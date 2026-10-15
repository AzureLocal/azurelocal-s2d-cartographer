<#
.SYNOPSIS
    Initialises a new Operation TRAILHEAD test run for S2DCartographer.

.DESCRIPTION
    Creates two artefacts for a test run:
        1. A date-stamped Markdown run log under tests/trailhead/logs/
        2. A GitHub issue that acts as a live commentary feed for the run

    After calling this script, dot-source the companion helper to get Write-TH*
    logging functions in your session:

        . .\tests\trailhead\scripts\TrailheadLog-Helpers.ps1

    Then use:
        Write-THPass   "P0.1" "PowerShell 7.6.0"
        Write-THFail   "P0.7" "ICMP to node03 timed out"
        Write-THFix    "P0.7" "Confirmed node03 online; was a transient timeout — retry passed"
        Write-THNote   "Starting P1 — auth checks"
        Write-THSkip   "P1.2" "Local mode only for this run — skipping KV path"

    At the end of a session, call:
        Close-THRun -Passed $n -Failed $m

.PARAMETER Version
    S2DCartographer version under test (default: read from S2DCartographer.psd1).

.PARAMETER Environment
    Target environment label (default: example-env).

.PARAMETER Phase
    Which phase to start at (0–7). Purely informational in the log header.

.PARAMETER RepoRoot
    Path to the azurelocal-s2d-cartographer repo root.

.EXAMPLE
    .\tests\trailhead\scripts\Start-TrailheadRun.ps1
    .\tests\trailhead\scripts\Start-TrailheadRun.ps1 -Version "0.2.0" -Phase 0
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Environment = "example-env",
    [ValidateRange(0,7)]
    [int]$Phase = 0,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ──────────────────────────────────────────────────────────────
if (-not $RepoRoot) {
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..') | Select-Object -ExpandProperty Path
}
$logsDir   = Join-Path $RepoRoot "tests\trailhead\logs"
$helpersPs = Join-Path $RepoRoot "tests\trailhead\scripts\TrailheadLog-Helpers.ps1"

# ── Resolve version if not supplied ───────────────────────────────────────────
if (-not $Version) {
    $psdPath = Join-Path $RepoRoot "S2DCartographer.psd1"
    if (Test-Path $psdPath) {
        $psdContent = Get-Content $psdPath -Raw
        if ($psdContent -match "ModuleVersion\s*=\s*'([^']+)'") {
            $Version = $Matches[1]
        }
    }
    if (-not $Version) { $Version = "unknown" }
}

# ── Generate run ID ───────────────────────────────────────────────────────────
$runStamp = Get-Date -Format "yyyyMMdd-HHmm"
$runId    = "TRAILHEAD-$runStamp"
$logFile  = Join-Path $logsDir "run-$runStamp.md"

# ── Build log file ────────────────────────────────────────────────────────────
$tzOffset  = [System.TimeZoneInfo]::Local.BaseUtcOffset
$tzString  = "UTC{0:+00;-00}:{1:00}" -f $tzOffset.Hours, [Math]::Abs($tzOffset.Minutes)
$startedAt = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $tzString"

$header = @"
# Operation TRAILHEAD — Run Log

| Field | Value |
|---|---|
| Run ID | ``$runId`` |
| Version | v$Version |
| Environment | $Environment |
| Starting Phase | P$Phase |
| Tester | $(whoami) |
| Started | $startedAt |
| Log file | ``tests/trailhead/logs/run-$runStamp.md`` |

---

## Legend

| Mark | Meaning |
|---|---|
| ✅ PASS | Check passed — no action required |
| ❌ FAIL | Check failed — see Fix entry |
| 🔧 FIX | Remediation applied after a failure |
| ℹ️ NOTE | Context, observation, or next-step annotation |
| ⏭️ SKIP | Check intentionally skipped — reason noted |

---

## Run Entries

"@

New-Item -ItemType File -Path $logFile -Value $header -Force | Out-Null
Write-Host "✅ Log file created: $logFile" -ForegroundColor Green

# ── Create GitHub run-log issue ───────────────────────────────────────────────
$issueBody = @"
## Operation TRAILHEAD — Live Run Log

| Field | Value |
|---|---|
| Run ID | ``$runId`` |
| Version | v$Version |
| Environment | $Environment |
| Starting Phase | P$Phase |
| Log file | ``tests/trailhead/logs/run-$runStamp.md`` |

This issue is the live commentary feed for this test run.
Results are also written to the log file above, which will be committed at end of session.

---

_Run started: $(Get-Date -Format "yyyy-MM-dd HH:mm") — entries follow as comments_
"@

Write-Host "Creating GitHub run-log issue..." -ForegroundColor Cyan
$issueUrl = gh issue create `
    --title "[TRAILHEAD RUN] $runId — v$Version on $Environment" `
    --body $issueBody `
    --label "type/infra" `
    --label "solution/s2dcartographer" `
    --repo "AzureLocal/azurelocal-s2d-cartographer" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Run-log issue: $issueUrl" -ForegroundColor Green
    $issueNumber = ($issueUrl -split '/')[-1]
} else {
    Write-Warning "Could not create GitHub issue — run will log to file only."
    $issueNumber = $null
}

# ── Write env vars for helpers ────────────────────────────────────────────────
$env:TH_LOG_FILE      = $logFile
$env:TH_ISSUE_NUMBER  = $issueNumber
$env:TH_RUN_ID        = $runId
$env:TH_REPO_ROOT     = $RepoRoot

Write-Host ""
Write-Host "──────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host " Run ID  : $runId" -ForegroundColor White
Write-Host " Log     : $logFile" -ForegroundColor White
if ($issueNumber) {
Write-Host " Issue   : $issueUrl" -ForegroundColor White
}
Write-Host "──────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Next: dot-source the helpers into your session:" -ForegroundColor Yellow
Write-Host "  . '$helpersPs'" -ForegroundColor Cyan
Write-Host ""
