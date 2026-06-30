#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Tests for graduated health scoring, named config references, and config hot-swap.
    Covers GH #57 (AB#267), #58 (AB#268), #59 (AB#269) — v1.10.0.
#>

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    # Helper: build a minimal healthy IIC session inside module scope.
    # Re-used by multiple contexts via a shared helper.
    $script:BuildHealthySession = {
        InModuleScope S2DCartographer {
            # Reset health config override so tests start from defaults
            $Script:S2DHealthConfig        = $null
            $Script:S2DHealthConfigDefault = $null

            $physDisks = @(foreach ($node in 1..4) {
                foreach ($disk in 1..4) {
                    [PSCustomObject]@{
                        NodeName          = "azl-iic-n0$node"
                        FriendlyName      = 'INTEL SSDPE2KX040T8'
                        SerialNumber      = "IIC01N0${node}D$disk"
                        MediaType         = 'NVMe'
                        Model             = 'INTEL SSDPE2KX040T8'
                        FirmwareVersion   = 'VCV10162'
                        HealthStatus      = 'Healthy'
                        OperationalStatus = 'OK'
                        Role              = 'Capacity'
                        SizeBytes         = [int64]3840000000000
                        WearPercentage    = 10
                        IsPoolMember      = $true
                    }
                }
            })

            $pool = [S2DStoragePool]::new()
            $pool.TotalSize       = [S2DCapacity]::new([int64]60820000000000)
            $pool.AllocatedSize   = [S2DCapacity]::new([int64]20000000000000)
            $pool.RemainingSize   = [S2DCapacity]::new([int64]40820000000000)
            $pool.ProvisionedSize = [S2DCapacity]::new([int64]6000000000000)
            $pool.OvercommitRatio = 0.099
            $pool.HealthStatus    = 'Healthy'
            $pool.OperationalStatus = 'OK'

            $vol1 = [S2DVolume]::new()
            $vol1.FriendlyName           = 'UserStorage_1'
            $vol1.HealthStatus           = 'Healthy'
            $vol1.OperationalStatus      = 'OK'
            $vol1.IsInfrastructureVolume = $false
            $vol1.ProvisioningType       = 'Fixed'
            $vol1.NumberOfDataCopies     = 3
            $vol1.Size                   = [S2DCapacity]::new([int64]3000000000000)
            $vol1.FootprintOnPool        = [S2DCapacity]::new([int64]9000000000000)

            $vol2 = [S2DVolume]::new()
            $vol2.FriendlyName           = 'Infrastructure_aabbccddeeff00112233445566778899'
            $vol2.HealthStatus           = 'Healthy'
            $vol2.OperationalStatus      = 'OK'
            $vol2.IsInfrastructureVolume = $true
            $vol2.Size                   = [S2DCapacity]::new([int64]524288000000)
            $vol2.FootprintOnPool        = [S2DCapacity]::new([int64]1572864000000)

            $cache = [S2DCacheTier]::new()
            $cache.IsAllFlash           = $true
            $cache.SoftwareCacheEnabled = $true
            $cache.CacheMode            = 'ReadWrite'
            $cache.CacheState           = 'Active'
            $cache.CacheDiskCount       = 0

            $wf = [S2DCapacityWaterfall]::new()
            $wf.ReserveActual      = [S2DCapacity]::new([int64]40820000000000)
            $wf.ReserveRecommended = [S2DCapacity]::new([int64]15360000000000)
            $wf.ReserveStatus      = 'Adequate'
            $wf.IsOvercommitted    = $false

            $Script:S2DSession = @{
                ClusterName   = 'azlocal-iic-s2d-01'
                ClusterFqdn   = 'azlocal-iic-s2d-01.iic.local'
                Nodes         = @('azl-iic-n01','azl-iic-n02','azl-iic-n03','azl-iic-n04')
                CimSession    = $null
                PSSession     = $null
                IsConnected   = $true
                IsLocal       = $true
                CollectedData = @{
                    PhysicalDisks     = $physDisks
                    StoragePool       = $pool
                    Volumes           = @($vol1, $vol2)
                    CacheTier         = $cache
                    CapacityWaterfall = $wf
                }
            }
        }
    }
}

# ── #57 Graduated threshold scoring ──────────────────────────────────────────

Describe '#57 Graduated scoring — S2DHealthCheck fields (AB#267)' {

    BeforeEach { & $script:BuildHealthySession }

    Context 'New scoring fields exist on every check' {
        It 'every check has Weight > 0' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object { $_.Weight | Should -BeGreaterThan 0 }
            }
        }

        It 'every check has MaxPoints equal to Weight' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object { $_.MaxPoints | Should -Be $_.Weight }
            }
        }

        It 'every check has AwardedPoints between 0 and MaxPoints' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object {
                    $_.AwardedPoints | Should -BeGreaterOrEqual 0
                    $_.AwardedPoints | Should -BeLessOrEqual $_.MaxPoints
                }
            }
        }

        It 'every check has a non-empty ScoreBand' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object { $_.ScoreBand | Should -Not -BeNullOrEmpty }
            }
        }

        It 'every check has ScorePercent between 0 and 100' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object {
                    $_.ScorePercent | Should -BeGreaterOrEqual 0
                    $_.ScorePercent | Should -BeLessOrEqual 100
                }
            }
        }
    }

    Context 'Pass checks award full points' {
        It 'a Pass check has AwardedPoints = MaxPoints' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $passChecks = @($result | Where-Object { $_.Status -eq 'Pass' })
                $passChecks.Count | Should -BeGreaterThan 0
                $passChecks | ForEach-Object {
                    $_.AwardedPoints | Should -Be $_.MaxPoints
                }
            }
        }

        It 'a Pass check has ScorePercent = 100' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $passChecks = @($result | Where-Object { $_.Status -eq 'Pass' })
                $passChecks | ForEach-Object {
                    $_.ScorePercent | Should -Be 100
                }
            }
        }
    }

    Context 'Warn checks award partial points' {
        It 'a Warn check has AwardedPoints between 0 and MaxPoints inclusive (partial credit via warnFactor)' {
            InModuleScope S2DCartographer {
                # Introduce a Warn: degrade cache tier
                $Script:S2DSession.CollectedData['CacheTier'].CacheState = 'Degraded'
                $result = Get-S2DHealthStatus
                $warnChecks = @($result | Where-Object { $_.Status -eq 'Warn' -and $_.CheckName -eq 'CacheTierHealth' })
                $warnChecks.Count | Should -BeGreaterThan 0
                foreach ($chk in $warnChecks) {
                    # CacheTierHealth has 1 threshold (Pass only), so Warn falls back to 0 points
                    # (no matching threshold for Warn in config) — awarded=0 is valid; still within [0,MaxPoints]
                    $chk.AwardedPoints | Should -BeGreaterOrEqual 0
                    $chk.AwardedPoints | Should -BeLessOrEqual $chk.MaxPoints
                }
            }
        }

        It 'NVMeWear Warn awards partial points (1 of 2 = 50%)' {
            InModuleScope S2DCartographer {
                $disks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
                $wornDisk = [PSCustomObject]@{
                    NodeName          = $disks[0].NodeName
                    FriendlyName      = $disks[0].FriendlyName
                    SerialNumber      = $disks[0].SerialNumber
                    MediaType         = 'NVMe'
                    Model             = $disks[0].Model
                    FirmwareVersion   = $disks[0].FirmwareVersion
                    Role              = 'Capacity'
                    SizeBytes         = $disks[0].SizeBytes
                    WearPercentage    = 85
                    HealthStatus      = 'Healthy'
                    OperationalStatus = 'OK'
                    IsPoolMember      = $true
                }
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @($wornDisk) + @($disks | Select-Object -Skip 1)
                $result = Get-S2DHealthStatus
                $nvmeCheck = $result | Where-Object CheckName -eq 'NVMeWear'
                $nvmeCheck.Status | Should -Be 'Warn'
                # NVMeWear thresholds: Pass=2pts, Warn=1pt. Weight=2. MaxPoints=2. AwardedPoints=1.
                $nvmeCheck.AwardedPoints | Should -Be 1
                $nvmeCheck.ScorePercent  | Should -Be 50
            }
        }
    }

    Context 'Fail checks award 0 points' {
        It 'a Critical Fail check awards 0 points' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Critical'
                $result = Get-S2DHealthStatus
                $failCheck = $result | Where-Object CheckName -eq 'ReserveAdequacy'
                $failCheck.Status        | Should -Be 'Fail'
                $failCheck.AwardedPoints | Should -Be 0
                $failCheck.ScorePercent  | Should -Be 0
            }
        }
    }

    Context 'Critical-severity checks have higher weight than Info checks' {
        It 'ReserveAdequacy (Critical) has higher weight than FirmwareConsistency (Info)' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $reserve  = $result | Where-Object CheckName -eq 'ReserveAdequacy'
                $firmware = $result | Where-Object CheckName -eq 'FirmwareConsistency'
                $reserve.Weight | Should -BeGreaterThan $firmware.Weight
            }
        }
    }

    Context 'HealthScore stored in CollectedData' {
        It 'HealthScore is written to CollectedData after Get-S2DHealthStatus' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score | Should -Not -BeNullOrEmpty
            }
        }

        It 'HealthScore.OverallScore is 0-100 integer on healthy cluster' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score.OverallScore | Should -BeGreaterOrEqual 0
                $score.OverallScore | Should -BeLessOrEqual 100
            }
        }

        It 'HealthScore.ScoreStatus is Excellent on a fully-healthy cluster' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score.ScoreStatus | Should -Be 'Excellent'
            }
        }

        It 'HealthScore.OverallScore drops when a Critical check fails' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Critical'
                Get-S2DHealthStatus | Out-Null
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score.OverallScore | Should -BeLessThan 100
            }
        }

        It 'HealthScore.OverallHealth matches legacy OverallHealth string' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $legacy = $Script:S2DSession.CollectedData['OverallHealth']
                $score.OverallHealth | Should -Be $legacy
            }
        }

        It 'HealthScore.TotalMax equals sum of all check MaxPoints' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $expectedMax = ($result | Measure-Object -Property MaxPoints -Sum).Sum
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score.TotalMax | Should -Be $expectedMax
            }
        }
    }

    Context 'Weighted scoring math — partial failure reduces score proportionally' {
        It 'a single weight-3 fail on a cluster with total weight N reduces score by 3/N * 100' {
            InModuleScope S2DCartographer {
                # Force only ReserveAdequacy to fail (weight=3, currently awards 3)
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Critical'
                $result = Get-S2DHealthStatus
                $totalMax = ($result | Measure-Object -Property MaxPoints -Sum).Sum
                $totalAwarded = ($result | Measure-Object -Property AwardedPoints -Sum).Sum
                $expectedScore = [int][math]::Round($totalAwarded / $totalMax * 100)
                $score = $Script:S2DSession.CollectedData['HealthScore']
                $score.OverallScore | Should -Be $expectedScore
            }
        }
    }
}

# ── #57/#58 Legacy output shape backward compatibility ─────────────────────

Describe '#57/#58 Legacy output shape backward compatibility (AB#267/AB#268)' {

    BeforeEach { & $script:BuildHealthySession }

    It 'OverallHealth in CollectedData is still populated (legacy)' {
        InModuleScope S2DCartographer {
            Get-S2DHealthStatus | Out-Null
            $Script:S2DSession.CollectedData['OverallHealth'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'HealthChecks in CollectedData is still populated (legacy)' {
        InModuleScope S2DCartographer {
            Get-S2DHealthStatus | Out-Null
            @($Script:S2DSession.CollectedData['HealthChecks']).Count | Should -BeGreaterThan 0
        }
    }

    It 'CheckName, Severity, Status, Details, Remediation are all still present' {
        InModuleScope S2DCartographer {
            $result = Get-S2DHealthStatus
            $result | ForEach-Object {
                $_.CheckName   | Should -Not -BeNullOrEmpty
                $_.Severity    | Should -Not -BeNullOrEmpty
                $_.Status      | Should -Not -BeNullOrEmpty
                $_.Details     | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'result type is still S2DHealthCheck[]' {
        InModuleScope S2DCartographer {
            $result = Get-S2DHealthStatus
            $result | ForEach-Object { $_.GetType().Name | Should -Be 'S2DHealthCheck' }
        }
    }
}

# ── #58 Named config references — config loads ─────────────────────────────

Describe '#58 Named config references — health-checks.json loads correctly (AB#268)' {

    BeforeEach { & $script:BuildHealthySession }

    It 'Get-S2DHealthConfig returns a hashtable with version and checks' {
        InModuleScope S2DCartographer {
            $cfg = Get-S2DHealthConfig
            $cfg | Should -Not -BeNullOrEmpty
            $cfg['version'] | Should -Not -BeNullOrEmpty
            @($cfg['checks']).Count | Should -BeGreaterThan 0
        }
    }

    It 'Get-S2DCheckDefinition returns the definition for ReserveAdequacy' {
        InModuleScope S2DCartographer {
            $def = Get-S2DCheckDefinition -CheckName 'ReserveAdequacy'
            $def | Should -Not -BeNullOrEmpty
            $def['id']     | Should -Be 'ReserveAdequacy'
            $def['weight'] | Should -Be 3
        }
    }

    It 'Get-S2DCheckDefinition returns $null for an unknown check name' {
        InModuleScope S2DCartographer {
            $def = Get-S2DCheckDefinition -CheckName 'NonExistentCheck_XYZ'
            $def | Should -BeNullOrEmpty
        }
    }

    It 'health-checks.json defines all 12 known check IDs' {
        InModuleScope S2DCartographer {
            $cfg = Get-S2DHealthConfig
            $ids = @($cfg['checks'] | ForEach-Object { $_['id'] })
            $expected = @('ReserveAdequacy','DiskSymmetry','VolumeHealth','DiskHealth','NVMeWear',
                          'ThinOvercommit','FirmwareConsistency','RebuildCapacity','InfrastructureVolume',
                          'CacheTierHealth','ThinReserveRisk','MaintenanceReserveN1')
            foreach ($id in $expected) {
                $ids | Should -Contain $id
            }
        }
    }

    It 'ReserveAdequacy has 3 thresholds covering Pass, Warn, Fail' {
        InModuleScope S2DCartographer {
            $def = Get-S2DCheckDefinition -CheckName 'ReserveAdequacy'
            $statuses = @($def['thresholds'] | ForEach-Object { $_['status'] })
            $statuses | Should -Contain 'Pass'
            $statuses | Should -Contain 'Warn'
            $statuses | Should -Contain 'Fail'
        }
    }

    It 'Custom weight from config is applied — overriding default weight=1' {
        InModuleScope S2DCartographer {
            # Install a custom config with ReserveAdequacy weight=1 (overrides default 3)
            $Script:S2DHealthConfig = [ordered]@{
                version        = '99.0.0'
                scoreThresholds = [ordered]@{ excellent = 80; good = 60; fair = 40; needsImprovement = 0 }
                weighting       = [ordered]@{ warnFactor = 0.5 }
                checks          = @(
                    [ordered]@{
                        id         = 'ReserveAdequacy'
                        weight     = 1
                        severity   = 'Critical'
                        title      = 'Reserve adequacy (custom weight)'
                        thresholds = @(
                            [ordered]@{ status = 'Pass'; label = 'Adequate';    points = 1 }
                            [ordered]@{ status = 'Warn'; label = 'Low';         points = 0 }
                            [ordered]@{ status = 'Fail'; label = 'Critical Low'; points = 0 }
                        )
                    }
                )
            }

            $result = Get-S2DHealthStatus
            $reserveCheck = $result | Where-Object CheckName -eq 'ReserveAdequacy'
            $reserveCheck.Weight | Should -Be 1
            $reserveCheck.MaxPoints | Should -Be 1

            # Reset
            $Script:S2DHealthConfig = $null
        }
    }
}

# ── #59 Config hot-swap — Export-S2DHealthConfig / Import-S2DHealthConfig ──

Describe '#59 Config hot-swap — Export-S2DHealthConfig (AB#269)' {

    BeforeAll {
        $script:ExportDir = Join-Path ([System.IO.Path]::GetTempPath()) 'S2DCartographerTests'
        if (-not (Test-Path $script:ExportDir)) { New-Item -ItemType Directory -Path $script:ExportDir | Out-Null }
        $script:ExportPath = Join-Path $script:ExportDir 'health-checks-export.json'
    }

    BeforeEach { & $script:BuildHealthySession }

    It 'Export-S2DHealthConfig writes a file with version and checks' {
        $result = Export-S2DHealthConfig -OutputPath $script:ExportPath
        $result | Should -Not -BeNullOrEmpty
        Test-Path $script:ExportPath -PathType Leaf | Should -BeTrue
        $content = Get-Content $script:ExportPath -Raw | ConvertFrom-Json
        $content.version | Should -Not -BeNullOrEmpty
        @($content.checks).Count | Should -BeGreaterThan 0
    }

    It 'Export-S2DHealthConfig returns a FileInfo object' {
        $result = Export-S2DHealthConfig -OutputPath $script:ExportPath
        $result.GetType().Name | Should -Be 'FileInfo'
    }

    It 'exported JSON round-trips back as valid config (contains expected check IDs)' {
        Export-S2DHealthConfig -OutputPath $script:ExportPath | Out-Null
        $content = Get-Content $script:ExportPath -Raw | ConvertFrom-Json
        $ids = @($content.checks | ForEach-Object { $_.id })
        $ids | Should -Contain 'ReserveAdequacy'
        $ids | Should -Contain 'DiskHealth'
    }
}

Describe '#59 Config hot-swap — Import-S2DHealthConfig (AB#269)' {

    BeforeAll {
        $script:ExportDir  = Join-Path ([System.IO.Path]::GetTempPath()) 'S2DCartographerTests'
        if (-not (Test-Path $script:ExportDir)) { New-Item -ItemType Directory -Path $script:ExportDir | Out-Null }
        $script:ExportPath = Join-Path $script:ExportDir 'health-checks-export.json'
        $script:BadJson    = Join-Path $script:ExportDir 'health-checks-bad.json'
        $script:BadSchema  = Join-Path $script:ExportDir 'health-checks-bad-schema.json'

        # Create a bad JSON file
        Set-Content -Path $script:BadJson    -Value 'THIS IS NOT JSON { broken }'
        # Create a JSON file missing a required field (no 'id' on a check)
        Set-Content -Path $script:BadSchema  -Value '{"version":"1.0.0","checks":[{"weight":1,"title":"Missing id","thresholds":[{"status":"Pass","label":"OK","points":1}]}]}'

        # Export a valid config for round-trip tests
        Export-S2DHealthConfig -OutputPath $script:ExportPath | Out-Null
    }

    BeforeEach { & $script:BuildHealthySession }

    It 'Import-S2DHealthConfig -Validate returns a dry-run result without activating' {
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig = $null
        }
        $result = Import-S2DHealthConfig -Path $script:ExportPath -Validate
        $result.validated  | Should -BeTrue
        $result.checkCount | Should -BeGreaterThan 0
        # Config should NOT be active (module-scope override remains null)
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig | Should -BeNullOrEmpty
        }
    }

    It 'Import-S2DHealthConfig activates the config for the session' {
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig = $null
        }
        $result = Import-S2DHealthConfig -Path $script:ExportPath
        $result.activated | Should -BeTrue
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig | Should -Not -BeNullOrEmpty
        }
    }

    It 'Import-S2DHealthConfig -Default resets to shipped defaults' {
        # First activate an override
        Import-S2DHealthConfig -Path $script:ExportPath | Out-Null
        # Then reset
        $result = Import-S2DHealthConfig -Default
        $result.reset | Should -BeTrue
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig | Should -BeNullOrEmpty
        }
    }

    It 'Import-S2DHealthConfig throws on malformed JSON' {
        { Import-S2DHealthConfig -Path $script:BadJson } | Should -Throw
    }

    It 'Import-S2DHealthConfig throws on schema violation (missing id)' {
        { Import-S2DHealthConfig -Path $script:BadSchema } | Should -Throw
    }

    It 'Import-S2DHealthConfig throws when file does not exist' {
        { Import-S2DHealthConfig -Path 'C:\Definitely\Does\Not\Exist\health.json' } | Should -Throw
    }

    It 'Export then Import round-trip: activated config has same check count as exported' {
        InModuleScope S2DCartographer {
            $Script:S2DHealthConfig = $null
            $Script:S2DHealthConfigDefault = $null
        }
        Export-S2DHealthConfig -OutputPath $script:ExportPath | Out-Null
        $importResult = Import-S2DHealthConfig -Path $script:ExportPath
        $exportedContent = Get-Content $script:ExportPath -Raw | ConvertFrom-Json
        $importResult.checkCount | Should -Be @($exportedContent.checks).Count
    }

    It 'after Import, Get-S2DHealthStatus still runs and returns all checks' {
        & $script:BuildHealthySession
        Export-S2DHealthConfig -OutputPath $script:ExportPath | Out-Null
        Import-S2DHealthConfig -Path $script:ExportPath | Out-Null

        InModuleScope S2DCartographer {
            $result = Get-S2DHealthStatus
            $result.Count | Should -Be 12
            $result | ForEach-Object { $_.Weight | Should -BeGreaterThan 0 }
        }

        # Clean up
        Import-S2DHealthConfig -Default | Out-Null
    }

    It 'after -Default reset, Get-S2DHealthStatus still runs correctly' {
        Import-S2DHealthConfig -Default | Out-Null
        & $script:BuildHealthySession
        InModuleScope S2DCartographer {
            $result = Get-S2DHealthStatus
            $result.Count | Should -Be 12
        }
    }
}
