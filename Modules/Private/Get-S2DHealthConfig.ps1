#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-S2DHealthConfig {
    <#
    .SYNOPSIS
        Returns the active health-check configuration (check definitions, weights, thresholds).
    .DESCRIPTION
        Returns the in-memory override config when Import-S2DHealthConfig has been called;
        otherwise loads and caches the default config/health-checks.json shipped with the module.
        Private helper — not exported.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    # Return the in-memory override when set by Import-S2DHealthConfig
    if ($Script:S2DHealthConfig -and $Script:S2DHealthConfig.Count -gt 0) {
        return $Script:S2DHealthConfig
    }

    # Load and cache the default config shipped with the module
    if ($null -eq $Script:S2DHealthConfigDefault) {
        # Primary: use the loaded module's ModuleBase (most reliable, works after Install-Module)
        $modInfo    = Get-Module S2DCartographer -ErrorAction SilentlyContinue
        $moduleRoot = if ($modInfo) { $modInfo.ModuleBase } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
        $configPath = Join-Path $moduleRoot 'config\health-checks.json'
        if (-not (Test-Path -Path $configPath -PathType Leaf)) {
            # Fallback: walk up from PSScriptRoot (Private -> Modules -> module root)
            $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $configPath = Join-Path $moduleRoot 'config\health-checks.json'
        }
        if (Test-Path -Path $configPath -PathType Leaf) {
            $raw = Get-Content -Path $configPath -Raw | ConvertFrom-Json -Depth 20
            $Script:S2DHealthConfigDefault = ConvertTo-S2DHealthConfigHashtable -InputObject $raw
        } else {
            Write-Warning "S2DCartographer: health-checks.json not found at '$configPath'. Using empty config — all checks will score with default weight 1."
            $Script:S2DHealthConfigDefault = [ordered]@{
                version        = '1.0.0'
                scoreThresholds = [ordered]@{ excellent = 80; good = 60; fair = 40; needsImprovement = 0 }
                weighting       = [ordered]@{ warnFactor = 0.5 }
                checks          = @()
            }
        }
    }

    return $Script:S2DHealthConfigDefault
}

function ConvertTo-S2DHealthConfigHashtable {
    <#
    .SYNOPSIS
        Converts a PSCustomObject (from ConvertFrom-Json) to a nested ordered hashtable.
    .DESCRIPTION
        Private helper used by Get-S2DHealthConfig and Import-S2DHealthConfig to ensure
        the config is always an IDictionary (not a PSCustomObject) for consistent access.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-S2DHealthConfigHashtable -InputObject $item))
        }
        return $list.ToArray()
    }

    if ($InputObject -is [PSCustomObject]) {
        $ht = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-S2DHealthConfigHashtable -InputObject $prop.Value
        }
        return $ht
    }

    return $InputObject
}

function Get-S2DCheckDefinition {
    <#
    .SYNOPSIS
        Returns the check definition hashtable for a given CheckName from the active config.
    .DESCRIPTION
        Private helper used by the scoring engine in Get-S2DHealthStatus. Returns $null
        when no matching definition is found (check will score with defaults: weight=1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckName
    )

    $config = Get-S2DHealthConfig
    $checks = $config['checks']
    if (-not $checks) { return $null }
    foreach ($c in $checks) {
        if ($c -is [System.Collections.IDictionary]) {
            if ($c['id'] -eq $CheckName) { return $c }
        } elseif ($c.PSObject) {
            if ($c.id -eq $CheckName) { return $c }
        }
    }
    return $null
}

function Invoke-S2DHealthCheckScoring {
    <#
    .SYNOPSIS
        Applies graduated scoring to an S2DHealthCheck using the active config definition.
    .DESCRIPTION
        Looks up the check definition by CheckName. Maps the check's Status to the matching
        threshold entry (Pass/Warn/Fail) and awards points accordingly. Populates the
        Weight, MaxPoints, AwardedPoints, ScoreBand, and ScorePercent fields on the check
        object in-place. Returns the same object for chaining.

        Backward compatibility: existing callers that only read CheckName/Severity/Status/
        Details/Remediation are unaffected — those fields are unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [S2DHealthCheck]$Check
    )

    $def  = Get-S2DCheckDefinition -CheckName $Check.CheckName
    $config = Get-S2DHealthConfig

    # Resolve weight from definition, fall back to 1
    $weight = 1
    if ($def -and $null -ne $def['weight']) {
        $weight = [int]$def['weight']
    }
    $Check.Weight    = $weight
    $Check.MaxPoints = $weight

    # Map Status to threshold entry and award points
    $awarded = 0.0
    $band    = 'Needs Improvement'
    $warnFactor = 0.5
    if ($config['weighting'] -and $null -ne $config['weighting']['warnFactor']) {
        $warnFactor = [double]$config['weighting']['warnFactor']
    }

    if ($def -and $def['thresholds']) {
        $matched = $null
        foreach ($t in $def['thresholds']) {
            $tStatus = if ($t -is [System.Collections.IDictionary]) { $t['status'] } else { $t.status }
            if ($tStatus -eq $Check.Status) { $matched = $t; break }
        }
        if ($matched) {
            $pts  = if ($matched -is [System.Collections.IDictionary]) { $matched['points'] } else { $matched.points }
            $lbl  = if ($matched -is [System.Collections.IDictionary]) { $matched['label']  } else { $matched.label }
            $awarded = [double]$pts
            $band    = if ($lbl) { [string]$lbl } else { [string]$Check.Status }
        } else {
            # No matching threshold — use warnFactor for Warn, 0 for Fail, full for Pass
            $awarded = switch ($Check.Status) {
                'Pass' { [double]$weight }
                'Warn' { [double]$weight * $warnFactor }
                default { 0.0 }
            }
            $band = [string]$Check.Status
        }
    } else {
        # No definition found — apply default scoring
        $awarded = switch ($Check.Status) {
            'Pass' { [double]$weight }
            'Warn' { [double]$weight * $warnFactor }
            default { 0.0 }
        }
        $band = [string]$Check.Status
    }

    $Check.AwardedPoints = $awarded
    $Check.ScorePercent  = if ($weight -gt 0) { [math]::Round($awarded / $weight * 100, 1) } else { 0.0 }
    $Check.ScoreBand     = $band

    return $Check
}

function Invoke-S2DHealthScoreRollup {
    <#
    .SYNOPSIS
        Computes the weighted overall health score from a set of scored S2DHealthCheck objects.
    .DESCRIPTION
        Sums AwardedPoints and MaxPoints across all checks. Returns an ordered hashtable with:
          OverallScore    — integer 0-100 (weighted percentage)
          ScoreStatus     — Excellent | Good | Fair | Needs Improvement
          TotalAwarded    — sum of weighted awarded points
          TotalMax        — sum of weighted max points
          OverallHealth   — legacy string: Healthy | Warning | Critical (unchanged)
        Private helper used by Get-S2DHealthStatus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [S2DHealthCheck[]]$Checks,

        [Parameter(Mandatory = $true)]
        [string]$OverallHealth
    )

    $config = Get-S2DHealthConfig
    $thresh = [ordered]@{ excellent = 80; good = 60; fair = 40; needsImprovement = 0 }
    if ($config['scoreThresholds']) {
        foreach ($k in @('excellent','good','fair','needsImprovement')) {
            if ($null -ne $config['scoreThresholds'][$k]) {
                $thresh[$k] = [int]$config['scoreThresholds'][$k]
            }
        }
    }

    $totalAwarded = 0.0
    $totalMax     = 0.0
    foreach ($c in $Checks) {
        $totalAwarded += [double]$c.AwardedPoints
        $totalMax     += [double]$c.MaxPoints
    }
    $score = if ($totalMax -gt 0) { [int][math]::Round($totalAwarded / $totalMax * 100) } else { 0 }

    $status = if ($score -ge $thresh.excellent)    { 'Excellent' }
              elseif ($score -ge $thresh.good)      { 'Good' }
              elseif ($score -ge $thresh.fair)      { 'Fair' }
              else                                   { 'Needs Improvement' }

    return [ordered]@{
        OverallScore   = $score
        ScoreStatus    = $status
        TotalAwarded   = [math]::Round($totalAwarded, 2)
        TotalMax       = [math]::Round($totalMax, 2)
        OverallHealth  = $OverallHealth
    }
}
