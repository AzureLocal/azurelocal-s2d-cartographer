#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Get-S2DHealthStatus' {

    BeforeEach {
        InModuleScope S2DCartographer {
            # 4-node IIC all-NVMe cluster, all healthy and symmetric
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
            $pool.FriendlyName      = 'S2D on azlocal-iic-s2d-01'
            $pool.HealthStatus      = 'Healthy'
            $pool.OperationalStatus = 'OK'
            $pool.IsReadOnly        = $false
            $pool.TotalSize         = [S2DCapacity]::new([int64]60820000000000)
            $pool.AllocatedSize     = [S2DCapacity]::new([int64]20000000000000)
            $pool.RemainingSize     = [S2DCapacity]::new([int64]40820000000000)
            $pool.ProvisionedSize   = [S2DCapacity]::new([int64]6000000000000)
            $pool.OvercommitRatio   = 0.099

            $vol1 = [S2DVolume]::new()
            $vol1.FriendlyName           = 'UserStorage_1'
            $vol1.HealthStatus           = 'Healthy'
            $vol1.OperationalStatus      = 'OK'
            $vol1.IsInfrastructureVolume = $false
            $vol1.ProvisioningType       = 'Fixed'
            $vol1.NumberOfDataCopies     = 3
            $vol1.EfficiencyPercent      = 33.3
            $vol1.Size                   = [S2DCapacity]::new([int64]3000000000000)
            $vol1.FootprintOnPool        = [S2DCapacity]::new([int64]9000000000000)

            $vol2 = [S2DVolume]::new()
            $vol2.FriendlyName           = 'Infrastructure_aabbccddeeff00112233445566778899'
            $vol2.HealthStatus           = 'Healthy'
            $vol2.OperationalStatus      = 'OK'
            $vol2.IsInfrastructureVolume = $true
            $vol2.EfficiencyPercent      = 33.3
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

    Context 'Output shape' {
        It 'returns exactly 12 S2DHealthCheck objects on a healthy cluster' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result.Count | Should -Be 12
                $result | ForEach-Object { $_.GetType().Name | Should -Be 'S2DHealthCheck' }
            }
        }

        It 'all 11 checks contain non-empty CheckName, Severity, Status, and Details' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                $result | ForEach-Object {
                    $_.CheckName | Should -Not -BeNullOrEmpty
                    $_.Severity  | Should -Not -BeNullOrEmpty
                    $_.Status    | Should -Not -BeNullOrEmpty
                    $_.Details   | Should -Not -BeNullOrEmpty
                }
            }
        }

        It 'filters results when -CheckName specifies a subset' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus -CheckName 'DiskHealth', 'NVMeWear'
                $result.Count | Should -Be 2
                $result.CheckName | Should -Contain 'DiskHealth'
                $result.CheckName | Should -Contain 'NVMeWear'
            }
        }
    }

    Context 'Healthy cluster — all checks pass' {
        It 'all checks are Pass on the healthy IIC cluster' {
            InModuleScope S2DCartographer {
                $failing = @(Get-S2DHealthStatus | Where-Object { $_.Status -ne 'Pass' })
                $failing.Count | Should -Be 0
            }
        }

        It 'sets OverallHealth to Healthy in CollectedData' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $Script:S2DSession.CollectedData['OverallHealth'] | Should -Be 'Healthy'
            }
        }

        It 'InfrastructureVolume passes when infra volume is healthy' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'InfrastructureVolume').Status | Should -Be 'Pass'
            }
        }

        It 'CacheTierHealth passes for all-flash software-cache cluster' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'CacheTierHealth').Status | Should -Be 'Pass'
            }
        }

        It 'DiskSymmetry passes when all nodes have equal disk counts' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'DiskSymmetry').Status | Should -Be 'Pass'
            }
        }

        It 'DiskHealth passes when all disks are Healthy' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'DiskHealth').Status | Should -Be 'Pass'
            }
        }

        It 'NVMeWear passes when all drives are below 80% wear' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'NVMeWear').Status | Should -Be 'Pass'
            }
        }
    }

    Context 'DiskSymmetry check' {
        It 'warns when one node has fewer disks than peers' {
            InModuleScope S2DCartographer {
                $disks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @(
                    $disks | Where-Object { -not ($_.NodeName -eq 'azl-iic-n04' -and $_.SerialNumber -in 'IIC01N04D3','IIC01N04D4') }
                )
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'DiskSymmetry').Status | Should -Be 'Warn'
            }
        }
    }

    Context 'DiskHealth check' {
        It 'fails when any physical disk is non-healthy' {
            InModuleScope S2DCartographer {
                $disks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
                $degraded = [PSCustomObject]@{
                    NodeName          = $disks[0].NodeName
                    FriendlyName      = $disks[0].FriendlyName
                    SerialNumber      = $disks[0].SerialNumber
                    MediaType         = 'NVMe'
                    Model             = $disks[0].Model
                    FirmwareVersion   = $disks[0].FirmwareVersion
                    Role              = 'Capacity'
                    SizeBytes         = $disks[0].SizeBytes
                    WearPercentage    = 10
                    HealthStatus      = 'Warning'
                    OperationalStatus = 'Degraded'
                }
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @($degraded) + @($disks | Select-Object -Skip 1)

                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'DiskHealth').Status | Should -Be 'Fail'
            }
        }
    }

    Context 'NVMeWear check' {
        It 'warns when an NVMe drive exceeds 80% wear' {
            InModuleScope S2DCartographer {
                $disks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
                $worn = [PSCustomObject]@{
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
                }
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @($worn) + @($disks | Select-Object -Skip 1)

                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'NVMeWear').Status | Should -Be 'Warn'
            }
        }
    }

    Context 'ReserveAdequacy check' {
        It 'passes when waterfall ReserveStatus is Adequate' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ReserveAdequacy').Status | Should -Be 'Pass'
            }
        }

        It 'warns when waterfall ReserveStatus is Warning' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Warning'
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ReserveAdequacy').Status | Should -Be 'Warn'
            }
        }

        It 'fails when waterfall ReserveStatus is Critical' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Critical'
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ReserveAdequacy').Status | Should -Be 'Fail'
            }
        }
    }

    Context 'OverallHealth rollup' {
        It 'is Critical when a Critical-severity check has Status Fail' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CapacityWaterfall'].ReserveStatus = 'Critical'
                Get-S2DHealthStatus | Out-Null
                $Script:S2DSession.CollectedData['OverallHealth'] | Should -Be 'Critical'
            }
        }

        It 'is Warning when only Warning-severity checks are non-Pass' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['CacheTier'].CacheState = 'Degraded'
                Get-S2DHealthStatus | Out-Null
                $Script:S2DSession.CollectedData['OverallHealth'] | Should -Be 'Warning'
            }
        }
    }

    Context 'ThinOvercommit check' {
        It 'passes on fixed-only cluster' {
            InModuleScope S2DCartographer {
                # vol1 is Fixed in the default fixture
                ($result = Get-S2DHealthStatus)
                ($result | Where-Object CheckName -eq 'ThinOvercommit').Status | Should -Be 'Pass'
            }
        }

        It 'warns when thin max potential footprint exceeds 80% of pool total' {
            InModuleScope S2DCartographer {
                # Thin volume: Size=30TB, 3 copies → max footprint=90TB, pool=60.82TB → 148% > 80%
                $thinVol = [S2DVolume]::new()
                $thinVol.FriendlyName           = 'ThinStorage_1'
                $thinVol.IsInfrastructureVolume = $false
                $thinVol.ProvisioningType       = 'Thin'
                $thinVol.NumberOfDataCopies     = 3
                $thinVol.HealthStatus           = 'Healthy'
                $thinVol.OperationalStatus      = 'OK'
                $thinVol.Size                   = [S2DCapacity]::new([int64]30000000000000)   # 30 TB
                $thinVol.FootprintOnPool        = [S2DCapacity]::new([int64]3000000000000)    # 3 TB current
                $thinVol.AllocatedSize          = [S2DCapacity]::new([int64]1000000000000)
                $thinVol.MaxPotentialFootprint  = [S2DCapacity]::new([int64]90000000000000)   # 90 TB = 30×3
                $thinVol.ThinGrowthHeadroom     = [S2DCapacity]::new([int64]29000000000000)

                $Script:S2DSession.CollectedData['Volumes'] = @($thinVol, $Script:S2DSession.CollectedData['Volumes'][1])
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ThinOvercommit').Status | Should -BeIn 'Warn','Fail'
            }
        }

        It 'fails when thin max potential footprint exceeds pool total' {
            InModuleScope S2DCartographer {
                # Thin volume: Size=25TB, 3 copies → max footprint=75TB > pool 60.82TB
                $thinVol = [S2DVolume]::new()
                $thinVol.FriendlyName           = 'ThinStorage_1'
                $thinVol.IsInfrastructureVolume = $false
                $thinVol.ProvisioningType       = 'Thin'
                $thinVol.NumberOfDataCopies     = 3
                $thinVol.HealthStatus           = 'Healthy'
                $thinVol.OperationalStatus      = 'OK'
                $thinVol.Size                   = [S2DCapacity]::new([int64]25000000000000)
                $thinVol.FootprintOnPool        = [S2DCapacity]::new([int64]3000000000000)
                $thinVol.AllocatedSize          = [S2DCapacity]::new([int64]1000000000000)
                $thinVol.MaxPotentialFootprint  = [S2DCapacity]::new([int64]75000000000000)   # 75TB > 60.82TB pool
                $thinVol.ThinGrowthHeadroom     = [S2DCapacity]::new([int64]24000000000000)

                $Script:S2DSession.CollectedData['Volumes'] = @($thinVol, $Script:S2DSession.CollectedData['Volumes'][1])
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ThinOvercommit').Status | Should -Be 'Fail'
            }
        }
    }

    Context 'ThinReserveRisk check' {
        It 'passes on fixed-only cluster' {
            InModuleScope S2DCartographer {
                ($result = Get-S2DHealthStatus)
                ($result | Where-Object CheckName -eq 'ThinReserveRisk').Status | Should -Be 'Pass'
            }
        }

        It 'warns when thin growth would consume the rebuild reserve' {
            InModuleScope S2DCartographer {
                # Pool free=40.82TB, reserve=15.36TB. Thin vol: max footprint 35TB, current 3TB → growth=32TB
                # Free after max growth = 40.82 - 32 = 8.82TB < reserve 15.36TB → Warn
                $thinVol = [S2DVolume]::new()
                $thinVol.FriendlyName           = 'ThinStorage_1'
                $thinVol.IsInfrastructureVolume = $false
                $thinVol.ProvisioningType       = 'Thin'
                $thinVol.NumberOfDataCopies     = 3
                $thinVol.HealthStatus           = 'Healthy'
                $thinVol.OperationalStatus      = 'OK'
                $thinVol.Size                   = [S2DCapacity]::new([int64]11000000000000)   # 11 TB
                $thinVol.FootprintOnPool        = [S2DCapacity]::new([int64]3000000000000)    # 3 TB current
                $thinVol.AllocatedSize          = [S2DCapacity]::new([int64]1000000000000)
                $thinVol.MaxPotentialFootprint  = [S2DCapacity]::new([int64]33000000000000)   # 33TB max
                $thinVol.ThinGrowthHeadroom     = [S2DCapacity]::new([int64]10000000000000)

                $Script:S2DSession.CollectedData['Volumes'] = @($thinVol, $Script:S2DSession.CollectedData['Volumes'][1])
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'ThinReserveRisk').Status | Should -BeIn 'Warn','Fail'
            }
        }
    }

    Context 'FirmwareConsistency check' {
        It 'warns when drives of the same model have different firmware versions' {
            InModuleScope S2DCartographer {
                $disks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
                $mixed = [PSCustomObject]@{
                    NodeName          = $disks[0].NodeName
                    FriendlyName      = $disks[0].FriendlyName
                    SerialNumber      = $disks[0].SerialNumber
                    MediaType         = 'NVMe'
                    Model             = 'INTEL SSDPE2KX040T8'
                    FirmwareVersion   = 'VCV10999'   # different from 'VCV10162'
                    Role              = 'Capacity'
                    SizeBytes         = $disks[0].SizeBytes
                    WearPercentage    = 10
                    HealthStatus      = 'Healthy'
                    OperationalStatus = 'OK'
                }
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @($mixed) + @($disks | Select-Object -Skip 1)

                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'FirmwareConsistency').Status | Should -Be 'Warn'
            }
        }

        It 'passes when all drives of the same model share the same firmware' {
            InModuleScope S2DCartographer {
                $result = Get-S2DHealthStatus
                ($result | Where-Object CheckName -eq 'FirmwareConsistency').Status | Should -Be 'Pass'
            }
        }
    }
}
