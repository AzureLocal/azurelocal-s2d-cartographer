function Connect-S2DCluster {
    <#
    .SYNOPSIS
        Establishes an authenticated session to an S2D-enabled Failover Cluster.

    .DESCRIPTION
        Connect-S2DCluster creates and stores a module-scoped session that all other
        S2DCartographer cmdlets use. After connecting, you do not need to pass credentials
        to each collector.

        Supports five connection methods:
          1. ClusterName + Credential       — WinRM/CIM to a cluster node
          2. CimSession                     — re-use an existing CimSession
          3. PSSession                      — re-use an existing PSSession
          4. Local                          — run directly on a cluster node (no remoting)
          5. ClusterName + KeyVaultName     — retrieve credentials from Azure Key Vault

        The cmdlet validates that the target has S2D enabled via Get-ClusterS2D before
        storing the session.

    .PARAMETER ClusterName
        DNS name or FQDN of the Failover Cluster (e.g. "c01-prd-bal" or "c01-prd-bal.corp.local").

    .PARAMETER Credential
        PSCredential to authenticate with. Prompted interactively if not supplied.

    .PARAMETER Authentication
        Authentication method passed to New-CimSession. Defaults to 'Negotiate', which
        auto-selects NTLM or Kerberos and works in both domain-joined and workgroup/lab
        environments. Use 'Kerberos' to enforce Kerberos explicitly.

    .PARAMETER CimSession
        An existing CimSession to use instead of creating a new one.

    .PARAMETER PSSession
        An existing PSSession to use instead of creating a new one.

    .PARAMETER Local
        Run against the local machine. Use this when executing directly on a cluster node.

    .PARAMETER KeyVaultName
        Azure Key Vault name to retrieve credentials from. Requires Az.KeyVault.

    .PARAMETER SecretName
        Name of the Key Vault secret containing the password (username encoded as secret tags or prefixed by convention).

    .PARAMETER Username
        Optional explicit username to pair with the Key Vault secret's password. When not provided,
        the module reads the username from the secret's ContentType tag (convention: 'domain\user').
        Use this when the secret does not have a ContentType populated — for example, when an
        infrastructure automation pipeline writes the password without also setting the tag.

    .EXAMPLE
        Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)

    .EXAMPLE
        # Non-domain or cross-domain client — use Negotiate to avoid Kerberos failure
        Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential) -Authentication Negotiate

    .EXAMPLE
        $cim = New-CimSession -ComputerName "node01" -Credential $cred
        Connect-S2DCluster -CimSession $cim

    .EXAMPLE
        Connect-S2DCluster -Local

    .EXAMPLE
        Connect-S2DCluster -ClusterName "c01-prd-bal" -KeyVaultName "kv-hcs-01" -SecretName "cluster-admin"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The secret is read from Azure Key Vault at run time (Get-AzKeyVaultSecret) and has to be wrapped into a PSCredential; it is never a literal in source.')]
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName',      Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'ByKeyVault',  Mandatory, Position = 0)]
        [string] $ClusterName,

        [Parameter(ParameterSetName = 'ByName')]
        [PSCredential] $Credential,

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateSet('Default','Digest','Negotiate','Basic','Kerberos','ClientCertificate','CredSsp')]
        [string] $Authentication = 'Negotiate',

        [Parameter(ParameterSetName = 'ByCimSession', Mandatory)]
        [CimSession] $CimSession,

        [Parameter(ParameterSetName = 'ByPSSession', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession] $PSSession,

        [Parameter(ParameterSetName = 'Local', Mandatory)]
        [switch] $Local,

        [Parameter(ParameterSetName = 'ByKeyVault', Mandatory)]
        [string] $KeyVaultName,

        [Parameter(ParameterSetName = 'ByKeyVault', Mandatory)]
        [string] $SecretName,

        [Parameter(ParameterSetName = 'ByKeyVault')]
        [string] $Username
    )

    # Ensure not already connected
    if ($Script:S2DSession.IsConnected) {
        Write-Warning "Already connected to cluster '$($Script:S2DSession.ClusterName)'. Call Disconnect-S2DCluster first."
        return
    }

    switch ($PSCmdlet.ParameterSetName) {

        'ByName' {
            # Remote CIM/WinRM without explicit credentials almost always fails on
            # workgroup or cross-domain hosts with a cryptic 'Access is denied'.
            # Prompt interactively instead so the user gets a credential dialog,
            # not a stack trace. Callers running non-interactively must supply
            # -Credential up front, -Local to skip remoting, or a prebuilt
            # -CimSession / -PSSession.
            if (-not $Credential) {
                $credMessage = @(
                    "Enter credentials for cluster '$ClusterName'."
                    ''
                    'Use one of these username formats:'
                    '  DOMAIN\user       (e.g. MGMT\svc.azl.local)'
                    '  user@fqdn.domain  (e.g. svc.azl.local@contoso.com)'
                    ''
                    'A plain local username will not authenticate against a domain cluster.'
                ) -join [Environment]::NewLine
                $Credential = Get-Credential -Message $credMessage
                if (-not $Credential) {
                    throw "Credentials are required to connect to cluster '$ClusterName'. Re-run with -Credential, or use -Local when running on a cluster node."
                }
            }

            # Resolve the cluster name to a FQDN before opening the CIM session.
            # On workgroup / non-domain-joined hosts, TrustedHosts is usually set
            # to FQDNs; a short name will fail WinRM server-identity checks with
            # 0x8009030e even when credentials are correct. Pass-through when
            # the caller already supplied a FQDN.
            #
            # Resolution order:
            #   1. TrustedHosts — if the user already trusts an FQDN that starts
            #      with the short name, use it. This is the most reliable source
            #      on workgroup hosts where AD DNS suffixes are not configured.
            #   2. DNS forward+reverse via GetHostEntry.
            #   3. Fall through to the short name and let the try/catch emit a
            #      precise remediation message.
            $clusterTarget = $ClusterName
            if ($ClusterName -notlike '*.*') {
                $resolvedVia = $null

                try {
                    $trustedHostsRaw = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
                    if ($trustedHostsRaw) {
                        $entries = $trustedHostsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        $hostMatches = $entries | Where-Object { $_ -like "$ClusterName.*" }
                        if ($hostMatches) {
                            $clusterTarget = ($hostMatches | Select-Object -First 1)
                            $resolvedVia = 'TrustedHosts'
                            if (@($hostMatches).Count -gt 1) {
                                Write-Verbose "Multiple TrustedHosts entries match '$ClusterName.*' — using '$clusterTarget'. Other matches: $((@($hostMatches) | Select-Object -Skip 1) -join ', ')"
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "TrustedHosts lookup failed: $_"
                }

                if (-not $resolvedVia) {
                    try {
                        $dnsEntry = [System.Net.Dns]::GetHostEntry($ClusterName)
                        if ($dnsEntry -and $dnsEntry.HostName -and $dnsEntry.HostName -like '*.*') {
                            $clusterTarget = $dnsEntry.HostName
                            $resolvedVia = 'DNS'
                        }
                    }
                    catch {
                        Write-Verbose "DNS lookup for '$ClusterName' failed: $_. Trying short name as-is."
                    }
                }

                if ($resolvedVia) {
                    Write-Verbose "Resolved cluster short name '$ClusterName' to FQDN '$clusterTarget' via $resolvedVia."
                }
            }

            Write-Verbose "Connecting to cluster '$clusterTarget' via CIM/WinRM (Authentication: $Authentication)..."
            $cimParams = @{
                ComputerName   = $clusterTarget
                Authentication = $Authentication
                ErrorAction    = 'Stop'
            }
            $cimParams['Credential'] = $Credential
            try {
                $session = New-CimSession @cimParams
            }
            catch {
                # Most common WinRM failures on workgroup/cross-domain hosts:
                #   0x8009030e — TrustedHosts or credential mismatch
                #   Access is denied — wrong credentials
                #   No such host is known — DNS / name resolution
                # Surface a precise remediation instead of the raw exception.
                $rawMessage = $_.Exception.Message
                $isDomainJoined = try { (Get-CimInstance Win32_ComputerSystem).PartOfDomain } catch { $false }
                $remedy = @(
                    "Failed to open CIM session to '$clusterTarget' (from input '$ClusterName') under authentication '$Authentication':"
                    "  $rawMessage"
                    ''
                    'Common causes and fixes:'
                    "  1. TrustedHosts does not contain the cluster FQDN. On this host, run:"
                    "       Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$clusterTarget' -Concatenate -Force"
                    "  2. Credentials are wrong. The username you supplied was '$($Credential.UserName)'."
                    '     For domain accounts use  DOMAIN\\user  or  user@fqdn.domain. Re-run and supply a cluster admin credential.'
                    '  3. You passed a short cluster name that does not resolve via DNS. Re-run with the FQDN, for example:'
                    "       Invoke-S2DCartographer -ClusterName '$ClusterName.<your-domain>' -Credential (Get-Credential)"
                    '  4. Run locally on a cluster node with  Connect-S2DCluster -Local  if you do not need remote access.'
                )
                if (-not $isDomainJoined) {
                    $remedy += '  (Detected: this host is not domain-joined, which is the most common trigger for 0x8009030e.)'
                }
                throw ($remedy -join [Environment]::NewLine)
            }
            $Script:S2DSession.CimSession     = $session
            $Script:S2DSession.ClusterName    = $ClusterName
            $Script:S2DSession.ClusterFqdn    = $clusterTarget
            $Script:S2DSession.Authentication = $Authentication
            $Script:S2DSession.Credential     = $Credential
        }

        'ByCimSession' {
            Write-Verbose "Using provided CimSession to '$($CimSession.ComputerName)'..."
            $Script:S2DSession.CimSession  = $CimSession
            $Script:S2DSession.ClusterName = $CimSession.ComputerName
        }

        'ByPSSession' {
            Write-Verbose "Using provided PSSession to '$($PSSession.ComputerName)'..."
            $Script:S2DSession.PSSession   = $PSSession
            $Script:S2DSession.ClusterName = $PSSession.ComputerName
        }

        'Local' {
            Write-Verbose "Connecting in local mode (no remoting)..."
            $Script:S2DSession.IsLocal     = $true
            $Script:S2DSession.ClusterName = $env:COMPUTERNAME
        }

        'ByKeyVault' {
            Write-Verbose "Retrieving credentials from Key Vault '$KeyVaultName' secret '$SecretName'..."
            if (-not (Get-Command Get-AzKeyVaultSecret -ErrorAction SilentlyContinue)) {
                throw "Az.KeyVault module is required for Key Vault credential retrieval. Install with: Install-Module Az.KeyVault"
            }
            $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText -ErrorAction Stop
            # Resolve username in precedence order:
            #   1. Explicit -Username parameter (most reliable — caller knows their environment)
            #   2. The secret's ContentType tag, by convention "domain\user"
            #   3. Fail with remediation guidance
            $resolvedUser = $Username
            if (-not $resolvedUser) {
                $resolvedUser = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName).ContentType
            }
            if (-not $resolvedUser) {
                throw "Username could not be resolved for Key Vault secret '$SecretName'. Pass -Username explicitly, or set the secret's ContentType tag to 'domain\\username'."
            }
            $kvCred = [PSCredential]::new($resolvedUser, (ConvertTo-SecureString $secret -AsPlainText -Force))
            $session = New-CimSession -ComputerName $ClusterName -Credential $kvCred -Authentication Negotiate -ErrorAction Stop
            $Script:S2DSession.CimSession     = $session
            $Script:S2DSession.ClusterName    = $ClusterName
            $Script:S2DSession.Authentication = 'Negotiate'
            $Script:S2DSession.Credential     = $kvCred
        }
    }

    # Validate that S2D is enabled on the target
    # Uses Get-StoragePool via CIM/remoting — avoids requiring local FailoverClusters RSAT module
    try {
        $s2dPool = if ($Script:S2DSession.IsLocal) {
            Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne 'Primordial' }
        } elseif ($Script:S2DSession.CimSession) {
            Get-StoragePool -CimSession $Script:S2DSession.CimSession -ErrorAction SilentlyContinue |
                Where-Object { $_.FriendlyName -ne 'Primordial' }
        } else {
            Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock {
                Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne 'Primordial' }
            } -ErrorAction Stop
        }

        if (-not $s2dPool) {
            throw "No S2D storage pool found on '$($Script:S2DSession.ClusterName)'. Ensure Storage Spaces Direct is enabled."
        }
    }
    catch {
        # Clean up partially-created sessions on failure
        if ($Script:S2DSession.CimSession) { $Script:S2DSession.CimSession | Remove-CimSession -ErrorAction SilentlyContinue }
        $Script:S2DSession = @{
            ClusterName    = $null; ClusterFqdn = $null; Nodes = @(); NodeTargets = @{}
            CimSession     = $null; PSSession   = $null
            IsConnected    = $false; IsLocal     = $false
            Authentication = 'Negotiate'; Credential = $null
            CollectedData  = @{}
        }
        throw "Failed to validate S2D on '$ClusterName': $_"
    }

    # Discover cluster nodes via remoting — avoids requiring local FailoverClusters RSAT module
    try {
        $Script:S2DSession.Nodes = if ($Script:S2DSession.IsLocal) {
            (Get-ClusterNode -ErrorAction SilentlyContinue).Name
        } elseif ($Script:S2DSession.CimSession) {
            Invoke-CimMethod -CimSession $Script:S2DSession.CimSession `
                -Namespace 'root/MSCluster' -ClassName 'MSCluster_Node' `
                -MethodName 'EnumerateNode' -ErrorAction SilentlyContinue | Out-Null
            (Get-CimInstance -CimSession $Script:S2DSession.CimSession `
                -Namespace 'root/MSCluster' -ClassName 'MSCluster_Node' `
                -ErrorAction SilentlyContinue).Name
        } else {
            Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock { (Get-ClusterNode).Name }
        }
    }
    catch {
        Write-Warning "Could not enumerate cluster nodes: $_"
    }

    # Build the NodeTargets lookup map (short name → FQDN) used by per-node fan-out
    # operations. On workgroup/non-domain-joined management machines the short name
    # returned by MSCluster_Node enumeration is not valid for CIM/WinRM; TrustedHosts
    # typically contains FQDNs. Resolving once here keeps every collector consistent.
    $Script:S2DSession.NodeTargets = @{}
    $clusterFqdnForResolution = if ($Script:S2DSession.ClusterFqdn) {
        $Script:S2DSession.ClusterFqdn
    } else {
        $Script:S2DSession.ClusterName
    }

    foreach ($nodeName in @($Script:S2DSession.Nodes)) {
        if (-not $nodeName) { continue }
        $fqdn = Resolve-S2DNodeFqdn -ShortName $nodeName -ClusterFqdn $clusterFqdnForResolution
        $Script:S2DSession.NodeTargets[$nodeName] = $fqdn
    }

    # Preflight fan-out — when a remote CIM session is active, verify that at least
    # one resolved node target is actually reachable under the configured credentials
    # and TrustedHosts. Failing here gives the user one precise, actionable message
    # instead of N repeated generic WinRM warnings from per-collector fan-out paths.
    if (-not $Script:S2DSession.IsLocal -and
        $Script:S2DSession.CimSession -and
        $Script:S2DSession.NodeTargets.Count -gt 0) {

        $sampleNode = $Script:S2DSession.Nodes | Select-Object -First 1
        $sampleTarget = $Script:S2DSession.NodeTargets[$sampleNode]

        Write-Verbose "Preflight: validating per-node remoting against '$sampleTarget'..."
        $preflightParams = @{
            ComputerName   = $sampleTarget
            Authentication = $Script:S2DSession.Authentication
            ErrorAction    = 'Stop'
        }
        if ($Script:S2DSession.Credential) { $preflightParams['Credential'] = $Script:S2DSession.Credential }

        try {
            $probe = New-CimSession @preflightParams
            Remove-CimSession -CimSession $probe -ErrorAction SilentlyContinue
        }
        catch {
            $fqdnList = ($Script:S2DSession.NodeTargets.Values | Sort-Object) -join ','
            $isDomainJoined = try { (Get-CimInstance Win32_ComputerSystem).PartOfDomain } catch { $false }
            $remedyHints = @(
                "Fan-out preflight to '$sampleTarget' failed under authentication '$($Script:S2DSession.Authentication)': $($_.Exception.Message)"
                ''
                'The cluster connection succeeded but per-node collection cannot reach the resolved node FQDNs.'
                'Pick one of the following remediations:'
                "  1. Run from a domain-joined management host that trusts '$($Script:S2DSession.Credential.UserName)'."
                '  2. Run locally on a cluster node with  Connect-S2DCluster -Local'
                '  3. Add the node FQDNs to TrustedHosts on this machine, e.g.:'
                "       Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$fqdnList' -Concatenate -Force"
                "       winrm set winrm/config/client `"@{TrustedHosts=`'$fqdnList`'}`"  (legacy form)"
            )
            if (-not $isDomainJoined) {
                $remedyHints += '  (Detected: this host is not domain-joined, which is the most common trigger.)'
            }

            # Clean up the cluster CIM session before throwing so the module is in a
            # clean state — the session we opened is technically fine, but leaving it
            # connected after reporting failure would confuse retry logic.
            if ($Script:S2DSession.CimSession) {
                $Script:S2DSession.CimSession | Remove-CimSession -ErrorAction SilentlyContinue
            }
            $Script:S2DSession = @{
                ClusterName    = $null; ClusterFqdn = $null; Nodes = @(); NodeTargets = @{}
                CimSession     = $null; PSSession   = $null
                IsConnected    = $false; IsLocal     = $false
                Authentication = 'Negotiate'; Credential = $null
                CollectedData  = @{}
            }

            throw ($remedyHints -join [Environment]::NewLine)
        }
    }

    $Script:S2DSession.IsConnected = $true

    [PSCustomObject]@{
        ClusterName = $Script:S2DSession.ClusterName
        Nodes       = $Script:S2DSession.Nodes
        Connected   = $true
        Method      = $PSCmdlet.ParameterSetName
    }
}
