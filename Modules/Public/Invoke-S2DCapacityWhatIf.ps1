function Invoke-S2DCapacityWhatIf {
    <#
    .SYNOPSIS
        Models the capacity impact of adding nodes, adding disks, replacing disks,
        or changing resiliency — without touching the live cluster.

    .DESCRIPTION
        Takes a baseline cluster snapshot (JSON file, S2DClusterData object, or live
        cluster connection) and applies one or more scenario modifications, then
        recomputes the capacity waterfall. Returns a what-if result object containing
        both the baseline and projected waterfalls plus per-stage deltas.

        Scenarios can be combined in a single invocation (composite what-if).

    .PARAMETER BaselineSnapshot
        Path to a JSON snapshot file produced by S2DCartographer (SchemaVersion 1.0).

    .PARAMETER InputObject
        An S2DClusterData object piped from Invoke-S2DCartographer -PassThru.

    .PARAMETER ClusterName
        Connect to a live cluster, collect data, then immediately model. Re-running
        with different scenario parameters will not re-hit the cluster.

    .PARAMETER AddNodes
        Number of nodes to add. New nodes are assumed to have the same disk
        configuration as the average existing node (disk count × disk size).

    .PARAMETER AddDisksPerNode
        Number of capacity disks to add per existing node. Enforces symmetry.

    .PARAMETER NewDiskSizeTB
        Size in decimal TB of new disks added via -AddNodes or -AddDisksPerNode.
        Defaults to the existing largest disk size.

    .PARAMETER ReplaceDiskSizeTB
        Model replacing all capacity disks with disks of this size in decimal TB.
        Node and disk counts remain the same.

    .PARAMETER ChangeResiliency
        Override the resiliency factor (NumberOfDataCopies). E.g. 2 = 2-way mirror,
        3 = 3-way mirror.

    .PARAMETER OutputDirectory
        Directory to write reports to. If omitted no files are written.

    .PARAMETER Format
        Report formats to generate. Accepts Html, Json. Default: Html.

    .PARAMETER PassThru
        Return the what-if result object to the pipeline.

    .EXAMPLE
        Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snap.json -AddNodes 2 -AddDisksPerNode 4 -NewDiskSizeTB 3.84

    .EXAMPLE
        Invoke-S2DCartographer -ClusterName clus01 -PassThru |
            Invoke-S2DCapacityWhatIf -ChangeResiliency 2

    .OUTPUTS
        PSCustomObject (S2DWhatIfResult)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Snapshot')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Snapshot', Position = 0)]
        [string] $BaselineSnapshot,

        [Parameter(Mandatory, ParameterSetName = 'Object', ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Live')]
        [string] $ClusterName,

        [int]    $AddNodes          = 0,
        [int]    $AddDisksPerNode   = 0,
        [double] $NewDiskSizeTB     = 0,
        [double] $ReplaceDiskSizeTB = 0,
        [int]    $ChangeResiliency  = 0,

        [string]   $OutputDirectory = '',
        [string[]] $Format          = @('Html'),
        [switch]   $PassThru
    )

    # ── Load baseline ─────────────────────────────────────────────────────────
    $baseline = switch ($PSCmdlet.ParameterSetName) {
        'Snapshot' {
            if (-not (Test-Path $BaselineSnapshot)) {
                throw "Baseline snapshot not found: $BaselineSnapshot"
            }
            $raw = Get-Content $BaselineSnapshot -Raw | ConvertFrom-Json
            if (-not $raw.SchemaVersion) {
                throw "File does not appear to be an S2DCartographer snapshot (missing SchemaVersion)."
            }
            $raw
        }
        'Object' { $InputObject }
        'Live' {
            Connect-S2DCluster -ClusterName $ClusterName
            Get-S2DPhysicalDiskInventory | Out-Null
            Get-S2DStoragePoolInfo       | Out-Null
            Get-S2DVolumeMap             | Out-Null
            Get-S2DCapacityWaterfall     | Out-Null
            $Script:S2DSession.CollectedData
        }
    }

    # ── Extract baseline inputs ───────────────────────────────────────────────
    $baseDisks = @(if ($baseline.PhysicalDisks) { $baseline.PhysicalDisks } else { @() })
    $baseCapDisks = @($baseDisks | Where-Object {
        $_.IsPoolMember -ne $false -and $_.Role -eq 'Capacity'
    })
    if (-not $baseCapDisks) {
        $baseCapDisks = @($baseDisks | Where-Object {
            $_.IsPoolMember -ne $false -and
            $_.Usage -ne 'Journal' -and $_.Usage -ne 'Retired'
        })
    }

    $baseNodeCount    = if ($baseline.NodeCount -gt 0) { [int]$baseline.NodeCount } else {
        @($baseCapDisks | Select-Object -ExpandProperty NodeName -Unique).Count
    }
    $disksPerNode     = if ($baseNodeCount -gt 0 -and $baseCapDisks.Count -gt 0) {
        [math]::Round($baseCapDisks.Count / $baseNodeCount)
    } else { 0 }

    $baseLargestDrive = [int64]($baseCapDisks | Measure-Object -Property SizeBytes -Maximum).Maximum
    $baseRawBytes     = [int64]($baseCapDisks | Measure-Object -Property SizeBytes -Sum).Sum

    $basePool = $baseline.StoragePool
    $basePoolTotalBytes = if ($basePool -and $basePool.TotalSize) {
        if ($basePool.TotalSize -is [hashtable] -or $basePool.TotalSize.PSObject.Properties['Bytes']) {
            [int64]$basePool.TotalSize.Bytes
        } else { [int64]$basePool.TotalSize }
    } else { [int64]0 }
    $basePoolFreeBytes = if ($basePool -and $basePool.RemainingSize) {
        if ($basePool.RemainingSize.PSObject.Properties['Bytes']) {
            [int64]$basePool.RemainingSize.Bytes
        } else { [int64]$basePool.RemainingSize }
    } else { [int64]0 }

    $baseVolumes   = @(if ($baseline.Volumes) { $baseline.Volumes } else { @() })
    $baseInfraVols = @($baseVolumes | Where-Object { $_.IsInfrastructureVolume })
    $baseInfraBytes = [int64]0
    foreach ($iv in $baseInfraVols) {
        $fp = if ($iv.FootprintOnPool -and $iv.FootprintOnPool.PSObject.Properties['Bytes']) {
            [int64]$iv.FootprintOnPool.Bytes
        } elseif ($iv.Size -and $iv.Size.PSObject.Properties['Bytes']) {
            [int64]$iv.Size.Bytes
        } else { [int64]0 }
        $baseInfraBytes += $fp
    }

    # AB#4642: prefer actual NumberOfDataCopies from pool Mirror resiliency settings.
    # Fallback changed from 3.0 to 2.0 (minimum-safe S2D assumption). When falling
    # back, pass -ResiliencyIsAssumed so the report labels it as assumed, not measured.
    $baseResFactor       = 2.0
    $baseResName         = '2-way mirror (assumed)'
    $baseResIsAssumed    = $true
    if ($basePool -and $basePool.ResiliencySettings) {
        $m = @($basePool.ResiliencySettings | Where-Object { $_.Name -eq 'Mirror' }) | Select-Object -First 1
        if ($m -and $m.NumberOfDataCopies -gt 0) {
            $baseResFactor    = [double]$m.NumberOfDataCopies
            $baseResName      = "$($m.NumberOfDataCopies)-way mirror"
            $baseResIsAssumed = $false
        }
    }

    # Compute baseline waterfall
    $baseWfParams = @{
        RawDiskBytes         = $baseRawBytes
        NodeCount            = $baseNodeCount
        LargestDiskSizeBytes = $baseLargestDrive
        PoolTotalBytes       = $basePoolTotalBytes
        PoolFreeBytes        = $basePoolFreeBytes
        InfraVolumeBytes     = $baseInfraBytes
        ResiliencyFactor     = $baseResFactor
        ResiliencyName       = $baseResName
    }
    if ($baseResIsAssumed) { $baseWfParams['ResiliencyIsAssumed'] = $true }
    $baselineWaterfall = Invoke-S2DWaterfallCalculation @baseWfParams

    # ── Apply scenario modifications ──────────────────────────────────────────
    $projNodeCount    = $baseNodeCount
    $projDisksPerNode = $disksPerNode
    $projDiskSize     = $baseLargestDrive
    $projResFactor    = $baseResFactor
    $projResName      = $baseResName
    $scenarioParts    = @()

    if ($ReplaceDiskSizeTB -gt 0) {
        $projDiskSize  = [int64]($ReplaceDiskSizeTB * 1000000000000)
        $scenarioParts += "Replace disks → $ReplaceDiskSizeTB TB"
    }
    if ($NewDiskSizeTB -gt 0) {
        $newDiskBytes  = [int64]($NewDiskSizeTB * 1000000000000)
        # Only override drive size for new disks if larger
        $projDiskSize  = [math]::Max($projDiskSize, $newDiskBytes)
    }
    if ($AddDisksPerNode -gt 0) {
        # Validate symmetry
        if ($projNodeCount -lt 1) { throw "Cannot add disks per node — node count unknown." }
        $projDisksPerNode += $AddDisksPerNode
        $scenarioParts    += "+$AddDisksPerNode disks/node"
    }
    if ($AddNodes -gt 0) {
        $projNodeCount += $AddNodes
        $scenarioParts += "+$AddNodes nodes"
    }
    # AB#4642: when -ChangeResiliency is explicitly supplied it is a user-specified
    # value (not assumed); otherwise the projected scenario inherits the baseline flag.
    $projResIsAssumed = $baseResIsAssumed
    if ($ChangeResiliency -gt 0) {
        $projResFactor    = [double]$ChangeResiliency
        $projResName      = "$ChangeResiliency-way mirror"
        $projResIsAssumed = $false
        $scenarioParts   += "Resiliency → $ChangeResiliency-way mirror"
    }

    $scenarioLabel  = if ($scenarioParts) { $scenarioParts -join ', ' } else { 'No changes (baseline)' }

    # Projected raw bytes: new node count × disks per node × disk size
    $projTotalDisks = $projNodeCount * $projDisksPerNode
    $projRawBytes   = if ($projTotalDisks -gt 0) {
        [int64]($projTotalDisks * $projDiskSize)
    } else { $baseRawBytes }

    # Projected pool: estimate from projected raw (no override — this is a new config)
    $projPoolTotalBytes = [int64]($projRawBytes * 0.99)
    # Projected pool free: scale pool free proportionally if pool grew
    $projPoolFreeBytes  = if ($basePoolTotalBytes -gt 0 -and $projPoolTotalBytes -gt $basePoolTotalBytes) {
        $basePoolFreeBytes + ($projPoolTotalBytes - $basePoolTotalBytes)
    } else { $basePoolFreeBytes }

    $projWfParams = @{
        RawDiskBytes         = $projRawBytes
        NodeCount            = $projNodeCount
        LargestDiskSizeBytes = $projDiskSize
        PoolTotalBytes       = $projPoolTotalBytes
        PoolFreeBytes        = $projPoolFreeBytes
        InfraVolumeBytes     = $baseInfraBytes
        ResiliencyFactor     = $projResFactor
        ResiliencyName       = $projResName
    }
    if ($projResIsAssumed) { $projWfParams['ResiliencyIsAssumed'] = $true }
    $projectedWaterfall = Invoke-S2DWaterfallCalculation @projWfParams

    # ── Build delta table ─────────────────────────────────────────────────────
    $deltaStages = for ($i = 0; $i -lt $baselineWaterfall.Stages.Count; $i++) {
        $b = $baselineWaterfall.Stages[$i]
        $p = $projectedWaterfall.Stages[$i]
        $deltaBytes = $p.Size.Bytes - $b.Size.Bytes
        [PSCustomObject]@{
            Stage          = $b.Stage
            Name           = $b.Name
            BaselineTiB    = $b.Size.TiB
            ProjectedTiB   = $p.Size.TiB
            DeltaTiB       = [math]::Round($deltaBytes / 1099511627776, 2)
            BaselineTB     = $b.Size.TB
            ProjectedTB    = $p.Size.TB
            DeltaTB        = [math]::Round($deltaBytes / 1000000000000, 2)
        }
    }

    $result = [PSCustomObject]@{
        PSTypeName         = 'S2DWhatIfResult'
        ScenarioLabel      = $scenarioLabel
        BaselineNodeCount  = $baseNodeCount
        ProjectedNodeCount = $projNodeCount
        BaselineWaterfall  = $baselineWaterfall
        ProjectedWaterfall = $projectedWaterfall
        DeltaStages        = $deltaStages
        DeltaUsableTiB     = $projectedWaterfall.UsableCapacity.TiB - $baselineWaterfall.UsableCapacity.TiB
        DeltaUsableTB      = [math]::Round(($projectedWaterfall.UsableCapacity.Bytes - $baselineWaterfall.UsableCapacity.Bytes) / 1000000000000, 2)
        GeneratedAt        = (Get-Date -Format 'o')
    }

    # ── Write reports ─────────────────────────────────────────────────────────
    if ($OutputDirectory) {
        $outDir = $OutputDirectory
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $base = Join-Path $outDir "whatif-$(Get-Date -Format 'yyyyMMdd-HHmm')"

        if ('Html' -in $Format -or 'All' -in $Format) {
            $htmlPath = Export-S2DWhatIfHtmlReport -Result $result -OutputPath "$base.html"
            Write-Verbose "What-if HTML report: $htmlPath"
        }
        if ('Json' -in $Format -or 'All' -in $Format) {
            $jsonPath = Export-S2DWhatIfJsonReport -Result $result -OutputPath "$base.json"
            Write-Verbose "What-if JSON output: $jsonPath"
        }
    }

    if ($PassThru -or -not $OutputDirectory) { $result }
}
