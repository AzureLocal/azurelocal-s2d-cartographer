#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
    Capacity contract test: S2D Cartographer vs Surveyor.

    The reference function below re-implements the canonical pipeline from Surveyor
    src/engine/capacity.ts (computeCapacity) in decimal TB:

      raw      = driveTB x drivesPerNode x nodes
      pool     = raw x 0.99
      reserve  = min(nodes, 4) x largest raw drive
      infraFP  = infraVolumeSizeTB / resiliencyFactor
      avail    = max(0, pool - reserve - infraFP)
      usable   = avail x resiliencyFactor

    Learn (windows-server/storage/storage-spaces/plan-volumes) grounds the reserve rule
    (one capacity drive per server, up to 4) and the footprint/size split; Learn
    (azure-local/concepts/rack-aware-cluster-requirements) grounds rack aware = two-way
    mirror for 1+1 and four-way mirror for 2+2 and larger.

    Documented, justified differences (asserted below so they cannot drift silently):
      1. The old 0.92 per-drive "efficiency" is NOT applied by either tool. It was a blended
         constant that double counted the TB->TiB conversion (about 0.9095); both tools now
         keep raw bytes and convert units once, at display.
      2. Cartographer takes a data-copies divisor (footprint / copies = usable); Surveyor uses
         an efficiency multiplier. They are reciprocals: copies = 1 / factor.
      3. Cartographer reads the live infrastructure-volume FOOTPRINT; Surveyor models it as
         infraVolumeSizeTB / factor. The test feeds Cartographer the Surveyor footprint.
      4. Surveyor expansion headroom treats dual parity as 2 copies; Cartographer derives the
         divisor from the real efficiency. Not part of the waterfall contract (documented only).
#>
BeforeDiscovery {
    $fx = Get-Content -Raw (Join-Path $PSScriptRoot '..\Fixtures\surveyor-contract-cases.json') | ConvertFrom-Json
    $script:Cases = @($fx.cases | ForEach-Object { @{ Case = $_; Name = $_.name } })
}

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
    $script:Fixture = Get-Content -Raw (Join-Path $PSScriptRoot '..\Fixtures\surveyor-contract-cases.json') | ConvertFrom-Json

    function script:Get-SurveyorFactor {
        param([string] $Resiliency, [int] $Nodes, [bool] $Hybrid)
        switch ($Resiliency) {
            'two-way-mirror'   { 0.5 }
            'three-way-mirror' { 1.0 / 3.0 }
            'nested-two-way'   { 0.25 }
            'four-way-mirror'  { 0.25 }
            'dual-parity' {
                if ($Nodes -le 6) { 0.5 }
                elseif ($Nodes -le 8) { 2.0 / 3.0 }
                elseif ($Hybrid) { if ($Nodes -le 11) { 2.0 / 3.0 } else { 8.0 / 11.0 } }
                elseif ($Nodes -le 15) { 0.75 }
                else { 0.8 }
            }
        }
    }
    function script:Get-SurveyorEffective {
        param($Case, [double] $InfraTB)
        $resil = $Case.resiliency
        if ($Case.rackAware) { $resil = if ($Case.nodes -ge 4) { 'four-way-mirror' } else { 'two-way-mirror' } }
        $f     = Get-SurveyorFactor -Resiliency $resil -Nodes $Case.nodes -Hybrid $Case.hybrid
        $raw   = $Case.driveTB * $Case.drivesPerNode * $Case.nodes
        $pool  = $raw * 0.99
        $res   = [math]::Min($Case.nodes, 4) * $Case.driveTB
        $infra = $InfraTB / $f
        $avail = [math]::Max(0.0, $pool - $res - $infra)
        [pscustomobject]@{ Factor = $f; Raw = $raw; Reserve = $res; Infra = $infra; Avail = $avail; Usable = $avail * $f }
    }
}

Describe 'Cartographer / Surveyor capacity contract' {

    It 'agrees with the Surveyor pipeline: <Name>' -ForEach $script:Cases {
        $ref = Get-SurveyorEffective -Case $Case -InfraTB $script:Fixture.infraVolumeSizeTB
        InModuleScope S2DCartographer -Parameters @{ Case = $Case; Ref = $ref } {
            $drive = [int64]($Case.driveTB * 1e12)
            $p = @{
                RawDiskBytes         = [int64]($drive * $Case.drivesPerNode * $Case.nodes)
                NodeCount            = [int]$Case.nodes
                LargestDiskSizeBytes = $drive
                InfraVolumeBytes     = [int64]($Ref.Infra * 1e12)
                ResiliencyFactor     = [double](1.0 / $Ref.Factor)
                ResiliencyName       = 'contract'
            }
            if ($Case.rackAware) { $p['RackAware'] = $true }
            $wf = Invoke-S2DWaterfallCalculation @p
            [math]::Abs($wf.RawCapacity.Bytes / 1e12 - $Ref.Raw) / $Ref.Raw | Should -BeLessThan 1e-6
            [math]::Abs($wf.ReserveRecommended.Bytes / 1e12 - $Ref.Reserve) | Should -BeLessThan 1e-6
            [math]::Abs($wf.AvailableForVolumes.Bytes / 1e12 - $Ref.Avail) / $Ref.Avail | Should -BeLessThan 1e-6
            [math]::Abs($wf.UsableCapacity.Bytes / 1e12 - $Ref.Usable) / $Ref.Usable | Should -BeLessThan 1e-6
        }
    }

    It 'documents that the 0.92 factor is not applied: stage 3 is raw x 0.99' {
        InModuleScope S2DCartographer {
            $drive = [int64]3840000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($drive * 16) -NodeCount 4 -LargestDiskSizeBytes $drive -ResiliencyFactor 3.0
            $ratio = $wf.Stages[2].Size.Bytes / ($drive * 16)
            $ratio | Should -BeGreaterThan 0.9899
            $ratio | Should -BeLessThan 0.9901
        }
    }

    It 'the 0.92 constant sits near the TB to TiB ratio (0.9095), i.e. it was a unit artefact, not a format overhead' {
        $tbToTib = 1e12 / [math]::Pow(1024, 4)
        [math]::Abs(0.92 - $tbToTib) | Should -BeLessThan 0.0125
    }

    It 'matches the Learn plan-volumes worked example: 4 x 16 x 2 TB, reserve 8 TB, 120 TB for volumes' {
        InModuleScope S2DCartographer {
            $drive = [int64]2000000000000
            # Learn example is decimal and ignores pool metadata, so zero the overhead.
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($drive * 64) -NodeCount 4 -LargestDiskSizeBytes $drive -PoolOverheadFraction 0 -ResiliencyFactor 3.0
            $wf.ReserveRecommended.Bytes | Should -Be 8000000000000
            $wf.AvailableForVolumes.Bytes | Should -Be 120000000000000
        }
    }
}
