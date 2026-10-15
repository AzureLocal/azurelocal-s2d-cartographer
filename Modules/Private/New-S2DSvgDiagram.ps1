# SVG diagram generation engine for S2DCartographer

function New-S2DWaterfallSvg {
    param([S2DCapacityWaterfall]$Waterfall, [string]$PrimaryUnit = 'TiB')

    $w = 900
    $barH = 36; $barGap = 10; $leftPad = 220; $rightPad = 20; $topPad = 60; $legendH = 50

    $colors = @{
        'Raw Physical'          = '#0078d4'
        'Vendor Label (TB)'     = '#005a9e'
        'Pool (after overhead)' = '#106ebe'
        'After Reserve'         = '#e8a218'
        'After Infra Volume'    = '#d47a00'
        'Available'             = '#107c10'
        'After Resiliency'      = '#0e6e0e'
        'Final Usable'          = '#054b05'
    }

    $maxBytes = $Waterfall.RawCapacity.Bytes
    $chartW   = $w - $leftPad - $rightPad

    $bars = ''
    $i = 0
    foreach ($stage in $Waterfall.Stages) {
        $y     = $topPad + $i * ($barH + $barGap)
        $bytes = if ($stage.Size) { $stage.Size.Bytes } else { 0 }
        $pct   = if ($maxBytes -gt 0) { $bytes / $maxBytes } else { 0 }
        $bw    = [math]::Max(2, [int]($chartW * $pct))
        $color = if ($colors.ContainsKey($stage.Name)) { $colors[$stage.Name] } else { '#888888' }
        $label = if ($PrimaryUnit -eq 'TiB') { "$($stage.Size.TiB) TiB" } else { "$($stage.Size.TB) TB" }
        $statusMark = if ($stage.Status -eq 'Warning') { ' ⚠' } elseif ($stage.Status -eq 'Critical') { ' ✖' } else { '' }

        $bars += @"
    <g>
      <text x="$($leftPad - 8)" y="$($y + $barH/2 + 5)" text-anchor="end" font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">Stage $($stage.Stage): $($stage.Name)</text>
      <rect x="$leftPad" y="$y" width="$bw" height="$barH" fill="$color" rx="3"/>
      <text x="$($leftPad + $bw + 6)" y="$($y + $barH/2 + 5)" font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">$label$statusMark</text>
    </g>
"@
        $i++
    }

    $svgH = $topPad + $i * ($barH + $barGap) + $legendH
    @"
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$svgH" viewBox="0 0 $w $svgH">
  <rect width="$w" height="$svgH" fill="#faf9f8" rx="8"/>
  <text x="$(($w/2))" y="36" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="600" fill="#201f1e">S2D Capacity Waterfall</text>
  <line x1="$leftPad" y1="$topPad" x2="$leftPad" y2="$($topPad + $i * ($barH + $barGap))" stroke="#c8c6c4" stroke-width="1"/>
$bars
  <text x="$($w/2)" y="$($svgH - 12)" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#605e5c">Raw: $($Waterfall.RawCapacity.TiB) TiB | Usable: $($Waterfall.UsableCapacity.TiB) TiB | Reserve: $($Waterfall.ReserveStatus) | Efficiency: $($Waterfall.BlendedEfficiencyPercent)%</text>
</svg>
"@
}

function New-S2DDiskNodeMapSvg {
    param([object[]]$PhysicalDisks)

    $nodeGroups = @($PhysicalDisks | Group-Object NodeName)
    $nodeCount  = $nodeGroups.Count
    $nodeW = 200; $nodeGap = 20; $diskH = 28; $diskGap = 4
    $headerH = 40; $footerH = 30; $padH = 16; $padW = 12

    $diskColors = @{
        Cache    = '#0078d4'  # blue
        Capacity = '#008272'  # teal
        Unknown  = '#8a8886'  # gray
    }
    $healthAlert = '#d13438'  # red for unhealthy

    $totalW = $nodeCount * $nodeW + ($nodeCount - 1) * $nodeGap + 40
    $maxDisksPerNode = ($nodeGroups | ForEach-Object { $_.Group.Count } | Measure-Object -Maximum).Maximum
    $nodeH = $headerH + $padH + $maxDisksPerNode * ($diskH + $diskGap) + $footerH

    $nodes = ''
    $ni = 0
    foreach ($group in $nodeGroups) {
        $nx = 20 + $ni * ($nodeW + $nodeGap)
        $nodes += "<rect x='$nx' y='20' width='$nodeW' height='$nodeH' fill='#f3f2f1' stroke='#c8c6c4' stroke-width='1.5' rx='6'/>"
        $shortName = $group.Name -replace '\..*$', ''
        $nodes += "<text x='$($nx + $nodeW/2)' y='46' text-anchor='middle' font-family='Segoe UI,Arial,sans-serif' font-size='13' font-weight='600' fill='#201f1e'>$shortName</text>"

        $di = 0
        foreach ($disk in $group.Group) {
            $dy     = 20 + $headerH + $padH + $di * ($diskH + $diskGap)
            $role   = if ($disk.PSObject.Properties['Role']) { $disk.Role } else { 'Unknown' }
            $isUnhealthy = $disk.HealthStatus -ne 'Healthy'
            $color  = if ($isUnhealthy) { $healthAlert } elseif ($diskColors.ContainsKey($role)) { $diskColors[$role] } else { $diskColors['Unknown'] }
            $sizeLabel = if ($disk.Size) { $disk.Size.TB.ToString('N2') + 'TB' } else { '' }
            $nodes += "<rect x='$($nx+$padW)' y='$dy' width='$($nodeW - 2*$padW)' height='$diskH' fill='$color' rx='3'/>"
            $nodes += "<text x='$($nx+$padW+6)' y='$($dy+$diskH/2+5)' font-family='Segoe UI,Arial,sans-serif' font-size='10' fill='white'>$($disk.MediaType) $sizeLabel</text>"
            $di++
        }

        $totalCap = [math]::Round(($group.Group | Where-Object { $_.SizeBytes } | Measure-Object -Property SizeBytes -Sum).Sum / 1TB, 1)
        $nodes += "<text x='$($nx + $nodeW/2)' y='$($20 + $nodeH - 10)' text-anchor='middle' font-family='Segoe UI,Arial,sans-serif' font-size='11' fill='#323130'>Total: $totalCap TB</text>"
        $ni++
    }

    $svgH = $nodeH + 80
    @"
<svg xmlns="http://www.w3.org/2000/svg" width="$totalW" height="$svgH" viewBox="0 0 $totalW $svgH">
  <rect width="$totalW" height="$svgH" fill="#ffffff" rx="8"/>
  <text x="$($totalW/2)" y="16" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="600" fill="#201f1e">Disk-to-Node Map</text>
$nodes
  <g transform="translate(20,$($svgH-28))">
    <rect width="14" height="14" fill="#0078d4" rx="2"/><text x="18" y="11" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#323130">Cache</text>
    <rect x="70" width="14" height="14" fill="#008272" rx="2"/><text x="88" y="11" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#323130">Capacity</text>
    <rect x="150" width="14" height="14" fill="#d13438" rx="2"/><text x="168" y="11" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#323130">Unhealthy</text>
  </g>
</svg>
"@
}

function New-S2DPoolLayoutSvg {
    param([S2DStoragePool]$Pool, [S2DCapacityWaterfall]$Waterfall, [object[]]$Volumes)

    $w = 600; $h = 400; $cx = 200; $cy = 200; $r = 160

    $totalBytes    = if ($Pool.TotalSize)  { $Pool.TotalSize.Bytes }  else { 1 }
    $infraBytes    = [int64](($Volumes | Where-Object IsInfrastructureVolume | ForEach-Object { if($_.FootprintOnPool){$_.FootprintOnPool.Bytes}else{0} } | Measure-Object -Sum).Sum)
    $workloadBytes = [int64](($Volumes | Where-Object { -not $_.IsInfrastructureVolume } | ForEach-Object { if($_.FootprintOnPool){$_.FootprintOnPool.Bytes}else{0} } | Measure-Object -Sum).Sum)
    $reserveBytes  = if ($Waterfall.ReserveRecommended) { $Waterfall.ReserveRecommended.Bytes } else { 0 }
    $freeBytes     = [math]::Max(0, $totalBytes - $workloadBytes - $infraBytes - $reserveBytes)

    function local:Slice { param($start, $end, $color, $label)
        $sa = ($start / $totalBytes) * 2 * [math]::PI - [math]::PI/2
        $ea = ($end   / $totalBytes) * 2 * [math]::PI - [math]::PI/2
        $x1 = $cx + $r * [math]::Cos($sa); $y1 = $cy + $r * [math]::Sin($sa)
        $x2 = $cx + $r * [math]::Cos($ea); $y2 = $cy + $r * [math]::Sin($ea)
        $large = if (($end - $start) / $totalBytes -gt 0.5) { 1 } else { 0 }
        "<path d='M $cx $cy L $([math]::Round($x1,1)) $([math]::Round($y1,1)) A $r $r 0 $large 1 $([math]::Round($x2,1)) $([math]::Round($y2,1)) Z' fill='$color'/>"
    }

    $slices = ''
    $pos = 0
    $slices += Slice $pos ($pos + $workloadBytes) '#0078d4' 'Workload'; $pos += $workloadBytes
    $slices += Slice $pos ($pos + $reserveBytes)  '#e8a218' 'Reserve';  $pos += $reserveBytes
    $slices += Slice $pos ($pos + $infraBytes)    '#d47a00' 'Infra';    $pos += $infraBytes
    $slices += Slice $pos ($pos + $freeBytes)     '#c8c6c4' 'Free'

    $wl  = [math]::Round($workloadBytes/1TB, 1); $rv = [math]::Round($reserveBytes/1TB, 1)
    $inf = [math]::Round($infraBytes/1TB,    1); $fr = [math]::Round($freeBytes/1TB,    1)

    @"
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">
  <rect width="$w" height="$h" fill="#faf9f8" rx="8"/>
  <text x="$($w/2)" y="28" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="600" fill="#201f1e">Storage Pool Layout</text>
$slices
  <circle cx="$cx" cy="$cy" r="70" fill="white"/>
  <text x="$cx" y="$($cy-10)" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="#201f1e">$($Pool.FriendlyName)</text>
  <text x="$cx" y="$($cy+10)" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#605e5c">$([math]::Round($totalBytes/1TB,1)) TB</text>
  <g transform="translate(410,80)">
    <rect y="0"  width="14" height="14" fill="#0078d4" rx="2"/><text x="18" y="11"  font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">Workload $wl TB</text>
    <rect y="24" width="14" height="14" fill="#e8a218" rx="2"/><text x="18" y="35"  font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">Reserve $rv TB</text>
    <rect y="48" width="14" height="14" fill="#d47a00" rx="2"/><text x="18" y="59"  font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">Infra $inf TB</text>
    <rect y="72" width="14" height="14" fill="#c8c6c4" rx="2"/><text x="18" y="83"  font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#323130">Free $fr TB</text>
  </g>
</svg>
"@
}

function New-S2DHealthScorecardSvg {
    param([S2DHealthCheck[]]$HealthChecks, [string]$OverallHealth = 'Unknown')

    $colors = @{ Pass='#107c10'; Warn='#e8a218'; Fail='#d13438'; Unknown='#8a8886' }
    $bgColors = @{ Pass='#dff6dd'; Warn='#fff4ce'; Fail='#fde7e9'; Unknown='#f3f2f1' }
    $overallColor = switch ($OverallHealth) { 'Healthy'{'#107c10'} 'Warning'{'#e8a218'} 'Critical'{'#d13438'} default{'#8a8886'} }

    $cardW = 820; $cardH = 60; $cardGap = 8; $padX = 20; $topPad = 80

    $cards = ''
    $i = 0
    foreach ($check in $HealthChecks) {
        $y      = $topPad + $i * ($cardH + $cardGap)
        $status = if ($check.Status -eq 'Warn') { 'Warn' } else { $check.Status }
        $c      = if ($colors.ContainsKey($status))   { $colors[$status]   } else { $colors['Unknown'] }
        $bg     = if ($bgColors.ContainsKey($status)) { $bgColors[$status] } else { $bgColors['Unknown'] }
        $icon   = switch ($status) { 'Pass'{'✔'} 'Warn'{'⚠'} 'Fail'{'✖'} default{'?'} }

        $cards += @"
  <rect x="$padX" y="$y" width="$cardW" height="$cardH" fill="$bg" stroke="$c" stroke-width="1.5" rx="4"/>
  <text x="$($padX+16)" y="$($y+24)" font-family="Segoe UI,Arial,sans-serif" font-size="16" fill="$c">$icon</text>
  <text x="$($padX+40)" y="$($y+22)" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="#201f1e">$($check.CheckName) <tspan font-weight="400" fill="#605e5c">[$($check.Severity)]</tspan></text>
  <text x="$($padX+40)" y="$($y+42)" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#323130">$([System.Security.SecurityElement]::Escape($(if($check.Details.Length -gt 100){$check.Details.Substring(0,97)+'...'}else{$check.Details})))</text>
"@
        $i++
    }

    $svgH = $topPad + $i * ($cardH + $cardGap) + 30
    @"
<svg xmlns="http://www.w3.org/2000/svg" width="860" height="$svgH" viewBox="0 0 860 $svgH">
  <rect width="860" height="$svgH" fill="#ffffff" rx="8"/>
  <text x="430" y="32" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="600" fill="#201f1e">Health Scorecard</text>
  <rect x="$padX" y="44" width="$cardW" height="28" fill="$overallColor" rx="4"/>
  <text x="430" y="63" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="white">Overall Health: $OverallHealth</text>
$cards
</svg>
"@
}

function New-S2DTiBTBReferenceSvg {
    $sizes = @(
        @{ TB='0.96'; TiB='0.873'; Diff='9.3%' }
        @{ TB='1.92'; TiB='1.747'; Diff='9.0%' }
        @{ TB='3.84'; TiB='3.492'; Diff='9.1%' }
        @{ TB='7.68'; TiB='6.986'; Diff='9.0%' }
        @{ TB='15.36'; TiB='13.97'; Diff='9.1%' }
        @{ TB='30.72'; TiB='27.94'; Diff='9.0%' }
    )

    $w = 600; $rowH = 36; $headerH = 80; $colX = @(30, 160, 300, 440)
    $svgH = $headerH + $sizes.Count * $rowH + 40

    $rows = ''
    $i = 0
    foreach ($s in $sizes) {
        $y  = $headerH + $i * $rowH
        $bg = if ($i % 2 -eq 0) { '#f3f2f1' } else { '#ffffff' }
        $rows += "<rect x='20' y='$y' width='560' height='$rowH' fill='$bg'/>"
        $rows += "<text x='$($colX[0]+8)' y='$($y+24)' font-family='Segoe UI,Arial,sans-serif' font-size='13' fill='#201f1e'>$($s.TB) TB</text>"
        $rows += "<text x='$($colX[1]+8)' y='$($y+24)' font-family='Segoe UI,Arial,sans-serif' font-size='13' fill='#201f1e'>$($s.TiB) TiB</text>"
        $rows += "<text x='$($colX[2]+8)' y='$($y+24)' font-family='Segoe UI,Arial,sans-serif' font-size='13' fill='#d13438'>-$($s.Diff)</text>"
        $i++
    }

    @"
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$svgH" viewBox="0 0 $w $svgH">
  <rect width="$w" height="$svgH" fill="#ffffff" rx="8"/>
  <text x="300" y="28" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="600" fill="#201f1e">TiB vs TB Reference</text>
  <text x="300" y="50" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="#605e5c">1 TB (decimal) = 0.909 TiB (binary). S2D reports in TiB; drives are labeled in TB.</text>
  <rect x="20" y="60" width="560" height="$rowH" fill="#0078d4" rx="4"/>
  <text x="$($colX[0]+8)" y="83" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="white">Drive Label (TB)</text>
  <text x="$($colX[1]+8)" y="83" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="white">Windows Sees (TiB)</text>
  <text x="$($colX[2]+8)" y="83" font-family="Segoe UI,Arial,sans-serif" font-size="13" font-weight="600" fill="white">Difference</text>
$rows
</svg>
"@
}

function New-S2DVolumeResiliencySvg {
    param([S2DVolume[]]$Volumes, [int]$NodeCount = 4)

    $workload = @($Volumes | Where-Object { -not $_.IsInfrastructureVolume })
    $rowH = 50; $headerH = 70; $w = 800
    $svgH = $headerH + $workload.Count * $rowH + 30

    $rows = ''
    $i = 0
    foreach ($vol in $workload) {
        $y   = $headerH + $i * $rowH
        $bg  = if ($i % 2 -eq 0) { '#f3f2f1' } else { '#ffffff' }
        $eff = "$($vol.EfficiencyPercent)%"
        $resType = switch ($vol.NumberOfDataCopies) {
            2 { if ($NodeCount -le 2) { 'Nested 2-Way Mirror' } else { '2-Way Mirror' } }
            3 { '3-Way Mirror' }
            default { "$($vol.ResiliencySettingName) ($($vol.NumberOfDataCopies) copies)" }
        }
        $sz = if ($vol.Size) { "$($vol.Size.TiB) TiB" } else { 'N/A' }
        $fp = if ($vol.FootprintOnPool) { "$($vol.FootprintOnPool.TiB) TiB" } else { 'N/A' }
        $healthColor = if ($vol.HealthStatus -eq 'Healthy') { '#107c10' } else { '#d13438' }

        $rows += "<rect x='10' y='$y' width='780' height='$rowH' fill='$bg'/>"
        $rows += "<text x='18' y='$($y+22)' font-family='Segoe UI,Arial,sans-serif' font-size='12' font-weight='600' fill='#201f1e'>$($vol.FriendlyName)</text>"
        $rows += "<text x='18' y='$($y+40)' font-family='Segoe UI,Arial,sans-serif' font-size='11' fill='#605e5c'>$resType | Size: $sz | Footprint: $fp | Efficiency: $eff | Prov: $($vol.ProvisioningType)</text>"
        $rows += "<circle cx='770' cy='$($y+25)' r='8' fill='$healthColor'/>"
        $i++
    }

    @"
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$svgH" viewBox="0 0 $w $svgH">
  <rect width="$w" height="$svgH" fill="#ffffff" rx="8"/>
  <text x="400" y="28" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="600" fill="#201f1e">Volume Resiliency Map</text>
  <rect x="10" y="40" width="780" height="$($rowH - 4)" fill="#0078d4" rx="4"/>
  <text x="18" y="62" font-family="Segoe UI,Arial,sans-serif" font-size="12" font-weight="600" fill="white">Volume Name | Resiliency | Size | Footprint | Efficiency | Provisioning</text>
$rows
</svg>
"@
}
