#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
#Requires -Version 7.0
# Regression tests for AB#265 (exec-summary table cramped) and AB#266
# (overall Word document layout defects).
#
# The exporter builds raw Open XML without requiring Word/Office - all assertions
# operate on the generated XML string extracted from the DOCX zip, so these
# tests are CI-safe (no Word/Office installation required).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    $outPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "CartographerWordTest_$([System.Guid]::NewGuid().ToString('N')).docx"
    )

    # Build stub data and invoke the private exporter entirely inside the module
    # scope so that S2DClusterData, S2DCapacity etc. are in scope.
    $script:docXml = InModuleScope S2DCartographer -Parameters @{ OutPath = $outPath } {
        param($OutPath)

        # -- Minimal stub S2DCapacity objects ---------------------------------
        $cap = [S2DCapacity]::new([int64]29990000000000)   # ~27.28 TiB / 29.99 TB
        $capSmall = [S2DCapacity]::new([int64]3840000000000) # 3.84 TB

        # -- S2DCapacityWaterfall ----------------------------------------------
        $wf = [S2DCapacityWaterfall]::new()
        $wf.RawCapacity              = $cap
        $wf.UsableCapacity           = [S2DCapacity]::new([int64]14990000000000)
        $wf.ReserveStatus            = 'Adequate'
        $wf.ReserveRecommended       = $capSmall
        $wf.ReserveActual            = [S2DCapacity]::new([int64]5000000000000)
        $wf.BlendedEfficiencyPercent = 50
        $wf.AvailableForVolumes      = [S2DCapacity]::new([int64]14990000000000)
        $wf.PlanningLine70Pct        = [S2DCapacity]::new([int64]10490000000000)
        $wf.IsAbove70PctLine         = $false
        $wf.Stages                   = @()

        # -- S2DStoragePool ----------------------------------------------------
        $pool = [S2DStoragePool]::new()
        $pool.TotalSize       = $cap
        $pool.RemainingSize   = [S2DCapacity]::new([int64]14300000000000)
        $pool.OvercommitRatio = 1.2

        # -- S2DVolume ---------------------------------------------------------
        $vol = [S2DVolume]::new()
        $vol.FriendlyName           = 'UserData01'
        $vol.IsInfrastructureVolume = $false
        $vol.ResiliencySettingName  = 'Mirror'
        $vol.NumberOfDataCopies     = 2
        $vol.Size                   = [S2DCapacity]::new([int64]5500000000000)
        $vol.FootprintOnPool        = [S2DCapacity]::new([int64]11000000000000)
        $vol.EfficiencyPercent      = 50
        $vol.ProvisioningType       = 'Fixed'
        $vol.HealthStatus           = 'Healthy'

        # -- Physical disk (PSCustomObject - exporter reads named properties) --
        $disk = [PSCustomObject]@{
            NodeName        = 'NODE01'
            FriendlyName    = 'ACME SSD 3.84T'
            MediaType       = 'SSD'
            Role            = 'Capacity'
            Size            = $capSmall
            WearPercentage  = 12
            HealthStatus    = 'Healthy'
            FirmwareVersion = 'XC1A'
            IsPoolMember    = $true
        }

        # -- S2DHealthCheck ----------------------------------------------------
        $hc = [S2DHealthCheck]::new()
        $hc.CheckName   = 'DriveHealth'
        $hc.Severity    = 'High'
        $hc.Status      = 'Pass'
        $hc.Details     = 'All drives healthy'
        $hc.Remediation = ''

        # -- S2DClusterData ----------------------------------------------------
        $cluster = [S2DClusterData]::new()
        $cluster.ClusterName      = 'TestCluster'
        $cluster.NodeCount        = 2
        $cluster.CapacityWaterfall = $wf
        $cluster.StoragePool      = $pool
        $cluster.Volumes          = @($vol)
        $cluster.PhysicalDisks    = @($disk)
        $cluster.HealthChecks     = @($hc)
        $cluster.OverallHealth    = 'Healthy'
        $cluster.CollectedAt      = [datetime]::UtcNow

        # -- Call the private exporter -----------------------------------------
        $docxPath = Export-S2DWordReport `
            -ClusterData $cluster `
            -OutputPath  $OutPath `
            -Author      'Test Author' `
            -Company     'Test Co'

        # -- Extract word/document.xml from the DOCX (zip) --------------------
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($docxPath)
        try {
            $entry = $zip.GetEntry('word/document.xml')
            $sr    = [System.IO.StreamReader]::new($entry.Open())
            $sr.ReadToEnd()
        } finally {
            $zip.Dispose()
        }
    }

    if (Test-Path $outPath) { Remove-Item $outPath -Force }
}

# -----------------------------------------------------------------------------
Describe 'AB#266 - Page margins: standard 1-inch (1440 twips each side)' {

    It 'sectPr pgMar top is 1440 twips' {
        $script:docXml | Should -Match 'w:top="1440"'
    }

    It 'sectPr pgMar right is 1440 twips' {
        $script:docXml | Should -Match 'w:right="1440"'
    }

    It 'sectPr pgMar bottom is 1440 twips' {
        $script:docXml | Should -Match 'w:bottom="1440"'
    }

    It 'sectPr pgMar left is 1440 twips' {
        $script:docXml | Should -Match 'w:left="1440"'
    }
}

# -----------------------------------------------------------------------------
Describe 'AB#266 - All tables use explicit dxa width, not auto' {

    It 'document XML contains no w:type="auto" table width declarations' {
        # Every tblW must be dxa - auto leaves sizing to Word and causes overflow
        $script:docXml | Should -Not -Match 'w:type="auto"'
    }

    It 'tblLayout fixed is present on at least one table - prevents Word autofit override' {
        $script:docXml | Should -Match 'w:type="fixed"'
    }
}

# -----------------------------------------------------------------------------
Describe 'AB#266 - Banner and SectionHeader span full usable page width (9360 dxa)' {

    It 'at least one tblW declares 9360 dxa' {
        $script:docXml | Should -Match 'w:w="9360" w:type="dxa"'
    }

    It 'multiple elements declare 9360 dxa width (banner + section headers + data tables)' {
        # -split on N occurrences yields N+1 parts; assert count > 3 means at least 3 matches
        $parts = $script:docXml -split 'w:w="9360" w:type="dxa"'
        ($parts.Count - 1) | Should -BeGreaterThan 2
    }

    It 'SectionHeader cells include tblCellMar padding (text not flush against colored edge)' {
        # Both Banner and SectionHeader now carry <w:tblCellMar> - at least 2 occurrences
        $parts = $script:docXml -split '<w:tblCellMar>'
        ($parts.Count - 1) | Should -BeGreaterThan 1
    }
}

# -----------------------------------------------------------------------------
Describe 'AB#265 - Executive summary table: explicit 35/65 column widths' {

    It 'Metric column is 3276 dxa (35% of 9360 page width)' {
        $script:docXml | Should -Match "w:w='3276' w:type='dxa'"
    }

    It 'Value column is 6084 dxa (65% of 9360 page width)' {
        $script:docXml | Should -Match "w:w='6084' w:type='dxa'"
    }

    It 'no header or data cell uses w:w=0 (which caused the auto-squeeze)' {
        # Cell widths must never be zero
        $script:docXml | Should -Not -Match "w:w='0' w:type='dxa'"
    }
}

# -----------------------------------------------------------------------------
Describe 'AB#265 - KPI tile table: per-cell widths and legible value font size' {

    It 'KPI tile table itself spans 9360 dxa' {
        # Verified indirectly - the KPI tblW is one of the 9360 occurrences above.
        # This test explicitly asserts the font reduction (was 40, now 32 half-points).
        $script:docXml | Should -Match 'w:sz w:val="32"'
    }

    It 'KPI value run no longer uses the original oversized 40 half-point font' {
        # The pattern <w:b/><w:color .../><w:sz w:val="40"> was the old KPI value run.
        $script:docXml | Should -Not -Match '<w:b/><w:color[^/]*/><w:sz w:val="40"'
    }

    It 'KPI cells include explicit tcMar cell padding' {
        $script:docXml | Should -Match '<w:tcMar>'
    }
}

# -----------------------------------------------------------------------------
Describe 'AB#266 - Wide data tables: proportioned explicit column widths present' {

    It 'Disk Inventory Node column width (1340 dxa) appears in XML' {
        $script:docXml | Should -Match "w:w='1340' w:type='dxa'"
    }

    It 'Disk Inventory Model column width (2000 dxa) appears in XML' {
        $script:docXml | Should -Match "w:w='2000' w:type='dxa'"
    }

    It 'Volume Map Volume-name column width (1680 dxa) appears in XML' {
        $script:docXml | Should -Match "w:w='1680' w:type='dxa'"
    }

    It 'Volume Map Resiliency column width (1120 dxa) appears in XML' {
        $script:docXml | Should -Match "w:w='1120' w:type='dxa'"
    }
}

