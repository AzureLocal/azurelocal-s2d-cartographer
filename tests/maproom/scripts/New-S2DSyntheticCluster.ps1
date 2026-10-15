<#
.SYNOPSIS
    Generates a synthetic S2D cluster fixture using IIC (Infinite Improbability Corp)
    fictional company data for simulation testing.

.DESCRIPTION
    Produces tests/maproom/Fixtures/synthetic-cluster.json without any live connections,
    CIM sessions, or WinRM. All data follows the mandatory IIC canonical standard.

    All company data follows the IIC canonical standard defined in:
    https://azurelocal.github.io/standards/examples

.PARAMETER OutputPath
    Path for the generated fixture. Defaults to tests/maproom/Fixtures/synthetic-cluster.json.

.EXAMPLE
    .\tests\maproom\scripts\New-S2DSyntheticCluster.ps1

.NOTES
    Output: tests/maproom/Fixtures/synthetic-cluster.json
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Fixtures\synthetic-cluster.json')
)

Set-StrictMode -Version Latest

# =============================================================================
# IIC REFERENCE DATA
# All data follows the mandatory IIC (Infinite Improbability Corp) standard.
# Domain: iic.local  |  NetBIOS: IMPROBABLE  |  Public: improbability.cloud
# =============================================================================

$iic = @{
    Company         = 'Infinite Improbability Corp'
    Abbreviation    = 'IIC'
    Domain          = 'iic.local'
    ClusterName     = 'azlocal-iic-s2d-01'
    NodeNames       = @('azl-iic-n01', 'azl-iic-n02', 'azl-iic-n03', 'azl-iic-n04')
    NodeFqdns       = @('azl-iic-n01.iic.local', 'azl-iic-n02.iic.local', 'azl-iic-n03.iic.local', 'azl-iic-n04.iic.local')
    NodeIPs         = @('10.0.0.11', '10.0.0.12', '10.0.0.13', '10.0.0.14')
    HardwareModel   = 'PowerEdge R760'
    HardwareMfr     = 'Dell Inc.'
    StoragePoolName = 'S2D on azlocal-iic-s2d-01'
    SubscriptionId  = '33333333-3333-3333-3333-333333333333'
    ResourceGroup   = 'rg-iic-compute-01'
    TenantId        = '00000000-0000-0000-0000-000000000000'
}

# Disk sizes: 4× 3.84 TB NVMe per node (3,840,000,000,000 bytes each)
$diskSizeBytes  = 3840000000000
$diskTiB        = [Math]::Round($diskSizeBytes / 1099511627776, 3)   # 3.492
$diskTB         = [Math]::Round($diskSizeBytes / 1000000000000, 2)   # 3.84

$generatedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

# =============================================================================
# BUILD: physical disks per node
# 4-node cluster, 4× 3.84 TB NVMe capacity per node (no separate cache tier — all-NVMe)
# =============================================================================

$allDisks = @()
foreach ($i in 0..3) {
    $nodeName = $iic.NodeNames[$i]
    foreach ($d in 1..4) {
        $allDisks += [ordered]@{
            NodeName        = $nodeName
            DiskNumber      = $d
            FriendlyName    = "INTEL SSDPE2KX040T8"
            SerialNumber    = "IIC{0:D2}N{1:D2}D{2:D1}" -f ($i+1), ($i+1), $d
            MediaType       = "NVMe"
            BusType         = "NVMe"
            Usage           = "Auto-Select"
            Role            = "Capacity"
            SizeBytes       = $diskSizeBytes
            SizeTiB         = $diskTiB
            SizeTB          = $diskTB
            SizeDisplay     = "$diskTiB TiB ($diskTB TB)"
            Model           = "INTEL SSDPE2KX040T8"
            FirmwareVersion = "VCV10162"
            Manufacturer    = "Intel"
            HealthStatus    = "Healthy"
            OperationalStatus = "OK"
            CanPool         = $false
            WearPercentage  = (Get-Random -Minimum 5 -Maximum 20)
            Temperature     = (Get-Random -Minimum 32 -Maximum 42)
            PowerOnHours    = (Get-Random -Minimum 10000 -Maximum 20000)
            ReadErrors      = 0
            WriteErrors     = 0
        }
    }
}

# =============================================================================
# BUILD: capacity waterfall (4-node, 4× 3.84 TB NVMe, 3-way mirror)
# =============================================================================

$rawBytes          = $diskSizeBytes * 16             # 16 disks total
$rawTiB            = [Math]::Round($rawBytes / 1099511627776, 2)
$rawTB             = [Math]::Round($rawBytes / 1000000000000, 2)

$reserveBytes      = $diskSizeBytes * 4              # min(4,4) × largest = 4 drives
$reserveTiB        = [Math]::Round($reserveBytes / 1099511627776, 2)
$reserveTB         = [Math]::Round($reserveBytes / 1000000000000, 2)

$poolOverheadBytes = [long]($rawBytes * 0.005)       # ~0.5% metadata

$infraVolBytes     = 268435456000                    # 250 GB
$infraVolTiB       = [Math]::Round($infraVolBytes / 1099511627776, 2)
$infraVolTB        = [Math]::Round($infraVolBytes / 1000000000000, 2)

$availableBytes    = $rawBytes - $poolOverheadBytes - $reserveBytes - $infraVolBytes
$availableTiB      = [Math]::Round($availableBytes / 1099511627776, 2)

$usableBytes       = [long]($availableBytes / 3)     # 3-way mirror = 33.3%
$usableTiB         = [Math]::Round($usableBytes / 1099511627776, 2)
$usableTB          = [Math]::Round($usableBytes / 1000000000000, 2)

$waterfall = [ordered]@{
    Raw = [ordered]@{
        Bytes   = $rawBytes
        TiB     = $rawTiB
        TB      = $rawTB
        Display = "$rawTiB TiB ($rawTB TB)"
    }
    AfterPoolOverhead = [ordered]@{
        OverheadBytes = $poolOverheadBytes
        TiB           = [Math]::Round(($rawBytes - $poolOverheadBytes) / 1099511627776, 2)
    }
    Reserve = [ordered]@{
        RecommendedBytes = $reserveBytes
        RecommendedTiB   = $reserveTiB
        RecommendedTB    = $reserveTB
        ActualBytes      = $reserveBytes
        Status           = "Adequate"
    }
    InfrastructureVolume = [ordered]@{
        PresentBytes = $infraVolBytes
        PresentTiB   = $infraVolTiB
        PresentTB    = $infraVolTB
        Detected     = $true
    }
    Available = [ordered]@{
        Bytes   = $availableBytes
        TiB     = $availableTiB
    }
    ResiliencyEfficiency = [ordered]@{
        ResiliencyType = "Mirror"
        NumberOfCopies = 3
        EfficiencyPct  = 33.3
    }
    Usable = [ordered]@{
        Bytes   = $usableBytes
        TiB     = $usableTiB
        TB      = $usableTB
        Display = "$usableTiB TiB ($usableTB TB)"
    }
}

# =============================================================================
# BUILD: health checks
# =============================================================================

$healthChecks = @(
    [ordered]@{ CheckName = "ReserveAdequacy";     Severity = "Critical"; Status = "Pass"; Details = "Reserve $reserveTiB TiB meets recommended $reserveTiB TiB" }
    [ordered]@{ CheckName = "DiskSymmetry";        Severity = "Warning";  Status = "Pass"; Details = "All 4 nodes have 4 disks" }
    [ordered]@{ CheckName = "VolumeHealth";        Severity = "Critical"; Status = "Pass"; Details = "All volumes Healthy" }
    [ordered]@{ CheckName = "DiskHealth";          Severity = "Critical"; Status = "Pass"; Details = "All 16 disks Healthy" }
    [ordered]@{ CheckName = "NvmeWear";            Severity = "Warning";  Status = "Pass"; Details = "All NVMe disks below 80% wear" }
    [ordered]@{ CheckName = "ThinOvercommit";      Severity = "Warning";  Status = "Pass"; Details = "No thin overcommit detected" }
    [ordered]@{ CheckName = "FirmwareConsistency"; Severity = "Info";     Status = "Pass"; Details = "All disks on firmware VCV10162" }
    [ordered]@{ CheckName = "InfraVolume";         Severity = "Info";     Status = "Pass"; Details = "Infrastructure volume detected (250 GB)" }
)

# =============================================================================
# ASSEMBLE: full synthetic cluster document
# =============================================================================

$synthetic = [ordered]@{
    infrastructure_type = "azure_local"
    generatedAt         = $generatedAt
    generatedBy         = "New-S2DSyntheticCluster.ps1"
    company             = $iic.Company
    clusterName         = $iic.ClusterName
    clusterFqdn         = "$($iic.ClusterName).$($iic.Domain)"
    nodeCount           = 4
    nodes               = $iic.NodeFqdns
    storagePoolName     = $iic.StoragePoolName
    physicalDisks       = $allDisks
    capacityWaterfall   = $waterfall
    healthChecks        = $healthChecks
    metadata = [ordered]@{
        subscriptionId  = $iic.SubscriptionId
        resourceGroup   = $iic.ResourceGroup
        tenantId        = $iic.TenantId
        hardwareModel   = $iic.HardwareModel
        hardwareMfr     = $iic.HardwareMfr
    }
    compliance          = [ordered]@{}
    performance         = [ordered]@{}
    user_journey        = [ordered]@{}
    iac                 = [ordered]@{}
}

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

$synthetic | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "✅ Synthetic cluster fixture written to: $OutputPath" -ForegroundColor Green
Write-Host "   Cluster  : $($synthetic.clusterName)" -ForegroundColor Gray
Write-Host "   Nodes    : $($synthetic.nodeCount)" -ForegroundColor Gray
Write-Host "   Disks    : $($allDisks.Count) ($diskTB TB NVMe each)" -ForegroundColor Gray
Write-Host "   Raw Cap  : $rawTiB TiB ($rawTB TB)" -ForegroundColor Gray
Write-Host "   Usable   : $usableTiB TiB ($usableTB TB) after 3-way mirror" -ForegroundColor Gray
