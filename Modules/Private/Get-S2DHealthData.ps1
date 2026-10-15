# CIM wrappers for health-related queries — thin shims for Pester mockability

function Get-S2DHealthFaultData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-HealthFault -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-HealthFault -ErrorAction SilentlyContinue
}

function Get-S2DStorageSubSystemData {
    param([CimSession] $CimSession)
    if ($PSBoundParameters.ContainsKey('CimSession')) {
        Get-StorageSubSystem -CimSession $CimSession -ErrorAction SilentlyContinue
        return
    }
    Get-StorageSubSystem -ErrorAction SilentlyContinue
}

function Get-S2DStorageHealthReportData {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $StorageSubSystem,

        [CimSession] $CimSession
    )
    process {
        try {
            if ($PSBoundParameters.ContainsKey('CimSession')) {
                $StorageSubSystem | Debug-StorageSubSystem -CimSession $CimSession -ErrorAction SilentlyContinue
                return
            }
            $StorageSubSystem | Debug-StorageSubSystem -ErrorAction SilentlyContinue
        } catch {
            $null
        }
    }
}
