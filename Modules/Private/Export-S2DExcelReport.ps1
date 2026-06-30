# Excel report exporter — uses ImportExcel module
# Professional table styling, conditional formatting on status columns,
# and a color-coded Summary dashboard tab.

function Export-S2DExcelReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks
    )

    if (-not (Get-Module -ListAvailable -Name ImportExcel -ErrorAction SilentlyContinue)) {
        Write-Verbose "ImportExcel not found — attempting to install from PSGallery..."
        try {
            Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            throw "Excel report format requires the ImportExcel module. Install it with: Install-Module ImportExcel -Scope CurrentUser`n(Auto-install failed: $_)"
        }
    }
    Import-Module ImportExcel -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    $wf    = $ClusterData.CapacityWaterfall
    $pool  = $ClusterData.StoragePool
    $vols  = @($ClusterData.Volumes)
    $allDisks = @($ClusterData.PhysicalDisks)
    $disks = if ($IncludeNonPoolDisks) { $allDisks } else { @($allDisks | Where-Object { $_.IsPoolMember -ne $false }) }
    $hc    = @($ClusterData.HealthChecks)

    # ── Color helpers ─────────────────────────────────────────────────────────
    $clrBlue      = [System.Drawing.Color]::FromArgb(0x00, 0x3A, 0x70)  # header dark blue
    $clrAccent    = [System.Drawing.Color]::FromArgb(0x00, 0x78, 0xD4)  # accent blue
    $clrWhite     = [System.Drawing.Color]::White
    $clrPass      = [System.Drawing.Color]::FromArgb(0xDF, 0xF6, 0xDD)
    $clrPassFg    = [System.Drawing.Color]::FromArgb(0x10, 0x7C, 0x10)
    $clrWarn      = [System.Drawing.Color]::FromArgb(0xFF, 0xF4, 0xCE)
    $clrWarnFg    = [System.Drawing.Color]::FromArgb(0x83, 0x5B, 0x00)
    $clrFail      = [System.Drawing.Color]::FromArgb(0xFD, 0xE7, 0xE9)
    $clrFailFg    = [System.Drawing.Color]::FromArgb(0xA4, 0x26, 0x2C)

    # ── Tab 1: Summary dashboard ──────────────────────────────────────────────
    $summary = [PSCustomObject]@{
        ClusterName          = $ClusterData.ClusterName
        NodeCount            = $ClusterData.NodeCount
        CollectedAt          = $ClusterData.CollectedAt
        OverallHealth        = $ClusterData.OverallHealth
        RawCapacityTiB       = if ($wf) { $wf.RawCapacity.TiB }       else { 'N/A' }
        RawCapacityTB        = if ($wf) { $wf.RawCapacity.TB }        else { 'N/A' }
        UsableCapacityTiB    = if ($wf) { $wf.UsableCapacity.TiB }    else { 'N/A' }
        UsableCapacityTB     = if ($wf) { $wf.UsableCapacity.TB }     else { 'N/A' }
        ReserveStatus        = if ($wf) { $wf.ReserveStatus }         else { 'N/A' }
        BlendedEfficiency    = if ($wf) { "$($wf.BlendedEfficiencyPercent)%" } else { 'N/A' }
        PoolFriendlyName     = if ($pool) { $pool.FriendlyName }      else { 'N/A' }
        PoolHealthStatus     = if ($pool) { $pool.HealthStatus }       else { 'N/A' }
        PoolTotalTiB         = if ($pool -and $pool.TotalSize)     { $pool.TotalSize.TiB }    else { 'N/A' }
        PoolAllocatedTiB     = if ($pool -and $pool.AllocatedSize) { $pool.AllocatedSize.TiB } else { 'N/A' }
        PoolRemainingTiB     = if ($pool -and $pool.RemainingSize) { $pool.RemainingSize.TiB } else { 'N/A' }
        OvercommitRatio      = if ($pool) { $pool.OvercommitRatio }    else { 'N/A' }
        Author               = $Author
        Company              = $Company
    }
    $xlpkg = $summary | Export-Excel -Path $OutputPath -WorksheetName 'Summary' `
        -AutoSize -FreezeTopRow -BoldTopRow -PassThru

    # Style the Summary sheet header row
    $wsSummary = $xlpkg.Workbook.Worksheets['Summary']
    $summaryHdrRange = $wsSummary.Cells['1:1']
    $summaryHdrRange.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $summaryHdrRange.Style.Fill.BackgroundColor.SetColor($clrBlue)
    $summaryHdrRange.Style.Font.Color.SetColor($clrWhite)
    $summaryHdrRange.Style.Font.Bold = $true

    # Color-code OverallHealth cell
    $ohRow = 2  # data starts at row 2
    $ohCol = 4  # OverallHealth is 4th column
    $ohCell = $wsSummary.Cells[$ohRow, $ohCol]
    $ohVal  = $ClusterData.OverallHealth
    $ohBg   = switch ($ohVal) { 'Healthy' { $clrPass } 'Warning' { $clrWarn } 'Critical' { $clrFail } default { $null } }
    $ohFg   = switch ($ohVal) { 'Healthy' { $clrPassFg } 'Warning' { $clrWarnFg } 'Critical' { $clrFailFg } default { $null } }
    if ($ohBg) {
        $ohCell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $ohCell.Style.Fill.BackgroundColor.SetColor($ohBg)
        $ohCell.Style.Font.Color.SetColor($ohFg)
        $ohCell.Style.Font.Bold = $true
    }
    Close-ExcelPackage $xlpkg

    # ── Tab 2: Capacity Waterfall ─────────────────────────────────────────────
    if ($wf) {
        $wfData = $wf.Stages | ForEach-Object {
            [PSCustomObject]@{
                Stage       = $_.Stage
                Name        = $_.Name
                SizeTiB     = if ($_.Size) { $_.Size.TiB } else { 0 }
                SizeTB      = if ($_.Size) { $_.Size.TB }  else { 0 }
                SizeBytes   = if ($_.Size) { $_.Size.Bytes } else { 0 }
                DeltaTiB    = if ($_.Delta) { $_.Delta.TiB } else { $null }
                Description = $_.Description
                Status      = $_.Status
            }
        }
        $xlpkg = $wfData | Export-Excel -Path $OutputPath -WorksheetName 'Capacity Waterfall' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableName 'CapacityWaterfall' -TableStyle Medium2 -Append -PassThru

        $wsWf = $xlpkg.Workbook.Worksheets['Capacity Waterfall']
        # Color Status column (col 8) by value
        $statusColWf = 8
        for ($r = 2; $r -le ($wfData.Count + 1); $r++) {
            $cell = $wsWf.Cells[$r, $statusColWf]
            $val  = $cell.Value
            $bg   = switch ($val) { 'Pass'{ $clrPass } 'Warn'{ $clrWarn } 'Fail'{ $clrFail } default { $null } }
            $fg   = switch ($val) { 'Pass'{ $clrPassFg } 'Warn'{ $clrWarnFg } 'Fail'{ $clrFailFg } default { $null } }
            if ($bg) {
                $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                $cell.Style.Fill.BackgroundColor.SetColor($bg)
                $cell.Style.Font.Color.SetColor($fg)
                $cell.Style.Font.Bold = $true
            }
        }
        Close-ExcelPackage $xlpkg
    }

    # ── Tab 3: Physical Disks ─────────────────────────────────────────────────
    $diskData = $disks | ForEach-Object {
        [PSCustomObject]@{
            NodeName          = $_.NodeName
            FriendlyName      = $_.FriendlyName
            SerialNumber      = $_.SerialNumber
            MediaType         = $_.MediaType
            BusType           = $_.BusType
            Role              = $_.Role
            SizeTiB           = if ($_.Size) { $_.Size.TiB } else { 0 }
            SizeTB            = if ($_.Size) { $_.Size.TB }  else { 0 }
            Model             = $_.Model
            FirmwareVersion   = $_.FirmwareVersion
            HealthStatus      = $_.HealthStatus
            OperationalStatus = $_.OperationalStatus
            WearPercentage    = $_.WearPercentage
            Temperature       = $_.Temperature
            PowerOnHours      = $_.PowerOnHours
            ReadErrors        = $_.ReadErrors
            WriteErrors       = $_.WriteErrors
        }
    }
    $xlpkg = $diskData | Export-Excel -Path $OutputPath -WorksheetName 'Physical Disks' `
        -AutoSize -FreezeTopRow -BoldTopRow -TableName 'PhysicalDisks' -TableStyle Medium2 -Append -PassThru

    $wsDisks = $xlpkg.Workbook.Worksheets['Physical Disks']
    # Highlight HealthStatus column (col 11)
    for ($r = 2; $r -le ($diskData.Count + 1); $r++) {
        $cell = $wsDisks.Cells[$r, 11]
        $val  = $cell.Value
        if ($val -ne 'Healthy' -and -not [string]::IsNullOrEmpty($val)) {
            $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $cell.Style.Fill.BackgroundColor.SetColor($clrFail)
            $cell.Style.Font.Color.SetColor($clrFailFg)
            $cell.Style.Font.Bold = $true
        }
        # Highlight wear column (col 13) when > 80
        $wearCell = $wsDisks.Cells[$r, 13]
        $wearVal  = $wearCell.Value
        if ($wearVal -is [double] -or $wearVal -is [int]) {
            if ($wearVal -gt 80) {
                $wearCell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                $wearCell.Style.Fill.BackgroundColor.SetColor($clrWarn)
                $wearCell.Style.Font.Color.SetColor($clrWarnFg)
            }
        }
    }
    Close-ExcelPackage $xlpkg

    # ── Tab 4: Storage Pool ───────────────────────────────────────────────────
    if ($pool) {
        $poolData = [PSCustomObject]@{
            FriendlyName         = $pool.FriendlyName
            HealthStatus         = $pool.HealthStatus
            OperationalStatus    = $pool.OperationalStatus
            IsReadOnly           = $pool.IsReadOnly
            TotalSizeTiB         = if ($pool.TotalSize)       { $pool.TotalSize.TiB }       else { 0 }
            AllocatedSizeTiB     = if ($pool.AllocatedSize)   { $pool.AllocatedSize.TiB }   else { 0 }
            RemainingSizeTiB     = if ($pool.RemainingSize)   { $pool.RemainingSize.TiB }   else { 0 }
            ProvisionedSizeTiB   = if ($pool.ProvisionedSize) { $pool.ProvisionedSize.TiB } else { 0 }
            OvercommitRatio      = $pool.OvercommitRatio
            FaultDomainAwareness = $pool.FaultDomainAwareness
        }
        $poolData | Export-Excel -Path $OutputPath -WorksheetName 'Storage Pool' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableName 'StoragePool' -TableStyle Medium2 -Append
    }

    # ── Tab 5: Volumes ────────────────────────────────────────────────────────
    $volData = $vols | ForEach-Object {
        [PSCustomObject]@{
            FriendlyName             = $_.FriendlyName
            FileSystem               = $_.FileSystem
            ResiliencySettingName    = $_.ResiliencySettingName
            NumberOfDataCopies       = $_.NumberOfDataCopies
            ProvisioningType         = $_.ProvisioningType
            SizeTiB                  = if ($_.Size)            { $_.Size.TiB }            else { 0 }
            FootprintOnPoolTiB       = if ($_.FootprintOnPool) { $_.FootprintOnPool.TiB } else { 0 }
            AllocatedSizeTiB         = if ($_.AllocatedSize)   { $_.AllocatedSize.TiB }   else { 0 }
            EfficiencyPercent        = $_.EfficiencyPercent
            HealthStatus             = $_.HealthStatus
            OperationalStatus        = $_.OperationalStatus
            IsDeduplicationEnabled   = $_.IsDeduplicationEnabled
            IsInfrastructureVolume   = $_.IsInfrastructureVolume
            ThinGrowthHeadroomTiB    = if ($_.ThinGrowthHeadroom)    { $_.ThinGrowthHeadroom.TiB }    else { $null }
            MaxPotentialFootprintTiB = if ($_.MaxPotentialFootprint) { $_.MaxPotentialFootprint.TiB } else { $null }
        }
    }
    $xlpkg = $volData | Export-Excel -Path $OutputPath -WorksheetName 'Volumes' `
        -AutoSize -FreezeTopRow -BoldTopRow -TableName 'Volumes' -TableStyle Medium2 -Append -PassThru

    $wsVols = $xlpkg.Workbook.Worksheets['Volumes']
    # Highlight HealthStatus column (col 10)
    for ($r = 2; $r -le ($volData.Count + 1); $r++) {
        $cell = $wsVols.Cells[$r, 10]
        $val  = $cell.Value
        if ($val -ne 'Healthy' -and -not [string]::IsNullOrEmpty($val)) {
            $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $cell.Style.Fill.BackgroundColor.SetColor($clrFail)
            $cell.Style.Font.Color.SetColor($clrFailFg)
            $cell.Style.Font.Bold = $true
        }
    }
    Close-ExcelPackage $xlpkg

    # ── Tab 6: Health Checks ──────────────────────────────────────────────────
    $hcData = $hc | ForEach-Object {
        [PSCustomObject]@{
            CheckName   = $_.CheckName
            Severity    = $_.Severity
            Status      = $_.Status
            Details     = $_.Details
            Remediation = $_.Remediation
        }
    }
    $xlpkg = $hcData | Export-Excel -Path $OutputPath -WorksheetName 'Health Checks' `
        -AutoSize -FreezeTopRow -BoldTopRow -TableName 'HealthChecks' -TableStyle Medium2 -Append -PassThru

    $wsHc = $xlpkg.Workbook.Worksheets['Health Checks']
    # Color entire row by Status (col 3)
    for ($r = 2; $r -le ($hcData.Count + 1); $r++) {
        $statusVal = $wsHc.Cells[$r, 3].Value
        $bg = switch ($statusVal) { 'Pass' { $clrPass } 'Warn' { $clrWarn } 'Fail' { $clrFail } default { $null } }
        $fg = switch ($statusVal) { 'Pass' { $clrPassFg } 'Warn' { $clrWarnFg } 'Fail' { $clrFailFg } default { $null } }
        if ($bg) {
            for ($c = 1; $c -le 5; $c++) {
                $cell = $wsHc.Cells[$r, $c]
                $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                $cell.Style.Fill.BackgroundColor.SetColor($bg)
                $cell.Style.Font.Color.SetColor($fg)
            }
            $wsHc.Cells[$r, 3].Style.Font.Bold = $true
        }
    }
    Close-ExcelPackage $xlpkg

    Write-Verbose "Excel report written to $OutputPath"
    $OutputPath
}
