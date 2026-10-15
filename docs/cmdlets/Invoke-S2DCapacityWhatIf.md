# Invoke-S2DCapacityWhatIf

Models the capacity impact of adding nodes, adding disks, replacing disks, or changing resiliency — without touching the live cluster.

---

## Synopsis

Takes a baseline cluster snapshot (JSON file, `S2DClusterData` object, or live cluster) and applies one or more scenario modifications, then recomputes the 7-stage capacity waterfall. Returns a what-if result object containing both the baseline and projected waterfalls plus per-stage deltas.

Scenarios can be combined in a single invocation (composite what-if).

---

## Syntax

**From a JSON snapshot file:**

```powershell
Invoke-S2DCapacityWhatIf
    [-BaselineSnapshot] <string>
    [-AddNodes <int>]
    [-AddDisksPerNode <int>]
    [-NewDiskSizeTB <double>]
    [-ReplaceDiskSizeTB <double>]
    [-ChangeResiliency <int>]
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-PassThru]
```

**From a pipeline S2DClusterData object:**

```powershell
<S2DClusterData> | Invoke-S2DCapacityWhatIf
    [-AddNodes <int>]
    [-AddDisksPerNode <int>]
    [-NewDiskSizeTB <double>]
    [-ReplaceDiskSizeTB <double>]
    [-ChangeResiliency <int>]
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-PassThru]
```

**From a live cluster (connects, collects, then models):**

```powershell
Invoke-S2DCapacityWhatIf
    -ClusterName <string>
    [-AddNodes <int>]
    [-AddDisksPerNode <int>]
    [-NewDiskSizeTB <double>]
    [-ReplaceDiskSizeTB <double>]
    [-ChangeResiliency <int>]
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-PassThru]
```

---

## Parameters

### `-BaselineSnapshot`

| | |
|---|---|
| Type | `string` |
| Required | Yes (Snapshot parameter set) |
| Position | 0 |
| Default | — |

Path to a JSON snapshot file produced by S2DCartographer (`SchemaVersion 1.0`). Typically the `.json` file written to the run output folder.

---

### `-InputObject`

| | |
|---|---|
| Type | `object` |
| Required | Yes (Object parameter set) |
| Pipeline | Yes |
| Default | — |

An `S2DClusterData` object piped from `Invoke-S2DCartographer -PassThru`.

---

### `-ClusterName`

| | |
|---|---|
| Type | `string` |
| Required | Yes (Live parameter set) |
| Default | — |

Cluster DNS name or FQDN. Connects to the cluster, collects data, then immediately runs the what-if model. Uses the active module session if already connected.

---

### `-AddNodes`

| | |
|---|---|
| Type | `int` |
| Required | No |
| Default | `0` |

Number of nodes to add to the cluster. New nodes are assumed to have the same disk configuration as the average existing node (disk count × disk size). Combine with `-NewDiskSizeTB` to specify a different disk size for the new nodes.

---

### `-AddDisksPerNode`

| | |
|---|---|
| Type | `int` |
| Required | No |
| Default | `0` |

Number of additional capacity disks to add to each existing node. Enforces symmetric expansion — all nodes get the same number of new disks. Use `-NewDiskSizeTB` to specify the size of new disks; defaults to the largest existing disk size.

---

### `-NewDiskSizeTB`

| | |
|---|---|
| Type | `double` |
| Required | No |
| Default | `0` (uses existing largest disk size) |

Size in decimal TB of new disks added via `-AddNodes` or `-AddDisksPerNode`. For example, `3.84` for a 3.84 TB NVMe drive.

---

### `-ReplaceDiskSizeTB`

| | |
|---|---|
| Type | `double` |
| Required | No |
| Default | `0` |

Model replacing all capacity disks with disks of this size in decimal TB. Node count and disk count remain the same — only the per-disk size changes. Example: model the impact of upgrading from 1.92 TB to 3.84 TB disks.

---

### `-ChangeResiliency`

| | |
|---|---|
| Type | `int` |
| Required | No |
| Default | `0` (no change) |

Override the resiliency factor (`NumberOfDataCopies`). `2` = 2-way mirror, `3` = 3-way mirror. Use this to model switching resiliency type without changing hardware.

---

### `-OutputDirectory`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | empty (no files written) |

Directory to write output reports. If omitted, no files are written — use `-PassThru` to receive the result object instead.

---

### `-Format`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | `Html` |
| Valid values | `Html`, `Json` |

Report formats to write when `-OutputDirectory` is specified.

---

### `-PassThru`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Return the `S2DWhatIfResult` object to the pipeline.

---

## Outputs

`PSCustomObject` (`S2DWhatIfResult`) when `-PassThru` is set.

The result contains:

| Property | Description |
|---|---|
| `Baseline` | The original capacity waterfall |
| `Projected` | The modelled capacity waterfall after changes |
| `Stages` | Per-stage delta table (Bytes, TiB, TB for each stage) |
| `Summary` | High-level before/after usable capacity comparison |

---

## Examples

**Add 2 nodes with 4 × 3.84 TB disks each:**

```powershell
Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snapshots\snap.json `
    -AddNodes 2 -AddDisksPerNode 4 -NewDiskSizeTB 3.84
```

**Model changing resiliency from 3-way to 2-way mirror:**

```powershell
Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snapshots\snap.json -ChangeResiliency 2
```

**Pipe from a live run:**

```powershell
Invoke-S2DCartographer -ClusterName clus01 -PassThru |
    Invoke-S2DCapacityWhatIf -AddNodes 2 -AddDisksPerNode 4 -NewDiskSizeTB 3.84
```

**Composite scenario — add nodes AND replace disks AND change resiliency:**

```powershell
Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snap.json `
    -AddNodes 2 `
    -ReplaceDiskSizeTB 7.68 `
    -ChangeResiliency 2 `
    -OutputDirectory C:\Reports `
    -Format Html, Json `
    -PassThru
```

**Model in memory and inspect result:**

```powershell
$result = Invoke-S2DCapacityWhatIf -BaselineSnapshot C:\snap.json `
    -AddDisksPerNode 4 -NewDiskSizeTB 3.84 -PassThru

$result.Summary | Format-List
$result.Stages  | Format-Table
```
