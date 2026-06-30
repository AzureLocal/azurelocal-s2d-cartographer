# Get-S2DMaintenanceReserveAssessment — optional N+1/N+2 maintenance-reserve compliance check.
#
# IMPORTANT: No #Requires, Set-StrictMode, or $ErrorActionPreference at file scope.
# Private helpers are dot-sourced into the module scope during Import-Module.
# Setting StrictMode or $ErrorActionPreference here bleeds into the module scope
# and breaks empty-data tests that deliberately pass null/empty inputs.
#
# ASSESSMENT ONLY — this function NEVER modifies cluster state.
# It answers: "does the cluster currently have enough free capacity (after holding
# the rebuild reserve) to keep a full node's worth of data available while that
# node is drained for patching?"
#
# MATH:
#   nodeRawBytes        = capacity-disk SizeBytes for the LARGEST node
#                         (pool-member Role='Capacity' disks, grouped by NodeName,
#                         take the node whose total is highest)
#   requiredBytes       = targetMultiplier × nodeRawBytes
#   maintenanceHeadroom = PoolFreeBytes - RebuildReserveRecommendedBytes
#   Meets               = maintenanceHeadroom >= requiredBytes
#
# Inputs are accepted as plain scalars (bytes) for maximum testability without
# requiring live CIM or a real waterfall object.

function Get-S2DMaintenanceReserveAssessment {
    <#
    .SYNOPSIS
        Assesses whether the cluster meets the N+1 (or N+2) maintenance-reserve recommendation.

    .DESCRIPTION
        Computes how much free pool capacity is available AFTER the rebuild reserve is held,
        then compares that to the raw capacity of the largest node. If the headroom meets or
        exceeds the target multiplier (1 for N+1, 2 for N+2), the assessment passes.

        This is an ASSESSMENT only — it reports against measured live state and does not
        modify cluster configuration in any way.

        Two-node clusters receive an informational note: two-way mirror keeps a full copy
        on each node, so a drained node does not lose data availability; this assessment
        focuses on operating headroom rather than data safety.

    .PARAMETER PoolFreeBytes
        Pool RemainingSize in bytes (from S2DStoragePool.RemainingSize.Bytes).

    .PARAMETER RebuildReserveRecommendedBytes
        The recommended rebuild reserve in bytes (from S2DCapacityWaterfall.ReserveRecommended.Bytes).

    .PARAMETER PhysicalDisks
        Array of physical disk objects. Must include NodeName, Role, and SizeBytes properties.
        Only pool-member capacity disks (Role='Capacity', IsPoolMember -ne $false) are used.

    .PARAMETER NodeCount
        Number of nodes in the cluster (used for the two-node note).

    .PARAMETER Target
        Assessment target: 'N+1' (default), 'N+2', or 'None' (assessment skipped).

    .OUTPUTS
        PSCustomObject with:
          Target, RequiredCapacity [S2DCapacity], AvailableHeadroom [S2DCapacity],
          Meets [bool], Status [string], Note [string]
        Returns $null-safe 'Unknown' result if inputs are missing or invalid.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int64] $PoolFreeBytes = [int64]0,

        [Parameter()]
        [int64] $RebuildReserveRecommendedBytes = [int64]0,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PhysicalDisks = @(),

        [Parameter()]
        [int] $NodeCount = 0,

        [Parameter()]
        [ValidateSet('None', 'N+1', 'N+2')]
        [string] $Target = 'N+1'
    )

    # ── Helper: build an unknown/graceful result ──────────────────────────────
    function local:New-UnknownResult {
        param([string]$Reason)
        [PSCustomObject]@{
            Target             = $Target
            RequiredCapacity   = $null
            AvailableHeadroom  = $null
            Meets              = $false
            Status             = 'Unknown'
            Note               = $Reason
        }
    }

    # ── None target: skip assessment ─────────────────────────────────────────
    if ($Target -eq 'None') {
        return [PSCustomObject]@{
            Target             = 'None'
            RequiredCapacity   = [S2DCapacity]::new([int64]0)
            AvailableHeadroom  = [S2DCapacity]::new([int64]0)
            Meets              = $true
            Status             = 'Meets'
            Note               = 'Maintenance reserve assessment is disabled (Target=None).'
        }
    }

    # ── Guard: empty disk list ────────────────────────────────────────────────
    if (-not $PhysicalDisks -or $PhysicalDisks.Count -eq 0) {
        return New-UnknownResult 'No physical disk data available — cannot determine largest-node capacity.'
    }

    # ── Determine largest-node raw bytes ─────────────────────────────────────
    # Scope: pool-member capacity disks only (Role='Capacity', IsPoolMember -ne $false).
    # Pre-1.2.0 fixtures may lack IsPoolMember — treat absence as pool member.
    $capacityDisks = @($PhysicalDisks | Where-Object {
        $_.Role -eq 'Capacity' -and $_.IsPoolMember -ne $false
    })

    if ($capacityDisks.Count -eq 0) {
        return New-UnknownResult 'No pool-member capacity disks found — cannot determine largest-node capacity.'
    }

    $byNode = @($capacityDisks | Group-Object NodeName)

    if ($byNode.Count -eq 0) {
        return New-UnknownResult 'Could not group capacity disks by node — NodeName property may be missing.'
    }

    # Sum SizeBytes per node, then take the maximum.
    $nodeRawBytes = [int64]0
    foreach ($nodeGroup in $byNode) {
        $nodeTotalRaw = [int64](
            ($nodeGroup.Group | ForEach-Object {
                if ($null -ne $_.SizeBytes) { [int64]$_.SizeBytes } else { [int64]0 }
            } | Measure-Object -Sum).Sum
        )
        if ($nodeTotalRaw -gt $nodeRawBytes) {
            $nodeRawBytes = $nodeTotalRaw
        }
    }

    if ($nodeRawBytes -le 0) {
        return New-UnknownResult 'Largest-node raw capacity resolved to zero — disk SizeBytes may be missing.'
    }

    # ── Compute assessment values ─────────────────────────────────────────────
    $multiplier = switch ($Target) {
        'N+1' { [int64]1 }
        'N+2' { [int64]2 }
        default { [int64]0 }
    }

    $requiredBytes = $multiplier * $nodeRawBytes

    # Headroom = free pool space minus the rebuild reserve that must always be held.
    # This is what remains for a maintenance operation once the rebuild reserve is ring-fenced.
    $headroomBytes = [math]::Max([int64]0, $PoolFreeBytes - $RebuildReserveRecommendedBytes)

    $meets = $headroomBytes -ge $requiredBytes

    $status = if ($meets) { 'Meets' } else { 'Does not meet' }

    # ── Two-node informational note ───────────────────────────────────────────
    $note = if ($NodeCount -eq 2) {
        "Two-way mirror keeps a full copy on each node, so a drained node does not lose data availability; this assesses operating headroom with a node offline."
    } else {
        "Microsoft WAF recommends holding at least one node's worth of raw capacity as maintenance reserve beyond the rebuild reserve, so a node can be fully drained for patching."
    }

    [PSCustomObject]@{
        Target            = $Target
        RequiredCapacity  = [S2DCapacity]::new($requiredBytes)
        AvailableHeadroom = [S2DCapacity]::new($headroomBytes)
        Meets             = $meets
        Status            = $status
        Note              = $note
    }
}
