# Get-S2DCacheTierInfo

Analyzes the S2D cache tier configuration, classifies cache vs capacity disks, computes the cache-to-capacity ratio, and detects all-flash software cache configurations.

---

## Syntax

```powershell
Get-S2DCacheTierInfo [[-CimSession] <CimSession>]
```

## Parameters

| Parameter | Type | Description |
| --- | --- | --- |
| `-CimSession` | `CimSession` | Override the module session CimSession. |

---

## Output

Returns `S2DCacheTier` — a single object describing the cache tier.

| Property | Type | Description |
| --- | --- | --- |
| `CacheMode` | `string` | `ReadWrite`, `ReadOnly`, `WriteOnly`, or `No Cache` |
| `IsAllFlash` | `bool` | `$true` when no HDD or Unknown media types are present |
| `SoftwareCacheEnabled` | `bool` | `$true` on all-flash clusters (software write-back cache) |
| `CacheDiskCount` | `int` | Number of physical cache disks identified |
| `CacheDiskModel` | `string` | Most common cache disk model |
| `CacheDiskSize` | `S2DCapacity` | Largest cache disk size (TiB + TB) |
| `CacheToCapacityRatio` | `double` | Cache disk count ÷ capacity disk count |
| `CacheState` | `string` | `Active`, `Degraded`, or `None` |
| `WriteCacheSizeBytes` | `int64` | Write cache size from `ClusterS2D` settings |

---

## Cache Architecture Modes

### Hybrid (NVMe/SSD over HDD)

The classic S2D cache configuration: faster media (NVMe or SSD) serves as a read/write cache for slower capacity drives (SSD or HDD). S2DCartographer identifies cache disks by `Usage = Journal` or by being the highest-ranked media type in the pool.

```
CacheMode:   ReadWrite
IsAllFlash:  False
CacheDiskCount: 2 (per node × 4 nodes = 8 total)
CacheToCapacityRatio: 0.5
```

### All-Flash / All-NVMe

When all drives are NVMe or SSD, S2D does not use a physical cache/capacity split. Instead, it enables a **software write-back cache** across all drives. S2DCartographer detects this automatically:

- `IsAllFlash = $true` — no HDD or Unknown media found
- `SoftwareCacheEnabled = $true` — set from `ClusterS2D.CacheEnabled` or forced when all-flash is detected
- `CacheDiskCount = 0` — no dedicated cache devices

> [!NOTE]
> **All-NVMe is the Azure Local default**
> Most Azure Local HCI configurations validated by Microsoft use all-NVMe drives. On these clusters, the software write-back cache is the only cache mechanism — `Get-S2DCacheTierInfo` will report `IsAllFlash = $true` and `SoftwareCacheEnabled = $true` with no physical cache disks.
>
---

## CacheState Values

| State | Meaning |
| --- | --- |
| `Active` | All cache disks are healthy, or software cache is enabled |
| `Degraded` | One or more cache disks are in a non-Healthy state |
| `None` | No cache tier and no software cache detected |

A `Degraded` cache tier dramatically reduces write performance and may increase the risk of data loss if the cluster sustains additional failures. The `CacheTierHealth` check in `Get-S2DHealthStatus` flags this as a warning.

---

## CIM Sources

```powershell
Get-PhysicalDisk                 # disk classification (media type, Usage)
Get-ClusterS2D                   # software cache settings (CacheEnabled, CacheMode)
```

The function reuses physical disk data from `$Script:S2DSession.CollectedData['PhysicalDisks']` when available, avoiding a redundant `Get-PhysicalDisk` query.

---

## Session Behavior

Results are cached in `$Script:S2DSession.CollectedData['CacheTier']`. `Get-S2DHealthStatus` reads from this cache for the `CacheTierHealth` check.

---

## Examples

```powershell
# Cache tier summary
Get-S2DCacheTierInfo | Select-Object CacheMode, IsAllFlash, SoftwareCacheEnabled, CacheDiskCount, CacheState

# All-NVMe check
$cache = Get-S2DCacheTierInfo
if ($cache.IsAllFlash) {
    "All-flash cluster. Software cache: $($cache.SoftwareCacheEnabled)"
} else {
    "Hybrid cluster. Cache disks: $($cache.CacheDiskCount), ratio: $($cache.CacheToCapacityRatio):1"
}

# Cache disk inventory
Get-S2DPhysicalDiskInventory | Where-Object Role -eq 'Cache' | Format-Table NodeName, FriendlyName, Size, HealthStatus
```

---

## Troubleshooting

> [!WARNING]
> **CacheDiskCount is 0 on a hybrid cluster**
> If you expect physical cache disks but see `CacheDiskCount = 0`, the cache disks may not be classified correctly. Check that `Get-S2DPhysicalDiskInventory` shows some disks with `Role = Cache` or `Usage = Journal`.
>
> On all-NVMe clusters this is expected — `CacheDiskCount = 0` with `SoftwareCacheEnabled = $true` is correct.
>
!!! tip "WriteCacheSizeBytes is 0"
    `WriteCacheSizeBytes` is sourced from `Get-ClusterS2D`. On clusters where `Get-ClusterS2D` is unavailable (e.g., non-domain-joined management machines without RSAT), this property will be 0 even if the cluster has an active write cache. The `IsAllFlash` and `CacheState` properties are still computed from disk data.
