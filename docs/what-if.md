# What-If Capacity Modeling

`Invoke-S2DCapacityWhatIf` models the capacity impact of proposed hardware changes — adding nodes, adding disks, replacing disks, or changing resiliency — without touching the live cluster.

It applies scenario modifications to a baseline capacity waterfall and recomputes all 7 stages, producing a side-by-side before/after comparison with per-stage deltas.

---

## Syntax

```powershell
# From a JSON snapshot
Invoke-S2DCapacityWhatIf -BaselineSnapshot <path> [scenario parameters] [-OutputDirectory <path>] [-Format <Html|Json>] [-PassThru]

# From a piped S2DClusterData object
Invoke-S2DCartographer -ClusterName <name> -PassThru |
    Invoke-S2DCapacityWhatIf [scenario parameters]

# Against a live cluster (collects then models — does not re-hit the cluster on repeated runs)
Invoke-S2DCapacityWhatIf -ClusterName <name> [scenario parameters]
```

---

## Parameters

### Baseline input (choose one)

| Parameter | Description |
| --- | --- |
| `-BaselineSnapshot` | Path to a JSON snapshot produced by `Invoke-S2DCartographer` (SchemaVersion 1.0). |
| `-InputObject` | An `S2DClusterData` object piped from `Invoke-S2DCartographer -PassThru`. |
| `-ClusterName` | Connect to a live cluster, collect data, then model. Does not re-collect on repeated `-PassThru` calls. |

### Scenario modifications (combinable)

| Parameter | Description |
| --- | --- |
| `-AddNodes <int>` | Number of nodes to add. New nodes are assumed to have the same disk configuration as existing nodes (average disk count × disk size). |
| `-AddDisksPerNode <int>` | Number of capacity disks to add per node. Enforces symmetry — all existing nodes receive the same count. |
| `-NewDiskSizeTB <double>` | Size in decimal TB for new disks added via `-AddNodes` or `-AddDisksPerNode`. Defaults to the existing largest disk. |
| `-ReplaceDiskSizeTB <double>` | Model replacing all capacity disks with disks of this size in decimal TB. Node count and disk count remain the same. |
| `-ChangeResiliency <int>` | Override the resiliency factor (NumberOfDataCopies). `2` = 2-way mirror, `3` = 3-way mirror. |

Scenario parameters can be combined in a single invocation for a composite what-if.

### Output

| Parameter | Description |
| --- | --- |
| `-OutputDirectory <string>` | Directory to write reports to. If omitted, no files are written. |
| `-Format <string[]>` | Report formats: `Html` (default), `Json`, or both. |
| `-PassThru` | Return the `S2DWhatIfResult` object to the pipeline. |

---

## Output object — `S2DWhatIfResult`

```
S2DWhatIfResult
├── ScenarioLabel          string          Human-readable description of applied changes
├── BaselineNodeCount      int             Node count before the scenario
├── ProjectedNodeCount     int             Node count after the scenario
├── DeltaUsableTiB         double          Net change in usable capacity (TiB)
├── DeltaUsableTB          double          Net change in usable capacity (TB)
├── GeneratedAt            string          ISO 8601 timestamp
├── BaselineWaterfall      S2DCapacityWaterfall
├── ProjectedWaterfall     S2DCapacityWaterfall
└── DeltaStages[]
    ├── Stage              int             Stage number (1–8)
    ├── Name               string          Stage name
    ├── BaselineTiB        double          Baseline size at this stage
    ├── ProjectedTiB       double          Projected size at this stage
    ├── DeltaTiB           double          Difference (positive = gain)
    ├── BaselineTB         double
    ├── ProjectedTB        double
    └── DeltaTB            double
```

---

## Examples

### Add 2 nodes

Model scaling out from 4 to 6 nodes on a cluster with 4 × 3.84 TB drives per node:

```powershell
Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snapshots\clus01-20260101.json -AddNodes 2
```

The projected waterfall recomputes all 7 stages with 6 nodes × 4 disks. Reserve deduction increases (min(6,4) × largest drive remains capped at 4), but raw capacity grows proportionally.

---

### Add 4 disks per node (same disk size)

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -AddDisksPerNode 4
```

Disk count per node grows from 4 to 8. The new disks are assumed to be the same size as the existing largest disk. Raw bytes and all downstream stages increase proportionally.

---

### Add disks with a specific size

When adding drives of a different size (e.g., upgrading to 7.68 TB NVMe):

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -AddDisksPerNode 4 `
    -NewDiskSizeTB 7.68
```

The projected largest-disk size used for reserve calculation will be `max(existing, new)`.

---

### Replace all capacity disks

Model replacing 3.84 TB drives with 7.68 TB drives across all nodes (same node and disk count):

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -ReplaceDiskSizeTB 7.68
```

Total disk count is unchanged. All stages recompute using the new drive size as both the per-disk size and the largest-disk reserve multiplier.

---

### Change resiliency (3-way → 2-way mirror)

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -ChangeResiliency 2
```

Stage 7 (Usable Capacity) changes. All earlier stages are unchanged because resiliency does not affect pool or reserve math. Blended efficiency changes from 33.3% to 50.0%.

> [!WARNING]
> **Resiliency change is a cluster-level operation**
> Changing resiliency on a live cluster requires draining, stopping, and reconfiguring volumes. This cmdlet models the capacity outcome only — it does not make any live changes.
>
---

### Composite: add 2 nodes + more disks + new resiliency

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -AddNodes 2 `
    -AddDisksPerNode 4 `
    -NewDiskSizeTB 7.68 `
    -ChangeResiliency 2
```

All four modifications are applied together. The `ScenarioLabel` property lists each change: `+2 nodes, +4 disks/node, Resiliency → 2-way mirror`.

---

### Pipeline from live run

Run the full audit on a cluster and immediately feed the result into what-if modeling:

```powershell
$data = Invoke-S2DCartographer -ClusterName clus01 -PassThru
$whatif = $data | Invoke-S2DCapacityWhatIf -AddNodes 2 -PassThru
$whatif.DeltaUsableTiB
```

---

### Generate HTML and JSON reports

```powershell
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260101.json `
    -AddNodes 2 `
    -AddDisksPerNode 4 `
    -OutputDirectory C:\Reports\WhatIf `
    -Format Html, Json
```

Writes two files to `C:\Reports\WhatIf\`:
- `whatif-20260101-1430.html` — interactive before/after waterfall chart with KPI summary and delta table
- `whatif-20260101-1430.json` — structured JSON with full baseline and projected waterfall data

---

## How the model works

### Baseline extraction

When loading from a JSON snapshot, the cmdlet extracts:

- **Node count** — from `NodeCount` field, or counted from unique node names on capacity disks
- **Disks per node** — `total capacity disks ÷ node count` (averaged, rounded)
- **Largest disk size** — maximum `SizeBytes` across pool-member capacity-tier disks
- **Pool total / free bytes** — from `StoragePool.TotalSize` and `RemainingSize`
- **Infrastructure volume bytes** — from `FootprintOnPool` (or `Size`) of volumes where `IsInfrastructureVolume = true`
- **Resiliency factor** — from `StoragePool.ResiliencySettings` Mirror entry `NumberOfDataCopies`; defaults to 3.0

### Projection calculation

Scenario parameters modify the extracted baseline inputs:

1. **`-ReplaceDiskSizeTB`** — overrides the per-disk size used for raw byte calculation
2. **`-NewDiskSizeTB`** — sets the size for newly added disks; projected largest-disk = `max(existing, new)`
3. **`-AddDisksPerNode`** — increments disks-per-node count
4. **`-AddNodes`** — increments node count
5. **`-ChangeResiliency`** — overrides the resiliency factor

Projected raw bytes = `projected node count × projected disks per node × projected disk size`

Projected pool = estimated as `projected raw × 99%` (standard pool overhead).

Infrastructure volume bytes are unchanged — the model assumes existing infra volumes are unchanged regardless of hardware changes.

The same `Invoke-S2DWaterfallCalculation` pure function computes both the baseline and projected waterfall from these inputs.

### Limitations

- New nodes are assumed to be **symmetric** — same disk count and size as the model inputs. If your real nodes will have a different configuration, chain `-AddNodes` and `-ReplaceDiskSizeTB` together.
- The model does not account for cluster rebuild time, performance impact, or rolling upgrade constraints.
- Thin-provisioned volume growth risk is modeled by `Get-S2DHealthStatus` (checks 6 and 11) — not by this cmdlet.

---

## Related

- [Capacity waterfall](collectors/capacity-waterfall.md) — how the 7 stages are computed
- [Capacity math](capacity-math.md) — reserve calculation, TiB vs TB, efficiency
- [Health checks](collectors/health-checks.md) — thin provisioning risk (checks 6 and 11)
- [JSON snapshot schema](schema/cluster-snapshot.md) — baseline snapshot format
