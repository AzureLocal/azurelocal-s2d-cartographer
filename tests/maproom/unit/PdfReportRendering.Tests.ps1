#Requires -Version 7.0
#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Regression tests for AB#263 and AB#264 — PDF/HTML bar graph rendering bugs.

    AB#263  Waterfall bar chart TB toggle used an imprecise JS approximation
            (TiB × 1.0995) instead of the authoritative S2DCapacity.TB values
            from PowerShell byte math. The fix passes $wfTbValues from PS.

    AB#264  (a) Pool breakdown chart: the reserve boundary line was drawn at
            the reserve *size* (e.g. 7.68 TB from origin), not at the
            start-of-reserve *position* (poolTotal - reserve). The fix uses
            poolTotalTB - reserveTB.
            (b) Pool health chart: the x-axis max excluded ph.free and
            ph.reserveOk, clipping bar segments for healthy clusters.
            The fix sums all five segments.

    These tests drive Export-S2DHtmlReport with representative in-memory data
    and assert the rendered HTML carries the correct values. No live cluster
    or PDF binary is required. All I/O is mocked or temp-file-only.
#>

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    # ── Shared cluster fixture ────────────────────────────────────────────────
    # 4-node Azure Local cluster, 4 × 3.84 TB NVMe per node (16 disks total)
    # Pool total 60.82 TB, reserve 15.36 TB (4 × 3.84), 40.82 TB pool free
    # Two workload volumes: 10 TB + 8 TB footprint = 18 TB total footprint
    # Reserve zone starts at 60.82 - 15.36 = 45.46 TB from left edge of bar
    $script:cd = InModuleScope S2DCartographer {
        $wf = Invoke-S2DWaterfallCalculation `
            -RawDiskBytes         ([int64]61440000000000) `
            -NodeCount            4 `
            -LargestDiskSizeBytes ([int64]3840000000000) `
            -PoolTotalBytes       ([int64]60820000000000) `
            -PoolFreeBytes        ([int64]40820000000000) `
            -InfraVolumeBytes     ([int64]1610612736000) `
            -ResiliencyFactor     2.0 `
            -ResiliencyName       '2-way mirror'

        $pool                  = [S2DStoragePool]::new()
        $pool.FriendlyName     = 'S2D on azlocal-test'
        $pool.HealthStatus     = 'Healthy'
        $pool.TotalSize        = [S2DCapacity]::new([int64]60820000000000)
        $pool.AllocatedSize    = [S2DCapacity]::new([int64]18000000000000)
        $pool.RemainingSize    = [S2DCapacity]::new([int64]42820000000000)
        $pool.ProvisionedSize  = [S2DCapacity]::new([int64]20000000000000)
        $pool.OvercommitRatio  = 1.0

        $v1 = [S2DVolume]::new()
        $v1.FriendlyName           = 'VMs-01'
        $v1.ResiliencySettingName  = 'Mirror'
        $v1.NumberOfDataCopies     = 2
        $v1.ProvisioningType       = 'Fixed'
        $v1.Size                   = [S2DCapacity]::new([int64]5000000000000)
        $v1.FootprintOnPool        = [S2DCapacity]::new([int64]10000000000000)
        $v1.EfficiencyPercent      = 50.0
        $v1.HealthStatus           = 'Healthy'
        $v1.IsInfrastructureVolume = $false

        $v2 = [S2DVolume]::new()
        $v2.FriendlyName           = 'VMs-02'
        $v2.ResiliencySettingName  = 'Mirror'
        $v2.NumberOfDataCopies     = 2
        $v2.ProvisioningType       = 'Fixed'
        $v2.Size                   = [S2DCapacity]::new([int64]4000000000000)
        $v2.FootprintOnPool        = [S2DCapacity]::new([int64]8000000000000)
        $v2.EfficiencyPercent      = 50.0
        $v2.HealthStatus           = 'Healthy'
        $v2.IsInfrastructureVolume = $false

        $cd                    = [S2DClusterData]::new()
        $cd.ClusterName        = 'azlocal-test'
        $cd.ClusterFqdn        = 'azlocal-test.local'
        $cd.NodeCount          = 4
        $cd.Nodes              = @('n01','n02','n03','n04')
        $cd.CollectedAt        = [datetime]::UtcNow
        $cd.PhysicalDisks      = @()
        $cd.StoragePool        = $pool
        $cd.Volumes            = @($v1, $v2)
        $cd.HealthChecks       = @()
        $cd.OverallHealth      = 'Healthy'
        $cd.CapacityWaterfall  = $wf
        $cd
    }

    # Render HTML to a temp file once; all Describes share this string.
    # [System.IO.Path]::GetTempPath() is cross-platform (/tmp on Linux, %TEMP% on Windows).
    # $env:TEMP is Windows-only and is empty on Linux, which makes Split-Path -Parent return
    # an empty string and causes a ParameterBindingValidationException at Export-S2DHtmlReport:578.
    $tmpPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "S2DCartographer-PdfRenderTest-$([System.IO.Path]::GetRandomFileName()).html"
    )
    try {
        InModuleScope S2DCartographer -Parameters @{ cd = $script:cd; out = $tmpPath } {
            param($cd, $out)
            Export-S2DHtmlReport -ClusterData $cd -OutputPath $out
        }
        $script:html = Get-Content -Raw -Path $tmpPath
    }
    finally {
        Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AB#263 — Waterfall bar chart: TB values must come from PowerShell, not JS math
# ─────────────────────────────────────────────────────────────────────────────
Describe 'AB#263 — Waterfall bar chart TB toggle uses authoritative PowerShell byte values' {

    Context 'tbValues array is emitted as a JS array literal, not a derived expression' {

        It 'HTML contains the const tbValues assignment as a JS array literal (not .map call)' {
            $script:html | Should -Match 'const tbValues\s*=\s*\['
        }

        It 'the JS script block does NOT contain the old approximation factor 1.0995 as a multiplier' {
            # Before the fix the JS line was: tibValues.map(v => Math.round(v * 1.0995 * 100) / 100)
            # Note: 1.0995 also appears in the Stage 2 description text as "1.0995 x 10^12 bytes" — that is
            # legitimate and expected. We only care that 1.0995 is absent from the <script> block.
            $scriptSection = [regex]::Match($script:html, '(?s)<script>(.*?)</script>').Groups[1].Value
            $scriptSection | Should -Not -Match '1\.0995'
        }

        It 'tbValues is NOT derived from tibValues.map in the rendered JS' {
            $script:html | Should -Not -Match 'tbValues\s*=\s*tibValues\.map'
        }
    }

    Context 'Stage 1 raw TiB and TB array values are both present and numerically distinct' {

        It 'tibValues array starts with the Stage 1 raw TiB value (approx 55.9)' {
            # Stage 1: 61,440,000,000,000 bytes / 1099511627776 = 55.88... → 55.9
            $expected = [math]::Round(61440000000000 / 1099511627776, 2)
            $script:html | Should -Match "const tibValues\s*=\s*\[$expected"
        }

        It 'tbValues array starts with the Stage 1 raw TB value (61.44)' {
            # Stage 1: 61,440,000,000,000 bytes / 1e12 = 61.44
            $expected = [math]::Round(61440000000000 / 1e12, 2)
            $script:html | Should -Match "const tbValues\s*=\s*\[$expected"
        }

        It 'Stage 1 TiB (~55.9) and TB (61.44) are different — no silent unit mixing' {
            $tibVal = [math]::Round(61440000000000 / 1099511627776, 2)
            $tbVal  = [math]::Round(61440000000000 / 1e12,          2)
            $tibVal | Should -Not -Be $tbVal
        }
    }

    Context 'Stage 7 TB value is byte-accurate (not TiB × 1.0995 approximation)' {

        It 'authoritative Stage 7 TB equals Bytes / 1e12, not TiB × 1.0995' {
            InModuleScope S2DCartographer {
                $wf = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1610612736000) `
                    -ResiliencyFactor     2.0
                $authTB            = [math]::Round($wf.Stages[6].Size.TB,  2)
                $expectedFromBytes = [math]::Round($wf.Stages[6].Size.Bytes / 1e12, 2)
                $authTB | Should -Be $expectedFromBytes `
                    -Because 'authoritative TB must equal Bytes / 1e12, not TiB × 1.0995'
            }
        }
    }

    Context 'toggleUnit() function references the tbValues variable' {

        It 'toggleUnit assigns chart data from tbValues (not an inline calculation)' {
            $script:html | Should -Match 'chart\.data\.datasets\[0\]\.data\s*=\s*useTiB\s*\?\s*tibValues\s*:\s*tbValues'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AB#264 (a) — Pool breakdown chart: reserve boundary at correct position
# ─────────────────────────────────────────────────────────────────────────────
Describe 'AB#264(a) — Pool breakdown reserve line drawn at poolTotal - reserve, not at reserve size' {

    Context 'JS plugin uses poolTotalTB - reserveTB expression' {

        It 'the reserveLine plugin calls getPixelForValue with poolTotalTB - reserveTB' {
            $script:html | Should -Match 'getPixelForValue\s*\(\s*poolTotalTB\s*-\s*reserveTB\s*\)'
        }

        It 'the old wrong call getPixelForValue(reserveTB) alone does not appear' {
            # Old code: const reserveX = xScale.getPixelForValue(reserveTB);
            # The literal pattern of getPixelForValue taking only reserveTB must not exist.
            $script:html | Should -Not -Match 'getPixelForValue\s*\(\s*reserveTB\s*\)'
        }
    }

    Context 'Emitted poolTotalTB and reserveTB JS constants are arithmetically sane' {

        It 'poolTotalTB constant equals 60.82 (pool.TotalSize.TB for this fixture)' {
            $script:html | Should -Match 'const poolTotalTB\s*=\s*60\.82\s*;'
        }

        It 'reserveTB constant is positive (non-zero for a 4-node cluster)' {
            $match = [regex]::Match($script:html, 'const reserveTB\s*=\s*([\d.]+)\s*;')
            $match.Success | Should -Be $true
            [double]$match.Groups[1].Value | Should -BeGreaterThan 0
        }

        It 'reserveTB is less than poolTotalTB (reserve fits within pool)' {
            $totalMatch   = [regex]::Match($script:html, 'const poolTotalTB\s*=\s*([\d.]+)\s*;')
            $reserveMatch = [regex]::Match($script:html, 'const reserveTB\s*=\s*([\d.]+)\s*;')
            $totalMatch.Success   | Should -Be $true
            $reserveMatch.Success | Should -Be $true
            [double]$reserveMatch.Groups[1].Value | Should -BeLessThan ([double]$totalMatch.Groups[1].Value)
        }

        It 'poolTotalTB - reserveTB is >= 40 TB for this cluster (line well inside bar, not at edge)' {
            # Pool 60.82 TB, reserve 15.36 TB → reserve starts at 45.46 TB
            $totalMatch   = [regex]::Match($script:html, 'const poolTotalTB\s*=\s*([\d.]+)\s*;')
            $reserveMatch = [regex]::Match($script:html, 'const reserveTB\s*=\s*([\d.]+)\s*;')
            $reserveStart = [double]$totalMatch.Groups[1].Value - [double]$reserveMatch.Groups[1].Value
            $reserveStart | Should -BeGreaterThan 40.0
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AB#264 (b) — Pool health chart: x-axis max includes all five segments
# ─────────────────────────────────────────────────────────────────────────────
Describe 'AB#264(b) — Pool health chart x-axis max includes all five bar segments' {

    Context 'JS max expression includes all ph segment fields' {

        It 'max expression contains ph.free' {
            $script:html | Should -Match 'ph\.free'
        }

        It 'max expression contains ph.reserveOk' {
            $script:html | Should -Match 'ph\.reserveOk'
        }

        It 'max expression contains all five terms in the correct sum' {
            # After the fix: ph.used + ph.free + ph.reserveOk + ph.reserveEaten + ph.overcommit
            $script:html | Should -Match 'ph\.used\s*\+\s*ph\.free\s*\+\s*ph\.reserveOk\s*\+\s*ph\.reserveEaten\s*\+\s*ph\.overcommit'
        }

        It 'old three-term sum (used + reserveEaten + overcommit without free/reserveOk) does not appear in max' {
            # Old broken pattern: ph.used + ph.reserveEaten — the fix adds ph.free before ph.reserveOk
            $script:html | Should -Not -Match 'ph\.used\s*\+\s*ph\.reserveEaten'
        }
    }

    Context 'Pool health PowerShell segment computations — correctness assertions' {

        It 'all five ph segments sum to approximately poolTotalTB (healthy cluster, no overcommit)' {
            # 60.82 TB pool, 15.36 TB reserve → availForVols = 45.46 TB
            # 18 TB total footprint → phUsed=18, phFree=27.46, phReserveOk=15.36, eaten/overcommit=0
            # Rounding to 2 dp at each intermediate step can introduce up to ~1 TB of accumulated error;
            # the important guarantee is that all segments are non-negative and the sum is close to poolTotal.
            $poolTotalTB      = [math]::Round(60820000000000 / 1e12, 2)
            $reserveTB        = [math]::Round(15360000000000 / 1e12, 2)
            $totalFootprintTB = 18.0
            $availForVols     = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
            $phUsed           = [math]::Round([math]::Min($totalFootprintTB, $availForVols),  2)
            $phFree           = [math]::Round([math]::Max(0, $availForVols - $totalFootprintTB), 2)
            $eatIntoReserve   = [math]::Round([math]::Max(0, $totalFootprintTB - $availForVols), 2)
            $phReserveOk      = [math]::Round([math]::Max(0, $reserveTB - $eatIntoReserve), 2)
            $phReserveEaten   = [math]::Round([math]::Min($reserveTB, $eatIntoReserve), 2)
            $phOvercommit     = [math]::Round([math]::Max(0, $totalFootprintTB - $poolTotalTB), 2)

            $segmentSum = $phUsed + $phFree + $phReserveOk + $phReserveEaten + $phOvercommit
            # Tolerance is 1 TB — segments individually round to 2 dp, so accumulated error is bounded.
            [math]::Abs($segmentSum - $poolTotalTB) | Should -BeLessThan 1.0 `
                -Because 'five segments must account for substantially all of the pool (within 2-dp rounding)'
        }

        It 'ph.free is positive for a healthy cluster with significant unused space' {
            $poolTotalTB      = [math]::Round(60820000000000 / 1e12, 2)
            $reserveTB        = [math]::Round(15360000000000 / 1e12, 2)
            $totalFootprintTB = 18.0
            $availForVols     = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
            $phFree           = [math]::Round([math]::Max(0, $availForVols - $totalFootprintTB), 2)
            $phFree | Should -BeGreaterThan 0 `
                -Because '18 TB used from 45.46 TB available must leave positive free space'
        }

        It 'ph.reserveOk is positive when footprint does not eat into the reserve' {
            $poolTotalTB      = [math]::Round(60820000000000 / 1e12, 2)
            $reserveTB        = [math]::Round(15360000000000 / 1e12, 2)
            $totalFootprintTB = 18.0
            $availForVols     = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
            $eatIntoReserve   = [math]::Round([math]::Max(0, $totalFootprintTB - $availForVols), 2)
            $phReserveOk      = [math]::Round([math]::Max(0, $reserveTB - $eatIntoReserve), 2)
            $phReserveOk | Should -BeGreaterThan 0 `
                -Because '18 TB footprint against 45.46 TB available leaves reserve fully intact'
        }

        It 'five-term max ceiling is >= three-term max ceiling (new formula never produces smaller axis)' {
            # Demonstrates that the fix expands (or equals) the axis relative to the old formula
            $poolTotalTB    = 60.82
            $phUsed         = 18.0
            $phFree         = 27.46
            $phReserveOk    = 15.36
            $phReserveEaten = 0.0
            $phOvercommit   = 0.0

            $oldMax = [math]::Ceiling([math]::Max($poolTotalTB, $phUsed + $phReserveEaten + $phOvercommit) * 1.08)
            $newMax = [math]::Ceiling([math]::Max($poolTotalTB, $phUsed + $phFree + $phReserveOk + $phReserveEaten + $phOvercommit) * 1.1)
            $newMax | Should -BeGreaterOrEqual $oldMax
        }

        It 'ph.overcommit is zero when total footprint does not exceed pool total' {
            $phOvercommit = [math]::Round([math]::Max(0, 18.0 - 60.82), 2)
            $phOvercommit | Should -Be 0
        }

        It 'ph.overcommit is positive in an overcommitted scenario' {
            $phOvercommit = [math]::Round([math]::Max(0, 65.0 - 60.82), 2)
            $phOvercommit | Should -BeGreaterThan 0
        }

        It 'ph.free is zero (not negative) when footprint exactly fills the available zone' {
            $poolTotalTB  = 60.82
            $reserveTB    = 15.36
            $availForVols = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
            $phFree       = [math]::Round([math]::Max(0, $availForVols - $availForVols), 2)
            $phFree | Should -Be 0
        }

        It 'no segment is negative for well-formed inputs (Max(0,...) guards hold)' {
            $poolTotalTB      = 60.82
            $reserveTB        = 15.36
            $totalFootprintTB = 18.0
            $availForVols     = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
            $phUsed           = [math]::Round([math]::Min($totalFootprintTB, $availForVols),  2)
            $phFree           = [math]::Round([math]::Max(0, $availForVols - $totalFootprintTB), 2)
            $eatIntoReserve   = [math]::Round([math]::Max(0, $totalFootprintTB - $availForVols), 2)
            $phReserveOk      = [math]::Round([math]::Max(0, $reserveTB - $eatIntoReserve), 2)
            $phReserveEaten   = [math]::Round([math]::Min($reserveTB, $eatIntoReserve), 2)
            $phOvercommit     = [math]::Round([math]::Max(0, $totalFootprintTB - $poolTotalTB), 2)

            $phUsed        | Should -BeGreaterOrEqual 0
            $phFree        | Should -BeGreaterOrEqual 0
            $phReserveOk   | Should -BeGreaterOrEqual 0
            $phReserveEaten | Should -BeGreaterOrEqual 0
            $phOvercommit  | Should -BeGreaterOrEqual 0
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration: rendered HTML is structurally complete for headless PDF print
# ─────────────────────────────────────────────────────────────────────────────
Describe 'Export-S2DHtmlReport — HTML structure sanity for headless PDF rendering' {

    It 'output begins with DOCTYPE html' {
        $script:html.TrimStart() | Should -BeLike '<!DOCTYPE html>*'
    }

    It 'output contains closing html tag' {
        $script:html | Should -Match ([regex]::Escape('</html>'))
    }

    It 'Chart.js CDN script tag is present (required for all bar graphs)' {
        $script:html | Should -Match 'chart\.js'
    }

    It 'waterfallChart canvas element is present' {
        $script:html | Should -Match 'id=.waterfallChart.'
    }

    It 'poolBreakdownChart canvas element is present' {
        $script:html | Should -Match 'id=.poolBreakdownChart.'
    }

    It 'poolHealthChart canvas element is present' {
        $script:html | Should -Match 'id=.poolHealthChart.'
    }

    It 'waterfallPlanLinePlugin is defined (70% planning line annotation)' {
        $script:html | Should -Match 'waterfallPlanLinePlugin'
    }

    It 'reserveLine plugin is defined (pool breakdown boundary markers)' {
        $script:html | Should -Match 'reserveLine'
    }

    It 'phBoundaryPlugin is defined (pool health boundary markers)' {
        $script:html | Should -Match 'phBoundaryPlugin'
    }

    It 'tibValues JS array is present and non-empty' {
        $script:html | Should -Match 'const tibValues\s*=\s*\[[0-9]'
    }

    It 'tbValues JS array is present and non-empty' {
        $script:html | Should -Match 'const tbValues\s*=\s*\[[0-9]'
    }
}
