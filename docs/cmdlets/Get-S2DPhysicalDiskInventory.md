# Get-S2DPhysicalDiskInventory

Inventories all physical disks in the S2D cluster with health, capacity, and wear data.

---

## Synopsis

Queries each cluster node for physical disk properties, reliability counters, and storage pool membership. Classifies each disk as Cache or Capacity tier, detects symmetry anomalies across nodes, and surfaces firmware inconsistencies.

Pool-member disks are deduplicated by `UniqueId` — because `Get-PhysicalDisk` on any S2D node returns ALL pool-member disks globally, querying each node individually would otherwise inflate the count by NodeCount×. Node ownership is resolved via `Get-StorageNode` associations.

Requires an active session from `Connect-S2DCluster`, or use `-CimSession` for a direct ad-hoc call.

---

## Syntax

```powershell
Get-S2DPhysicalDiskInventory
    [-NodeName <string[]>]
    [-CimSession <CimSession>]
```

---

## Parameters

### `-NodeName`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | all nodes |

Limit results to one or more specific node names. Example: `-NodeName "node01", "node02"`.

---

### `-CimSession`

| | |
|---|---|
| Type | `CimSession` |
| Required | No |
| Default | uses module session |

Override the module session and target this `CimSession` directly. Useful for ad-hoc calls without a full `Connect-S2DCluster` session.

---

## Outputs

`PSCustomObject[]` — one object per physical disk.

Key properties returned per disk:

| Property | Description |
|---|---|
| `NodeName` | Cluster node the disk belongs to |
| `FriendlyName` | Disk model/friendly name |
| `SerialNumber` | Disk serial number |
| `UniqueId` | Globally unique disk identifier |
| `MediaType` | `NVMe`, `SSD`, or `HDD` |
| `Role` | `Cache` or `Capacity` |
| `SizeBytes` | Raw size in bytes |
| `Size` | `S2DCapacity` object (TiB + TB dual display) |
| `HealthStatus` | `Healthy`, `Warning`, `Unhealthy` |
| `OperationalStatus` | WMI operational status |
| `WearPercentage` | Percentage of life consumed (NVMe/SSD) |
| `IsPoolMember` | `$true` if this disk is a storage pool member |
| `FirmwareVersion` | Disk firmware version |
| `BusType` | `NVMe`, `SATA`, `SAS`, etc. |
| `CanPool` | Whether the disk is eligible to be added to a pool |

---

## Examples

**All pool-member disks:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DPhysicalDiskInventory
```

**Summary table:**

```powershell
Get-S2DPhysicalDiskInventory | Format-Table NodeName, FriendlyName, Role, Size, HealthStatus, WearPercentage
```

**Filter to specific nodes:**

```powershell
Get-S2DPhysicalDiskInventory -NodeName "node01", "node02"
```

**Show only unhealthy disks:**

```powershell
Get-S2DPhysicalDiskInventory | Where-Object HealthStatus -ne 'Healthy'
```

**Check wear on all NVMe drives:**

```powershell
Get-S2DPhysicalDiskInventory |
    Where-Object MediaType -eq 'NVMe' |
    Select-Object NodeName, FriendlyName, SerialNumber, WearPercentage |
    Sort-Object WearPercentage -Descending
```
