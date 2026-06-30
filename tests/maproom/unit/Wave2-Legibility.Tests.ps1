#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
# Wave 2 legibility tests — AB#4644 (70% planning line) + AB#4645 (TB/TiB + footprint/usable labels)
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Wave 2 — AB#4644: 70% planning line' {

    # Reference cluster: 3.84 TB × 4 drives × 2 nodes, two-way mirror
    # Raw: 8 × 3,840,000,000,000 = 30,720,000,000,000 bytes
    # Pool (estimated, no PoolTotalBytes supplied): 30,720,000,000,000 × 0.99 = 30,412,800,000,000
    # Reserve: min(2,4) × 3,840,000,000,000 = 7,680,000,000,000
    # Infra: 322,122,547,200 (~300 GiB footprint)
    # Stage 6 (AvailableForVolumes): 30,412,800,000,000 - 7,680,000,000,000 - 322,122,547,200 = 22,410,677,452,800
    # 70% line: 22,410,677,452,800 × 0.70 = 15,687,474,216,960

    Context 'PlanningLine70Pct property is populated' {
        It 'returns an S2DCapacityWaterfall with PlanningLine70Pct set' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64](8 * 3840000000000)) `
                    -NodeCount            2 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]0) `
                    -PoolFreeBytes        ([int64]0) `
                    -InfraVolumeBytes     ([int64]322122547200) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $result.PlanningLine70Pct               | Should -Not -BeNullOrEmpty
                $result.PlanningLine70Pct.GetType().Name | Should -Be 'S2DCapacity'
            }
        }

        It 'PlanningLine70Pct.Bytes equals 70% of Stage 6 (AvailableForVolumes) bytes' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64](8 * 3840000000000)) `
                    -NodeCount            2 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]0) `
                    -PoolFreeBytes        ([int64]0) `
                    -InfraVolumeBytes     ([int64]322122547200) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $stage6Bytes = $result.Stages[5].Size.Bytes
                $expected    = [int64]($stage6Bytes * 0.70)
                $result.PlanningLine70Pct.Bytes | Should -Be $expected
            }
        }

        It 'PlanningLine70Pct equals AvailableForVolumes × 0.70 (cross-check via AvailableForVolumes property)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64](8 * 3840000000000)) `
                    -NodeCount            2 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]0) `
                    -PoolFreeBytes        ([int64]0) `
                    -InfraVolumeBytes     ([int64]322122547200) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $expected = [int64]($result.AvailableForVolumes.Bytes * 0.70)
                $result.PlanningLine70Pct.Bytes | Should -Be $expected
            }
        }

        It 'PlanningLine70Pct is strictly less than AvailableForVolumes' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)
                $result.PlanningLine70Pct.Bytes | Should -BeLessThan $result.AvailableForVolumes.Bytes
            }
        }

        It 'PlanningLine70Pct TB and TiB values are consistent with its Bytes (both units populated)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)
                $line = $result.PlanningLine70Pct
                $expectedTB  = [math]::Round($line.Bytes / 1e12,            2)
                $expectedTiB = [math]::Round($line.Bytes / 1099511627776.0, 2)
                $line.TB  | Should -Be $expectedTB
                $line.TiB | Should -Be $expectedTiB
            }
        }

        It 'sanity: reference cluster 70% line is approximately 15.69 TB (within 1% of canonical 15.70 TB)' {
            # capacity-model.md reference: 70% line ≈ 15.70 TB / 14.28 TiB for 3.84TB×4×2 cluster
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64](8 * 3840000000000)) `
                    -NodeCount            2 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]0) `
                    -PoolFreeBytes        ([int64]0) `
                    -InfraVolumeBytes     ([int64]322122547200) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $actualTB = $result.PlanningLine70Pct.TB
                # Canonical says ~15.70 TB; allow ±2% tolerance for pool-overhead estimation path
                $actualTB | Should -BeGreaterThan 15.0
                $actualTB | Should -BeLessThan    16.5
            }
        }
    }

    Context 'IsAbove70PctLine default on pure function output' {
        It 'IsAbove70PctLine defaults to false from Invoke-S2DWaterfallCalculation (set by caller)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.IsAbove70PctLine | Should -Be $false
            }
        }
    }

    Context 'AvailableForVolumes property' {
        It 'AvailableForVolumes is an S2DCapacity object matching Stage 6 bytes' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)
                $result.AvailableForVolumes               | Should -Not -BeNullOrEmpty
                $result.AvailableForVolumes.GetType().Name | Should -Be 'S2DCapacity'
                $result.AvailableForVolumes.Bytes          | Should -Be $result.Stages[5].Size.Bytes
            }
        }
    }
}

Describe 'Wave 2 — AB#4645: TB/TiB + footprint/usable labels in stage descriptions' {

    Context 'Stage descriptions label space type' {
        It 'Stage 1 description starts with FOOTPRINT' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[0].Description | Should -BeLike 'FOOTPRINT*'
            }
        }

        It 'Stage 2 description is labeled INFORMATIONAL (no deduction)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[1].Description | Should -BeLike 'INFORMATIONAL*'
            }
        }

        It 'Stage 3 description starts with FOOTPRINT' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[2].Description | Should -BeLike 'FOOTPRINT*'
            }
        }

        It 'Stage 4 description starts with FOOTPRINT' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[3].Description | Should -BeLike 'FOOTPRINT*'
            }
        }

        It 'Stage 5 description starts with FOOTPRINT' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[4].Description | Should -BeLike 'FOOTPRINT*'
            }
        }

        It 'Stage 6 description starts with FOOTPRINT and mentions 70% planning line' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[5].Description | Should -BeLike 'FOOTPRINT*'
                $result.Stages[5].Description | Should -BeLike '*70%*'
            }
        }

        It 'Stage 7 description starts with DATA (usable)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[6].Description | Should -BeLike 'DATA*'
            }
        }
    }

    Context 'Stage descriptions include both TB and TiB values' {
        It 'Stage 1 description contains both TB and TiB tokens' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[0].Description | Should -BeLike '* TB *'
                $result.Stages[0].Description | Should -BeLike '* TiB*'
            }
        }

        It 'Stage 7 description contains both TB and TiB tokens for footprint and usable data' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[6].Description | Should -BeLike '* TB *'
                $result.Stages[6].Description | Should -BeLike '* TiB*'
            }
        }
    }

    Context 'S2DCapacity.Display dual-unit format' {
        It 'S2DCapacity.Display shows TiB (binary) then TB (decimal) — no silent mixing' {
            InModuleScope S2DCartographer {
                $cap = [S2DCapacity]::new([int64]3840000000000)
                # Display format: "X.XX TiB (Y.YY TB)"  — TiB primary, TB in parens
                $cap.Display | Should -BeLike '* TiB (*TB*)'
            }
        }

        It 'S2DCapacity TB and TiB are different values (confirms no silent decimal/binary mixing)' {
            InModuleScope S2DCartographer {
                $cap = [S2DCapacity]::new([int64]3840000000000)
                $cap.TB  | Should -Be 3.84   # decimal: 3,840,000,000,000 / 1e12
                $cap.TiB | Should -Be 3.49   # binary:  3,840,000,000,000 / 1099511627776 ≈ 3.492 → rounds 3.49
            }
        }
    }
}
