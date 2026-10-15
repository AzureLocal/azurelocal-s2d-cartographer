# Get-S2DHealthStatus

Runs all S2D health checks and returns pass/warn/fail results with severity.

---

## Synopsis

Executes 11 health checks covering reserve adequacy, disk symmetry, volume health, disk health, NVMe wear, thin overcommit, firmware consistency, rebuild capacity, infrastructure volume presence, cache tier health, and thin provisioning reserve risk.

Uses already-collected data from the session cache where available. Run the collector cmdlets first for best results, or they will be invoked automatically.

Requires an active session from `Connect-S2DCluster`.

---

## Syntax

```powershell
Get-S2DHealthStatus
    [-CheckName <string[]>]
```

---

## Parameters

### `-CheckName`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | all checks |

Limit execution to one or more specific check names. See the table below for valid names.

---

## Health Checks

| Check Name | Severity | What it tests |
|---|---|---|
| `ReserveAdequacy` | Critical | Rebuild reserve ≥ one drive per node (up to 4 nodes) |
| `DiskSymmetry` | Warning | All nodes have identical disk count and media types |
| `VolumeHealth` | Critical | No volumes in Warning or Unhealthy state |
| `DiskHealth` | Critical | No pool-member disks in Warning or Unhealthy state |
| `NVMeWear` | Warning (>75%), Critical (>90%) | NVMe/SSD drive wear percentage |
| `ThinOvercommit` | Warning (>80%), Critical (>100%) | Thin-provisioned logical size vs pool total |
| `FirmwareConsistency` | Warning | All disks of the same model run the same firmware version |
| `RebuildCapacity` | Critical | Largest per-node disk total ≤ pool free space (enough room to rebuild if a node fails) |
| `InfraVolumePresent` | Warning | Expected Azure Local infrastructure volumes are present |
| `CacheTierHealth` | Critical | Cache tier is healthy with no missing or failed cache disks |
| `ThinReserveRisk` | Warning | Uncommitted thin growth headroom vs rebuild reserve |

---

## Outputs

`S2DHealthCheck[]` — one object per check.

Properties per check:

| Property | Description |
|---|---|
| `CheckName` | Name of the health check |
| `Severity` | `Warning` or `Critical` (maximum severity if the check fails) |
| `Status` | `Pass`, `Warn`, or `Fail` |
| `Details` | Human-readable description of the result |
| `Remediation` | Recommended action when status is not `Pass` |

---

## Examples

**Run all checks:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -Credential $cred
Get-S2DHealthStatus
```

**Show only non-passing checks:**

```powershell
Get-S2DHealthStatus | Where-Object Status -ne 'Pass' | Format-List
```

**Run a single check:**

```powershell
Get-S2DHealthStatus -CheckName RebuildCapacity
```

**Run a subset of checks:**

```powershell
Get-S2DHealthStatus -CheckName DiskHealth, NVMeWear, ThinOvercommit
```

**Check overall health in a script:**

```powershell
$checks = Get-S2DHealthStatus
$critical = $checks | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Critical' }
if ($critical) {
    Write-Error "CRITICAL health issues: $($critical.CheckName -join ', ')"
}
```
