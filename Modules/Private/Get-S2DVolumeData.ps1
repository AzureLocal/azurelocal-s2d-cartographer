# CIM wrappers for volume-related queries — thin shims for Pester mockability

function Get-S2DVirtualDiskData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-VirtualDisk -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-VirtualDisk -ErrorAction SilentlyContinue
}

function Get-S2DVolumeInfoData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-Volume -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-Volume -ErrorAction SilentlyContinue
}

function Get-S2DClusterSharedVolumeData {
    param([CimSession] $CimSession)
    # Get-ClusterSharedVolume is cluster-aware — use CIM via MSCluster_Resource or direct call
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        try {
            Get-ClusterSharedVolume -ErrorAction SilentlyContinue
        } catch {
            $null
        }
        return
    }
    try {
        Get-ClusterSharedVolume -ErrorAction SilentlyContinue
    } catch {
        $null
    }
}

function Get-S2DVirtualDiskFootprintData {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $VirtualDisk,

        [CimSession] $CimSession
    )
    process {
        if ($PSBoundParameters.ContainsKey('CimSession')) {
            $VirtualDisk | Get-StorageExtent -CimSession $CimSession -ErrorAction SilentlyContinue
            return
        }
        $VirtualDisk | Get-StorageExtent -ErrorAction SilentlyContinue
    }
}
