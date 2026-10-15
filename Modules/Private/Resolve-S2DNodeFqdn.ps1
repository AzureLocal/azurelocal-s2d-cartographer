# Resolve-S2DNodeFqdn — derive a fan-out target FQDN for a cluster node short name.
#
# On workgroup/non-domain-joined management machines, CIM/WinRM sessions typically
# only succeed against fully qualified names listed in TrustedHosts. The cluster's
# MSCluster_Node enumeration returns short names (e.g. 'node01'). This helper
# converts them to FQDNs so per-node fan-out operations actually reach the target.
#
# Strategy, in order:
#   1. If $ShortName already contains a dot, treat it as a FQDN and return unchanged.
#   2. If $ClusterFqdn contains a dot, extract its domain suffix and append to $ShortName.
#   3. Fall back to [System.Net.Dns]::GetHostEntry() to let the OS resolver produce a FQDN.
#   4. If all else fails, return $ShortName unchanged and emit a verbose note — the caller
#      will surface a precise error at preflight if fan-out won't work.
#
# This function performs no network I/O except the optional DNS fallback (step 3) and is
# safe to call with bogus inputs during unit tests by passing a $ClusterFqdn that contains
# a dot (step 2 wins before DNS is consulted).

function Resolve-S2DNodeFqdn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ShortName,

        [Parameter()]
        [string] $ClusterFqdn
    )

    # Already an FQDN — leave it alone.
    if ($ShortName -like '*.*') {
        return $ShortName
    }

    # Cluster was supplied as an FQDN — append its domain suffix.
    if ($ClusterFqdn -and $ClusterFqdn -like '*.*') {
        $suffix = $ClusterFqdn.Substring($ClusterFqdn.IndexOf('.') + 1)
        if ($suffix) {
            return "$ShortName.$suffix"
        }
    }

    # DNS resolver fallback.
    try {
        $entry = [System.Net.Dns]::GetHostEntry($ShortName)
        if ($entry -and $entry.HostName -and $entry.HostName -like '*.*') {
            return $entry.HostName
        }
    }
    catch {
        Write-Verbose "Resolve-S2DNodeFqdn: DNS lookup for '$ShortName' failed: $_"
    }

    return $ShortName
}
