function Get-S2DCacheTierInfo {
    <#
    .SYNOPSIS
        Analyzes the S2D cache tier configuration, binding ratio, and health.

    .DESCRIPTION
        Classifies cache vs capacity disks, computes the cache-to-capacity ratio, and
        surfaces degradation or missing cache disk conditions.

        Handles all-NVMe clusters (software write-back cache) and hybrid configurations
        (NVMe/SSD cache over HDD/SSD capacity tier).

        Requires an active session established with Connect-S2DCluster, or pass
        -CimSession directly.

    .PARAMETER CimSession
        Override the module session and target this CimSession directly.

    .EXAMPLE
        Get-S2DCacheTierInfo

    .EXAMPLE
        Get-S2DCacheTierInfo | Select-Object CacheMode, IsAllFlash, CacheDiskCount, CacheToCapacityRatio

    .OUTPUTS
        S2DCacheTier
    #>
    [CmdletBinding()]
    [OutputType([S2DCacheTier])]
    param(
        [Parameter()]
        [CimSession] $CimSession
    )

    $usePSSession = -not $PSBoundParameters.ContainsKey('CimSession') -and
                    -not $Script:S2DSession.IsLocal -and
                    $null -ne $Script:S2DSession.PSSession

    $session = if ($usePSSession) { $null } else { Resolve-S2DSession -CimSession $CimSession }

    # ── Re-use already-collected disk data if available ───────────────────────
    $physDisks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
    if (-not $physDisks) {
        Write-Verbose "PhysicalDisk data not cached — collecting now."
        $physDisks = @(
            if ($usePSSession) {
                Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock {
                    @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
                }
            }
            elseif ($session) { Get-S2DPhysicalDiskData -CimSession $session }
            else               { Get-S2DPhysicalDiskData }
        )
    }

    # ── Detect all-flash ──────────────────────────────────────────────────────
    $mediaTypes = @(
        $physDisks |
        Select-Object -ExpandProperty MediaType -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )
    # StrictMode-safe: wrap in @() so .Count never fails when Where-Object yields $null.
    $isAllFlash = (@($mediaTypes | Where-Object { $_ -notin 'NVMe','SSD','SCM' }).Count -eq 0) -and
                   ($mediaTypes.Count -gt 0)

    # ── Query ClusterS2D for software cache details ───────────────────────────
    $clusterS2D = $null
    try {
        $clusterS2D = if ($usePSSession) {
            Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock {
                try { Get-ClusterS2D -ErrorAction SilentlyContinue } catch { $null }
            }
        }
        elseif ($session) { Get-S2DClusterS2DData -CimSession $session }
        else               { Get-S2DClusterS2DData }
    }
    catch {}

    $softwareCacheEnabled = $false
    $writeCacheSizeBytes  = [int64]0
    $cacheMode            = 'No Cache'

    if ($clusterS2D) {
        $softwareCacheEnabled = try { [bool]$clusterS2D.CacheEnabled }          catch { $false }
        $writeCacheSizeBytes  = try { [int64]$clusterS2D.CachePageSizeKBytes * 1024 } catch { [int64]0 }

        if ($softwareCacheEnabled) {
            $rawMode = try { [string]$clusterS2D.CacheMode } catch { '' }
            $cacheMode = if ([string]::IsNullOrWhiteSpace($rawMode)) { 'ReadWrite' } else { $rawMode }
        }
    }

    # All-NVMe: software write-back cache across all drives, no physical split
    if ($isAllFlash) {
        $softwareCacheEnabled = $true
        if ($cacheMode -eq 'No Cache') { $cacheMode = 'ReadWrite' }
    }

    # ── Identify physical cache and capacity disks ────────────────────────────
    $cacheDisks    = @($physDisks | Where-Object { $_.Role -eq 'Cache'    -or $_.Usage -eq 'Journal' })
    $capacityDisks = @($physDisks | Where-Object { $_.Role -eq 'Capacity' -or ($_.Usage -eq 'Auto-Select' -and $_.Role -ne 'Cache') })

    $cacheDiskCount = $cacheDisks.Count

    $cacheModel = if ($cacheDisks) {
        ($cacheDisks |
         Group-Object Model |
         Sort-Object Count -Descending |
         Select-Object -First 1).Name
    }
    else { $null }

    $cacheDiskSizeBytes = if ($cacheDisks) {
        [int64](
            $cacheDisks |
            Select-Object -ExpandProperty SizeBytes -ErrorAction SilentlyContinue |
            Measure-Object -Maximum
        ).Maximum
    }
    else { [int64]0 }

    $cacheToCapacityRatio = if ($capacityDisks.Count -gt 0 -and $cacheDiskCount -gt 0) {
        [math]::Round($cacheDiskCount / $capacityDisks.Count, 2)
    }
    else { 0 }

    $cacheState = if ($cacheDisks) {
        $unhealthy = @($cacheDisks | Where-Object { $_.HealthStatus -ne 'Healthy' })
        if ($unhealthy.Count -gt 0) { 'Degraded' } else { 'Active' }
    }
    elseif ($softwareCacheEnabled) { 'Active' }
    else { 'None' }

    $result = [S2DCacheTier]::new()
    $result.CacheMode            = $cacheMode
    $result.IsAllFlash           = $isAllFlash
    $result.SoftwareCacheEnabled = $softwareCacheEnabled
    $result.CacheDiskCount       = $cacheDiskCount
    $result.CacheDiskModel       = $cacheModel
    $result.CacheDiskSize        = if ($cacheDiskSizeBytes -gt 0) { [S2DCapacity]::new($cacheDiskSizeBytes) } else { $null }
    $result.CacheToCapacityRatio = $cacheToCapacityRatio
    $result.CacheState           = $cacheState
    $result.WriteCacheSizeBytes  = $writeCacheSizeBytes

    $Script:S2DSession.CollectedData['CacheTier'] = $result
    $result
}
