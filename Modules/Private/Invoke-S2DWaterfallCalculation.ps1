# Invoke-S2DWaterfallCalculation — pure waterfall math, no session dependency.
# Called by Get-S2DCapacityWaterfall (live cluster) and Invoke-S2DCapacityWhatIf (what-if modeling).

function Invoke-S2DWaterfallCalculation {
    <#
    .SYNOPSIS
        Computes the 7-stage S2D capacity waterfall from explicit numeric inputs.

    .DESCRIPTION
        Pure function — no PowerShell session, no module state, no live CIM queries.
        All inputs are passed explicitly. Returns an S2DCapacityWaterfall object.

        Stage 1  Raw physical capacity (pool-member capacity disks)
        Stage 2  Vendor TB label note (informational — no bytes deducted)
        Stage 3  After storage pool overhead
        Stage 4  After reserve space (min(NodeCount,4) × largest drive)
        Stage 5  After infrastructure volume
        Stage 6  Available for workload volumes
        Stage 7  Usable capacity after resiliency overhead (pipeline terminus)

    .PARAMETER RawDiskBytes
        Sum of all pool-member capacity-tier disk sizes in bytes (Stage 1).

    .PARAMETER NodeCount
        Number of nodes in the cluster. Used for reserve calculation.

    .PARAMETER LargestDiskSizeBytes
        Size in bytes of the largest capacity-tier disk. Used for reserve calculation.

    .PARAMETER PoolTotalBytes
        Storage pool total size in bytes (Stage 3). If 0, estimated as
        RawDiskBytes × (1 - PoolOverheadFraction).

    .PARAMETER PoolFreeBytes
        Current unallocated pool bytes. Used for reserve status only (Adequate/Warning/Critical).
        Does not affect stage values.

    .PARAMETER PoolOverheadFraction
        Pool overhead as a fraction (default 0.01 = 1%). Used only when PoolTotalBytes is 0.

    .PARAMETER InfraVolumeBytes
        Infrastructure volume pool footprint in bytes (Stage 5 deduction).

    .PARAMETER ResiliencyFactor
        Number of data copies for resiliency.
        Default 2.0 (two-way mirror) — the minimum-safe S2D assumption when no actual
        NumberOfDataCopies can be read from pool or volume settings. When the default
        is used the report labels it as an assumed value, not a measured one. (AB#4642)
        Stage 7 = Stage 6 / ResiliencyFactor.

    .PARAMETER ResiliencyName
        Human-readable label for the resiliency type.
        Default '2-way mirror (assumed)' — updated when actual pool/volume data supplies
        a confirmed copy count (AB#4642).

    .PARAMETER ResiliencyIsAssumed
        When $true the caller did not supply an actual NumberOfDataCopies; the fallback
        default was used. Stage 7 and the waterfall object description are tagged to
        distinguish assumed from measured values in reports. (AB#4642)
    #>
    [CmdletBinding()]
    [OutputType([S2DCapacityWaterfall])]
    param(
        [Parameter(Mandatory)]
        [int64]  $RawDiskBytes,

        [Parameter(Mandatory)]
        [int]    $NodeCount,

        [Parameter(Mandatory)]
        [int64]  $LargestDiskSizeBytes,

        [int64]  $PoolTotalBytes        = 0,
        [int64]  $PoolFreeBytes         = 0,
        [double] $PoolOverheadFraction  = 0.01,
        [int64]  $InfraVolumeBytes      = 0,
        # AB#4642: safe minimum-assumption fallback changed from 3.0 to 2.0.
        # Two-way mirror is valid on as few as 2 nodes; three-way requires ≥3 nodes.
        # Callers that have read actual NumberOfDataCopies must pass the real value.
        [double] $ResiliencyFactor      = 2.0,
        [string] $ResiliencyName        = '2-way mirror (assumed)',
        [switch] $ResiliencyIsAssumed
    )

    # ── Stage 1: Raw physical ─────────────────────────────────────────────────
    $stage1Bytes = $RawDiskBytes

    # ── Stage 2: Vendor TB label note (no deduction) ─────────────────────────
    $vendorLabeledTB = [math]::Round($stage1Bytes / 1000000000000, 2)
    $stage2Bytes     = $stage1Bytes

    # ── Stage 3: Pool overhead ────────────────────────────────────────────────
    $stage3Bytes = if ($PoolTotalBytes -gt 0) {
        $PoolTotalBytes
    } else {
        [int64]($stage2Bytes * (1.0 - $PoolOverheadFraction))
    }

    # ── Stage 4: Reserve space ────────────────────────────────────────────────
    $reserveCalc  = Get-S2DReserveCalculation `
        -NodeCount                    $NodeCount `
        -LargestCapacityDriveSizeBytes $LargestDiskSizeBytes `
        -PoolFreeBytes                $PoolFreeBytes
    $reserveBytes = $reserveCalc.ReserveRecommendedBytes
    $stage4Bytes  = $stage3Bytes - $reserveBytes

    # ── Stage 5: Infrastructure volume ───────────────────────────────────────
    $stage5Bytes = $stage4Bytes - $InfraVolumeBytes

    # ── Stage 6: Available ────────────────────────────────────────────────────
    $stage6Bytes = $stage5Bytes

    # ── Stage 7: Theoretical resiliency ──────────────────────────────────────
    $stage7Bytes = [int64]($stage6Bytes / $ResiliencyFactor)
    $theoreticalEffPct = [math]::Round(100.0 / $ResiliencyFactor, 1)
    # AB#4642: tag assumed vs measured so reports can label them differently.
    $resiliencyTag = if ($ResiliencyIsAssumed) { ' [ASSUMED — actual NumberOfDataCopies not available]' } else { '' }

    # Stage 7 is the pipeline terminus — no Stage 8.

    # ── Build stage objects ───────────────────────────────────────────────────
    function local:New-Stage {
        param([int]$N, [string]$Name, [int64]$Bytes, [int64]$Prev, [string]$Desc, [string]$Status = 'OK')
        $s = [S2DWaterfallStage]::new()
        $s.Stage       = $N
        $s.Name        = $Name
        $s.Size        = if ($Bytes -gt 0) { [S2DCapacity]::new($Bytes) } else { [S2DCapacity]::new([int64]0) }
        $s.Delta       = if ($Prev -gt $Bytes -and $Prev -gt 0) { [S2DCapacity]::new($Prev - $Bytes) } else { $null }
        $s.Description = $Desc
        $s.Status      = $Status
        $s
    }

    # All stages are theoretical — no stage carries a health status.
    # Reserve adequacy is reported via ReserveStatus on the waterfall object and
    # evaluated in Health Checks (Check 1). It does not belong on a pipeline stage.
    $driveCount   = if ($LargestDiskSizeBytes -gt 0) { [math]::Round($RawDiskBytes / $LargestDiskSizeBytes) } else { 0 }
    $infraDisplay = if ($InfraVolumeBytes -gt 0) { "$([math]::Round($InfraVolumeBytes/1073741824,1)) GiB" } else { 'None detected' }

    $stages = @(
        (New-Stage 1 'Raw Capacity'           $stage1Bytes $stage1Bytes   "All pool-member capacity drives. $driveCount × $('{0:N2}' -f ($LargestDiskSizeBytes/1TB)) TB = $('{0:N2}' -f ($stage1Bytes/1TB)) TB"),
        (New-Stage 2 'Vendor (TB)'            $stage2Bytes $stage1Bytes   "Informational. Vendor labels use decimal TB; Windows reports binary TiB. Vendor label: $vendorLabeledTB TB. No deduction."),
        (New-Stage 3 'Pool Overhead'          $stage3Bytes $stage2Bytes   "~$([math]::Round($PoolOverheadFraction*100,0))% held by the storage pool for internal metadata. Deduction: $('{0:N2}' -f (($stage2Bytes-$stage3Bytes)/1TB)) TB"),
        (New-Stage 4 'Reserve'                $stage4Bytes $stage3Bytes   "Per Microsoft: one drive per server, up to 4 servers. $([math]::Min($NodeCount,4)) × $('{0:N2}' -f ($LargestDiskSizeBytes/1TB)) TB = $('{0:N2}' -f ($reserveBytes/1TB)) TB held for repair."),
        (New-Stage 5 'Infrastructure Volume'  $stage5Bytes $stage4Bytes   "Azure Local system volume pool footprint deducted. $infraDisplay"),
        (New-Stage 6 'Available for Volumes'  $stage6Bytes $stage5Bytes   "Pool space remaining for workload volume footprint after all deductions."),
        (New-Stage 7 'Usable Capacity'        $stage7Bytes $stage6Bytes   "$ResiliencyName writes $([int]$ResiliencyFactor) copies of every byte. $('{0:N2}' -f ($stage6Bytes/1TB)) TB pool ÷ $([int]$ResiliencyFactor) copies = $('{0:N2}' -f ($stage7Bytes/1TB)) TB you can actually store.$resiliencyTag")
    )

    $wf = [S2DCapacityWaterfall]::new()
    $wf.Stages                   = $stages
    $wf.RawCapacity              = [S2DCapacity]::new($stage1Bytes)
    $wf.UsableCapacity           = if ($stage7Bytes -gt 0) { [S2DCapacity]::new($stage7Bytes) } else { [S2DCapacity]::new([int64]0) }
    $wf.ReserveRecommended       = $reserveCalc.ReserveRecommended
    $wf.ReserveActual            = $reserveCalc.ReserveActual
    $wf.ReserveStatus            = $reserveCalc.Status
    $wf.IsOvercommitted          = $false
    $wf.OvercommitRatio          = 0.0
    $wf.NodeCount                = $NodeCount
    $wf.BlendedEfficiencyPercent = $theoreticalEffPct
    $wf
}
