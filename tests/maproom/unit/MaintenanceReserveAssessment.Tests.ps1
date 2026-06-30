#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Unit tests for Get-S2DMaintenanceReserveAssessment (AB#maintenancereserve).

.DESCRIPTION
    Validates the N+1/N+2 maintenance-reserve compliance assessment against
    synthetic fixtures derived from the POC golden cluster:
      - 2 nodes, 4 x 3.84 TB NVMe each
      - nodeRawBytes (largest node) = 4 x 3,840,000,000,000 = 15,360,000,000,000 bytes

    All S2DCapacity construction is inside InModuleScope (S2DCapacity is module-private).
    Storage collection shims are mocked at the Describe level — Linux CI safe.
    Uses [System.IO.Path]::GetTempPath() for any temp paths (cross-platform).

    Math:
      nodeRawBytes  = 4 x 3,840,000,000,000 = 15,360,000,000,000
      reserve       = 3,840,000,000,000 (1 drive)
      poolFreeMeets = 20,000,000,000,000  → headroom = 16,160,000,000,000 > 15,360,000,000,000 → Meets
      poolFreeNoMt  = 5,000,000,000,000   → headroom =  1,160,000,000,000 < 15,360,000,000,000 → Does not meet
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force

    # Shared fixture constants (accessible to all Describes via $script:)
    $script:DiskSizeBytes   = [int64]3840000000000   # 3.84 TB NVMe
    $script:DisksPerNode    = 4
    $script:NodeCount       = 2
    $script:NodeRawBytes    = [int64]($script:DisksPerNode * $script:DiskSizeBytes)  # 15,360,000,000,000
    $script:ReserveBytes    = [int64]3840000000000   # 3.84 TB (1 drive)
    $script:PoolFreeMeets   = [int64]20000000000000  # 20 TB  → headroom 16.16 TB > 15.36 TB
    $script:PoolFreeNoMeet  = [int64]5000000000000   # 5 TB   → headroom 1.16 TB < 15.36 TB

    # Build POC capacity-disk array (2 nodes x 4 disks each) at script scope
    $script:PocDisks = @(
        foreach ($n in 1..$script:NodeCount) {
            foreach ($d in 1..$script:DisksPerNode) {
                [PSCustomObject]@{
                    NodeName     = "poc-node-0$n"
                    FriendlyName = "SAMSUNG MZQLB3T8HALS #$d"
                    Role         = 'Capacity'
                    IsPoolMember = $true
                    SizeBytes    = $script:DiskSizeBytes
                }
            }
        }
    )
}

# ── Describe 1: N+1 Meets case ────────────────────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — N+1 Meets (POC golden)' {

    BeforeAll {
        # All computation must run inside InModuleScope because S2DCapacity is defined there.
        # Pass every outer variable via -Parameters so InModuleScope can see it.
        $script:result1 = InModuleScope S2DCartographer -Parameters @{
            PoolFree  = $script:PoolFreeMeets
            Reserve   = $script:ReserveBytes
            Disks     = $script:PocDisks
            NC        = $script:NodeCount
        } {
            param($PoolFree, $Reserve, $Disks, $NC)
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  $PoolFree `
                -RebuildReserveRecommendedBytes  $Reserve `
                -PhysicalDisks                   $Disks `
                -NodeCount                       $NC `
                -Target                          'N+1'
        }
    }

    It 'returns a non-null result' {
        $script:result1 | Should -Not -BeNullOrEmpty
    }

    It 'Target is N+1' {
        $script:result1.Target | Should -Be 'N+1'
    }

    It 'Status is Meets' {
        $script:result1.Status | Should -Be 'Meets'
    }

    It 'Meets is $true' {
        $script:result1.Meets | Should -BeTrue
    }

    It 'RequiredCapacity.Bytes equals one node raw bytes (15,360,000,000,000)' {
        $script:result1.RequiredCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'RequiredCapacity is an S2DCapacity object' {
        $script:result1.RequiredCapacity.GetType().Name | Should -Be 'S2DCapacity'
    }

    It 'AvailableHeadroom.Bytes equals poolFree - reserve (16,160,000,000,000)' {
        # 20,000,000,000,000 - 3,840,000,000,000 = 16,160,000,000,000
        $script:result1.AvailableHeadroom.Bytes | Should -Be ([int64]16160000000000)
    }

    It 'AvailableHeadroom is an S2DCapacity object' {
        $script:result1.AvailableHeadroom.GetType().Name | Should -Be 'S2DCapacity'
    }

    It 'Note is non-empty' {
        $script:result1.Note | Should -Not -BeNullOrEmpty
    }

    It 'Note contains two-node informational text for 2-node cluster' {
        $script:result1.Note | Should -Match 'two-way mirror'
    }
}

# ── Describe 2: N+1 Does-not-meet case ───────────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — N+1 Does not meet (insufficient headroom)' {

    BeforeAll {
        $script:result2 = InModuleScope S2DCartographer -Parameters @{
            PoolFree  = $script:PoolFreeNoMeet
            Reserve   = $script:ReserveBytes
            Disks     = $script:PocDisks
            NC        = $script:NodeCount
        } {
            param($PoolFree, $Reserve, $Disks, $NC)
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  $PoolFree `
                -RebuildReserveRecommendedBytes  $Reserve `
                -PhysicalDisks                   $Disks `
                -NodeCount                       $NC `
                -Target                          'N+1'
        }
    }

    It 'returns a non-null result' {
        $script:result2 | Should -Not -BeNullOrEmpty
    }

    It 'Meets is $false' {
        $script:result2.Meets | Should -BeFalse
    }

    It 'Status is "Does not meet"' {
        $script:result2.Status | Should -Be 'Does not meet'
    }

    It 'RequiredCapacity.Bytes equals one node raw bytes (15,360,000,000,000)' {
        $script:result2.RequiredCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'AvailableHeadroom.Bytes equals 1,160,000,000,000 (5TB - 3.84TB)' {
        # 5,000,000,000,000 - 3,840,000,000,000 = 1,160,000,000,000
        $script:result2.AvailableHeadroom.Bytes | Should -Be ([int64]1160000000000)
    }

    It 'RequiredCapacity.TB is approx 15.36 (+/-0.01)' {
        $script:result2.RequiredCapacity.TB | Should -BeGreaterThan 15.35
        $script:result2.RequiredCapacity.TB | Should -BeLessThan    15.37
    }

    It 'AvailableHeadroom.TB is approx 1.16 (+/-0.01)' {
        $script:result2.AvailableHeadroom.TB | Should -BeGreaterThan 1.15
        $script:result2.AvailableHeadroom.TB | Should -BeLessThan    1.17
    }
}

# ── Describe 3: Target=None skips assessment ──────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — Target=None skips assessment' {

    BeforeAll {
        $script:result3 = InModuleScope S2DCartographer -Parameters @{
            PoolFree  = $script:PoolFreeMeets
            Reserve   = $script:ReserveBytes
            Disks     = $script:PocDisks
            NC        = $script:NodeCount
        } {
            param($PoolFree, $Reserve, $Disks, $NC)
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  $PoolFree `
                -RebuildReserveRecommendedBytes  $Reserve `
                -PhysicalDisks                   $Disks `
                -NodeCount                       $NC `
                -Target                          'None'
        }
    }

    It 'returns a non-null result' {
        $script:result3 | Should -Not -BeNullOrEmpty
    }

    It 'Target is None' {
        $script:result3.Target | Should -Be 'None'
    }

    It 'Meets is $true (None always passes)' {
        $script:result3.Meets | Should -BeTrue
    }

    It 'Status is Meets' {
        $script:result3.Status | Should -Be 'Meets'
    }

    It 'RequiredCapacity.Bytes is 0' {
        $script:result3.RequiredCapacity.Bytes | Should -Be 0
    }

    It 'Note mentions disabled/Target=None' {
        $script:result3.Note | Should -Match 'None'
    }
}

# ── Describe 4: N+2 case — required doubles ───────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — N+2 requires 2x node capacity' {

    BeforeAll {
        $script:result4 = InModuleScope S2DCartographer -Parameters @{
            PoolFree  = $script:PoolFreeMeets
            Reserve   = $script:ReserveBytes
            Disks     = $script:PocDisks
            NC        = $script:NodeCount
        } {
            param($PoolFree, $Reserve, $Disks, $NC)
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  $PoolFree `
                -RebuildReserveRecommendedBytes  $Reserve `
                -PhysicalDisks                   $Disks `
                -NodeCount                       $NC `
                -Target                          'N+2'
        }
    }

    It 'Target is N+2' {
        $script:result4.Target | Should -Be 'N+2'
    }

    It 'RequiredCapacity.Bytes equals 2x node raw bytes (30,720,000,000,000)' {
        $script:result4.RequiredCapacity.Bytes | Should -Be ([int64]30720000000000)
    }

    It 'Does not meet (headroom 16.16TB < required 30.72TB)' {
        # headroom = 16,160,000,000,000 < 30,720,000,000,000
        $script:result4.Meets | Should -BeFalse
    }
}

# ── Describe 5: Empty/null input graceful handling ────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — empty and null inputs return gracefully' {

    It 'empty PhysicalDisks array returns Unknown status without throwing' {
        $r = InModuleScope S2DCartographer {
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  ([int64]10000000000000) `
                -RebuildReserveRecommendedBytes  ([int64]1000000000000) `
                -PhysicalDisks                   @() `
                -NodeCount                       2 `
                -Target                          'N+1'
        }
        $r | Should -Not -BeNullOrEmpty
        $r.Status | Should -Be 'Unknown'
    }

    It 'null PhysicalDisks returns Unknown status without throwing' {
        $r = InModuleScope S2DCartographer {
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  ([int64]10000000000000) `
                -RebuildReserveRecommendedBytes  ([int64]1000000000000) `
                -PhysicalDisks                   $null `
                -NodeCount                       2 `
                -Target                          'N+1'
        }
        $r | Should -Not -BeNullOrEmpty
        $r.Status | Should -Be 'Unknown'
    }

    It 'no capacity disks (only cache-role disks) returns Unknown status without throwing' {
        $r = InModuleScope S2DCartographer {
            $cacheOnlyDisks = @(
                [PSCustomObject]@{ NodeName='n01'; Role='Cache'; IsPoolMember=$true; SizeBytes=[int64]400000000000 },
                [PSCustomObject]@{ NodeName='n02'; Role='Cache'; IsPoolMember=$true; SizeBytes=[int64]400000000000 }
            )
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  ([int64]10000000000000) `
                -RebuildReserveRecommendedBytes  ([int64]1000000000000) `
                -PhysicalDisks                   $cacheOnlyDisks `
                -NodeCount                       2 `
                -Target                          'N+1'
        }
        $r | Should -Not -BeNullOrEmpty
        $r.Status | Should -Be 'Unknown'
    }

    It 'PoolFreeBytes=0 and RebuildReserve=0 yields headroom=0 and Does not meet' {
        $r = InModuleScope S2DCartographer -Parameters @{
            Disks = $script:PocDisks
            NC    = $script:NodeCount
        } {
            param($Disks, $NC)
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  ([int64]0) `
                -RebuildReserveRecommendedBytes  ([int64]0) `
                -PhysicalDisks                   $Disks `
                -NodeCount                       $NC `
                -Target                          'N+1'
        }
        $r | Should -Not -BeNullOrEmpty
        $r.Status                  | Should -Be 'Does not meet'
        $r.Meets                   | Should -BeFalse
        $r.AvailableHeadroom.Bytes | Should -Be 0
    }

    It 'disks with null SizeBytes are treated as 0 and result in Unknown (zero largest node)' {
        $r = InModuleScope S2DCartographer {
            $badDisks = @(
                [PSCustomObject]@{ NodeName='n01'; Role='Capacity'; IsPoolMember=$true; SizeBytes=$null },
                [PSCustomObject]@{ NodeName='n02'; Role='Capacity'; IsPoolMember=$true; SizeBytes=$null }
            )
            Get-S2DMaintenanceReserveAssessment `
                -PoolFreeBytes                  ([int64]10000000000000) `
                -RebuildReserveRecommendedBytes  ([int64]1000000000000) `
                -PhysicalDisks                   $badDisks `
                -NodeCount                       2 `
                -Target                          'N+1'
        }
        $r | Should -Not -BeNullOrEmpty
        $r.Status | Should -Be 'Unknown'
        $r.Note   | Should -Not -BeNullOrEmpty
    }
}
