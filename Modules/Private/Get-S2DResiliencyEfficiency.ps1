# Get-S2DResiliencyEfficiency — returns the usable/footprint efficiency ratio for
# each S2D resiliency type. Used by Get-S2DVolumeMap and Get-S2DCapacityWaterfall.

function Get-S2DResiliencyEfficiency {
    <#
    .SYNOPSIS
        Returns the capacity efficiency percentage for a given S2D resiliency configuration.

    .PARAMETER ResiliencySettingName
        The resiliency setting name: Mirror or Parity.

    .PARAMETER NumberOfDataCopies
        2 = two-way mirror, 3 = three-way mirror. Only applies when ResiliencySettingName = 'Mirror'.

    .PARAMETER PhysicalDiskRedundancy
        Used with Parity volumes. 1 = single parity (dual parity disk redundancy),
        2 = dual parity.

    .PARAMETER NodeCount
        Cluster node count. Kept for parity / Parity efficiency calculations; no longer
        used to infer nested-mirror from node count — use NumberOfDataCopies=4 explicitly.

    .OUTPUTS
        PSCustomObject with ResiliencyType (display name), EfficiencyPercent, Description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Mirror', 'Parity')]
        [string] $ResiliencySettingName,

        [Parameter()]
        [ValidateRange(2, 4)]
        [int] $NumberOfDataCopies = 3,

        [Parameter()]
        [int] $PhysicalDiskRedundancy = 2,

        [Parameter()]
        [int] $NodeCount = 3
    )

    if ($ResiliencySettingName -eq 'Mirror') {
        switch ($NumberOfDataCopies) {
            2 {
                # NumberOfDataCopies=2 is always a plain two-way mirror (50% efficiency).
                # A nested two-way mirror writes 4 physical copies and reports
                # NumberOfDataCopies=4 — use that value, not node count, to detect nesting.
                [PSCustomObject]@{
                    ResiliencyType    = 'Two-Way Mirror'
                    EfficiencyPercent = 50.0
                    Description       = 'Two-way mirror. Usable = footprint ÷ 2. Requires minimum 2 nodes.'
                }
            }
            3 {
                [PSCustomObject]@{
                    ResiliencyType    = 'Three-Way Mirror'
                    EfficiencyPercent = 33.3
                    Description       = 'Three-way mirror. Usable = footprint ÷ 3. Requires minimum 3 nodes.'
                }
            }
            4 {
                # Nested two-way mirror (two-way inside two-way) — writes 4 copies.
                # Available on 2-node clusters. NumberOfDataCopies is 4 in this config.
                [PSCustomObject]@{
                    ResiliencyType    = 'Nested Two-Way Mirror'
                    EfficiencyPercent = 25.0
                    Description       = 'Nested two-way mirror (2-node). Writes 4 copies. Usable = footprint ÷ 4.'
                }
            }
            default {
                [PSCustomObject]@{
                    ResiliencyType    = "Mirror (${NumberOfDataCopies}-copy)"
                    EfficiencyPercent = [math]::Round(100.0 / $NumberOfDataCopies, 1)
                    Description       = "$NumberOfDataCopies-copy mirror. Usable = footprint ÷ $NumberOfDataCopies."
                }
            }
        }
    } else {
        # Parity — efficiency depends on PhysicalDiskRedundancy and node count
        switch ($PhysicalDiskRedundancy) {
            1 {
                [PSCustomObject]@{
                    ResiliencyType    = 'Single Parity'
                    EfficiencyPercent = [math]::Round((($NodeCount - 1) / $NodeCount) * 100, 1)
                    Description       = "Single parity. Efficiency ~$(([math]::Round((($NodeCount - 1) / $NodeCount) * 100, 1)))% with $NodeCount nodes."
                }
            }
            2 {
                [PSCustomObject]@{
                    ResiliencyType    = 'Dual Parity'
                    EfficiencyPercent = [math]::Round((($NodeCount - 2) / $NodeCount) * 100, 1)
                    Description       = "Dual parity. Efficiency ~$(([math]::Round((($NodeCount - 2) / $NodeCount) * 100, 1)))% with $NodeCount nodes."
                }
            }
            default {
                [PSCustomObject]@{
                    ResiliencyType    = 'Parity'
                    EfficiencyPercent = 60.0
                    Description       = 'Estimated parity efficiency. Exact value requires node count and encoding configuration.'
                }
            }
        }
    }
}
