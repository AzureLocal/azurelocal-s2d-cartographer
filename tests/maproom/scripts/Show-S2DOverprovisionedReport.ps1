<#
.SYNOPSIS
    Generates an HTML report for a synthetic *overprovisioned* S2D cluster
    so you can see exactly what S2DCartographer renders when the pool has
    been over-allocated and the recommended rebuild reserve is gone.

.DESCRIPTION
    Builds an in-memory S2DClusterData object representing a fictional
    4-node IIC cluster whose volumes add up to more than the pool's
    available capacity and leave no room for the 1-node rebuild reserve.
    Passes that object to New-S2DReport -Format Html to render the same
    report that would be produced from a live cluster in this state.

    This is offline: no WinRM, no CIM, no domain, no cluster required.

.PARAMETER OutputDirectory
    Where the generated HTML is written. Defaults to C:\S2DCartographer.

.PARAMETER Open
    Launch the generated HTML in the default browser.

.EXAMPLE
    .\tests\maproom\scripts\Show-S2DOverprovisionedReport.ps1 -Open

.NOTES
    All company / cluster data follows the IIC canonical standard.
    See tests/maproom/docs/maproom-guide.md for the MAPROOM overview.
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory = 'C:\S2DCartographer',
    [switch] $Open
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..') | Select-Object -ExpandProperty Path

Write-Host ''
Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host '  S2DCartographer — Overprovisioned Cluster Report Simulation       ' -ForegroundColor Cyan
Write-Host '  Cluster: azlocal-iic-s2d-01  (Infinite Improbability Corp)        ' -ForegroundColor Cyan
Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host '[1/4] Importing S2DCartographer module...' -ForegroundColor DarkGray
# Dot-source class files into caller scope so type literals are available at runtime
. (Join-Path $repoRoot 'Modules\Classes\S2DCapacity.ps1')
. (Join-Path $repoRoot 'Modules\Classes\S2DClasses.ps1')
Import-Module (Join-Path $repoRoot 'S2DCartographer.psd1') -Force

# -----------------------------------------------------------------------------
# Cluster dimensions
# 4 nodes × 4× 3.84 TB NVMe  =  61.44 TB raw (TB decimal)
# Three-way mirror → ~33% storage efficiency
# Reserve recommended = 1 node-worth = 15.36 TB raw
# Available for volumes = 61.44 − 15.36 = 46.08 TB raw → 15.36 TB effective
# -----------------------------------------------------------------------------

Write-Host '[2/4] Building synthetic cluster data (overprovisioned scenario)...' -ForegroundColor DarkGray

$driveSizeBytes = 3840000000000           # 3.84 TB
$rawPoolBytes   = 16 * $driveSizeBytes    # 4 nodes × 4 drives = 61.44 TB

# Physical disks — 16 total
$physicalDisks = @()
$nodeNames     = @('azl-iic-n01', 'azl-iic-n02', 'azl-iic-n03', 'azl-iic-n04')
foreach ($i in 0..3) {
    $nodeName = $nodeNames[$i]
    foreach ($d in 1..4) {
        $physicalDisks += [pscustomobject]@{
            NodeName          = $nodeName
            DiskNumber        = $d
            FriendlyName      = 'INTEL SSDPE2KX040T8'
            SerialNumber      = ('IIC{0:D2}N{1:D2}D{2:D1}' -f ($i+1), ($i+1), $d)
            Model             = 'INTEL SSDPE2KX040T8'
            MediaType         = 'NVMe'
            BusType           = 'NVMe'
            FirmwareVersion   = 'VCV10162'
            Manufacturer      = 'Intel'
            Role              = 'Capacity'
            Usage             = 'Auto-Select'
            CanPool           = $false
            HealthStatus      = 'Healthy'
            OperationalStatus = 'OK'
            PhysicalLocation  = "Node $nodeName : Slot $d"
            SlotNumber        = $d
            Size              = [S2DCapacity]::new([int64]$driveSizeBytes)
            SizeBytes         = $driveSizeBytes
            Temperature       = 37 + ($d * 2)
            WearPercentage    = 3 + ($i * 2) + $d
            PowerOnHours      = 10000 + ($i * 1000) + ($d * 250)
            ReadErrors        = 0
            WriteErrors       = 0
            ReadLatency       = 1
            WriteLatency      = 2
        }
    }
}

# Volumes — these overfill the pool
#   Logical sizes   : 8 + 10 + 5 + 2  = 25 TB
#   3-way footprint : 24 + 30 + 15 + 6 = 75 TB     (vs 61.44 TB raw pool)
#   Pool allocated  : 75 TB — exceeds total 61.44 TB → OvercommitRatio ≈ 1.22
#   Reserve actual  : 0 TB (pool is over-subscribed, no free space for rebuild)
$volumes = @(
    [S2DVolume]@{
        FriendlyName           = 'ClusterPerformanceHistory'
        FileSystem             = 'CSVFS_ReFS'
        ResiliencySettingName  = 'Mirror'
        NumberOfDataCopies     = 3
        PhysicalDiskRedundancy = 2
        ProvisioningType       = 'Fixed'
        Size                   = [S2DCapacity]::FromGiB(25)
        FootprintOnPool        = [S2DCapacity]::FromGiB(75)
        AllocatedSize          = [S2DCapacity]::FromGiB(25)
        OperationalStatus      = 'OK'
        HealthStatus           = 'Healthy'
        IsDeduplicationEnabled = $false
        IsInfrastructureVolume = $true
        EfficiencyPercent      = 33.3
        OvercommitRatio        = 1.0
    }
    [S2DVolume]@{
        FriendlyName           = 'VM-OS'
        FileSystem             = 'CSVFS_ReFS'
        ResiliencySettingName  = 'Mirror'
        NumberOfDataCopies     = 3
        PhysicalDiskRedundancy = 2
        ProvisioningType       = 'Fixed'
        Size                   = [S2DCapacity]::FromTB(8)
        FootprintOnPool        = [S2DCapacity]::FromTB(24)
        AllocatedSize          = [S2DCapacity]::FromTB(8)
        OperationalStatus      = 'OK'
        HealthStatus           = 'Healthy'
        IsDeduplicationEnabled = $false
        IsInfrastructureVolume = $false
        EfficiencyPercent      = 33.3
        OvercommitRatio        = 1.0
    }
    [S2DVolume]@{
        FriendlyName           = 'VM-Data'
        FileSystem             = 'CSVFS_ReFS'
        ResiliencySettingName  = 'Mirror'
        NumberOfDataCopies     = 3
        PhysicalDiskRedundancy = 2
        ProvisioningType       = 'Fixed'
        Size                   = [S2DCapacity]::FromTB(10)
        FootprintOnPool        = [S2DCapacity]::FromTB(30)
        AllocatedSize          = [S2DCapacity]::FromTB(10)
        OperationalStatus      = 'OK'
        HealthStatus           = 'Healthy'
        IsDeduplicationEnabled = $false
        IsInfrastructureVolume = $false
        EfficiencyPercent      = 33.3
        OvercommitRatio        = 1.0
    }
    [S2DVolume]@{
        FriendlyName           = 'Backup'
        FileSystem             = 'CSVFS_ReFS'
        ResiliencySettingName  = 'Mirror'
        NumberOfDataCopies     = 3
        PhysicalDiskRedundancy = 2
        ProvisioningType       = 'Fixed'
        Size                   = [S2DCapacity]::FromTB(5)
        FootprintOnPool        = [S2DCapacity]::FromTB(15)
        AllocatedSize          = [S2DCapacity]::FromTB(5)
        OperationalStatus      = 'OK'
        HealthStatus           = 'Healthy'
        IsDeduplicationEnabled = $false
        IsInfrastructureVolume = $false
        EfficiencyPercent      = 33.3
        OvercommitRatio        = 1.0
    }
    [S2DVolume]@{
        FriendlyName           = 'Archive'
        FileSystem             = 'CSVFS_ReFS'
        ResiliencySettingName  = 'Mirror'
        NumberOfDataCopies     = 3
        PhysicalDiskRedundancy = 2
        ProvisioningType       = 'Fixed'
        Size                   = [S2DCapacity]::FromTB(2)
        FootprintOnPool        = [S2DCapacity]::FromTB(6)
        AllocatedSize          = [S2DCapacity]::FromTB(2)
        OperationalStatus      = 'OK'
        HealthStatus           = 'Healthy'
        IsDeduplicationEnabled = $false
        IsInfrastructureVolume = $false
        EfficiencyPercent      = 33.3
        OvercommitRatio        = 1.0
    }
)

# Storage pool — allocated > total by design
$pool = [S2DStoragePool]@{
    FriendlyName          = 'S2D on azlocal-iic-s2d-01'
    HealthStatus          = 'Warning'
    OperationalStatus     = 'Degraded'
    IsReadOnly            = $false
    TotalSize             = [S2DCapacity]::new([int64]$rawPoolBytes)                          # 61.44 TB
    AllocatedSize         = [S2DCapacity]::FromTB(75)                                          # 75 TB  (overcommitted)
    RemainingSize         = [S2DCapacity]::new([int64]0)                                       # 0 bytes free
    ProvisionedSize       = [S2DCapacity]::FromTB(25)                                          # 25 TB logical
    OvercommitRatio       = 1.22
    FaultDomainAwareness  = 'StorageScaleUnit'
    WriteCacheSizeDefault = 1073741824
}

# Cache tier — all NVMe, no separate cache disks
$cacheTier = [S2DCacheTier]@{
    CacheMode             = 'WriteOnly'
    IsAllFlash            = $true
    SoftwareCacheEnabled  = $false
    CacheDiskCount        = 0
    CacheDiskModel        = 'None (all-NVMe)'
    CacheDiskSize         = [S2DCapacity]::new([int64]0)
    CacheToCapacityRatio  = 0.0
    CacheState            = 'NotApplicable'
    WriteCacheSizeBytes   = 1073741824
}

# Capacity waterfall — 8 stages, ending in overcommitted
$stages = @(
    [S2DWaterfallStage]@{ Stage = 1; Name = 'Raw Physical'      ; Size = [S2DCapacity]::FromTB(61.44); Delta = [S2DCapacity]::new(0); Description = '16 × 3.84 TB NVMe across 4 nodes'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 2; Name = 'Pool Total'        ; Size = [S2DCapacity]::FromTB(61.44); Delta = [S2DCapacity]::new(0); Description = 'Entire raw pool'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 3; Name = 'Filesystem Overhead'; Size = [S2DCapacity]::FromTB(60.21); Delta = [S2DCapacity]::FromTB(-1.23); Description = 'ReFS metadata and reserve blocks (~2%)'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 4; Name = 'Rebuild Reserve'   ; Size = [S2DCapacity]::FromTB(44.85); Delta = [S2DCapacity]::FromTB(-15.36); Description = '1 node-worth (15.36 TB raw) held for S2D auto-rebuild'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 5; Name = 'Usable After Reserve'; Size = [S2DCapacity]::FromTB(44.85); Delta = [S2DCapacity]::new(0); Description = 'Raw space available for provisioned volumes'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 6; Name = 'Three-Way Mirror'  ; Size = [S2DCapacity]::FromTB(14.95); Delta = [S2DCapacity]::FromTB(-29.90); Description = '÷3 for numberOfDataCopies = 3'; Status = 'OK' }
    [S2DWaterfallStage]@{ Stage = 7; Name = 'Allocated to Volumes'; Size = [S2DCapacity]::FromTB(25); Delta = [S2DCapacity]::FromTB(10.05); Description = 'Exceeds effective usable by 10 TB'; Status = 'Fail' }
    [S2DWaterfallStage]@{ Stage = 8; Name = 'Free for Growth'   ; Size = [S2DCapacity]::new(0); Delta = [S2DCapacity]::FromTB(-14.95); Description = 'No room for new volumes; rebuild reserve consumed'; Status = 'Fail' }
)

$waterfall = [S2DCapacityWaterfall]@{
    Stages                  = $stages
    RawCapacity             = [S2DCapacity]::FromTB(61.44)
    UsableCapacity          = [S2DCapacity]::FromTB(14.95)
    ReserveRecommended      = [S2DCapacity]::FromTB(15.36)
    ReserveActual           = [S2DCapacity]::new(0)
    ReserveStatus           = 'Critical'
    IsOvercommitted         = $true
    OvercommitRatio         = 1.22
    NodeCount               = 4
    BlendedEfficiencyPercent = 33.3
}

# Health checks — surface the overprovisioning
$healthChecks = @(
    [S2DHealthCheck]@{ CheckName='ReserveAdequacy'       ; Severity='Error'  ; Status='Fail'; Details='Pool has 0 B free but 15.36 TB is recommended for single-node rebuild. S2D cannot auto-repair after a drive failure.'; Remediation='Remove or shrink volumes to restore at least 15.36 TB of pool free space, or expand the cluster with additional nodes/drives.' }
    [S2DHealthCheck]@{ CheckName='OverCapacity'          ; Severity='Error'  ; Status='Fail'; Details='Pool allocated 75.00 TB exceeds pool total 61.44 TB (122% utilization). Volumes are thin-over-thick oversubscribed.'; Remediation='Reduce allocated volume footprint below pool total. Each TB of volume consumes 3 TB of pool under three-way mirror.' }
    [S2DHealthCheck]@{ CheckName='HighUtilization'       ; Severity='Error'  ; Status='Fail'; Details='Pool utilization is 122%. S2D best practice is to keep utilization below 70%.'; Remediation='Free pool capacity by removing volumes, migrating data off, or adding capacity drives.' }
    [S2DHealthCheck]@{ CheckName='DiskSymmetry'          ; Severity='Info'   ; Status='Pass'; Details='All 4 nodes have an equal 4 capacity disks.'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='VolumeHealth'          ; Severity='Warning'; Status='Pass'; Details='All 5 volumes report Healthy / OK.'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='DiskHealth'            ; Severity='Warning'; Status='Pass'; Details='All 16 physical disks report Healthy / OK.'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='NVMeWear'              ; Severity='Info'   ; Status='Pass'; Details='Highest NVMe wear is 13% on azl-iic-n04/disk 4. Well within drive life.'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='ThinOvercommit'        ; Severity='Error'  ; Status='Fail'; Details='Pool footprint exceeds pool total capacity. Any write pressure can fail unexpectedly.'; Remediation='Reduce provisioned size or add capacity.' }
    [S2DHealthCheck]@{ CheckName='FirmwareConsistency'   ; Severity='Info'   ; Status='Pass'; Details='All INTEL SSDPE2KX040T8 disks are on firmware VCV10162.'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='RebuildCapacity'       ; Severity='Error'  ; Status='Fail'; Details='Available pool free space (0 B) is below required rebuild reserve (15.36 TB). Drive failure will leave the pool degraded until volumes are reduced.'; Remediation='Restore 15.36 TB of pool free space before relying on auto-rebuild.' }
    [S2DHealthCheck]@{ CheckName='InfrastructureVolume'  ; Severity='Info'   ; Status='Pass'; Details='ClusterPerformanceHistory volume detected (25 GiB, Three-Way Mirror).'; Remediation='' }
    [S2DHealthCheck]@{ CheckName='CacheTierHealth'       ; Severity='Info'   ; Status='Pass'; Details='All-NVMe cluster — no dedicated cache tier.'; Remediation='' }
)

$clusterData = [S2DClusterData]::new()
$clusterData.ClusterName       = 'azlocal-iic-s2d-01'
$clusterData.ClusterFqdn       = 'azlocal-iic-s2d-01.iic.local'
$clusterData.NodeCount         = 4
$clusterData.Nodes             = $nodeNames
$clusterData.CollectedAt       = Get-Date
$clusterData.PhysicalDisks     = $physicalDisks
$clusterData.StoragePool       = $pool
$clusterData.Volumes           = $volumes
$clusterData.CacheTier         = $cacheTier
$clusterData.HealthChecks      = $healthChecks
$clusterData.OverallHealth     = 'Fail'
$clusterData.CapacityWaterfall = $waterfall

# -----------------------------------------------------------------------------
# Render HTML
# -----------------------------------------------------------------------------

Write-Host '[3/4] Rendering HTML report via New-S2DReport...' -ForegroundColor DarkGray

if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$reportPath = $clusterData | New-S2DReport -Format All, Csv -OutputDirectory $OutputDirectory `
    -Author 'MAPROOM simulation' -Company 'Infinite Improbability Corp'

Write-Host ''
Write-Host '[4/4] Report ready.' -ForegroundColor DarkGray
Write-Host "      File : $reportPath" -ForegroundColor Gray
Write-Host ''
Write-Host 'Scenario summary:' -ForegroundColor Cyan
Write-Host '  Pool total           : 61.44 TB   (4 nodes × 4× 3.84 TB NVMe)' -ForegroundColor Gray
Write-Host '  Pool allocated       : 75.00 TB   (footprint of 5 volumes at 3-way mirror)' -ForegroundColor Red
Write-Host '  Pool free            : 0 B        (overcommitted by ~14 TB)' -ForegroundColor Red
Write-Host '  Rebuild reserve      : 0 TB       (15.36 TB recommended, nothing left)' -ForegroundColor Red
Write-Host '  Effective usable     : 14.95 TB   (logical 25 TB allocated exceeds this)' -ForegroundColor Red
Write-Host '  Health check status  : FAIL       (5 errors, 2 warnings, 5 info)' -ForegroundColor Red
Write-Host ''

if ($Open) {
    Start-Process $reportPath
}
