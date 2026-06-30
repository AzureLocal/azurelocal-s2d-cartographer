# Word (.docx) report exporter — generates Open XML without requiring Office
# Cover page with branded banner, KPI table, color-coded section headers,
# alternating-row data tables, and health check cards with status colors.

function Export-S2DWordReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks
    )

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Page geometry (US Letter, 1-inch margins all sides):
    # Page width = 12240 twips; margins = 1440 left + 1440 right → usable = 9360 twips.
    $pageWidth = 9360

    $cn    = $ClusterData.ClusterName
    $nc    = $ClusterData.NodeCount
    $wf    = $ClusterData.CapacityWaterfall
    $pool  = $ClusterData.StoragePool
    $vols  = @($ClusterData.Volumes)
    $allDisks = @($ClusterData.PhysicalDisks)
    $disks = if ($IncludeNonPoolDisks) { $allDisks } else { @($allDisks | Where-Object { $_.IsPoolMember -ne $false }) }
    $hc    = @($ClusterData.HealthChecks)
    $oh    = $ClusterData.OverallHealth
    $date  = Get-Date -Format 'MMMM d, yyyy'

    # ── XML helpers ───────────────────────────────────────────────────────────
    function local:Esc { param([string]$s) [System.Security.SecurityElement]::Escape($s) }

    function local:Para {
        param(
            [string]$text,
            [string]$color       = '323130',
            [int]   $sz          = 22,
            [bool]  $bold        = $false,
            [string]$align       = 'left',
            [int]   $spaceBefore = 60,
            [int]   $spaceAfter  = 60
        )
        $b = if ($bold) { '<w:b/>' } else { '' }
        "<w:p><w:pPr><w:jc w:val='$align'/><w:spacing w:before='$spaceBefore' w:after='$spaceAfter'/></w:pPr><w:r><w:rPr>$b<w:color w:val='$color'/><w:sz w:val='$sz'/><w:szCs w:val='$sz'/><w:rFonts w:ascii='Segoe UI' w:hAnsi='Segoe UI'/></w:rPr><w:t xml:space='preserve'>$(Esc $text)</w:t></w:r></w:p>"
    }

    function local:Spacer { "<w:p><w:pPr><w:spacing w:before='0' w:after='160'/></w:pPr></w:p>" }

    function local:PageBreak { "<w:p><w:r><w:br w:type='page'/></w:r></w:p>" }

    # Full-width branded banner — used for cover page and section dividers.
    # w:w="$pageWidth" spans the full usable page width (12240 - 1440 left - 1440 right = 9360 twips).
    function local:Banner {
        param(
            [string]$line1,
            [string]$line2      = '',
            [string]$fill       = '003A70',
            [string]$textColor  = 'FFFFFF',
            [int]   $sz1        = 52,
            [int]   $sz2        = 26,
            [string]$accentColor = 'F7941D'
        )
        $l2xml = if ($line2) {
            "<w:p><w:pPr><w:jc w:val='center'/><w:spacing w:before='40' w:after='360'/></w:pPr><w:r><w:rPr><w:color w:val='$accentColor'/><w:sz w:val='$sz2'/><w:szCs w:val='$sz2'/><w:rFonts w:ascii='Segoe UI' w:hAnsi='Segoe UI'/></w:rPr><w:t>$(Esc $line2)</w:t></w:r></w:p>"
        } else {
            "<w:p><w:pPr><w:spacing w:before='0' w:after='280'/></w:pPr></w:p>"
        }
        @"
<w:tbl>
<w:tblPr>
  <w:tblW w:w="$pageWidth" w:type="dxa"/>
  <w:tblLayout w:type="fixed"/>
  <w:tblBorders>
    <w:top w:val="none" w:sz="0" w:color="auto"/>
    <w:left w:val="none" w:sz="0" w:color="auto"/>
    <w:bottom w:val="none" w:sz="0" w:color="auto"/>
    <w:right w:val="none" w:sz="0" w:color="auto"/>
    <w:insideH w:val="none" w:sz="0" w:color="auto"/>
    <w:insideV w:val="none" w:sz="0" w:color="auto"/>
  </w:tblBorders>
  <w:tblCellMar>
    <w:top w:w="200" w:type="dxa"/>
    <w:left w:w="280" w:type="dxa"/>
    <w:bottom w:w="200" w:type="dxa"/>
    <w:right w:w="280" w:type="dxa"/>
  </w:tblCellMar>
</w:tblPr>
<w:tr>
  <w:tc>
    <w:tcPr>
      <w:tcW w:w="$pageWidth" w:type="dxa"/>
      <w:shd w:val="clear" w:color="auto" w:fill="$fill"/>
      <w:vAlign w:val="center"/>
    </w:tcPr>
    <w:p>
      <w:pPr><w:jc w:val="center"/><w:spacing w:before="400" w:after="80"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:color w:val="$textColor"/><w:sz w:val="$sz1"/><w:szCs w:val="$sz1"/><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/></w:rPr>
        <w:t>$(Esc $line1)</w:t>
      </w:r>
    </w:p>
    $l2xml
  </w:tc>
</w:tr>
</w:tbl>
"@
    }

    # Section header — full-width blue bar with left-aligned title.
    # Fixed at page width ($pageWidth dxa) and includes cell padding for legibility.
    function local:SectionHeader {
        param([string]$title, [string]$fill = '0078D4')
        @"
<w:tbl>
<w:tblPr>
  <w:tblW w:w="$pageWidth" w:type="dxa"/>
  <w:tblLayout w:type="fixed"/>
  <w:tblBorders>
    <w:top w:val="none" w:sz="0" w:color="auto"/>
    <w:left w:val="none" w:sz="0" w:color="auto"/>
    <w:bottom w:val="none" w:sz="0" w:color="auto"/>
    <w:right w:val="none" w:sz="0" w:color="auto"/>
    <w:insideH w:val="none" w:sz="0" w:color="auto"/>
    <w:insideV w:val="none" w:sz="0" w:color="auto"/>
  </w:tblBorders>
  <w:tblCellMar>
    <w:top w:w="120" w:type="dxa"/>
    <w:left w:w="200" w:type="dxa"/>
    <w:bottom w:w="120" w:type="dxa"/>
    <w:right w:w="200" w:type="dxa"/>
  </w:tblCellMar>
</w:tblPr>
<w:tr>
  <w:tc>
    <w:tcPr>
      <w:tcW w:w="$pageWidth" w:type="dxa"/>
      <w:shd w:val="clear" w:color="auto" w:fill="$fill"/>
    </w:tcPr>
    <w:p>
      <w:pPr><w:spacing w:before="140" w:after="140"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="28"/><w:szCs w:val="28"/><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/></w:rPr>
        <w:t xml:space="preserve">$(Esc $title)</w:t>
      </w:r>
    </w:p>
  </w:tc>
</w:tr>
</w:tbl>
"@
    }

    # KPI tile table — colored boxes with large value + small label.
    # Distributed across full page width: each cell gets ($pageWidth / count) twips.
    # Value font reduced from 40 (20pt) to 32 (16pt) so multi-unit values like
    # "22.44 TiB" fit without wrapping in each tile.
    function local:KpiTable {
        param([hashtable[]]$kpis)
        $kpiCount  = [Math]::Max(1, $kpis.Count)
        $cellWidth = [int][Math]::Floor($pageWidth / $kpiCount)
        $cells = $kpis | ForEach-Object {
            $bg = switch ($_.status) {
                'Fail'    { 'FDE7E9' } 'Warn' { 'FFF4CE' } 'Pass' { 'DFF6DD' } default { 'EFF6FC' }
            }
            $fg = switch ($_.status) {
                'Fail'    { 'A4262C' } 'Warn' { '835B00' } 'Pass' { '107C10' } default { '0078D4' }
            }
            @"
<w:tc>
  <w:tcPr>
    <w:tcW w:w="$cellWidth" w:type="dxa"/>
    <w:shd w:val="clear" w:color="auto" w:fill="$bg"/>
    <w:tcBdr>
      <w:top w:val="single" w:sz="6" w:color="EDEBE9"/>
      <w:left w:val="single" w:sz="6" w:color="EDEBE9"/>
      <w:bottom w:val="single" w:sz="6" w:color="EDEBE9"/>
      <w:right w:val="single" w:sz="6" w:color="EDEBE9"/>
    </w:tcBdr>
    <w:tcMar>
      <w:top w:w="100" w:type="dxa"/>
      <w:left w:w="120" w:type="dxa"/>
      <w:bottom w:w="100" w:type="dxa"/>
      <w:right w:w="120" w:type="dxa"/>
    </w:tcMar>
  </w:tcPr>
  <w:p>
    <w:pPr><w:jc w:val="center"/><w:spacing w:before="100" w:after="40"/></w:pPr>
    <w:r>
      <w:rPr><w:b/><w:color w:val="$fg"/><w:sz w:val="32"/><w:szCs w:val="32"/><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/></w:rPr>
      <w:t>$(Esc $_.value)</w:t>
    </w:r>
  </w:p>
  <w:p>
    <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="100"/></w:pPr>
    <w:r>
      <w:rPr><w:color w:val="605E5C"/><w:sz w:val="18"/><w:szCs w:val="18"/><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/></w:rPr>
      <w:t>$(Esc $_.label)</w:t>
    </w:r>
  </w:p>
</w:tc>
"@
        }
        @"
<w:tbl>
<w:tblPr>
  <w:tblW w:w="$pageWidth" w:type="dxa"/>
  <w:tblLayout w:type="fixed"/>
  <w:tblBorders>
    <w:top w:val="none"/><w:left w:val="none"/>
    <w:bottom w:val="none"/><w:right w:val="none"/>
    <w:insideH w:val="none"/><w:insideV w:val="none"/>
  </w:tblBorders>
</w:tblPr>
<w:tr>$($cells -join '')</w:tr>
</w:tbl>
"@
    }

    # Data table with blue header row and alternating body rows.
    # Always spans full page width ($pageWidth dxa). Optional $colWidths supplies
    # explicit per-column widths in twips (dxa); if omitted, columns are
    # distributed evenly. This prevents Word's autofit from squeezing wide-value
    # columns (AB#265) and ensures the table never overflows the page (AB#266).
    function local:DataTable {
        param(
            [string[]]  $headers,
            [object[]]  $rows,
            [string[]]  $props,
            [int[]]     $colWidths = @()   # explicit widths in twips; empty = even split
        )
        $colCount = $headers.Count
        if ($colWidths.Count -eq $colCount) {
            $widths = $colWidths
        } else {
            $evenWidth = [int][Math]::Floor($pageWidth / [Math]::Max(1, $colCount))
            $widths    = @($evenWidth) * $colCount
        }

        $colIdx = 0
        $hcells = $headers | ForEach-Object {
            $cw = $widths[$colIdx]; $colIdx++
            "<w:tc><w:tcPr><w:tcW w:w='$cw' w:type='dxa'/><w:shd w:val='clear' w:color='auto' w:fill='003A70'/><w:tcMar><w:top w:w='80' w:type='dxa'/><w:left w:w='120' w:type='dxa'/><w:bottom w:w='80' w:type='dxa'/><w:right w:w='120' w:type='dxa'/></w:tcMar></w:tcPr><w:p><w:pPr><w:spacing w:before='60' w:after='60'/></w:pPr><w:r><w:rPr><w:b/><w:color w:val='FFFFFF'/><w:sz w:val='18'/><w:szCs w:val='18'/><w:rFonts w:ascii='Segoe UI' w:hAnsi='Segoe UI'/></w:rPr><w:t>$(Esc $_)</w:t></w:r></w:p></w:tc>"
        }
        $hrow = "<w:tr><w:trPr><w:tblHeader/></w:trPr>$($hcells -join '')</w:tr>"
        $rowIndex = 0
        $drows = $rows | ForEach-Object {
            $obj  = $_
            $fill = if ($rowIndex % 2 -eq 0) { 'FFFFFF' } else { 'F5F5F5' }
            $rowIndex++
            $pIdx   = 0
            $dcells = $props | ForEach-Object {
                $v = $obj.$_; $vStr = if ($null -eq $v) { '' } else { [string]$v }
                $cw = $widths[$pIdx]; $pIdx++
                "<w:tc><w:tcPr><w:tcW w:w='$cw' w:type='dxa'/><w:shd w:val='clear' w:color='auto' w:fill='$fill'/><w:tcMar><w:top w:w='60' w:type='dxa'/><w:left w:w='120' w:type='dxa'/><w:bottom w:w='60' w:type='dxa'/><w:right w:w='120' w:type='dxa'/></w:tcMar></w:tcPr><w:p><w:pPr><w:spacing w:before='40' w:after='40'/></w:pPr><w:r><w:rPr><w:color w:val='323130'/><w:sz w:val='18'/><w:szCs w:val='18'/><w:rFonts w:ascii='Segoe UI' w:hAnsi='Segoe UI'/></w:rPr><w:t xml:space='preserve'>$(Esc $vStr)</w:t></w:r></w:p></w:tc>"
            }
            "<w:tr>$($dcells -join '')</w:tr>"
        }
        @"
<w:tbl>
<w:tblPr>
  <w:tblW w:w="$pageWidth" w:type="dxa"/>
  <w:tblLayout w:type="fixed"/>
  <w:tblBorders>
    <w:top w:val="single" w:sz="4" w:color="EDEBE9"/>
    <w:left w:val="single" w:sz="4" w:color="EDEBE9"/>
    <w:bottom w:val="single" w:sz="4" w:color="EDEBE9"/>
    <w:right w:val="single" w:sz="4" w:color="EDEBE9"/>
    <w:insideH w:val="single" w:sz="4" w:color="EDEBE9"/>
    <w:insideV w:val="single" w:sz="4" w:color="EDEBE9"/>
  </w:tblBorders>
</w:tblPr>
$hrow
$($drows -join '')
</w:tbl>
"@
    }

    # ── Build document body ───────────────────────────────────────────────────
    $body = @()

    # Cover page
    $body += Banner 'S2D CARTOGRAPHER' 'Storage Spaces Direct Analysis Report'
    $body += Spacer
    $body += Para "Cluster:  $cn"   -sz 30 -bold $true  -spaceBefore 240 -spaceAfter 80
    $body += Para "Nodes:    $nc"   -sz 22              -spaceBefore 40  -spaceAfter 40
    $body += Para "Generated: $date" -sz 22             -spaceBefore 40  -spaceAfter 40
    if ($Author)  { $body += Para "Prepared by: $Author"     -sz 22 -spaceBefore 40 -spaceAfter 40 }
    if ($Company) { $body += Para "Organization: $Company"   -sz 22 -spaceBefore 40 -spaceAfter 40 }
    $ohColor = switch ($oh) {
        'Healthy'  { '107C10' } 'Warning' { '835B00' } 'Critical' { 'A4262C' } default { '323130' }
    }
    $body += Para "Overall Health: $oh" -color $ohColor -sz 26 -bold $true -spaceBefore 160 -spaceAfter 80
    $body += PageBreak

    # Executive Summary
    $body += SectionHeader 'Executive Summary'
    $body += Spacer
    if ($wf) {
        $reserveKpiStatus = switch ($wf.ReserveStatus) { 'Adequate' { 'Pass' } 'Warning' { 'Warn' } default { 'Fail' } }
        $ohKpiStatus      = switch ($oh) { 'Healthy' { 'Pass' } 'Warning' { 'Warn' } default { 'Fail' } }
        $body += KpiTable @(
            @{ label = 'Raw Capacity';       value = "$($wf.RawCapacity.TiB) TiB";       status = 'neutral' }
            @{ label = 'Usable Capacity';    value = "$($wf.UsableCapacity.TiB) TiB";    status = 'neutral' }
            @{ label = 'Reserve Status';     value = $wf.ReserveStatus;                  status = $reserveKpiStatus }
            @{ label = 'Blended Efficiency'; value = "$($wf.BlendedEfficiencyPercent)%"; status = 'neutral' }
            @{ label = 'Overall Health';     value = $oh;                                status = $ohKpiStatus }
        )
    }
    $body += Spacer
    $summaryRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $summaryRows.Add([PSCustomObject]@{ Metric = 'Cluster Name'; Value = $cn })
    $summaryRows.Add([PSCustomObject]@{ Metric = 'Node Count';   Value = $nc })
    $summaryRows.Add([PSCustomObject]@{ Metric = 'Overall Health'; Value = $oh })
    if ($wf) {
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Raw Capacity';      Value = "$($wf.RawCapacity.TiB) TiB ($($wf.RawCapacity.TB) TB)" })
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Usable Capacity';   Value = "$($wf.UsableCapacity.TiB) TiB ($($wf.UsableCapacity.TB) TB)" })
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Reserve Status';    Value = $wf.ReserveStatus })
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Resiliency Efficiency'; Value = "$($wf.BlendedEfficiencyPercent)%" })
    }
    if ($pool) {
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Pool Total';    Value = "$($pool.TotalSize.TiB) TiB ($($pool.TotalSize.TB) TB)" })
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Pool Free';     Value = "$($pool.RemainingSize.TiB) TiB ($($pool.RemainingSize.TB) TB)" })
        $summaryRows.Add([PSCustomObject]@{ Metric = 'Overcommit Ratio'; Value = "$($pool.OvercommitRatio)x" })
    }
    if ($Author)  { $summaryRows.Add([PSCustomObject]@{ Metric = 'Prepared By';   Value = $Author }) }
    if ($Company) { $summaryRows.Add([PSCustomObject]@{ Metric = 'Organization';  Value = $Company }) }
    $summaryRows.Add([PSCustomObject]@{ Metric = 'Report Date'; Value = $date })
    # AB#265: explicit 35/65 column split so the Value column has room for
    # multi-unit strings like "22.44 TiB (24.65 TB)" without wrapping.
    # 9360 * 0.35 = 3276 (Metric); remainder 6084 (Value).
    $body += DataTable -headers @('Metric', 'Value') -rows $summaryRows -props @('Metric', 'Value') `
        -colWidths @(3276, 6084)
    $body += PageBreak

    # Capacity Waterfall
    $body += SectionHeader 'Capacity Waterfall'
    $body += Spacer
    $body += Para 'Theoretical pipeline showing how raw storage is accounted for under S2D best practices. Each stage represents a recommended deduction. No health state is shown — this is pure capacity math.' `
        -sz 20 -color '605E5C' -spaceBefore 40 -spaceAfter 120
    if ($wf) {
        $wfRows = $wf.Stages | ForEach-Object {
            [PSCustomObject]@{
                Stage       = "Stage $($_.Stage)"
                Name        = $_.Name
                Deducted    = if ($_.Delta -and $_.Delta.TB -gt 0) { "-$($_.Delta.TB) TB" } else { '—' }
                Remaining   = if ($_.Size) { "$($_.Size.TB) TB" } else { '0 TB' }
                Description = $_.Description
            }
        }
        $body += DataTable -headers @('Stage', 'Name', 'Deducted', 'Remaining', 'Description') `
            -rows $wfRows -props @('Stage', 'Name', 'Deducted', 'Remaining', 'Description')
        $body += Spacer
        $body += Para "Reserve — Recommended: $($wf.ReserveRecommended.TiB) TiB ($($wf.ReserveRecommended.TB) TB)   Actual: $($wf.ReserveActual.TiB) TiB   Status: $($wf.ReserveStatus)" `
            -sz 20 -bold $true -spaceBefore 60 -spaceAfter 60
    }
    $body += PageBreak

    # Physical Disk Inventory
    $body += SectionHeader 'Physical Disk Inventory'
    $body += Spacer
    $diskRows = $disks | ForEach-Object {
        [PSCustomObject]@{
            Node     = $_.NodeName
            Model    = $_.FriendlyName
            Type     = $_.MediaType
            Role     = $_.Role
            Size     = if ($_.Size) { "$($_.Size.TiB) TiB ($($_.Size.TB) TB)" } else { 'N/A' }
            Wear     = if ($null -ne $_.WearPercentage) { "$($_.WearPercentage)%" } else { 'N/A' }
            Health   = $_.HealthStatus
            Firmware = $_.FirmwareVersion
        }
    }
    # AB#266: 8 columns — proportioned so wide data columns (Node, Model, Size)
    # get more space than short fixed-value columns (Type, Role, Wear, Firmware).
    # Total = 9360: Node=1340 Model=2000 Type=780 Role=780 Size=1560 Wear=670 Health=780 Firmware=1450
    $body += DataTable -headers @('Node', 'Model', 'Type', 'Role', 'Size', 'Wear %', 'Health', 'Firmware') `
        -rows $diskRows -props @('Node', 'Model', 'Type', 'Role', 'Size', 'Wear', 'Health', 'Firmware') `
        -colWidths @(1340, 2000, 780, 780, 1560, 670, 780, 1450)
    $body += PageBreak

    # Volume Map
    $body += SectionHeader 'Volume Map'
    $body += Spacer
    $volRows = $vols | ForEach-Object {
        $infraMark = if ($_.IsInfrastructureVolume) { ' [Infra]' } else { '' }
        [PSCustomObject]@{
            Name      = "$($_.FriendlyName)$infraMark"
            Resiliency = "$($_.ResiliencySettingName) ($($_.NumberOfDataCopies)x)"
            Size      = if ($_.Size)            { "$($_.Size.TiB) TiB" }            else { 'N/A' }
            Footprint = if ($_.FootprintOnPool) { "$($_.FootprintOnPool.TiB) TiB" } else { 'N/A' }
            Eff       = "$($_.EfficiencyPercent)%"
            Prov      = $_.ProvisioningType
            Headroom  = if ($_.ThinGrowthHeadroom)    { "$([math]::Round($_.ThinGrowthHeadroom.TiB,2)) TiB" }    else { '-' }
            MaxFP     = if ($_.MaxPotentialFootprint) { "$([math]::Round($_.MaxPotentialFootprint.TiB,2)) TiB" } else { '-' }
            Health    = $_.HealthStatus
        }
    }
    # AB#266: 9 columns — Volume name and Resiliency need the most space;
    # numeric/status columns are narrower.
    # Total = 9360: Name=1680 Res=1120 Size=900 FP=900 Eff=670 Prov=780 Headroom=1000 MaxFP=1000 Health=1310
    $body += DataTable `
        -headers @('Volume', 'Resiliency', 'Size', 'Pool Footprint', 'Efficiency', 'Provisioning', 'Growth Headroom', 'Max Potential FP', 'Health') `
        -rows $volRows `
        -props @('Name', 'Resiliency', 'Size', 'Footprint', 'Eff', 'Prov', 'Headroom', 'MaxFP', 'Health') `
        -colWidths @(1680, 1120, 900, 900, 670, 780, 1000, 1000, 1310)
    $body += PageBreak

    # Expansion Headroom
    $body += SectionHeader 'Expansion Headroom'
    $body += Spacer
    $eh = $ClusterData.ExpansionHeadroom
    if ($eh) {
        # Part A: provisioning-aware 70% note.
        $ehThinNote = if ($eh.HasThinVolumes) {
            '70% is the recommended planning line — thin volumes are present; a full pool takes thin volumes offline.'
        } else {
            '70% is a recommended operational headroom guideline — mainly relevant for thin-provisioned volumes, where a full pool takes thin volumes offline. Not a Microsoft hard limit. The firm storage limits are footprints fitting the pool and the rebuild reserve staying intact. All volumes are fixed — footprint is committed up front.'
        }
        $body += Para "Current utilization: $($eh.CurrentUtilizationPct)% of Available-for-Volumes (footprint basis). New-volume usable data assumes $($eh.PrevalentDataCopies) data copies (prevailing resiliency — assumed for estimates). $ehThinNote" `
            -sz 20 -color '605E5C' -spaceBefore 40 -spaceAfter 80
        $body += Para 'Size to enter is the value to type into New-Volume -Size or WAC. PowerShell and WAC read size suffixes as binary (1 TB = 1 TiB), so this equals the TiB column, rounded down so the new volume always fits.' `
            -sz 18 -color '605E5C' -spaceBefore 20 -spaceAfter 80
        $ehRows = $eh.Thresholds | ForEach-Object {
            $planNote = if ($_.IsRecommendedPlanningLine) {
                if ($eh.HasThinVolumes) { ' [Planning line]' } else { ' [Advisory]' }
            } else { '' }
            $pastNote = if ($_.IsPastLine) { ' [PAST]' } else { '' }
            # Part B: SizeToEnterTiB — null-safe for JSON snapshots that predate this property.
            $stePropW = $_.PSObject.Properties['SizeToEnterTiB']
            $steVal = if ($_.IsPastLine) {
                [string][char]0x2014  # em dash
            } elseif ($null -ne $stePropW) {
                "$($stePropW.Value)TB"
            } else {
                "$([Math]::Floor($_.NewUsableData.TiB * 100) / 100)TB"
            }
            [PSCustomObject]@{
                FillTarget        = "$($_.FillTargetPct)%$planNote$pastNote"
                FootprintBudget   = "$($_.FootprintBudget.TB) TB / $($_.FootprintBudget.TiB) TiB"
                RemainingFP       = "$($_.RemainingFootprint.TB) TB / $($_.RemainingFootprint.TiB) TiB"
                NewUsableData     = "$($_.NewUsableData.TB) TB / $($_.NewUsableData.TiB) TiB"
                SizeToEnter       = $steVal
            }
        }
        # 5 columns: FillTarget=780 FootprintBudget=2280 RemainingFP=2280 NewUsableData=2280 SizeToEnter=1740 (total=9360)
        $body += DataTable `
            -headers @('Fill Target', 'Footprint Budget', 'Remaining Footprint', 'New Usable Data', "Size to enter`nNew-Volume / WAC") `
            -rows $ehRows `
            -props @('FillTarget', 'FootprintBudget', 'RemainingFP', 'NewUsableData', 'SizeToEnter') `
            -colWidths @(780, 2280, 2280, 2280, 1740)
    } else {
        $body += Para 'Expansion headroom data not available (waterfall required).' -sz 20 -color '605E5C' -spaceBefore 40 -spaceAfter 60
    }
    $body += PageBreak

    # Compute Maintenance Reserve Context — INFORMATIONAL ONLY
    # DEFENSIVE: every property access is guarded — null assessment skips the section.
    # N+1/N+2 is a COMPUTE resiliency target, not a storage-pool reserve.
    $mraData = $ClusterData.MaintenanceReserveAssessment
    if ($null -ne $mraData -and $mraData.Status -ne 'Unknown') {
        $mraTargetLabel = if ($mraData.Target) { [string]$mraData.Target } else { 'N+1' }
        $body += SectionHeader "Compute Maintenance Reserve Context ($mraTargetLabel) — Advisory"
        $body += Spacer
        $mraNodeVal = if ($mraData.LargestNodeCapacity) {
            "$([math]::Round($mraData.LargestNodeCapacity.TB, 2)) TB / $([math]::Round($mraData.LargestNodeCapacity.TiB, 2)) TiB"
        } else { 'N/A' }
        $body += KpiTable @(
            @{ label = 'Largest node raw storage'; value = $mraNodeVal;     status = 'neutral' }
            @{ label = "$mraTargetLabel context";  value = 'Advisory only'; status = 'neutral' }
        )
        $body += Spacer
        $body += Para 'N+1/N+2 is a COMPUTE resiliency target — reserve one or two nodes'' worth of CPU + RAM so a node can be drained for updates or lost without dropping VMs. Microsoft WAF scopes this to compute and lists it separately from storage. It is not a storage-pool reserve. The firm storage reserves are the per-drive rebuild reserve and keeping volume footprints within the pool.' `
            -sz 20 -color '605E5C' -spaceBefore 40 -spaceAfter 80
        if ($mraData.Note) {
            $body += Para ([string]$mraData.Note) -sz 20 -color '605E5C' -spaceBefore 20 -spaceAfter 60
        }
        $body += PageBreak
    }

    # Health Assessment
    $body += SectionHeader 'Health Assessment'
    $body += Spacer
    $hcRows = $hc | ForEach-Object {
        [PSCustomObject]@{
            Check    = $_.CheckName
            Severity = $_.Severity
            Status   = $_.Status
            Details  = $_.Details
        }
    }
    $body += DataTable -headers @('Check', 'Severity', 'Status', 'Details') `
        -rows $hcRows -props @('Check', 'Severity', 'Status', 'Details')

    # Remediation cards for non-passing checks
    $nonPass = @($hc | Where-Object { $_.Status -ne 'Pass' })
    if ($nonPass.Count -gt 0) {
        $body += Spacer
        $body += SectionHeader 'Remediation Actions' -fill '605E5C'
        $body += Spacer
        foreach ($check in $nonPass) {
            $cardFill = switch ($check.Status) { 'Fail' { 'FDE7E9' } 'Warn' { 'FFF4CE' } default { 'F3F2F1' } }
            $cardFg   = switch ($check.Status) { 'Fail' { 'A4262C' } 'Warn' { '835B00' } default { '323130' } }
            $body += Banner "$($check.CheckName)  |  $($check.Severity)  |  $($check.Status)" '' `
                -fill $cardFill -textColor $cardFg -sz1 24
            $body += Para $check.Details -sz 20 -spaceBefore 60 -spaceAfter 40
            if ($check.Remediation) {
                $body += Para "Remediation: $($check.Remediation)" -sz 20 -bold $true -color '0078D4' -spaceBefore 40 -spaceAfter 100
            }
        }
    }
    $body += PageBreak

    # Appendices
    $body += SectionHeader 'Appendix A — TiB vs TB'
    $body += Spacer
    $body += Para 'Drive manufacturers label storage in decimal terabytes (1 TB = 1,000,000,000,000 bytes). Windows and S2D report capacity in binary tebibytes (1 TiB = 1,099,511,627,776 bytes). This creates an apparent ~9% difference. All data is present — the discrepancy is purely a unit conversion.' `
        -sz 20 -color '605E5C' -spaceBefore 60 -spaceAfter 120
    $tibRows = @(
        [PSCustomObject]@{ DriveLabel = '0.96 TB';  Windows = '0.873 TiB';  Diff = '-9.3%' }
        [PSCustomObject]@{ DriveLabel = '1.92 TB';  Windows = '1.747 TiB';  Diff = '-9.0%' }
        [PSCustomObject]@{ DriveLabel = '3.84 TB';  Windows = '3.492 TiB';  Diff = '-9.1%' }
        [PSCustomObject]@{ DriveLabel = '7.68 TB';  Windows = '6.986 TiB';  Diff = '-9.0%' }
        [PSCustomObject]@{ DriveLabel = '15.36 TB'; Windows = '13.97 TiB';  Diff = '-9.1%' }
    )
    $body += DataTable -headers @('Drive Label', 'Windows Reports', 'Difference') `
        -rows $tibRows -props @('DriveLabel', 'Windows', 'Diff')
    $body += Spacer
    $body += SectionHeader 'Appendix B — S2D Reserve Space Best Practices' -fill '005A9E'
    $body += Spacer
    $reserveText = "Microsoft recommends keeping at least min(NodeCount, 4) x (largest capacity drive size) of unallocated pool " +
        "space to enable full rebuild after a drive or node failure. " +
        "For a $nc-node cluster the recommended reserve is " +
        "$(if ($wf) {"$($wf.ReserveRecommended.TiB) TiB ($($wf.ReserveRecommended.TB) TB)"} else {'N/A'})."
    $body += Para $reserveText -sz 20 -color '605E5C' -spaceBefore 60 -spaceAfter 60

    $bodyXml = $body -join "`n"

    # ── Open XML package components ───────────────────────────────────────────
    $contentTypesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"   ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
'@

    $relsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@

    $wordRelsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
'@

    $stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI" w:cs="Segoe UI"/>
        <w:sz w:val="22"/>
        <w:szCs w:val="22"/>
        <w:color w:val="323130"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/>
      <w:sz w:val="22"/>
    </w:rPr>
  </w:style>
</w:styles>
'@

    $documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<w:body>
$bodyXml
<w:sectPr>
  <w:pgSz w:w="12240" w:h="15840"/>
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
           w:header="720" w:footer="720" w:gutter="0"/>
</w:sectPr>
</w:body>
</w:document>
"@

    # ── Assemble DOCX ─────────────────────────────────────────────────────────
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ms  = [System.IO.MemoryStream]::new()
    $zip = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)

    function local:AddEntry { param([string]$name, [string]$content)
        $e  = $zip.CreateEntry($name)
        $sw = [System.IO.StreamWriter]::new($e.Open(), [System.Text.Encoding]::UTF8)
        $sw.Write($content)
        $sw.Close()
    }

    AddEntry '[Content_Types].xml'          $contentTypesXml
    AddEntry '_rels/.rels'                  $relsXml
    AddEntry 'word/_rels/document.xml.rels' $wordRelsXml
    AddEntry 'word/styles.xml'              $stylesXml
    AddEntry 'word/document.xml'            $documentXml

    $zip.Dispose()
    [System.IO.File]::WriteAllBytes($OutputPath, $ms.ToArray())
    $ms.Dispose()

    Write-Verbose "Word report written to $OutputPath"
    $OutputPath
}
