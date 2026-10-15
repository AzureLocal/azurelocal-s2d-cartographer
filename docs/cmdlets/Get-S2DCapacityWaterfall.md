# Get-S2DCapacityWaterfall

Computes the 7-stage theoretical capacity waterfall from raw physical to final usable capacity.

---

## Synopsis

Extracts inputs from the live cluster session (physical disks, pool, volumes) and computes the 7-stage waterfall model. The waterfall is entirely theoretical — it represents what the hardware *can* deliver, not what has been provisioned.

Stage deductions are applied in sequence:

| Stage | Description | Deduction |
|---|---|---|
| 1 | Raw Physical | Pool-member capacity-tier disk total |
| 2 | After Format | File system and partition overhead (~0.9%) |
| 3 | After Pool Overhead | S2D pool management overhead (~1%) |
| 4 | After Reserve | Rebuild reserve: `min(NodeCount, 4) × one drive` |
| 5 | After Infrastructure | Azure Local system volumes (UserStorage, SBEAgent, etc.) |
| 6 | After Resiliency | Resiliency factor deduction (÷ NumberOfDataCopies) |
| 7 | Usable Capacity | Final available capacity for workload volumes |

Requires an active session from `Connect-S2DCluster`.

This cmdlet takes no parameters.

---

## Syntax

```powershell
Get-S2DCapacityWaterfall
```

---

## Outputs

`S2DCapacityWaterfall` — contains the full waterfall model.

Key properties:

| Property | Description |
|---|---|
| `Stages` | Array of `S2DWaterfallStage` objects (one per stage) |
| `UsableCapacity` | Final Stage 7 usable capacity as `S2DCapacity` |
| `RawCapacity` | Stage 1 raw capacity as `S2DCapacity` |
| `ResiliencyFactor` | The `NumberOfDataCopies` used in Stage 6 |
| `NodeCount` | Number of cluster nodes contributing to the model |
| `ReserveStatus` | `Adequate` or `Critical` based on reserve vs pool free |
| `BlendedEfficiencyPercent` | Usable / raw capacity efficiency percentage |

Each `S2DWaterfallStage`:

| Property | Description |
|---|---|
| `StageNumber` | 1–7 |
| `StageName` | Human-readable stage name |
| `Capacity` | Cumulative capacity at this stage as `S2DCapacity` |
| `Deducted` | Amount deducted from the previous stage as `S2DCapacity` |
| `Description` | Explanation of the deduction |

---

## Examples

**Compute and display:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DCapacityWaterfall
```

**Show the stage table:**

```powershell
Get-S2DCapacityWaterfall | Select-Object -ExpandProperty Stages | Format-Table StageNumber, StageName, Capacity, Deducted
```

**Get the usable capacity number:**

```powershell
$waterfall = Get-S2DCapacityWaterfall
"Usable: $($waterfall.UsableCapacity.Display)"
```

---

## Related

See [Capacity Math](../capacity-math.md) for a detailed explanation of each stage formula, and [Collectors / Capacity Waterfall](../collectors/capacity-waterfall.md) for the full pipeline context.
