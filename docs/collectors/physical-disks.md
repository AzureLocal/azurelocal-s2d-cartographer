# Get-S2DPhysicalDiskInventory

Inventories all physical disks in the S2D cluster with health, capacity, wear, and reliability data — collected per node over WinRM or local execution.

---

## Syntax

```powershell
Get-S2DPhysicalDiskInventory [[-NodeName] <string[]>] [[-CimSession] <CimSession>]
```

## Parameters

| Parameter | Type | Description |
| --- | --- | --- |
| `-NodeName` | `string[]` | Limit results to one or more specific node names. |
| `-CimSession` | `CimSession` | Override the module session CimSession. Useful for ad-hoc calls without a full `Connect-S2DCluster` session. |

---

## Output

Returns `PSCustomObject[]` — one object per physical disk.

| Property | Type | Description |
| --- | --- | --- |
| `NodeName` | `string` | Node that reported this disk |
| `DiskNumber` | `int` | Windows disk number (from `Get-Disk`) |
| `UniqueId` | `string` | Storage subsystem unique identifier |
| `FriendlyName` | `string` | Vendor-reported model string |
| `SerialNumber` | `string` | Drive serial number |
| `Model` | `string` | Disk model identifier |
| `MediaType` | `string` | `NVMe`, `SSD`, `HDD`, or `SCM` |
| `BusType` | `string` | `NVMe`, `SATA`, `SAS`, `RAID`, etc. |
| `FirmwareVersion` | `string` | Active firmware version string |
| `Manufacturer` | `string` | Drive vendor |
| `Role` | `string` | `Cache`, `Capacity`, or `Unknown` |
| `Usage` | `string` | S2D usage classification: `Auto-Select`, `Journal`, `Retired` |
| `CanPool` | `bool` | Whether the disk is eligible for pooling |
| `IsPoolMember` | `bool` | Whether this disk is currently a member of the S2D storage pool. **Use this to filter out boot drives (BOSS) and SAN-presented LUNs that happen to be visible to the node.** |
| `HealthStatus` | `string` | `Healthy`, `Warning`, or `Unhealthy` |
| `OperationalStatus` | `string` | Operational state from WMI |
| `PhysicalLocation` | `string` | Physical bay/slot location string (when available) |
| `SlotNumber` | `int` | Numeric slot number (when available) |
| `Size` | `S2DCapacity` | Disk capacity (TiB + TB dual-display) |
| `SizeBytes` | `int64` | Raw capacity in bytes |
| `Temperature` | `int` | Drive temperature in Celsius |
| `WearPercentage` | `int` | NVMe wear percentage (0–100) |
| `PowerOnHours` | `int64` | Total power-on hours |
| `ReadErrors` | `int64` | Uncorrected read errors |
| `WriteErrors` | `int64` | Uncorrected write errors |
| `ReadLatency` | `int64` | Average read latency (when available) |
| `WriteLatency` | `int64` | Average write latency (when available) |

---

## Pool Membership Filter

`Get-S2DPhysicalDiskInventory` returns **every** disk visible to every node — boot drives (Dell BOSS, HPE SmartArray M.2, etc.), SAN-presented LUNs, and anything else Windows can see. This is intentional: the collector gives downstream consumers full fidelity, and the JSON / CSV exports always preserve every disk.

The rendered reports (HTML, Word, PDF, Excel Physical Disk Inventory table) **filter to pool members only by default**. The filter is driven by the `IsPoolMember` boolean on each disk:

- `IsPoolMember = $true` — disk is a member of the S2D storage pool. Included.
- `IsPoolMember = $false` — disk is visible to the node but not a pool member (boot drive, SAN LUN, spare). Excluded from the rendered table.

To include non-pool disks in rendered reports:

```powershell
Invoke-S2DCartographer -ClusterName <name> -IncludeNonPoolDisks
New-S2DReport -InputObject $data -Format All -IncludeNonPoolDisks
```

Health checks (`DiskSymmetry`, `DiskHealth`, `NVMeWear`, `FirmwareConsistency`, `RebuildCapacity`) always operate on pool members only, regardless of this switch — non-pool disks are not in S2D scope.

---

## Role Classification

S2DCartographer classifies each disk as `Cache`, `Capacity`, or `Unknown` based on two factors:

1. **Usage field** — disks with `Usage = Journal` are always `Cache`.
2. **Media type heuristic** — within the pool, disks with the highest media rank (NVMe > SSD > HDD) are classified as `Cache`; lower-rank disks are `Capacity`.

On **all-NVMe clusters** where all drives share the same media type, all pool disks are classified as `Capacity` — S2D uses a software write-back cache in this configuration rather than a physical cache tier.

---

## Anomaly Detection

On first collection, `Get-S2DPhysicalDiskInventory` emits `Write-Warning` output for any of the following conditions:

- **Disk symmetry** — disk count differs across nodes (asymmetric configuration is unsupported by S2D)
- **Mixed capacity sizes** — capacity-tier disks of different sizes within the cluster
- **Firmware inconsistency** — disks of the same model running different firmware versions
- **Non-healthy disks** — any disk not in `Healthy` state

These warnings surface immediately in the console and are also detected formally by `Get-S2DHealthStatus` as `DiskSymmetry`, `FirmwareConsistency`, and `DiskHealth` checks.

---

## CIM Sources

```powershell
Get-PhysicalDisk                           # per node
Get-PhysicalDisk | Get-StorageReliabilityCounter  # per disk
Get-Disk                                   # enriches physical location and slot
Get-StoragePool | Get-PhysicalDisk         # pool membership check
```

All queries run per node when PSSession is available. When only a CimSession is present, the function creates temporary per-node CIM sessions from the node list stored in `$Script:S2DSession.Nodes`.

---

## Session Behavior

| Connection type | How disks are collected |
| --- | --- |
| PSSession (standard remote) | `Invoke-Command` to each node; runs locally on that node |
| CimSession only | Creates temporary per-node `CimSession` from the node list |
| `-Local` switch | Runs against `$env:COMPUTERNAME` directly |
| `-NodeName` filter | Applied after collection; no impact on CIM sessions opened |

Results are cached in `$Script:S2DSession.CollectedData['PhysicalDisks']` after first collection. Subsequent callers (including `Get-S2DCapacityWaterfall`, `Get-S2DHealthStatus`, and `Get-S2DCacheTierInfo`) read from cache without a network round-trip.

---

## Examples

```powershell
# Full inventory — all nodes
Get-S2DPhysicalDiskInventory | Format-Table NodeName, FriendlyName, Role, Size, WearPercentage, HealthStatus

# NVMe wear report — highlight drives over 60%
Get-S2DPhysicalDiskInventory |
    Where-Object { $_.MediaType -eq 'NVMe' } |
    Sort-Object WearPercentage -Descending |
    Format-Table NodeName, FriendlyName, WearPercentage, PowerOnHours

# Single-node inventory
Get-S2DPhysicalDiskInventory -NodeName "node01"

# Capacity-tier disks only
Get-S2DPhysicalDiskInventory | Where-Object Role -eq 'Capacity' | Format-Table FriendlyName, Size, FirmwareVersion
```

---

## Troubleshooting

> [!WARNING]
> **Returns empty or partial results**
> If the command returns nothing or only disks from some nodes, at least one node is unreachable. Use `-Verbose` to see per-node connection attempts:
>
> ```powershell
> Get-S2DPhysicalDiskInventory -Verbose
> ```
>
> Look for `WARNING: Could not collect disks from node` lines.
>
!!! note "Reliability counters may be null"
    `WearPercentage`, `PowerOnHours`, `ReadErrors`, and `WriteErrors` are sourced from `Get-StorageReliabilityCounter`. Some drivers and firmware versions do not expose all reliability counters — these properties will be `$null` when the counter is unavailable.

> [!TIP]
> **Running on a cluster node**
> If you run `Connect-S2DCluster -Local` directly on a node, the function skips per-node session creation and queries the local host only. All pool disks visible to that node will be returned, but disks exclusively visible to other nodes may be missing.
