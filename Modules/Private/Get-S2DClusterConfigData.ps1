# CIM wrappers for cluster configuration queries — thin shims for Pester mockability

function Get-S2DResiliencySettingData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-ResiliencySetting -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-ResiliencySetting -ErrorAction SilentlyContinue
}

function Get-S2DStorageTierData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-StorageTier -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-StorageTier -ErrorAction SilentlyContinue
}

function Get-S2DClusterS2DData {
    param([CimSession] $CimSession)
    try {
        if ($PSBoundParameters.ContainsKey('CimSession')) {
            Get-ClusterS2D -CimSession $CimSession -ErrorAction SilentlyContinue
            return
        }
        Get-ClusterS2D -ErrorAction SilentlyContinue
    } catch {
        $null
    }
}

function Get-S2DClusterNodeData {
    param([CimSession] $CimSession)
    try {
        if ($PSBoundParameters.ContainsKey('CimSession')) {
            Get-ClusterNode -ErrorAction SilentlyContinue
            return
        }
        Get-ClusterNode -ErrorAction SilentlyContinue
    } catch {
        $null
    }
}

function Get-S2DStoragePoolResiliencyData {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $StoragePool,

        [CimSession] $CimSession
    )
    process {
        if ($PSBoundParameters.ContainsKey('CimSession')) {
            $StoragePool | Get-ResiliencySetting -CimSession $CimSession -ErrorAction SilentlyContinue
            return
        }
        $StoragePool | Get-ResiliencySetting -ErrorAction SilentlyContinue
    }
}

function Get-S2DStoragePoolTierData {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $StoragePool,

        [CimSession] $CimSession
    )
    process {
        if ($PSBoundParameters.ContainsKey('CimSession')) {
            $StoragePool | Get-StorageTier -CimSession $CimSession -ErrorAction SilentlyContinue
            return
        }
        $StoragePool | Get-StorageTier -ErrorAction SilentlyContinue
    }
}
