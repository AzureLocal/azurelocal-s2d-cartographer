#Requires -Version 7.0
#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Tests for -InfrastructureFile: the cluster name and the Key Vault secret come from the environment's
    infrastructure.yml (Resolve-S2DInfrastructure, Connect-S2DCluster, Invoke-S2DCartographer, Invoke-S2DCapacityWhatIf).

.DESCRIPTION
    No cluster, no Azure: every CIM, storage and Key Vault call is mocked.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
    Import-Module powershell-yaml
    $script:InfraFile = Resolve-Path (Join-Path $PSScriptRoot '..\Fixtures\infrastructure.example.yml')
    # Get-AzKeyVaultSecret is not installed on the test host; Connect-S2DCluster looks it up before it calls it.
    function global:Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    # A real CimSession object (a local DCOM session, no network) for the mocked storage cmdlets, whose parameter is typed.
    $script:FakeSession = New-CimSession -ComputerName localhost -SessionOption (New-CimSessionOption -Protocol Dcom)
}

AfterAll {
    if ($script:FakeSession) { Remove-CimSession $script:FakeSession }
    Remove-Item Function:\global:Get-AzKeyVaultSecret -ErrorAction SilentlyContinue
}

Describe 'Resolve-S2DInfrastructure' {

    It 'reads the cluster FQDN and the Key Vault secret of the LCM user' {
        InModuleScope S2DCartographer -Parameters @{ File = $script:InfraFile } {
            param($File)
            $facts = Resolve-S2DInfrastructure -InfrastructureFile $File
            $facts.ClusterName  | Should -Be 'iic-azl-01.improbability.cloud'
            $facts.KeyVaultName | Should -Be 'kv-iic-mgmt-01'
            $facts.SecretName   | Should -Be 'lcm-password'
            $facts.Username     | Should -Be 'IIC\lcm-iic-azl-01'
        }
    }

    It 'reads the local administrator when the design has no Active Directory, and leaves a non-Key-Vault reference out' {
        $file = Join-Path $TestDrive 'local.yml'
        Set-Content -LiteralPath $file -Value @(
            '_metadata:', '  schema_version: "5.6.30"', 'cluster:', '  name: "iic-azl-02"',
            'identity:', '  local_admin:', '    username: "azl-admin"', '    password: "env://IIC_LOCAL_ADMIN"')
        InModuleScope S2DCartographer -Parameters @{ File = $file } {
            param($File)
            $facts = Resolve-S2DInfrastructure -InfrastructureFile $File
            $facts.ClusterName  | Should -Be 'iic-azl-02'
            $facts.Username     | Should -Be 'azl-admin'
            $facts.KeyVaultName | Should -BeNullOrEmpty
            $facts.SecretName   | Should -BeNullOrEmpty
        }
    }

    It 'refuses a file that is not schema 5, has no cluster name, or is missing' {
        $old = Join-Path $TestDrive 'old.yml'
        Set-Content -LiteralPath $old -Value @('cluster:', '  name: "x"')
        $noName = Join-Path $TestDrive 'noname.yml'
        Set-Content -LiteralPath $noName -Value @('_metadata:', '  schema_version: "5.6.0"')
        InModuleScope S2DCartographer -Parameters @{ Old = $old; NoName = $noName; Missing = (Join-Path $TestDrive 'missing.yml') } {
            param($Old, $NoName, $Missing)
            { Resolve-S2DInfrastructure -InfrastructureFile $Old }     | Should -Throw '*not an infrastructure.yml of schema 5*'
            { Resolve-S2DInfrastructure -InfrastructureFile $NoName }  | Should -Throw '*no cluster.name*'
            { Resolve-S2DInfrastructure -InfrastructureFile $Missing } | Should -Throw '*not found*'
        }
    }
}

Describe 'Connect-S2DCluster -InfrastructureFile' {

    BeforeEach {
        Mock Get-AzKeyVaultSecret { 'Not-A-Real-Secret-1' } -ModuleName S2DCartographer
        Mock New-CimSession { $script:FakeSession } -ModuleName S2DCartographer
        Mock Remove-CimSession { } -ModuleName S2DCartographer
        Mock Get-StoragePool { [pscustomobject]@{ FriendlyName = 'S2D on iic-azl-01' } } -ModuleName S2DCartographer
        Mock Invoke-CimMethod { } -ModuleName S2DCartographer
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'iic-azl-n01' }, [pscustomobject]@{ Name = 'iic-azl-n02' }) } -ModuleName S2DCartographer
    }

    AfterEach { Disconnect-S2DCluster -ErrorAction SilentlyContinue }

    It 'connects to the cluster of the file with the Key Vault credential of the LCM user' {
        $result = Connect-S2DCluster -InfrastructureFile $script:InfraFile
        $result.ClusterName | Should -Be 'iic-azl-01.improbability.cloud'
        $result.Method      | Should -Be 'ByKeyVault'
        Should -Invoke Get-AzKeyVaultSecret -ModuleName S2DCartographer -ParameterFilter { $VaultName -eq 'kv-iic-mgmt-01' -and $Name -eq 'lcm-password' }
        Should -Invoke New-CimSession -ModuleName S2DCartographer -ParameterFilter { $ComputerName -eq 'iic-azl-01.improbability.cloud' -and $Credential.UserName -eq 'IIC\lcm-iic-azl-01' }
    }

    It 'lets an explicit -ClusterName and -Username win over the file' {
        $null = Connect-S2DCluster -InfrastructureFile $script:InfraFile -ClusterName 'iic-azl-09.improbability.cloud' -Username 'IIC\svc-iic-reader'
        Should -Invoke New-CimSession -ModuleName S2DCartographer -ParameterFilter { $ComputerName -eq 'iic-azl-09.improbability.cloud' -and $Credential.UserName -eq 'IIC\svc-iic-reader' }
    }

    It 'uses an explicit -Credential instead of the Key Vault secret' {
        $cred = [pscredential]::new('IIC\svc-iic-reader', [securestring]::new())
        $result = Connect-S2DCluster -InfrastructureFile $script:InfraFile -Credential $cred
        $result.Method | Should -Be 'ByName'
        Should -Invoke Get-AzKeyVaultSecret -ModuleName S2DCartographer -Times 0
        Should -Invoke New-CimSession -ModuleName S2DCartographer -ParameterFilter { $Credential.UserName -eq 'IIC\svc-iic-reader' -and $ComputerName -eq 'iic-azl-01.improbability.cloud' }
    }
}

Describe 'Invoke-S2DCartographer and Invoke-S2DCapacityWhatIf -InfrastructureFile' {

    It 'Invoke-S2DCartographer passes the cluster and the Key Vault secret of the file to Connect-S2DCluster, and explicit values win' {
        Mock Connect-S2DCluster { } -ModuleName S2DCartographer
        # The run stops after the connect step: no session exists, so the next step fails and the splat is what we check.
        try { Invoke-S2DCartographer -InfrastructureFile $script:InfraFile -OutputDirectory (Join-Path $TestDrive 'out') -SkipHealthChecks -Format Json } catch { Write-Verbose "stopped after connect: $_" }
        Should -Invoke Connect-S2DCluster -ModuleName S2DCartographer -ParameterFilter {
            $ClusterName -eq 'iic-azl-01.improbability.cloud' -and $KeyVaultName -eq 'kv-iic-mgmt-01' -and $SecretName -eq 'lcm-password' -and $Username -eq 'IIC\lcm-iic-azl-01'
        }
        Mock Connect-S2DCluster { } -ModuleName S2DCartographer
        try { Invoke-S2DCartographer -InfrastructureFile $script:InfraFile -ClusterName 'iic-azl-09' -KeyVaultName 'kv-other' -SecretName 'other-secret' -OutputDirectory (Join-Path $TestDrive 'out2') -SkipHealthChecks -Format Json } catch { Write-Verbose "stopped after connect: $_" }
        Should -Invoke Connect-S2DCluster -ModuleName S2DCartographer -ParameterFilter {
            $ClusterName -eq 'iic-azl-09' -and $KeyVaultName -eq 'kv-other' -and $SecretName -eq 'other-secret' -and $Username -eq 'IIC\lcm-iic-azl-01'
        }
    }

    It 'Invoke-S2DCapacityWhatIf has a live set that takes the infrastructure file' {
        $command = Get-Command Invoke-S2DCapacityWhatIf
        $command.ParameterSets.Name | Should -Contain 'LiveInfrastructure'
        $command.Parameters['InfrastructureFile'].ParameterSets.Keys | Should -Be @('LiveInfrastructure')
        Mock Connect-S2DCluster { } -ModuleName S2DCartographer
        try { Invoke-S2DCapacityWhatIf -InfrastructureFile $script:InfraFile -AddNodes 1 } catch { Write-Verbose "stopped after connect: $_" }
        Should -Invoke Connect-S2DCluster -ModuleName S2DCartographer -ParameterFilter { $InfrastructureFile -eq $script:InfraFile.Path }
    }
}
