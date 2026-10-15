# New-S2DReport

Generates HTML, Word, PDF, Excel, JSON, or CSV reports from S2D cluster data.

---

## Synopsis

Accepts an `S2DClusterData` object (from `Invoke-S2DCartographer -PassThru` or pipeline) and renders publication-quality reports. Supports single or multiple formats in one call.

- **HTML** — interactive dashboard with KPI cards, waterfall chart, health scorecard, disk inventory, volume map, and pool allocation breakdown
- **Word** — customer-deliverable `.docx` with all tables and waterfall model
- **PDF** — rendered from the Word document
- **Excel** — per-sheet workbook with disk inventory, volumes, health checks, and waterfall
- **JSON** — structured snapshot of the full `S2DClusterData` object (see [Cluster Snapshot Schema](../schema/cluster-snapshot.md))
- **CSV** — one flat table per collector (physical disks, volumes, health checks, waterfall stages)

---

## Syntax

```powershell
<S2DClusterData> | New-S2DReport
    -Format <string[]>
    [-OutputDirectory <string>]
    [-Author <string>]
    [-Company <string>]
    [-IncludeNonPoolDisks]
```

```powershell
New-S2DReport
    -InputObject <S2DClusterData>
    -Format <string[]>
    [-OutputDirectory <string>]
    [-Author <string>]
    [-Company <string>]
    [-IncludeNonPoolDisks]
```

---

## Parameters

### `-InputObject`

| | |
|---|---|
| Type | `object` (S2DClusterData) |
| Required | Yes |
| Pipeline | Yes |
| Default | — |

S2DClusterData object from `Invoke-S2DCartographer -PassThru`. Accepts pipeline input.

---

### `-Format`

| | |
|---|---|
| Type | `string[]` |
| Required | Yes |
| Valid values | `Html`, `Word`, `Pdf`, `Excel`, `Json`, `Csv`, `All` |

One or more output formats. `All` = Html + Word + Pdf + Excel + Json. `Csv` is always opt-in because it writes multiple files per run.

---

### `-OutputDirectory`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `C:\S2DCartographer` |

Destination folder for report files. Created if it does not exist.

---

### `-Author`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | empty |

Author name embedded in the report header (HTML, Word, PDF).

---

### `-Company`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | empty |

Company or organization name embedded in the report header.

---

### `-IncludeNonPoolDisks`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Include non-pool disks (boot drives, SAN LUNs, OS drives) in the Physical Disk Inventory tables. Default is pool-members only. Does **not** affect JSON or CSV outputs — those always include every disk with an `IsPoolMember` flag.

---

## Outputs

`string[]` — paths to all generated report files.

---

## Examples

**HTML report from a live run:**

```powershell
Invoke-S2DCartographer -ClusterName clus01 -PassThru |
    New-S2DReport -Format Html
```

**All formats with author details:**

```powershell
$data = Invoke-S2DCartographer -ClusterName clus01 -PassThru
New-S2DReport -InputObject $data -Format All -Author "Alex Admin" -Company "Contoso"
```

**JSON snapshot only:**

```powershell
$data | New-S2DReport -Format Json -OutputDirectory C:\Snapshots
```

**HTML + Word, custom output folder:**

```powershell
$data | New-S2DReport -Format Html, Word -OutputDirectory D:\CustomerReports
```

**Include all disks (not just pool members):**

```powershell
$data | New-S2DReport -Format Html -IncludeNonPoolDisks
```
