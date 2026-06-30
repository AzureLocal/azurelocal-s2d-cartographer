# Get-S2DMaintenanceReserveAssessment — N+1/N+2 COMPUTE resiliency context note.
#
# IMPORTANT: No #Requires, Set-StrictMode, or $ErrorActionPreference at file scope.
# Private helpers are dot-sourced into the module scope during Import-Module.
# Setting StrictMode or $ErrorActionPreference here bleeds into the module scope
# and breaks empty-data tests that deliberately pass null/empty inputs.
#
# ASSESSMENT ONLY — this function NEVER modifies cluster state.
#
# FRAMING (WAF-grounded, verified against Microsoft Azure Local baseline):
#   N+1/N+2 maintenance reserve is a COMPUTE resiliency concept.
#   Microsoft WAF defines it as: reserve N+1 (or N+2) physical machines worth of
#   CPU + RAM capacity so that a node can be DRAINED for updates (its VMs migrate
#   to remaining nodes) or lost without dropping VMs. This is listed SEPARATELY
#   from storage in the baseline and labeled "compute resiliency."
#
#   Cartographer audits STORAGE; it has no VM compute-allocation data. It cannot
#   perform a real compute drain assessment. This function provides INFORMATIONAL
#   CONTEXT ONLY: it surfaces the raw capacity of the largest node so an
#   administrator can reason about compute headroom. It does NOT produce a
#   storage pass/fail verdict.
#
#   The firm STORAGE reserves documented by Microsoft are:
#     (a) Per-drive rebuild reserve: min(NodeCount, 4) × largest capacity drive.
#     (b) Keep 5–10% of pool unallocated (leave volume footprints within pool).
#   These are handled by Check 1 (ReserveAdequacy) in Get-S2DHealthStatus.
#
# MATH (unchanged — kept for context value):
#   nodeRawBytes = capacity-disk SizeBytes for the LARGEST node
#                  (pool-member Role='Capacity' disks, grouped by NodeName,
#                  take the node whose total is highest)
#   contextBytes = targetMultiplier × nodeRawBytes
#
# Inputs are accepted as plain scalars (bytes) for maximum testability without
# requiring live CIM or a real waterfall object.

function Get-S2DMaintenanceReserveAssessment {
    <#
    .SYNOPSIS
        Returns informational compute-resiliency context for N+1/N+2 node headroom.

    .DESCRIPTION
        Computes the raw capacity of the largest node as context for the operator.
        N+1/N+2 is a COMPUTE resiliency target (reserve one/two nodes' worth of
        CPU + RAM so a node can be drained for updates or survive a node loss without
        dropping VMs). It is NOT a storage-pool capacity requirement.

        Microsoft WAF scopes N+1/N+2 to compute resiliency and lists it separately
        from storage. The storage-pool reserves are the per-drive rebuild reserve
        (min(NodeCount,4) x largest drive) and keeping volume footprints within the
        pool — both handled by the ReserveAdequacy health check.

        Because Cartographer audits storage and has no VM compute-allocation data,
        this function surfaces the largest-node raw capacity as an INFORMATIONAL
        reference only. Status is always 'Info' (not a storage pass/fail).

        Two-node clusters receive an informational note: two-way mirror keeps a full
        copy on each node, so a drained node does not lose data availability.

        This is an ASSESSMENT only — it reports against measured live state and does
        not modify cluster configuration in any way.

    .PARAMETER PoolFreeBytes
        Pool RemainingSize in bytes (from S2DStoragePool.RemainingSize.Bytes).
        Retained for API compatibility; not used in the compliance verdict.

    .PARAMETER RebuildReserveRecommendedBytes
        The recommended rebuild reserve in bytes (from S2DCapacityWaterfall.ReserveRecommended.Bytes).
        Retained for API compatibility; not used in the compliance verdict.

    .PARAMETER PhysicalDisks
        Array of physical disk objects. Must include NodeName, Role, and SizeBytes properties.
        Only pool-member capacity disks (Role='Capacity', IsPoolMember -ne $false) are used
        to compute the largest-node context value.

    .PARAMETER NodeCount
        Number of nodes in the cluster (used for the two-node note).

    .PARAMETER Target
        Compute resiliency target: 'N+1' (default), 'N+2', or 'None' (assessment skipped).

    .OUTPUTS
        PSCustomObject with:
          Target, LargestNodeCapacity [S2DCapacity], ContextCapacity [S2DCapacity],
          Status [string] ('Info' or 'Unknown'), Note [string]
        Returns $null-safe 'Unknown' result if inputs are missing or invalid.
        The legacy Meets and AvailableHeadroom/RequiredCapacity fields are retained
        for JSON schema continuity; Meets is always $null and AvailableHeadroom is
        always $null in the informational framing.
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
            Target               = $Target
            LargestNodeCapacity  = $null
            ContextCapacity      = $null
            # Legacy fields retained for JSON schema compatibility
            RequiredCapacity     = $null
            AvailableHeadroom    = $null
            Meets                = $null
            Status               = 'Unknown'
            Note                 = $Reason
        }
    }

    # ── None target: skip assessment ─────────────────────────────────────────
    if ($Target -eq 'None') {
        return [PSCustomObject]@{
            Target               = 'None'
            LargestNodeCapacity  = [S2DCapacity]::new([int64]0)
            ContextCapacity      = [S2DCapacity]::new([int64]0)
            RequiredCapacity     = [S2DCapacity]::new([int64]0)
            AvailableHeadroom    = $null
            Meets                = $null
            Status               = 'Info'
            Note                 = 'Compute maintenance reserve assessment is disabled (Target=None).'
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

    # ── Compute context values ────────────────────────────────────────────────
    $multiplier = switch ($Target) {
        'N+1' { [int64]1 }
        'N+2' { [int64]2 }
        default { [int64]0 }
    }

    $contextBytes = $multiplier * $nodeRawBytes

    # ── Informational note (compute framing) ──────────────────────────────────
    $twoNodeNote = if ($NodeCount -eq 2) {
        " Two-node cluster: two-way mirror keeps a full copy on each node, so a drained node does not lose data availability."
    } else { '' }

    $note = "N+1/N+2 is a COMPUTE resiliency target (reserve CPU + RAM so a node can be drained for updates or lost without dropping VMs) — not a storage-pool reserve. The largest node holds approximately $([math]::Round($nodeRawBytes / 1TB, 2)) TB raw storage capacity. The firm storage reserves are the per-drive rebuild reserve and keeping volume footprints within the pool.$twoNodeNote"

    [PSCustomObject]@{
        Target               = $Target
        LargestNodeCapacity  = [S2DCapacity]::new($nodeRawBytes)
        ContextCapacity      = [S2DCapacity]::new($contextBytes)
        # Legacy fields retained for JSON schema compatibility — not a storage verdict
        RequiredCapacity     = [S2DCapacity]::new($contextBytes)
        AvailableHeadroom    = $null
        Meets                = $null
        Status               = 'Info'
        Note                 = $note
    }
}
