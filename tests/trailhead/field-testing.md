# Field Testing Methodology — Operation TRAILHEAD

This document describes the S2DCartographer field-testing methodology. A field-testing cycle is run
against a **real Azure Local or Windows Server S2D cluster** before any significant release to validate
that live data collection, credential resolution, connectivity, capacity math, and output generation all
work against actual infrastructure — not just fixture data.

## Codename

Each field-testing cycle uses the codename **Operation TRAILHEAD**.

> Every test cycle starts at the trailhead — the point where real infrastructure begins.

This name is the standard across all AzureLocal repos. TRAILHEAD is live. MAPROOM is offline.

## When to Run a Cycle

- Before every minor or major release (v0.x.0, v1.0.0, etc.)
- After significant changes to collectors, credential resolution, or output generation
- When validating S2DCartographer against a new cluster configuration for the first time

## Milestone Exit Policy

Every delivery milestone should have a corresponding **TRAILHEAD gate issue** before the milestone is closed.

- Create the issue from `.github/ISSUE_TEMPLATE/trailhead_milestone_gate.md`.
- Run `Invoke-Pester -Path .\tests` for the baseline regression check.
- Run a full P0-P7 cycle for milestones that affect live discovery, authentication, execution, rendering, or release automation.
- For narrower milestones, execute only the impacted TRAILHEAD phases and document any waived phases in the gate issue.
- Do not close the release milestone until the gate issue is closed or explicitly waived.

## What is NOT Tested

| Excluded | Reason |
|----------|--------|
| Azure Monitor integration | Future feature (Phase 6) |
| OEM BMC/iDRAC queries | Future feature (Phase 6) |
| Historical trending | Future feature (Phase 6) |

## Starting a New Cycle

Use the `New-S2DCartographerFieldTestCycle.ps1` script to create a GitHub milestone and all 8 phase issues:

```powershell
cd E:\git\azurelocal-s2d-cartographer
.\tests\trailhead\scripts\New-S2DCartographerFieldTestCycle.ps1 `
    -Version "0.2.0" `
    -Environment "clus01 (4-node example cluster)" `
    -DueDate "2026-06-30"
```

Use `-WhatIf` to preview without touching GitHub.

## Phase Summary

| Phase | Name | Gate |
|-------|------|------|
| P0 | Preflight | All environment checks pass |
| P1 | Authentication & Credentials | KV resolution + cluster auth |
| P2 | Connectivity & Remote Execution | WinRM, CIM sessions |
| P3 | Individual Collector Live Tests | All Phase 1 collectors run without terminating error |
| P4 | Data Quality & Accuracy | Collected data cross-validated against known cluster values |
| P5 | Capacity Math Validation | Waterfall stages validated against manual calculations |
| P6 | Output Generation | All output artifacts generated and valid |
| P7 | Regression & Sign-off | Pester baseline holds; milestone closed |

## Test Environment Requirements

The execution host must have:

- PowerShell 7.0+
- Network line-of-sight to cluster nodes (WinRM 5985)
- Domain join or credential with cluster admin rights
- Az PowerShell module (for Key Vault path)

## IIC Canonical Data Standard

All **Pester unit and integration tests** use the IIC (Infinite Improbability Corp) fictional company
as test data. Do not use real environment names (real cluster names, customer names) in Pester tests.

Field testing (TRAILHEAD) uses **real environment data** and is never committed to the repository.

## Recording Results

Each phase issue contains a markdown checklist. As tests are executed:

1. Check off passing items in the issue checklist
2. For any failure, open a new bug issue and link it to the phase issue
3. For any waived test, add a comment explaining the reason
