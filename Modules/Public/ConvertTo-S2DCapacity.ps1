function ConvertTo-S2DCapacity {
    <#
    .SYNOPSIS
        Converts a storage capacity value to a dual-unit S2DCapacity object.

    .DESCRIPTION
        Takes a capacity expressed in bytes, TB (decimal/drive-label), TiB (binary/Windows),
        GB (decimal), or GiB (binary) and returns an S2DCapacity object containing all unit
        representations plus a Display string showing both TiB and TB.

        This is the canonical conversion utility used throughout S2DCartographer to eliminate
        TiB vs TB confusion.

    .PARAMETER Bytes
        Capacity in bytes (int64).

    .PARAMETER TB
        Capacity in terabytes — decimal (drive manufacturer labeling). 1 TB = 1,000,000,000,000 bytes.

    .PARAMETER TiB
        Capacity in tebibytes — binary (Windows reporting). 1 TiB = 1,099,511,627,776 bytes.

    .PARAMETER GB
        Capacity in gigabytes — decimal. 1 GB = 1,000,000,000 bytes.

    .PARAMETER GiB
        Capacity in gibibytes — binary. 1 GiB = 1,073,741,824 bytes.

    .EXAMPLE
        ConvertTo-S2DCapacity -Bytes 3840755982336
        # Returns: 3.49 TiB (3.84 TB)

    .EXAMPLE
        ConvertTo-S2DCapacity -TB 1.92
        # Returns: 1.75 TiB (1.92 TB)

    .EXAMPLE
        ConvertTo-S2DCapacity -TiB 13.97
        # Returns: 13.97 TiB (15.36 TB)

    .OUTPUTS
        S2DCapacity
    #>
    [CmdletBinding(DefaultParameterSetName = 'Bytes')]
    [OutputType('S2DCapacity')]
    param(
        [Parameter(ParameterSetName = 'Bytes', Mandatory, ValueFromPipeline, Position = 0)]
        [int64] $Bytes,

        [Parameter(ParameterSetName = 'TB', Mandatory)]
        [double] $TB,

        [Parameter(ParameterSetName = 'TiB', Mandatory)]
        [double] $TiB,

        [Parameter(ParameterSetName = 'GB', Mandatory)]
        [double] $GB,

        [Parameter(ParameterSetName = 'GiB', Mandatory)]
        [double] $GiB
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Bytes' { [S2DCapacity]::new($Bytes) }
            'TB'    { [S2DCapacity]::FromTB($TB) }
            'TiB'   { [S2DCapacity]::FromTiB($TiB) }
            'GB'    { [S2DCapacity]::new([int64]($GB * 1000000000)) }
            'GiB'   { [S2DCapacity]::FromGiB($GiB) }
        }
    }
}
