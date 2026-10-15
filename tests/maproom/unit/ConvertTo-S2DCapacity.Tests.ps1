#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Pester unit tests for ConvertTo-S2DCapacity.

.DESCRIPTION
    Tests all parameter sets (-Bytes, -TB, -TiB, -GB, -GiB), verifies the S2DCapacity
    object's computed properties (TiB, TB, GiB, GB, Display), and validates pipeline input.

    Drive sizes used:  960 GB SSD / 1.92 TB NVMe / 3.84 TB NVMe / 7.68 TB NVMe / 15.36 TB NVMe
                       250 GiB infrastructure volume

    Reference math (all rounded to 2 decimal places by the S2DCapacity class):
      1 TiB = 1,099,511,627,776 bytes   (binary)
      1 TB  = 1,000,000,000,000 bytes   (decimal)
      1 GiB = 1,073,741,824 bytes
      1 GB  = 1,000,000,000 bytes
#>
BeforeAll {
    $psm1 = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\S2DCartographer.psm1')
    Import-Module $psm1 -Force
}

Describe 'ConvertTo-S2DCapacity' {

    Context '-Bytes parameter set' {

        It 'returns an S2DCapacity object' {
            $result = ConvertTo-S2DCapacity -Bytes 3840000000000
            $result.GetType().Name | Should -Be 'S2DCapacity'
        }

        It 'sets the Bytes property exactly' {
            $result = ConvertTo-S2DCapacity -Bytes 3840000000000
            $result.Bytes | Should -Be 3840000000000
        }

        It 'calculates TiB for a 3.84 TB NVMe disk (raw bytes)' {
            # 3,840,000,000,000 / 1,099,511,627,776 = 3.4924... → 3.49
            $result = ConvertTo-S2DCapacity -Bytes 3840000000000
            $result.TiB | Should -Be 3.49
        }

        It 'calculates TB for a 3.84 TB NVMe disk (raw bytes)' {
            $result = ConvertTo-S2DCapacity -Bytes 3840000000000
            $result.TB | Should -Be 3.84
        }

        It 'accepts pipeline input' {
            $result = 1920000000000 | ConvertTo-S2DCapacity
            $result.TiB | Should -Be 1.75
        }

        It 'accepts positional argument' {
            $result = ConvertTo-S2DCapacity 7680000000000
            $result.TiB | Should -Be 6.98
        }
    }

    Context '-TB parameter set (NVMe drive nominal sizes)' {

        It 'converts 0.96 TB (960 GB SSD) correctly' {
            # 960,000,000,000 bytes → 0.87 TiB
            $result = ConvertTo-S2DCapacity -TB 0.96
            $result.TiB | Should -Be 0.87
            $result.TB  | Should -Be 0.96
        }

        It 'converts 1.92 TB NVMe correctly' {
            # 1,920,000,000,000 bytes → 1.75 TiB
            $result = ConvertTo-S2DCapacity -TB 1.92
            $result.TiB | Should -Be 1.75
            $result.TB  | Should -Be 1.92
        }

        It 'converts 3.84 TB NVMe correctly' {
            # 3,840,000,000,000 bytes → 3.49 TiB
            $result = ConvertTo-S2DCapacity -TB 3.84
            $result.TiB | Should -Be 3.49
            $result.TB  | Should -Be 3.84
        }

        It 'converts 7.68 TB NVMe correctly' {
            # 7,680,000,000,000 bytes → 6.98 TiB
            $result = ConvertTo-S2DCapacity -TB 7.68
            $result.TiB | Should -Be 6.98
            $result.TB  | Should -Be 7.68
        }

        It 'converts 15.36 TB NVMe correctly' {
            # 15,360,000,000,000 bytes → 13.97 TiB
            $result = ConvertTo-S2DCapacity -TB 15.36
            $result.TiB | Should -Be 13.97
            $result.TB  | Should -Be 15.36
        }
    }

    Context '-TiB parameter set' {

        It 'converts 1.75 TiB round-trip correctly' {
            # [int64](1.75 × 1,099,511,627,776) = 1,924,145,348,608 → TiB = 1.75, TB = 1.92
            $result = ConvertTo-S2DCapacity -TiB 1.75
            $result.TiB | Should -Be 1.75
            $result.TB  | Should -Be 1.92
        }

        It 'converts 3.49 TiB to expected bytes band' {
            $result = ConvertTo-S2DCapacity -TiB 3.49
            $result.Bytes | Should -Be ([int64](3.49 * 1099511627776))
        }
    }

    Context '-GiB parameter set' {

        It 'converts 250 GiB (infrastructure volume) correctly' {
            # [int64](250 × 1,073,741,824) = 268,435,456,000 bytes
            $result = ConvertTo-S2DCapacity -GiB 250
            $result.GiB     | Should -Be 250
            $result.Bytes   | Should -Be 268435456000
        }
    }

    Context '-GB parameter set' {

        It 'converts 960 GB SSD correctly' {
            # 960 × 1,000,000,000 = 960,000,000,000 bytes → 0.87 TiB
            $result = ConvertTo-S2DCapacity -GB 960
            $result.GB  | Should -Be 960
            $result.TiB | Should -Be 0.87
        }
    }

    Context 'Display property format' {

        It 'formats Display as "X.XX TiB (Y.YY TB)"' {
            $result = ConvertTo-S2DCapacity -TB 3.84
            $result.Display | Should -Be '3.49 TiB (3.84 TB)'
        }

        It 'Display matches ToString() output' {
            $result = ConvertTo-S2DCapacity -TB 1.92
            $result.ToString() | Should -Be $result.Display
        }
    }

    Context 'Unit consistency across parameter sets' {

        It '-Bytes and -TB for same size return same TiB' {
            $fromBytes = ConvertTo-S2DCapacity -Bytes 3840000000000
            $fromTB    = ConvertTo-S2DCapacity -TB 3.84
            $fromBytes.TiB | Should -Be $fromTB.TiB
        }

        It '-TiB round-trip: FromTiB(x).TiB -eq x' {
            foreach ($tib in @(1.0, 2.5, 6.98, 13.97)) {
                $result = ConvertTo-S2DCapacity -TiB $tib
                $result.TiB | Should -Be $tib -Because "TiB=$tib should round-trip"
            }
        }
    }
}
