function Get-S2DCapacityWaterfall {
    <#
    .SYNOPSIS
        Computes the 7-stage theoretical capacity waterfall from raw physical to final usable capacity.

    .DESCRIPTION
        Thin wrapper around Invoke-S2DWaterfallCalculation. Extracts inputs from the live
        cluster session (physical disks, pool, volumes) and calls the pure function. The
        waterfall is entirely theoretical — no live provisioned-volume state influences
        the pipeline.

        Requires an active session established with Connect-S2DCluster.

    .EXAMPLE
        Get-S2DCapacityWaterfall

    .EXAMPLE
        Get-S2DCapacityWaterfall | Select-Object -ExpandProperty Stages | Format-Table

    .OUTPUTS
        S2DCapacityWaterfall
    #>
    [CmdletBinding()]
    [OutputType([S2DCapacityWaterfall])]
    param()

    # ── Gather prerequisite data from cache or live queries ───────────────────
    $physDisks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
    if (-not $physDisks) {
        Write-Verbose "Collecting physical disk data for waterfall."
        $physDisks = @(Get-S2DPhysicalDiskInventory)
    }

    $pool = $Script:S2DSession.CollectedData['StoragePool']
    if (-not $pool) {
        Write-Verbose "Collecting storage pool data for waterfall."
        $pool = Get-S2DStoragePoolInfo
    }

    $volumes = @($Script:S2DSession.CollectedData['Volumes'])
    if (-not $volumes) {
        Write-Verbose "Collecting volume data for waterfall."
        $volumes = @(Get-S2DVolumeMap)
    }

    $nodeCount = if ($Script:S2DSession.Nodes.Count -gt 0) { $Script:S2DSession.Nodes.Count } else {
        $perNode = @($physDisks | Group-Object NodeName)
        if ($perNode.Count -gt 0) { $perNode.Count } else { 4 }
    }

    # ── Extract inputs ────────────────────────────────────────────────────────
    $capacityDisks = @($physDisks | Where-Object { $_.IsPoolMember -ne $false -and $_.Role -eq 'Capacity' })
    if (-not $capacityDisks) {
        $capacityDisks = @($physDisks | Where-Object {
            $_.IsPoolMember -ne $false -and
            $_.Usage -ne 'Journal' -and
            $_.Usage -ne 'Retired'
        })
    }

    $rawDiskBytes      = [int64]($capacityDisks | Measure-Object -Property SizeBytes -Sum).Sum
    $largestDriveBytes = [int64]($capacityDisks | Measure-Object -Property SizeBytes -Maximum).Maximum
    $poolTotalBytes    = if ($pool -and $pool.TotalSize) { $pool.TotalSize.Bytes } else { [int64]0 }
    $poolFreeBytes     = if ($pool -and $pool.RemainingSize) { $pool.RemainingSize.Bytes } else { [int64]0 }

    $infraVolumes  = @($volumes | Where-Object IsInfrastructureVolume)
    $infraBytes    = [int64]0
    foreach ($iv in $infraVolumes) {
        if ($iv.FootprintOnPool) { $infraBytes += $iv.FootprintOnPool.Bytes }
        elseif ($iv.Size)        { $infraBytes += $iv.Size.Bytes }
    }

    # AB#4642: prefer actual NumberOfDataCopies from pool Mirror resiliency settings.
    # Fallback is 2.0 (two-way mirror — minimum-safe S2D assumption) rather than the
    # former 3.0 default which understated usable capacity on 2-copy clusters by 33%.
    # When falling back, pass -ResiliencyIsAssumed so the report labels it clearly.
    $resiliencyFactor    = 2.0
    $resiliencyName      = '2-way mirror (assumed)'
    $resiliencyIsAssumed = $true
    if ($pool -and $pool.ResiliencySettings) {
        $mirrorSetting = @($pool.ResiliencySettings | Where-Object { $_.Name -eq 'Mirror' }) | Select-Object -First 1
        if ($mirrorSetting -and $mirrorSetting.NumberOfDataCopies -gt 0) {
            $resiliencyFactor    = [double]$mirrorSetting.NumberOfDataCopies
            $resiliencyName      = "$($mirrorSetting.NumberOfDataCopies)-way mirror"
            $resiliencyIsAssumed = $false
        }
    }

    # ── Compute waterfall via pure function ───────────────────────────────────
    $waterfallParams = @{
        RawDiskBytes         = $rawDiskBytes
        NodeCount            = $nodeCount
        LargestDiskSizeBytes = $largestDriveBytes
        PoolTotalBytes       = $poolTotalBytes
        PoolFreeBytes        = $poolFreeBytes
        InfraVolumeBytes     = $infraBytes
        ResiliencyFactor     = $resiliencyFactor
        ResiliencyName       = $resiliencyName
    }
    if ($resiliencyIsAssumed) { $waterfallParams['ResiliencyIsAssumed'] = $true }
    $waterfall = Invoke-S2DWaterfallCalculation @waterfallParams

    # Overcommit state is live-cluster context — set it here, not in the pure function
    $waterfall.IsOvercommitted = $pool -and $pool.OvercommitRatio -gt 1.0
    $waterfall.OvercommitRatio = if ($pool) { $pool.OvercommitRatio } else { 0.0 }

    $Script:S2DSession.CollectedData['CapacityWaterfall'] = $waterfall
    $waterfall
}
