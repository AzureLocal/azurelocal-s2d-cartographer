# What-if JSON output — serializes S2DWhatIfResult to a structured JSON file.

function Export-S2DWhatIfJsonReport {
    param(
        [Parameter(Mandatory)] [object] $Result,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $moduleVersion = try {
        (Get-Module S2DCartographer | Select-Object -First 1).Version.ToString()
    } catch { 'unknown' }

    # Flatten waterfall stages to simple objects for JSON consumers
    function ConvertTo-WaterfallJson {
        param([object] $Waterfall)
        [ordered]@{
            RawCapacityTiB           = $Waterfall.RawCapacity.TiB
            RawCapacityTB            = $Waterfall.RawCapacity.TB
            UsableCapacityTiB        = $Waterfall.UsableCapacity.TiB
            UsableCapacityTB         = $Waterfall.UsableCapacity.TB
            ReserveStatus            = $Waterfall.ReserveStatus
            BlendedEfficiencyPercent = $Waterfall.BlendedEfficiencyPercent
            NodeCount                = $Waterfall.NodeCount
            Stages                   = @($Waterfall.Stages | ForEach-Object {
                [ordered]@{
                    Stage       = $_.Stage
                    Name        = $_.Name
                    SizeTiB     = if ($_.Size)  { $_.Size.TiB  } else { 0 }
                    SizeTB      = if ($_.Size)  { $_.Size.TB   } else { 0 }
                    DeltaTiB    = if ($_.Delta) { $_.Delta.TiB } else { $null }
                    Description = $_.Description
                    Status      = $_.Status
                }
            })
        }
    }

    $output = [ordered]@{
        SchemaVersion = '1.0'
        Type          = 'S2DWhatIfResult'
        Generated     = [ordered]@{
            Timestamp     = (Get-Date).ToUniversalTime().ToString('o')
            ModuleVersion = $moduleVersion
        }
        ScenarioLabel      = $Result.ScenarioLabel
        BaselineNodeCount  = $Result.BaselineNodeCount
        ProjectedNodeCount = $Result.ProjectedNodeCount
        DeltaUsableTiB     = $Result.DeltaUsableTiB
        DeltaUsableTB      = $Result.DeltaUsableTB
        BaselineWaterfall  = ConvertTo-WaterfallJson $Result.BaselineWaterfall
        ProjectedWaterfall = ConvertTo-WaterfallJson $Result.ProjectedWaterfall
        DeltaStages        = @($Result.DeltaStages | ForEach-Object {
            [ordered]@{
                Stage        = $_.Stage
                Name         = $_.Name
                BaselineTiB  = $_.BaselineTiB
                ProjectedTiB = $_.ProjectedTiB
                DeltaTiB     = $_.DeltaTiB
                BaselineTB   = $_.BaselineTB
                ProjectedTB  = $_.ProjectedTB
                DeltaTB      = $_.DeltaTB
            }
        })
    }

    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $output | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputPath -Encoding utf8 -Force
    $OutputPath
}
