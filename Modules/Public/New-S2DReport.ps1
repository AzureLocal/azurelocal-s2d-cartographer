function New-S2DReport {
    <#
    .SYNOPSIS
        Generates HTML, Word, PDF, Excel, JSON, or CSV reports from S2D cluster data.

    .DESCRIPTION
        Accepts an S2DClusterData object (from Invoke-S2DCartographer -PassThru or pipeline)
        and renders publication-quality reports. Supports single or multiple formats in one call.

        HTML, Word, Pdf, Excel are human-readable reports. Json is a structured snapshot
        of the full S2DClusterData object (see docs/schema/cluster-snapshot.md). Csv writes
        one flat table per collector (physical disks, volumes, health checks, waterfall).

        Output files are written to OutputDirectory (default: C:\S2DCartographer).

    .PARAMETER InputObject
        S2DClusterData object from Invoke-S2DCartographer -PassThru. Accepts pipeline input.

    .PARAMETER Format
        One or more output formats: Html, Word, Pdf, Excel, Json, Csv, All.
        All = Html + Word + Pdf + Excel + Json (everything except Csv, which is opt-in).

    .PARAMETER OutputDirectory
        Destination folder for report files. Created if it does not exist.

    .PARAMETER Author
        Author name embedded in the report header.

    .PARAMETER Company
        Company or organization name embedded in the report header.

    .PARAMETER IncludeNonPoolDisks
        Include non-pool disks (boot drives, SAN LUNs) in the Physical Disk Inventory table.
        Default is to show pool members only. Does NOT affect the Json or Csv outputs —
        those always contain every disk with an IsPoolMember flag so downstream tooling
        has full fidelity.

    .EXAMPLE
        Invoke-S2DCartographer -ClusterName clus01 -PassThru | New-S2DReport -Format Html

    .EXAMPLE
        $data = Invoke-S2DCartographer -ClusterName clus01 -PassThru
        New-S2DReport -InputObject $data -Format All -Author "Alex Admin" -Company "Contoso"

    .EXAMPLE
        # Get just the structured data for a downstream script
        $data | New-S2DReport -Format Json -OutputDirectory C:\snapshots

    .OUTPUTS
        string[] — paths to generated report files
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Html', 'Word', 'Pdf', 'Excel', 'Json', 'Csv', 'All')]
        [string[]] $Format,

        [Parameter()]
        [string] $OutputDirectory = 'C:\S2DCartographer',

        [Parameter()]
        [string] $Author = '',

        [Parameter()]
        [string] $Company = '',

        [Parameter()]
        [switch] $IncludeNonPoolDisks
    )

    process {
        if ($InputObject -isnot [S2DClusterData]) {
            throw "InputObject must be an S2DClusterData object. Use Invoke-S2DCartographer -PassThru to obtain one."
        }

        # 'All' expands to the four human-readable formats + JSON. Csv is opt-in
        # because it produces multiple files per run and is only useful for
        # spreadsheet / BI consumers. When the caller passes -Format All, Csv,
        # union the two so All-expansion + extras both land.
        $effectiveFormats = if ('All' -in $Format) {
            @('Html', 'Word', 'Pdf', 'Excel', 'Json') + @($Format | Where-Object { $_ -ne 'All' }) | Select-Object -Unique
        } else {
            $Format
        }

        $cn       = $InputObject.ClusterName -replace '[^\w\-]', '_'
        $stamp    = Get-Date -Format 'yyyyMMdd-HHmm'
        $baseName = "S2DCartographer_${cn}_${stamp}"

        $outputFiles = @()

        foreach ($fmt in $effectiveFormats) {
            $ext  = switch ($fmt) {
                'Html'  { 'html' }
                'Word'  { 'docx' }
                'Pdf'   { 'pdf'  }
                'Excel' { 'xlsx' }
                'Json'  { 'json' }
                'Csv'   { 'csv'  }
            }
            $path = Join-Path $OutputDirectory "$baseName.$ext"

            Write-Verbose "Generating $fmt report -> $path"
            try {
                $exportParams = @{
                    ClusterData = $InputObject
                    OutputPath  = $path
                    Author      = $Author
                    Company     = $Company
                }
                if ($IncludeNonPoolDisks) { $exportParams['IncludeNonPoolDisks'] = $true }

                $result = switch ($fmt) {
                    'Html'  { Export-S2DHtmlReport  @exportParams }
                    'Word'  { Export-S2DWordReport  @exportParams }
                    'Pdf'   { Export-S2DPdfReport   @exportParams }
                    'Excel' { Export-S2DExcelReport @exportParams }
                    'Json'  { Export-S2DJsonReport  @exportParams }
                    'Csv'   { Export-S2DCsvReport   @exportParams }
                }
                if ($result) { $outputFiles += $result }
            }
            catch {
                Write-Warning "$fmt report failed: $_"
            }
        }

        $outputFiles
    }
}
