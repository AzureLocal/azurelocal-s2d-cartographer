#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'Resolve-S2DNodeFqdn' {

    It 'returns the short name unchanged when it is already a FQDN' {
        InModuleScope S2DCartographer {
            Resolve-S2DNodeFqdn -ShortName 'node01.contoso.local' -ClusterFqdn 'clus.contoso.local' |
                Should -Be 'node01.contoso.local'
        }
    }

    It 'appends the cluster domain suffix to a short node name' {
        InModuleScope S2DCartographer {
            Resolve-S2DNodeFqdn -ShortName 'tplabs-01-n01' -ClusterFqdn 'tplabs-clus01.azrl.mgmt' |
                Should -Be 'tplabs-01-n01.azrl.mgmt'
        }
    }

    It 'handles multi-label domain suffixes correctly' {
        InModuleScope S2DCartographer {
            Resolve-S2DNodeFqdn -ShortName 'host' -ClusterFqdn 'c.dept.division.corp.example.com' |
                Should -Be 'host.dept.division.corp.example.com'
        }
    }

    It 'returns the short name when cluster is also a short name and DNS does not resolve' {
        InModuleScope S2DCartographer {
            # Use a deliberately invalid short name that will not resolve via DNS so we
            # exercise the final fall-through branch deterministically.
            $result = Resolve-S2DNodeFqdn -ShortName 'notarealhost-s2dcartographer' -ClusterFqdn 'clus-short'
            $result | Should -Be 'notarealhost-s2dcartographer'
        }
    }

    It 'returns the short name when no cluster FQDN is supplied and DNS fails' {
        InModuleScope S2DCartographer {
            $result = Resolve-S2DNodeFqdn -ShortName 'notarealhost-s2dcartographer2'
            $result | Should -Be 'notarealhost-s2dcartographer2'
        }
    }
}

Describe 'Get-S2DPhysicalDiskInventory fan-out targets' -Skip:(-not $IsWindows) {

    BeforeEach {
        InModuleScope S2DCartographer {
            $Script:S2DSession = @{
                ClusterName    = 'clus.azrl.mgmt'
                ClusterFqdn    = 'clus.azrl.mgmt'
                Nodes          = @('node01', 'node02')
                NodeTargets    = @{ 'node01' = 'node01.azrl.mgmt'; 'node02' = 'node02.azrl.mgmt' }
                CimSession     = $null
                PSSession      = $null
                IsConnected    = $true
                IsLocal        = $false
                Authentication = 'Negotiate'
                Credential     = $null
                CollectedData  = @{}
            }
        }
    }

    It 'uses the FQDN from NodeTargets when opening per-node CIM sessions' {
        # Store captured names in the module-level $Script: scope via InModuleScope,
        # then read them back after the call. This avoids Pester's scope isolation
        # between the mock scriptblock (runs in module scope) and the test script scope.
        InModuleScope S2DCartographer {
            $Script:_testCapturedNames = @()

            $stubClusterCim = [PSCustomObject]@{ ComputerName = 'clus.azrl.mgmt' }
            Mock Resolve-S2DSession { $stubClusterCim } -ModuleName S2DCartographer

            Mock New-CimSession -ModuleName S2DCartographer -MockWith {
                param($ComputerName)
                $Script:_testCapturedNames += $ComputerName
                [PSCustomObject]@{ ComputerName = $ComputerName }
            } -ParameterFilter { $ComputerName }

            Mock Remove-CimSession -ModuleName S2DCartographer { } -ParameterFilter { $true }
            Mock Get-S2DPhysicalDiskData -ModuleName S2DCartographer { @() }
            Mock Get-S2DDiskData -ModuleName S2DCartographer { @() }
            Mock Get-S2DStorageReliabilityData -ModuleName S2DCartographer { $null }
            Mock Get-S2DStoragePoolData -ModuleName S2DCartographer { @() }
            Mock Get-S2DPoolPhysicalDiskData -ModuleName S2DCartographer { @() }

            $null = Get-S2DPhysicalDiskInventory

            $Script:_testCapturedNames | Should -Contain 'node01.azrl.mgmt'
            $Script:_testCapturedNames | Should -Contain 'node02.azrl.mgmt'
            $Script:_testCapturedNames | Should -Not -Contain 'node01'
            $Script:_testCapturedNames | Should -Not -Contain 'node02'
        }
    }

    It 'falls back to the short name when NodeTargets map is absent' {
        InModuleScope S2DCartographer {
            $Script:S2DSession.NodeTargets = @{}
            $Script:_testCapturedNames = @()

            $stubClusterCim = [PSCustomObject]@{ ComputerName = 'clus.azrl.mgmt' }
            Mock Resolve-S2DSession { $stubClusterCim } -ModuleName S2DCartographer

            Mock New-CimSession -ModuleName S2DCartographer -MockWith {
                param($ComputerName)
                $Script:_testCapturedNames += $ComputerName
                [PSCustomObject]@{ ComputerName = $ComputerName }
            } -ParameterFilter { $ComputerName }

            Mock Remove-CimSession -ModuleName S2DCartographer { } -ParameterFilter { $true }
            Mock Get-S2DPhysicalDiskData -ModuleName S2DCartographer { @() }
            Mock Get-S2DDiskData -ModuleName S2DCartographer { @() }
            Mock Get-S2DStorageReliabilityData -ModuleName S2DCartographer { $null }
            Mock Get-S2DStoragePoolData -ModuleName S2DCartographer { @() }
            Mock Get-S2DPoolPhysicalDiskData -ModuleName S2DCartographer { @() }

            $null = Get-S2DPhysicalDiskInventory

            $Script:_testCapturedNames | Should -Contain 'node01'
            $Script:_testCapturedNames | Should -Contain 'node02'
        }
    }
}
