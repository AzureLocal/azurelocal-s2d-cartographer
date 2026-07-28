# Get-S2DStoragePoolInfo

Returns S2D storage pool configuration, capacity allocation, resiliency settings, storage tiers, and thin provisioning overcommit status.

---

## Syntax

```powershell
Get-S2DStoragePoolInfo [[-CimSession] <CimSession>]
```

## Parameters

| Parameter | Type | Description |
| --- | --- | --- |
| `-CimSession` | `CimSession` | Override the module session CimSession. |

---

## Output

Returns `S2DStoragePool` — a single object representing the non-primordial S2D pool.

### Top-level properties

| Property | Type | Description |
| --- | --- | --- |
| `FriendlyName` | `string` | Pool name (e.g., `S2D on c01-prd-bal`) |
| `HealthStatus` | `string` | `Healthy`, `Warning`, or `Unhealthy` |
| `OperationalStatus` | `string` | WMI operational state |
| `IsReadOnly` | `bool` | Whether the pool is in read-only mode |
| `TotalSize` | `S2DCapacity` | Total pool capacity (TiB + TB) |
| `AllocatedSize` | `S2DCapacity` | Pool space consumed by all virtual disk footprints |
| `RemainingSize` | `S2DCapacity` | `TotalSize − AllocatedSize` |
| `ProvisionedSize` | `S2DCapacity` | Sum of all virtual disk *logical* sizes (thin or fixed) |
| `OvercommitRatio` | `double` | `ProvisionedSize ÷ TotalSize`; > 1.0 indicates overcommit |
| `FaultDomainAwareness` | `string` | `PhysicalDisk`, `StorageEnclosure`, or `StorageScaleUnit` |
| `WriteCacheSizeDefault` | `int64` | Default write cache size in bytes |
| `ResiliencySettings` | `object[]` | Available resiliency configurations (see below) |
| `StorageTiers` | `object[]` | Configured storage tiers (see below) |

### ResiliencySettings items

| Property | Description |
| --- | --- |
| `Name` | `Mirror`, `Parity`, or a custom name |
| `NumberOfDataCopies` | Number of data copies (2 = two-way, 3 = three-way) |
| `PhysicalDiskRedundancy` | Number of disk failures tolerated |
| `NumberOfColumns` | Stripe columns for parity calculations |

### StorageTiers items

| Property | Description |
| --- | --- |
| `FriendlyName` | Tier name (e.g., `Performance`, `Capacity`) |
| `MediaType` | `NVMe`, `SSD`, `HDD` |
| `Size` | Tier total size as `S2DCapacity` |
| `AllocatedSize` | Tier space consumed |

---

## Understanding OvercommitRatio

The `OvercommitRatio` reflects thin provisioning exposure:

- **≤ 1.0** — All volumes are within pool capacity. Fixed-provisioned volumes always have ratio ≤ 1.0.
- **> 1.0** — Total logical size of all volumes exceeds pool physical capacity. This is only possible with thin-provisioned volumes. Actual space is only consumed as data is written, so the ratio alone is not an emergency — but growth trends should be monitored.

The `ThinOvercommit` health check in `Get-S2DHealthStatus` flags any cluster where `OvercommitRatio > 1.0`.

> [!WARNING]
> **Overcommit and pool exhaustion**
> If thin volumes grow to consume their full logical size, the pool can run out of space unexpectedly. This causes volume pauses and can corrupt workloads. Monitor `RemainingSize` against expected growth rates.
>
---

## CIM Sources

```powershell
Get-StoragePool | Where-Object IsPrimordial -eq $false
$pool | Get-ResiliencySetting
$pool | Get-StorageTier
Get-VirtualDisk  # for ProvisionedSize calculation
```

The function targets the first non-primordial pool. In a standard S2D deployment there is exactly one such pool. If no pool is found, the function returns `$null` and emits a warning.

---

## Session Behavior

Results are cached in `$Script:S2DSession.CollectedData['StoragePool']` after first collection. `Get-S2DCapacityWaterfall` and `Get-S2DHealthStatus` both read from this cache automatically.

---

## Examples

```powershell
# Pool summary
Get-S2DStoragePoolInfo | Select-Object FriendlyName, HealthStatus, TotalSize, RemainingSize, OvercommitRatio

# Resiliency settings table
(Get-S2DStoragePoolInfo).ResiliencySettings | Format-Table Name, NumberOfDataCopies, PhysicalDiskRedundancy

# Check for overcommit
$pool = Get-S2DStoragePoolInfo
if ($pool.OvercommitRatio -gt 1.0) {
    Write-Warning "Pool is overcommitted: $($pool.OvercommitRatio)x"
}

# Capacity at a glance
$pool = Get-S2DStoragePoolInfo
"Total:      $($pool.TotalSize.Display)"
"Allocated:  $($pool.AllocatedSize.Display)"
"Free:       $($pool.RemainingSize.Display)"
"Overcommit: $($pool.OvercommitRatio)x"
```

---

## Troubleshooting

> [!CAUTION]
> **Returns `$null` — pool not found**
> If the command returns nothing and warns `No non-primordial storage pool found`, S2D may not be enabled or the pool may be offline.
>
> Verify on a cluster node:
>
> ```powershell
> Get-StoragePool | Where-Object IsPrimordial -eq $false
> ```
>
> If no pool is returned, check `Get-ClusterS2D` to confirm S2D is enabled.
>
!!! note "AllocatedSize vs ProvisionedSize"
    `AllocatedSize` is the actual pool footprint consumed by virtual disk data (resiliency overhead included). `ProvisionedSize` is the sum of logical sizes as seen by the guest — for thin volumes these differ. Use `AllocatedSize` for physical capacity planning, `ProvisionedSize` for overcommit monitoring.
