# Troubleshooting

Common issues and their fixes, organized by the command or feature where they surface.

---

## Connection Issues

### WinRM connection refused

**Symptom:** `Connect-S2DCluster` fails with `WSManFault` or `Connection refused`.

**Cause:** WinRM is not enabled on the cluster nodes, or the firewall blocks ports 5985/5986.

**Fix:**

```powershell
# Run on each cluster node (or via Group Policy)
Enable-PSRemoting -Force

# Verify WinRM is listening
Test-NetConnection -ComputerName "node01.contoso.com" -Port 5985
```

> [!NOTE]
> **Azure Local default state**
> WinRM is enabled by default on Azure Local nodes deployed through Azure Arc. If nodes were deployed via an older wizard-based method, WinRM may need to be enabled manually.
>
---

### RSAT cmdlets not found

**Symptom:** `Get-ClusterNode`, `Get-StoragePool`, or other storage cmdlets are missing.

**Cause:** The Failover Clustering and Storage RSAT features are not installed on your management machine.

**Fix:**

```powershell
# Windows 11 / Windows Server 2022 — management machine only
Add-WindowsCapability -Online -Name "Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0"
Add-WindowsCapability -Online -Name "Rsat.FileServices.Tools~~~~0.0.1.0"
```

> [!TIP]
> **Running on a cluster node**
> If you run S2DCartographer directly on a cluster node with `Connect-S2DCluster -Local`, no RSAT installation is needed — the cmdlets are already present on the node.
>
---

### Non-domain-joined: authentication fails with Kerberos error

**Symptom:** `Connect-S2DCluster` fails with `The credentials supplied to the package were not recognized`.

**Cause:** Kerberos cannot authenticate from a non-domain-joined machine.

**Fix:**

```powershell
# Enable NTLM fallback — run once on your management machine (elevated)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*.contoso.com" -Force

# Then connect with explicit FQDN
Connect-S2DCluster -ClusterName "c01-prd-bal.contoso.com" -Credential $cred
```

---

### "S2D is not enabled on this cluster" error

**Symptom:** `Connect-S2DCluster` exits with `S2D storage pool not found`.

**Cause:** Either S2D is not enabled, or the management CimSession landed on a node that doesn't host the pool.

**Fix:** Verify S2D is enabled on the target cluster:

```powershell
# Run on a cluster node
Get-StoragePool | Where-Object IsPrimordial -eq $false
```

If no pool is returned, S2D is either not enabled or the pool is offline.

---

## Report Generation

### Excel: `ImportExcel module not found`

**Symptom:** `New-S2DReport -Format Excel` fails with a module not found error.

**Cause:** The `ImportExcel` module is a separate dependency not installed by default.

**Fix:**

```powershell
Install-Module ImportExcel -Scope CurrentUser -Force
```

> [!WARNING]
> **Required for Excel only**
> `ImportExcel` is only needed for `-Format Excel` or `-Format All`. HTML, Word, and PDF reports have no additional dependencies.
>
---

### PDF: `No suitable browser found`

**Symptom:** `New-S2DReport -Format Pdf` warns "No browser found for headless print" and returns `$null`.

**Cause:** S2DCartographer uses headless Edge or Chrome to print HTML to PDF. Neither was found on the machine.

**Fix:** Ensure Microsoft Edge or Google Chrome is installed. Edge ships pre-installed on:

- Windows 11
- Windows Server 2022+
- Azure Local nodes

The browser search order is:

1. `msedge.exe` in standard Edge install paths
2. `chrome.exe` in standard Chrome install paths
3. `msedge` / `chrome` / `chromium-browser` on `$env:PATH`

> [!TIP]
> **Manual PDF from HTML**
> If no browser is available, generate the HTML report first and open it in a browser to print manually:
> ```powershell
> New-S2DReport -InputObject $data -Format Html -OutputDirectory "C:\Reports\"
> # Open the .html file in Edge/Chrome → Print → Save as PDF
> ```
>
---

### Word: `Unexpected token in Open XML`

**Symptom:** The generated `.docx` file opens with a repair prompt or shows garbled XML.

**Cause:** Usually caused by special characters (em-dashes, Unicode symbols) in cluster or volume names that weren't properly XML-escaped.

**Fix:** This is a bug — please [open an issue](https://github.com/AzureLocal/azurelocal-s2d-cartographer/issues/new?template=bug_report.yml) with the cluster name and affected volume names.

---

## Collector Issues

### `Get-S2DPhysicalDiskInventory` returns empty

**Symptom:** The command returns nothing, or returns only disks from one node.

**Cause:** The PS sessions to individual nodes timed out, or some nodes are unreachable.

**Fix:**

```powershell
# Check which nodes are reachable
$session = $Script:S2DSession  # only works inside the module; use -Verbose instead
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential $cred -Verbose
```

Look for `WARNING: Could not reach node` lines in the verbose output.

---

### `Get-S2DCapacityWaterfall` Stage 7 (Usable Capacity) is zero

**Symptom:** Stage 7 (Usable Capacity) shows 0 TiB.

**Cause:** No workload volumes were found — either all volumes are infrastructure volumes, or `Get-S2DVolumeMap` was not called before the waterfall.

**Fix:**

```powershell
# Check what volumes were found
Get-S2DVolumeMap | Format-Table FriendlyName, IsInfrastructureVolume, Size
```

If all volumes show `IsInfrastructureVolume = $true`, verify the cluster has workload CSV volumes created.

---

## Key Vault Issues

### `Get-AzKeyVaultSecret: Forbidden`

**Symptom:** Key Vault credential retrieval fails with a 403 Forbidden error.

**Cause:** The identity running the script (user account or Managed Identity) does not have `Get` permission on secrets in the Key Vault.

**Fix:** Grant the identity Key Vault Secrets User role (RBAC) or add a `Get` access policy (vault access policy model):

```powershell
# RBAC model
New-AzRoleAssignment -ObjectId <identity-object-id> `
    -RoleDefinitionName "Key Vault Secrets User" `
    -Scope "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/kv-prod"
```

---

## Diagnostics

### Enable verbose output

All S2DCartographer commands respect `-Verbose`:

```powershell
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential $cred -Verbose
Get-S2DPhysicalDiskInventory -Verbose
Get-S2DHealthStatus -Verbose
```

Verbose output shows CIM query timings, node connection status, cache hits, and any non-fatal anomalies detected during collection.

### Check the session state

```powershell
# View what's in the current session (from within a script or the module scope)
InModuleScope S2DCartographer { $Script:S2DSession | ConvertTo-Json -Depth 3 }
```
