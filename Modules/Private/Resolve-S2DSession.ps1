# Resolve-S2DSession — returns the active CimSession or $null for local mode.
# Used by all collector cmdlets to get the right CIM target.

function Resolve-S2DSession {
    param(
        [CimSession] $CimSession
    )

    # Explicit override takes priority
    if ($CimSession) { return $CimSession }

    # Module session CimSession
    if ($Script:S2DSession.CimSession) { return $Script:S2DSession.CimSession }

    # Local mode — return $null, callers omit -CimSession from CIM calls
    if ($Script:S2DSession.IsLocal) { return $null }

    # PSSession path (collectors will handle via Invoke-Command)
    if ($Script:S2DSession.PSSession) { return $null }

    throw "No active S2DCartographer session. Call Connect-S2DCluster first."
}
