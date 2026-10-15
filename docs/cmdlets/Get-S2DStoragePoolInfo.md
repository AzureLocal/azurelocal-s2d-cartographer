# Get-S2DStoragePoolInfo

Returns S2D storage pool configuration, capacity allocation, and overcommit status.

---

## Synopsis

Queries the non-primordial storage pool for health, total/allocated/remaining capacity, resiliency settings, storage tiers, fault domain awareness, and thin provisioning overcommit ratio.

Requires an active session from `Connect-S2DCluster`, or use `-CimSession` directly.

---

## Syntax

```powershell
Get-S2DStoragePoolInfo
    [-CimSession <CimSession>]
```

---

## Parameters

### `-CimSession`

| | |
|---|---|
| Type | `CimSession` |
| Required | No |
| Default | uses module session |

Override the module session and target this `CimSession` directly.

---

## Outputs

`S2DStoragePool` — a single object representing the S2D pool.

Key properties:

| Property | Description |
|---|---|
| `FriendlyName` | Pool name |
| `HealthStatus` | `Healthy`, `Warning`, `Unhealthy` |
| `OperationalStatus` | WMI operational status |
| `TotalSize` | Total pool capacity as `S2DCapacity` |
| `AllocatedSize` | Allocated (provisioned) capacity as `S2DCapacity` |
| `RemainingSize` | Free capacity as `S2DCapacity` |
| `ProvisioningTypeDefault` | `Thin` or `Fixed` |
| `ResiliencySettings` | Array of resiliency configurations (Mirror, Parity) |
| `NumberOfDataCopies` | Current resiliency factor |
| `FaultDomainAwarenessDefault` | `PhysicalDisk`, `StorageScaleUnit`, etc. |
| `OvercommitRatio` | Thin-provisioned logical size / pool total (>1 = overcommitted) |
| `IsReadOnly` | `$true` if the pool is in a read-only state |

---

## Examples

**Basic pool info:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DStoragePoolInfo
```

**Key capacity numbers:**

```powershell
Get-S2DStoragePoolInfo | Select-Object FriendlyName, HealthStatus, TotalSize, RemainingSize
```

**Check overcommit ratio:**

```powershell
$pool = Get-S2DStoragePoolInfo
"Overcommit ratio: $($pool.OvercommitRatio)"
```
