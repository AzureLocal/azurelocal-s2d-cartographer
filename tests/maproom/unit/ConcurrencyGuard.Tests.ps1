#Requires -Version 7.0
#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Tests for the concurrent collection guard (AB#279) and empty-data safeguards.

.DESCRIPTION
    Covers:
      (a) A second concurrent Invoke-S2DCartographer invocation throws while one is in progress.
      (b) The guard is released after a failed run so a subsequent run can succeed.
      (c) Empty/null disk, pool, and volume data does not throw and yields a sane empty result.

    All external CIM/cluster calls are mocked — no live cluster required.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Concurrent Collection Guard' {

    # ── Helpers ───────────────────────────────────────────────────────────────
    # These BeforeEach / AfterEach blocks run inside InModuleScope so they can
    # manipulate module-scoped state directly.

    BeforeEach {
        InModuleScope S2DCartographer {
            # Reset guard and session before each test.
            $Script:S2DCollectionInProgress = $false
            $Script:S2DSession = @{
                ClusterName    = $null
                ClusterFqdn    = $null
                Nodes          = @()
                NodeTargets    = @{}
                CimSession     = $null
                PSSession      = $null
                IsConnected    = $false
                IsLocal        = $false
                Authentication = 'Negotiate'
                Credential     = $null
                CollectedData  = @{}
            }
        }
    }

    Context '(a) Second concurrent invocation throws' {

        It 'throws "A collection is already in progress" when guard is set' {
            InModuleScope S2DCartographer {
                # Simulate an in-progress run by setting the guard directly.
                $Script:S2DCollectionInProgress = $true

                # Invoke-S2DCartographer must check the flag before doing any
                # real work. Mock Connect-S2DCluster to prevent actual connections
                # (the throw should happen before Connect is ever called).
                Mock Connect-S2DCluster { } -ModuleName S2DCartographer

                { Invoke-S2DCartographer -ClusterName 'fake-cluster' -Format Json -OutputDirectory $TestDrive } |
                    Should -Throw -ExpectedMessage '*A collection is already in progress*'
            }
        }

        It 'throw message contains "Invoke-S2DCartographer"' {
            InModuleScope S2DCartographer {
                $Script:S2DCollectionInProgress = $true
                Mock Connect-S2DCluster { } -ModuleName S2DCartographer

                $err = $null
                try {
                    Invoke-S2DCartographer -ClusterName 'fake-cluster' -Format Json -OutputDirectory $TestDrive
                }
                catch {
                    $err = $_
                }
                $err | Should -Not -BeNullOrEmpty
                $err.Exception.Message | Should -Match 'collection is already in progress'
            }
        }

        It 'guard flag is still set after the second call throws (first run still owns it)' {
            InModuleScope S2DCartographer {
                $Script:S2DCollectionInProgress = $true
                Mock Connect-S2DCluster { } -ModuleName S2DCartographer

                try {
                    Invoke-S2DCartographer -ClusterName 'fake-cluster' -Format Json -OutputDirectory $TestDrive
                }
                catch { }

                # The flag must still be true — the "first" run still owns the guard.
                $Script:S2DCollectionInProgress | Should -BeTrue
            }
        }
    }

    Context '(b) Guard is released after a failed run so a subsequent run can succeed' {

        It 'guard is false after Invoke-S2DCartographer fails mid-run' {
            InModuleScope S2DCartographer {
                # Mock Connect-S2DCluster to throw, simulating a failed run.
                Mock Connect-S2DCluster { throw 'Simulated connection failure' } -ModuleName S2DCartographer

                try {
                    Invoke-S2DCartographer -ClusterName 'bad-cluster' -Format Json -OutputDirectory $TestDrive
                }
                catch { }

                $Script:S2DCollectionInProgress | Should -BeFalse
            }
        }

        It 'a subsequent Invoke-S2DCartographer call succeeds after the guard is released' {
            InModuleScope S2DCartographer {
                # First call: Connect throws — guard must be released in finally.
                Mock Connect-S2DCluster { throw 'Simulated connection failure' } -ModuleName S2DCartographer

                try {
                    Invoke-S2DCartographer -ClusterName 'bad-cluster' -Format Json -OutputDirectory $TestDrive
                }
                catch { }

                # Guard must be false now.
                $Script:S2DCollectionInProgress | Should -BeFalse

                # Second call should not be blocked by the guard.
                # It will still fail (Connect still throws) but the error must be
                # the connection error, NOT a "collection already in progress" error.
                $err = $null
                try {
                    Invoke-S2DCartographer -ClusterName 'bad-cluster' -Format Json -OutputDirectory $TestDrive
                }
                catch {
                    $err = $_
                }
                $err | Should -Not -BeNullOrEmpty
                $err.Exception.Message | Should -Not -Match 'collection is already in progress'
            }
        }

        It 'guard is false when Invoke-S2DCartographer is not running' {
            InModuleScope S2DCartographer {
                $Script:S2DCollectionInProgress | Should -BeFalse
            }
        }
    }
}

Describe 'Empty-Data Safeguards' {

    BeforeEach {
        InModuleScope S2DCartographer {
            $Script:S2DCollectionInProgress = $false
            # Establish a minimal "connected" local session with no real CIM objects.
            $Script:S2DSession = @{
                ClusterName    = 'empty-cluster'
                ClusterFqdn    = 'empty-cluster.local'
                Nodes          = @('node01')
                NodeTargets    = @{}
                CimSession     = $null
                PSSession      = $null
                IsConnected    = $true
                IsLocal        = $true
                Authentication = 'Negotiate'
                Credential     = $null
                CollectedData  = @{
                    PhysicalDisks = @()
                    StoragePool   = $null
                    Volumes       = @()
                    CacheTier     = $null
                }
            }
        }
    }

    Context '(c) Get-S2DCapacityWaterfall with no capacity disks' {

        It 'does not throw when CollectedData PhysicalDisks is an empty array' {
            InModuleScope S2DCartographer {
                { Get-S2DCapacityWaterfall } | Should -Not -Throw
            }
        }

        It 'does not throw when CollectedData PhysicalDisks is null' {
            InModuleScope S2DCartographer {
                $Script:S2DSession.CollectedData['PhysicalDisks'] = $null
                { Get-S2DCapacityWaterfall } | Should -Not -Throw
            }
        }

        It 'returns an S2DCapacityWaterfall object (not null) with empty disk data' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }

        It 'RawCapacity.Bytes is 0 when no capacity disks present' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).RawCapacity.Bytes | Should -Be 0
            }
        }

        It 'UsableCapacity.Bytes is 0 when no capacity disks present' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).UsableCapacity.Bytes | Should -Be 0
            }
        }

        It 'produces exactly 7 stages even with no capacity disk data' {
            InModuleScope S2DCartographer {
                (Get-S2DCapacityWaterfall).Stages.Count | Should -Be 7
            }
        }

        It 'caches a zeroed waterfall in CollectedData when no disks found' {
            InModuleScope S2DCartographer {
                Get-S2DCapacityWaterfall | Out-Null
                $Script:S2DSession.CollectedData['CapacityWaterfall'] | Should -Not -BeNullOrEmpty
                $Script:S2DSession.CollectedData['CapacityWaterfall'].GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }
    }

    Context '(c) Get-S2DHealthStatus with empty disk/pool/volume data' {

        It 'does not throw when all data is empty' {
            InModuleScope S2DCartographer {
                { Get-S2DHealthStatus } | Should -Not -Throw
            }
        }

        It 'returns a non-empty array of health check objects' {
            InModuleScope S2DCartographer {
                $result = @(Get-S2DHealthStatus)
                $result.Count | Should -BeGreaterThan 0
            }
        }

        It 'DiskSymmetry check is Warn (not Pass) when no pool-member disks found' {
            InModuleScope S2DCartographer {
                $checks = @(Get-S2DHealthStatus)
                $diskCheck = $checks | Where-Object CheckName -eq 'DiskSymmetry'
                $diskCheck | Should -Not -BeNullOrEmpty
                $diskCheck.Status | Should -Be 'Warn'
            }
        }

        It 'DiskSymmetry warn message mentions no pool-member disks found' {
            InModuleScope S2DCartographer {
                $checks = @(Get-S2DHealthStatus)
                $diskCheck = $checks | Where-Object CheckName -eq 'DiskSymmetry'
                $diskCheck.Details | Should -Match 'No pool-member disks found'
            }
        }

        It 'VolumeHealth check is Pass when volumes array is empty' {
            InModuleScope S2DCartographer {
                $checks = @(Get-S2DHealthStatus)
                $volCheck = $checks | Where-Object CheckName -eq 'VolumeHealth'
                $volCheck | Should -Not -BeNullOrEmpty
                # 0 degraded volumes → Pass (all 0 volumes are healthy is still Pass)
                $volCheck.Status | Should -Be 'Pass'
            }
        }

        It 'DiskHealth check is Pass when pool-member disk array is empty' {
            InModuleScope S2DCartographer {
                $checks = @(Get-S2DHealthStatus)
                $diskHealth = $checks | Where-Object CheckName -eq 'DiskHealth'
                $diskHealth | Should -Not -BeNullOrEmpty
                $diskHealth.Status | Should -Be 'Pass'
            }
        }

        It 'overall health rollup is not null or empty' {
            InModuleScope S2DCartographer {
                Get-S2DHealthStatus | Out-Null
                $Script:S2DSession.CollectedData['OverallHealth'] | Should -Not -BeNullOrEmpty
            }
        }

        It 'RebuildCapacity check is Pass when pool is null (no pool data)' {
            InModuleScope S2DCartographer {
                $checks = @(Get-S2DHealthStatus)
                $rebuildCheck = $checks | Where-Object CheckName -eq 'RebuildCapacity'
                $rebuildCheck | Should -Not -BeNullOrEmpty
                # Pool is null → falls through to the "pool data unavailable" branch → Pass
                $rebuildCheck.Status | Should -Be 'Pass'
            }
        }
    }

    Context '(c) Get-S2DCapacityWaterfall with null pool but non-empty disks' {

        BeforeEach {
            InModuleScope S2DCartographer {
                # Provide capacity disks but no pool object — simulates a cluster
                # where pool data collection failed but disk data succeeded.
                $Script:S2DSession.CollectedData['PhysicalDisks'] = @(
                    [PSCustomObject]@{
                        NodeName     = 'node01'
                        Role         = 'Capacity'
                        Usage        = 'Auto-Select'
                        SizeBytes    = [int64]3840000000000
                        IsPoolMember = $true
                    }
                )
                $Script:S2DSession.CollectedData['StoragePool'] = $null
                $Script:S2DSession.CollectedData['Volumes']     = @()
            }
        }

        It 'does not throw when pool is null but disks are present' {
            InModuleScope S2DCartographer {
                { Get-S2DCapacityWaterfall } | Should -Not -Throw
            }
        }

        It 'Stage 1 RawCapacity.Bytes reflects the single disk even without a pool' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                $result.RawCapacity.Bytes | Should -Be ([int64]3840000000000)
            }
        }

        It 'RawCapacity.Bytes is greater than 0 and Stage 1 bytes match disk size' {
            InModuleScope S2DCartographer {
                $result = Get-S2DCapacityWaterfall
                # One 3.84 TB capacity disk — Stage 1 must equal its raw bytes.
                $result.RawCapacity.Bytes | Should -Be ([int64]3840000000000)
            }
        }
    }

    Context '(c) Get-S2DStoragePoolInfo with no virtual disks' {

        It 'provisionedBytes is 0 (not null/exception) when no virtual disks found' {
            InModuleScope S2DCartographer {
                # Provide a fake pool via session mock — exercise the local branch
                # by running locally (no CimSession, no PSSession).
                Mock Get-S2DStoragePoolData {
                    return [PSCustomObject]@{
                        FriendlyName              = 'S2D on test-cluster'
                        HealthStatus              = 'Healthy'
                        OperationalStatus         = 'OK'
                        IsReadOnly                = $false
                        IsPrimordial              = $false
                        Size                      = [int64]10000000000000
                        AllocatedSize             = [int64]0
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'
                        WriteCacheSizeDefault     = [int64]0
                    }
                } -ModuleName S2DCartographer

                Mock Get-S2DVirtualDiskData { return @() } -ModuleName S2DCartographer
                Mock Get-S2DStoragePoolResiliencyData { return @() } -ModuleName S2DCartographer
                Mock Get-S2DStoragePoolTierData { return @() } -ModuleName S2DCartographer
                Mock Resolve-S2DSession { return $null } -ModuleName S2DCartographer

                { Get-S2DStoragePoolInfo } | Should -Not -Throw
            }
        }

        It 'ProvisionedSize is null when no virtual disks exist (provisionedBytes = 0)' {
            InModuleScope S2DCartographer {
                Mock Get-S2DStoragePoolData {
                    return [PSCustomObject]@{
                        FriendlyName              = 'S2D on test-cluster'
                        HealthStatus              = 'Healthy'
                        OperationalStatus         = 'OK'
                        IsReadOnly                = $false
                        IsPrimordial              = $false
                        Size                      = [int64]10000000000000
                        AllocatedSize             = [int64]0
                        FaultDomainAwarenessDefault = 'StorageScaleUnit'
                        WriteCacheSizeDefault     = [int64]0
                    }
                } -ModuleName S2DCartographer

                Mock Get-S2DVirtualDiskData { return @() } -ModuleName S2DCartographer
                Mock Get-S2DStoragePoolResiliencyData { return @() } -ModuleName S2DCartographer
                Mock Get-S2DStoragePoolTierData { return @() } -ModuleName S2DCartographer
                Mock Resolve-S2DSession { return $null } -ModuleName S2DCartographer

                $pool = Get-S2DStoragePoolInfo
                # ProvisionedSize is $null when provisionedBytes = 0 (per existing code: if > 0)
                $pool.ProvisionedSize | Should -BeNullOrEmpty
            }
        }
    }
}
