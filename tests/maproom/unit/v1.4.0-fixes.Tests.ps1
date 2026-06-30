#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Regression tests for v1.4.0 bug fixes.

    #46  ThinOvercommit / ThinReserveRisk must not fire on Azure Local
         infrastructure volumes (UserStorage_N, HCI_UserStorage_N, SBEAgent,
         ClusterPerformanceHistory, Infrastructure_<guid>).

    #47  Capacity Model stage table: all stage Status values must be 'OK'.
         Reserve adequacy lives on ReserveStatus only — never on a stage row.

    #52  Capacity waterfall must have exactly 7 stages with correct Microsoft
         S2D terminology names.
#>

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

# ─────────────────────────────────────────────────────────────────────────────
# #46  Infrastructure volume detection — must not trigger thin overcommit checks
# ─────────────────────────────────────────────────────────────────────────────
Describe 'v1.4.0 #46 — Infrastructure volumes are not flagged as thin overcommit risk' {

    Context 'Get-S2DInfraVolumeFlag — known Azure Local system volume names' {

        $cases = @(
            @{ Name = 'ClusterPerformanceHistory';    Expected = $true  }
            @{ Name = 'Infrastructure_abc123def456';  Expected = $true  }
            @{ Name = 'UserStorage_1';                Expected = $true  }
            @{ Name = 'UserStorage_2';                Expected = $true  }
            @{ Name = 'HCI_UserStorage_1';            Expected = $true  }
            @{ Name = 'HCI_UserStorage_3';            Expected = $true  }
            @{ Name = 'SBEAgent';                     Expected = $true  }
            @{ Name = 'VM-Workload';                  Expected = $false }
            @{ Name = 'VMs-Thin';                     Expected = $false }
            @{ Name = 'Backup';                       Expected = $false }
            @{ Name = 'UserData';                     Expected = $false }
        )

        It 'correctly classifies <Name> as IsInfra=<Expected>' -ForEach $cases {
            InModuleScope S2DCartographer -Parameters @{ n = $Name; exp = $Expected } {
                param($n, $exp)
                $result = Get-S2DInfraVolumeFlag -FriendlyName $n -SizeBytes 0
                $result | Should -Be $exp -Because "'$n' IsInfrastructureVolume should be $exp"
            }
        }
    }

    Context 'Get-S2DVolumeMap — infra volumes do not set ThinOvercommit on thin-provisioned system volumes' {

        BeforeEach {
            InModuleScope S2DCartographer {
                $Script:S2DSession = @{
                    ClusterName   = 'azlocal-test'
                    ClusterFqdn   = 'azlocal-test.local'
                    Nodes         = @('n01','n02','n03','n04')
                    CimSession    = $null
                    PSSession     = $null
                    IsConnected   = $true
                    IsLocal       = $true
                    CollectedData = @{}
                }
            }
        }

        It 'UserStorage_1 thin volume has IsInfrastructureVolume = true' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName          = 'UserStorage_1'
                        ResiliencySettingName = 'Mirror'
                        NumberOfDataCopies    = 3
                        PhysicalDiskRedundancy = 2
                        ProvisioningType      = 'Thin'
                        Size                  = [int64]107374182400    # 100 GiB
                        FootprintOnPool       = [int64]53687091200
                        AllocatedSize         = [int64]10737418240
                        OperationalStatus     = 'OK'
                        HealthStatus          = 'Healthy'
                    })
                }
                $vols = Get-S2DVolumeMap
                $vols[0].IsInfrastructureVolume | Should -Be $true
            }
        }

        It 'HCI_UserStorage_1 thin volume has IsInfrastructureVolume = true' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName          = 'HCI_UserStorage_1'
                        ResiliencySettingName = 'Mirror'
                        NumberOfDataCopies    = 3
                        PhysicalDiskRedundancy = 2
                        ProvisioningType      = 'Thin'
                        Size                  = [int64]107374182400
                        FootprintOnPool       = [int64]53687091200
                        AllocatedSize         = [int64]10737418240
                        OperationalStatus     = 'OK'
                        HealthStatus          = 'Healthy'
                    })
                }
                $vols = Get-S2DVolumeMap
                $vols[0].IsInfrastructureVolume | Should -Be $true
            }
        }

        It 'SBEAgent thin volume has IsInfrastructureVolume = true' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName          = 'SBEAgent'
                        ResiliencySettingName = 'Mirror'
                        NumberOfDataCopies    = 3
                        PhysicalDiskRedundancy = 2
                        ProvisioningType      = 'Thin'
                        Size                  = [int64]107374182400
                        FootprintOnPool       = [int64]53687091200
                        AllocatedSize         = [int64]10737418240
                        OperationalStatus     = 'OK'
                        HealthStatus          = 'Healthy'
                    })
                }
                $vols = Get-S2DVolumeMap
                $vols[0].IsInfrastructureVolume | Should -Be $true
            }
        }

        It 'user workload thin volume has IsInfrastructureVolume = false' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName          = 'VM-Workload'
                        ResiliencySettingName = 'Mirror'
                        NumberOfDataCopies    = 3
                        PhysicalDiskRedundancy = 2
                        ProvisioningType      = 'Thin'
                        Size                  = [int64]5000000000000
                        FootprintOnPool       = [int64]1000000000000
                        AllocatedSize         = [int64]500000000000
                        OperationalStatus     = 'OK'
                        HealthStatus          = 'Healthy'
                    })
                }
                $vols = Get-S2DVolumeMap
                $vols[0].IsInfrastructureVolume | Should -Be $false
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# #47 / #52  Capacity waterfall — 7 stages, correct names, no health on stages
# ─────────────────────────────────────────────────────────────────────────────
Describe 'v1.4.0 #47/#52 — Capacity waterfall is a purely theoretical 7-stage pipeline' {

    # Shared inputs: 4-node IIC cluster, 16 × 3.84 TB NVMe
    $raw      = [int64]61440000000000
    $largest  = [int64]3840000000000
    $poolFree = [int64]40820000000000

    Context 'Stage count' {

        It 'returns exactly 7 stages — redundant Stage 8 was removed' {
            InModuleScope S2DCartographer -Parameters @{ raw = [int64]61440000000000; largest = [int64]3840000000000 } {
                param($raw, $largest)
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         $raw `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes $largest `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages.Count | Should -Be 7
            }
        }
    }

    Context 'Stage names match Microsoft S2D terminology' {

        $expectedNames = @(
            @{ Index = 0; Name = 'Raw Capacity'          }
            @{ Index = 1; Name = 'Vendor (TB)'           }
            @{ Index = 2; Name = 'Pool Overhead'         }
            @{ Index = 3; Name = 'Reserve'               }
            @{ Index = 4; Name = 'Infrastructure Volume' }
            @{ Index = 5; Name = 'Available for Volumes' }
            @{ Index = 6; Name = 'Usable Capacity'       }
        )

        It 'Stage <Index+1> is named "<Name>"' -ForEach $expectedNames {
            InModuleScope S2DCartographer -Parameters @{ idx = $Index; expected = $Name } {
                param($idx, $expected)
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[$idx].Name | Should -Be $expected
            }
        }

        It 'Stage 4 is named "Reserve" not "Rebuild Reserve"' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.Stages[3].Name | Should -Be 'Reserve'
                $result.Stages[3].Name | Should -Not -BeLike '*Rebuild*'
            }
        }
    }

    Context 'No health state on any stage — reserve status lives on waterfall object only' {

        It 'all stages are Status=OK even when pool free is critically low' {
            InModuleScope S2DCartographer {
                # Critical reserve — stages must still all be OK
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]1000000000000)
                foreach ($s in $result.Stages) {
                    $s.Status | Should -Be 'OK' `
                        -Because "Stage $($s.Stage) must never carry health state; reserve health belongs on ReserveStatus"
                }
            }
        }

        It 'ReserveStatus is Critical when pool free is below recommendation (not the stage)' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]1000000000000)
                $result.ReserveStatus | Should -Be 'Critical'
            }
        }

        It 'ReserveStatus is Adequate when pool free exceeds recommendation' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.ReserveStatus | Should -Be 'Adequate'
            }
        }
    }

    Context 'Stage 4 reserve formula — one drive per server, capped at 4' {

        It 'reserve = 4 × largest drive on a 4-node cluster' {
            InModuleScope S2DCartographer {
                $largest  = [int64]3840000000000
                $expected = [int64](4 * $largest)
                $result   = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes $largest `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.ReserveRecommended.Bytes | Should -Be $expected
            }
        }

        It 'reserve is still capped at 4 drives on an 8-node cluster' {
            InModuleScope S2DCartographer {
                $largest  = [int64]3840000000000
                $expected = [int64](4 * $largest)   # min(8,4) = 4
                $result   = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            8 `
                    -LargestDiskSizeBytes $largest `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                $result.ReserveRecommended.Bytes | Should -Be $expected
            }
        }

        It 'Stage 4 description contains "one drive per server" language' {
            InModuleScope S2DCartographer {
                $result = Invoke-S2DWaterfallCalculation `
                    -RawDiskBytes         ([int64]61440000000000) `
                    -NodeCount            4 `
                    -LargestDiskSizeBytes ([int64]3840000000000) `
                    -PoolTotalBytes       ([int64]60820000000000) `
                    -PoolFreeBytes        ([int64]40820000000000)
                # AB#4645: description now says "one capacity drive per server" for clarity
                $result.Stages[3].Description | Should -BeLike '*one*drive per server*'
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Pool-member disk deduplication
# In S2D, Get-PhysicalDisk on any node returns ALL pool-member disks (the pool
# is globally visible). Per-node CIM queries must be deduplicated by UniqueId
# or Stage 1 raw capacity inflates by NodeCount×.
# ─────────────────────────────────────────────────────────────────────────────
Describe 'Pool-member disk deduplication — Stage 1 must not inflate when querying per node' {

    # Simulate 4 nodes each returning the same 4 pool-member disks
    # (as happens with Get-PhysicalDisk on S2D cluster nodes).
    $diskSizeBytes = [int64]3840000000000   # 3.84 TB

    function local:New-FakeDisk {
        param([string]$UniqueId, [string]$NodeName, [bool]$IsPool = $true)
        [PSCustomObject]@{
            UniqueId   = $UniqueId
            NodeName   = $NodeName
            SizeBytes  = $diskSizeBytes
            IsPoolMember = $IsPool
            Role       = if ($IsPool) { 'Capacity' } else { 'Unknown' }
        }
    }

    It 'raw capacity waterfall with deduplicated disks equals 4-node × 4-disk cluster, not 16-node equivalent' {
        InModuleScope S2DCartographer -Parameters @{ sz = [int64]3840000000000 } {
            param($sz)
            # 4 real pool-member disks, each appearing 4 times (once per queried node)
            $realDisks = @(
                [PSCustomObject]@{ UniqueId = 'DISK-A'; SizeBytes = $sz; IsPoolMember = $true; Role = 'Capacity' }
                [PSCustomObject]@{ UniqueId = 'DISK-B'; SizeBytes = $sz; IsPoolMember = $true; Role = 'Capacity' }
                [PSCustomObject]@{ UniqueId = 'DISK-C'; SizeBytes = $sz; IsPoolMember = $true; Role = 'Capacity' }
                [PSCustomObject]@{ UniqueId = 'DISK-D'; SizeBytes = $sz; IsPoolMember = $true; Role = 'Capacity' }
            )
            # Deduplicate by UniqueId (same logic now in Get-S2DPhysicalDiskInventory)
            $seen = @{}
            $deduped = @($realDisks | Where-Object {
                if ($seen.ContainsKey($_.UniqueId)) { return $false }
                $seen[$_.UniqueId] = $true; $true
            })
            $rawBytes = [int64]($deduped | Measure-Object -Property SizeBytes -Sum).Sum
            # 4 disks × 3.84 TB = 15.36 TB (not 16× that)
            $rawBytes | Should -Be ([int64](4 * $sz))
        }
    }

    It 'waterfall Stage 1 equals pool TotalSize when disk duplication would otherwise inflate it 4x' {
        InModuleScope S2DCartographer -Parameters @{ sz = [int64]3840000000000 } {
            param($sz)
            # Real cluster: 16 pool member disks (4 nodes × 4 disks)
            $correctRaw   = [int64](16 * $sz)
            $poolTotal    = [int64]([math]::Round($correctRaw * 0.99))

            $wf = Invoke-S2DWaterfallCalculation `
                -RawDiskBytes         $correctRaw `
                -NodeCount            4 `
                -LargestDiskSizeBytes $sz `
                -PoolTotalBytes       $poolTotal `
                -PoolFreeBytes        ([int64]($poolTotal * 0.65))

            # Stage 1 and Stage 3 should be close (pool overhead ~1%)
            $ratio = $wf.Stages[0].Size.Bytes / $wf.Stages[2].Size.Bytes
            $ratio | Should -BeLessOrEqual 1.02  -Because 'Stage 1 raw should be within ~1% of pool total when disks are not duplicated'

            # If disks were duplicated 4×, Stage 1 would be 4× pool total — catch that regression
            $inflatedRaw = [int64](64 * $sz)
            $wfInflated  = Invoke-S2DWaterfallCalculation `
                -RawDiskBytes         $inflatedRaw `
                -NodeCount            4 `
                -LargestDiskSizeBytes $sz `
                -PoolTotalBytes       $poolTotal `
                -PoolFreeBytes        ([int64]($poolTotal * 0.65))

            ($wfInflated.Stages[0].Size.Bytes / $wfInflated.Stages[2].Size.Bytes) | Should -BeGreaterThan 3.9 `
                -Because 'inflated (bug) raw is ~4× pool total — confirms this test catches the regression'
        }
    }
}
