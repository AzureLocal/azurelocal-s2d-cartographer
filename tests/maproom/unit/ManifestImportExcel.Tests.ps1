#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Asserts that the module manifest validates and imports cleanly without ImportExcel
    being installed, and that RequiredModules does not list ImportExcel.

.DESCRIPTION
    Regression test for the fix introduced in v1.10.1:
    ImportExcel moved from RequiredModules (hard dependency) to an optional runtime
    dependency loaded on-demand inside Export-S2DExcelReport. This ensures CI
    (which installs only Pester/PSScriptAnalyzer) can run Test-ModuleManifest and
    import the module without pre-installing ImportExcel.
#>

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..') | Select-Object -ExpandProperty Path
    $psd1Path  = Join-Path $repoRoot 'S2DCartographer.psd1'
    $psm1Path  = Join-Path $repoRoot 'S2DCartographer.psm1'
    $script:Psd1Path = $psd1Path
    $script:Psm1Path = $psm1Path
}

Describe 'Module manifest — ImportExcel is an optional dependency' {

    Context 'Test-ModuleManifest' {

        It 'succeeds without ImportExcel installed' {
            # Test-ModuleManifest validates the psd1 structure and resolves
            # RequiredModules. If ImportExcel were still in RequiredModules
            # this would throw when ImportExcel is absent from the runner.
            { Test-ModuleManifest -Path $script:Psd1Path -ErrorAction Stop } | Should -Not -Throw
        }

        It 'returns a manifest with the correct module name' {
            $manifest = Test-ModuleManifest -Path $script:Psd1Path -ErrorAction Stop
            $manifest.Name | Should -Be 'S2DCartographer'
        }

        It 'returns module version 1.10.1 or higher' {
            $manifest = Test-ModuleManifest -Path $script:Psd1Path -ErrorAction Stop
            $manifest.Version | Should -BeGreaterOrEqual ([version]'1.10.1')
        }
    }

    Context 'RequiredModules does not contain ImportExcel' {

        It 'RequiredModules is empty or does not reference ImportExcel' {
            $manifest = Test-ModuleManifest -Path $script:Psd1Path -ErrorAction Stop
            $importExcelEntry = $manifest.RequiredModules |
                Where-Object { $_.Name -eq 'ImportExcel' -or $_ -eq 'ImportExcel' }
            $importExcelEntry | Should -BeNullOrEmpty
        }
    }

    Context 'Import-Module succeeds without ImportExcel' {

        It 'imports the module without error' {
            { Import-Module $script:Psm1Path -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'exports the expected public cmdlets after import' {
            Import-Module $script:Psm1Path -Force
            $exported = (Get-Module S2DCartographer).ExportedFunctions.Keys
            $exported | Should -Contain 'Connect-S2DCluster'
            $exported | Should -Contain 'New-S2DReport'
            $exported | Should -Contain 'Invoke-S2DCartographer'
        }
    }
}
