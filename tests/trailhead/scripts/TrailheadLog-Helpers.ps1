<#
.SYNOPSIS
    Helper functions for writing entries to an active TRAILHEAD test run log.

.DESCRIPTION
    Dot-source this file after running Start-TrailheadRun.ps1:

        . .\tests\trailhead\scripts\TrailheadLog-Helpers.ps1

    Requires env vars set by Start-TrailheadRun.ps1:
        $env:TH_LOG_FILE      — path to the run log markdown file
        $env:TH_ISSUE_NUMBER  — GitHub issue number for live commentary
        $env:TH_RUN_ID        — run identifier
        $env:TH_REPO_ROOT     — repo root path

.FUNCTIONS
    Write-THPass  <CheckId> <Detail>       — Record a passing check
    Write-THFail  <CheckId> <Detail>       — Record a failing check
    Write-THFix   <CheckId> <Detail>       — Record the fix applied after a failure
    Write-THNote  <Detail>                 — Record a general observation or next-step
    Write-THSkip  <CheckId> <Reason>       — Record a skipped check with reason
    Write-THPhase <PhaseLabel>             — Record a phase boundary marker
    Close-THRun   -Passed N -Failed M      — Write summary and close the run
#>

Set-StrictMode -Version Latest

function Test-ThGuard {
    if (-not $env:TH_LOG_FILE) {
        throw "No active TRAILHEAD run. Run tests/trailhead/scripts/Start-TrailheadRun.ps1 first."
    }
}

function Add-ThLogEntry {
    param([string]$Line, [switch]$GitHubComment)
    Test-ThGuard
    Add-Content -Path $env:TH_LOG_FILE -Value $Line
    if ($GitHubComment -and $env:TH_ISSUE_NUMBER) {
        gh issue comment $env:TH_ISSUE_NUMBER --body $Line --repo "AzureLocal/azurelocal-s2d-cartographer" 2>$null | Out-Null
    }
}

function Write-THPhase {
    <#.SYNOPSIS Phase boundary marker — call at the start of each phase.#>
    param([Parameter(Mandatory)][string]$Label)
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "`n### $Label — started $ts`n"
    Add-ThLogEntry $line -GitHubComment
    Write-Host "`n▶  $Label" -ForegroundColor Cyan
}

function Write-THPass {
    <#.SYNOPSIS Record a passing check.#>
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$Detail
    )
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "- ``$ts`` ✅ **$CheckId** — $Detail"
    Add-ThLogEntry $line
    Write-Host "  ✅ $CheckId — $Detail" -ForegroundColor Green
}

function Write-THFail {
    <#.SYNOPSIS Record a failing check.#>
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$Detail
    )
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "- ``$ts`` ❌ **$CheckId** — $Detail"
    Add-ThLogEntry $line -GitHubComment
    Write-Host "  ❌ $CheckId — $Detail" -ForegroundColor Red
}

function Write-THFix {
    <#.SYNOPSIS Record the remediation applied after a failure.#>
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$Detail
    )
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "  - ``$ts`` 🔧 **FIX $CheckId** — $Detail"
    Add-ThLogEntry $line -GitHubComment
    Write-Host "    🔧 FIX $CheckId — $Detail" -ForegroundColor Yellow
}

function Write-THNote {
    <#.SYNOPSIS Record a general observation, context note, or next-step annotation.#>
    param([Parameter(Mandatory)][string]$Detail)
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "- ``$ts`` ℹ️  $Detail"
    Add-ThLogEntry $line
    Write-Host "  ℹ️  $Detail" -ForegroundColor DarkCyan
}

function Write-THSkip {
    <#.SYNOPSIS Record a check intentionally skipped with reason.#>
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][string]$Reason
    )
    Test-ThGuard
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "- ``$ts`` ⏭️  **$CheckId** — SKIPPED: $Reason"
    Add-ThLogEntry $line
    Write-Host "  ⏭️  $CheckId — SKIPPED: $Reason" -ForegroundColor DarkGray
}

function Close-THRun {
    <#.SYNOPSIS Write the run summary and close the log.#>
    param(
        [Parameter(Mandatory)][int]$Passed,
        [Parameter(Mandatory)][int]$Failed,
        [int]$Skipped = 0,
        [string]$Notes = ""
    )
    Test-ThGuard
    $ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $verdict = if ($Failed -eq 0) { "✅ ALL PASS" } else { "❌ $Failed FAILURE(S)" }

    $summary = @"

---

## Run Summary

| | |
|---|---|
| Closed | $ts |
| Passed | $Passed |
| Failed | $Failed |
| Skipped | $Skipped |
| Verdict | $verdict |

$Notes
"@
    Add-ThLogEntry $summary -GitHubComment

    if ($env:TH_ISSUE_NUMBER) {
        if ($Failed -eq 0) {
            gh issue close $env:TH_ISSUE_NUMBER --comment "Run complete — $verdict. Log committed to repo." --repo "AzureLocal/azurelocal-s2d-cartographer" 2>$null | Out-Null
            Write-Host "`n✅ Run closed. Issue #$($env:TH_ISSUE_NUMBER) closed." -ForegroundColor Green
        } else {
            Write-Host "`n⚠️  Run closed with failures. Issue #$($env:TH_ISSUE_NUMBER) left open." -ForegroundColor Yellow
        }
    }

    Write-Host "Log: $env:TH_LOG_FILE" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commit the log file:" -ForegroundColor Yellow
    $relPath = 'tests/trailhead/logs/' + (Split-Path $env:TH_LOG_FILE -Leaf)
    Write-Host "  cd '$env:TH_REPO_ROOT'" -ForegroundColor DarkGray
    Write-Host "  git add '$relPath'" -ForegroundColor DarkGray
    Write-Host "  git commit -m `"test(trailhead): run log $($env:TH_RUN_ID)`"" -ForegroundColor DarkGray
    Write-Host "  git push origin main" -ForegroundColor DarkGray

    Remove-Item Env:TH_LOG_FILE      -ErrorAction SilentlyContinue
    Remove-Item Env:TH_ISSUE_NUMBER  -ErrorAction SilentlyContinue
    Remove-Item Env:TH_RUN_ID        -ErrorAction SilentlyContinue
    Remove-Item Env:TH_REPO_ROOT     -ErrorAction SilentlyContinue
}

Write-Host "TRAILHEAD log helpers loaded." -ForegroundColor DarkCyan
Write-Host "  Write-THPhase / Write-THPass / Write-THFail / Write-THFix / Write-THNote / Write-THSkip / Close-THRun" -ForegroundColor DarkGray
