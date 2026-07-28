# Get-S2DVolumeMap

Maps all S2D volumes (virtual disks) with resiliency type, pool footprint, efficiency percentage, provisioning type, and infrastructure volume classification.

---

## Syntax

```powershell
Get-S2DVolumeMap [[-VolumeName] <string[]>] [[-CimSession] <CimSession>]
```

## Parameters

| Parameter | Type | Description |
| --- | --- | --- |
| `-VolumeName` | `string[]` | Limit results to specific volume friendly names. |
| `-CimSession` | `CimSession` | Override the module session CimSession. |

---

## Output

Returns `S2DVolume[]` — one object per virtual disk.

| Property | Type | Description |
| --- | --- | --- |
| `FriendlyName` | `string` | Volume name |
| `FileSystem` | `string` | `CSVFS_ReFS`, `CSVFS_NTFS`, or `Unknown` |
| `ResiliencySettingName` | `string` | `Mirror` or `Parity` |
| `NumberOfDataCopies` | `int` | Data copy count (2 = two-way, 3 = three-way) |
| `PhysicalDiskRedundancy` | `int` | Disk failure tolerance |
| `ProvisioningType` | `string` | `Fixed` or `Thin` |
| `Size` | `S2DCapacity` | Logical volume size (what VMs see) |
| `FootprintOnPool` | `S2DCapacity` | Actual pool space consumed (includes resiliency overhead) |
| `AllocatedSize` | `S2DCapacity` | Bytes written to the volume (thin volumes only) |
| `OperationalStatus` | `string` | `OK`, `InService`, `Online`, or error state |
| `HealthStatus` | `string` | `Healthy`, `Warning`, or `Unhealthy` |
| `IsDeduplicationEnabled` | `bool` | Whether deduplication is active |
| `IsInfrastructureVolume` | `bool` | Azure Local infrastructure volume detection (see below) |
| `EfficiencyPercent` | `double` | Resiliency efficiency (logical ÷ footprint × 100) |
| `OvercommitRatio` | `double` | Thin overcommit ratio for this volume (`AllocatedSize ÷ FootprintOnPool`) |
| `ThinGrowthHeadroom` | `S2DCapacity` | Remaining write headroom before pool footprint equals provisioned size: `Size − AllocatedSize`. `$null` for fixed-provisioned volumes. |
| `MaxPotentialFootprint` | `S2DCapacity` | Maximum pool space this volume could consume if written completely full: `Size × NumberOfDataCopies`. `$null` for fixed-provisioned volumes. |

---

## Resiliency Efficiency

`EfficiencyPercent` is computed per volume based on resiliency type and node count:

| Configuration | `EfficiencyPercent` |
| --- | --- |
| Two-way mirror | 50.0 |
| Three-way mirror | 33.3 |
| Nested two-way mirror (2-node) | 25.0 |
| Single parity | 66.7 (4-node) / 75.0 (6-node) |
| Dual parity (LRC) | 50.0 (4-node) / 66.7 (6-node) |

The blended efficiency across all workload volumes is reported as `BlendedEfficiencyPercent` on the `S2DCapacityWaterfall` object.

---

## Infrastructure Volume Detection

Azure Local automatically creates one or more infrastructure volumes for cluster metadata, storage bus layer logs, and CSV cache. `Get-S2DVolumeMap` detects these volumes and sets `IsInfrastructureVolume = $true` using two signals:

**Name pattern match** (any of):

- `Infrastructure_<guid>` — Azure Local infrastructure CSV
- `ClusterPerformanceHistory` — storage performance history
- Any name containing `infra` or `infrastructure`

**Size heuristic:**

- Volumes smaller than 600 GiB are flagged as infrastructure volumes

> [!NOTE]
> **Infrastructure volume in capacity math**
> The infrastructure volume footprint is broken out in Stage 5 of the capacity waterfall so that it does not inflate the workload usable capacity figure. Use `Where-Object IsInfrastructureVolume -eq $false` to see workload volumes only.
>
---

## CIM Sources

```powershell
Get-VirtualDisk
```

Volume objects are constructed from `VirtualDisk` WMI properties. File system type is inferred from the filesystem field; cluster shared volume association is implied by the CSV namespace path.

---

## Session Behavior

Results are cached in `$Script:S2DSession.CollectedData['Volumes']` after first collection. `Get-S2DCapacityWaterfall` and `Get-S2DHealthStatus` read from this cache.

When `-VolumeName` is specified, the filter is applied **after** caching — all volumes are cached, but only the requested ones are returned to the caller.

---

## Examples

```powershell
# All volumes with key properties
Get-S2DVolumeMap | Format-Table FriendlyName, ResiliencySettingName, Size, FootprintOnPool, EfficiencyPercent, IsInfrastructureVolume

# Workload volumes only
Get-S2DVolumeMap | Where-Object IsInfrastructureVolume -eq $false

# Thin-provisioned volumes with overcommit
Get-S2DVolumeMap | Where-Object ProvisioningType -eq 'Thin' | Format-Table FriendlyName, Size, AllocatedSize, OvercommitRatio

# Thin provisioning risk — max potential footprint vs current pool footprint
Get-S2DVolumeMap |
    Where-Object { $_.ProvisioningType -eq 'Thin' -and $_.MaxPotentialFootprint } |
    Format-Table FriendlyName, Size, ThinGrowthHeadroom, MaxPotentialFootprint, AllocatedSize

# Unhealthy volumes
Get-S2DVolumeMap | Where-Object HealthStatus -ne 'Healthy' | Format-List

# Single volume detail
Get-S2DVolumeMap -VolumeName "VM-Storage-01" | Format-List
```

---

## Troubleshooting

> [!WARNING]
> **No volumes returned**
> If the command emits `No virtual disks found`, either no volumes have been created yet or the PSSession cannot see them. Verify on a cluster node:
>
> ```powershell
> Get-VirtualDisk | Format-Table FriendlyName, OperationalStatus, HealthStatus
> ```
>
!!! tip "Usable Capacity (Stage 7) is zero after Get-S2DCapacityWaterfall"
    If the final usable capacity is 0 TiB, no workload volumes were found — either all volumes are classified as infrastructure, or `Get-S2DVolumeMap` returned no results. Check:

    ```powershell
    Get-S2DVolumeMap | Format-Table FriendlyName, IsInfrastructureVolume, Size
    ```

    If all show `IsInfrastructureVolume = $true`, verify that workload CSV volumes have been created.
