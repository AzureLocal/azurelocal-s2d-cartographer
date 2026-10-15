# Getting Started

## Prerequisites

| Requirement | Details |
| ------------- | -------- |
| **PowerShell 7.2+** | Required. [Download here](https://github.com/PowerShell/PowerShell) |
| **Storage / FailoverClusters RSAT** | Required on management machine, or run directly on a cluster node |
| **WinRM / CIM access** | Required for remote connections. Ports 5985/5986 open to cluster nodes |
| **ImportExcel** | Installed automatically as a module dependency via PSGallery |
| **Microsoft Edge or Chrome** | Required for PDF output (headless print). Pre-installed on most Windows machines |
| **Az.KeyVault** | Optional — only needed for Key Vault credential retrieval |

## Installation

### From PowerShell Gallery

```powershell
Install-Module S2DCartographer -Scope CurrentUser
```

### From source

```powershell
git clone https://github.com/AzureLocal/azurelocal-s2d-cartographer.git
Set-Location .\azurelocal-s2d-cartographer
Import-Module .\S2DCartographer.psd1 -Force
```

---

## Quick Start

The fastest path — one command that connects, collects, analyzes, and generates all reports:

```powershell
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential (Get-Credential)
```

Output files are written to a per-run folder under `C:\S2DCartographer\` by default:

```text
C:\S2DCartographer\
  c01-prd-bal\
    20260413-1430\
      S2DCartographer_c01-prd-bal_20260413-1430.html
      S2DCartographer_c01-prd-bal_20260413-1430.docx
      S2DCartographer_c01-prd-bal_20260413-1430.xlsx
      S2DCartographer_c01-prd-bal_20260413-1430.pdf
      S2DCartographer_c01-prd-bal_20260413-1430.json
      S2DCartographer_c01-prd-bal_20260413-1430.log
      diagrams\        ← when -IncludeDiagrams is used
```

Each run creates its own timestamped subfolder so multiple clusters and repeated runs never overwrite each other. The `.log` file captures every collection step, duration, warnings, and output paths. The `.json` file is a structured snapshot of all collected data — see [Cluster Snapshot Schema](schema/cluster-snapshot.md) for consumption details.

---

## Step-by-Step Workflow

For more control, run the pipeline manually.

### 1 — Connect to the cluster

```powershell
# Remote — most common for management machines
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)

# Remote with a pre-existing CimSession
$cim = New-CimSession -ComputerName "node01.contoso.com" -Credential $cred
Connect-S2DCluster -CimSession $cim

# Local — run directly on a cluster node (no credentials needed)
Connect-S2DCluster -Local
```

### 2 — Collect data

Run each collector individually, or let `Invoke-S2DCartographer` call them in the right order.

```powershell
# Physical disks — role, health, wear, latency
$disks = Get-S2DPhysicalDiskInventory
$disks | Format-Table NodeName, FriendlyName, Role, Size, HealthStatus, WearPercentage

# Storage pool — capacity, overcommit ratio, resiliency settings
$pool = Get-S2DStoragePoolInfo
$pool | Select-Object FriendlyName, TotalSize, RemainingSize, OvercommitRatio

# Volumes — resiliency type, footprint, infra detection
$volumes = Get-S2DVolumeMap
$volumes | Format-Table FriendlyName, ResiliencySettingName, Size, FootprintOnPool, IsInfrastructureVolume

# Cache tier — mode, disk count, all-flash detection
$cache = Get-S2DCacheTierInfo

# 7-stage capacity waterfall
$waterfall = Get-S2DCapacityWaterfall
$waterfall.Stages | Format-Table Stage, Name, Size, Delta, Status

# 11 health checks (includes thin provisioning risk checks 6 and 11)
$health = Get-S2DHealthStatus
$health | Format-Table CheckName, Severity, Status, Details
```

### 3 — Generate reports

```powershell
# All formats — HTML, Word, PDF, Excel (default)
$data = Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred -PassThru
New-S2DReport -InputObject $data -Format All -Author "Your Name" -Company "Your Company" `
    -OutputDirectory "C:\Reports\"

# Single format only
New-S2DReport -InputObject $data -Format Html -OutputDirectory "C:\Reports\"
```

### 3a — What-if capacity modeling (optional)

Use the JSON snapshot written in step 3 to model hardware changes without hitting the cluster again:

```powershell
# Model adding 2 nodes — no live cluster required
Invoke-S2DCapacityWhatIf `
    -BaselineSnapshot "C:\Reports\c01-prd-bal\20260413-1430\S2DCartographer_c01-prd-bal_20260413-1430.json" `
    -AddNodes 2 `
    -OutputDirectory "C:\Reports\WhatIf" `
    -Format Html, Json

# Or pipe directly from a live run
$data | Invoke-S2DCapacityWhatIf -AddNodes 2 -AddDisksPerNode 4 -OutputDirectory "C:\Reports\WhatIf"
```

See [What-If Modeling](what-if.md) for all scenario types and worked examples.

### 4 — Generate diagrams

```powershell
# All 6 diagram types as SVG files
New-S2DDiagram -InputObject $data -DiagramType All -OutputDirectory "C:\Reports\"

# Waterfall only
New-S2DDiagram -InputObject $data -DiagramType Waterfall -OutputDirectory "C:\Reports\"
```

### 5 — Disconnect

```powershell
Disconnect-S2DCluster
```

---

## One-Shot Mode

`Invoke-S2DCartographer` runs the entire pipeline automatically:

```powershell
# All formats — HTML, Word, PDF, Excel (default — no -Format needed)
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential (Get-Credential)

# All formats + all diagrams
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred `
    -IncludeDiagrams `
    -Author "Alex Admin" -Company "Contoso" `
    -OutputDirectory "C:\Deliverables\"

# Return the data object for further processing
$data = Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred -PassThru
$data.CapacityWaterfall.Stages | Where-Object Status -ne 'OK'

# Skip health checks for faster runs (capacity data only)
Invoke-S2DCartographer -ClusterName "c01-prd-bal" -Credential $cred -SkipHealthChecks
```

---

## Key Vault Integration

For unattended runs and automation pipelines, retrieve cluster credentials from Azure Key Vault instead of prompting:

```powershell
# Key Vault stores the cluster admin password as a secret
Invoke-S2DCartographer -ClusterName "c01-prd-bal" `
    -KeyVaultName "kv-platform-prod" `
    -SecretName "cluster-admin-password"
```

The Key Vault secret should contain the password as a plain string. The username defaults to the cluster name's domain admin. Use `Az.KeyVault` module and an authenticated Az session.

---

## Capacity Unit Preference

S2DCartographer always shows both **TiB** (binary/Windows) and **TB** (decimal/drive label) in every output. This cannot be disabled — it is a core design principle.

```text
Raw Capacity:  55.88 TiB  (61.44 TB)
Usable Space:  13.97 TiB  (15.36 TB)
```

See [TiB vs TB](tib-vs-tb.md) for why this matters and how the conversion works.
