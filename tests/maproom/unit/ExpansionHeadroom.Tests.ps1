#Requires -Version 7.0
#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Tests for the EfficiencyPercent bug fix (1.7.1) and Get-S2DExpansionHeadroom.

.DESCRIPTION
    (a) EfficiencyPercent regression — NumberOfDataCopies=2 is always 50% regardless
        of node count. NumberOfDataCopies=4 is the nested two-way mirror at 25%.
        Covers both Get-S2DResiliencyEfficiency directly and through Get-S2DVolumeMap
        with the ground-truth measured-footprint path.

    (b) Get-S2DExpansionHeadroom golden values — POC cluster fixture:
        A = 22,441,090,170,880 B (AvailableForVolumes)
        U = 14,278,618,775,552 B (non-infra footprint sum)
        copies = 2

    All external CIM/cluster cmdlets are mocked at the Describe level so the
    suite runs hermetically on Linux CI (no Windows Storage cmdlets required).
    Uses [System.IO.Path]::GetTempPath() not $env:TEMP.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

# ── (a) EfficiencyPercent regression ─────────────────────────────────────────

Describe 'EfficiencyPercent bug fix — NumberOfDataCopies=2 is always 50% (AB#1.7.1)' {

    BeforeEach {
        InModuleScope S2DCartographer {
            $Script:S2DSession = @{
                ClusterName   = 'poc-2node'
                ClusterFqdn   = 'poc-2node.local'
                Nodes         = @('poc-n01', 'poc-n02')
                CimSession    = $null
                PSSession     = $null
                IsConnected   = $true
                IsLocal       = $true
                CollectedData = @{}
            }
        }
    }

    Context 'Get-S2DResiliencyEfficiency — formula path' {

        It 'NumberOfDataCopies=2, NodeCount=2 → Two-Way Mirror (not Nested)' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 2 -NodeCount 2
                $r.ResiliencyType | Should -Be 'Two-Way Mirror'
            }
        }

        It 'NumberOfDataCopies=2, NodeCount=2 → 50.0% (not 25%)' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 2 -NodeCount 2
                $r.EfficiencyPercent | Should -Be 50.0
            }
        }

        It 'NumberOfDataCopies=2, NodeCount=1 → Two-Way Mirror at 50%' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 2 -NodeCount 1
                $r.ResiliencyType    | Should -Be 'Two-Way Mirror'
                $r.EfficiencyPercent | Should -Be 50.0
            }
        }

        It 'NumberOfDataCopies=4, NodeCount=2 → Nested Two-Way Mirror at 25%' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 4 -NodeCount 2
                $r.ResiliencyType    | Should -Be 'Nested Two-Way Mirror'
                $r.EfficiencyPercent | Should -Be 25.0
            }
        }

        It 'NumberOfDataCopies=4, NodeCount=4 → Nested Two-Way Mirror at 25%' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 4 -NodeCount 4
                $r.ResiliencyType    | Should -Be 'Nested Two-Way Mirror'
                $r.EfficiencyPercent | Should -Be 25.0
            }
        }

        It 'NumberOfDataCopies=3 → Three-Way Mirror at 33.3% (unchanged)' {
            InModuleScope S2DCartographer {
                $r = Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 3 -NodeCount 3
                $r.ResiliencyType    | Should -Be 'Three-Way Mirror'
                $r.EfficiencyPercent | Should -Be 33.3
            }
        }
    }

    Context 'Get-S2DVolumeMap — ground-truth measured-footprint path on 2-node cluster' {

        BeforeEach {
            InModuleScope S2DCartographer {
                # Mock all Windows-only Storage shims — Linux CI safe.
                Mock Resolve-S2DSession     { return $null } -ModuleName S2DCartographer
                Mock Get-S2DPhysicalDiskData { return @()  } -ModuleName S2DCartographer
                Mock Get-S2DDiskData         { return @()  } -ModuleName S2DCartographer
                Mock Get-S2DStoragePoolData  { return $null } -ModuleName S2DCartographer
                Mock Get-S2DClusterS2DData   { return $null } -ModuleName S2DCartographer
            }
        }

        It 'POC two-way mirror (copies=2) on 2-node: EfficiencyPercent = 50.0 from measured footprint' {
            InModuleScope S2DCartographer {
                # POC proof: FootprintOnPool = 2 × Size → measured efficiency = 50.0%
                $sizeBytes      = [int64]3570000000000   # ~3.57 TB (Size)
                $footprintBytes = [int64]7140000000000   # ~7.14 TB (FootprintOnPool = 2× size)

                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName           = 'ProdVM-1'
                        ResiliencySettingName  = 'Mirror'
                        NumberOfDataCopies     = 2
                        PhysicalDiskRedundancy = 1
                        ProvisioningType       = 'Fixed'
                        Size                   = $sizeBytes
                        FootprintOnPool        = $footprintBytes
                        AllocatedSize          = [int64]0
                        FileSystem             = 'CSVFS_ReFS'
                        OperationalStatus      = 'OK'
                        HealthStatus           = 'Healthy'
                    })
                } -ModuleName S2DCartographer

                $result = Get-S2DVolumeMap
                $result[0].EfficiencyPercent | Should -Be 50.0
            }
        }

        It 'Nested mirror (copies=4) volume: EfficiencyPercent = 25.0 from measured footprint (footprint=4×size)' {
            InModuleScope S2DCartographer {
                $sizeBytes      = [int64]1000000000000
                $footprintBytes = [int64]4000000000000   # 4× size

                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName           = 'NestedVol'
                        ResiliencySettingName  = 'Mirror'
                        NumberOfDataCopies     = 4
                        PhysicalDiskRedundancy = 1
                        ProvisioningType       = 'Fixed'
                        Size                   = $sizeBytes
                        FootprintOnPool        = $footprintBytes
                        AllocatedSize          = [int64]0
                        FileSystem             = 'CSVFS_ReFS'
                        OperationalStatus      = 'OK'
                        HealthStatus           = 'Healthy'
                    })
                } -ModuleName S2DCartographer

                $result = Get-S2DVolumeMap
                $result[0].EfficiencyPercent | Should -Be 25.0
            }
        }

        It 'Falls back to formula efficiency when FootprintOnPool = 0' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName           = 'NoFootprint'
                        ResiliencySettingName  = 'Mirror'
                        NumberOfDataCopies     = 2
                        PhysicalDiskRedundancy = 1
                        ProvisioningType       = 'Fixed'
                        Size                   = [int64]5000000000000
                        FootprintOnPool        = [int64]0
                        AllocatedSize          = [int64]0
                        FileSystem             = 'CSVFS_ReFS'
                        OperationalStatus      = 'OK'
                        HealthStatus           = 'Healthy'
                    })
                } -ModuleName S2DCartographer

                $result = Get-S2DVolumeMap
                # Formula path: NumberOfDataCopies=2 → 50.0%
                $result[0].EfficiencyPercent | Should -Be 50.0
            }
        }
    }
}

# ── (b) Get-S2DExpansionHeadroom golden values ────────────────────────────────

Describe 'Get-S2DExpansionHeadroom — POC cluster golden values (AB#1.7.1)' {

    # POC canonical values (docs/capacity-model.md)
    # A = 22,441,090,170,880 B  (AvailableForVolumes)
    # U = 14,278,618,775,552 B  (non-infra footprint sum: two prod volumes)
    # copies = 2
    #
    # All S2DCapacity / S2DClasses constructs must live inside InModuleScope
    # because those types are defined inside the module and are not available
    # at the outer Pester/test-runner scope. S2DCapacity is not exported.

    BeforeAll {
        # Run the full fixture setup inside the module where S2DCapacity is defined.
        # Results are returned and stored in $Script:* for use by all It blocks.
        $fixtureData = InModuleScope S2DCartographer {
            $availBytes = [int64]22441090170880
            $usedBytes  = [int64]14278618775552

            $fakeWaterfall = [PSCustomObject]@{
                AvailableForVolumes = [S2DCapacity]::new($availBytes)
            }

            $half = [int64][math]::Round($usedBytes / 2)
            $rem  = $usedBytes - $half

            $fakeVolumes = @(
                [PSCustomObject]@{
                    FriendlyName           = 'ProdVM-1'
                    IsInfrastructureVolume = $false
                    NumberOfDataCopies     = 2
                    FootprintOnPool        = [S2DCapacity]::new($half)
                },
                [PSCustomObject]@{
                    FriendlyName           = 'ProdVM-2'
                    IsInfrastructureVolume = $false
                    NumberOfDataCopies     = 2
                    FootprintOnPool        = [S2DCapacity]::new($rem)
                },
                [PSCustomObject]@{
                    FriendlyName           = 'Infrastructure_abc123'
                    IsInfrastructureVolume = $true
                    NumberOfDataCopies     = 2
                    FootprintOnPool        = [S2DCapacity]::new([int64]500000000000)
                }
            )

            $result = Get-S2DExpansionHeadroom -Waterfall $fakeWaterfall -Volumes $fakeVolumes

            # Return everything the outer scope needs
            [PSCustomObject]@{
                AvailBytes    = $availBytes
                UsedBytes     = $usedBytes
                FakeWaterfall = $fakeWaterfall
                FakeVolumes   = $fakeVolumes
                Result        = $result
            }
        }

        $Script:availBytes    = $fixtureData.AvailBytes
        $Script:usedBytes     = $fixtureData.UsedBytes
        $Script:fakeWaterfall = $fixtureData.FakeWaterfall
        $Script:fakeVolumes   = $fixtureData.FakeVolumes
        $Script:result        = $fixtureData.Result
    }

    Context 'Top-level properties' {

        It 'returns a non-null result' {
            $Script:result | Should -Not -BeNullOrEmpty
        }

        It 'CurrentUtilizationPct = 63.6% (±0.15)' {
            $Script:result.CurrentUtilizationPct | Should -BeGreaterThan 63.4
            $Script:result.CurrentUtilizationPct | Should -BeLessThan    63.8
        }

        It 'PrevalentDataCopies = 2' {
            $Script:result.PrevalentDataCopies | Should -Be 2
        }

        It 'AvailableForVolumesBytes matches input A' {
            $Script:result.AvailableForVolumesBytes | Should -Be $Script:availBytes
        }

        It 'UsedFootprintBytes matches input U (infra volume excluded)' {
            $Script:result.UsedFootprintBytes | Should -Be $Script:usedBytes
        }

        It 'Thresholds array has 4 entries' {
            $Script:result.Thresholds.Count | Should -Be 4
        }
    }

    Context '70% threshold (recommended planning line)' {

        BeforeAll { $Script:t70 = $Script:result.Thresholds | Where-Object FillTargetPct -eq 70 }

        It 'exists' { $Script:t70 | Should -Not -BeNullOrEmpty }
        It 'IsRecommendedPlanningLine = $true'  { $Script:t70.IsRecommendedPlanningLine | Should -BeTrue }
        It 'IsPastLine = $false (63.6% < 70%)'  { $Script:t70.IsPastLine | Should -BeFalse }

        It 'FootprintBudget.TB approx 15.71 (±0.02)' {
            $Script:t70.FootprintBudget.TB | Should -BeGreaterThan 15.68
            $Script:t70.FootprintBudget.TB | Should -BeLessThan    15.74
        }
        It 'RemainingFootprint.TB approx 1.43 (±0.02)' {
            $Script:t70.RemainingFootprint.TB | Should -BeGreaterThan 1.40
            $Script:t70.RemainingFootprint.TB | Should -BeLessThan    1.46
        }
        It 'NewUsableData.TB approx 0.72 (±0.02)' {
            $Script:t70.NewUsableData.TB | Should -BeGreaterThan 0.69
            $Script:t70.NewUsableData.TB | Should -BeLessThan    0.75
        }
        It 'FootprintBudget is an S2DCapacity object' {
            $Script:t70.FootprintBudget.GetType().Name | Should -Be 'S2DCapacity'
        }
    }

    Context '80% threshold' {

        BeforeAll { $Script:t80 = $Script:result.Thresholds | Where-Object FillTargetPct -eq 80 }

        It 'exists' { $Script:t80 | Should -Not -BeNullOrEmpty }
        It 'IsRecommendedPlanningLine = $false' { $Script:t80.IsRecommendedPlanningLine | Should -BeFalse }

        It 'FootprintBudget.TB approx 17.95 (±0.02)' {
            $Script:t80.FootprintBudget.TB | Should -BeGreaterThan 17.92
            $Script:t80.FootprintBudget.TB | Should -BeLessThan    17.98
        }
        It 'RemainingFootprint.TB approx 3.67 (±0.02)' {
            $Script:t80.RemainingFootprint.TB | Should -BeGreaterThan 3.64
            $Script:t80.RemainingFootprint.TB | Should -BeLessThan    3.70
        }
        It 'NewUsableData.TB approx 1.84 (±0.02)' {
            $Script:t80.NewUsableData.TB | Should -BeGreaterThan 1.81
            $Script:t80.NewUsableData.TB | Should -BeLessThan    1.87
        }
    }

    Context '90% threshold' {

        BeforeAll { $Script:t90 = $Script:result.Thresholds | Where-Object FillTargetPct -eq 90 }

        It 'exists' { $Script:t90 | Should -Not -BeNullOrEmpty }

        It 'FootprintBudget.TB approx 20.20 (±0.02)' {
            $Script:t90.FootprintBudget.TB | Should -BeGreaterThan 20.17
            $Script:t90.FootprintBudget.TB | Should -BeLessThan    20.23
        }
        It 'RemainingFootprint.TB approx 5.92 (±0.02)' {
            $Script:t90.RemainingFootprint.TB | Should -BeGreaterThan 5.89
            $Script:t90.RemainingFootprint.TB | Should -BeLessThan    5.95
        }
        It 'NewUsableData.TB approx 2.96 (±0.02)' {
            $Script:t90.NewUsableData.TB | Should -BeGreaterThan 2.93
            $Script:t90.NewUsableData.TB | Should -BeLessThan    2.99
        }
    }

    Context '100% threshold' {

        BeforeAll { $Script:t100 = $Script:result.Thresholds | Where-Object FillTargetPct -eq 100 }

        It 'exists' { $Script:t100 | Should -Not -BeNullOrEmpty }
        It 'IsRecommendedPlanningLine = $false' { $Script:t100.IsRecommendedPlanningLine | Should -BeFalse }

        It 'FootprintBudget.TB approx 22.44 (±0.02)' {
            $Script:t100.FootprintBudget.TB | Should -BeGreaterThan 22.41
            $Script:t100.FootprintBudget.TB | Should -BeLessThan    22.47
        }
        It 'RemainingFootprint.TB approx 8.16 (±0.02)' {
            $Script:t100.RemainingFootprint.TB | Should -BeGreaterThan 8.13
            $Script:t100.RemainingFootprint.TB | Should -BeLessThan    8.19
        }
        It 'NewUsableData.TB approx 4.08 (±0.02)' {
            $Script:t100.NewUsableData.TB | Should -BeGreaterThan 4.05
            $Script:t100.NewUsableData.TB | Should -BeLessThan    4.11
        }
    }

    Context 'Edge cases' {

        It 'empty volumes — PrevalentDataCopies = 2 (default), utilization = 0%' {
            $emptyResult = InModuleScope S2DCartographer -Parameters @{ Wf = $Script:fakeWaterfall } {
                param($Wf)
                Get-S2DExpansionHeadroom -Waterfall $Wf -Volumes @()
            }
            $emptyResult.CurrentUtilizationPct | Should -Be 0.0
            $emptyResult.PrevalentDataCopies   | Should -Be 2
            $emptyResult.UsedFootprintBytes    | Should -Be 0
        }

        It 'all volumes are infra — usedBytes = 0, utilization = 0%' {
            $infraResult = InModuleScope S2DCartographer -Parameters @{ Wf = $Script:fakeWaterfall } {
                param($Wf)
                $infraOnly = @(
                    [PSCustomObject]@{
                        FriendlyName           = 'Infrastructure_xyz'
                        IsInfrastructureVolume = $true
                        NumberOfDataCopies     = 2
                        FootprintOnPool        = [S2DCapacity]::new([int64]1000000000000)
                    }
                )
                Get-S2DExpansionHeadroom -Waterfall $Wf -Volumes $infraOnly
            }
            $infraResult.CurrentUtilizationPct | Should -Be 0.0
            $infraResult.UsedFootprintBytes    | Should -Be 0
        }

        It 'null AvailableForVolumes — AvailableForVolumesBytes = 0, all threshold budgets = 0' {
            $nullResult = InModuleScope S2DCartographer {
                $nullWf = [PSCustomObject]@{ AvailableForVolumes = $null }
                Get-S2DExpansionHeadroom -Waterfall $nullWf -Volumes @()
            }
            $nullResult.AvailableForVolumesBytes | Should -Be 0
            ($nullResult.Thresholds | ForEach-Object { $_.FootprintBudget.Bytes } | Measure-Object -Sum).Sum | Should -Be 0
        }
    }
}
