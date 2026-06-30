# HTML report exporter — self-contained single-file dashboard with Chart.js

function Export-S2DHtmlReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks
    )

    $generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $cn   = $ClusterData.ClusterName
    $nc   = $ClusterData.NodeCount
    $pool = $ClusterData.StoragePool
    $wf   = $ClusterData.CapacityWaterfall
    $hc   = @($ClusterData.HealthChecks)
    $oh   = $ClusterData.OverallHealth
    $vols = @($ClusterData.Volumes)
    # Physical Disk Inventory shows pool members only by default. Boot drives
    # (BOSS) and SAN-presented LUNs are not in S2D scope — their presence in
    # the report misleads the reader into thinking they are pool capacity.
    $allDisks = @($ClusterData.PhysicalDisks)
    $disks = if ($IncludeNonPoolDisks) { $allDisks } else { @($allDisks | Where-Object { $_.IsPoolMember -ne $false }) }
    $cache = $ClusterData.CacheTier

    # Part A: provisioning-aware 70% framing.
    # Determine if any workload (non-infra) volumes are thin-provisioned.
    # Used for the 70% KPI tile, waterfall planning-line row, and headroom table.
    # Null-safe: ProvisioningType comparison is guarded against $null via -eq (returns $false when $null).
    $hasThinVolumes = [bool](@($vols | Where-Object {
        (-not $_.IsInfrastructureVolume) -and ($_.ProvisioningType -eq 'Thin')
    }).Count -gt 0)

    $overallBg = switch ($oh) { 'Healthy'{'#dff6dd'} 'Warning'{'#fff4ce'} 'Critical'{'#fde7e9'} default{'#f3f2f1'} }
    $overallFg = switch ($oh) { 'Healthy'{'#107c10'} 'Warning'{'#d47a00'} 'Critical'{'#d13438'} default{'#323130'} }

    # ── Waterfall chart data ──────────────────────────────────────────────────
    $wfLabels       = ''
    $wfValues       = ''
    $wfTbValues     = ''   # AB#263: authoritative TB values — consumed via here-string interpolation below
    $wfDescRows     = ''
    $wf70LineTiB    = 0
    $wf70LineTB     = 0
    $wfAbove70Flag  = $false
    if ($wf) {
        $wfLabels   = ($wf.Stages | ForEach-Object { "'Stage $($_.Stage): $($_.Name)'" }) -join ','
        $wfValues   = ($wf.Stages | ForEach-Object { if ($_.Size) { [math]::Round($_.Size.TiB, 2) } else { 0 } }) -join ','
        # AB#263: authoritative TB values from S2DCapacity.TB (byte-accurate) — do not approximate TiB × 1.0995 in JS.
        $wfTbValues = ($wf.Stages | ForEach-Object { if ($_.Size) { [math]::Round($_.Size.TB,  2) } else { 0 } }) -join ','

        # AB#4644: 70% planning line values for chart annotation
        if ($wf.PlanningLine70Pct) {
            $wf70LineTiB   = [math]::Round($wf.PlanningLine70Pct.TiB, 2)
            $wf70LineTB    = [math]::Round($wf.PlanningLine70Pct.TB,  2)
            $wfAbove70Flag = $wf.IsAbove70PctLine
        }

        # AB#4645: waterfall table rows — show both TB and TiB for remaining and delta;
        # label each stage as FOOTPRINT or DATA (usable). The Description field (from
        # Invoke-S2DWaterfallCalculation) now carries the full dual-unit breakdown.
        $wfDescRows = ($wf.Stages | ForEach-Object {
            $icon      = '<span style="color:#0078d4;font-size:14px">&#x2192;</span>'
            $deltaStr  = if ($_.Delta -and [math]::Abs($_.Delta.TB) -gt 0) {
                $dTB  = [math]::Round($_.Delta.TB,  2)
                $dTiB = [math]::Round($_.Delta.TiB, 2)
                "<span style='color:#a19f9d;font-size:12px'>&#x2212;$dTB TB / $dTiB TiB</span>"
            } else {
                "<span style='color:#a19f9d;font-size:11px'>&#x2014;</span>"
            }
            # AB#4645: remaining shows TB (decimal) and TiB (binary) — both units, unambiguous
            $remTB  = if ($_.Size) { [math]::Round($_.Size.TB,  2) } else { 0 }
            $remTiB = if ($_.Size) { [math]::Round($_.Size.TiB, 2) } else { 0 }
            # AB#4645: space-type badge — footprint vs data
            $spaceBadge = if ($_.Stage -eq 7) {
                "<span style='font-size:10px;background:#dff6dd;color:#107c10;border-radius:3px;padding:1px 5px;margin-left:4px'>DATA</span>"
            } else {
                "<span style='font-size:10px;background:#eff6fc;color:#0078d4;border-radius:3px;padding:1px 5px;margin-left:4px'>FOOTPRINT</span>"
            }
            $stageRow = "<tr><td style='width:28px;text-align:center;padding:6px 4px'>$icon</td><td style='width:24px;font-weight:700;color:#0078d4;padding:6px 8px'>$($_.Stage)</td><td style='font-weight:600;padding:6px 8px;white-space:nowrap'>$($_.Name)$spaceBadge</td><td style='text-align:right;color:#a19f9d;padding:6px 8px;white-space:nowrap;font-size:12px'>$deltaStr</td><td style='color:#605e5c;padding:6px 8px;font-size:12px'>$($_.Description)</td><td style='text-align:right;font-weight:600;padding:6px 8px;white-space:nowrap'>$remTB TB<br><span style='font-size:11px;color:#605e5c;font-weight:400'>$remTiB TiB</span></td></tr>"
            # AB#4644: inject 70% line row after Stage 6 (Available for Volumes)
            if ($_.Stage -eq 6 -and $wf.PlanningLine70Pct -and $wf.PlanningLine70Pct.Bytes -gt 0) {
                $lineTB  = [math]::Round($wf.PlanningLine70Pct.TB,  2)
                $lineTiB = [math]::Round($wf.PlanningLine70Pct.TiB, 2)
                # Part A: amber alert only when thin volumes are present; neutral/advisory otherwise.
                $alertStyle = if ($wfAbove70Flag -and $hasThinVolumes) { "background:#fff4ce" } else { "background:#faf9f8" }
                $alertBadge = if ($wfAbove70Flag -and $hasThinVolumes) {
                    "<span style='font-size:10px;background:#fff4ce;color:#d47a00;border-radius:3px;padding:1px 5px;margin-left:6px;font-weight:700'>ALERT: above 70% line</span>"
                } elseif ($wfAbove70Flag) {
                    "<span style='font-size:10px;background:#eff6fc;color:#0078d4;border-radius:3px;padding:1px 5px;margin-left:6px;font-weight:500'>Above 70% (advisory)</span>"
                } else { '' }
                $lineLabel      = if ($hasThinVolumes) { 'Planning Line' } else { 'Advisory Line' }
                $lineColor      = if ($hasThinVolumes) { '#e8a218' } else { '#0078d4' }
                $lineDesc       = if ($hasThinVolumes) {
                    '70% of available-for-volumes (footprint basis). Thin volumes are present — a full pool takes thin volumes offline. Workload footprint should stay below this line.'
                } else {
                    '70% is a recommended operational headroom guideline — mainly relevant for thin-provisioned volumes, where a full pool takes thin volumes offline. Not a Microsoft hard limit. The firm limits are footprints fitting the pool and the rebuild reserve staying intact. All volumes are fixed — footprint is committed up front.'
                }
                $lineRow = "<tr style='$alertStyle'><td style='text-align:center;padding:6px 4px'><span style='color:$lineColor;font-size:14px'>&#x25BA;</span></td><td style='font-weight:700;color:$lineColor;padding:6px 8px'>70%</td><td style='font-weight:600;padding:6px 8px;color:$lineColor;white-space:nowrap'>$lineLabel$alertBadge</td><td></td><td style='color:#605e5c;padding:6px 8px;font-size:12px'>$lineDesc</td><td style='text-align:right;font-weight:600;padding:6px 8px;white-space:nowrap;color:$lineColor'>$lineTB TB<br><span style='font-size:11px;color:#a19f9d;font-weight:400'>$lineTiB TiB</span></td></tr>"
                "$stageRow`n$lineRow"
            } else {
                $stageRow
            }
        }) -join "`n"
    }

    # ── Pool breakdown bar data ───────────────────────────────────────────────
    $poolBarDatasets  = ''
    $poolTotalTB      = 0
    $reserveTB        = 0
    $phUsed           = 0
    $phFree           = 0
    $phReserveOk      = 0
    $phReserveEaten   = 0
    $phOvercommit     = 0
    $phAvailLine      = 0
    if ($pool -and $vols) {
        $poolTotalTB = $pool.TotalSize.TB
        $reserveTB   = if ($wf) { [math]::Round($wf.ReserveRecommended.TB, 2) } else { 0 }
        $volColors   = @('#0078d4','#005a9e','#106ebe','#005b70','#00b7c3','#006f94','#4ba3c7','#00546e')
        $ci          = 0
        $dsLines     = @()

        foreach ($v in $vols) {
            $ftb   = if ($v.FootprintOnPool) { [math]::Round($v.FootprintOnPool.TB, 2) } else { 0 }
            $label = if ($v.IsInfrastructureVolume) { "$($v.FriendlyName) (infra) $ftb TB" } else { "$($v.FriendlyName) $ftb TB" }
            $color = if ($v.IsInfrastructureVolume) { '#008272' } else { $volColors[$ci % $volColors.Count]; $ci++ }
            $dsLines += "{ label: '$label', data: [$ftb], backgroundColor: '$color', borderWidth: 0 }"
        }

        $totalFootprintTB = [math]::Round(($vols | ForEach-Object { if ($_.FootprintOnPool) { $_.FootprintOnPool.TB } else { 0 } } | Measure-Object -Sum).Sum, 2)
        $freeTB           = [math]::Round([math]::Max(0, $poolTotalTB - $totalFootprintTB), 2)
        $overcommitTB     = [math]::Round([math]::Max(0, $totalFootprintTB - $poolTotalTB), 2)

        if ($freeTB -gt 0) {
            $dsLines += "{ label: 'Free $freeTB TB', data: [$freeTB], backgroundColor: '#dff6dd', borderWidth: 0 }"
        }
        if ($overcommitTB -gt 0) {
            $dsLines += "{ label: 'Overcommit $overcommitTB TB', data: [$overcommitTB], backgroundColor: '#d13438', borderWidth: 0 }"
        }

        $poolBarDatasets = $dsLines -join ','

        # Pool health bar segments
        $availForVols      = [math]::Round([math]::Max(0, $poolTotalTB - $reserveTB), 2)
        $phUsed            = [math]::Round([math]::Min($totalFootprintTB, $availForVols), 2)
        $phFree            = [math]::Round([math]::Max(0, $availForVols - $totalFootprintTB), 2)
        $eatIntoReserve    = [math]::Round([math]::Max(0, $totalFootprintTB - $availForVols), 2)
        $phReserveOk       = [math]::Round([math]::Max(0, $reserveTB - $eatIntoReserve), 2)
        $phReserveEaten    = [math]::Round([math]::Min($reserveTB, $eatIntoReserve), 2)
        $phOvercommit      = [math]::Round([math]::Max(0, $totalFootprintTB - $poolTotalTB), 2)
        $phAvailLine       = $availForVols
    }

    # ── Disk inventory table rows ─────────────────────────────────────────────
    $diskRows = ($disks | ForEach-Object {
        $hw = if ($_.WearPercentage -gt 80) { ' style="color:#d13438"' } else { '' }
        $hs = if ($_.HealthStatus -eq 'Healthy') { '<span class="badge ok">Healthy</span>' } else { "<span class='badge fail'>$($_.HealthStatus)</span>" }
        "<tr><td>$($_.NodeName)</td><td>$($_.FriendlyName)</td><td>$($_.MediaType)</td><td>$($_.Role)</td><td>$(if($_.Size){"$($_.Size.TiB) TiB ($($_.Size.TB) TB)"}else{'N/A'})</td><td$hw>$(if($null -ne $_.WearPercentage){"$($_.WearPercentage)%"}else{'N/A'})</td><td>$hs</td></tr>"
    }) -join "`n"

    # ── Thin provisioning risk KPI ────────────────────────────────────────────
    $thinVols = @($vols | Where-Object { -not $_.IsInfrastructureVolume -and $_.ProvisioningType -eq 'Thin' })
    $thinKpiHtml = ''
    if ($thinVols.Count -gt 0 -and $pool -and $pool.TotalSize) {
        $maxPotBytes = [int64](($thinVols | ForEach-Object { if ($_.MaxPotentialFootprint) { $_.MaxPotentialFootprint.Bytes } else { 0 } } | Measure-Object -Sum).Sum)
        $thinRiskPct = [math]::Round($maxPotBytes / $pool.TotalSize.Bytes * 100, 1)
        $thinKpiClass = if ($thinRiskPct -gt 100) { ' critical' } elseif ($thinRiskPct -gt 80) { ' warn' } else { '' }
        $thinKpiStyle = if ($thinRiskPct -gt 100) { '' } elseif ($thinRiskPct -gt 80) { 'style="background:#fff4ce;border-color:#e8a218" ' } else { '' }
        $thinKpiHtml = "<div class='kpi$thinKpiClass' $thinKpiStyle><div class='val'>$thinRiskPct%</div><div class='lbl'>Thin Provision Risk</div></div>"
    }

    # ── 70% line KPI (Executive Summary) ──────────────────────────────────────
    # The 70% line is a thin-provisioning headroom guideline, NOT a current-health metric and NOT a
    # Microsoft hard limit. Surface it in the Executive Summary health band ONLY when thin volumes are
    # present (where a full pool takes thin volumes offline). For fixed-provisioned clusters the figure
    # still lives in the Capacity Model waterfall + headroom table below — it just no longer competes
    # with health signals up top.
    $kpi70Html = ''
    if ($hasThinVolumes -and $wf -and $wf.PlanningLine70Pct) {
        $kpi70Cls  = if ($wf.IsAbove70PctLine) { ' warn' } else { '' }
        $kpi70Html = "<div class='kpi$kpi70Cls'><div class='val'>$($wf.PlanningLine70Pct.TiB) TiB</div><div class='lbl'>70% Planning Line — footprint</div></div>"
    }

    # ── Volume table rows ─────────────────────────────────────────────────────
    $volRows = ($vols | ForEach-Object {
        $infraTag = if ($_.IsInfrastructureVolume) { ' <span class="badge info">Infra</span>' } else { '' }
        $hs = if ($_.HealthStatus -eq 'Healthy') { '<span class="badge ok">Healthy</span>' } else { "<span class='badge fail'>$($_.HealthStatus)</span>" }
        $thinCells = if ($_.ProvisioningType -eq 'Thin') {
            $headroom = if ($_.ThinGrowthHeadroom) { "$([math]::Round($_.ThinGrowthHeadroom.TiB,2)) TiB" } else { 'N/A' }
            $maxFp    = if ($_.MaxPotentialFootprint) { "$([math]::Round($_.MaxPotentialFootprint.TiB,2)) TiB" } else { 'N/A' }
            "<td>$headroom</td><td>$maxFp</td>"
        } else { "<td style='color:#a19f9d'>—</td><td style='color:#a19f9d'>—</td>" }
        "<tr><td>$($_.FriendlyName)$infraTag</td><td>$($_.ResiliencySettingName) ($($_.NumberOfDataCopies) copies)</td><td>$(if($_.Size){"$($_.Size.TiB) TiB"}else{'N/A'})</td><td>$(if($_.FootprintOnPool){"$($_.FootprintOnPool.TiB) TiB"}else{'N/A'})</td><td>$($_.EfficiencyPercent)%</td><td>$($_.ProvisioningType)</td>$thinCells<td>$hs</td></tr>"
    }) -join "`n"

    # Compute Maintenance Reserve (N+1/N+2) context box removed from the HTML report (v1.9.1):
    # N+1/N+2 is a COMPUTE resiliency concept (reserve a node's worth of CPU+RAM for maintenance),
    # not a storage figure, so it added no value to a storage-capacity audit and confused readers —
    # half the box was spent explaining why it is NOT a storage reserve. The MaintenanceReserveN1
    # health check (Info severity) still carries the advisory in Health Checks, and the
    # MaintenanceReserveAssessment object remains on $ClusterData for Surveyor's planning deductions.

    # ── Expansion headroom table + chart data ────────────────────────────────
    $eh = $ClusterData.ExpansionHeadroom
    $ehCurrentPct   = if ($eh) { $eh.CurrentUtilizationPct } else { 0 }
    $ehCopies       = if ($eh) { $eh.PrevalentDataCopies }   else { 2 }
    # $hasThinVolumes is already computed from $vols above — reuse for headroom table too.
    $ehTableRows    = ''
    $ehChartLabels  = ''
    $ehChartTB      = ''
    $ehChartTiB     = ''
    if ($eh -and $eh.Thresholds) {
        $ehTableRows = ($eh.Thresholds | ForEach-Object {
            $t = $_
            $rowStyle  = if ($t.IsRecommendedPlanningLine) { " style='background:#fffde7'" } else { '' }
            $planBadge = if ($t.IsRecommendedPlanningLine) {
                if ($hasThinVolumes) {
                    " <span style='font-size:10px;background:#fff4ce;color:#d47a00;border-radius:3px;padding:1px 6px;margin-left:4px;font-weight:700'>Planning line — thin volumes present</span>"
                } else {
                    " <span style='font-size:10px;background:#eff6fc;color:#0078d4;border-radius:3px;padding:1px 6px;margin-left:4px;font-weight:500'>Advisory — fixed volumes commit footprint up front</span>"
                }
            } else { '' }
            $pastBadge = if ($t.IsPastLine) {
                " <span style='font-size:10px;background:#fde7e9;color:#d13438;border-radius:3px;padding:1px 6px;margin-left:4px;font-weight:700'>PAST</span>"
            } else { '' }
            $budgetStr   = "$($t.FootprintBudget.TB) TB / $($t.FootprintBudget.TiB) TiB"
            $remainFPStr = "$($t.RemainingFootprint.TB) TB / $($t.RemainingFootprint.TiB) TiB"
            $remainDStr  = "$($t.NewUsableData.TB) TB / $($t.NewUsableData.TiB) TiB"
            # Part B: SizeToEnterTiB — value to type into New-Volume -Size or WAC.
            # Null-safe: older JSON snapshots may not carry this property.
            $steProp = $t.PSObject.Properties['SizeToEnterTiB']
            $steStr = if ($t.IsPastLine -or $null -eq $steProp) {
                "<span style='color:#a19f9d'>&#x2014;</span>"
            } else {
                "<strong>$($steProp.Value)TB</strong>"
            }
            "<tr$rowStyle><td style='font-weight:700'>$($t.FillTargetPct)%$planBadge$pastBadge</td><td>$budgetStr</td><td>$remainFPStr</td><td>$remainDStr</td><td style='text-align:center'>$steStr</td></tr>"
        }) -join "`n"

        $ehChartLabels = ($eh.Thresholds | ForEach-Object { "'$($_.FillTargetPct)%'" }) -join ','
        $ehChartTB     = ($eh.Thresholds | ForEach-Object { [math]::Round($_.NewUsableData.TB,  2) }) -join ','
        $ehChartTiB    = ($eh.Thresholds | ForEach-Object { [math]::Round($_.NewUsableData.TiB, 2) }) -join ','
    }

    # ── Health check cards ────────────────────────────────────────────────────
    $hcCards = ($hc | ForEach-Object {
        $cls = switch ($_.Status) { 'Pass'{'hc-pass'} 'Warn'{'hc-warn'} 'Fail'{'hc-fail'} default{'hc-info'} }
        $icon = switch ($_.Status) { 'Pass'{'✔'} 'Warn'{'⚠'} 'Fail'{'✖'} default{'ℹ'} }
        "<div class='hc-card $cls'><span class='hc-icon'>$icon</span><div class='hc-body'><strong>$($_.CheckName)</strong> <em>[$($_.Severity)]</em><p>$([System.Net.WebUtility]::HtmlEncode($_.Details))</p>$(if($_.Status -ne 'Pass'){"<p class='remediation'><strong>Remediation:</strong> $([System.Net.WebUtility]::HtmlEncode($_.Remediation))</p>"})</div></div>"
    }) -join "`n"

    # ── Cache tier summary ────────────────────────────────────────────────────
    $cacheSummary = if ($cache) {
        $allFlashTag = if ($cache.IsAllFlash) { '<span class="badge info">All-Flash</span>' } else { '' }
        "<p><strong>Cache Mode:</strong> $($cache.CacheMode) $allFlashTag &nbsp; <strong>State:</strong> $($cache.CacheState) &nbsp; <strong>Disks:</strong> $($cache.CacheDiskCount)</p>"
    } else { '<p>Cache data not available.</p>' }

    $poolSummary = if ($pool) {
        # AB#4645: show both TiB (binary, Windows-reported) and TB (decimal, vendor label) for every pool figure.
        # "Overcommit" only applies when provisioned capacity exceeds the pool total (ratio > 1.0x) — the
        # thin-provisioning case where writes can fail. Below 1.0x the pool is UNDER-committed; printing
        # "Overcommit: 0.24x" on a healthy, lightly-provisioned pool reads as a false alarm. Show a neutral
        # provisioning percentage instead, and flag (red) only genuine overcommit.
        $provDisplay = if ($pool.OvercommitRatio -gt 1.0) {
            "<strong style='color:var(--red)'>Overcommit:</strong> $($pool.OvercommitRatio)x"
        } else {
            "<strong>Provisioned:</strong> $([math]::Round($pool.OvercommitRatio * 100, 1))% of pool <span style='color:var(--green)'>(within capacity)</span>"
        }
        "<p><strong>Pool:</strong> $($pool.FriendlyName) &nbsp; <strong>Health:</strong> $($pool.HealthStatus) &nbsp; <strong>Total:</strong> $($pool.TotalSize.TiB) TiB / $($pool.TotalSize.TB) TB &nbsp; <strong>Allocated:</strong> $($pool.AllocatedSize.TiB) TiB / $($pool.AllocatedSize.TB) TB &nbsp; <strong>Free:</strong> $($pool.RemainingSize.TiB) TiB / $($pool.RemainingSize.TB) TB &nbsp; $provDisplay</p>"
    } else { '<p>Pool data not available.</p>' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>S2D Cartographer — $cn</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
:root{--blue:#0078d4;--teal:#008272;--green:#107c10;--amber:#e8a218;--red:#d13438;--bg:#faf9f8;--card:#ffffff;--border:#edebe9;--text:#201f1e;--muted:#605e5c}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:var(--bg);color:var(--text);font-size:14px}
header{background:var(--blue);color:white;padding:20px 32px;display:flex;justify-content:space-between;align-items:center}
header h1{font-size:22px;font-weight:600}
header .meta{font-size:12px;opacity:.85;text-align:right}
.container{max-width:1200px;margin:0 auto;padding:24px}
.section{background:var(--card);border:1px solid var(--border);border-radius:6px;margin-bottom:20px;padding:20px}
.section h2{font-size:16px;font-weight:600;margin-bottom:12px;padding-bottom:8px;border-bottom:2px solid var(--blue);color:var(--blue)}
.overview-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:16px}
.kpi{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:14px;text-align:center}
.kpi .val{font-size:22px;font-weight:700;color:var(--blue)}
.kpi .lbl{font-size:11px;color:var(--muted);margin-top:4px}
.kpi.critical{background:#fde7e9;border-color:#d13438}.kpi.critical .val{color:#d13438}.kpi.critical .lbl{color:#d13438}
.kpi.warn{background:#fff4ce;border-color:#e8a218}.kpi.warn .val{color:#d47a00}.kpi.warn .lbl{color:#d47a00}
.health-banner{border-radius:6px;padding:12px 20px;margin-bottom:16px;font-weight:600;font-size:15px;background:$overallBg;color:$overallFg}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#f3f2f1;text-align:left;padding:8px 10px;font-weight:600;border-bottom:2px solid var(--border)}
td{padding:7px 10px;border-bottom:1px solid var(--border)}
tr:hover{background:#f3f2f1}
.badge{display:inline-block;border-radius:4px;padding:2px 7px;font-size:11px;font-weight:600}
.badge.ok{background:#dff6dd;color:#107c10}.badge.fail{background:#fde7e9;color:#d13438}.badge.info{background:#eff6fc;color:#0078d4}
.hc-card{display:flex;align-items:flex-start;gap:12px;border-radius:6px;padding:12px 16px;margin-bottom:8px;border-left:4px solid}
.hc-pass{background:#dff6dd;border-color:#107c10}.hc-warn{background:#fff4ce;border-color:#e8a218}.hc-fail{background:#fde7e9;border-color:#d13438}.hc-info{background:#eff6fc;border-color:#0078d4}
.hc-icon{font-size:20px;min-width:24px}.hc-body strong{font-size:13px}.hc-body p{font-size:12px;color:var(--muted);margin-top:4px}.remediation{color:#323130 !important;font-style:italic}
.toggle-row{display:flex;align-items:center;gap:10px;margin-bottom:12px;font-size:13px}
.toggle-btn{background:var(--blue);color:white;border:none;border-radius:4px;padding:5px 14px;cursor:pointer;font-size:12px}
.chart-wrap{position:relative;height:300px}
.tib-tb-table{font-size:13px}
.tib-tb-table th,.tib-tb-table td{padding:6px 14px}
@media print{.toggle-row{display:none}}
</style>
</head>
<body>
<header>
  <div>
    <h1>S2D Cartographer Report</h1>
    <div style="font-size:13px;opacity:.9">$cn &nbsp;|&nbsp; $nc nodes</div>
  </div>
  <div class="meta">
    Generated: $generatedAt<br>
    $(if($Author){"By: $Author<br>"})$(if($Company){"$Company"})
  </div>
</header>
<div class="container">

<div class="section">
  <h2>Executive Summary</h2>
  <div class="health-banner">Overall Health: $oh</div>
  <div class="overview-grid">
    <div class="kpi"><div class="val">$nc</div><div class="lbl">Nodes</div></div>
    <div class="kpi"><div class="val">$(if($wf){"$($wf.RawCapacity.TiB) TiB"}else{'N/A'})</div><div class="lbl">Raw Capacity (binary)</div></div>
    <div class="kpi"><div class="val">$(if($wf){"$($wf.AvailableForVolumes.TiB) TiB"}else{'N/A'})</div><div class="lbl">Avail for Volumes — footprint</div></div>
    <div class="kpi"><div class="val">$(if($wf){"$($wf.UsableCapacity.TiB) TiB"}else{'N/A'})</div><div class="lbl">Usable Data — after resiliency</div></div>
    $kpi70Html
    <div class="kpi"><div class="val">$(if($pool){"$($pool.RemainingSize.TiB) TiB"}else{'N/A'})</div><div class="lbl">Pool Free (binary)</div></div>
    <div class="kpi"><div class="val">$($disks.Count)</div><div class="lbl">Physical Disks</div></div>
    <div class="kpi"><div class="val">$(@($vols | Where-Object { -not $_.IsInfrastructureVolume }).Count)</div><div class="lbl">Workload Volumes</div></div>
    <div class="kpi$(if($wf -and $wf.ReserveStatus -eq 'Critical'){' critical'}else{''})"><div class="val">$(if($wf){"$($wf.ReserveStatus)"}else{'N/A'})</div><div class="lbl">Reserve Status</div></div>
    <div class="kpi"><div class="val">$(if($wf){"$($wf.BlendedEfficiencyPercent)%"}else{'N/A'})</div><div class="lbl">Resiliency Efficiency</div></div>
    $thinKpiHtml
  </div>
  $poolSummary
  $cacheSummary
</div>

<div class="section">
  <h2>Capacity Model</h2>
  <p style="margin-bottom:14px;font-size:12px;color:var(--muted)">Theoretical pipeline showing how raw storage should be accounted for under S2D best practices. Each stage represents a recommended deduction. Actual provisioning state is in the Volume Map and Health Checks below. &nbsp;<a href="https://learn.microsoft.com/en-us/azure-stack/hci/concepts/plan-volumes" target="_blank" style="color:#0078d4">Microsoft S2D capacity planning docs &#8599;</a></p>
  <div class="toggle-row">
    <span>Display unit:</span>
    <button class="toggle-btn" onclick="toggleUnit()">Toggle TiB / TB</button>
    <span id="unitLabel" style="font-weight:600">TiB</span>
  </div>
  <div class="chart-wrap"><canvas id="waterfallChart"></canvas></div>
  <table style="margin-top:16px;font-size:13px;width:100%;border-collapse:collapse">
    <thead><tr style="background:#f3f2f1"><th style="padding:7px 8px;text-align:left;width:28px"></th><th style="padding:7px 8px;text-align:left;width:24px">#</th><th style="padding:7px 8px;text-align:left">Stage</th><th style="padding:7px 8px;text-align:right;color:#a19f9d;font-weight:500;width:90px">Deducted</th><th style="padding:7px 8px;text-align:left">What it represents</th><th style="padding:7px 8px;text-align:right">Remaining</th></tr></thead>
    <tbody>$wfDescRows</tbody>
  </table>
</div>

<div class="section">
  <h2>Pool Allocation Breakdown</h2>
  <p style="margin-bottom:12px;font-size:12px;color:var(--muted)">Single bar showing how the raw storage pool is carved up across volumes. The dashed amber line marks the recommended rebuild reserve boundary. Any bar extending past the pool total is overcommit (shown in red).</p>
  <div style="position:relative;height:180px"><canvas id="poolBreakdownChart"></canvas></div>
</div>

<div class="section">
  <h2>Storage Pool Health</h2>
  <p style="margin-bottom:16px;font-size:12px;color:var(--muted)">The bar represents the full pool. The amber zone on the right is the recommended rebuild reserve — S2D needs this space free to auto-repair after a drive failure. If workload volumes eat into that zone it turns red. Any portion beyond the pool total is overcommit.</p>
  <div style="position:relative;height:130px"><canvas id="poolHealthChart"></canvas></div>
</div>

<div class="section">
  <h2>Physical Disk Inventory</h2>
  <table id="diskTable">
    <thead><tr><th>Node</th><th>Model</th><th>Media</th><th>Role</th><th>Size</th><th>Wear %</th><th>Health</th></tr></thead>
    <tbody>$diskRows</tbody>
  </table>
</div>

<div class="section">
  <h2>Volume Map</h2>
  <table>
    <thead><tr><th>Volume</th><th>Resiliency</th><th>Size</th><th>Pool Footprint</th><th>Efficiency</th><th>Provisioning</th><th>Growth Headroom</th><th>Max Potential Footprint</th><th>Health</th></tr></thead>
    <tbody>$volRows</tbody>
  </table>
</div>

<div class="section">
  <h2>Expansion Headroom</h2>
  <p style="margin-bottom:12px;font-size:12px;color:var(--muted)">How much room remains to expand existing volumes or create new ones, measured against Available-for-Volumes (footprint basis). New-volume usable data assumes <strong>$ehCopies data copies</strong> (prevailing resiliency — assumed for estimates). Current pool utilization: <strong>$ehCurrentPct%</strong> of available-for-volumes.</p>
  <p style="margin-bottom:12px;font-size:12px;color:var(--muted)">70% is a recommended operational headroom guideline — mainly relevant for thin-provisioned volumes, where a full pool takes thin volumes offline. Not a Microsoft hard limit. The firm limits are footprints fitting the pool and the rebuild reserve staying intact.</p>
  <table style="margin-bottom:8px">
    <thead><tr style="background:#f3f2f1"><th>Fill target</th><th>Footprint budget (TB / TiB)</th><th>Remaining footprint (TB / TiB)</th><th>New usable data (TB / TiB)</th><th style="white-space:nowrap">Size to enter<br><span style="font-weight:400;font-size:11px">New-Volume / WAC</span></th></tr></thead>
    <tbody>$ehTableRows</tbody>
  </table>
  <p style="margin-bottom:16px;font-size:11px;color:var(--muted);font-style:italic">Size to enter is the value to type into New-Volume -Size or WAC. PowerShell and WAC read size suffixes as binary (1 TB = 1 TiB), so this equals the TiB column, rounded down so the new volume always fits.</p>
  <div style="position:relative;height:220px"><canvas id="ehChart"></canvas></div>
</div>

<div class="section">
  <h2>Health Checks</h2>
  $hcCards
</div>

<div class="section">
  <h2>Understanding Storage Units — TiB vs TB</h2>
  <p style="margin-bottom:12px;color:var(--muted)">Hard drive manufacturers use decimal (1 TB = 1,000,000,000,000 bytes). Windows reports in binary (1 TiB = 1,099,511,627,776 bytes). This creates an apparent ~9% discrepancy — the data is all there, it's just expressed in different units.</p>
  <table class="tib-tb-table">
    <thead><tr><th>Drive Label (TB)</th><th>Windows Reports (TiB)</th><th>Difference</th></tr></thead>
    <tbody>
      <tr><td>0.96 TB</td><td>0.873 TiB</td><td style="color:var(--red)">-9.3%</td></tr>
      <tr><td>1.92 TB</td><td>1.747 TiB</td><td style="color:var(--red)">-9.0%</td></tr>
      <tr><td>3.84 TB</td><td>3.492 TiB</td><td style="color:var(--red)">-9.1%</td></tr>
      <tr><td>7.68 TB</td><td>6.986 TiB</td><td style="color:var(--red)">-9.0%</td></tr>
      <tr><td>15.36 TB</td><td>13.97 TiB</td><td style="color:var(--red)">-9.1%</td></tr>
    </tbody>
  </table>
</div>

</div>
<script>
const tibValues        = [$wfValues];
// AB#263: authoritative TB values from PowerShell byte math — never use a JS approximation factor.
const tbValues         = [$wfTbValues];
const labels           = [$wfLabels];
// AB#4644: 70% planning line — 70% of Available-for-Volumes (footprint basis)
const planLine70TiB    = $wf70LineTiB;
const planLine70TB     = $wf70LineTB;
const above70PctLine   = $($wfAbove70Flag.ToString().ToLower());
let useTiB = true;

// AB#4644: chart plugin that draws the 70% planning line on the waterfall chart
const waterfallPlanLinePlugin = {
  id: 'waterfallPlanLine',
  afterDraw(chart) {
    const lineVal = useTiB ? planLine70TiB : planLine70TB;
    if (!lineVal) return;
    const ctx = chart.ctx, xScale = chart.scales.x;
    const px  = xScale.getPixelForValue(lineVal);
    ctx.save();
    ctx.strokeStyle = above70PctLine ? '#d13438' : '#e8a218';
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.moveTo(px, chart.chartArea.top - 4);
    ctx.lineTo(px, chart.chartArea.bottom + 4);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = above70PctLine ? '#d13438' : '#e8a218';
    ctx.font = 'bold 11px Segoe UI,Arial,sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('70% of avail-for-vols' + (above70PctLine ? ' ⚠' : ''), px, chart.chartArea.top - 8);
    ctx.restore();
  }
};

const ctx = document.getElementById('waterfallChart').getContext('2d');
const chart = new Chart(ctx, {
  type: 'bar',
  data: {
    labels: labels,
    datasets: [{
      label: 'Capacity (TiB)',
      data: tibValues,
      backgroundColor: ['#0078d4','#005a9e','#106ebe','#e8a218','#d47a00','#107c10','#0e6e0e','#054b05'],
      borderRadius: 4
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    indexAxis: 'y',
    plugins: { legend: { display: false }, tooltip: { callbacks: { label: ctx => ctx.raw + (useTiB ? ' TiB' : ' TB') } } },
    scales: { x: { beginAtZero: true, title: { display: true, text: 'TiB' } } }
  },
  plugins: [waterfallPlanLinePlugin]
});

function toggleUnit() {
  useTiB = !useTiB;
  document.getElementById('unitLabel').textContent = useTiB ? 'TiB' : 'TB';
  chart.data.datasets[0].data = useTiB ? tibValues : tbValues;
  chart.data.datasets[0].label = useTiB ? 'Capacity (TiB)' : 'Capacity (TB)';
  chart.options.scales.x.title.text = useTiB ? 'TiB' : 'TB';
  chart.update();
}

// Pool breakdown bar
const poolTotalTB = $poolTotalTB;
const reserveTB   = $reserveTB;
const reserveLine = {
  id: 'reserveLine',
  afterDraw(chart) {
    if (!poolTotalTB) return;
    const ctx = chart.ctx;
    const xScale = chart.scales.x;
    // Pool boundary line (solid red if overcommitted, solid gray otherwise)
    const boundaryX = xScale.getPixelForValue(poolTotalTB);
    ctx.save();
    ctx.strokeStyle = '#323130';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(boundaryX, chart.chartArea.top - 4);
    ctx.lineTo(boundaryX, chart.chartArea.bottom + 4);
    ctx.stroke();
    ctx.fillStyle = '#323130';
    ctx.font = '11px Segoe UI,Arial,sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('Pool total', boundaryX, chart.chartArea.top - 8);
    // Reserve boundary line (dashed amber) — drawn at start-of-reserve zone, not at reserve size.
    // AB#264: the reserve zone begins at poolTotal - reserve, not at the reserve value itself.
    if (reserveTB > 0) {
      const reserveX = xScale.getPixelForValue(poolTotalTB - reserveTB);
      ctx.strokeStyle = '#e8a218';
      ctx.lineWidth = 2;
      ctx.setLineDash([5, 4]);
      ctx.beginPath();
      ctx.moveTo(reserveX, chart.chartArea.top - 4);
      ctx.lineTo(reserveX, chart.chartArea.bottom + 4);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = '#e8a218';
      ctx.textAlign = 'center';
      ctx.fillText('Reserve', reserveX, chart.chartArea.bottom + 14);
    }
    ctx.restore();
  }
};

const pbCtx = document.getElementById('poolBreakdownChart').getContext('2d');
new Chart(pbCtx, {
  type: 'bar',
  data: {
    labels: ['Pool'],
    datasets: [$poolBarDatasets]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    indexAxis: 'y',
    layout: { padding: { top: 20, bottom: 4 } },
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 14, font: { size: 11 } } },
      tooltip: { callbacks: { label: ctx => ctx.dataset.label } }
    },
    scales: {
      x: {
        stacked: true,
        beginAtZero: true,
        title: { display: true, text: 'TB' },
        grid: { color: '#edebe9' }
      },
      y: { stacked: true, display: false }
    }
  },
  plugins: [reserveLine]
});

// ── Storage Pool Health bar ───────────────────────────────────────────────
const ph = {
  used:          $phUsed,
  free:          $phFree,
  reserveOk:     $phReserveOk,
  reserveEaten:  $phReserveEaten,
  overcommit:    $phOvercommit,
  poolTotal:     $poolTotalTB,
  reserveLine:   $phAvailLine
};

function makeHazard(ctx) {
  const sz = 10;
  const c  = document.createElement('canvas');
  c.width  = sz; c.height = sz;
  const p  = c.getContext('2d');
  p.fillStyle = '#fde7e9';
  p.fillRect(0, 0, sz, sz);
  p.strokeStyle = '#d13438';
  p.lineWidth = 2.5;
  [[0, sz, sz, 0], [-sz * 0.5, sz * 0.5, sz * 0.5, -sz * 0.5], [sz * 0.5, sz * 1.5, sz * 1.5, sz * 0.5]].forEach(([x1,y1,x2,y2]) => {
    p.beginPath(); p.moveTo(x1, y1); p.lineTo(x2, y2); p.stroke();
  });
  return ctx.createPattern(c, 'repeat');
}

const phBoundaryPlugin = {
  id: 'phBoundary',
  afterDraw(chart) {
    const ctx = chart.ctx, x = chart.scales.x, top = chart.chartArea.top, bot = chart.chartArea.bottom;
    const drawLine = (val, color, dash, label, labelPos) => {
      const px = x.getPixelForValue(val);
      ctx.save();
      ctx.strokeStyle = color; ctx.lineWidth = 2;
      if (dash) ctx.setLineDash([5, 4]);
      ctx.beginPath(); ctx.moveTo(px, top - 6); ctx.lineTo(px, bot + 6); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = color; ctx.font = 'bold 11px Segoe UI,Arial,sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(label, px, labelPos === 'top' ? top - 10 : bot + 18);
      ctx.restore();
    };
    if (ph.reserveLine > 0) drawLine(ph.reserveLine, '#e8a218', true,  'Reserve starts', 'top');
    if (ph.poolTotal  > 0) drawLine(ph.poolTotal,  '#323130', false, 'Pool total',     'top');
  }
};

const phCtx = document.getElementById('poolHealthChart').getContext('2d');
const hazard = makeHazard(phCtx);
const phDatasets = [
  { label: 'Volumes  ' + ph.used + ' TB',            data: [ph.used],         backgroundColor: '#0078d4', borderWidth: 0 },
  { label: 'Free  '    + ph.free + ' TB',             data: [ph.free],         backgroundColor: '#dff6dd', borderWidth: 1, borderColor: '#107c10' },
  { label: 'Reserve — OK  ' + ph.reserveOk + ' TB',  data: [ph.reserveOk],    backgroundColor: '#e8a218', borderWidth: 0 },
  { label: 'Reserve — consumed  ' + ph.reserveEaten + ' TB', data: [ph.reserveEaten], backgroundColor: hazard, borderWidth: 0 },
  { label: 'Overcommit  ' + ph.overcommit + ' TB',   data: [ph.overcommit],   backgroundColor: '#a80000', borderWidth: 0 }
].filter(d => d.data[0] > 0);

new Chart(phCtx, {
  type: 'bar',
  data: { labels: [''], datasets: phDatasets },
  options: {
    responsive: true, maintainAspectRatio: false,
    indexAxis: 'y',
    layout: { padding: { top: 28, bottom: 4, left: 4, right: 8 } },
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: ctx => ctx.dataset.label } }
    },
    scales: {
      x: {
        stacked: true, beginAtZero: true,
        // AB#264: include all segments in the max calc so Chart.js never clips the bar.
        // Previous formula omitted ph.free and ph.reserveOk, clipping healthy clusters.
        max: Math.ceil(Math.max(ph.poolTotal, ph.used + ph.free + ph.reserveOk + ph.reserveEaten + ph.overcommit) * 1.1),
        title: { display: true, text: 'TB' },
        grid: { color: '#edebe9' }
      },
      y: { stacked: true, display: false }
    }
  },
  plugins: [phBoundaryPlugin]
});

// ── Expansion Headroom chart ──────────────────────────────────────────────
(function() {
  const ehLabels  = [$ehChartLabels];
  const ehTB      = [$ehChartTB];
  const ehTiB     = [$ehChartTiB];
  const ehColors  = ['#107c10','#0078d4','#e8a218','#a19f9d'];
  const ehEl = document.getElementById('ehChart');
  if (!ehEl || !ehLabels.length) return;
  let ehUseTiB = false;  // default TB for this chart
  new Chart(ehEl.getContext('2d'), {
    type: 'bar',
    data: {
      labels: ehLabels,
      datasets: [{
        label: 'New usable data remaining (TB)',
        data: ehTB,
        backgroundColor: ehColors,
        borderRadius: 4
      }]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: ctx => ctx.raw + (ehUseTiB ? ' TiB' : ' TB') + ' new usable data' } },
        title: { display: true, text: 'New usable data capacity remaining at each fill threshold', font: { size: 12 }, color: '#605e5c', padding: { bottom: 8 } }
      },
      scales: {
        y: { beginAtZero: true, title: { display: true, text: 'TB' }, grid: { color: '#edebe9' } },
        x: { grid: { display: false } }
      }
    }
  });
})();

// Custom legend for pool health bar
(function() {
  const wrap = document.getElementById('poolHealthChart').parentElement;
  const leg  = document.createElement('div');
  leg.style.cssText = 'display:flex;flex-wrap:wrap;gap:16px;margin-top:8px;font-size:12px;align-items:center';
  const items = [
    { color: '#0078d4', label: 'Volumes used' },
    { color: '#dff6dd', label: 'Free', border: '#107c10' },
    { color: '#e8a218', label: 'Reserve — intact' },
    { color: '#d13438', label: 'Reserve — consumed', hazard: true },
    { color: '#a80000', label: 'Overcommit (past pool total)' }
  ];
  const phMap = { 'Volumes used': ph.used, 'Free': ph.free, 'Reserve — intact': ph.reserveOk, 'Reserve — consumed': ph.reserveEaten, 'Overcommit (past pool total)': ph.overcommit };
  items.filter(i => phMap[i.label] > 0).forEach(i => {
    const d = document.createElement('div');
    d.style.cssText = 'display:flex;align-items:center;gap:6px';
    const swatch = document.createElement('div');
    swatch.style.cssText = 'width:14px;height:14px;border-radius:2px;flex-shrink:0';
    if (i.hazard) {
      swatch.style.background = 'repeating-linear-gradient(45deg,#fde7e9 0px,#fde7e9 4px,#d13438 4px,#d13438 7px)';
    } else {
      swatch.style.background = i.color;
      if (i.border) swatch.style.border = '1px solid ' + i.border;
    }
    d.appendChild(swatch);
    d.appendChild(Object.assign(document.createElement('span'), { textContent: i.label + '  ' + phMap[i.label] + ' TB' }));
    leg.appendChild(d);
  });
  wrap.appendChild(leg);
})();
</script>
</body>
</html>
"@

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $html | Set-Content -Path $OutputPath -Encoding UTF8 -Force
    Write-Verbose "HTML report written to $OutputPath"
    $OutputPath
}
