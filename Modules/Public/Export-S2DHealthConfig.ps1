#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-S2DHealthConfig {
    <#
    .SYNOPSIS
        Exports the active S2D health-check configuration to a JSON file.

    .DESCRIPTION
        Writes the active health-check configuration (weights, thresholds, and check definitions)
        to a JSON file so operators can inspect and edit it. The exported file can be modified and
        re-loaded with Import-S2DHealthConfig to override scoring behaviour without code changes.

        When Import-S2DHealthConfig has not been called (no override is active), the shipped
        default config/health-checks.json is exported. When an override is active, the override
        is exported.

    .PARAMETER OutputPath
        Path to write the exported JSON. Defaults to 'health-checks.json' in the current directory.

    .EXAMPLE
        Export-S2DHealthConfig -OutputPath C:\Temp\my-health-checks.json

    .EXAMPLE
        Export-S2DHealthConfig | Select-Object -ExpandProperty FullName

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter()]
        [string] $OutputPath = (Join-Path (Get-Location) 'health-checks.json')
    )

    # Resolve the source: prefer the baked-in default file so Export always produces
    # a canonical, well-formatted JSON rather than a round-trip through ConvertTo-Json
    # (which can reorder keys). When an override is active, we still output the raw
    # canonical file plus a note — the override is in-memory only.

    $moduleBase = (Get-Module S2DCartographer -ErrorAction SilentlyContinue).ModuleBase
    if (-not $moduleBase) {
        throw 'S2DCartographer module is not loaded. Import-Module S2DCartographer first.'
    }

    $sourcePath = Join-Path $moduleBase 'config\health-checks.json'
    if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
        throw "Shipped health-checks.json not found at '$sourcePath'. The module installation may be incomplete."
    }

    # When an active override exists, serialize it instead of copying the default
    if ($Script:S2DHealthConfig -and $Script:S2DHealthConfig.Count -gt 0) {
        $json = $Script:S2DHealthConfig | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
        Write-Verbose "Exported active (overridden) health config to '$OutputPath'."
    } else {
        Copy-Item -Path $sourcePath -Destination $OutputPath -Force
        Write-Verbose "Exported default health config to '$OutputPath'."
    }

    Get-Item -Path $OutputPath
}
