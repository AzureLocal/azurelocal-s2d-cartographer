#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    # Build a minimal snapshot JSON for the Snapshot parameter-set tests
    # 4-node cluster, 4 × 3.84 TB capacity disks per node, 3-way mirror
    $script:snapshotPath = Join-Path $TestDrive 'baseline.json'
    $snapshot = [ordered]@{
        SchemaVersion = '1.0'
        NodeCount     = 4
        PhysicalDisks = @(foreach ($n in 1..4) {
            foreach ($d in 1..4) {
                [ordered]@{
                    NodeName     = "azl-n0$n"
                    Role         = 'Capacity'
                    Usage        = 'Auto-Select'
                    SizeBytes    = 3840000000000
                    IsPoolMember = $true
                }
            }
        })
        StoragePool = [ordered]@{
            TotalSize     = [ordered]@{ Bytes = 60820000000000 }
            RemainingSize = [ordered]@{ Bytes = 40820000000000 }
            ResiliencySettings = @(
                [ordered]@{ Name = 'Mirror'; NumberOfDataCopies = 3; PhysicalDiskRedundancy = 2; NumberOfColumns = 1 }
            )
        }
        Volumes = @(
            [ordered]@{
                FriendlyName           = 'Infrastructure_aabb'
                IsInfrastructureVolume = $true
                Size                   = [ordered]@{ Bytes = 524288000000 }
                FootprintOnPool        = [ordered]@{ Bytes = 1572864000000 }
            }
        )
    }
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content $script:snapshotPath -Encoding utf8
}

Describe 'Invoke-S2DCapacityWhatIf' {

    Context 'Result object structure' {
        It 'returns an S2DWhatIfResult PSCustomObject' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r                                   | Should -Not -BeNullOrEmpty
                $r.PSObject.TypeNames[0]             | Should -Be 'S2DWhatIfResult'
            }
        }

        It 'result contains BaselineWaterfall and ProjectedWaterfall' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r.BaselineWaterfall              | Should -Not -BeNullOrEmpty
                $r.ProjectedWaterfall             | Should -Not -BeNullOrEmpty
                $r.BaselineWaterfall.GetType().Name  | Should -Be 'S2DCapacityWaterfall'
                $r.ProjectedWaterfall.GetType().Name | Should -Be 'S2DCapacityWaterfall'
            }
        }

        It 'DeltaStages contains exactly 7 entries' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                @($r.DeltaStages).Count | Should -Be 7
            }
        }

        It 'DeltaUsableTiB is numeric' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                ($r.DeltaUsableTiB -is [double] -or $r.DeltaUsableTiB -is [int]) | Should -BeTrue
            }
        }
    }

    Context 'No-op scenario (no modifications)' {
        It 'DeltaUsableTiB rounds to 0 when no changes applied' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                # The projected pool is always re-estimated as raw × 0.99, so the byte values
                # may differ slightly from the snapshot's actual pool size. TiB rounds to 2dp
                # and the delta should round to 0.00.
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                [math]::Abs($r.BaselineWaterfall.UsableCapacity.TiB - $r.ProjectedWaterfall.UsableCapacity.TiB) |
                    Should -BeLessOrEqual 0.01
            }
        }

        It 'DeltaUsableTiB is 0 when no changes applied' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r.DeltaUsableTiB | Should -Be 0
            }
        }

        It 'ScenarioLabel is "No changes (baseline)" when no changes applied' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r.ScenarioLabel | Should -Be 'No changes (baseline)'
            }
        }

        It 'BaselineNodeCount and ProjectedNodeCount are both 4' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r.BaselineNodeCount  | Should -Be 4
                $r.ProjectedNodeCount | Should -Be 4
            }
        }
    }

    Context '-AddNodes' {
        It 'ProjectedNodeCount increases by AddNodes' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                $r.ProjectedNodeCount | Should -Be 6
            }
        }

        It 'projected usable capacity exceeds baseline when nodes are added' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                $r.ProjectedWaterfall.UsableCapacity.Bytes | Should -BeGreaterThan $r.BaselineWaterfall.UsableCapacity.Bytes
            }
        }

        It 'DeltaUsableTiB is positive when nodes are added' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                $r.DeltaUsableTiB | Should -BeGreaterThan 0
            }
        }

        It 'ScenarioLabel contains "+2 nodes"' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                $r.ScenarioLabel | Should -Match '\+2 nodes'
            }
        }
    }

    Context '-AddDisksPerNode' {
        It 'projected raw bytes increase when disks are added per node' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddDisksPerNode 2 -PassThru
                $r.ProjectedWaterfall.RawCapacity.Bytes | Should -BeGreaterThan $r.BaselineWaterfall.RawCapacity.Bytes
            }
        }

        It 'ScenarioLabel contains "+2 disks/node"' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddDisksPerNode 2 -PassThru
                $r.ScenarioLabel | Should -Match '\+2 disks/node'
            }
        }
    }

    Context '-ReplaceDiskSizeTB' {
        It 'projected raw bytes reflect new disk size' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                # 16 disks × 7.68 TB = 122.88 TB raw
                $r        = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -ReplaceDiskSizeTB 7.68 -PassThru
                $expected = [int64](16 * 7680000000000)
                $r.ProjectedWaterfall.RawCapacity.Bytes | Should -Be $expected
            }
        }

        It 'ScenarioLabel mentions disk replacement' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -ReplaceDiskSizeTB 7.68 -PassThru
                $r.ScenarioLabel | Should -Match 'Replace disks'
            }
        }
    }

    Context '-ChangeResiliency' {
        It 'projected usable capacity is higher switching from 3-way to 2-way mirror' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -ChangeResiliency 2 -PassThru
                $r.ProjectedWaterfall.UsableCapacity.Bytes | Should -BeGreaterThan $r.BaselineWaterfall.UsableCapacity.Bytes
            }
        }

        It 'ScenarioLabel mentions resiliency change' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -ChangeResiliency 2 -PassThru
                $r.ScenarioLabel | Should -Match 'Resiliency.*2-way mirror'
            }
        }

        It 'ProjectedWaterfall BlendedEfficiencyPercent is 50.0 for 2-way mirror' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -ChangeResiliency 2 -PassThru
                $r.ProjectedWaterfall.BlendedEfficiencyPercent | Should -Be 50.0
            }
        }
    }

    Context 'Composite scenario (AddNodes + AddDisksPerNode + ChangeResiliency)' {
        It 'ScenarioLabel contains all three scenario parts' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap `
                    -AddNodes 2 -AddDisksPerNode 2 -ChangeResiliency 2 -PassThru
                $r.ScenarioLabel | Should -Match '\+2 nodes'
                $r.ScenarioLabel | Should -Match '\+2 disks/node'
                $r.ScenarioLabel | Should -Match 'Resiliency.*2-way mirror'
            }
        }

        It 'projected capacity exceeds baseline on all three improvements' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap `
                    -AddNodes 2 -AddDisksPerNode 2 -ChangeResiliency 2 -PassThru
                $r.ProjectedWaterfall.UsableCapacity.Bytes | Should -BeGreaterThan $r.BaselineWaterfall.UsableCapacity.Bytes
            }
        }
    }

    Context 'DeltaStages consistency' {
        It 'every DeltaStage has Stage, Name, BaselineTiB, ProjectedTiB, DeltaTiB' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                foreach ($ds in $r.DeltaStages) {
                    $ds.Stage       | Should -Not -BeNullOrEmpty
                    $ds.Name        | Should -Not -BeNullOrEmpty
                    ($null -ne $ds.BaselineTiB)  | Should -BeTrue
                    ($null -ne $ds.ProjectedTiB) | Should -BeTrue
                    ($null -ne $ds.DeltaTiB)     | Should -BeTrue
                }
            }
        }

        It 'DeltaUsableTiB equals Stage 7 DeltaTiB (pipeline terminus)' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r           = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -AddNodes 2 -PassThru
                $stage7Delta = ($r.DeltaStages | Where-Object { $_.Stage -eq 7 }).DeltaTiB
                $r.DeltaUsableTiB | Should -Be $stage7Delta
            }
        }
    }

    Context 'Error handling' {
        It 'throws when snapshot file does not exist' {
            InModuleScope S2DCartographer {
                { Invoke-S2DCapacityWhatIf -BaselineSnapshot 'C:\does\not\exist.json' -PassThru } |
                    Should -Throw
            }
        }

        It 'throws when JSON lacks SchemaVersion' {
            InModuleScope S2DCartographer -Parameters @{ td = $TestDrive } {
                $badJson = Join-Path $td 'bad.json'
                '{"NotASnapshot":true}' | Set-Content $badJson
                { Invoke-S2DCapacityWhatIf -BaselineSnapshot $badJson -PassThru } |
                    Should -Throw
            }
        }
    }

    Context 'Report output' {
        It 'writes HTML report when OutputDirectory specified' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath; td = $TestDrive } {
                $outDir = Join-Path $td 'whatif-out'
                Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap `
                    -AddNodes 1 -OutputDirectory $outDir -Format Html
                $htmlFiles = @(Get-ChildItem $outDir -Filter '*.html' -ErrorAction SilentlyContinue)
                $htmlFiles.Count | Should -BeGreaterThan 0
            }
        }

        It 'writes JSON report when Format includes Json' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath; td = $TestDrive } {
                $outDir = Join-Path $td 'whatif-out-json'
                Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap `
                    -AddNodes 1 -OutputDirectory $outDir -Format @('Html','Json')
                $jsonFiles = @(Get-ChildItem $outDir -Filter '*.json' -ErrorAction SilentlyContinue)
                $jsonFiles.Count | Should -BeGreaterThan 0
            }
        }

        It 'returns result when PassThru specified without OutputDirectory' {
            InModuleScope S2DCartographer -Parameters @{ snap = $script:snapshotPath } {
                $r = Invoke-S2DCapacityWhatIf -BaselineSnapshot $snap -PassThru
                $r | Should -Not -BeNullOrEmpty
            }
        }
    }
}
