# Reports

S2DCartographer generates publication-quality reports and structured data exports from collected cluster data. All human-readable formats show TiB and TB side-by-side throughout. Structured formats (JSON, CSV) carry both unit representations on every size field so downstream tools never need to convert.

## Formats

| Format | Extension | Use case |
| --- | --- | --- |
| **HTML** | `.html` | Interactive browser dashboard; self-contained, no dependencies |
| **Word** | `.docx` | Customer deliverables, architecture review documents |
| **PDF** | `.pdf` | Archivable, printable, universally readable |
| **Excel** | `.xlsx` | Data analysis, capacity tracking over time |
| **JSON** | `.json` | Structured snapshot of the full S2DClusterData object for downstream tools, diffs, external dashboards. Schema documented in [Cluster Snapshot Schema](schema/cluster-snapshot.md) |
| **CSV** | `.csv` (4 files) | Flat per-collector tables: physical disks, volumes, health checks, waterfall. For spreadsheet / Power BI consumers |
| **All** | — | Generates HTML + Word + PDF + Excel + JSON in one call (CSV is opt-in and must be requested explicitly) |

---

## HTML Dashboard

Self-contained single-file HTML with embedded CSS and Chart.js 4.4.0. No internet connection required — all assets are inlined.

**Sections:**

- **Executive Summary** — cluster name, node count, overall health badge (green/yellow/red), collection timestamp
- **Capacity Waterfall** — interactive horizontal bar chart (Chart.js) showing all 7 stages with values
- **TiB/TB Toggle** — switch in the toolbar flips all capacity values between TiB and TB simultaneously
- **Physical Disk Inventory** — table with node, model, media type, role, capacity, wear %, health
- **Storage Pool** — total/allocated/remaining capacity, overcommit ratio
- **Volume Map** — per-volume resiliency, footprint, efficiency %, infra flag
- **Health Checks** — traffic-light cards per check with Details and Remediation text
- **TiB/TB Reference** — conversion table for common NVMe/SSD drive sizes

**Generate:**

```powershell
$data = Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred -PassThru
New-S2DReport -InputObject $data -Format Html -OutputDirectory "C:\Reports\"
```

---

## Word Document

Pure PowerShell `.docx` — no Microsoft Office or COM automation required. Uses `System.IO.Compression.ZipArchive` to generate Open XML directly.

**Sections:**

- Title page with cluster name, author, company, and collection date
- Executive Summary — health status, key capacity metrics
- Capacity Waterfall — 7-stage table
- Physical Disk Inventory — full table with all disk fields
- Volume Map — per-volume resiliency and capacity
- Health Assessment — all 11 checks with severity-coded status and remediation guidance
- Appendix A: TiB vs TB Explanation
- Appendix B: S2D Reserve Space Best Practices

**Generate:**

```powershell
New-S2DReport -InputObject $data -Format Word `
    -Author "Kristopher Turner" -Company "TierPoint" `
    -OutputDirectory "C:\Deliverables\"
```

> [!NOTE]
> **No Office required**
> The Word document is built from scratch using Open XML — compatible with Word 2016+, LibreOffice, and Google Docs. Microsoft Office does not need to be installed on the machine running S2DCartographer.
>
!!! warning "Garbled XML on open"
    If the generated `.docx` opens with a repair prompt or shows garbled XML, this is usually caused by special characters (em-dashes, Unicode symbols) in cluster or volume names. Please [open an issue](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/new?template=bug_report.yml) with the cluster name and affected volume names.

---

## PDF

Generates HTML first, then uses headless Edge or Chrome to print it to PDF.

**Browser search order:**

1. `msedge.exe` in standard Edge install paths
2. `chrome.exe` in standard Chrome install paths
3. `msedge` / `chrome` / `chromium-browser` on `$env:PATH`

**Generate:**

```powershell
New-S2DReport -InputObject $data -Format Pdf -OutputDirectory "C:\Reports\"
```

> [!NOTE]
> **Browser requirement**
> PDF generation requires Microsoft Edge or Google Chrome. Edge ships pre-installed on Windows 11, Windows Server 2022+, and Azure Local nodes. If no browser is found, the command warns and returns `$null`.
>
!!! tip "Manual PDF from HTML"
    If no browser is available, generate the HTML report first, then open it in a browser to print manually (Edge/Chrome → Print → Save as PDF).

```powershell
New-S2DReport -InputObject $data -Format Html -OutputDirectory "C:\Reports\"
# Open the .html file in Edge/Chrome → Print → Save as PDF
```

---

## Excel Workbook

Multi-tab `.xlsx` using the [ImportExcel](https://github.com/dfinke/ImportExcel) module.

**Tabs:**

| Tab | Content |
| --- | --- |
| **Summary** | Cluster name, node count, health status, collection date, key capacity metrics |
| **Capacity Waterfall** | All 7 stages with TiB and TB columns |
| **Physical Disks** | Full disk inventory — node, model, media type, role, capacity, wear %, firmware |
| **Storage Pool** | Pool name, health, total/allocated/remaining, overcommit ratio, resiliency settings |
| **Volumes** | All volumes — resiliency, copies, provisioning type, size, footprint, efficiency |
| **Health Checks** | All 11 checks — name, severity, status, details, remediation |
| **Metadata** | Module version, collection timestamp, cluster FQDN, node list |

**Generate:**

```powershell
New-S2DReport -InputObject $data -Format Excel -OutputDirectory "C:\Reports\"
```

> [!NOTE]
> **ImportExcel installed automatically**
> `ImportExcel` is declared as a required module in the S2DCartographer manifest. When you install S2DCartographer from PSGallery, `ImportExcel` is installed automatically — no manual step required.
>
---

## JSON Snapshot

Structured data export of the full `S2DClusterData` object. Intended for downstream tools (historical diff, what-if scenarios, external dashboards, custom scripts). Included by default when `-Format All` is used.

**File name:** `S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.json`

**Shape:**

```json
{
  "SchemaVersion": "1.0",
  "Generated":     { "Timestamp": "...", "ModuleVersion": "...", ... },
  "Cluster":       { "Name": "...", "Fqdn": "...", "NodeCount": 4, "Nodes": [...], ... },
  "OverallHealth": "Warning",
  "PhysicalDisks": [ { ... } ],
  "StoragePool":   { ... },
  "Volumes":       [ { ... } ],
  "CacheTier":     { ... },
  "CapacityWaterfall": { ... },
  "HealthChecks":  [ { ... } ]
}
```

**Full schema:** [Cluster Snapshot Schema](schema/cluster-snapshot.md).

**Canonical sample:** [`samples/cluster-snapshot.json`](https://github.com/AzureLocal/azurelocal-s2d-cartographer/blob/main/samples/cluster-snapshot.json).

**Consuming from PowerShell:**

```powershell
$snap = Get-Content .\S2DCartographer_*.json -Raw | ConvertFrom-Json
$snap.PhysicalDisks | Where-Object IsPoolMember | Measure-Object -Property SizeBytes -Sum
$snap.HealthChecks  | Where-Object Status -ne 'Pass'
```

**Consuming from jq:**

```bash
jq '.CapacityWaterfall.UsableCapacity.TiB' snapshot.json
jq '.HealthChecks[] | select(.Status != "Pass")' snapshot.json
```

> [!NOTE]
> **JSON always contains every disk**
> The JSON export includes every disk visible to every node — boot drives and SAN-presented LUNs too — each tagged with an `IsPoolMember` boolean. This is by design: downstream tools get full fidelity. The Physical Disk Inventory in HTML / Word / PDF / Excel reports filters to pool members only by default.
>
---

## CSV Tables

Flat per-collector tables for spreadsheet / Power BI consumers. Opt-in via `-Format Csv` (not included in `-Format All`).

**Files produced:**

| File suffix | Content |
| --- | --- |
| `-physical-disks.csv` | One row per disk including `IsPoolMember` column |
| `-volumes.csv` | One row per volume |
| `-health-checks.csv` | One row per health check |
| `-waterfall.csv` | One row per waterfall stage |

**Generate:**

```powershell
New-S2DReport -InputObject $data -Format Csv -OutputDirectory "C:\Reports\"

# Or combine with All
New-S2DReport -InputObject $data -Format All, Csv -OutputDirectory "C:\Reports\"
```

---

## What-If Modeling Reports

`Invoke-S2DCapacityWhatIf` generates standalone what-if reports that are independent of the cluster audit reports above. They model capacity changes without a live cluster.

**Formats:**

| Format | Content |
| --- | --- |
| **HTML** | Side-by-side Chart.js waterfall charts (baseline left, projected right), KPI summary row (usable capacity, delta, reserve status, efficiency), scenario badge, stage-by-stage delta table with color-coded delta column |
| **JSON** | Structured output (SchemaVersion 1.0, Type S2DWhatIfResult) with both waterfalls flattened to stage arrays and all TiB/TB delta values |

**Generate:**

```powershell
# From a JSON snapshot — no live cluster required
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot C:\snapshots\clus01-20260413.json `
    -AddNodes 2 `
    -OutputDirectory C:\Reports\WhatIf `
    -Format Html, Json

# From a live run, piped directly
Invoke-S2DCartographer -ClusterName clus01 -Credential $cred -PassThru |
    Invoke-S2DCapacityWhatIf -ChangeResiliency 2 -OutputDirectory C:\Reports\WhatIf
```

See [What-If Modeling](what-if.md) for all scenario parameters and worked examples.

---

## Using `New-S2DReport` directly

`New-S2DReport` requires an `S2DClusterData` object. Obtain one with `-PassThru` on `Invoke-S2DCartographer`, or by building the pipeline manually.

**Parameters:**

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `-InputObject` | `S2DClusterData` | Yes | Cluster data object (also accepts pipeline) |
| `-Format` | `string[]` | Yes | `Html`, `Word`, `Pdf`, `Excel`, `Json`, `Csv`, or `All` |
| `-OutputDirectory` | `string` | No | Destination folder (default: `C:\S2DCartographer`) |
| `-Author` | `string` | No | Author name embedded in report headers |
| `-Company` | `string` | No | Company/org name embedded in report headers |
| `-IncludeNonPoolDisks` | `switch` | No | Include boot drives and SAN-presented LUNs in the Physical Disk Inventory table. Default is to show pool members only. Does not affect JSON or CSV outputs, which always include every disk |

**Output folder structure:** Each `Invoke-S2DCartographer` run creates a per-run subfolder:

```text
<OutputDirectory>\<ClusterName>\<yyyyMMdd-HHmm>\
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.html
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.docx
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.xlsx
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.pdf
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.json
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.log
  S2DCartographer_<ClusterName>_<yyyyMMdd-HHmm>.log
  diagrams\
```

Multiple clusters and repeated runs never overwrite each other.

---

## Via `Invoke-S2DCartographer`

The orchestrator handles connect → collect → report → disconnect in one call:

```powershell
# All formats — HTML, Word, PDF, Excel (default — no -Format needed)
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential (Get-Credential)

# All formats + all diagrams
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred `
    -IncludeDiagrams `
    -Author "Your Name" -Company "Your Company" `
    -OutputDirectory "C:\Reports\"

# Word + PDF only — customer deliverable
Invoke-S2DCartographer -ClusterName "customer-cluster-01" -Credential $cred `
    -Format Word, Pdf `
    -Author "Kristopher Turner" -Company "Hybrid Cloud Solutions" `
    -OutputDirectory "C:\Deliverables\"

# Key Vault credentials (unattended) — all formats
Invoke-S2DCartographer -ClusterName "c01-prd-bal" `
    -KeyVaultName "kv-platform-prod" -SecretName "cluster-admin-password" `
    -OutputDirectory "C:\AutoReports\"
```
