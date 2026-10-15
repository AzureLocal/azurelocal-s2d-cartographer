# Connect-S2DCluster

Establishes an authenticated session to an S2D-enabled Failover Cluster.

---

## Synopsis

Creates and stores a module-scoped session used by all other S2DCartographer cmdlets. After connecting, you do not need to pass credentials to each collector.

The cmdlet validates that the target has S2D enabled via `Get-ClusterS2D` before storing the session.

Supports five connection methods:

1. **ClusterName + Credential** — WinRM/CIM to a cluster node
2. **CimSession** — re-use an existing CimSession
3. **PSSession** — re-use an existing PSSession
4. **Local** — run directly on a cluster node (no remoting)
5. **ClusterName + KeyVaultName** — retrieve credentials from Azure Key Vault

---

## Syntax

**By cluster name:**

```powershell
Connect-S2DCluster
    [-ClusterName] <string>
    [-Credential <PSCredential>]
    [-Authentication <string>]
```

**By cluster name with Key Vault:**

```powershell
Connect-S2DCluster
    [-ClusterName] <string>
    -KeyVaultName <string>
    -SecretName <string>
    [-Username <string>]
```

**By existing CimSession:**

```powershell
Connect-S2DCluster
    -CimSession <CimSession>
```

**By existing PSSession:**

```powershell
Connect-S2DCluster
    -PSSession <PSSession>
```

**Local execution:**

```powershell
Connect-S2DCluster
    -Local
```

---

## Parameters

### `-ClusterName`

| | |
|---|---|
| Type | `string` |
| Required | Yes (ByName and ByKeyVault parameter sets) |
| Position | 0 |
| Default | — |

DNS name or FQDN of the Failover Cluster. Examples: `c01-prd-bal` or `c01-prd-bal.corp.local`.

---

### `-Credential`

| | |
|---|---|
| Type | `PSCredential` |
| Required | No |
| Default | — |

PSCredential for cluster authentication. Prompted interactively if not supplied.

---

### `-Authentication`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | `Negotiate` |
| Valid values | `Default`, `Digest`, `Negotiate`, `Basic`, `Kerberos`, `ClientCertificate`, `CredSsp` |

Authentication method passed to `New-CimSession`. `Negotiate` auto-selects NTLM or Kerberos and works in both domain-joined and workgroup/lab environments. Use `Kerberos` to enforce Kerberos explicitly.

---

### `-CimSession`

| | |
|---|---|
| Type | `CimSession` |
| Required | Yes (ByCimSession parameter set) |
| Default | — |

An existing `CimSession` to use instead of creating a new one.

---

### `-PSSession`

| | |
|---|---|
| Type | `PSSession` |
| Required | Yes (ByPSSession parameter set) |
| Default | — |

An existing `PSSession` to use instead of creating a new one.

---

### `-Local`

| | |
|---|---|
| Type | `switch` |
| Required | Yes (Local parameter set) |
| Default | off |

Run against the local machine. Use when executing directly on a cluster node.

---

### `-KeyVaultName`

| | |
|---|---|
| Type | `string` |
| Required | Yes (ByKeyVault parameter set) |
| Default | — |

Azure Key Vault name to retrieve credentials from. Requires `Az.KeyVault` and an active `Connect-AzAccount` session.

---

### `-SecretName`

| | |
|---|---|
| Type | `string` |
| Required | Yes (ByKeyVault parameter set) |
| Default | — |

Name of the Key Vault secret containing the cluster password. The username is read from the secret's `ContentType` tag by convention (`domain\user`).

---

### `-Username`

| | |
|---|---|
| Type | `string` |
| Required | No |
| Default | — |

Explicit username to pair with the Key Vault secret password. Use when the secret's `ContentType` tag is not set. Example: `MGMT\svc.azl.local`.

---

## Outputs

None. The session is stored module-scope and consumed by all subsequent cmdlets.

---

## Examples

**Domain credential:**

```powershell
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)
```

**Non-domain or cross-domain client (force Negotiate to avoid Kerberos failure):**

```powershell
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential) -Authentication Negotiate
```

**Re-use an existing CimSession:**

```powershell
$cim = New-CimSession -ComputerName "node01" -Credential $cred
Connect-S2DCluster -CimSession $cim
```

**Run locally on a cluster node:**

```powershell
Connect-S2DCluster -Local
```

**Azure Key Vault credentials:**

```powershell
Connect-S2DCluster -ClusterName "clus01" -KeyVaultName "kv-contoso-platform" -SecretName "lcm-deployment-password"
```

**Key Vault with explicit username (no ContentType tag):**

```powershell
Connect-S2DCluster -ClusterName "clus01" `
    -KeyVaultName "kv-contoso-platform" `
    -SecretName "lcm-deployment-password" `
    -Username "MGMT\svc.azl.local"
```
