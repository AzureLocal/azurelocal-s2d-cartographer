# S2DCartographer — Project Plan

## Azure Local Storage Spaces Direct Analysis, Visualization & Reporting Module

**Author:** Kristopher Turner (Country Cloud Boy)
**Organization:** AzureLocal (github.com/AzureLocal)
**Repo:** `AzureLocal/azurelocal-s2dcartographer`
**Module Name:** `S2DCartographer`
**License:** MIT
**Date:** April 2026

---

## 1. Project Naming

### Primary Recommendation: **S2DCartographer**

A cartographer creates detailed maps, charts, and diagrams of terrain — exactly what this tool does for Storage Spaces Direct. It maps raw physical disks through the storage pool, across resiliency layers, down to usable volume capacity, producing visual artifacts that make S2D understandable. Fits the Scout/Ranger explorer naming theme perfectly.

**PowerShell Gallery:** Name `S2DCartographer` does not exist on PSGallery as of April 2026.

### Alternate Names (if preferred)

| Name | Rationale | Vibe |
|------|-----------|------|
| **S2DSherpa** | A sherpa guides people through mountain complexity — fits your Appalachian location and the goal of guiding people through S2D confusion | Mountain guide |
| **S2DCompass** | Points people in the right direction for storage planning; short and memorable | Navigation |
| **S2DScope** | Scope out the storage landscape; clean, two-syllable punch | Reconnaissance |

### Naming Convention Alignment

| Project | Theme | Role |
|---------|-------|------|
| Azure Scout | Broad Azure inventory explorer | Wide reconnaissance |
| Azure Local Ranger | Deep Azure Local cluster auditor | Focused patrol |
| **S2DCartographer** | S2D storage mapping & visualization | Detailed mapmaking |

---

## 2. Project Purpose & Problem Statement

### The Problem

Storage Spaces Direct is one of the most misunderstood technologies in the Azure Local / Windows Server ecosystem. Common pain points include:

1. **TiB vs TB confusion** — Drive manufacturers label disks in TB (decimal, 1 TB = 1,000,000,000,000 bytes) while Windows reports in TiB (binary, 1 TiB = 1,099,511,627,776 bytes). A "1.92 TB" NVMe drive shows as ~1.75 TiB in Windows. Customers buy capacity expecting TB and get confused when the numbers don't match.

2. **Reserve space misunderstanding** — Microsoft recommends reserving the equivalent of one capacity drive per server (up to 4 drives). Many deployments ignore this entirely or get the math wrong, leaving clusters unable to self-heal after a drive failure.

3. **Resiliency overhead surprise** — Three-way mirror uses only 33.3% of raw capacity. Two-way mirror uses 50%. Customers provision expecting near-raw capacity and are shocked when volumes are smaller than expected.

4. **Infrastructure volume blindspot** — Azure Local automatically creates an infrastructure volume for cluster metadata and logs. This consumes pool capacity that customers didn't plan for.

5. **Mixed resiliency math** — Clusters with volumes using different mirror types (two-way, three-way, mirror-accelerated parity) have complex capacity math that existing calculators handle poorly.

6. **Thin vs fixed provisioning confusion** — Thin-provisioned volumes can be overcommitted, leading to dangerous out-of-space conditions that customers don't detect until it's too late.

7. **No "expected vs actual" comparison** — Existing calculators are planning tools. Nothing connects to a live cluster to compare what the storage *should* look like versus what it *actually* looks like.

### The Solution

**S2DCartographer** connects to a live Azure Local cluster, inventories every layer of the storage stack (physical disks → cache tier → capacity tier → storage pool → virtual disks → volumes), and produces:

- **Capacity waterfall diagrams** showing raw → after cache → after reserve → after resiliency → after infrastructure volume → usable capacity
- **Health assessments** with clear pass/fail indicators for reserve adequacy, resiliency coverage, and thin-provisioning risk
- **Publication-quality reports** in HTML, Word, PDF, and Excel formats suitable for customer deliverables, architecture reviews, and operational documentation
- **TiB/TB dual-display** throughout all outputs, eliminating unit confusion permanently

---

## 3. TiB vs TB Strategy

This is a first-class concern, not an afterthought. S2DCartographer handles it as follows:

### Display Philosophy: Always Show Both

Every capacity value in every output (console, report, diagram) is displayed in **dual format**:

```
Raw Capacity:  13.97 TiB  (15.36 TB)
Usable Space:   4.66 TiB  ( 5.12 TB)
```

### Implementation

```powershell
# Core conversion class used throughout the module
class S2DCapacity {
    [int64]$Bytes
    [double]$TiB        # Binary: bytes / 1099511627776
    [double]$TB         # Decimal: bytes / 1000000000000
    [double]$GiB        # Binary: bytes / 1073741824
    [double]$GB         # Decimal: bytes / 1000000000
    [string]$Display    # "13.97 TiB (15.36 TB)"
}
```

### User-Configurable Default

```powershell
# Module preference variable
$S2DCartographerPreference = @{
    PrimaryUnit = 'TiB'     # or 'TB' — controls which appears first
    ShowDual    = $true      # always show both; $false for single-unit mode
}
```

### Report Handling

- **Console output**: Dual format, TiB primary by default
- **HTML reports**: Dual format with tooltip showing bytes
- **Excel reports**: Separate TiB and TB columns with raw bytes in a hidden column
- **Word/PDF reports**: Dual format inline, with a terminology appendix explaining the difference
- **Diagrams**: Primary unit with secondary in parentheses, to avoid visual clutter

### Educational Component

Every report includes a brief "Understanding Storage Units" section explaining that a "1.92 TB" drive label means the drive holds 1,920,000,000,000 bytes, which Windows displays as approximately 1.75 TiB. This section demystifies the discrepancy once and for all.

---

## 4. Module Architecture

### PowerShell Module Structure

```
S2DCartographer/
├── S2DCartographer.psd1                    # Module manifest
├── S2DCartographer.psm1                    # Root module loader
├── Public/                                 # Exported cmdlets
│   ├── Invoke-S2DCartographer.ps1          # Main orchestrator
│   ├── Connect-S2DCluster.ps1             # Authentication & session management
│   ├── Disconnect-S2DCluster.ps1          # Cleanup
│   ├── Get-S2DPhysicalDiskInventory.ps1   # Physical disk collector
│   ├── Get-S2DStoragePoolInfo.ps1         # Storage pool collector
│   ├── Get-S2DVolumeMap.ps1               # Volume collector
│   ├── Get-S2DCacheTierInfo.ps1           # Cache tier collector
│   ├── Get-S2DHealthStatus.ps1            # Health & alerts collector
│   ├── Get-S2DCapacityWaterfall.ps1       # Capacity math engine
│   ├── New-S2DReport.ps1                  # Report generator (HTML/Word/PDF/Excel)
│   ├── New-S2DDiagram.ps1                 # Diagram generator
│   └── ConvertTo-S2DCapacity.ps1          # TiB/TB conversion utility
├── Private/                                # Internal helper functions
│   ├── Initialize-S2DSession.ps1
│   ├── Invoke-S2DRemoteCommand.ps1        # CIM/WinRM session wrapper
│   ├── Get-S2DReserveCalculation.ps1      # Reserve math
│   ├── Get-S2DResiliencyEfficiency.ps1    # Resiliency % calculator
│   ├── Get-S2DInfrastructureVolume.ps1    # Infra volume detection
│   ├── Format-S2DCapacity.ps1             # Formatting helpers
│   ├── Export-S2DHtmlReport.ps1           # HTML report engine
│   ├── Export-S2DWordReport.ps1           # Word (.docx) report engine
│   ├── Export-S2DPdfReport.ps1            # PDF report engine
│   ├── Export-S2DExcelReport.ps1          # Excel report engine
│   ├── New-S2DSvgDiagram.ps1             # SVG diagram renderer
│   └── Get-S2DOemInfo.ps1                 # OEM hardware detection (Dell, Lenovo, HPE, DataON)
├── Templates/                              # Report & diagram templates
│   ├── Html/
│   │   ├── report-template.html
│   │   ├── dashboard.css
│   │   └── charts.js                      # Chart.js-based visualizations
│   ├── Word/
│   │   └── report-template.json           # docx-js template config
│   └── Diagrams/
│       ├── waterfall-template.svg
│       ├── pool-layout-template.svg
│       └── disk-map-template.svg
├── Localization/                           # Future: multi-language support
│   └── en-US/
│       └── S2DCartographer.psd1
├── Tests/                                  # Pester tests
│   ├── Unit/
│   │   ├── ConvertTo-S2DCapacity.Tests.ps1
│   │   ├── Get-S2DReserveCalculation.Tests.ps1
│   │   └── Get-S2DResiliencyEfficiency.Tests.ps1
│   ├── Integration/
│   │   └── Invoke-S2DCartographer.Tests.ps1
│   └── Mocks/
│       ├── 2node-allnvme.json             # Simulated cluster data
│       ├── 3node-mixed-tier.json
│       ├── 4node-3way-mirror.json
│       └── 16node-mixed-resiliency.json
├── docs/                                   # MkDocs documentation
│   ├── mkdocs.yml
│   ├── index.md
│   ├── getting-started.md
│   ├── collectors.md
│   ├── reports.md
│   ├── diagrams.md
│   ├── tib-vs-tb.md
│   └── capacity-math.md
├── samples/                                # Example outputs
│   ├── sample-html-report.html
│   ├── sample-waterfall.svg
│   └── sample-excel-export.xlsx
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                         # Pester tests on PR
│   │   ├── publish.yml                    # PSGallery publish on release
│   │   └── docs.yml                       # MkDocs deploy
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── .gitignore
```

---

## 5. Authentication & Connectivity Model

Following the Azure Local Ranger and Azure Scout patterns:

### Connection Methods

```powershell
# Method 1: Direct WinRM/CIM to cluster node (domain-joined management machine)
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)

# Method 2: Pre-existing CIM session
$session = New-CimSession -ComputerName "node01" -Credential $cred
Connect-S2DCluster -CimSession $session

# Method 3: PowerShell remoting session
$psSession = New-PSSession -ComputerName "node01" -Credential $cred
Connect-S2DCluster -PSSession $psSession

# Method 4: Local execution (run directly on a cluster node)
Connect-S2DCluster -Local

# Method 5: Key Vault credential retrieval (Ranger pattern)
Connect-S2DCluster -ClusterName "c01-prd-bal" `
    -KeyVaultName "kv-hcs-vault-01" `
    -SecretName "cluster-admin-cred"
```

### Session Management

```powershell
# Module-scoped session state
$Script:S2DSession = @{
    ClusterName    = $null
    Nodes          = @()
    CimSession     = $null
    PSSession      = $null
    IsConnected    = $false
    CollectedData  = @{}    # Cache collected data for report generation
}
```

### Authentication Flow

1. Accept credential via parameter, existing session, or Key Vault
2. Validate connectivity to at least one cluster node
3. Discover all cluster nodes via `Get-ClusterNode`
4. Validate S2D is enabled via `Get-ClusterS2D`
5. Store session for subsequent collector cmdlets
6. All collectors use the established session — no re-authentication per cmdlet

---

## 6. Collector Domains

### 6.1 Physical Disk Inventory (`Get-S2DPhysicalDiskInventory`)

**PowerShell Data Sources:**
```powershell
Get-PhysicalDisk -CimSession $session
Get-PhysicalDisk -CimSession $session | Get-StorageReliabilityCounter
Get-Disk -CimSession $session
```

**Collected Properties:**
- **Per disk:** FriendlyName, SerialNumber, MediaType (SSD/NVMe/HDD), BusType, Size (bytes → TiB/TB), Model, FirmwareVersion, Manufacturer, Usage (Auto-Select, ManualSelect, Journal, Retired), HealthStatus, OperationalStatus, CanPool, PhysicalLocation, SlotNumber
- **Per node:** Which node owns which disks, disk count per node, symmetry check (all nodes should have identical disk configs)
- **Reliability counters:** Temperature, Wear (NVMe percentage used), PowerOnHours, ReadErrors, WriteErrors, ReadLatency, WriteLatency
- **Classification:** Which disks are cache tier vs capacity tier vs journal
- **Anomaly detection:** Mismatched disk counts across nodes, mixed disk sizes within capacity tier, firmware version inconsistencies, disks with non-healthy status

**Output Object:**
```powershell
[PSCustomObject]@{
    NodeName         = "node01"
    DiskNumber       = 2
    FriendlyName     = "INTEL SSDPE2KX040T8"
    MediaType        = "NVMe"
    Usage            = "Auto-Select"
    Role             = "Capacity"        # Computed: Cache or Capacity
    Size             = [S2DCapacity]::new(3840755982336)  # 3.49 TiB (3.84 TB)
    Model            = "INTEL SSDPE2KX040T8"
    FirmwareVersion  = "VCV10162"
    HealthStatus     = "Healthy"
    WearPercentage   = 12
    Temperature      = 38
    PowerOnHours     = 14892
}
```

### 6.2 Storage Pool Inventory (`Get-S2DStoragePoolInfo`)

**PowerShell Data Sources:**
```powershell
Get-StoragePool -CimSession $session | Where-Object IsPrimordial -eq $false
Get-StoragePool -CimSession $session | Get-PhysicalDisk
Get-StoragePool -CimSession $session | Get-ResiliencySetting
Get-StorageTier -CimSession $session
```

**Collected Properties:**
- Pool FriendlyName, HealthStatus, OperationalStatus, IsReadOnly
- TotalSize (raw), AllocatedSize, RemainingSize (unallocated/free)
- ProvisionedSize vs AllocatedSize (overcommit detection for thin provisioning)
- Supported resiliency settings and their requirements
- Storage tiers configured (Performance, Capacity)
- Fault domain awareness level (PhysicalDisk, StorageEnclosure, StorageScaleUnit)
- WriteCacheSizeDefault

### 6.3 Volume Map (`Get-S2DVolumeMap`)

**PowerShell Data Sources:**
```powershell
Get-VirtualDisk -CimSession $session
Get-Volume -CimSession $session
Get-ClusterSharedVolume -Cluster $clusterName
```

**Collected Properties per Volume:**
- FriendlyName, FileSystem (ReFS, CSVFS_ReFS, NTFS)
- ResiliencySettingName (Mirror, Parity, etc.)
- NumberOfDataCopies (2 = two-way, 3 = three-way)
- PhysicalDiskRedundancy
- ProvisioningType (Fixed or Thin)
- Size (logical size presented to VMs)
- FootprintOnPool (actual pool consumption including resiliency overhead)
- AllocatedSize (for thin: how much is actually written)
- OperationalStatus, HealthStatus
- IsDeduplicationEnabled
- StorageTier breakdown (if tiered)
- **Computed fields:**
  - Resiliency efficiency percentage
  - Overcommit ratio (thin provisioned)
  - Is this the infrastructure volume? (auto-detect by name/size pattern)

### 6.4 Cache Tier Analysis (`Get-S2DCacheTierInfo`)

**Collected Properties:**
- Cache mode (Read+Write, ReadOnly, WriteOnly, or No Cache)
- Cache disk count per node
- Cache disk model, size, health
- Cache-to-capacity binding ratio
- Cache state (Active, Degraded, etc.)
- Software Storage Bus cache statistics (if available)

### 6.5 Health & Alerts (`Get-S2DHealthStatus`)

**PowerShell Data Sources:**
```powershell
Get-HealthFault -CimSession $session
Get-StorageSubSystem -CimSession $session | Get-StorageHealthReport
Debug-StorageSubSystem -CimSession $session
Get-ClusterS2D -CimSession $session
```

**Health Checks (pass/fail with severity):**

| Check | Severity | Description |
|-------|----------|-------------|
| Reserve adequacy | Critical | Is unallocated pool space ≥ recommended reserve? |
| Disk symmetry | Warning | Do all nodes have identical disk count/type? |
| Volume health | Critical | Any volumes in degraded/detached state? |
| Disk health | Critical | Any disks with non-Healthy status? |
| NVMe wear | Warning | Any NVMe disks >80% wear? |
| Thin overcommit | Warning | Total provisioned > total pool capacity? |
| Firmware consistency | Info | All disks of same model on same firmware? |
| Rebuild capacity | Critical | Can the pool survive a node failure and rebuild? |
| Infrastructure volume | Info | Is infrastructure volume present and healthy? |
| Cache tier health | Warning | Any cache disks degraded or missing? |

---

## 7. Capacity Math Engine (`Get-S2DCapacityWaterfall`)

This is the core intellectual property of the module. It computes the full capacity waterfall:

### Waterfall Stages

```
Stage 1: Raw Physical Capacity
    Total bytes across all capacity-tier disks on all nodes
    (Cache disks excluded — they don't contribute to capacity)

Stage 2: After Vendor Labeling Adjustment
    Show the discrepancy: disks are labeled in TB but Windows sees TiB
    Example: 8 × "1.92 TB" NVMe = 15.36 TB labeled → 13.97 TiB actual

Stage 3: After Storage Pool Overhead
    Minor metadata overhead consumed by the pool itself (~0.5-1%)

Stage 4: After Reserve Space
    Recommended: 1 capacity drive per node, up to 4 drives total
    Reserve = min(NodeCount, 4) × LargestCapacityDriveSize
    This space must remain UNALLOCATED in the pool

Stage 5: After Infrastructure Volume
    Azure Local auto-creates an infrastructure volume for:
      - Cluster metadata
      - Storage bus logs
      - Cluster shared volume metadata
    Typically 250-500 GB depending on cluster size

Stage 6: Available for Workload Volumes
    This is what remains for user-created volumes BEFORE resiliency

Stage 7: After Resiliency Overhead (per volume)
    Three-way mirror: usable = footprint ÷ 3  (33.3% efficiency)
    Two-way mirror:   usable = footprint ÷ 2  (50% efficiency)
    Dual parity:      usable depends on encoding (50-80% efficiency)
    Nested mirror:    ~25% efficiency (two-node clusters)
    Mirror-accel parity: ~35-40% efficiency

Stage 8: Final Usable Capacity
    Sum of all volume usable capacities
    This is what VMs/workloads can actually consume
```

### Mixed Resiliency Handling

When a cluster has volumes with different resiliency types, the waterfall computes each volume's overhead independently and produces a blended efficiency:

```powershell
# Example: 3-node cluster, 60 TiB raw
# Volume "VMs"    = 15 TiB three-way mirror → 45 TiB footprint
# Volume "Archive" = 10 TiB dual parity    → 16.7 TiB footprint
# Total footprint: 61.7 TiB — WARNING: exceeds available pool capacity!
```

### "Expected vs Actual" Comparison

The core differentiator. For each stage, show:

| Stage | Expected (Best Practice) | Actual (This Cluster) | Status |
|-------|--------------------------|----------------------|--------|
| Reserve space | 13.97 TiB | 2.1 TiB (unallocated) | ⚠️ INSUFFICIENT |
| Infrastructure volume | Present | Present (256 GB) | ✅ OK |
| Volumes provisioned | ≤ available capacity | 105% overcommit | 🔴 CRITICAL |

---

## 8. Report Artifacts

### 8.1 HTML Dashboard Report (`New-S2DReport -Format Html`)

**Self-contained single-file HTML** with embedded CSS and JavaScript (Chart.js):

- **Executive Summary**: Cluster name, node count, total raw vs usable, health score (green/yellow/red)
- **Capacity Waterfall Chart**: Interactive bar chart showing each stage of capacity consumption
- **Physical Disk Inventory Table**: Sortable, filterable table of all disks with health indicators
- **Storage Pool Overview**: Pool utilization gauge, allocated vs free
- **Volume Map**: Table of all volumes with resiliency type, size, provisioning type
- **Health Checks Dashboard**: Pass/fail cards for each health check with remediation guidance
- **TiB/TB Reference**: Toggle switch to display all values in TiB or TB
- **Export buttons**: Print to PDF, copy tables to clipboard

```powershell
Invoke-S2DCartographer -ClusterName "c01-prd-bal" |
    New-S2DReport -Format Html -OutputPath "C:\Reports\cluster-storage-report.html"
```

### 8.2 Word Document Report (`New-S2DReport -Format Word`)

**Professional .docx** suitable for customer deliverables:

- Cover page with cluster name, date, author
- Table of contents
- Executive summary with key findings and recommendations
- Detailed sections matching the HTML report
- Capacity waterfall as an embedded SVG image
- Disk inventory as formatted Word tables
- Volume map with resiliency details
- Health assessment with severity-coded findings
- Appendix A: TiB vs TB Explanation
- Appendix B: S2D Reserve Space Best Practices
- Appendix C: Raw Data Tables

```powershell
Invoke-S2DCartographer -ClusterName "c01-prd-bal" |
    New-S2DReport -Format Word -OutputPath "C:\Reports\cluster-storage-report.docx" `
                  -Author "Alex Admin" -Company "Hybrid Cloud Solutions, LLC"
```

### 8.3 PDF Report (`New-S2DReport -Format Pdf`)

Generated from the HTML template via headless rendering or direct PDF library. Same content as Word but in a universally readable format.

### 8.4 Excel Workbook (`New-S2DReport -Format Excel`)

**Multi-tab workbook** using ImportExcel module:

| Tab | Content |
|-----|---------|
| Summary | Key metrics, health score, cluster info |
| Capacity Waterfall | Waterfall data with embedded chart |
| Physical Disks | Full disk inventory with all properties |
| Storage Pool | Pool configuration and utilization |
| Volumes | All volumes with resiliency, size, provisioning |
| Health Checks | Pass/fail results with descriptions |
| Raw Data | Complete JSON dump for further analysis |

```powershell
Invoke-S2DCartographer -ClusterName "c01-prd-bal" |
    New-S2DReport -Format Excel -OutputPath "C:\Reports\cluster-storage-data.xlsx"
```

### 8.5 All Formats at Once

```powershell
Invoke-S2DCartographer -ClusterName "c01-prd-bal" |
    New-S2DReport -Format All -OutputDirectory "C:\Reports\2026-04-09-c01-prd-bal\"
```

---

## 9. Diagram Types (`New-S2DDiagram`)

### 9.1 Capacity Waterfall Diagram

A horizontal or vertical waterfall chart showing capacity flowing from raw to usable, with each stage labeled and color-coded:

```
Raw Capacity         ████████████████████████████████████  55.88 TiB
  − Cache tier       ██                                    −6.98 TiB
  − Pool overhead    ░                                     −0.28 TiB
  − Reserve          ████                                  −13.97 TiB
  − Infra volume     ░                                     −0.25 TiB
  = Available        ████████████████████                   34.40 TiB
  − Mirror overhead  ████████████                          −22.93 TiB
  = USABLE           ████████                               11.47 TiB
```

### 9.2 Disk-to-Node Map

Visual diagram showing each node as a box containing its physical disks, color-coded by role (cache/capacity) and health status:

```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│      Node 01        │  │      Node 02        │  │      Node 03        │
│  ┌──┐┌──┐           │  │  ┌──┐┌──┐           │  │  ┌──┐┌──┐           │
│  │C1││C2│  Cache     │  │  │C1││C2│  Cache     │  │  │C1││C2│  Cache     │
│  └──┘└──┘           │  │  └──┘└──┘           │  │  └──┘└──┘           │
│  ┌──┐┌──┐┌──┐┌──┐   │  │  ┌──┐┌──┐┌──┐┌──┐   │  │  ┌──┐┌──┐┌──┐┌──┐   │
│  │D1││D2││D3││D4│   │  │  │D1││D2││D3││D4│   │  │  │D1││D2││D3││D4│   │
│  └──┘└──┘└──┘└──┘   │  │  └──┘└──┘└──┘└──┘   │  │  └──┘└──┘└──┘└──┘   │
│  Capacity: 13.97 TiB │  │  Capacity: 13.97 TiB │  │  Capacity: 13.97 TiB │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

### 9.3 Storage Pool Layout

Pie or stacked bar showing pool allocation:

- Allocated to volumes (broken down per volume)
- Reserve space (recommended vs actual)
- Infrastructure volume
- Free/unallocated (beyond reserve)

### 9.4 Volume Resiliency Diagram

Per-volume diagram showing how data copies are distributed across fault domains:

```
Volume: "VMs" (Three-Way Mirror)
┌────────┐  ┌────────┐  ┌────────┐
│ Copy 1 │  │ Copy 2 │  │ Copy 3 │
│ Node01 │  │ Node02 │  │ Node03 │
│ 5 TiB  │  │ 5 TiB  │  │ 5 TiB  │
└────────┘  └────────┘  └────────┘
Usable: 5 TiB | Footprint: 15 TiB | Efficiency: 33.3%
```

### 9.5 Health Scorecard

Visual dashboard-style SVG with traffic-light indicators for each health check area.

### 9.6 TiB/TB Conversion Reference Chart

Visual side-by-side showing common drive sizes in both units:

| Drive Label (TB) | Actual Bytes | Windows Shows (TiB) | Difference |
|-------------------|-------------|---------------------|------------|
| 960 GB | 960,000,000,000 | 894 GiB | −6.9% |
| 1.92 TB | 1,920,000,000,000 | 1.75 TiB | −6.9% |
| 3.84 TB | 3,840,000,000,000 | 3.49 TiB | −6.9% |
| 7.68 TB | 7,680,000,000,000 | 6.98 TiB | −6.9% |
| 15.36 TB | 15,360,000,000,000 | 13.97 TiB | −6.9% |

---

## 10. Cmdlet Reference (Public Surface)

### Primary Orchestrator

```powershell
Invoke-S2DCartographer
    [-ClusterName <string>]
    [-Credential <PSCredential>]
    [-CimSession <CimSession>]
    [-PSSession <PSSession>]
    [-Local]
    [-KeyVaultName <string>]
    [-SecretName <string>]
    [-OutputDirectory <string>]
    [-Format <string[]>]           # Html, Word, Pdf, Excel, All
    [-IncludeDiagrams]
    [-PrimaryUnit <string>]        # TiB (default) or TB
    [-SkipHealthChecks]
    [-PassThru]                    # Return data object instead of file paths
```

### Individual Cmdlets

```powershell
# Connection
Connect-S2DCluster [-ClusterName] [-Credential] [-CimSession] [-PSSession] [-Local]
Disconnect-S2DCluster

# Collectors (can be run individually for targeted inspection)
Get-S2DPhysicalDiskInventory [-NodeName <string[]>]
Get-S2DStoragePoolInfo
Get-S2DVolumeMap [-VolumeName <string[]>]
Get-S2DCacheTierInfo
Get-S2DHealthStatus [-CheckName <string[]>]
Get-S2DCapacityWaterfall

# Report & Diagram Generation
New-S2DReport [-InputObject <S2DClusterData>] [-Format] [-OutputPath] [-Author] [-Company]
New-S2DDiagram [-InputObject <S2DClusterData>] [-DiagramType] [-OutputPath]

# Utility
ConvertTo-S2DCapacity [-Bytes <int64>] [-TiB <double>] [-TB <double>]
```

---

## 11. Dependencies

| Dependency | Purpose | Required/Optional |
|------------|---------|-------------------|
| PowerShell 7+ | Core runtime | Required |
| FailoverClusters module | Cluster cmdlets | Required (on mgmt machine or node) |
| Storage module | Storage cmdlets | Required (on mgmt machine or node) |
| ImportExcel | Excel report generation | Required |
| PSWriteHTML | HTML report engine (or custom) | Optional (may use custom templates) |
| Az.KeyVault | Key Vault credential retrieval | Optional |
| Az.Accounts | Azure authentication | Optional |
| Pester 5+ | Testing | Dev dependency |
| platyPS | Help documentation | Dev dependency |

---

## 12. Development Phases

### Phase 1: Foundation (Weeks 1-3)

**Deliverables:**
- Repo creation with full scaffolding
- Module manifest and root loader
- `Connect-S2DCluster` and `Disconnect-S2DCluster`
- `ConvertTo-S2DCapacity` with TiB/TB dual display
- `Get-S2DPhysicalDiskInventory` collector
- Pester tests for capacity conversion math
- Mock data files for offline testing (2-node, 3-node, 4-node, 16-node configs)
- README.md with project overview

### Phase 2: Core Collectors (Weeks 4-6)

**Deliverables:**
- `Get-S2DStoragePoolInfo`
- `Get-S2DVolumeMap`
- `Get-S2DCacheTierInfo`
- `Get-S2DCapacityWaterfall` (the capacity math engine)
- `Get-S2DHealthStatus` with all health checks
- Pester tests for reserve calculation, resiliency efficiency math
- PowerShell data model classes

### Phase 3: Reporting Engine (Weeks 7-10)

**Deliverables:**
- `New-S2DReport -Format Html` with Chart.js-based dashboard
- `New-S2DReport -Format Excel` with multi-tab workbook
- `New-S2DReport -Format Word` with professional formatting
- `New-S2DReport -Format Pdf`
- HTML template with responsive design, dark/light mode
- TiB/TB toggle in HTML reports

### Phase 4: Diagrams & Visualization (Weeks 11-13)

**Deliverables:**
- `New-S2DDiagram` with all 6 diagram types
- SVG rendering engine for capacity waterfall
- Disk-to-node map visualization
- Pool layout diagram
- Volume resiliency diagrams
- Diagrams embedded in Word/PDF reports

### Phase 5: Orchestrator & Polish (Weeks 14-16)

**Deliverables:**
- `Invoke-S2DCartographer` main orchestrator
- Key Vault integration for credentials
- MkDocs documentation site
- GitHub Actions CI/CD pipeline
- PowerShell Gallery publishing workflow
- Sample report outputs in `/samples/`
- CHANGELOG.md, CONTRIBUTING.md

### Phase 6: Advanced Features (Post-Launch)

**Future enhancements:**
- OEM-specific disk detail enrichment (Dell iDRAC, HPE iLO, Lenovo XClarity)
- Historical trending (store snapshots, compare over time)
- What-if calculator ("What if I add 2 more nodes?")
- Slack/Teams webhook alerts for health check failures
- Integration with Azure Monitor for cloud-side visibility
- Interactive HTML report with drill-down from pool → volume → disk

---

## 13. Testing Strategy

### Unit Tests (Pester 5)

- **Capacity conversion**: Verify TiB/TB math for known drive sizes
- **Reserve calculation**: Test with 1, 2, 3, 4, 8, 16 node configurations
- **Resiliency efficiency**: Test all mirror and parity types
- **Waterfall stages**: End-to-end math with mock cluster data
- **Health checks**: Each check with pass and fail scenarios

### Integration Tests

- Test against mock CIM session data (serialized from real clusters)
- Test report generation produces valid HTML/docx/xlsx/PDF files
- Test diagram SVG output is well-formed

### Mock Data Sets

| Mock File | Description |
|-----------|-------------|
| `2node-allnvme.json` | 2-node, all NVMe, two-way mirror, healthy |
| `3node-mixed-tier.json` | 3-node, NVMe cache + SSD capacity, three-way mirror |
| `4node-3way-mirror.json` | 4-node, three-way mirror, some thin provisioned |
| `4node-mixed-resiliency.json` | 4-node with both mirror and parity volumes |
| `16node-enterprise.json` | 16-node, max scale, mixed everything |
| `2node-overcommitted.json` | 2-node with thin overcommit — should trigger warnings |
| `3node-insufficient-reserve.json` | 3-node with all space allocated — critical reserve failure |
| `single-node.json` | Single-node cluster (local mirror only) |

---

## 14. PowerShell Gallery Publishing

### Module Manifest Key Fields

```powershell
@{
    RootModule        = 'S2DCartographer.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '<generated>'
    Author            = 'Kristopher Turner'
    CompanyName       = 'Hybrid Cloud Solutions, LLC'
    Copyright         = '(c) 2026 Kristopher Turner. All rights reserved.'
    Description       = 'Storage Spaces Direct analysis, visualization, and reporting for Azure Local and Windows Server clusters. Inventories physical disks, storage pools, and volumes; computes capacity waterfalls with TiB/TB dual display; generates HTML dashboards, Word documents, PDFs, and Excel workbooks with publication-quality diagrams.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Connect-S2DCluster',
        'Disconnect-S2DCluster',
        'Invoke-S2DCartographer',
        'Get-S2DPhysicalDiskInventory',
        'Get-S2DStoragePoolInfo',
        'Get-S2DVolumeMap',
        'Get-S2DCacheTierInfo',
        'Get-S2DHealthStatus',
        'Get-S2DCapacityWaterfall',
        'New-S2DReport',
        'New-S2DDiagram',
        'ConvertTo-S2DCapacity'
    )
    RequiredModules   = @('ImportExcel')
    Tags              = @('S2D', 'StorageSpacesDirect', 'AzureLocal', 'AzureStackHCI', 'Storage',
                          'HCI', 'HyperConverged', 'Reporting', 'Visualization', 'Capacity')
    ProjectUri        = 'https://github.com/AzureLocal/azurelocal-s2dcartographer'
    LicenseUri        = 'https://github.com/AzureLocal/azurelocal-s2dcartographer/blob/main/LICENSE'
    IconUri           = 'https://raw.githubusercontent.com/AzureLocal/azurelocal-s2dcartographer/main/assets/icon.png'
}
```

### GitHub Topics

```
azure-local, storage-spaces-direct, s2d, azure-stack-hci, powershell, 
storage, capacity-planning, reporting, hyper-converged, windows-server
```

---

## 15. Differentiation from Existing Tools

| Feature | S2D Calculator (Cosmos) | Schmitt-Nieto Calculator | SizerLab | **S2DCartographer** |
|---------|------------------------|-------------------------|----------|---------------------|
| Input source | Manual entry | Manual entry | Manual entry | **Live cluster scan** |
| TiB/TB handling | Single unit | Single unit | Single unit | **Dual display always** |
| Expected vs actual | N/A (planning only) | N/A (planning only) | N/A | **Core feature** |
| Infrastructure volume | Not shown | Not shown | Not shown | **Auto-detected** |
| Health assessment | No | No | No | **10+ health checks** |
| Report artifacts | No | No | No | **HTML, Word, PDF, Excel** |
| Diagrams | Basic | Basic | Basic | **6 diagram types** |
| Reserve validation | Static recommendation | Static recommendation | Static | **Live check vs actual** |
| Thin overcommit | No | No | No | **Detected & warned** |
| PowerShell module | No | No | No | **PSGallery installable** |
| Offline/mock mode | N/A | N/A | N/A | **Yes, with mock data** |

---

## 16. Sample Usage Scenarios

### Scenario 1: Quick Health Check

```powershell
Install-Module S2DCartographer
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)
Get-S2DHealthStatus | Format-Table CheckName, Severity, Status, Details
```

### Scenario 2: Customer-Ready Report

```powershell
Invoke-S2DCartographer -ClusterName "customer-cluster-01" `
    -Credential $cred `
    -Format Word, Pdf `
    -OutputDirectory "C:\Deliverables\Acme-Corp\" `
    -Author "Alex Admin" `
    -Company "Contoso" `
    -IncludeDiagrams
```

### Scenario 3: Capacity Planning Deep Dive

```powershell
Connect-S2DCluster -ClusterName "c01-prd-bal"
$waterfall = Get-S2DCapacityWaterfall
$waterfall | Format-List  # See every stage

# "What does the reserve situation look like?"
$waterfall.ReserveStatus  # Returns: Adequate, Warning, or Critical
$waterfall.ReserveRecommended  # 13.97 TiB
$waterfall.ReserveActual       # 2.1 TiB
$waterfall.ReserveDeficit      # 11.87 TiB
```

### Scenario 4: Multi-Cluster Comparison (Excel)

```powershell
$clusters = @("cluster01", "cluster02", "cluster03")
$results = $clusters | ForEach-Object {
    Invoke-S2DCartographer -ClusterName $_ -Credential $cred -PassThru
}
$results | New-S2DReport -Format Excel -OutputPath "C:\Reports\all-clusters.xlsx"
```

---

## 17. Blog & Community Launch Plan

1. **thisismydemo.cloud blog post**: "Introducing S2DCartographer: Finally See Your Storage Spaces Direct the Way It Really Is"
2. **GitHub README** with animated GIF showing `Invoke-S2DCartographer` producing a full HTML report
3. **PowerShell Gallery** publish with comprehensive description and tags
4. **Social media**: Twitter/LinkedIn announcement with sample report screenshots
5. **MMS MOA or Dell Tech World demo**: Live demo scanning a cluster and generating reports on stage
6. **Hyper-V Renaissance blog series**: Reference in Post 18/19 as the companion tool for S2D chapter