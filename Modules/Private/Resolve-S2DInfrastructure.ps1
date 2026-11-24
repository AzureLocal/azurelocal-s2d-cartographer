function Resolve-S2DInfrastructure {
    <#
    .SYNOPSIS
        Reads the connection facts of an Azure Local cluster from the environment's infrastructure.yml (schema 5).

    .DESCRIPTION
        Returns ClusterName, KeyVaultName, SecretName and Username for Connect-S2DCluster, Invoke-S2DCartographer and
        Invoke-S2DCapacityWhatIf, so a run needs no value typed twice:

          cluster.name                                    ClusterName (with identity.active_directory.domain_fqdn
                                                          appended, so the name is a FQDN)
          identity.active_directory.lcm_user.password     KeyVaultName and SecretName when it is a keyvault://<vault>/<secret>
          (a design without Active Directory:             reference; Username is the lcm_user name with the NetBIOS domain
           identity.local_admin.password)                 in front (DOMAIN\user)

        A password that is an env://, file:// or command:// reference leaves KeyVaultName and SecretName empty: this module
        reads Key Vault only. An explicit parameter on the calling cmdlet always wins over what this returns. The file
        needs the powershell-yaml module.

    .PARAMETER InfrastructureFile
        Path to infrastructure.yml (the full file, or a cut with _metadata.scope s2d_cartographer).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $InfrastructureFile
    )

    if (-not (Test-Path -LiteralPath $InfrastructureFile -PathType Leaf)) {
        throw "Infrastructure file not found: $InfrastructureFile"
    }
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
            throw "Reading an infrastructure file needs the powershell-yaml module. Install with: Install-Module powershell-yaml -Scope CurrentUser"
        }
        Import-Module powershell-yaml -ErrorAction Stop
    }

    $data = ConvertFrom-Yaml (Get-Content -LiteralPath $InfrastructureFile -Raw)

    function Get-Value {
        param($Node, [string] $Path)
        foreach ($segment in $Path -split '\.') {
            if ($Node -is [System.Collections.IDictionary] -and $Node.Contains($segment)) { $Node = $Node[$segment] } else { return $null }
        }
        $Node
    }

    $version = [string](Get-Value $data '_metadata.schema_version')
    if ($version -notmatch '^5(\.|$)') {
        throw "$InfrastructureFile is not an infrastructure.yml of schema 5 (_metadata.schema_version is '$version')."
    }

    $name = [string](Get-Value $data 'cluster.name')
    if (-not $name) { throw "$InfrastructureFile has no cluster.name." }
    $domain = [string](Get-Value $data 'identity.active_directory.domain_fqdn')
    $netbios = [string](Get-Value $data 'identity.active_directory.netbios_name')

    # The account that reads the cluster: the LCM user of an Active Directory design, else the local administrator.
    $account = if ($domain) { Get-Value $data 'identity.active_directory.lcm_user' } else { Get-Value $data 'identity.local_admin' }
    $user = if ($account -is [System.Collections.IDictionary]) { [string]$account['username'] } else { '' }
    $reference = if ($account -is [System.Collections.IDictionary]) { [string]$account['password'] } else { '' }

    $vault = $null; $secret = $null
    if ($reference -match '^keyvault://(?<vault>[^/]+)/(?<secret>[^/]+)$') { $vault = $Matches['vault']; $secret = $Matches['secret'] }

    $userName = if ($user -and $domain -and $netbios -and $user -notmatch '[\\@]') { "$netbios\$user" } elseif ($user) { $user } else { $null }

    [pscustomobject]@{
        ClusterName  = $(if ($domain -and $name -notlike '*.*') { "$name.$domain" } else { $name })
        KeyVaultName = $vault
        SecretName   = $secret
        Username     = $userName
        Source       = (Resolve-Path -LiteralPath $InfrastructureFile).Path
    }
}