#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Get-S2DCapacityWaterfall' {

    BeforeEach {
        InModuleScope S2DCartographer {
            # IIC 4-node, 4× 3.84TB NVMe per node — all capacity disks, all pool members
            $physDisks = @(foreach ($node in 1..4) {
                foreach ($disk in 1..4) {
                    [PSCustomObject]@{
                        NodeName     = "azl-iic-n0$node"
                        Role         = 'Capacity'
                        Usage        = 'Auto-Select'
                        SizeBytes    = [int64]3840000000000
                        IsPoolMember = $true
                    }
                }
            })

            # Pool: 16 × 3.84TB = 61.44TB raw → pool with slight overhead
            $poolTotal  = [int64]60820000000000   # ~60.82 TB
            $poolFree   = [int64]40820000000000   # ~40.82 TB free (adequate reserve)
            $poolAlloc  = $poolTotal - $poolFree

            $pool = [S2DStoragePool]::new()
            $pool.TotalSize      = [S2DCapacity]::new($poolTotal)
            $pool.AllocatedSize  = [S2DCapacity]::new($poolAlloc)
            $pool.RemainingSize  = [S2DCapacity]::new($poolFree)
            $pool.OvercommitRatio = 0.10
            # No ResiliencySettings → waterfall defaults to 3-way mirror (factor 3.0)

            # 1 infra + 2 workload volumes (used only for infra footprint in Stage 5)
            $iv = [S2DVolume]::new()
            $iv.FriendlyName           = 'Infrastructure_aabbccddeeff'
            $iv.IsInfrastructureVolume = $true
            $iv.Size                   = [S2DCapacity]::new([int64]524288000000)    # 512 GiB
            $iv.FootprintOnPool        = [S2DCapacity]::new([int64]1572864000000)   # 1.5 TiB 3-way footprint

            $wv1 = [S2DVolume]::new()
            $wv1.FriendlyName           = 'UserStorage_1'
            $wv1.IsInfrastructureVolume = $false
            $wv1.Size                   = [S2DCapacity]::new([int64]3000000000000)
            $wv1.FootprintOnPool        = [S2DCapacity]::new([int64]9000000000000)

            $wv2 = [S2DVolume]::new()
            $wv2.FriendlyName           = 'UserStorage_2'
            $wv2.IsInfrastructureVolume = $false
            $wv2.Size                   = [S2DCapacity]::new([int64]3000000000000)
            $wv2.FootprintOnPool        = [S2DCapacity]::new([int64]9000000000000)

            $Script:S2DSession = @{
                ClusterName   = 'azlocal-iic-s2d-01'
                ClusterFqdn   = 'azlocal-iic-s2d-01.iic.local'
                Nodes         = @('azl-iic-n01','azl-iic-n02','azl-iic-n03','azl-iic-n04')
                CimSession    = $null
                PSSession     = $null
                IsConnected   = $true
                IsLocal       = $true
                CollectedData = @{
                    PhysicalDisks = $physDisks
                    StoragePool   = $pool
                    Volumes       = @($iv, $wv1, $wv2)
                }
            }
        }
    }

    Context 'Return type and structure' {
        It 'returns an S2DCapacityWaterfall object' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result                | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }

        It 'produces exactly 7 stages' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).Stages.Count | Should -Be 7
            }
        }

        It 'stages are numbered 1 through 7 in order' {
            InModuleScope S2DCartographer {
                $i = 1
                foreach ($stage in (Get-S2DCapacityWaterfall).Stages) {
                    $stage.Stage | Should -Be $i
                    $i++
                }
            }
        }

        It 'RawCapacity and UsableCapacity are S2DCapacity objects' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result.RawCapacity.GetType().Name    | Should -Be 'S2DCapacity'
                $result.UsableCapacity.GetType().Name | Should -Be 'S2DCapacity'
            }
        }

        It 'ReserveRecommended and ReserveActual are S2DCapacity objects' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result.ReserveRecommended.GetType().Name | Should -Be 'S2DCapacity'
                $result.ReserveActual.GetType().Name      | Should -Be 'S2DCapacity'
            }
        }

        It 'NodeCount matches session node count' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).NodeCount | Should -Be 4
            }
        }
    }

    Context 'Stage calculations' {
        It 'Stage 1 (Raw Physical) equals sum of pool-member capacity disk bytes' {
            InModuleScope S2DCartographer {
                $expected = [int64](16 * 3840000000000)   # 16 disks × 3.84 TB
                (Get-S2DCapacityWaterfall).Stages[0].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 1 excludes non-pool-member disks' {
            InModuleScope S2DCartographer {
                # Add 2 non-pool disks (BOSS boot drives) — should not affect Stage 1
                $extraDisks = @(
                    [PSCustomObject]@{ NodeName='azl-iic-n01'; Role='Capacity'; Usage='Auto-Select'; SizeBytes=[int64]240000000000; IsPoolMember=$false },
                    [PSCustomObject]@{ NodeName='azl-iic-n02'; Role='Capacity'; Usage='Auto-Select'; SizeBytes=[int64]240000000000; IsPoolMember=$false }
                )
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @($Script:S2DSession.CollectedData['PhysicalDisks']) + $extraDisks
                $expected = [int64](16 * 3840000000000)
                (Get-S2DCapacityWaterfall).Stages[0].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 2 (Vendor Label) has the same bytes as Stage 1' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result.Stages[1].Size.Bytes | Should -Be $result.Stages[0].Size.Bytes
            }
        }

        It 'Stage 3 (Pool) uses pool.TotalSize when pool data is present' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).Stages[2].Size.Bytes | Should -Be ([int64]60820000000000)
            }
        }

        It 'Stage 4 (After Reserve) equals Stage 3 minus min(NodeCount,4) × largest drive' {
            InModuleScope S2DCartographer {
                $poolTotal    = [int64]60820000000000
                $reserveBytes = [int64](4 * 3840000000000)   # 4 × 3.84 TB = 15.36 TB
                $expected     = $poolTotal - $reserveBytes
                (Get-S2DCapacityWaterfall).Stages[3].Size.Bytes | Should -Be $expected
            }
        }

        It 'Stage 7 (After Resiliency) equals Stage 6 divided by resiliency factor (default 2.0 — AB#4642)' {
            InModuleScope S2DCartographer {
                # Pool fixture has no ResiliencySettings → falls back to 2.0 (minimum-safe assumption).
                $result   = Get-S2DCapacityWaterfall
                $stage6   = $result.Stages[5].Size.Bytes
                $expected = [int64]($stage6 / 2.0)
                $result.Stages[6].Size.Bytes | Should -Be $expected
            }
        }

        It 'pipeline is monotonically non-increasing from Stage 3 onward' {
            InModuleScope S2DCartographer {
                $stages = (Get-S2DCapacityWaterfall).Stages
                # Stage 1 = Stage 2 (informational), Stage 3 onwards must not increase
                for ($i = 2; $i -lt $stages.Count - 1; $i++) {
                    $stages[$i + 1].Size.Bytes | Should -BeLessOrEqual $stages[$i].Size.Bytes `
                        -Because "Stage $($stages[$i+1].Stage) must not exceed Stage $($stages[$i].Stage)"
                }
            }
        }

        It 'resiliency factor from pool ResiliencySettings overrides default when Mirror entry present' {
            InModuleScope S2DCartographer {
                $pool = $Script:S2DSession.CollectedData['StoragePool']
                $pool.ResiliencySettings = @([PSCustomObject]@{ Name='Mirror'; NumberOfDataCopies=2; PhysicalDiskRedundancy=1; NumberOfColumns=1 })

                $result = Get-S2DCapacityWaterfall
                $stage6 = $result.Stages[5].Size.Bytes
                $expected = [int64]($stage6 / 2.0)
                $result.Stages[6].Size.Bytes | Should -Be $expected
            }
        }

        It 'UsableCapacity matches Stage 7 (pipeline terminus)' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result.UsableCapacity.Bytes | Should -Be $result.Stages[6].Size.Bytes
            }
        }

        It 'BlendedEfficiencyPercent reflects theoretical resiliency efficiency' {
            InModuleScope S2DCartographer {
                # Pool fixture has no ResiliencySettings → falls back to 2-way mirror (AB#4642) → 50.0%
                $result = Get-S2DCapacityWaterfall
                $result.BlendedEfficiencyPercent | Should -Be 50.0
            }
        }
    }

    Context 'Reserve status' {
        It 'ReserveStatus is Adequate when pool free space exceeds recommendation' {
            InModuleScope S2DCartographer {
                # poolFree=40.82TB >> reserve=15.36TB
                (Get-S2DCapacityWaterfall).ReserveStatus | Should -Be 'Adequate'
            }
        }

        It 'ReserveStatus is Critical when pool free space is critically low' {
            InModuleScope S2DCartographer {
                $pool = $Script:S2DSession.CollectedData['StoragePool']
                $pool.RemainingSize = [S2DCapacity]::new([int64]3000000000000)   # 3 TB << 15.36 TB reserve

                (Get-S2DCapacityWaterfall).ReserveStatus | Should -Be 'Critical'
            }
        }

        It 'Stage 4 Status is OK when reserve is Adequate' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).Stages[3].Status | Should -Be 'OK'
            }
        }

        It 'all stage Status values are OK even when reserve is critically low — no health state on stages' {
            InModuleScope S2DCartographer {
                $pool = $Script:S2DSession.CollectedData['StoragePool']
                $pool.RemainingSize = [S2DCapacity]::new([int64]3000000000000)

                $result = Get-S2DCapacityWaterfall
                foreach ($s in $result.Stages) {
                    $s.Status | Should -Be 'OK' -Because "Stage $($s.Stage) must never carry health state"
                }
            }
        }
    }

    Context 'Caching' {
        It 'caches result in CollectedData after computation' {
            InModuleScope S2DCartographer {
                Get-S2DCapacityWaterfall | Out-Null
                $Script:S2DSession.CollectedData['CapacityWaterfall']                | Should -Not -BeNullOrEmpty
                $Script:S2DSession.CollectedData['CapacityWaterfall'].GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }
    }
}
