#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# Cross-tool reconciliation test — Wave 3 keystone (AB#4633 child).
#
# Validates the S2D Cartographer waterfall engine against the SHARED
# golden-cluster fixture (tests/maproom/Fixtures/golden-clusters.json). An
# IDENTICAL copy of that fixture lives in the Surveyor repo, whose vitest
# suite (src/engine/__tests__/reconciliation.test.ts) asserts the same
# expected byte values from its TypeScript engine.
#
# The fixture is the contract: if this suite is green AND Surveyor's
# reconciliation.test.ts is green, the two tools agree on the canonical
# capacity model (docs/capacity-model.md) within ±2% — by construction.
#
# All fixture expectations are already in BYTES, Cartographer's native unit.

# ── Discovery-phase: load the shared fixture and project each cluster into a
#    flat hashtable so Describe -ForEach can expand the keys as variables. ──
$fixturePath = Join-Path $PSScriptRoot '..\Fixtures\golden-clusters.json'
$golden      = Get-Content -Raw -Path $fixturePath | ConvertFrom-Json
$tolPct      = [double]$golden.tolerancePct
$TB          = [double]$golden._meta.units.TB

$cases = foreach ($c in $golden.clusters) {
    $hw          = $c.hardware
    $driveBytes  = [int64]([double]$hw.capacityDriveSizeTB * $TB)
    # Infra pool FOOTPRINT derived from the shared primitives (logical size ×
    # resiliency divisor) — exactly how Surveyor derives it from infraVolumeSizeTB.
    $infraBytes  = [int64]([double]$hw.infraVolumeSizeTB * [double]$hw.resiliencyDivisor * $TB)
    @{
        Id          = $c.id
        Description = $c.description
        RawBytes    = [int64]($driveBytes * [int]$hw.capacityDrivesPerNode * [int]$hw.nodeCount)
        NodeCount   = [int]$hw.nodeCount
        LargestDisk = $driveBytes
        InfraBytes  = $infraBytes
        Divisor     = [double]$hw.resiliencyDivisor
        ExpRaw      = [int64]$c.expected.rawBytes
        ExpPool     = [int64]$c.expected.poolAfterMetaBytes
        ExpReserve  = [int64]$c.expected.reserveBytes
        ExpInfra    = [int64]$c.expected.infraFootprintBytes
        ExpAvail    = [int64]$c.expected.availableForVolumesBytes
        ExpUsable   = [int64]$c.expected.usableBytes
        TolPct      = $tolPct
    }
}

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    # Relative-percentage tolerance helper, shared by every assertion below.
    function Script:Test-WithinPct {
        param([double]$Actual, [double]$Expected, [double]$TolPct)
        if ($Expected -eq 0) { return [math]::Abs($Actual) -lt 1 }
        return ([math]::Abs($Actual - $Expected) / [math]::Abs($Expected)) -le ($TolPct / 100.0)
    }
}

Describe 'Cross-tool reconciliation — golden clusters (AB#4633)' -ForEach $cases {

    BeforeAll {
        # Run the pure waterfall inside the module and surface only the byte
        # values this suite reconciles. PoolTotalBytes=0 forces the ~1% pool
        # metadata estimate (raw × 0.99) — matching Surveyor's POOL_METADATA_FACTOR.
        $script:actual = InModuleScope S2DCartographer -Parameters @{
            RawBytes    = $RawBytes
            NodeCount   = $NodeCount
            LargestDisk = $LargestDisk
            InfraBytes  = $InfraBytes
            Divisor     = $Divisor
        } {
            param($RawBytes, $NodeCount, $LargestDisk, $InfraBytes, $Divisor)
            $wf = Invoke-S2DWaterfallCalculation `
                -RawDiskBytes         $RawBytes `
                -NodeCount            $NodeCount `
                -LargestDiskSizeBytes $LargestDisk `
                -PoolTotalBytes       ([int64]0) `
                -PoolFreeBytes        ([int64]0) `
                -InfraVolumeBytes     $InfraBytes `
                -ResiliencyFactor     $Divisor
            @{
                Raw     = [int64]$wf.Stages[0].Size.Bytes   # Stage 1 — raw physical
                Pool    = [int64]$wf.Stages[2].Size.Bytes   # Stage 3 — after pool metadata
                Reserve = [int64]($wf.Stages[2].Size.Bytes - $wf.Stages[3].Size.Bytes)  # Stage 3→4 delta
                Infra   = [int64]($wf.Stages[3].Size.Bytes - $wf.Stages[4].Size.Bytes)  # Stage 4→5 delta
                Avail   = [int64]$wf.AvailableForVolumes.Bytes  # Stage 6 — footprint available
                Usable  = [int64]$wf.UsableCapacity.Bytes       # Stage 7 — usable data (terminus)
            }
        }
    }

    It '<Id>: raw matches canonical' {
        Test-WithinPct $script:actual.Raw $ExpRaw $TolPct | Should -BeTrue
    }

    It '<Id>: pool-after-metadata matches canonical' {
        Test-WithinPct $script:actual.Pool $ExpPool $TolPct | Should -BeTrue
    }

    It '<Id>: reserve matches canonical' {
        Test-WithinPct $script:actual.Reserve $ExpReserve $TolPct | Should -BeTrue
    }

    It '<Id>: infrastructure-volume footprint matches canonical' {
        Test-WithinPct $script:actual.Infra $ExpInfra $TolPct | Should -BeTrue
    }

    It '<Id>: available-for-volumes (footprint) matches canonical' {
        Test-WithinPct $script:actual.Avail $ExpAvail $TolPct | Should -BeTrue
    }

    It '<Id>: usable (data) matches canonical' {
        Test-WithinPct $script:actual.Usable $ExpUsable $TolPct | Should -BeTrue
    }
}
