function New-S2DDiagram {
    <#
    .SYNOPSIS
        Generates SVG diagrams for capacity waterfall, disk-node map, pool layout, and resiliency.

    .DESCRIPTION
        Accepts an S2DClusterData object and renders SVG diagrams to the output directory.

        Diagram types:
          Waterfall      — 7-stage capacity waterfall horizontal bar diagram
          DiskNodeMap    — Node boxes with disks color-coded by role and health
          PoolLayout     — Storage pool allocation pie chart with reserve and infra segments
          Resiliency     — Per-volume resiliency type, footprint, and efficiency
          HealthCard     — Traffic-light health scorecard
          TiBTBReference — Common NVMe drive sizes in both TiB and TB

        Output files are written to OutputDirectory (default: C:\S2DCartographer).

    .PARAMETER InputObject
        S2DClusterData object from Invoke-S2DCartographer -PassThru. Accepts pipeline input.

    .PARAMETER DiagramType
        One or more diagram types to generate, or 'All'.

    .PARAMETER OutputDirectory
        Destination folder for SVG files. Created if it does not exist.

    .EXAMPLE
        Invoke-S2DCartographer -ClusterName clus01 -PassThru | New-S2DDiagram

    .EXAMPLE
        New-S2DDiagram -InputObject $data -DiagramType Waterfall, DiskNodeMap

    .OUTPUTS
        string[] — paths to generated SVG files
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $InputObject,

        [Parameter()]
        [ValidateSet('Waterfall','DiskNodeMap','PoolLayout','Resiliency','HealthCard','TiBTBReference','All')]
        [string[]] $DiagramType = 'All',

        [Parameter()]
        [string] $OutputDirectory = 'C:\S2DCartographer'
    )

    process {
        if ($InputObject -isnot [S2DClusterData]) {
            throw "InputObject must be an S2DClusterData object. Use Invoke-S2DCartographer -PassThru to obtain one."
        }

        $effectiveTypes = if ('All' -in $DiagramType) {
            @('Waterfall','DiskNodeMap','PoolLayout','Resiliency','HealthCard','TiBTBReference')
        } else { $DiagramType }

        if (-not (Test-Path $OutputDirectory)) {
            New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        }

        $cn    = $InputObject.ClusterName -replace '[^\w\-]', '_'
        $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $nc    = $InputObject.NodeCount

        $outputFiles = @()

        foreach ($type in $effectiveTypes) {
            $path = Join-Path $OutputDirectory "${cn}_${type}_${stamp}.svg"
            Write-Verbose "Generating $type diagram → $path"

            try {
                $svg = switch ($type) {
                    'Waterfall' {
                        if ($InputObject.CapacityWaterfall) {
                            New-S2DWaterfallSvg -Waterfall $InputObject.CapacityWaterfall
                        } else { Write-Warning "Waterfall: no CapacityWaterfall data."; $null }
                    }
                    'DiskNodeMap' {
                        if ($InputObject.PhysicalDisks) {
                            New-S2DDiskNodeMapSvg -PhysicalDisks $InputObject.PhysicalDisks
                        } else { Write-Warning "DiskNodeMap: no PhysicalDisk data."; $null }
                    }
                    'PoolLayout' {
                        if ($InputObject.StoragePool -and $InputObject.CapacityWaterfall) {
                            New-S2DPoolLayoutSvg -Pool $InputObject.StoragePool -Waterfall $InputObject.CapacityWaterfall -Volumes $InputObject.Volumes
                        } else { Write-Warning "PoolLayout: pool or waterfall data missing."; $null }
                    }
                    'Resiliency' {
                        if ($InputObject.Volumes) {
                            New-S2DVolumeResiliencySvg -Volumes $InputObject.Volumes -NodeCount $nc
                        } else { Write-Warning "Resiliency: no volume data."; $null }
                    }
                    'HealthCard' {
                        if ($InputObject.HealthChecks) {
                            New-S2DHealthScorecardSvg -HealthChecks $InputObject.HealthChecks -OverallHealth $InputObject.OverallHealth
                        } else { Write-Warning "HealthCard: no health check data."; $null }
                    }
                    'TiBTBReference' {
                        New-S2DTiBTBReferenceSvg
                    }
                }

                if ($svg) {
                    $svg | Set-Content -Path $path -Encoding UTF8 -Force
                    $outputFiles += $path
                }
            }
            catch {
                Write-Warning "$type diagram failed: $_"
            }
        }

        $outputFiles
    }
}
