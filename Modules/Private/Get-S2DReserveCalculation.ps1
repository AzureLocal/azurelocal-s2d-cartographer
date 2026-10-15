# Get-S2DReserveCalculation — computes the recommended and available reserve space.
# Used by Get-S2DCapacityWaterfall and Get-S2DHealthStatus.
#
# Microsoft recommendation (Learn: plan-volumes, "Reserve capacity"): reserve the
# equivalent of 1 capacity drive per server, up to a maximum of 4 drives, unallocated
# in the pool. In clusters with all three media types (NVMe + SSD + HDD) Learn
# recommends one SSD plus one HDD per server, up to 4 drives of each; pass both
# -LargestSsdDriveSizeBytes and -LargestHddDriveSizeBytes to apply that rule.

function Get-S2DReserveCalculation {
    <#
    .SYNOPSIS
        Computes recommended reserve space based on node count and largest capacity drive size.

    .PARAMETER NodeCount
        Number of nodes in the cluster.

    .PARAMETER LargestCapacityDriveSizeBytes
        Size in bytes of the largest capacity-tier disk in the cluster.

    .PARAMETER LargestSsdDriveSizeBytes
        Optional. Largest SSD capacity drive in bytes. Supply together with
        LargestHddDriveSizeBytes for NVMe + SSD + HDD clusters: the reserve becomes
        min(NodeCount,4) x (largest SSD + largest HDD), per Learn plan-volumes.

    .PARAMETER LargestHddDriveSizeBytes
        Optional. Largest HDD capacity drive in bytes (see LargestSsdDriveSizeBytes).

    .PARAMETER PoolFreeBytes
        Current unallocated bytes remaining in the storage pool.

    .OUTPUTS
        PSCustomObject with ReserveRecommendedBytes, ReserveActualBytes, IsAdequate,
        DriveEquivalentCount, and Status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $NodeCount,

        [Parameter(Mandatory)]
        [int64] $LargestCapacityDriveSizeBytes,

        [Parameter(Mandatory)]
        [int64] $PoolFreeBytes,

        [int64] $LargestSsdDriveSizeBytes = 0,

        [int64] $LargestHddDriveSizeBytes = 0
    )

    # Recommendation: min(NodeCount, 4) drives worth of unallocated space
    $driveEquivalentCount       = [math]::Min($NodeCount, 4)
    $isMixedMedia = ($LargestSsdDriveSizeBytes -gt 0 -and $LargestHddDriveSizeBytes -gt 0)
    $reserveRecommendedBytes    = if ($isMixedMedia) {
        # Three-media-type cluster: one SSD plus one HDD per server, up to 4 of each.
        $driveEquivalentCount * ($LargestSsdDriveSizeBytes + $LargestHddDriveSizeBytes)
    } else {
        $driveEquivalentCount * $LargestCapacityDriveSizeBytes
    }

    $isAdequate = $PoolFreeBytes -ge $reserveRecommendedBytes

    $status = if ($isAdequate) {
        'Adequate'
    } elseif ($PoolFreeBytes -ge ($reserveRecommendedBytes * 0.5)) {
        'Warning'    # Less than recommended but at least half
    } else {
        'Critical'   # Less than half of recommended reserve
    }

    [PSCustomObject]@{
        NodeCount                   = $NodeCount
        DriveEquivalentCount        = $driveEquivalentCount
        LargestCapacityDrive        = [S2DCapacity]::new($LargestCapacityDriveSizeBytes)
        ReserveRecommended          = [S2DCapacity]::new($reserveRecommendedBytes)
        ReserveRecommendedBytes     = $reserveRecommendedBytes
        ReserveActual               = [S2DCapacity]::new($PoolFreeBytes)
        ReserveActualBytes          = $PoolFreeBytes
        ReserveDeficit              = if (-not $isAdequate) { [S2DCapacity]::new($reserveRecommendedBytes - $PoolFreeBytes) } else { $null }
        IsMixedMedia                = $isMixedMedia
        IsAdequate                  = $isAdequate
        Status                      = $status
    }
}
