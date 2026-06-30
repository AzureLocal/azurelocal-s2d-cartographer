# S2DCartographer data model classes
# Depends on S2DCapacity (loaded first — Capacity sorts before Classes alphabetically)

class S2DStoragePool {
    [string]      $FriendlyName
    [string]      $HealthStatus
    [string]      $OperationalStatus
    [bool]        $IsReadOnly
    [S2DCapacity] $TotalSize
    [S2DCapacity] $AllocatedSize
    [S2DCapacity] $RemainingSize
    [S2DCapacity] $ProvisionedSize
    [double]      $OvercommitRatio
    [string]      $FaultDomainAwareness
    [int64]       $WriteCacheSizeDefault
    [object[]]    $ResiliencySettings
    [object[]]    $StorageTiers
}

class S2DVolume {
    [string]      $FriendlyName
    [string]      $FileSystem
    [string]      $ResiliencySettingName
    [int]         $NumberOfDataCopies
    [int]         $PhysicalDiskRedundancy
    [string]      $ProvisioningType
    [S2DCapacity] $Size
    [S2DCapacity] $FootprintOnPool
    [S2DCapacity] $AllocatedSize
    [string]      $OperationalStatus
    [string]      $HealthStatus
    [bool]        $IsDeduplicationEnabled
    [bool]        $IsInfrastructureVolume
    [double]      $EfficiencyPercent
    [double]      $OvercommitRatio
    # Thin provisioning fields — populated only when ProvisioningType = 'Thin'
    [S2DCapacity] $ThinGrowthHeadroom      # Size - AllocatedSize (how much more can be written)
    [S2DCapacity] $MaxPotentialFootprint   # Size × NumberOfDataCopies (full pool footprint if completely written)
}

class S2DCacheTier {
    [string]      $CacheMode
    [bool]        $IsAllFlash
    [bool]        $SoftwareCacheEnabled
    [int]         $CacheDiskCount
    [string]      $CacheDiskModel
    [S2DCapacity] $CacheDiskSize
    [double]      $CacheToCapacityRatio
    [string]      $CacheState
    [int64]       $WriteCacheSizeBytes
}

class S2DHealthCheck {
    # Legacy fields — always populated for backward compatibility
    [string] $CheckName
    [string] $Severity
    [string] $Status
    [string] $Details
    [string] $Remediation
    # Graduated scoring fields — added in v1.10.0 (#57)
    [int]    $Weight          # Relative importance (1-3). Loaded from health-checks.json.
    [int]    $MaxPoints       # Maximum points this check can award (= Weight).
    [double] $AwardedPoints   # Points actually awarded: Pass=MaxPoints, Warn=MaxPoints*0.5, Fail=0.
    [string] $ScoreBand       # Named band for this check: Excellent | Good | Fair | Needs Improvement
    [double] $ScorePercent    # AwardedPoints / MaxPoints * 100 for this individual check.
}

class S2DWaterfallStage {
    [int]         $Stage
    [string]      $Name
    [S2DCapacity] $Size
    [S2DCapacity] $Delta
    [string]      $Description
    [string]      $Status
}

class S2DCapacityWaterfall {
    [S2DWaterfallStage[]] $Stages
    [S2DCapacity]  $RawCapacity
    [S2DCapacity]  $AvailableForVolumes   # Stage 6 — footprint space available for workload volumes
    [S2DCapacity]  $UsableCapacity        # Stage 7 — data (usable) space after resiliency overhead
    [S2DCapacity]  $PlanningLine70Pct     # 70% of AvailableForVolumes (footprint basis — alert threshold)
    [bool]         $IsAbove70PctLine      # true when consumed/planned footprint exceeds the 70% line
    [S2DCapacity]  $ReserveRecommended
    [S2DCapacity]  $ReserveActual
    [string]       $ReserveStatus
    [bool]         $IsOvercommitted
    [double]       $OvercommitRatio
    [int]          $NodeCount
    [double]       $BlendedEfficiencyPercent
}

class S2DClusterData {
    [string]               $ClusterName
    [string]               $ClusterFqdn
    [int]                  $NodeCount
    [string[]]             $Nodes
    [datetime]             $CollectedAt
    [object[]]             $PhysicalDisks
    [S2DStoragePool]       $StoragePool
    [S2DVolume[]]          $Volumes
    [S2DCacheTier]         $CacheTier
    [S2DHealthCheck[]]     $HealthChecks
    [string]               $OverallHealth
    [S2DCapacityWaterfall] $CapacityWaterfall
    # Expansion headroom — how much room remains at 70/80/90/100% fill thresholds.
    # Populated by Get-S2DExpansionHeadroom after the waterfall and volume collection.
    [object]               $ExpansionHeadroom
    # Maintenance reserve assessment — N+1/N+2 compliance check (optional, read-only).
    # Populated by Get-S2DMaintenanceReserveAssessment after the waterfall is computed.
    # $null when -MaintenanceReserveTarget = 'None' is not set and data is unavailable.
    [object]               $MaintenanceReserveAssessment
}
