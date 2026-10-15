# PDF report exporter — renders HTML report via headless Chromium/Edge

function Export-S2DPdfReport {
    param(
        [Parameter(Mandatory)] [S2DClusterData] $ClusterData,
        [Parameter(Mandatory)] [string]          $OutputPath,
        [string] $Author  = '',
        [string] $Company = '',
        [switch] $IncludeNonPoolDisks
    )

    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # ── Generate intermediate HTML ────────────────────────────────────────────
    $htmlPath = [System.IO.Path]::ChangeExtension($OutputPath, '.pdf.html')
    $htmlParams = @{
        ClusterData = $ClusterData
        OutputPath  = $htmlPath
        Author      = $Author
        Company     = $Company
    }
    if ($IncludeNonPoolDisks) { $htmlParams['IncludeNonPoolDisks'] = $true }
    Export-S2DHtmlReport @htmlParams | Out-Null

    # ── Locate headless browser ───────────────────────────────────────────────
    $browserPaths = @(
        # Microsoft Edge (ships with Windows 11/Server 2022+)
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        # Google Chrome
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        # Chromium
        'C:\Program Files\Chromium\Application\chrome.exe'
    )

    # Check PATH too
    $browserExe = $null
    foreach ($p in $browserPaths) {
        if (Test-Path $p) { $browserExe = $p; break }
    }
    if (-not $browserExe) {
        $browserExe = Get-Command msedge.exe  -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if (-not $browserExe) {
            $browserExe = Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        }
    }

    if (-not $browserExe) {
        Write-Warning "PDF export requires Microsoft Edge or Google Chrome. Neither was found on this system."
        Write-Warning "The HTML report is available at: $htmlPath"
        Write-Warning "To convert manually: Open $htmlPath in a browser and use Ctrl+P → Save as PDF."
        Remove-Item $htmlPath -Force -ErrorAction SilentlyContinue
        return $null
    }

    # ── Invoke headless print-to-PDF ──────────────────────────────────────────
    $absHtml = (Resolve-Path $htmlPath).Path
    $absPdf  = $OutputPath

    $chromeArgs = @(
        '--headless=new'
        '--disable-gpu'
        '--no-sandbox'
        '--disable-extensions'
        "--print-to-pdf=`"$absPdf`""
        '--print-to-pdf-no-header'
        "`"$absHtml`""
    )

    Write-Verbose "Invoking: $browserExe $($chromeArgs -join ' ')"
    $proc = Start-Process -FilePath $browserExe -ArgumentList $chromeArgs -Wait -PassThru -WindowStyle Hidden

    if ($proc.ExitCode -ne 0) {
        Write-Warning "Browser exited with code $($proc.ExitCode). PDF may not have been generated."
    }

    # Clean up intermediate HTML
    Remove-Item $htmlPath -Force -ErrorAction SilentlyContinue

    if (Test-Path $OutputPath) {
        Write-Verbose "PDF report written to $OutputPath"
        $OutputPath
    }
    else {
        Write-Warning "PDF file was not created at $OutputPath. Check browser output."
        $null
    }
}
