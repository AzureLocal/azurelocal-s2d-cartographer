# CSV data exporter — writes flat per-collector CSVs for spreadsheet / Power BI
# consumers who prefer tabular data over nested JSON. Writes multiple files:
#
#   <base>-physical-disks.csv
#   <base>-volumes.csv
#   <base>-health-checks.csv
#   <base>-waterfall.csv
#
# OutputPath acts as a base name; the four suffixes are derived from it. The
# function returns an array of all paths actually written so callers can list
# them in reports.

function Export-S2DCsvReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks  # ignored — CSV always contains ALL disks with IsPoolMember column
    )

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $base = [System.IO.Path]::Combine($dir, [System.IO.Path]::GetFileNameWithoutExtension($OutputPath))

    $written = @()

    # Physical disks
    $diskPath = "$base-physical-disks.csv"
    @($ClusterData.PhysicalDisks) | ForEach-Object {
        [PSCustomObject]@{
            NodeName          = $_.NodeName
            FriendlyName      = $_.FriendlyName
            SerialNumber      = $_.SerialNumber
            Model             = $_.Model
            MediaType         = $_.MediaType
            BusType           = $_.BusType
            Role              = $_.Role
            Usage             = $_.Usage
            IsPoolMember      = $_.IsPoolMember
            SizeBytes         = $_.SizeBytes
            SizeTiB           = if ($_.Size) { $_.Size.TiB } else { 0 }
            SizeTB            = if ($_.Size) { $_.Size.TB }  else { 0 }
            FirmwareVersion   = $_.FirmwareVersion
            HealthStatus      = $_.HealthStatus
            OperationalStatus = $_.OperationalStatus
            WearPercentage    = $_.WearPercentage
            Temperature       = $_.Temperature
            PowerOnHours      = $_.PowerOnHours
            PhysicalLocation  = $_.PhysicalLocation
            SlotNumber        = $_.SlotNumber
        }
    } | Export-Csv -Path $diskPath -NoTypeInformation -Encoding UTF8
    $written += $diskPath

    # Volumes
    $volPath = "$base-volumes.csv"
    @($ClusterData.Volumes) | ForEach-Object {
        [PSCustomObject]@{
            FriendlyName            = $_.FriendlyName
            FileSystem              = $_.FileSystem
            ResiliencySettingName   = $_.ResiliencySettingName
            NumberOfDataCopies      = $_.NumberOfDataCopies
            PhysicalDiskRedundancy  = $_.PhysicalDiskRedundancy
            ProvisioningType        = $_.ProvisioningType
            SizeTiB                 = if ($_.Size) { $_.Size.TiB } else { 0 }
            SizeTB                  = if ($_.Size) { $_.Size.TB }  else { 0 }
            FootprintOnPoolTiB      = if ($_.FootprintOnPool) { $_.FootprintOnPool.TiB } else { 0 }
            FootprintOnPoolTB       = if ($_.FootprintOnPool) { $_.FootprintOnPool.TB }  else { 0 }
            EfficiencyPercent       = $_.EfficiencyPercent
            IsInfrastructureVolume  = $_.IsInfrastructureVolume
            HealthStatus            = $_.HealthStatus
            OperationalStatus       = $_.OperationalStatus
            IsDeduplicationEnabled       = $_.IsDeduplicationEnabled
            ThinGrowthHeadroomTiB        = if ($_.ThinGrowthHeadroom)    { $_.ThinGrowthHeadroom.TiB }    else { '' }
            ThinGrowthHeadroomTB         = if ($_.ThinGrowthHeadroom)    { $_.ThinGrowthHeadroom.TB }     else { '' }
            MaxPotentialFootprintTiB     = if ($_.MaxPotentialFootprint) { $_.MaxPotentialFootprint.TiB } else { '' }
            MaxPotentialFootprintTB      = if ($_.MaxPotentialFootprint) { $_.MaxPotentialFootprint.TB }  else { '' }
        }
    } | Export-Csv -Path $volPath -NoTypeInformation -Encoding UTF8
    $written += $volPath

    # Health checks
    $hcPath = "$base-health-checks.csv"
    @($ClusterData.HealthChecks) | ForEach-Object {
        [PSCustomObject]@{
            CheckName   = $_.CheckName
            Severity    = $_.Severity
            Status      = $_.Status
            Details     = $_.Details
            Remediation = $_.Remediation
        }
    } | Export-Csv -Path $hcPath -NoTypeInformation -Encoding UTF8
    $written += $hcPath

    # Capacity waterfall
    if ($ClusterData.CapacityWaterfall) {
        $wfPath = "$base-waterfall.csv"
        @($ClusterData.CapacityWaterfall.Stages) | ForEach-Object {
            [PSCustomObject]@{
                Stage       = $_.Stage
                Name        = $_.Name
                SizeBytes   = if ($_.Size)  { $_.Size.Bytes }  else { 0 }
                SizeTiB     = if ($_.Size)  { $_.Size.TiB }    else { 0 }
                SizeTB      = if ($_.Size)  { $_.Size.TB }     else { 0 }
                DeltaBytes  = if ($_.Delta) { $_.Delta.Bytes } else { 0 }
                DeltaTiB    = if ($_.Delta) { $_.Delta.TiB }   else { 0 }
                Description = $_.Description
                Status      = $_.Status
            }
        } | Export-Csv -Path $wfPath -NoTypeInformation -Encoding UTF8
        $written += $wfPath
    }

    Write-Verbose "CSV reports written: $($written -join ', ')"
    $written
}
