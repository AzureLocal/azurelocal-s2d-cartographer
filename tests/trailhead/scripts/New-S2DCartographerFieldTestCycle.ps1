<#
.SYNOPSIS
    Creates a new Operation TRAILHEAD field-testing cycle — milestone + 8 phase issues — in the
    AzureLocal/azurelocal-s2d-cartographer GitHub repository.

.DESCRIPTION
    Run this script to kick off a fresh field-testing cycle for a new S2DCartographer version.
    It creates:
      - One GitHub milestone  : "Operation TRAILHEAD — v<Version> Field Validation"
      - Eight phase issues     : P0 Preflight through P7 Regression/Sign-off
      - All issues are labelled and assigned to the milestone automatically.

    The GitHub CLI (gh) must be installed and authenticated before running.

.PARAMETER Version
    The module version being tested (e.g. "0.2.0").

.PARAMETER Environment
    Short human-readable description of the test environment (e.g. "clus01 (4-node example cluster)").

.PARAMETER DueDate
    Optional. ISO 8601 date (YYYY-MM-DD) for the milestone due date. Defaults to 30 days from today.

.PARAMETER WhatIf
    Print what would be created without actually calling the GitHub API.

.EXAMPLE
    .\New-S2DCartographerFieldTestCycle.ps1 -Version "0.2.0" -Environment "clus01 (4-node Dell)"

.NOTES
    Place this script in tests/trailhead/scripts/.
    See tests/trailhead/field-testing.md for the full testing methodology.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [Parameter(Mandatory)]
    [string]$Environment,

    [Parameter()]
    [string]$DueDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd"),

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Gh {
    param([string[]]$GhArgs)
    if ($WhatIf) {
        Write-Host "[WhatIf] gh $($GhArgs -join ' ')" -ForegroundColor Cyan
        return "0"
    }
    gh @GhArgs
    if ($LASTEXITCODE -ne 0) { throw "gh exited with code $LASTEXITCODE" }
}

$milestoneTitle = "Operation TRAILHEAD — v$Version Field Validation"
$labels         = @("type/infra", "priority/high", "solution/s2dcartographer")
$labelArgs      = $labels | ForEach-Object { "--label"; $_ }

Write-Host "`nOperation TRAILHEAD — v$Version" -ForegroundColor Green
Write-Host "Environment : $Environment"
Write-Host "Milestone   : $milestoneTitle"
Write-Host "Due         : $DueDate`n"

# ---------------------------------------------------------------------------
# 1. Milestone
# ---------------------------------------------------------------------------
Write-Host "Creating milestone..." -ForegroundColor Yellow
Invoke-Gh @("api", "repos/AzureLocal/azurelocal-s2d-cartographer/milestones",
    "--method", "POST",
    "--field", "title=$milestoneTitle",
    "--field", "due_on=${DueDate}T00:00:00Z",
    "--field", "description=Operation TRAILHEAD field-testing cycle for S2DCartographer v$Version. See tests/trailhead/field-testing.md for methodology."
) | Out-Null
Write-Host "  Milestone created." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Phase issue definitions
# ---------------------------------------------------------------------------
$phases = @(
    @{
        Title = "[TRAILHEAD P0] Preflight — execution environment and baseline validation"
        Body  = @"
## Operation TRAILHEAD — Phase 0: Preflight

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle

Confirm the execution environment is ready **before any live test touches infrastructure**.
All checks must pass before proceeding to Phase 1.

---

### Checklist

- [ ] P0.1 — PowerShell 7.0+ present: ``\$PSVersionTable.PSVersion``
- [ ] P0.2 — Module loads clean: ``Import-Module .\S2DCartographer.psd1 -Force`` — no errors, all functions exported
- [ ] P0.3 — Pester baseline: ``Invoke-Pester -Path .\tests -PassThru`` — all existing tests pass
- [ ] P0.4 — Az module present: ``Get-Module -ListAvailable Az.Accounts``
- [ ] P0.5 — FailoverClusters module present: ``Get-Module -ListAvailable FailoverClusters``
- [ ] P0.6 — Storage module present: ``Get-Module -ListAvailable Storage``
- [ ] P0.7 — ICMP reachable: all cluster nodes — no unexpected failures

---

**Pass gate:** All checks must pass before Phase 1.
"@
    },
    @{
        Title = "[TRAILHEAD P1] Authentication and credential resolution validation"
        Body  = @"
## Operation TRAILHEAD — Phase 1: Authentication & Credentials

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 0 passing

---

### Checklist

- [ ] P1.1 — ``Connect-S2DCluster -ClusterName`` with explicit credential resolves
- [ ] P1.2 — ``Connect-S2DCluster -Local`` succeeds when run from a cluster node
- [ ] P1.3 — ``Connect-S2DCluster`` validates S2D is enabled (``Get-ClusterS2D``)
- [ ] P1.4 — Node list populated after connect: ``\$Script:S2DSession.Nodes`` count matches expected
- [ ] P1.5 — ``Disconnect-S2DCluster`` cleanly tears down session
- [ ] P1.6 — Re-connect after disconnect completes without error
- [ ] P1.7 — No plaintext credentials in any committed file (grep check)

---

**Pass gate:** All auth paths used in Phase 2+ must pass.
"@
    },
    @{
        Title = "[TRAILHEAD P2] Connectivity and CIM session validation"
        Body  = @"
## Operation TRAILHEAD — Phase 2: Connectivity & CIM Sessions

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 1 passing

---

### Checklist

- [ ] P2.1 — CIM session established to cluster node
- [ ] P2.2 — ``Get-CimInstance -ClassName MSCluster_Cluster`` returns cluster name
- [ ] P2.3 — ``Get-ClusterNode`` returns all expected nodes
- [ ] P2.4 — ``Get-PhysicalDisk`` returns results via CIM session
- [ ] P2.5 — Per-node CIM sessions open to all nodes in cluster
- [ ] P2.6 — ``Resolve-S2DSession`` (private helper) returns correct session object
- [ ] P2.7 — Session state caching: second call to collector does not re-establish sessions

---

**Pass gate:** CIM connectivity to all nodes must be confirmed.
"@
    },
    @{
        Title = "[TRAILHEAD P3] Physical disk collector live tests"
        Body  = @"
## Operation TRAILHEAD — Phase 3: Physical Disk Collector Live Tests

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 2 passing

Run ``Get-S2DPhysicalDiskInventory`` against the live cluster and validate the output.

---

### Checklist

- [ ] P3.1 — Returns without terminating error
- [ ] P3.2 — Disk count per node is plausible (≥ 2 disks per node)
- [ ] P3.3 — Role classification correct: cache disks show ``Role = 'Cache'``, capacity disks show ``Role = 'Capacity'``
- [ ] P3.4 — ``MediaType`` populated (NVMe / SSD / HDD)
- [ ] P3.5 — ``Size`` returns an ``S2DCapacity`` object with TiB and TB values
- [ ] P3.6 — ``HealthStatus`` populated for all disks
- [ ] P3.7 — Disk symmetry check runs: warning issued if nodes have different disk counts
- [ ] P3.8 — Results cached in ``\$Script:S2DSession.CollectedData['PhysicalDisks']``
- [ ] P3.9 — ``WearPercentage`` populated for NVMe disks (may be null for HDD/SSD)

---

**Pass gate:** Collector returns without error; disk inventory shape is correct.
"@
    },
    @{
        Title = "[TRAILHEAD P4] Capacity math and unit conversion validation"
        Body  = @"
## Operation TRAILHEAD — Phase 4: Capacity Math & Unit Conversion

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 3 passing

Validate TiB/TB conversion accuracy and reserve calculation correctness against known cluster values.

---

### Checklist

- [ ] P4.1 — ``ConvertTo-S2DCapacity -TB 1.92`` returns ``TiB ≈ 1.747`` (within 0.01 tolerance)
- [ ] P4.2 — ``ConvertTo-S2DCapacity -TB 3.84`` returns ``TiB ≈ 3.493``
- [ ] P4.3 — ``ConvertTo-S2DCapacity -TB 7.68`` returns ``TiB ≈ 6.986``
- [ ] P4.4 — ``ConvertTo-S2DCapacity -TB 15.36`` returns ``TiB ≈ 13.97``
- [ ] P4.5 — ``Display`` property shows dual-unit format: ``"X.XX TiB (X.XX TB)"``
- [ ] P4.6 — Reserve calculation: ``min(NodeCount, 4) × LargestCapacityDrive`` is correct for this cluster
- [ ] P4.7 — Reserve status returned: Adequate / Warning / Critical
- [ ] P4.8 — Resiliency efficiency: 3-way mirror = 33.3%, 2-way = 50%
- [ ] P4.9 — Cross-check raw capacity against vendor spec for this cluster

---

**Pass gate:** All conversion checks pass within tolerance; reserve math matches manual calculation.
"@
    },
    @{
        Title = "[TRAILHEAD P5] Output generation validation"
        Body  = @"
## Operation TRAILHEAD — Phase 5: Output Generation

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 4 passing

Validate that output artifacts are generated correctly. (Phase 3+ output formats only for Phase 1.)

---

### Checklist

- [ ] P5.1 — Console output of ``Get-S2DPhysicalDiskInventory | Format-Table`` renders cleanly
- [ ] P5.2 — ``S2DCapacity`` objects display correctly in ``Format-List``
- [ ] P5.3 — No ``WriteError`` or ``WriteWarning`` written unexpectedly
- [ ] P5.4 — Pipeline: ``Get-S2DPhysicalDiskInventory | Where-Object Role -eq 'Capacity'`` filters correctly

---

**Pass gate:** All console output renders correctly.
"@
    },
    @{
        Title = "[TRAILHEAD P6] End-to-end scenario tests"
        Body  = @"
## Operation TRAILHEAD — Phase 6: End-to-End Scenarios

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phase 5 passing

Run complete end-to-end scenarios and record outcomes.

---

### Scenarios

- [ ] P6.1 — Connect → Get-S2DPhysicalDiskInventory → Disconnect completes without error
- [ ] P6.2 — Connect → ConvertTo-S2DCapacity pipeline from disk sizes → Disconnect
- [ ] P6.3 — Run while already connected: duplicate Connect-S2DCluster gives appropriate warning
- [ ] P6.4 — Run without connecting first: all collectors throw helpful error
- [ ] P6.5 — WinRM timeout scenario: reasonable error message returned (simulate with invalid node)

---

**Pass gate:** All scenarios reach a recorded outcome (pass, expected warning, or known limitation filed as issue).
"@
    },
    @{
        Title = "[TRAILHEAD P7] Regression and sign-off"
        Body  = @"
## Operation TRAILHEAD — Phase 7: Regression & Sign-off

**Version:** $Version
**Environment:** $Environment
**Milestone:** $milestoneTitle
**Depends on:** Phases 0-6 complete

---

### Checklist

- [ ] P7.1 — ``Invoke-Pester -Path .\tests -Output Detailed`` — all unit tests pass on execution host
- [ ] P7.2 — No new issues opened since P0 that are unresolved or un-waived
- [ ] P7.3 — TRAILHEAD run log committed to ``tests/trailhead/logs/``
- [ ] P7.4 — CHANGELOG.md updated with findings if any bugs were fixed during the cycle
- [ ] P7.5 — Release milestone closed after this gate issue is closed

---

**Pass gate:** All regression tests pass; no unresolved issues; run log committed.
"@
    }
)

# ---------------------------------------------------------------------------
# 3. Create issues and assign to milestone
# ---------------------------------------------------------------------------
$null = Invoke-Gh @("api", "repos/AzureLocal/azurelocal-s2d-cartographer/milestones",
    "--jq", ".[] | select(.title == `"$milestoneTitle`") | .number"
) 2>$null

Write-Host "`nCreating phase issues..." -ForegroundColor Yellow

foreach ($phase in $phases) {
    $body = $phase.Body
    Write-Host "  Creating: $($phase.Title)" -ForegroundColor Gray
    Invoke-Gh @(
        "issue", "create",
        "--repo", "AzureLocal/azurelocal-s2d-cartographer",
        "--title", $phase.Title,
        "--body", $body
    ) + $labelArgs | Out-Null
}

Write-Host "`nDone. Assign the issues to milestone '$milestoneTitle' in GitHub." -ForegroundColor Green
Write-Host "Use: gh issue list --repo AzureLocal/azurelocal-s2d-cartographer --label 'type/infra'" -ForegroundColor DarkGray
