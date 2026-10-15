# What-if HTML report — before/after capacity waterfall comparison

function Export-S2DWhatIfHtmlReport {
    param(
        [Parameter(Mandatory)] [object] $Result,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $bwf  = $Result.BaselineWaterfall
    $pwf  = $Result.ProjectedWaterfall
    $ds   = @($Result.DeltaStages)
    $gen  = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $scen = $Result.ScenarioLabel

    # Chart data
    $bLabels  = ($bwf.Stages | ForEach-Object { "'$($_.Name)'" }) -join ','
    $bValues  = ($bwf.Stages | ForEach-Object { if ($_.Size) { [math]::Round($_.Size.TiB,2) } else { 0 } }) -join ','
    $pValues  = ($pwf.Stages | ForEach-Object { if ($_.Size) { [math]::Round($_.Size.TiB,2) } else { 0 } }) -join ','

    # Delta rows
    $deltaRows = ($ds | ForEach-Object {
        $sign  = if ($_.DeltaTiB -gt 0) { '+' } elseif ($_.DeltaTiB -lt 0) { '' } else { '±' }
        $color = if ($_.DeltaTiB -gt 0) { '#107c10' } elseif ($_.DeltaTiB -lt 0) { '#d13438' } else { '#605e5c' }
        "<tr><td style='font-weight:700;color:#0078d4'>$($_.Stage)</td><td style='font-weight:600'>$($_.Name)</td><td style='text-align:right'>$($_.BaselineTiB) TiB</td><td style='text-align:right'>$($_.ProjectedTiB) TiB</td><td style='text-align:right;font-weight:700;color:$color'>$sign$($_.DeltaTiB) TiB</td></tr>"
    }) -join "`n"

    $deltaUsableSign  = if ($Result.DeltaUsableTiB -gt 0) { '+' } elseif ($Result.DeltaUsableTiB -lt 0) { '' } else { '±' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>S2D Cartographer — What-If Analysis</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
:root{--blue:#0078d4;--green:#107c10;--red:#d13438;--amber:#e8a218;--bg:#faf9f8;--card:#fff;--border:#edebe9;--text:#201f1e;--muted:#605e5c}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:var(--bg);color:var(--text);font-size:14px}
header{background:var(--blue);color:white;padding:20px 32px;display:flex;justify-content:space-between;align-items:center}
header h1{font-size:22px;font-weight:600}
header .meta{font-size:12px;opacity:.85;text-align:right}
.container{max-width:1200px;margin:0 auto;padding:24px}
.section{background:var(--card);border:1px solid var(--border);border-radius:6px;margin-bottom:20px;padding:20px}
.section h2{font-size:16px;font-weight:600;margin-bottom:12px;padding-bottom:8px;border-bottom:2px solid var(--blue);color:var(--blue)}
.kpi-row{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:16px}
.kpi{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:14px 20px;text-align:center;min-width:140px}
.kpi .val{font-size:22px;font-weight:700;color:var(--blue)}.kpi .lbl{font-size:11px;color:var(--muted);margin-top:4px}
.kpi.positive .val{color:var(--green)}.kpi.negative .val{color:var(--red)}
.scenario-badge{display:inline-block;background:#eff6fc;color:#0078d4;border:1px solid #c7e0f4;border-radius:4px;padding:4px 12px;font-size:13px;font-weight:600;margin-bottom:16px}
.chart-grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}
.chart-wrap{position:relative;height:320px}
.chart-label{font-size:12px;font-weight:600;color:var(--muted);margin-bottom:8px;text-transform:uppercase;letter-spacing:.5px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#f3f2f1;text-align:left;padding:8px 10px;font-weight:600;border-bottom:2px solid var(--border)}
td{padding:7px 10px;border-bottom:1px solid var(--border)}
tr:hover{background:#f3f2f1}
.delta-summary{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:16px;margin-bottom:16px;display:flex;gap:32px;align-items:center}
</style>
</head>
<body>
<header>
  <div>
    <h1>S2D Cartographer — What-If Analysis</h1>
    <div style="font-size:13px;opacity:.9">Capacity impact modeling</div>
  </div>
  <div class="meta">Generated: $gen<br>Nodes: $($Result.BaselineNodeCount) → $($Result.ProjectedNodeCount)</div>
</header>
<div class="container">

<div class="section">
  <h2>Scenario</h2>
  <div class="scenario-badge">$scen</div>
  <div class="kpi-row">
    <div class="kpi"><div class="val">$($bwf.UsableCapacity.TiB) TiB</div><div class="lbl">Baseline Usable</div></div>
    <div class="kpi"><div class="val">$($pwf.UsableCapacity.TiB) TiB</div><div class="lbl">Projected Usable</div></div>
    <div class="kpi $(if($Result.DeltaUsableTiB -gt 0){'positive'}elseif($Result.DeltaUsableTiB -lt 0){'negative'}else{''})">
      <div class="val">$deltaUsableSign$($Result.DeltaUsableTiB) TiB</div><div class="lbl">Delta Usable</div>
    </div>
    <div class="kpi"><div class="val">$($bwf.ReserveStatus)</div><div class="lbl">Baseline Reserve</div></div>
    <div class="kpi"><div class="val">$($pwf.ReserveStatus)</div><div class="lbl">Projected Reserve</div></div>
    <div class="kpi"><div class="val">$($bwf.BlendedEfficiencyPercent)%</div><div class="lbl">Baseline Efficiency</div></div>
    <div class="kpi"><div class="val">$($pwf.BlendedEfficiencyPercent)%</div><div class="lbl">Projected Efficiency</div></div>
  </div>
</div>

<div class="section">
  <h2>Capacity Waterfall — Before vs After</h2>
  <div class="chart-grid">
    <div>
      <div class="chart-label">Baseline</div>
      <div class="chart-wrap"><canvas id="baseChart"></canvas></div>
    </div>
    <div>
      <div class="chart-label">Projected ($scen)</div>
      <div class="chart-wrap"><canvas id="projChart"></canvas></div>
    </div>
  </div>
</div>

<div class="section">
  <h2>Stage-by-Stage Delta</h2>
  <table>
    <thead><tr><th>#</th><th>Stage</th><th style="text-align:right">Baseline</th><th style="text-align:right">Projected</th><th style="text-align:right">Delta</th></tr></thead>
    <tbody>$deltaRows</tbody>
  </table>
</div>

</div>
<script>
const labels  = [$bLabels];
const bVals   = [$bValues];
const pVals   = [$pValues];
const colors  = ['#0078d4','#005a9e','#106ebe','#e8a218','#d47a00','#107c10','#0e6e0e','#054b05'];

function makeChart(id, vals) {
  new Chart(document.getElementById(id).getContext('2d'), {
    type: 'bar',
    data: { labels, datasets: [{ data: vals, backgroundColor: colors, borderRadius: 4 }] },
    options: {
      responsive: true, maintainAspectRatio: false, indexAxis: 'y',
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: c => c.raw + ' TiB' } } },
      scales: { x: { beginAtZero: true, title: { display: true, text: 'TiB' } } }
    }
  });
}
makeChart('baseChart', bVals);
makeChart('projChart', pVals);
</script>
</body>
</html>
"@

    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $html | Set-Content -Path $OutputPath -Encoding UTF8 -Force
    $OutputPath
}
