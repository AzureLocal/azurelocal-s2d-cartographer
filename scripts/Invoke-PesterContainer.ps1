#Requires -Version 7.0
#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}
<#
.SYNOPSIS
    Runs one Pester test container in the current process and exits non-zero on any failure.
.PARAMETER Path
    Path to a *.Tests.ps1 file or a folder.
.PARAMETER ResultPath
    Optional NUnit XML result file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [string] $ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cfg = New-PesterConfiguration
$cfg.Run.Path = $Path
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'Minimal'
if ($ResultPath) {
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputPath = $ResultPath
}
$r = Invoke-Pester -Configuration $cfg
Write-Host "RESULT $Path passed=$($r.PassedCount) failed=$($r.FailedCount) skipped=$($r.SkippedCount)"
if ($r.FailedCount -gt 0 -or $r.Result -eq 'Failed') { exit 1 }
exit 0
