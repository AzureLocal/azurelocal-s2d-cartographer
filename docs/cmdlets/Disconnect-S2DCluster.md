# Disconnect-S2DCluster

Disconnects from the active S2D cluster session and releases resources.

---

## Synopsis

Closes the CimSession or PSSession stored by `Connect-S2DCluster` and clears all module-scope session state. Call this when you are done collecting data to cleanly release WinRM resources on the cluster nodes.

This cmdlet has no parameters.

---

## Syntax

```powershell
Disconnect-S2DCluster
```

---

## Outputs

None.

---

## Examples

**Basic disconnect:**

```powershell
Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential (Get-Credential)
# ... run collectors ...
Disconnect-S2DCluster
```

**In a try/finally block:**

```powershell
try {
    Connect-S2DCluster -ClusterName "c01-prd-bal" -Credential $cred
    $data = Invoke-S2DCartographer -PassThru
}
finally {
    Disconnect-S2DCluster
}
```

> [!NOTE]
> `Invoke-S2DCartographer` calls `Disconnect-S2DCluster` automatically at the end of its pipeline. You only need to call this directly when using the individual collector cmdlets manually.
