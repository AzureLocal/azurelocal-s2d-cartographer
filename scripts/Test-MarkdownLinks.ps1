#Requires -Version 7.0
<#
.SYNOPSIS
    Checks relative links in Markdown files. No network access.
.DESCRIPTION
    Finds [text](target) links and reference-style definitions, ignores http(s), mailto and pure
    anchors, and verifies that the target file or directory exists. Anchors are not validated.
.PARAMETER Root
    Repository root. Defaults to the parent of this script's folder.
.PARAMETER Exclude
    Path fragments to skip (default: .git, node_modules, archive, docs/public, repo-management).
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string[]] $Exclude = @('.git', 'node_modules', 'archive', 'docs/public', 'repo-management')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path
$files = Get-ChildItem -Path $Root -Recurse -File -Filter '*.md' | Where-Object {
    $rel = $_.FullName.Substring($Root.Length + 1).Replace([string][char]92, '/')
    $skip = $false
    foreach ($x in $Exclude) { if ($rel -eq $x -or $rel.StartsWith("$x/") -or $rel.Contains("/$x/")) { $skip = $true } }
    -not $skip
}

$broken = [System.Collections.Generic.List[string]]::new()
$checked = 0
foreach ($f in $files) {
    $inFence = $false
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
        $lineNo++
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        $clean = [regex]::Replace($line, '`[^`]*`', '')
        $targets = @([regex]::Matches($clean, '\]\(([^)\s]+)(?:\s+"[^"]*")?\)') | ForEach-Object { $_.Groups[1].Value })
        $targets += [regex]::Matches($clean, '^\s*\[[^\]]+\]:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value }
        foreach ($t in $targets) {
            if ($t -match '^(https?:|mailto:|#|\{|<|data:)') { continue }
            $path = ($t -split '[#?]')[0]
            if (-not $path) { continue }
            $path = [uri]::UnescapeDataString($path)
            $base = if ($path.StartsWith('/')) { $Root } else { $f.DirectoryName }
            $full = Join-Path $base $path.TrimStart('/')
            $checked++
            if (-not (Test-Path -LiteralPath $full)) {
                $broken.Add(('{0}:{1} -> {2}' -f ($f.FullName.Substring($Root.Length + 1)), $lineNo, $t))
            }
        }
    }
}
Write-Host "Checked $checked relative links in $(@($files).Count) Markdown files; $($broken.Count) broken."
$broken | ForEach-Object { Write-Host "  BROKEN $_" }
if ($broken.Count -gt 0) { exit 1 }
