# Invoke-S2DCartographer

Full orchestrated S2D analysis run: connect, collect, analyze, and report.

---

## Synopsis

Runs the complete S2DCartographer pipeline in a single call:

1. Connect to the cluster (`Connect-S2DCluster`)
2. Collect all data — physical disks, pool, volumes, cache tier
3. Compute the 7-stage capacity waterfall
4. Run all 11 health checks
5. Generate requested report formats (HTML, Word, PDF, Excel, JSON, CSV)
6. Generate SVG diagrams (if `-IncludeDiagrams`)
7. Disconnect from the cluster

Output files are written to a per-run subfolder:

```text
<OutputDirectory>\<ClusterName>\<yyyyMMdd-HHmm>\
```

A session log is written to the same folder capturing each collection step, warnings, and final output paths.

---

## Syntax

**By cluster name (domain credential):**

```powershell
Invoke-S2DCartographer
    -ClusterName <string>
    [-Credential <PSCredential>]
    [-Authentication <string>]
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-IncludeNonPoolDisks]
    [-IncludeDiagrams]
    [-PrimaryUnit <string>]
    [-SkipHealthChecks]
    [-Author <string>]
    [-Company <string>]
    [-PassThru]
```

**By cluster name (Azure Key Vault credential):**

```powershell
Invoke-S2DCartographer
    -ClusterName <string>
    -KeyVaultName <string>
    -SecretName <string>
    [-Username <string>]
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-IncludeNonPoolDisks]
    [-IncludeDiagrams]
    [-PrimaryUnit <string>]
    [-SkipHealthChecks]
    [-Author <string>]
    [-Company <string>]
    [-PassThru]
```

**By existing CimSession:**

```powershell
Invoke-S2DCartographer
    -CimSession <CimSession>
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-IncludeNonPoolDisks]
    [-IncludeDiagrams]
    [-PrimaryUnit <string>]
    [-SkipHealthChecks]
    [-Author <string>]
    [-Company <string>]
    [-PassThru]
```

**Local (run from a cluster node):**

```powershell
Invoke-S2DCartographer
    -Local
    [-OutputDirectory <string>]
    [-Format <string[]>]
    [-IncludeNonPoolDisks]
    [-IncludeDiagrams]
    [-PrimaryUnit <string>]
    [-SkipHealthChecks]
    [-Author <string>]
    [-Company <string>]
    [-PassThru]
```

---

## Parameters

### `-ClusterName`

| | |
|---|---|
| Type | `string` |
| Required | No (unless connecting by name) |
| Default | — |

DNS name or FQDN of the Failover Cluster. Examples: `clus01` or `clus01.contoso.com`. Not required when `-CimSession` or `-Local` is used.

---

### `-Credential`

| | |
|---|---|
| Type | `PSCredential` |
| Required | No |
| Default | — |

PSCredential to authenticate with. Prompted interactively if not supplied and the cluster requires credentials. Mutually exclusive with `-KeyVaultName`.

---

### `-Authentication`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `Negotiate` |
| Valid values | `Default`, `Digest`, `Negotiate`, `Basic`, `Kerberos`, `ClientCertificate`, `CredSsp` |

Authentication method passed through to `Connect-S2DCluster` and `New-CimSession`. `Negotiate` auto-selects NTLM or Kerberos and works in both domain-joined and workgroup/lab environments. Use `Kerberos` to enforce Kerberos explicitly.

---

### `-CimSession`

| | |
|---|---|
| Type | `CimSession` |
| Required | No |
| Default | — |

Re-use an existing `CimSession` instead of creating a new one. Skips `Connect-S2DCluster`.

---

### `-Local`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Run against the local machine. Use when executing directly on a cluster node — eliminates the need for WinRM remoting.

---

### `-KeyVaultName`

| | |
|---|---|
| Type | `string` |
| Required | No (required with `-SecretName`) |
| Default | — |

Azure Key Vault name to retrieve credentials from. Requires the `Az.KeyVault` module to be installed and the caller authenticated to Azure (`Connect-AzAccount`).

---

### `-SecretName`

| | |
|---|---|
| Type | `string` |
| Required | No (required with `-KeyVaultName`) |
| Default | — |

Name of the Key Vault secret containing the cluster password. The username is read from the secret's `ContentType` tag by convention (`domain\user`). Use `-Username` if the tag is not populated.

---

### `-Username`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | — |

Explicit username to pair with the Key Vault secret password. Use when the secret does not have a `ContentType` tag set. Example: `MGMT\svc.azl.local`.

---

### `-OutputDirectory`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `C:\S2DCartographer` |

Root folder for all output files. A per-run subfolder `<ClusterName>\<yyyyMMdd-HHmm>\` is created automatically. The root folder is created if it does not exist.

---

### `-Format`

| | |
|---|---|
| Type | `string[]` |
| Required | No |
| Default | `All` |
| Valid values | `Html`, `Word`, `Pdf`, `Excel`, `Json`, `Csv`, `All` |

Report formats to generate. `All` produces HTML + Word + PDF + Excel + JSON. `Csv` is always opt-in because it writes multiple files per run (one per collector table). Multiple values are accepted: `-Format Html, Json`.

---

### `-IncludeNonPoolDisks`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Include non-pool disks (boot drives, SAN LUNs, OS drives) in the Physical Disk Inventory report tables. By default only storage-pool members are shown in reports. This switch does **not** affect JSON or CSV outputs, which always include every disk with an `IsPoolMember` flag.

---

### `-IncludeDiagrams`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Also generate all six SVG diagram types alongside the reports. Equivalent to running `New-S2DDiagram -DiagramType All` on the collected data.

---

### `-PrimaryUnit`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `TiB` |
| Valid values | `TiB`, `TB` |

Preferred capacity display unit in report output. Both units are always shown in parentheses; this controls which is presented first and used for axis labels.

---

### `-SkipHealthChecks`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Skip the health check phase. Useful for fast capacity-only snapshots where the full 11-check evaluation is not needed.

---

### `-Author`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | empty |

Author name embedded in the report header of HTML, Word, and PDF outputs.

---

### `-Company`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | empty |

Company or organization name embedded in the report header.

---

### `-PassThru`

| | |
|---|---|
| Type | `switch` |
| Required | No |
| Default | off |

Return the `S2DClusterData` object to the pipeline in addition to writing files. Use this to pipe the collected data into `New-S2DReport`, `New-S2DDiagram`, or `Invoke-S2DCapacityWhatIf`.

---

## Outputs

`string[]` — paths to all generated report files (default).

`S2DClusterData` — full collected data object when `-PassThru` is set.

---

## Examples

**Simplest run — all formats, Key Vault credentials:**

```powershell
Invoke-S2DCartographer -ClusterName clus01.contoso.com `
    -KeyVaultName kv-contoso-platform -SecretName lcm-deployment-password
```

**Explicit username (when Key Vault secret has no ContentType tag):**

```powershell
Invoke-S2DCartographer -ClusterName clus01.contoso.com `
    -KeyVaultName kv-contoso-platform -SecretName lcm-deployment-password `
    -Username 'MGMT\svc.azl.local'
```

**Domain credential, specific formats, include diagrams:**

```powershell
$cred = Get-Credential
Invoke-S2DCartographer -ClusterName c01-prd-bal `
    -Credential $cred `
    -Format Html, Json `
    -IncludeDiagrams `
    -Author "Alex Admin" -Company "Contoso"
```

**Run locally from a cluster node:**

```powershell
Invoke-S2DCartographer -Local -OutputDirectory D:\Reports
```

**Capture data for further processing:**

```powershell
$data = Invoke-S2DCartographer -ClusterName clus01 -PassThru -SkipHealthChecks
$data | Invoke-S2DCapacityWhatIf -AddNodes 2 -AddDisksPerNode 4 -NewDiskSizeTB 3.84
```
