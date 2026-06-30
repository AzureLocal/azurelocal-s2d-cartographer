#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Get-S2DVolumeMap' {

    BeforeEach {
        InModuleScope S2DCartographer {
            $Script:S2DSession = @{
                ClusterName   = 'azlocal-iic-s2d-01'
                ClusterFqdn   = 'azlocal-iic-s2d-01.iic.local'
                Nodes         = @('azl-iic-n01','azl-iic-n02','azl-iic-n03','azl-iic-n04')
                CimSession    = $null
                PSSession     = $null
                IsConnected   = $true
                IsLocal       = $true
                CollectedData = @{}
            }
        }
    }

    Context 'Return type and basic fields' {
        It 'returns S2DVolume objects for each virtual disk' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName           = 'UserStorage_1'
                        ResiliencySettingName  = 'Mirror'
                        NumberOfDataCopies     = 3
                        PhysicalDiskRedundancy = 2
                        ProvisioningType       = 'Fixed'
                        Size                   = [int64]9000000000000
                        FootprintOnPool        = [int64]27000000000000
                        AllocatedSize          = [int64]0
                        FileSystem             = 'CSVFS_ReFS'
                        OperationalStatus      = 'OK'
                        HealthStatus           = 'Healthy'
                    })
                }

                $result = @(Get-S2DVolumeMap)

                $result.Count                    | Should -Be 1
                $result[0].GetType().Name        | Should -Be 'S2DVolume'
                $result[0].FriendlyName          | Should -Be 'UserStorage_1'
                $result[0].ResiliencySettingName | Should -Be 'Mirror'
                $result[0].NumberOfDataCopies    | Should -Be 3
                $result[0].FileSystem            | Should -Be 'CSVFS_ReFS'
                $result[0].HealthStatus          | Should -Be 'Healthy'
                $result[0].OperationalStatus     | Should -Be 'OK'
            }
        }

        It 'wraps Size and FootprintOnPool in S2DCapacity objects' {
            InModuleScope S2DCartographer {
                $sizeBytes     = [int64]9000000000000
                $footprintBytes = [int64]27000000000000

                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName = 'UserStorage_1'; ResiliencySettingName = 'Mirror'
                        NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                        Size = $sizeBytes; FootprintOnPool = $footprintBytes; AllocatedSize = [int64]0
                        FileSystem = 'CSVFS_ReFS'; OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                    })
                }

                $result = Get-S2DVolumeMap

                $result[0].Size.GetType().Name            | Should -Be 'S2DCapacity'
                $result[0].FootprintOnPool.GetType().Name | Should -Be 'S2DCapacity'
                $result[0].Size.Bytes                     | Should -Be $sizeBytes
                $result[0].FootprintOnPool.Bytes          | Should -Be $footprintBytes
            }
        }

        It 'maps 4 IIC workload volumes correctly' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @(1..4 | ForEach-Object {
                        [PSCustomObject]@{
                            FriendlyName = "UserStorage_$_"; ResiliencySettingName = 'Mirror'
                            NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        }
                    })
                }

                $result = Get-S2DVolumeMap

                $result.Count | Should -Be 4
                $result | ForEach-Object { $_.ResiliencySettingName | Should -Be 'Mirror' }
                $result | ForEach-Object { $_.NumberOfDataCopies | Should -Be 3 }
            }
        }
    }

    Context 'Infrastructure volume detection' {
        It 'flags volumes matching Infrastructure_<guid> name pattern as infrastructure' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName = 'Infrastructure_a1b2c3d4-e5f6-7890-abcd-ef1234567890'
                        ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                        PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                        Size = [int64]524288000000; FootprintOnPool = [int64]1572864000000
                        AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                        OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                    })
                }

                $result = Get-S2DVolumeMap

                $result[0].IsInfrastructureVolume | Should -BeTrue
            }
        }

        It 'flags ClusterPerformanceHistory as infrastructure by name' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName = 'ClusterPerformanceHistory'
                        ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                        PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                        Size = [int64]53687091200; FootprintOnPool = [int64]161061273600
                        AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                        OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                    })
                }

                $result = Get-S2DVolumeMap

                $result[0].IsInfrastructureVolume | Should -BeTrue
            }
        }

        It 'flags volumes smaller than 600 GiB as infrastructure by size heuristic' {
            InModuleScope S2DCartographer {
                # 400 GiB — no infra name, but below 600 GiB threshold
                $smallSize = [int64](400 * 1073741824)

                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName = 'SomeSmallVolume'
                        ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                        PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                        Size = $smallSize; FootprintOnPool = [int64]($smallSize * 3)
                        AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                        OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                    })
                }

                $result = Get-S2DVolumeMap

                $result[0].IsInfrastructureVolume | Should -BeTrue
            }
        }

        It 'does not flag user workload volumes as infrastructure' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @([PSCustomObject]@{
                        FriendlyName = 'VM-Workload'
                        ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                        PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                        Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                        AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                        OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                    })
                }

                $result = Get-S2DVolumeMap

                $result[0].IsInfrastructureVolume | Should -BeFalse
            }
        }

        It 'correctly separates infra and workload volumes in a mixed list' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @(
                        [PSCustomObject]@{
                            FriendlyName = 'Infrastructure_aabbccdd-1234-5678-abcd-ef1234567890'
                            ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                            PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]524288000000; FootprintOnPool = [int64]1572864000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        },
                        [PSCustomObject]@{
                            FriendlyName = 'UserStorage_1'
                            ResiliencySettingName = 'Mirror'; NumberOfDataCopies = 3
                            PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        }
                    )
                }

                $result = Get-S2DVolumeMap

                $result.Count                                                                        | Should -Be 2
                ($result | Where-Object FriendlyName -like 'Infrastructure*').IsInfrastructureVolume | Should -BeTrue
                ($result | Where-Object FriendlyName -eq 'UserStorage_1').IsInfrastructureVolume     | Should -BeTrue
            }
        }
    }

    Context 'Filtering and caching' {
        It 'filters to named volumes when -VolumeName is specified' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @(
                        [PSCustomObject]@{
                            FriendlyName = 'UserStorage_1'; ResiliencySettingName = 'Mirror'
                            NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        },
                        [PSCustomObject]@{
                            FriendlyName = 'UserStorage_2'; ResiliencySettingName = 'Mirror'
                            NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        }
                    )
                }

                $result = @(Get-S2DVolumeMap -VolumeName 'UserStorage_1')

                $result.Count          | Should -Be 1
                $result[0].FriendlyName | Should -Be 'UserStorage_1'
            }
        }

        It 'warns and returns empty array when no virtual disks found' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData { @() }
                Mock Write-Warning {}

                $result = @(Get-S2DVolumeMap)

                $result.Count | Should -Be 0
                Should -Invoke Write-Warning -Scope It -Times 1
            }
        }

        It 'caches all volumes (unfiltered) in CollectedData' {
            InModuleScope S2DCartographer {
                Mock Get-S2DVirtualDiskData {
                    @(
                        [PSCustomObject]@{
                            FriendlyName = 'UserStorage_1'; ResiliencySettingName = 'Mirror'
                            NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        },
                        [PSCustomObject]@{
                            FriendlyName = 'UserStorage_2'; ResiliencySettingName = 'Mirror'
                            NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; ProvisioningType = 'Fixed'
                            Size = [int64]9000000000000; FootprintOnPool = [int64]27000000000000
                            AllocatedSize = [int64]0; FileSystem = 'CSVFS_ReFS'
                            OperationalStatus = 'OK'; HealthStatus = 'Healthy'
                        }
                    )
                }

                Get-S2DVolumeMap -VolumeName 'UserStorage_1' | Out-Null

                # CollectedData should have all volumes, not just the filtered one
                $Script:S2DSession.CollectedData['Volumes'].Count | Should -Be 2
            }
        }
    }
}
