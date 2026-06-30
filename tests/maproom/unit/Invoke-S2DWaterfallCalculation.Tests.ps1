#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Invoke-S2DWaterfallCalculation' {

    # IIC 4-node, 4× 3.84 TB capacity disks per node
    # Raw: 16 × 3,840,000,000,000 = 61,440,000,000,000 bytes
    # Pool: 60,820,000,000,000 bytes (provided)
    # Reserve: min(4,4) × 3,840,000,000,000 = 15,360,000,000,000 bytes
    # Infra: 1,572,864,000,000 bytes
    # Stage 4: 60,820,000,000,000 - 15,360,000,000,000 = 45,460,000,000,000
    # Stage 5: 45,460,000,000,000 - 1,572,864,000,000  = 43,887,136,000,000
    # Stage 6: 43,887,136,000,000
    # Stage 7 (Usable Capacity): 43,887,136,000,000 / 2.0 = 21,943,568,000,000  ← pipeline terminus (AB#4642: default changed 3.0→2.0)

    # Note: $script: vars are invisible inside InModuleScope — use literals or -Parameters
    # All constants defined here for the Describe block's documentation value only.
    #   rawBytes    = [int64](16 * 3840000000000) = 61440000000000
    #   poolTotal   = 60820000000000
    #   poolFree    = 40820000000000
    #   largestDisk = 3840000000000
    #   infraBytes  = 1572864000000
    #   nodeCount   = 4

    Context 'Return type and structure' {
        It 'returns an S2DCapacityWaterfall object' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result                | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }

        It 'returns exactly 7 stages' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages.Count | Should -Be 7
            }
        }

        It 'stage numbers are 1 through 7 in order' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $i = 1
                foreach ($s in $result.Stages) {
                    $s.Stage | Should -Be $i
                    $i++
                }
            }
        }

        It 'RawCapacity, UsableCapacity, ReserveRecommended, ReserveActual are S2DCapacity' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.RawCapacity.GetType().Name         | Should -Be 'S2DCapacity'
                $result.UsableCapacity.GetType().Name      | Should -Be 'S2DCapacity'
                $result.ReserveRecommended.GetType().Name  | Should -Be 'S2DCapacity'
                $result.ReserveActual.GetType().Name       | Should -Be 'S2DCapacity'
            }
        }
    }

    Context 'Stage arithmetic' {
        It 'Stage 1 (Raw Physical) equals RawDiskBytes' {
            InModuleScope S2DCartographer {
                $raw    = [int64]61440000000000
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         $raw `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[0].Size.Bytes | Should -Be $raw
            }
        }

        It 'Stage 2 (Vendor Label) equals Stage 1 — no deduction' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[1].Size.Bytes | Should -Be $result.Stages[0].Size.Bytes
            }
        }

        It 'Stage 3 (Pool) uses PoolTotalBytes when provided' {
            InModuleScope S2DCartographer {
                $poolTotal = [int64]60820000000000
                $result    = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       $poolTotal `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[2].Size.Bytes | Should -Be $poolTotal
            }
        }

        It 'Stage 3 (Pool) estimates as RawBytes × (1 - overhead) when PoolTotalBytes is 0' {
            InModuleScope S2DCartographer {
                $raw    = [int64]61440000000000
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         $raw `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]0) `
                    -PoolFreeBytes        ([int64]0)
                $expected = [int64]($raw * 0.99)
                $result.Stages[2].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 4 (After Reserve) deducts min(NodeCount,4) × largest drive' {
            InModuleScope S2DCartographer {
                $poolTotal    = [int64]60820000000000
                $largestDisk  = [int64]3840000000000
                $reserveBytes = [int64](4 * $largestDisk)
                $expected     = $poolTotal - $reserveBytes
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes $largestDisk `
                    -PoolTotalBytes       $poolTotal `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[3].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 4 caps reserve multiplier at 4 for large node counts' {
            InModuleScope S2DCartographer {
                # 8-node cluster — reserve still uses min(8,4)=4 drives
                $poolTotal    = [int64]60820000000000
                $largestDisk  = [int64]3840000000000
                $reserveBytes = [int64](4 * $largestDisk)
                $expected     = $poolTotal - $reserveBytes
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            8 `
                    -LargestDiskSizeBytes $largestDisk `
                    -PoolTotalBytes       $poolTotal `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[3].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 5 (After Infra Volume) deducts InfraVolumeBytes' {
            InModuleScope S2DCartographer {
                $poolTotal    = [int64]60820000000000
                $largestDisk  = [int64]3840000000000
                $infraBytes   = [int64]1572864000000
                $reserveBytes = [int64](4 * $largestDisk)
                $stage4       = $poolTotal - $reserveBytes
                $expected     = $stage4 - $infraBytes
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes $largestDisk `
                    -PoolTotalBytes       $poolTotal `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     $infraBytes
                $result.Stages[4].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 6 (Available) equals Stage 5' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)
                $result.Stages[5].Size.Bytes | Should -Be $result.Stages[4].Size.Bytes
            }
        }

        It 'Stage 7 (After Resiliency) = Stage 6 ÷ ResiliencyFactor (default 2.0 — AB#4642)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)
                # Default is now 2.0 (two-way mirror — minimum-safe assumption) not 3.0.
                $expected = [int64]($result.Stages[5].Size.Bytes / 2.0)
                $result.Stages[6].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 7 uses explicit ResiliencyFactor when provided' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $expected = [int64]($result.Stages[5].Size.Bytes / 2.0)
                $result.Stages[6].Size.Bytes | Should -Be $expected
            }
        }

        It 'pipeline is monotonically non-increasing from Stage 3 onward' {
            InModuleScope S2DCartographer {
                $stages = (Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -InfraVolumeBytes     ([int64]1572864000000)).Stages
                for ($i = 2; $i -lt $stages.Count - 1; $i++) {
                    $stages[$i + 1].Size.Bytes | Should -BeLessOrEqual $stages[$i].Size.Bytes `
                        -Because "Stage $($stages[$i+1].Stage) must not exceed Stage $($stages[$i].Stage)"
                }
            }
        }

        It 'UsableCapacity matches Stage 7 (pipeline terminus)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.UsableCapacity.Bytes | Should -Be $result.Stages[6].Size.Bytes
            }
        }

        It 'RawCapacity matches Stage 1' {
            InModuleScope S2DCartographer {
                $raw    = [int64]61440000000000
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         $raw `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.RawCapacity.Bytes | Should -Be $raw
            }
        }

        It 'BlendedEfficiencyPercent is 50.0 for default (2-way mirror assumed — AB#4642)' {
            InModuleScope S2DCartographer {
                # Default ResiliencyFactor is now 2.0, so default efficiency is 50.0%.
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.BlendedEfficiencyPercent | Should -Be 50.0
            }
        }

        It 'BlendedEfficiencyPercent is 33.3 for explicit 3-way mirror' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -ResiliencyFactor     3.0 `
                    -ResiliencyName       '3-way mirror'
                $result.BlendedEfficiencyPercent | Should -Be 33.3
            }
        }

        It 'BlendedEfficiencyPercent is 50.0 for explicit 2-way mirror' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000) `
                    -ResiliencyFactor     2.0 `
                    -ResiliencyName       '2-way mirror'
                $result.BlendedEfficiencyPercent | Should -Be 50.0
            }
        }
    }

    Context 'Reserve status' {
        It 'ReserveStatus is Adequate when pool free exceeds recommendation' {
            InModuleScope S2DCartographer {
                # poolFree=40.82TB >> reserve=15.36TB
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.ReserveStatus | Should -Be 'Adequate'
            }
        }

        It 'ReserveStatus is Critical when pool free is far below recommendation' {
            InModuleScope S2DCartographer {
                $lowFree = [int64]3000000000000   # 3 TB << 15.36 TB reserve
                $result  = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        $lowFree
                $result.ReserveStatus | Should -Be 'Critical'
            }
        }

        It 'all stage Status values are OK — waterfall is theoretical, no health state on stages' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]3000000000000)   # critically low reserve — still OK on stages
                foreach ($s in $result.Stages) {
                    $s.Status | Should -Be 'OK' -Because "Stage $($s.Stage) must never carry health state; reserve status lives on ReserveStatus only"
                }
            }
        }
    }
}
