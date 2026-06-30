# Get-S2DExpansionHeadroom — calculates remaining room to expand or create volumes
# at 70 / 80 / 90 / 100% fill thresholds against AvailableForVolumes (footprint basis).
#
# CANONICAL MATH (docs/capacity-model.md):
#   A     = CapacityWaterfall.AvailableForVolumes.Bytes  (excludes pool meta, reserve, infra)
#   U     = sum of FootprintOnPool.Bytes for non-infra volumes
#   copies = prevailing NumberOfDataCopies among non-infra volumes (assumed for new volumes)
#   currentUtilizationPct = U / A * 100
#   For X in {0.70, 0.80, 0.90, 1.00}:
#     footprintBudgetBytes    = X * A
#     remainingFootprintBytes = max(0, X*A - U)
#     remainingNewUsableBytes = remainingFootprintBytes / copies
#     isPastLine              = (U > X*A)

function Get-S2DExpansionHeadroom {
    <#
    .SYNOPSIS
        Calculates expansion headroom at 70/80/90/100% fill thresholds.

    .DESCRIPTION
        Given a completed capacity waterfall and the current volume map, computes
        how much footprint space and new usable data capacity remain before each
        fill threshold is crossed.  Uses the prevailing (most-common)
        NumberOfDataCopies among non-infrastructure volumes to estimate new-volume
        usable data from remaining footprint.

        All capacity values are returned as [S2DCapacity] objects carrying both
        TiB (binary) and TB (decimal) representations.

    .PARAMETER Waterfall
        The S2DCapacityWaterfall object from Get-S2DCapacityWaterfall.
        AvailableForVolumes.Bytes is the denominator (A).

    .PARAMETER Volumes
        Array of S2DVolume objects from Get-S2DVolumeMap.
        Only non-infrastructure volumes contribute to the used footprint (U).

    .OUTPUTS
        PSCustomObject with CurrentUtilizationPct, PrevalentDataCopies,
        AvailableForVolumesBytes, UsedFootprintBytes, HasThinVolumes, and a
        Thresholds array. Each threshold row includes SizeToEnterTiB — the
        value to type into New-Volume -Size or WAC (PowerShell/WAC read size
        suffixes as binary, so 1 TB = 1 TiB; value is floor-rounded to 2
        decimals so the new volume always fits).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Waterfall,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Volumes
    )

    # A = available for volumes (footprint basis, excludes meta + reserve + infra)
    $availBytes = if ($Waterfall -and $Waterfall.AvailableForVolumes -and
                      $Waterfall.AvailableForVolumes.Bytes -gt 0) {
        [int64]$Waterfall.AvailableForVolumes.Bytes
    } else {
        [int64]0
    }

    # Non-infrastructure volumes only
    $workloadVols = @($Volumes | Where-Object { -not $_.IsInfrastructureVolume })

    # Thin provisioning presence flag — used by report renderers for Part A:
    # the 70% amber warning is only shown when thin volumes are present.
    # When all volumes are fixed, 70% is rendered as advisory/neutral.
    # Null-safe: -eq against $null returns $false, so missing ProvisioningType defaults to non-thin.
    $hasThinVolumes = [bool]($workloadVols | Where-Object { $_.ProvisioningType -eq 'Thin' })

    # U = sum of footprint bytes for non-infra volumes
    $usedBytes = [int64](
        ($workloadVols | ForEach-Object {
            if ($_.FootprintOnPool -and $_.FootprintOnPool.Bytes -gt 0) {
                [int64]$_.FootprintOnPool.Bytes
            } else { [int64]0 }
        } | Measure-Object -Sum).Sum
    )

    # Prevailing data copies — most common NumberOfDataCopies among non-infra volumes.
    # Defaults to 2 (two-way mirror) when volumes list is empty.
    $prevalentCopies = if ($workloadVols.Count -gt 0) {
        $grouped = $workloadVols |
            Group-Object -Property NumberOfDataCopies |
            Sort-Object -Property Count -Descending
        [int]$grouped[0].Name
    } else {
        2
    }

    $currentPct = if ($availBytes -gt 0) {
        [math]::Round($usedBytes / $availBytes * 100, 1)
    } else { 0.0 }

    $thresholds = foreach ($pct in @(70, 80, 90, 100)) {
        $fraction              = $pct / 100.0
        $budgetBytes           = [int64][math]::Round($fraction * $availBytes)
        $remainingFootprint    = [int64][math]::Max([int64]0, $budgetBytes - $usedBytes)
        $remainingUsable       = if ($prevalentCopies -gt 0) {
            [int64][math]::Round($remainingFootprint / $prevalentCopies)
        } else { [int64]0 }
        $isPast                = ($usedBytes -gt $budgetBytes)

        # SizeToEnterTiB: the exact number to type into New-Volume -Size or WAC.
        # PowerShell and WAC parse size suffixes as binary (1 TB = 1 TiB), so
        # this equals NewUsableData.TiB, floor-rounded to 2 decimals so the new
        # volume always fits. Past-line rows set to 0.
        $sizeToEnterTiB = if ($isPast) {
            [double]0
        } else {
            [Math]::Floor(($remainingUsable / 1099511627776.0) * 100) / 100
        }

        [PSCustomObject]@{
            FillTargetPct               = $pct
            FootprintBudget             = [S2DCapacity]::new($budgetBytes)
            RemainingFootprint          = [S2DCapacity]::new($remainingFootprint)
            NewUsableData               = [S2DCapacity]::new($remainingUsable)
            SizeToEnterTiB              = $sizeToEnterTiB
            IsPastLine                  = $isPast
            IsRecommendedPlanningLine   = ($pct -eq 70)
        }
    }

    [PSCustomObject]@{
        CurrentUtilizationPct     = $currentPct
        PrevalentDataCopies       = $prevalentCopies
        PrevalentCopiesNote       = "Assumed for new-volume estimates. Actual resiliency can differ."
        AvailableForVolumesBytes  = $availBytes
        UsedFootprintBytes        = $usedBytes
        HasThinVolumes            = $hasThinVolumes
        Thresholds                = @($thresholds)
    }
}
