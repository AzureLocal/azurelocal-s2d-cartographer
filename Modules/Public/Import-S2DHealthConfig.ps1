#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-S2DHealthConfig {
    <#
    .SYNOPSIS
        Loads an external health-check configuration to override the default scoring behaviour.

    .DESCRIPTION
        Validates and activates a user-supplied health-checks.json file. The loaded config
        overrides the defaults for all subsequent Get-S2DHealthStatus calls in the current
        PowerShell session. The override is in-memory only — it does not modify the shipped
        config/health-checks.json inside the module installation.

        Use -Validate to dry-run schema validation without activating the config.
        Use -Default to reset to the shipped defaults (clear any active override).

    .PARAMETER Path
        Path to the health-checks.json file to load and activate.

    .PARAMETER Validate
        Schema-check the file without activating it. Returns a result object.

    .PARAMETER Default
        Reset to the shipped default config. Clears any active in-memory override.

    .EXAMPLE
        Import-S2DHealthConfig -Path C:\Temp\my-health-checks.json

    .EXAMPLE
        Import-S2DHealthConfig -Path C:\Temp\my-health-checks.json -Validate

    .EXAMPLE
        Import-S2DHealthConfig -Default

    .OUTPUTS
        PSCustomObject (when -Validate) | System.IO.FileInfo (when activating)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Load')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Load', Position = 0)]
        [string] $Path,

        [Parameter(ParameterSetName = 'Load')]
        [switch] $Validate,

        [Parameter(Mandatory = $true, ParameterSetName = 'Default')]
        [switch] $Default
    )

    if ($Default) {
        # Clear the in-memory override and the cached default (forces reload from disk)
        $Script:S2DHealthConfig        = $null
        $Script:S2DHealthConfigDefault = $null
        Write-Verbose 'S2DHealthConfig: reset to shipped defaults.'
        return [pscustomobject]@{ reset = $true; message = 'Active config cleared — shipped defaults will be used.' }
    }

    # Resolve and validate path
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else {
        Join-Path (Get-Location) $Path
    }
    if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
        throw "Health config file not found: '$resolvedPath'"
    }

    # Parse JSON
    $parsed = $null
    try {
        $raw    = Get-Content -Path $resolvedPath -Raw
        $parsed = $raw | ConvertFrom-Json -Depth 20
    } catch {
        throw "Invalid JSON in '$resolvedPath': $($_.Exception.Message)"
    }

    # Schema validation: required top-level keys
    foreach ($key in @('version', 'checks')) {
        if (-not $parsed.PSObject.Properties[$key]) {
            throw "Health config '$resolvedPath' is missing required top-level key '$key'."
        }
    }

    # Each check must have id, weight, title
    $errors = New-Object System.Collections.ArrayList
    foreach ($c in @($parsed.checks)) {
        foreach ($field in @('id', 'weight', 'title')) {
            $val = if ($c.PSObject.Properties[$field]) { $c.$field } else { $null }
            if ([string]::IsNullOrWhiteSpace([string]$val)) {
                [void]$errors.Add("Check is missing '$field' (id='$($c.id)')")
            }
        }
        # Each check must have at least one threshold
        if (-not $c.thresholds -or @($c.thresholds).Count -eq 0) {
            [void]$errors.Add("Check '$($c.id)' has no thresholds defined.")
        } else {
            foreach ($t in @($c.thresholds)) {
                foreach ($tf in @('status', 'label', 'points')) {
                    $tv = if ($t.PSObject.Properties[$tf]) { $t.$tf } else { $null }
                    if ($null -eq $tv) {
                        [void]$errors.Add("Check '$($c.id)' threshold is missing '$tf'.")
                    }
                }
            }
        }
    }

    if ($errors.Count -gt 0) {
        throw "Health config schema violations in '$resolvedPath':`n  - $($errors -join "`n  - ")"
    }

    $checkCount = @($parsed.checks).Count

    if ($Validate) {
        Write-Verbose "Validated '$resolvedPath' ($checkCount check definitions) — not activated (dry-run)."
        return [pscustomobject]@{
            validated  = $true
            checkCount = $checkCount
            version    = [string]$parsed.version
            path       = $resolvedPath
            message    = "Validation passed ($checkCount checks). Use Import-S2DHealthConfig without -Validate to activate."
        }
    }

    # Activate: convert to hashtable and store in module-scoped variable
    $Script:S2DHealthConfig = ConvertTo-S2DHealthConfigHashtable -InputObject $parsed
    # Clear the cached default so a subsequent -Default reset works correctly
    $Script:S2DHealthConfigDefault = $null

    Write-Verbose "Imported health config from '$resolvedPath' ($checkCount checks). Active for this session."
    return [pscustomobject]@{
        activated  = $true
        checkCount = $checkCount
        version    = [string]$parsed.version
        path       = $resolvedPath
    }
}
