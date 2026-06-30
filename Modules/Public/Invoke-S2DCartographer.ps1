function Invoke-S2DCartographer {
    <#
    .SYNOPSIS
        Full orchestrated S2D analysis run: connect, collect, analyze, and report.

    .DESCRIPTION
        Runs the complete S2DCartographer pipeline in a single call:
          1. Connect to the cluster (Connect-S2DCluster)
          2. Collect all data (physical disks, pool, volumes, cache tier)
          3. Compute the 7-stage capacity waterfall
          4. Run all 10 health checks
          5. Generate requested report formats (HTML, Word, PDF, Excel)
          6. Generate SVG diagrams (if -IncludeDiagrams)
          7. Disconnect from the cluster

        Output files are written to a per-run subfolder under OutputDirectory:
          <OutputDirectory>\<ClusterName>\<yyyyMMdd-HHmm>\

        A session log file is written to the same run folder capturing each
        collection step, warnings, and final output paths.
        Use -PassThru to receive the S2DClusterData object for further processing.

    .PARAMETER ClusterName
        Cluster name or FQDN. Required unless -CimSession, -PSSession, or -Local is used.

    .PARAMETER Credential
        PSCredential for cluster authentication. Resolved from Key Vault when -KeyVaultName is provided.

    .PARAMETER Authentication
        Authentication method passed through to Connect-S2DCluster / New-CimSession.
        Defaults to 'Negotiate', which works in both domain-joined and workgroup/lab environments.

    .PARAMETER CimSession
        Existing CimSession to the cluster. Skips Connect-S2DCluster.

    .PARAMETER Local
        Run locally from a cluster node.

    .PARAMETER KeyVaultName
        Azure Key Vault name to resolve credentials from.

    .PARAMETER SecretName
        Key Vault secret name containing the cluster password.

    .PARAMETER Username
        Optional explicit username for the Key Vault credential path. When not provided,
        the username is read from the secret's ContentType tag (convention: 'domain\user').
        Use this when the secret does not have a ContentType populated.

    .PARAMETER OutputDirectory
        Root folder for all output files. Created if it does not exist.
        Defaults to C:\S2DCartographer.

    .PARAMETER Format
        Report formats to generate: Html, Word, Pdf, Excel, Json, Csv, All.
        Defaults to All (= HTML + Word + PDF + Excel + JSON). CSV is opt-in
        because it produces multiple files per run.

    .PARAMETER IncludeNonPoolDisks
        Include non-pool disks (boot drives, SAN LUNs) in the Physical Disk Inventory
        tables. Default is to show pool members only. JSON and CSV outputs always
        include every disk with an IsPoolMember flag regardless of this switch.

    .PARAMETER IncludeDiagrams
        Also generate all six SVG diagram types.

    .PARAMETER PrimaryUnit
        Preferred display unit for capacity values: TiB (default) or TB.

    .PARAMETER SkipHealthChecks
        Skip the health check phase (faster runs when only capacity data is needed).

    .PARAMETER Author
        Author name embedded in generated reports.

    .PARAMETER Company
        Company or organization name embedded in generated reports.

    .PARAMETER PassThru
        Return the S2DClusterData object in addition to writing files.

    .EXAMPLE
        Invoke-S2DCartographer -ClusterName tplabs-clus01.azrl.mgmt `
            -KeyVaultName kv-tplabs-platform -SecretName lcm-deployment-password

    .EXAMPLE
        $data = Invoke-S2DCartographer -ClusterName tplabs-clus01 -Format All -IncludeDiagrams -PassThru
        $data | New-S2DReport -Format Html

    .OUTPUTS
        string[] file paths (default), or S2DClusterData when -PassThru is set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string] $ClusterName,

        [Parameter()]
        [PSCredential] $Credential,

        [Parameter()]
        [CimSession] $CimSession,

        [Parameter()]
        [switch] $Local,

        [Parameter()]
        [ValidateSet('Default','Digest','Negotiate','Basic','Kerberos','ClientCertificate','CredSsp')]
        [string] $Authentication = 'Negotiate',

        [Parameter()]
        [string] $KeyVaultName,

        [Parameter()]
        [string] $SecretName,

        [Parameter()]
        [string] $Username,

        [Parameter()]
        [string] $OutputDirectory = 'C:\S2DCartographer',

        [Parameter()]
        [ValidateSet('Html', 'Word', 'Pdf', 'Excel', 'Json', 'Csv', 'All')]
        [string[]] $Format = @('All'),

        [Parameter()]
        [switch] $IncludeNonPoolDisks,

        [Parameter()]
        [switch] $IncludeDiagrams,

        [Parameter()]
        [ValidateSet('TiB', 'TB')]
        [string] $PrimaryUnit = 'TiB',

        [Parameter()]
        [switch] $SkipHealthChecks,

        [Parameter()]
        [string] $Author = '',

        [Parameter()]
        [string] $Company = '',

        [Parameter()]
        [switch] $PassThru
    )

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    # ── Concurrent collection guard ───────────────────────────────────────────
    # Prevent two Invoke-S2DCartographer calls from running simultaneously and
    # corrupting shared $Script:S2DSession / CollectedData state.
    if ($Script:S2DCollectionInProgress) {
        throw 'A collection is already in progress. Wait for the current Invoke-S2DCartographer run to complete before starting another.'
    }
    $Script:S2DCollectionInProgress = $true

    # ── Log helper (writes to file and verbose stream) ────────────────────────
    $logLines  = [System.Collections.Generic.List[string]]::new()
    $runStart  = Get-Date
    $logPath   = $null   # resolved after connect when cluster name is known

    function local:Write-Log {
        param([string]$Message, [string]$Level = 'INFO')
        $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $line = "[$ts] [$Level] $Message"
        $logLines.Add($line)
        if ($logPath) { $line | Out-File -FilePath $logPath -Append -Encoding utf8 }
        Write-Verbose $line
    }

    $ownedSession = $false

    try {
        Write-Log "S2DCartographer run started. PSVersion=$($PSVersionTable.PSVersion) Platform=$($PSVersionTable.Platform)"
        Write-Log "Parameters: Format=$($Format -join ',') IncludeDiagrams=$IncludeDiagrams SkipHealthChecks=$SkipHealthChecks"

        # ── Step 1: Connect ───────────────────────────────────────────────────
        # Build splat for Connect-S2DCluster with strict parameter-set discipline.
        # Each parameter set (ByName / ByKeyVault / ByCimSession / Local) accepts a
        # disjoint set of parameters — splatting one set's parameters into another
        # causes PowerShell parameter-set resolution to fall back to ByName, which
        # then demands a -Credential that was never supplied and throws a misleading
        # "Credentials are required" error. See issue #39.
        if (-not $Script:S2DSession.IsConnected) {
            $connectParams = @{}

            if ($Local) {
                $connectParams['Local'] = $Local
            }
            elseif ($CimSession) {
                $connectParams['CimSession'] = $CimSession
            }
            elseif ($KeyVaultName -and $SecretName) {
                # ByKeyVault — -Authentication is NOT a valid parameter here
                $connectParams['ClusterName']  = $ClusterName
                $connectParams['KeyVaultName'] = $KeyVaultName
                $connectParams['SecretName']   = $SecretName
                if ($Username) { $connectParams['Username'] = $Username }
            }
            else {
                # ByName — requires ClusterName; Credential + Authentication valid
                if ($ClusterName)  { $connectParams['ClusterName']    = $ClusterName }
                if ($Credential)   { $connectParams['Credential']     = $Credential }
                $connectParams['Authentication'] = $Authentication
            }

            if ($PSCmdlet.ShouldProcess($ClusterName, 'Connect to S2D cluster')) {
                Write-Log "Connecting to cluster: $ClusterName"
                Write-Log "Splat keys passed to Connect-S2DCluster: $($connectParams.Keys -join ', ')"
                Connect-S2DCluster @connectParams
                $ownedSession = $true
                Write-Log "Connected. Cluster=$($Script:S2DSession.ClusterName) Nodes=$($Script:S2DSession.Nodes.Count)"
            }
        }

        # ── Build per-run output folder ───────────────────────────────────────
        $safeName  = ($Script:S2DSession.ClusterName -replace '[^\w\-]', '_').ToLower()
        $stamp     = $runStart.ToString('yyyyMMdd-HHmm')
        $runDir    = Join-Path $OutputDirectory "$safeName\$stamp"
        $diagramDir = Join-Path $runDir 'diagrams'
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        $baseName  = "S2DCartographer_${safeName}_${stamp}"
        $logPath   = Join-Path $runDir "$baseName.log"

        # Flush buffered pre-connect log lines now that we have a path
        $logLines | Out-File -FilePath $logPath -Encoding utf8
        Write-Log "Run folder: $runDir"

        # ── Step 2: Collect ───────────────────────────────────────────────────
        Write-Progress -Activity 'S2DCartographer' -Status 'Collecting physical disks...' -PercentComplete 10
        Write-Log "Collecting physical disks..."
        $t = Get-Date; $physDisks = @(Get-S2DPhysicalDiskInventory)
        Write-Log "Physical disks: $($physDisks.Count) disk(s) collected in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"

        Write-Progress -Activity 'S2DCartographer' -Status 'Collecting storage pool...' -PercentComplete 25
        Write-Log "Collecting storage pool..."
        $t = Get-Date; $pool = Get-S2DStoragePoolInfo
        Write-Log "Storage pool: $(if($pool){"$($pool.FriendlyName) [$($pool.HealthStatus)]"}else{'none found'}) in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"

        Write-Progress -Activity 'S2DCartographer' -Status 'Collecting volumes...' -PercentComplete 40
        Write-Log "Collecting volumes..."
        $t = Get-Date; $volumes = @(Get-S2DVolumeMap)
        Write-Log "Volumes: $($volumes.Count) volume(s) collected in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"

        Write-Progress -Activity 'S2DCartographer' -Status 'Analyzing cache tier...' -PercentComplete 55
        Write-Log "Analyzing cache tier..."
        $t = Get-Date; $cacheTier = Get-S2DCacheTierInfo
        Write-Log "Cache tier: $(if($cacheTier){"$($cacheTier.CacheState) / $($cacheTier.CacheMode)"}else{'no data'}) in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"

        Write-Progress -Activity 'S2DCartographer' -Status 'Computing capacity waterfall...' -PercentComplete 65
        Write-Log "Computing capacity waterfall..."
        $t = Get-Date; $waterfall = Get-S2DCapacityWaterfall
        Write-Log "Waterfall: $(if($waterfall){"ReserveStatus=$($waterfall.ReserveStatus) Usable=$($waterfall.UsableCapacity.TiB) TiB"}else{'no data'}) in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"

        $healthChecks  = @()
        $overallHealth = 'Unknown'
        if (-not $SkipHealthChecks) {
            Write-Progress -Activity 'S2DCartographer' -Status 'Running health checks...' -PercentComplete 75
            Write-Log "Running health checks..."
            $t = Get-Date; $healthChecks = @(Get-S2DHealthStatus)
            $overallHealth = [string]$Script:S2DSession.CollectedData['OverallHealth']
            $failed = @($healthChecks | Where-Object { $_.Status -ne 'Pass' })
            Write-Log "Health checks: OverallHealth=$overallHealth Checks=$($healthChecks.Count) NonPass=$($failed.Count) in $([math]::Round(((Get-Date)-$t).TotalSeconds,1))s"
            foreach ($f in $failed) {
                Write-Log "  [$($f.Status)] $($f.CheckName): $($f.Details)" -Level 'WARN'
            }
        } else {
            Write-Log "Health checks skipped (-SkipHealthChecks)"
        }

        # ── Step 3: Assemble S2DClusterData ───────────────────────────────────
        $clusterData = [S2DClusterData]::new()
        $clusterData.ClusterName       = $Script:S2DSession.ClusterName
        $clusterData.ClusterFqdn       = $Script:S2DSession.ClusterFqdn
        $clusterData.NodeCount         = if ($Script:S2DSession.Nodes.Count -gt 0) { $Script:S2DSession.Nodes.Count } else { 0 }
        $clusterData.Nodes             = $Script:S2DSession.Nodes
        $clusterData.CollectedAt       = Get-Date
        $clusterData.PhysicalDisks     = $physDisks
        $clusterData.StoragePool       = $pool
        $clusterData.Volumes           = $volumes
        $clusterData.CacheTier         = $cacheTier
        $clusterData.CapacityWaterfall = $waterfall
        $clusterData.HealthChecks      = $healthChecks
        $clusterData.OverallHealth     = $overallHealth

        # Expansion headroom — computed after waterfall + volumes are both available
        Write-Log "Computing expansion headroom..."
        $clusterData.ExpansionHeadroom = if ($waterfall -and $waterfall.AvailableForVolumes) {
            Get-S2DExpansionHeadroom -Waterfall $waterfall -Volumes $volumes
        } else { $null }
        if ($clusterData.ExpansionHeadroom) {
            Write-Log "Expansion headroom: util=$($clusterData.ExpansionHeadroom.CurrentUtilizationPct)% copies=$($clusterData.ExpansionHeadroom.PrevalentDataCopies)"
        }

        # ── Step 4: Generate reports ──────────────────────────────────────────
        $outputFiles = @()
        if ($Format) {
            Write-Progress -Activity 'S2DCartographer' -Status 'Generating reports...' -PercentComplete 85
            Write-Log "Generating reports: $($Format -join ', ')"
            $reportParams = @{
                InputObject     = $clusterData
                Format          = $Format
                OutputDirectory = $runDir
                Author          = $Author
                Company         = $Company
            }
            if ($IncludeNonPoolDisks) { $reportParams['IncludeNonPoolDisks'] = $true }
            $generated = @(New-S2DReport @reportParams)
            $outputFiles += $generated
            foreach ($f in $generated) { Write-Log "  Report: $f" }
        }

        # ── Step 5: Generate diagrams ─────────────────────────────────────────
        if ($IncludeDiagrams) {
            Write-Progress -Activity 'S2DCartographer' -Status 'Generating diagrams...' -PercentComplete 95
            Write-Log "Generating diagrams..."
            New-Item -ItemType Directory -Path $diagramDir -Force | Out-Null
            $generated = @(New-S2DDiagram -InputObject $clusterData -DiagramType All -OutputDirectory $diagramDir)
            $outputFiles += $generated
            foreach ($f in $generated) { Write-Log "  Diagram: $f" }
        }

        Write-Progress -Activity 'S2DCartographer' -Completed

        $elapsed = [math]::Round(((Get-Date) - $runStart).TotalSeconds, 1)
        Write-Log "Run complete. OverallHealth=$overallHealth Files=$($outputFiles.Count) Duration=${elapsed}s"
        Write-Log "Log: $logPath"

        if ($PassThru) { return $clusterData }
        $outputFiles

    }
    catch {
        Write-Log "FATAL: $_" -Level 'ERROR'
        throw
    }
    finally {
        # Always release the concurrent guard, even on error, so subsequent runs succeed.
        $Script:S2DCollectionInProgress = $false

        if ($ownedSession -and $Script:S2DSession.IsConnected) {
            Disconnect-S2DCluster
            Write-Log "Disconnected from cluster."
        }
        # Final flush if log file was never opened (connect failed before runDir was created)
        if (-not $logPath -and $logLines.Count -gt 0) {
            $fallbackLog = Join-Path $OutputDirectory "S2DCartographer_failed_$($runStart.ToString('yyyyMMdd-HHmm')).log"
            $logLines | Out-File -FilePath $fallbackLog -Encoding utf8
        }
    }
}
