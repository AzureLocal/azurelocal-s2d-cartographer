#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
# Rack aware / nested resiliency and mixed-media reserve.
# Learn: azure-local/concepts/rack-aware-cluster-requirements and
#        windows-server/storage/storage-spaces/plan-volumes (Reserve capacity).
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Rack aware waterfall' {
    It '1+1 (2 machines) uses two-way mirror, 50 percent' {
        InModuleScope S2DCartographer {
            $d = [int64]3840000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($d * 8) -NodeCount 2 -LargestDiskSizeBytes $d -RackAware -ResiliencyFactor 3.0
            $wf.BlendedEfficiencyPercent | Should -Be 50.0
            $wf.Stages[6].Description | Should -Match 'Rack Level Nested Mirror'
            $wf.Stages[6].Description | Should -Not -Match 'ASSUMED'
        }
    }
    It '<n> machines use four-way mirror, 25 percent' -ForEach @(@{ n = 4 }, @{ n = 6 }, @{ n = 8 }) {
        InModuleScope S2DCartographer -Parameters @{ n = $n } {
            $d = [int64]3840000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($d * 8 * $n) -NodeCount $n -LargestDiskSizeBytes $d -RackAware -ResiliencyFactor 2.0
            $wf.BlendedEfficiencyPercent | Should -Be 25.0
            $wf.UsableCapacity.Bytes | Should -Be ([int64]($wf.AvailableForVolumes.Bytes / 4))
        }
    }
    It 'ignores a caller supplied three-way factor (three-way is not allowed on rack aware)' {
        InModuleScope S2DCartographer {
            $d = [int64]3840000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($d * 32) -NodeCount 4 -LargestDiskSizeBytes $d -RackAware -ResiliencyFactor 3.0
            $wf.BlendedEfficiencyPercent | Should -Not -Be 33.3
        }
    }
}

Describe 'Nested two-way mirror (not rack aware)' {
    It 'NumberOfDataCopies=4 is 25 percent in the efficiency table and the waterfall' {
        InModuleScope S2DCartographer {
            (Get-S2DResiliencyEfficiency -ResiliencySettingName Mirror -NumberOfDataCopies 4).EfficiencyPercent | Should -Be 25.0
            $d = [int64]3840000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ($d * 8) -NodeCount 2 -LargestDiskSizeBytes $d -ResiliencyFactor 4.0 -ResiliencyName 'nested two-way mirror (4 copies)'
            $wf.BlendedEfficiencyPercent | Should -Be 25.0
        }
    }
}

Describe 'Mixed media reserve (NVMe + SSD + HDD)' {
    It 'reserve is min(nodes,4) x (largest SSD + largest HDD)' {
        InModuleScope S2DCartographer {
            $ssd = [int64]3840000000000; $hdd = [int64]16000000000000
            $r = Get-S2DReserveCalculation -NodeCount 6 -LargestCapacityDriveSizeBytes $hdd -PoolFreeBytes ([int64]100e12) -LargestSsdDriveSizeBytes $ssd -LargestHddDriveSizeBytes $hdd
            $r.IsMixedMedia | Should -BeTrue
            $r.ReserveRecommendedBytes | Should -Be (4 * ($ssd + $hdd))
        }
    }
    It 'without both media sizes the single-drive rule applies' {
        InModuleScope S2DCartographer {
            $hdd = [int64]16000000000000
            $r = Get-S2DReserveCalculation -NodeCount 3 -LargestCapacityDriveSizeBytes $hdd -PoolFreeBytes ([int64]100e12)
            $r.IsMixedMedia | Should -BeFalse
            $r.ReserveRecommendedBytes | Should -Be (3 * $hdd)
        }
    }
    It 'waterfall stage 4 uses the mixed reserve' {
        InModuleScope S2DCartographer {
            $ssd = [int64]3840000000000; $hdd = [int64]16000000000000
            $wf = Invoke-S2DWaterfallCalculation -RawDiskBytes ([int64]200e12) -NodeCount 2 -LargestDiskSizeBytes $hdd -LargestSsdDriveSizeBytes $ssd -LargestHddDriveSizeBytes $hdd -ResiliencyFactor 2.0
            $wf.Stages[3].Description | Should -Match 'one SSD plus one HDD per server'
            ($wf.Stages[2].Size.Bytes - $wf.Stages[3].Size.Bytes) | Should -Be (2 * ($ssd + $hdd))
        }
    }
}

Describe 'Get-S2DCapacityWaterfall (live path, fixtures only)' {
    BeforeEach {
        InModuleScope S2DCartographer {
            function script:New-Disk([string] $Node, [string] $Media, [int64] $Size, [string] $Role) {
                [PSCustomObject]@{ NodeName = $Node; Role = $Role; Usage = 'Auto-Select'; MediaType = $Media; SizeBytes = $Size; IsPoolMember = $true }
            }
            $disks = @()
            foreach ($n in 1..4) {
                $disks += New-Disk "node0$n" 'NVMe' ([int64]1600000000000) 'Cache'
                $disks += New-Disk "node0$n" 'SSD'  ([int64]3840000000000) 'Capacity'
                $disks += New-Disk "node0$n" 'HDD'  ([int64]16000000000000) 'Capacity'
            }
            $pool = [S2DStoragePool]::new()
            $pool.TotalSize     = [S2DCapacity]::new([int64]300e12)
            $pool.RemainingSize = [S2DCapacity]::new([int64]200e12)
            $pool.AllocatedSize = [S2DCapacity]::new([int64]100e12)
            $pool.OvercommitRatio = 0.1
            $iv = [S2DVolume]::new()
            $iv.FriendlyName = 'Infrastructure_example'
            $iv.IsInfrastructureVolume = $true
            $iv.FootprintOnPool = [S2DCapacity]::new([int64]1e12)
            $Script:S2DSession = @{
                ClusterName = 'clus01.contoso.com'; ClusterFqdn = 'clus01.contoso.com'
                Nodes = @('node01', 'node02', 'node03', 'node04'); CimSession = $null; PSSession = $null
                IsConnected = $true; IsLocal = $true
                CollectedData = @{ PhysicalDisks = $disks; StoragePool = $pool; Volumes = @($iv) }
            }
        }
    }
    It 'applies the one SSD plus one HDD per server reserve on NVMe + SSD + HDD' {
        InModuleScope S2DCartographer {
            $wf = Get-S2DCapacityWaterfall -WarningAction SilentlyContinue
            $wf.ReserveRecommended.Bytes | Should -Be (4 * ([int64]3840000000000 + [int64]16000000000000))
        }
    }
    It '-RackAware on four machines reports four-way mirror (25 percent)' {
        InModuleScope S2DCartographer {
            $wf = Get-S2DCapacityWaterfall -RackAware -WarningAction SilentlyContinue
            $wf.BlendedEfficiencyPercent | Should -Be 25.0
        }
    }
}
