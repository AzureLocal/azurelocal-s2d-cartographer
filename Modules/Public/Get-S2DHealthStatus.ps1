function Get-S2DHealthStatus {
    <#
    .SYNOPSIS
        Runs all S2D health checks and returns pass/warn/fail results with severity.

    .DESCRIPTION
        Executes 11 health checks covering reserve adequacy, disk symmetry, volume health,
        disk health, NVMe wear, thin overcommit, firmware consistency, rebuild capacity,
        infrastructure volume presence, cache tier health, and thin provisioning reserve risk.

        Uses already-collected data from the session cache where available. Run the
        collector cmdlets first for best results, or they will be invoked automatically.

        Requires an active session established with Connect-S2DCluster.

    .PARAMETER CheckName
        Limit results to one or more specific check names.

    .EXAMPLE
        Get-S2DHealthStatus

    .EXAMPLE
        Get-S2DHealthStatus | Where-Object Status -ne 'Pass' | Format-List

    .OUTPUTS
        S2DHealthCheck[]
    #>
    [CmdletBinding()]
    [OutputType([S2DHealthCheck])]
    param(
        [Parameter()]
        [string[]] $CheckName
    )

    # ── Gather prerequisite data ──────────────────────────────────────────────
    $physDisks = @($Script:S2DSession.CollectedData['PhysicalDisks'])
    if (-not $physDisks) { $physDisks = @(Get-S2DPhysicalDiskInventory) }

    $pool = $Script:S2DSession.CollectedData['StoragePool']
    if (-not $pool) { $pool = Get-S2DStoragePoolInfo }

    $volumes = @($Script:S2DSession.CollectedData['Volumes'])
    if (-not $volumes) { $volumes = @(Get-S2DVolumeMap) }

    $cacheTier = $Script:S2DSession.CollectedData['CacheTier']
    if (-not $cacheTier) { $cacheTier = Get-S2DCacheTierInfo }

    $waterfall = $Script:S2DSession.CollectedData['CapacityWaterfall']
    if (-not $waterfall) { $waterfall = Get-S2DCapacityWaterfall }

    $nodeCount = if ($Script:S2DSession.Nodes.Count -gt 0) { $Script:S2DSession.Nodes.Count } else { 4 }

    # ── Helper ────────────────────────────────────────────────────────────────
    function local:New-HealthCheck {
        param([string]$Name, [string]$Severity, [string]$Status, [string]$Details, [string]$Remediation)
        $hc = [S2DHealthCheck]::new()
        $hc.CheckName   = $Name
        $hc.Severity    = $Severity
        $hc.Status      = $Status
        $hc.Details     = $Details
        $hc.Remediation = $Remediation
        $hc
    }

    $checks = @()

    # ── Check 1: Reserve adequacy ─────────────────────────────────────────────
    $check1 = if ($waterfall) {
        switch ($waterfall.ReserveStatus) {
            'Adequate' {
                New-HealthCheck 'ReserveAdequacy' 'Critical' 'Pass' `
                    "Reserve space is adequate. Actual: $($waterfall.ReserveActual.TiB) TiB, Recommended: $($waterfall.ReserveRecommended.TiB) TiB." `
                    "No action required."
            }
            'Warning' {
                New-HealthCheck 'ReserveAdequacy' 'Critical' 'Warn' `
                    "Reserve space is below recommendation. Actual: $($waterfall.ReserveActual.TiB) TiB, Recommended: $($waterfall.ReserveRecommended.TiB) TiB." `
                    "Free pool space by deleting or shrinking volumes, or add capacity drives to the pool."
            }
            default {
                New-HealthCheck 'ReserveAdequacy' 'Critical' 'Fail' `
                    "Reserve space is critically low. Actual: $($waterfall.ReserveActual.TiB) TiB, Recommended: $($waterfall.ReserveRecommended.TiB) TiB." `
                    "Immediately free pool space. The cluster cannot sustain a drive failure and full rebuild."
            }
        }
    }
    else {
        New-HealthCheck 'ReserveAdequacy' 'Critical' 'Warn' 'Could not determine reserve status — no waterfall data.' 'Run Get-S2DCapacityWaterfall to evaluate reserve space.'
    }
    $checks += $check1

    # ── Check 2: Disk symmetry ────────────────────────────────────────────────
    # Only pool members count — boot drives (BOSS) and SAN-presented LUNs visible
    # to some nodes but not others are expected asymmetry and not S2D concerns.
    # Treat missing IsPoolMember (pre-1.2.0 fixtures / older inputs) as pool member
    # so this filter is backward-compatible.
    $poolMemberDisks = @($physDisks | Where-Object { $_.IsPoolMember -ne $false })

    # Empty-data safeguard: when no pool-member disks are present, report as a warning
    # rather than silently passing with a misleading "0 disks per node" pass message.
    if ($poolMemberDisks.Count -eq 0) {
        $checks += New-HealthCheck 'DiskSymmetry' 'Warning' 'Warn' `
            'No pool-member disks found. Physical disk inventory may be empty or collection failed.' `
            'Run Get-S2DPhysicalDiskInventory to verify disk collection. Confirm the cluster has active pool-member drives.'
    }
    else {
        $byNode = @($poolMemberDisks | Group-Object NodeName)
        $diskSymmetryOk = $true
        $symmetryDetail = ''
        if ($byNode.Count -gt 1) {
            $counts = $byNode | Select-Object Name, Count
            $uniqueCounts = @($counts | Select-Object -ExpandProperty Count | Select-Object -Unique)
            if ($uniqueCounts.Count -gt 1) {
                $diskSymmetryOk = $false
                $symmetryDetail = ($counts | ForEach-Object { "$($_.Name)=$($_.Count) pool disks" }) -join ', '
            }
        }
        $disksPerNode = if ($byNode.Count -gt 0) { ($byNode | Select-Object -First 1).Count } else { 0 }
        $check2 = if ($diskSymmetryOk) {
            New-HealthCheck 'DiskSymmetry' 'Warning' 'Pass' `
                "All nodes have a consistent pool-member disk count ($disksPerNode disks per node)." `
                "No action required."
        } else {
            New-HealthCheck 'DiskSymmetry' 'Warning' 'Warn' `
                "Pool-member disk count is inconsistent across nodes: $symmetryDetail" `
                "Investigate missing or additional disks. S2D requires symmetric pool-member disk configurations across nodes."
        }
        $checks += $check2
    }

    # ── Check 3: Volume health ────────────────────────────────────────────────
    $degradedVolumes = @($volumes | Where-Object {
        $_.HealthStatus -ne 'Healthy' -or
        ($_.OperationalStatus -notin 'OK','InService','Online')
    })
    $check3 = if ($degradedVolumes.Count -eq 0) {
        New-HealthCheck 'VolumeHealth' 'Critical' 'Pass' `
            "All $($volumes.Count) volume(s) are healthy." `
            "No action required."
    } else {
        $labels = ($degradedVolumes | ForEach-Object { "$($_.FriendlyName) [$($_.HealthStatus)/$($_.OperationalStatus)]" }) -join ', '
        New-HealthCheck 'VolumeHealth' 'Critical' 'Fail' `
            "Degraded or detached volume(s) detected: $labels" `
            "Run Get-VirtualDisk to investigate. Check cluster event logs and storage health reports."
    }
    $checks += $check3

    # ── Check 4: Disk health ──────────────────────────────────────────────────
    # Scoped to pool-member disks. A failing BOSS / boot drive is a real
    # operational concern but it is outside S2D — not the subject of this tool.
    $unhealthyDisks = @($poolMemberDisks | Where-Object { $_.HealthStatus -ne 'Healthy' })
    $check4 = if ($unhealthyDisks.Count -eq 0) {
        New-HealthCheck 'DiskHealth' 'Critical' 'Pass' `
            "All $($poolMemberDisks.Count) pool-member disk(s) are healthy." `
            "No action required."
    } else {
        $labels = ($unhealthyDisks | ForEach-Object { "$($_.NodeName)/$($_.FriendlyName) [$($_.HealthStatus)]" }) -join ', '
        New-HealthCheck 'DiskHealth' 'Critical' 'Fail' `
            "Non-healthy pool-member disk(s) detected: $labels" `
            "Replace failed or degraded disks promptly. Check Get-PhysicalDisk -HasMediaFailure."
    }
    $checks += $check4

    # ── Check 5: NVMe wear ────────────────────────────────────────────────────
    # Pool members only — wear on a SAN LUN or a BOSS boot drive is not in scope.
    $wornDisks = @($poolMemberDisks | Where-Object {
        $_.MediaType -eq 'NVMe' -and $null -ne $_.WearPercentage -and $_.WearPercentage -gt 80
    })
    $check5 = if ($wornDisks.Count -eq 0) {
        New-HealthCheck 'NVMeWear' 'Warning' 'Pass' `
            "No NVMe drives exceed 80% wear threshold." `
            "No action required. Monitor wear percentage with Get-S2DPhysicalDiskInventory."
    } else {
        $labels = ($wornDisks | ForEach-Object { "$($_.FriendlyName) [$($_.WearPercentage)%]" }) -join ', '
        New-HealthCheck 'NVMeWear' 'Warning' 'Warn' `
            "NVMe drive(s) with wear > 80%: $labels" `
            "Plan replacement for high-wear NVMe drives before they reach 100% (end of rated write endurance)."
    }
    $checks += $check5

    # ── Check 6: Thin overcommit ──────────────────────────────────────────────
    # Tiered check: max potential footprint (if all thin volumes were fully written)
    # vs pool total. Fires earlier than a simple overcommit ratio check.
    $thinWorkloadVols = @($volumes | Where-Object { -not $_.IsInfrastructureVolume -and $_.ProvisioningType -eq 'Thin' })
    $maxPotentialFootprintBytes = [int64](
        ($thinWorkloadVols | ForEach-Object {
            if ($_.MaxPotentialFootprint) { $_.MaxPotentialFootprint.Bytes } else { [int64]0 }
        } | Measure-Object -Sum).Sum
    )
    $poolTotalBytes  = if ($pool -and $pool.TotalSize) { $pool.TotalSize.Bytes } else { [int64]0 }
    $potentialRatio  = if ($poolTotalBytes -gt 0 -and $maxPotentialFootprintBytes -gt 0) {
        [math]::Round($maxPotentialFootprintBytes / $poolTotalBytes, 3)
    } else { 0.0 }
    $isOvercommitted = $pool -and $pool.OvercommitRatio -gt 1.0

    $check6 = if ($potentialRatio -gt 1.0) {
        New-HealthCheck 'ThinOvercommit' 'Critical' 'Fail' `
            "Thin volume max potential footprint ($([math]::Round($maxPotentialFootprintBytes/1TB,2)) TB, $([math]::Round($potentialRatio*100,1))% of pool) exceeds pool total ($([math]::Round($poolTotalBytes/1TB,2)) TB). Pool will be exhausted if all thin volumes write to their provisioned size." `
            "Reduce provisioned sizes of thin volumes, convert high-growth volumes to fixed provisioning, or add capacity drives."
    } elseif ($potentialRatio -gt 0.8) {
        New-HealthCheck 'ThinOvercommit' 'Warning' 'Warn' `
            "Thin volume max potential footprint is $([math]::Round($potentialRatio*100,1))% of pool total ($([math]::Round($maxPotentialFootprintBytes/1TB,2)) TB of $([math]::Round($poolTotalBytes/1TB,2)) TB). Heavy write workloads could exhaust the pool." `
            "Monitor thin volume growth. Consider reducing provisioned sizes or converting high-growth volumes to fixed provisioning."
    } elseif ($isOvercommitted) {
        New-HealthCheck 'ThinOvercommit' 'Warning' 'Warn' `
            "Pool is overcommitted. Provisioned: $($pool.ProvisionedSize.TiB) TiB, Pool total: $($pool.TotalSize.TiB) TiB (ratio: $($pool.OvercommitRatio)x)." `
            "Monitor actual data growth. Thin-provisioned volumes can run out of pool space unexpectedly. Add capacity or reduce provisioned sizes."
    } else {
        $thinDesc = if ($thinWorkloadVols.Count -gt 0) {
            "$($thinWorkloadVols.Count) thin workload volume(s). Max potential footprint: $([math]::Round($maxPotentialFootprintBytes/1TB,2)) TB ($([math]::Round($potentialRatio*100,1))% of pool). Overcommit ratio: $(if($pool){"$($pool.OvercommitRatio)x"} else {"N/A"})."
        } else {
            "No thin-provisioned workload volumes. Overcommit ratio: $(if($pool){"$($pool.OvercommitRatio)x"} else {"N/A"})."
        }
        New-HealthCheck 'ThinOvercommit' 'Warning' 'Pass' $thinDesc "No action required."
    }
    $checks += $check6

    # ── Check 7: Firmware consistency ─────────────────────────────────────────
    # Pool members only — firmware consistency across BOSS and SAN LUNs is not
    # relevant to S2D correctness.
    $firmwareInconsistent = $false
    $firmwareDetail = ''
    $byModel = $poolMemberDisks | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Model) } | Group-Object Model
    foreach ($modelGroup in $byModel) {
        $fwVersions = @($modelGroup.Group | Select-Object -ExpandProperty FirmwareVersion | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($fwVersions.Count -gt 1) {
            $firmwareInconsistent = $true
            $firmwareDetail += "Model '$($modelGroup.Name)': $($fwVersions -join ', '). "
        }
    }
    $check7 = if (-not $firmwareInconsistent) {
        New-HealthCheck 'FirmwareConsistency' 'Info' 'Pass' `
            "All disks of the same model are on consistent firmware." `
            "No action required."
    } else {
        New-HealthCheck 'FirmwareConsistency' 'Info' 'Warn' `
            "Firmware inconsistency detected: $($firmwareDetail.Trim())" `
            "Update all drives of the same model to the latest firmware. Use the vendor update tool or Dell/HPE/Lenovo HCI management utilities."
    }
    $checks += $check7

    # ── Check 8: Rebuild capacity ─────────────────────────────────────────────
    # Cluster can survive a node failure and fully rebuild if:
    # free pool space >= (total data on largest node's disks × resiliency copies)
    $rebuildOk = $true
    $rebuildDetail = ''
    if ($pool -and $pool.RemainingSize -and $pool.AllocatedSize) {
        $freeBytes  = $pool.RemainingSize.Bytes
        # Rebuild capacity math is pool-only — non-pool disks are never rebuilt
        # into the S2D pool if their node fails.
        $nodeGroups = @($poolMemberDisks | Group-Object NodeName)
        # Empty-data safeguard: Measure-Object -Maximum on an empty pipeline yields $null;
        # explicitly default to 0 to prevent [int64]$null issues under StrictMode.
        $largestNodeDiskBytesRaw = (
            $nodeGroups |
            ForEach-Object { ($_.Group | Measure-Object -Property SizeBytes -Sum).Sum } |
            Measure-Object -Maximum
        ).Maximum
        $largestNodeDiskBytes = if ($null -ne $largestNodeDiskBytesRaw) { [int64]$largestNodeDiskBytesRaw } else { [int64]0 }
        # Sanity check: if NodeName grouping produced fewer groups than nodes, disk
        # NodeName assignment is unreliable (can happen when collection deduplicates
        # pool-member disks but StorageNode associations are unavailable). Fall back
        # to evenly distributing pool total across node count.
        if ($nodeGroups.Count -lt $nodeCount -and $nodeCount -gt 0 -and $pool.TotalSize) {
            $largestNodeDiskBytes = [int64]($pool.TotalSize.Bytes / $nodeCount)
        }

        if ($freeBytes -lt $largestNodeDiskBytes) {
            $rebuildOk     = $false
            $rebuildDetail = "Free pool space ($([math]::Round($freeBytes/1TB,2)) TB) is less than largest node's disk capacity ($([math]::Round($largestNodeDiskBytes/1TB,2)) TB). Rebuild after a node failure may not complete."
        }
        else {
            $rebuildDetail = "Free pool space ($([math]::Round($freeBytes/1TB,2)) TB) is sufficient to absorb loss of the largest node ($([math]::Round($largestNodeDiskBytes/1TB,2)) TB)."
        }
    }
    else {
        $rebuildDetail = 'Pool data unavailable — could not evaluate rebuild capacity.'
    }
    $check8 = if ($rebuildOk) {
        New-HealthCheck 'RebuildCapacity' 'Critical' 'Pass' $rebuildDetail "No action required."
    } else {
        New-HealthCheck 'RebuildCapacity' 'Critical' 'Warn' $rebuildDetail `
            "Free pool space by removing or shrinking volumes. Consider adding capacity drives."
    }
    $checks += $check8

    # ── Check 9: Infrastructure volume ────────────────────────────────────────
    $infraVolumes = @($volumes | Where-Object IsInfrastructureVolume)
    $check9 = if ($infraVolumes.Count -gt 0) {
        $healthyInfra = @($infraVolumes | Where-Object { $_.HealthStatus -eq 'Healthy' })
        if ($healthyInfra.Count -eq $infraVolumes.Count) {
            New-HealthCheck 'InfrastructureVolume' 'Info' 'Pass' `
                "Infrastructure volume(s) present and healthy: $(($infraVolumes | Select-Object -ExpandProperty FriendlyName) -join ', ')." `
                "No action required."
        }
        else {
            New-HealthCheck 'InfrastructureVolume' 'Info' 'Warn' `
                "Infrastructure volume detected but not fully healthy: $(($infraVolumes | ForEach-Object {"$($_.FriendlyName) [$($_.HealthStatus)]"}) -join ', ')." `
                "Investigate with Get-VirtualDisk. Azure Local management plane may be degraded."
        }
    } else {
        New-HealthCheck 'InfrastructureVolume' 'Info' 'Warn' `
            "No infrastructure volume detected. Expected on Azure Local clusters." `
            "This may be normal for Windows Server S2D. On Azure Local, check cluster deployment status."
    }
    $checks += $check9

    # ── Check 10: Cache tier health ───────────────────────────────────────────
    $check10 = if (-not $cacheTier) {
        New-HealthCheck 'CacheTierHealth' 'Warning' 'Warn' `
            "Cache tier data unavailable." `
            "Run Get-S2DCacheTierInfo to evaluate cache health."
    } elseif ($cacheTier.CacheState -eq 'Degraded') {
        New-HealthCheck 'CacheTierHealth' 'Warning' 'Warn' `
            "Cache tier is degraded. Cache state: $($cacheTier.CacheState). Cache disks: $($cacheTier.CacheDiskCount)." `
            "Check cache disk health with Get-S2DPhysicalDiskInventory. Replace failed cache drives promptly to restore write performance."
    } elseif ($cacheTier.IsAllFlash -and $cacheTier.SoftwareCacheEnabled) {
        New-HealthCheck 'CacheTierHealth' 'Warning' 'Pass' `
            "All-flash cluster with software write-back cache enabled. Cache mode: $($cacheTier.CacheMode)." `
            "No action required. Software cache is managed by S2D automatically."
    } elseif ($cacheTier.CacheState -eq 'Active') {
        New-HealthCheck 'CacheTierHealth' 'Warning' 'Pass' `
            "Cache tier is active. Mode: $($cacheTier.CacheMode), $($cacheTier.CacheDiskCount) cache disk(s), ratio: $($cacheTier.CacheToCapacityRatio):1." `
            "No action required."
    } else {
        New-HealthCheck 'CacheTierHealth' 'Warning' 'Warn' `
            "Cache tier state is '$($cacheTier.CacheState)'. Mode: $($cacheTier.CacheMode)." `
            "Investigate cache tier with Get-ClusterS2D and Get-PhysicalDisk."
    }
    $checks += $check10

    # ── Check 11: Thin provisioning reserve risk ──────────────────────────────
    # Asks: if all thin volumes grew to their maximum provisioned size, would the
    # rebuild reserve still be intact? Pool.RemainingSize looks healthy today but
    # uncommitted thin growth can silently consume that space.
    $currentThinFootprintBytes = [int64](
        ($thinWorkloadVols | ForEach-Object {
            if ($_.FootprintOnPool) { $_.FootprintOnPool.Bytes } else { [int64]0 }
        } | Measure-Object -Sum).Sum
    )
    $uncommittedGrowthBytes = [math]::Max([int64]0, $maxPotentialFootprintBytes - $currentThinFootprintBytes)
    $poolFreeBytes          = if ($pool -and $pool.RemainingSize) { $pool.RemainingSize.Bytes } else { [int64]0 }
    $reserveRecommBytes     = if ($waterfall -and $waterfall.ReserveRecommended) { $waterfall.ReserveRecommended.Bytes } else { [int64]0 }
    $freeAfterMaxGrowth     = $poolFreeBytes - $uncommittedGrowthBytes

    $check11 = if ($thinWorkloadVols.Count -eq 0) {
        New-HealthCheck 'ThinReserveRisk' 'Warning' 'Pass' `
            "No thin-provisioned workload volumes. Rebuild reserve is not at risk from thin volume growth." `
            "No action required."
    } elseif ($uncommittedGrowthBytes -eq 0) {
        New-HealthCheck 'ThinReserveRisk' 'Warning' 'Pass' `
            "Thin volumes have no uncommitted growth headroom — already at maximum footprint." `
            "No action required."
    } elseif ($freeAfterMaxGrowth -lt 0) {
        New-HealthCheck 'ThinReserveRisk' 'Critical' 'Fail' `
            "If all thin volumes write to full provisioned size, pool free space will be exhausted. Current free: $([math]::Round($poolFreeBytes/1TB,2)) TB. Uncommitted thin growth: $([math]::Round($uncommittedGrowthBytes/1TB,2)) TB." `
            "Reduce thin volume provisioned sizes, convert to fixed provisioning, or add capacity drives immediately."
    } elseif ($freeAfterMaxGrowth -lt $reserveRecommBytes) {
        New-HealthCheck 'ThinReserveRisk' 'Warning' 'Warn' `
            "If all thin volumes write to full provisioned size, the rebuild reserve will be consumed. Free after max growth: $([math]::Round($freeAfterMaxGrowth/1TB,2)) TB vs. recommended reserve $([math]::Round($reserveRecommBytes/1TB,2)) TB." `
            "Monitor thin volume growth. Reduce provisioned sizes or add capacity to protect the rebuild reserve."
    } else {
        New-HealthCheck 'ThinReserveRisk' 'Warning' 'Pass' `
            "Rebuild reserve is safe even at maximum thin volume growth. Free after max growth: $([math]::Round($freeAfterMaxGrowth/1TB,2)) TB, reserve requirement: $([math]::Round($reserveRecommBytes/1TB,2)) TB." `
            "No action required."
    }
    $checks += $check11

    # ── Filter by CheckName ───────────────────────────────────────────────────
    $result = if ($CheckName) {
        @($checks | Where-Object { $_.CheckName -in $CheckName })
    }
    else {
        @($checks)
    }

    # ── Overall health rollup ─────────────────────────────────────────────────
    $overallHealth = if (@($result | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Critical' }).Count -gt 0) {
        'Critical'
    }
    elseif (@($result | Where-Object { $_.Status -in 'Fail','Warn' }).Count -gt 0) {
        'Warning'
    }
    else {
        'Healthy'
    }

    $Script:S2DSession.CollectedData['HealthChecks']   = $result
    $Script:S2DSession.CollectedData['OverallHealth']  = $overallHealth

    $result
}
