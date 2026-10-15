# Get-S2DCacheTierInfo

Analyzes the S2D cache tier configuration, binding ratio, and health.

---

## Synopsis

Classifies cache vs capacity disks, computes the cache-to-capacity binding ratio, and surfaces degradation or missing cache disk conditions.

Handles all-NVMe clusters (software write-back cache) and hybrid configurations (NVMe/SSD cache over HDD/SSD capacity tier).

Requires an active session from `Connect-S2DCluster`, or use `-CimSession` directly.

---

## Syntax

```powershell
Get-S2DCacheTierInfo
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

`S2DCacheTier` — a single object describing the cache configuration.

Key properties:

| Property | Description |
|---|---|
| `CacheMode` | `WriteBack`, `WriteThrough`, or `Disabled` |
| `IsAllFlash` | `$true` when all pool disks are NVMe or SSD |
| `CacheDiskCount` | Number of cache-tier disks in the cluster |
| `CapacityDiskCount` | Number of capacity-tier disks in the cluster |
| `CacheToCapacityRatio` | Cache disk count / capacity disk count (e.g. `1:4`) |
| `CacheDiskMediaType` | Media type of cache disks (`NVMe`, `SSD`) |
| `CapacityDiskMediaType` | Media type of capacity disks (`NVMe`, `SSD`, `HDD`) |
| `HealthStatus` | `Healthy`, `Degraded`, `Unhealthy` |
| `DegradedNodes` | Nodes with a missing or failed cache disk |

---

## Examples

**Basic cache info:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DCacheTierInfo
```

**Key cache metrics:**

```powershell
Get-S2DCacheTierInfo | Select-Object CacheMode, IsAllFlash, CacheDiskCount, CacheToCapacityRatio
```

**Check for degraded cache:**

```powershell
$cache = Get-S2DCacheTierInfo
if ($cache.HealthStatus -ne 'Healthy') {
    "Cache degraded on: $($cache.DegradedNodes -join ', ')"
}
```
