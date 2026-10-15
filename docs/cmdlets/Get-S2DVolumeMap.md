# Get-S2DVolumeMap

Maps all S2D volumes with resiliency type, capacity footprint, and provisioning detail.

---

## Synopsis

Queries `VirtualDisk` and `ClusterSharedVolume`. Returns per-volume resiliency efficiency, footprint on pool, provisioning type, overcommit ratio for thin volumes, and thin growth headroom. Auto-detects Azure Local infrastructure volumes by name and size pattern.

Requires an active session from `Connect-S2DCluster`, or use `-CimSession` directly.

---

## Syntax

```powershell
Get-S2DVolumeMap
    [-VolumeName <string[]>]
    [-CimSession <CimSession>]
```

---

## Parameters

### `-VolumeName`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | all volumes |

Limit results to one or more specific volume friendly names.

---

### `-CimSession`

| | |
|---|---|
| Type | `CimSession` |
| Required | No |
| Default | uses module session |

Override the module session and target this `CimSession` directly.

---

## Outputs

`S2DVolume[]` — one object per volume.

Key properties:

| Property | Description |
|---|---|
| `FriendlyName` | Volume name |
| `ResiliencySettingName` | `Mirror` or `Parity` |
| `NumberOfDataCopies` | Resiliency factor (2 = 2-way mirror, 3 = 3-way mirror) |
| `ProvisioningType` | `Thin` or `Fixed` |
| `Size` | Logical size as `S2DCapacity` |
| `FootprintOnPool` | Physical space consumed on the pool as `S2DCapacity` |
| `EfficiencyPercent` | Logical size / footprint × 100 |
| `AllocatedSize` | Actually written data (thin volumes) as `S2DCapacity` |
| `ThinGrowthHeadroom` | Remaining thin headroom before pool is full as `S2DCapacity` |
| `MaxPotentialFootprint` | Maximum pool space this thin volume could ever consume as `S2DCapacity` |
| `OvercommitRatio` | `MaxPotentialFootprint / pool.TotalSize` |
| `HealthStatus` | `Healthy`, `Warning`, `Unhealthy` |
| `OperationalStatus` | WMI operational status |
| `IsInfrastructureVolume` | `$true` for Azure Local system volumes (UserStorage, SBEAgent, etc.) |
| `CSVPath` | Cluster Shared Volume mount path |

---

## Examples

**All volumes:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DVolumeMap
```

**Capacity summary:**

```powershell
Get-S2DVolumeMap | Format-Table FriendlyName, ResiliencySettingName, ProvisioningType, Size, FootprintOnPool, EfficiencyPercent
```

**Thin volume risk assessment:**

```powershell
Get-S2DVolumeMap |
    Where-Object ProvisioningType -eq 'Thin' |
    Select-Object FriendlyName, Size, AllocatedSize, ThinGrowthHeadroom, MaxPotentialFootprint, OvercommitRatio
```

**Filter to specific volumes:**

```powershell
Get-S2DVolumeMap -VolumeName "UserStorage_1", "UserStorage_2"
```

**Show only user (non-infrastructure) volumes:**

```powershell
Get-S2DVolumeMap | Where-Object IsInfrastructureVolume -eq $false
```
