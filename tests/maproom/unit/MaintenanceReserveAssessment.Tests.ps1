#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Unit tests for Get-S2DMaintenanceReserveAssessment (v1.9.0 re-frame).

.DESCRIPTION
    Validates the N+1/N+2 compute-resiliency context note against synthetic fixtures
    derived from the POC golden cluster:
      - 2 nodes, 4 x 3.84 TB NVMe each
      - nodeRawBytes (largest node) = 4 x 3,840,000,000,000 = 15,360,000,000,000 bytes

    FRAMING: N+1/N+2 is a COMPUTE resiliency target (CPU + RAM headroom for node drain
    or loss) — NOT a storage-pool reserve. The function now returns Status='Info' (never
    a storage pass/fail). It surfaces the largest-node raw capacity as context only.
    Meets is always $null. AvailableHeadroom is always $null.

    All S2DCapacity construction is inside InModuleScope (S2DCapacity is module-private).
    Storage collection shims are mocked at the Describe level — Linux CI safe.
    Uses [System.IO.Path]::GetTempPath() for any temp paths (cross-platform).
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
    $script:PoolFreeMeets   = [int64]20000000000000  # 20 TB (retained for API compat)
    $script:PoolFreeNoMeet  = [int64]5000000000000   # 5 TB  (retained for API compat)

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

# ── Describe 1: N+1 informational result ─────────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — N+1 informational context (POC golden)' {

    BeforeAll {
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

    It 'Status is Info (not a storage pass/fail)' {
        $script:result1.Status | Should -Be 'Info'
    }

    It 'Meets is $null (not a storage compliance verdict)' {
        $script:result1.Meets | Should -BeNullOrEmpty
    }

    It 'AvailableHeadroom is $null (not a storage measurement)' {
        $script:result1.AvailableHeadroom | Should -BeNullOrEmpty
    }

    It 'LargestNodeCapacity.Bytes equals one node raw bytes (15,360,000,000,000)' {
        $script:result1.LargestNodeCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'LargestNodeCapacity is an S2DCapacity object' {
        $script:result1.LargestNodeCapacity.GetType().Name | Should -Be 'S2DCapacity'
    }

    It 'ContextCapacity.Bytes equals 1x node raw bytes (N+1 multiplier)' {
        $script:result1.ContextCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'RequiredCapacity retained for JSON schema compat and equals ContextCapacity' {
        $script:result1.RequiredCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'Note is non-empty' {
        $script:result1.Note | Should -Not -BeNullOrEmpty
    }

    It 'Note mentions COMPUTE (not a storage requirement)' {
        $script:result1.Note | Should -Match '(?i)COMPUTE'
    }

    It 'Note contains two-node informational text for 2-node cluster' {
        $script:result1.Note | Should -Match 'two-way mirror'
    }
}

# ── Describe 2: N+1 with lower pool free — still Info (no storage fail) ──────
Describe 'Get-S2DMaintenanceReserveAssessment — N+1 with low pool free is still Info (no storage verdict)' {

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

    It 'Status is Info regardless of pool free space (not a storage verdict)' {
        $script:result2.Status | Should -Be 'Info'
    }

    It 'Meets is $null (compute context only)' {
        $script:result2.Meets | Should -BeNullOrEmpty
    }

    It 'LargestNodeCapacity.Bytes still equals one node raw bytes (15,360,000,000,000)' {
        $script:result2.LargestNodeCapacity.Bytes | Should -Be ([int64]15360000000000)
    }

    It 'LargestNodeCapacity.TB is approx 15.36 (+/-0.01)' {
        $script:result2.LargestNodeCapacity.TB | Should -BeGreaterThan 15.35
        $script:result2.LargestNodeCapacity.TB | Should -BeLessThan    15.37
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

    It 'Status is Info when Target=None' {
        $script:result3.Status | Should -Be 'Info'
    }

    It 'Meets is $null (no storage verdict even for None target)' {
        $script:result3.Meets | Should -BeNullOrEmpty
    }

    It 'Note mentions disabled/Target=None' {
        $script:result3.Note | Should -Match 'None'
    }
}

# ── Describe 4: N+2 case — context doubles ───────────────────────────────────
Describe 'Get-S2DMaintenanceReserveAssessment — N+2 context is 2x node capacity' {

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

    It 'Status is Info for N+2' {
        $script:result4.Status | Should -Be 'Info'
    }

    It 'ContextCapacity.Bytes equals 2x node raw bytes (30,720,000,000,000)' {
        $script:result4.ContextCapacity.Bytes | Should -Be ([int64]30720000000000)
    }

    It 'Meets is $null for N+2' {
        $script:result4.Meets | Should -BeNullOrEmpty
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

    It 'PoolFreeBytes=0 returns Info status (pool free no longer drives the verdict)' {
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
        $r.Status | Should -Be 'Info'
        $r.Meets  | Should -BeNullOrEmpty
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
