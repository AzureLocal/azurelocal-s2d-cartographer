# S2DCapacity class — dual-unit capacity representation used throughout S2DCartographer

class S2DCapacity {
    [int64]  $Bytes
    [double] $TiB
    [double] $TB
    [double] $GiB
    [double] $GB
    [string] $Display

    S2DCapacity([int64]$bytes) {
        $this.Bytes   = $bytes
        $this.TiB     = [math]::Round($bytes / 1099511627776, 2)
        $this.TB      = [math]::Round($bytes / 1000000000000, 2)
        $this.GiB     = [math]::Round($bytes / 1073741824, 2)
        $this.GB      = [math]::Round($bytes / 1000000000, 2)
        $this.Display = "$($this.TiB) TiB ($($this.TB) TB)"
    }

    # Convenience: construct from TB (decimal — drive label value)
    static [S2DCapacity] FromTB([double]$tb) {
        return [S2DCapacity]::new([int64]($tb * 1000000000000))
    }

    # Convenience: construct from TiB (binary — Windows-reported value)
    static [S2DCapacity] FromTiB([double]$tib) {
        return [S2DCapacity]::new([int64]($tib * 1099511627776))
    }

    # Convenience: construct from GiB
    static [S2DCapacity] FromGiB([double]$gib) {
        return [S2DCapacity]::new([int64]($gib * 1073741824))
    }

    [string] ToString() {
        return $this.Display
    }
}
