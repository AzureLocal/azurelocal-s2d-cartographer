#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Get-S2DStoragePoolInfo' {

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

    Context 'Return type and capacity fields' {
        It 'returns an S2DStoragePool object' {
            InModuleScope S2DCartographer {
                $totalBytes = [int64]60820000000000
                $allocBytes = [int64]36000000000000

                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = $totalBytes; AllocatedSize = $allocBytes
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData { @() }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData           { @() }

                $result = Get-S2DStoragePoolInfo

                $result                        | Should -Not -BeNullOrEmpty
                $result.GetType().Name         | Should -Be 'S2DStoragePool'
                $result.FriendlyName           | Should -Be 'S2D on azlocal-iic-s2d-01'
                $result.HealthStatus           | Should -Be 'Healthy'
            }
        }

        It 'TotalSize, AllocatedSize, RemainingSize are S2DCapacity objects with correct bytes' {
            InModuleScope S2DCartographer {
                $totalBytes = [int64]60820000000000
                $allocBytes = [int64]36000000000000

                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = $totalBytes; AllocatedSize = $allocBytes
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData { @() }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData           { @() }

                $result = Get-S2DStoragePoolInfo

                $result.TotalSize.GetType().Name      | Should -Be 'S2DCapacity'
                $result.AllocatedSize.GetType().Name  | Should -Be 'S2DCapacity'
                $result.RemainingSize.GetType().Name  | Should -Be 'S2DCapacity'
                $result.TotalSize.Bytes               | Should -Be $totalBytes
                $result.AllocatedSize.Bytes           | Should -Be $allocBytes
                $result.RemainingSize.Bytes           | Should -Be ($totalBytes - $allocBytes)
            }
        }

        It 'ProvisionedSize equals sum of virtual disk sizes' {
            InModuleScope S2DCartographer {
                $vdiskSize = [int64]9000000000000   # 9 TB per volume

                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = [int64]60820000000000; AllocatedSize = [int64]36000000000000
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData { @() }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData {
                    @(
                        [PSCustomObject]@{ Size = $vdiskSize },
                        [PSCustomObject]@{ Size = $vdiskSize },
                        [PSCustomObject]@{ Size = $vdiskSize },
                        [PSCustomObject]@{ Size = $vdiskSize }
                    )
                }

                $result = Get-S2DStoragePoolInfo

                $result.ProvisionedSize.Bytes | Should -Be ([int64]($vdiskSize * 4))
            }
        }

        It 'OvercommitRatio exceeds 1.0 when thin-provisioned volumes exceed pool size' {
            InModuleScope S2DCartographer {
                $totalBytes    = [int64]60820000000000
                $thinVdisk     = [int64]20000000000000   # 4 × 20 TB = 80 TB > 60.8 TB pool

                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = $totalBytes; AllocatedSize = [int64]36000000000000
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData { @() }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData { @(1..4 | ForEach-Object { [PSCustomObject]@{ Size = $thinVdisk } }) }

                $result = Get-S2DStoragePoolInfo

                $result.OvercommitRatio | Should -BeGreaterThan 1.0
            }
        }
    }

    Context 'ResiliencySettings and StorageTiers' {
        It 'populates ResiliencySettings from pool resiliency data' {
            InModuleScope S2DCartographer {
                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = [int64]60820000000000; AllocatedSize = [int64]36000000000000
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData {
                    @(
                        [PSCustomObject]@{ Name = 'Mirror'; NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; NumberOfColumns = 1 },
                        [PSCustomObject]@{ Name = 'Parity'; NumberOfDataCopies = 1; PhysicalDiskRedundancy = 2; NumberOfColumns = 4 }
                    )
                }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData           { @() }

                $result = Get-S2DStoragePoolInfo

                $result.ResiliencySettings.Count | Should -Be 2
                ($result.ResiliencySettings | Where-Object Name -eq 'Mirror').NumberOfDataCopies | Should -Be 3
                ($result.ResiliencySettings | Where-Object Name -eq 'Parity').NumberOfColumns     | Should -Be 4
            }
        }
    }

    Context 'Caching and error handling' {
        It 'caches result in CollectedData after successful collection' {
            InModuleScope S2DCartographer {
                Mock Get-S2DStoragePoolData {
                    [PSCustomObject]@{
                        IsPrimordial = $false; FriendlyName = 'S2D on azlocal-iic-s2d-01'
                        HealthStatus = 'Healthy'; OperationalStatus = 'OK'; IsReadOnly = $false
                        Size = [int64]60820000000000; AllocatedSize = [int64]30000000000000
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'; WriteCacheSizeDefault = [int64]0
                    }
                }
                Mock Get-S2DStoragePoolResiliencyData { @() }
                Mock Get-S2DStoragePoolTierData       { @() }
                Mock Get-S2DVirtualDiskData           { @() }

                Get-S2DStoragePoolInfo | Out-Null

                $Script:S2DSession.CollectedData['StoragePool']                | Should -Not -BeNullOrEmpty
                $Script:S2DSession.CollectedData['StoragePool'].GetType().Name | Should -Be 'S2DStoragePool'
            }
        }

        It 'returns null and writes a warning when no non-primordial pool is found' {
            InModuleScope S2DCartographer {
                Mock Get-S2DStoragePoolData { @() }
                Mock Write-Warning {}

                $result = Get-S2DStoragePoolInfo

                $result | Should -BeNullOrEmpty
                Should -Invoke Write-Warning -Scope It -Times 1
            }
        }
    }
}
