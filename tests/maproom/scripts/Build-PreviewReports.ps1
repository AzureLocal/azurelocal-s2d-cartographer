<#
.SYNOPSIS
    Generates HTML, Word, and Excel preview reports from the MAPROOM cluster-snapshot.json
    without requiring a live cluster connection.

.NOTES
    All S2DClusterData construction runs inside the module scope so that the PowerShell
    class types (S2DStoragePool, S2DVolume, etc.) are accessible.
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory = 'C:\S2DCartographer\maproom-preview',
    [string] $SnapshotPath    = '',
    [switch] $Open
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$repoRoot     = Resolve-Path (Join-Path $PSScriptRoot '..\..\..') | Select-Object -ExpandProperty Path
$snapshotPath = if ($SnapshotPath) { $SnapshotPath } else { Join-Path $repoRoot 'samples\cluster-snapshot.json' }

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  S2DCartographer - MAPROOM Preview Report Build               ' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# Import module — classes are in module scope, accessible via & (Get-Module) { }
Write-Host '[1/4] Importing module...' -ForegroundColor DarkGray
Import-Module (Join-Path $repoRoot 'S2DCartographer.psd1') -Force

Write-Host '[2/4] Loading cluster-snapshot.json...' -ForegroundColor DarkGray
$jsonRaw = Get-Content $snapshotPath -Raw

# Run all type-dependent code inside the module scope
Write-Host '[3/4] Building S2DClusterData and generating reports...' -ForegroundColor DarkGray

$result = & (Get-Module S2DCartographer) {
    param($jsonRaw, $outputDir, $author, $company)

    $j = $jsonRaw | ConvertFrom-Json -Depth 20

    function local:Cap {
        param($c)
        if ($null -eq $c) { return $null }
        $b = if ($c.PSObject.Properties['Bytes']) { [int64]$c.Bytes } else { [int64]0 }
        if ($b -eq 0) { return $null }
        [S2DCapacity]::new($b)
    }

    function local:Stage {
        param($s)
        $st             = [S2DWaterfallStage]::new()
        $st.Stage       = [int]$s.Stage
        $st.Name        = [string]$s.Name
        $st.Description = [string]$s.Description
        $st.Status      = [string]$s.Status
        $st.Size        = Cap $s.Size
        $st.Delta       = if ($s.PSObject.Properties['Delta'] -and $s.Delta) { Cap $s.Delta } else { $null }
        $st
    }

    # StoragePool
    $jp   = $j.StoragePool
    $pool = [S2DStoragePool]::new()
    $pool.FriendlyName          = [string]$jp.FriendlyName
    $pool.HealthStatus          = [string]$jp.HealthStatus
    $pool.OperationalStatus     = [string]$jp.OperationalStatus
    $pool.IsReadOnly            = [bool]$jp.IsReadOnly
    $pool.TotalSize             = Cap $jp.TotalSize
    $pool.AllocatedSize         = Cap $jp.AllocatedSize
    $pool.RemainingSize         = Cap $jp.RemainingSize
    $pool.ProvisionedSize       = if ($jp.PSObject.Properties['ProvisionedSize'] -and $jp.ProvisionedSize) { Cap $jp.ProvisionedSize } else { $null }
    $pool.OvercommitRatio       = [double]$jp.OvercommitRatio
    $pool.FaultDomainAwareness  = [string]$jp.FaultDomainAwareness

    # Volumes
    $volumes = @($j.Volumes | ForEach-Object {
        $jv = $_
        $v  = [S2DVolume]::new()
        $v.FriendlyName           = [string]$jv.FriendlyName
        $v.FileSystem             = [string]$jv.FileSystem
        $v.ResiliencySettingName  = [string]$jv.ResiliencySettingName
        $v.NumberOfDataCopies     = [int]$jv.NumberOfDataCopies
        $v.PhysicalDiskRedundancy = [int]$jv.PhysicalDiskRedundancy
        $v.ProvisioningType       = [string]$jv.ProvisioningType
        $v.OperationalStatus      = [string]$jv.OperationalStatus
        $v.HealthStatus           = [string]$jv.HealthStatus
        $v.IsDeduplicationEnabled = [bool]$jv.IsDeduplicationEnabled
        $v.IsInfrastructureVolume = [bool]$jv.IsInfrastructureVolume
        $v.EfficiencyPercent      = [double]$jv.EfficiencyPercent
        $v.OvercommitRatio        = [double]$jv.OvercommitRatio
        $v.Size                   = Cap $jv.Size
        $v.FootprintOnPool        = Cap $jv.FootprintOnPool
        $v.AllocatedSize          = Cap $jv.AllocatedSize
        if ($jv.PSObject.Properties['ThinGrowthHeadroom'] -and $jv.ThinGrowthHeadroom) {
            $v.ThinGrowthHeadroom = Cap $jv.ThinGrowthHeadroom
        }
        if ($jv.PSObject.Properties['MaxPotentialFootprint'] -and $jv.MaxPotentialFootprint) {
            $v.MaxPotentialFootprint = Cap $jv.MaxPotentialFootprint
        }
        $v
    })

    # CacheTier
    $jc    = $j.CacheTier
    $cache = [S2DCacheTier]::new()
    $cache.CacheMode            = [string]$jc.CacheMode
    $cache.IsAllFlash           = [bool]$jc.IsAllFlash
    $cache.SoftwareCacheEnabled = [bool]$jc.SoftwareCacheEnabled
    $cache.CacheDiskCount       = [int]$jc.CacheDiskCount
    $cache.CacheDiskModel       = [string]$jc.CacheDiskModel
    $cache.CacheToCapacityRatio = [double]$jc.CacheToCapacityRatio
    $cache.CacheState           = [string]$jc.CacheState
    $cache.CacheDiskSize        = Cap $jc.CacheDiskSize

    # CapacityWaterfall
    $jw = $j.CapacityWaterfall
    $wf = [S2DCapacityWaterfall]::new()
    $wf.RawCapacity              = Cap $jw.RawCapacity
    $wf.UsableCapacity           = Cap $jw.UsableCapacity
    $wf.ReserveRecommended       = Cap $jw.ReserveRecommended
    $wf.ReserveActual            = Cap $jw.ReserveActual
    $wf.ReserveStatus            = [string]$jw.ReserveStatus
    $wf.IsOvercommitted          = [bool]$jw.IsOvercommitted
    $wf.OvercommitRatio          = [double]$jw.OvercommitRatio
    $wf.NodeCount                = [int]$jw.NodeCount
    $wf.BlendedEfficiencyPercent = [double]$jw.BlendedEfficiencyPercent
    $wf.Stages                   = @($jw.Stages | ForEach-Object { Stage $_ })

    # HealthChecks
    $healthChecks = @($j.HealthChecks | ForEach-Object {
        $hc             = [S2DHealthCheck]::new()
        $hc.CheckName   = [string]$_.CheckName
        $hc.Severity    = [string]$_.Severity
        $hc.Status      = [string]$_.Status
        $hc.Details     = [string]$_.Details
        $hc.Remediation = [string]$_.Remediation
        $hc
    })

    # PhysicalDisks (plain PSCustomObjects — exporters read properties by name)
    $physDisks = @($j.PhysicalDisks | ForEach-Object {
        $d  = $_
        $sz = if ($d.PSObject.Properties['Size'] -and $d.Size) { Cap $d.Size } else { $null }
        [PSCustomObject]@{
            NodeName          = [string]$d.NodeName
            FriendlyName      = [string]$d.FriendlyName
            SerialNumber      = [string]$d.SerialNumber
            Model             = [string]$d.Model
            MediaType         = [string]$d.MediaType
            BusType           = [string]$d.BusType
            FirmwareVersion   = [string]$d.FirmwareVersion
            Role              = [string]$d.Role
            HealthStatus      = [string]$d.HealthStatus
            OperationalStatus = [string]$d.OperationalStatus
            Size              = $sz
            SizeBytes         = [int64]$d.SizeBytes
            WearPercentage    = if ($d.PSObject.Properties['WearPercentage']) { $d.WearPercentage } else { $null }
            Temperature       = if ($d.PSObject.Properties['Temperature']) { $d.Temperature } else { $null }
            PowerOnHours      = if ($d.PSObject.Properties['PowerOnHours']) { $d.PowerOnHours } else { $null }
            ReadErrors        = if ($d.PSObject.Properties['ReadErrors']) { $d.ReadErrors } else { $null }
            WriteErrors       = if ($d.PSObject.Properties['WriteErrors']) { $d.WriteErrors } else { $null }
            IsPoolMember      = if ($d.PSObject.Properties['IsPoolMember']) { [bool]$d.IsPoolMember } else { $true }
        }
    })

    # Assemble S2DClusterData
    $data                   = [S2DClusterData]::new()
    $data.ClusterName       = [string]$j.Cluster.Name
    $data.ClusterFqdn       = [string]$j.Cluster.Fqdn
    $data.NodeCount         = [int]$j.Cluster.NodeCount
    $data.Nodes             = @($j.Cluster.Nodes)
    $data.CollectedAt       = [datetime]$j.Cluster.CollectedAt
    $data.PhysicalDisks     = $physDisks
    $data.StoragePool       = $pool
    $data.Volumes           = $volumes
    $data.CacheTier         = $cache
    $data.CapacityWaterfall = $wf
    $data.HealthChecks      = $healthChecks
    $data.OverallHealth     = [string]$j.OverallHealth

    # Generate reports (New-S2DReport is a public function, accessible in module scope)
    $files = New-S2DReport -InputObject $data -Format Html, Word, Excel `
        -Author $author -Company $company `
        -OutputDirectory $outputDir

    # Return summary for outer scope
    [PSCustomObject]@{
        ClusterName = $data.ClusterName
        NodeCount   = $data.NodeCount
        Health      = $data.OverallHealth
        Files       = $files
    }
} $jsonRaw $OutputDirectory 'MAPROOM Simulation' 'Infinite Improbability Corp'

Write-Host "      Cluster : $($result.ClusterName)" -ForegroundColor Gray
Write-Host "      Nodes   : $($result.NodeCount)" -ForegroundColor Gray
Write-Host "      Health  : $($result.Health)" -ForegroundColor Gray

Write-Host ''
Write-Host '[4/4] Output files:' -ForegroundColor DarkGray
foreach ($f in $result.Files) {
    Write-Host "      $f" -ForegroundColor Green
}
Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  Build complete.' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

if ($Open) {
    Start-Process explorer.exe $OutputDirectory
}
