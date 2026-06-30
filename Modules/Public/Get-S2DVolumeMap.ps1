function Get-S2DVolumeMap {
    <#
    .SYNOPSIS
        Maps all S2D volumes with resiliency type, capacity footprint, and provisioning detail.

    .DESCRIPTION
        Queries VirtualDisk and ClusterSharedVolume. Returns per-volume resiliency
        efficiency, footprint, provisioning type, overcommit ratio for thin volumes, and
        auto-detects the Azure Local infrastructure volume by name/size pattern.

        Requires an active session established with Connect-S2DCluster, or pass
        -CimSession directly.

    .PARAMETER VolumeName
        Limit results to one or more specific volume friendly names.

    .PARAMETER CimSession
        Override the module session and target this CimSession directly.

    .EXAMPLE
        Get-S2DVolumeMap

    .EXAMPLE
        Get-S2DVolumeMap | Format-Table FriendlyName, ResiliencySettingName, Size, EfficiencyPercent

    .OUTPUTS
        S2DVolume[]
    #>
    [CmdletBinding()]
    [OutputType([S2DVolume])]
    param(
        [Parameter()]
        [string[]] $VolumeName,

        [Parameter()]
        [CimSession] $CimSession
    )

    $usePSSession = -not $PSBoundParameters.ContainsKey('CimSession') -and
                    -not $Script:S2DSession.IsLocal -and
                    $null -ne $Script:S2DSession.PSSession

    $session   = if ($usePSSession) { $null } else { Resolve-S2DSession -CimSession $CimSession }
    $nodeCount = if ($Script:S2DSession.Nodes.Count -gt 0) { $Script:S2DSession.Nodes.Count } else { 3 }

    # ── Collect raw virtual disks ─────────────────────────────────────────────
    $vdisks = @()

    if ($usePSSession) {
        $vdisks = @(Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock {
            @(Get-VirtualDisk -ErrorAction SilentlyContinue)
        })
    }
    else {
        $vdisks = @(if ($session) { Get-S2DVirtualDiskData -CimSession $session } else { Get-S2DVirtualDiskData })
    }

    if (-not $vdisks) {
        Write-Warning "No virtual disks found."
        return
    }

    # ── Build volume objects ──────────────────────────────────────────────────
    $result = @($vdisks | ForEach-Object {
        $vd = $_

        $resiliencyName  = try { [string]$vd.ResiliencySettingName }  catch { 'Mirror' }
        $dataCopies      = try { [int]$vd.NumberOfDataCopies }         catch { 2 }
        $diskRedundancy  = try { [int]$vd.PhysicalDiskRedundancy }     catch { 2 }
        $provType        = try { [string]$vd.ProvisioningType }        catch { 'Fixed' }

        $safeResiliency = if ($resiliencyName -in 'Mirror', 'Parity') { $resiliencyName } else { 'Mirror' }
        $effResult = Get-S2DResiliencyEfficiency `
            -ResiliencySettingName  $safeResiliency `
            -NumberOfDataCopies     $dataCopies `
            -PhysicalDiskRedundancy $diskRedundancy `
            -NodeCount              $nodeCount

        $sizeBytes      = [int64]$vd.Size
        $footprintBytes = try { [int64]$vd.FootprintOnPool } catch { [int64]0 }
        $allocatedBytes = try { [int64]$vd.AllocatedSize }   catch { [int64]0 }

        $overcommitRatio = if ($footprintBytes -gt 0 -and $allocatedBytes -gt $footprintBytes) {
            [math]::Round($allocatedBytes / $footprintBytes, 3)
        }
        else { 1.0 }

        $isInfra = Get-S2DInfraVolumeFlag -FriendlyName $vd.FriendlyName -SizeBytes $sizeBytes

        $vol = [S2DVolume]::new()
        $vol.FriendlyName           = $vd.FriendlyName
        $vol.FileSystem             = try { [string]$vd.FileSystem } catch { 'Unknown' }
        $vol.ResiliencySettingName  = $resiliencyName
        $vol.NumberOfDataCopies     = $dataCopies
        $vol.PhysicalDiskRedundancy = $diskRedundancy
        $vol.ProvisioningType       = $provType
        $vol.Size                   = if ($sizeBytes -gt 0)      { [S2DCapacity]::new($sizeBytes) }      else { $null }
        $vol.FootprintOnPool        = if ($footprintBytes -gt 0) { [S2DCapacity]::new($footprintBytes) } else { $null }
        $vol.AllocatedSize          = if ($allocatedBytes -gt 0) { [S2DCapacity]::new($allocatedBytes) } else { $null }
        $vol.OperationalStatus      = try { [string]$vd.OperationalStatus } catch { 'Unknown' }
        $vol.HealthStatus           = try { [string]$vd.HealthStatus }       catch { 'Unknown' }
        $vol.IsDeduplicationEnabled = $false
        $vol.IsInfrastructureVolume = $isInfra
        # Ground-truth efficiency: derive from measured footprint/size when both are
        # available (eliminates any resiliency-detection error). Falls back to the
        # formula result only when footprint data is absent (e.g. very old clusters).
        $vol.EfficiencyPercent      = if ($footprintBytes -gt 0 -and $sizeBytes -gt 0) {
            [math]::Round($sizeBytes / $footprintBytes * 100, 1)
        } else {
            $effResult.EfficiencyPercent
        }
        $vol.OvercommitRatio        = $overcommitRatio

        # Thin provisioning growth metrics — only meaningful for thin volumes
        if ($provType -eq 'Thin' -and $sizeBytes -gt 0) {
            $headroomBytes = $sizeBytes - $allocatedBytes
            $vol.ThinGrowthHeadroom    = if ($headroomBytes -gt 0) { [S2DCapacity]::new($headroomBytes) } else { [S2DCapacity]::new([int64]0) }
            $vol.MaxPotentialFootprint = [S2DCapacity]::new($sizeBytes * $dataCopies)
        }

        $vol
    })

    $Script:S2DSession.CollectedData['Volumes'] = $result

    if ($VolumeName) {
        $result = @($result | Where-Object { $_.FriendlyName -in $VolumeName })
    }

    $result
}

function Get-S2DInfraVolumeFlag {
    param([string]$FriendlyName, [int64]$SizeBytes)

    # Azure Local infrastructure volume name patterns.
    # UserStorage_N volumes are created by Azure Local deployment as system storage;
    # they are often thin-provisioned but are not user workload volumes.
    $infraPatterns = @(
        '^Infrastructure_[0-9a-f-]+$',
        '^ClusterPerformanceHistory$',
        '^UserStorage_\d+$',
        '^HCI_UserStorage_\d+$',
        '^SBEAgent$',
        'infra',
        'infrastructure'
    )
    foreach ($pattern in $infraPatterns) {
        if ($FriendlyName -imatch $pattern) { return $true }
    }

    # Size heuristic: < 600 GiB and non-zero is likely an infra volume
    if ($SizeBytes -gt 0 -and $SizeBytes -lt 644245094400) { return $true }

    return $false
}
