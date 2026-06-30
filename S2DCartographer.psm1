# S2DCartographer root module loader

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleFolders = @(
    (Join-Path $moduleRoot 'Modules\Classes'),
    (Join-Path $moduleRoot 'Modules\Private'),
    (Join-Path $moduleRoot 'Modules\Collectors'),
    (Join-Path $moduleRoot 'Modules\Outputs\Reports'),
    (Join-Path $moduleRoot 'Modules\Outputs\Templates'),
    (Join-Path $moduleRoot 'Modules\Outputs\Diagrams'),
    (Join-Path $moduleRoot 'Modules\Public')
)

foreach ($folder in $moduleFolders) {
    if (Test-Path -Path $folder) {
        Get-ChildItem -Path $folder -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            ForEach-Object { . $_.FullName }
    }
}

# Module-scoped session state — shared by all cmdlets
$Script:S2DSession = @{
    ClusterName    = $null
    ClusterFqdn    = $null
    Nodes          = @()
    NodeTargets    = @{}
    CimSession     = $null
    PSSession      = $null
    IsConnected    = $false
    IsLocal        = $false
    Authentication = 'Negotiate'
    Credential     = $null
    CollectedData  = @{}
}

# Concurrent collection guard — set by Invoke-S2DCartographer; prevents overlapping runs.
$Script:S2DCollectionInProgress = $false

# Health-check config state (#57/#58/#59)
# $Script:S2DHealthConfig — in-memory override loaded by Import-S2DHealthConfig; $null = use defaults.
# $Script:S2DHealthConfigDefault — cached default loaded from config/health-checks.json on first use.
$Script:S2DHealthConfig        = $null
$Script:S2DHealthConfigDefault = $null

Export-ModuleMember -Function @(
    # Connectivity
    'Connect-S2DCluster',
    'Disconnect-S2DCluster',
    # Collectors
    'Get-S2DPhysicalDiskInventory',
    'Get-S2DStoragePoolInfo',
    'Get-S2DVolumeMap',
    'Get-S2DCacheTierInfo',
    'Get-S2DCapacityWaterfall',
    'Get-S2DHealthStatus',
    # Utilities
    'ConvertTo-S2DCapacity',
    # Orchestrator
    'Invoke-S2DCartographer',
    # What-if modeling
    'Invoke-S2DCapacityWhatIf',
    # Output
    'New-S2DReport',
    'New-S2DDiagram',
    # Health config hot-swap (#57/#58/#59)
    'Export-S2DHealthConfig',
    'Import-S2DHealthConfig'
)
