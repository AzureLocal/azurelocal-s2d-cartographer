# JSON data exporter — writes the full S2DClusterData snapshot as structured
# JSON for downstream consumers (historical diff, what-if calculator, external
# dashboards, custom scripts).
#
# SCHEMA CONTRACT:
#   The shape of this output is a stable API. See docs/schema/cluster-snapshot.md.
#   Bump SchemaVersion minor for additive fields; major for renames/removals.

function Export-S2DJsonReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks  # ignored — JSON always contains ALL disks with IsPoolMember flag
    )

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $moduleVersion = try {
        (Get-Module S2DCartographer | Select-Object -First 1).Version.ToString()
    } catch { 'unknown' }

    $snapshot = [ordered]@{
        SchemaVersion = '1.0'
        Generated     = [ordered]@{
            Timestamp     = (Get-Date).ToUniversalTime().ToString('o')
            ModuleVersion = $moduleVersion
            Author        = $Author
            Company       = $Company
        }
        Cluster = [ordered]@{
            Name        = $ClusterData.ClusterName
            Fqdn        = $ClusterData.ClusterFqdn
            NodeCount   = $ClusterData.NodeCount
            Nodes       = @($ClusterData.Nodes)
            CollectedAt = if ($ClusterData.CollectedAt) { $ClusterData.CollectedAt.ToUniversalTime().ToString('o') } else { $null }
        }
        NodeCount          = $ClusterData.NodeCount
        OverallHealth      = $ClusterData.OverallHealth
        PhysicalDisks      = @($ClusterData.PhysicalDisks)
        StoragePool        = $ClusterData.StoragePool
        Volumes            = @($ClusterData.Volumes)
        CacheTier          = $ClusterData.CacheTier
        CapacityWaterfall  = $ClusterData.CapacityWaterfall
        HealthChecks       = @($ClusterData.HealthChecks)
        ExpansionHeadroom  = $ClusterData.ExpansionHeadroom
    }

    # Depth 10 is enough for S2DCapacity (3 deep) nested inside waterfall stages
    # inside the waterfall object inside the snapshot (max depth ~6).
    $json = $snapshot | ConvertTo-Json -Depth 10

    # Strip PowerShell's PSTypeName noise if it appears anywhere — consumers in
    # jq / Python / Go should not need to know about PowerShell types.
    $json = $json -replace '(?m)^\s*"PSTypeName":\s*"[^"]*",?\s*\r?\n', ''

    $json | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Verbose "JSON snapshot written to $OutputPath"
    $OutputPath
}
