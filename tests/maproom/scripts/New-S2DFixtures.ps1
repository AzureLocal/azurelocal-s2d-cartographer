<#
.SYNOPSIS
    Generates all 8 S2DCartographer unit-test fixture JSON files in tests/maproom/Fixtures/.

.DESCRIPTION
    Creates scenario-specific fixtures covering: healthy 2-node all-NVMe, 3-node mixed-tier,
    4-node three-way mirror with thin volumes, 4-node mixed resiliency, 16-node enterprise,
    2-node thin-overcommit warning, 3-node insufficient-reserve critical, and single-node.

    All company data uses the IIC (Infinite Improbability Corp) canonical standard.

.EXAMPLE
    .\tests\maproom\scripts\New-S2DFixtures.ps1

.NOTES
    Run from repo root or any location — paths are resolved relative to this script.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixturesDir = Resolve-Path (Join-Path $PSScriptRoot '..\Fixtures')
Write-Host "Generating fixtures to: $fixturesDir" -ForegroundColor Cyan

# ─── Constants ────────────────────────────────────────────────────────────────
$TiB_DIVISOR     = [int64]1099511627776
$TB_DIVISOR      = [int64]1000000000000
$INFRA_VOL_BYTES = [int64]268435456000   # 250 GiB  — Azure Local infrastructure volume
$POOL_OVERHEAD   = 0.005                 # 0.5% pool metadata

# IIC domain constants
$IIC_COMPANY  = 'Infinite Improbability Corp'
$IIC_TENANT   = '00000000-0000-0000-0000-000000000000'
$IIC_SUB      = '33333333-3333-3333-3333-333333333333'
$IIC_RG       = 'rg-iic-compute-01'

# ─── Helpers ──────────────────────────────────────────────────────────────────

function script:BytesToTiB([int64]$b) { [Math]::Round($b / $TiB_DIVISOR, 3) }
function script:BytesToTB([int64]$b)  { [Math]::Round($b / $TB_DIVISOR, 3) }

function script:MakeDisk([string]$node, [int]$num, [string]$role, [string]$media,
                          [int64]$sizeBytes, [string]$model, [string]$fw,
                          [string]$mfr, [int]$wear = 0) {
    $sizeTiB = [Math]::Round($sizeBytes / $TiB_DIVISOR, 3)
    $sizeTB  = [Math]::Round($sizeBytes / $TB_DIVISOR, 3)
    [ordered]@{
        NodeName          = $node
        FriendlyName      = $model
        SerialNumber      = 'IIC-{0}-D{1:D2}' -f $node.ToUpper(), $num
        Model             = $model
        MediaType         = $media
        BusType           = if ($media -eq 'NVMe') { 'NVMe' } else { 'SATA' }
        Role              = $role
        Usage             = if ($role -eq 'Cache') { 'Journal' } else { 'Auto-Select' }
        SizeBytes         = $sizeBytes
        SizeTiB           = $sizeTiB
        SizeTB            = $sizeTB
        SizeDisplay       = "$sizeTiB TiB ($sizeTB TB)"
        FirmwareVersion   = $fw
        Manufacturer      = $mfr
        HealthStatus      = 'Healthy'
        OperationalStatus = 'OK'
        CanPool           = $false
        WearPercentage    = $wear
        Temperature       = 35
        PowerOnHours      = 14400
        ReadErrors        = 0
        WriteErrors       = 0
    }
}

function script:MakeVolume([string]$name, [string]$resiliency, [int]$copies,
                            [int64]$footprintBytes, [string]$provisioning = 'Fixed',
                            [bool]$isInfra = $false, [int64]$allocatedBytes = 0) {
    $effPct  = if ($copies -gt 0) { [Math]::Round(100.0 / $copies, 1) } else { 50.0 }
    $usable  = [long]($footprintBytes / $copies)
    $alloc   = if ($allocatedBytes -gt 0) { $allocatedBytes } else { $usable }
    [ordered]@{
        FriendlyName          = $name
        ResiliencySettingName = $resiliency
        NumberOfDataCopies    = $copies
        ProvisioningType      = $provisioning
        IsInfrastructure      = $isInfra
        FootprintBytes        = $footprintBytes
        FootprintTiB          = [Math]::Round($footprintBytes / $TiB_DIVISOR, 3)
        SizeBytes             = $usable
        SizeTiB               = [Math]::Round($usable / $TiB_DIVISOR, 3)
        AllocatedBytes        = $alloc
        AllocatedTiB          = [Math]::Round($alloc / $TiB_DIVISOR, 3)
        EfficiencyPercent     = $effPct
        HealthStatus          = 'Healthy'
        OperationalStatus     = 'OK'
    }
}

function script:MakeWaterfall([int64]$rawBytes, [int]$nodeCount, [int64]$largestDiskBytes,
                               [int64]$allocatedBytes, [double]$blendedEfficiency = 33.3) {
    $overhead     = [long]($rawBytes * $POOL_OVERHEAD)
    $poolTotal    = $rawBytes - $overhead
    $reserveRec   = [Math]::Min($nodeCount, 4) * $largestDiskBytes
    $free         = $poolTotal - $allocatedBytes
    $reserveStat  = if ($free -ge $reserveRec) { 'Adequate' } elseif ($free -ge ($reserveRec*0.5)) { 'Warning' } else { 'Critical' }
    $available    = $poolTotal - $reserveRec - $INFRA_VOL_BYTES
    $usable       = [long]($available * ($blendedEfficiency / 100.0))
    [ordered]@{
        Raw = [ordered]@{
            Bytes   = $rawBytes
            TiB     = (BytesToTiB $rawBytes)
            TB      = (BytesToTB $rawBytes)
        }
        PoolOverhead = [ordered]@{
            Bytes = $overhead
            TiB   = (BytesToTiB $overhead)
        }
        PoolTotal = [ordered]@{
            Bytes = $poolTotal
            TiB   = (BytesToTiB $poolTotal)
        }
        Reserve = [ordered]@{
            RecommendedBytes = $reserveRec
            RecommendedTiB   = (BytesToTiB $reserveRec)
            ActualFreeBytes  = $free
            ActualFreeTiB    = (BytesToTiB $free)
            Status           = $reserveStat
        }
        InfrastructureVolume = [ordered]@{
            Bytes   = $INFRA_VOL_BYTES
            TiB     = (BytesToTiB $INFRA_VOL_BYTES)
            Present = $true
        }
        Available = [ordered]@{
            Bytes = $available
            TiB   = (BytesToTiB $available)
        }
        ResiliencyEfficiency = [ordered]@{
            BlendedPercent = $blendedEfficiency
        }
        Usable = [ordered]@{
            Bytes = $usable
            TiB   = (BytesToTiB $usable)
            TB    = (BytesToTB $usable)
        }
    }
}

function script:MakeHealthChecks([bool]$reserveOK = $true, [bool]$overcommit = $false,
                                  [bool]$diskHealth = $true, [bool]$volumeHealth = $true,
                                  [bool]$nvmeWear = $true) {
    @(
        [ordered]@{ CheckName='ReserveAdequacy';     Severity='Critical'; Status=if($reserveOK){'Pass'}else{'Fail'};   Details=if($reserveOK){'Reserve meets recommendation'}else{'CRITICAL: Reserve below 50% of recommendation'} }
        [ordered]@{ CheckName='DiskSymmetry';        Severity='Warning';  Status='Pass'; Details='All nodes have identical disk count and type' }
        [ordered]@{ CheckName='VolumeHealth';        Severity='Critical'; Status=if($volumeHealth){'Pass'}else{'Fail'}; Details=if($volumeHealth){'All volumes Healthy'}else{'One or more volumes in Degraded state'} }
        [ordered]@{ CheckName='DiskHealth';          Severity='Critical'; Status=if($diskHealth){'Pass'}else{'Fail'};   Details=if($diskHealth){'All disks Healthy'}else{'One or more disks non-Healthy'} }
        [ordered]@{ CheckName='NvmeWear';            Severity='Warning';  Status=if($nvmeWear){'Pass'}else{'Warn'};     Details=if($nvmeWear){'All NVMe disks below 80% wear'}else{'Warning: NVMe disk approaching end of wear'} }
        [ordered]@{ CheckName='ThinOvercommit';      Severity='Warning';  Status=if($overcommit){'Warn'}else{'Pass'};   Details=if($overcommit){'WARNING: Thin-provisioned volumes exceed available pool capacity'}else{'No thin overcommit detected'} }
        [ordered]@{ CheckName='FirmwareConsistency'; Severity='Info';     Status='Pass'; Details='All disks of the same model are on the same firmware version' }
        [ordered]@{ CheckName='RebuildCapacity';     Severity='Critical'; Status='Pass'; Details='Cluster can survive a single node failure and fully rebuild' }
        [ordered]@{ CheckName='InfraVolume';         Severity='Info';     Status='Pass'; Details='Infrastructure volume detected (250 GiB)' }
        [ordered]@{ CheckName='CacheTierHealth';     Severity='Warning';  Status='Pass'; Details='Cache tier healthy' }
    )
}

function script:WritFixture([string]$name, [hashtable]$data) {
    $path = Join-Path $fixturesDir "$name.json"
    $data | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding UTF8
    Write-Host "  ✅ $name.json" -ForegroundColor Green
}

# ─── FIXTURE 1: 2node-allnvme ─────────────────────────────────────────────────
# 2 nodes · 0 cache · 4× 3.84 TB NVMe capacity per node · two-way mirror · healthy
Write-Host "`n[1/8] 2node-allnvme" -ForegroundColor DarkGray
$diskBytes = [int64]3840000000000
$nodes2    = @('azl-iic-2na-n01', 'azl-iic-2na-n02')
$disks2na  = foreach ($n in $nodes2) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'NVMe' $diskBytes 'INTEL SSDPE2KX040T8' 'VCV10162' 'Intel' 12 }
}
$raw2na    = [int64]($diskBytes * 8)
$alloc2na  = [int64]($raw2na * 0.38)          # leaves room for reserve
$wf2na     = MakeWaterfall $raw2na 2 $diskBytes $alloc2na 50.0

WritFixture '2node-allnvme' ([ordered]@{
    scenario      = '2node-allnvme'
    description   = '2-node, all-NVMe capacity (no cache tier), two-way mirror, healthy baseline'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-2na-01'
    nodeCount     = 2
    nodes         = $nodes2
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='INTEL SSDPE2KX040T8'; diskSizeTB=3.84; cacheTierMode='None -- all-NVMe software storage bus write cache' }
    physicalDisks = @($disks2na)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-2na-01"; totalSizeBytes=[long]($raw2na*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc2na; freeSizeBytes=([long]($raw2na*(1-$POOL_OVERHEAD))-$alloc2na) }
    volumes       = @(
        (MakeVolume 'VMs'  'Mirror' 2 ([int64]($diskBytes*5)) 'Fixed')
        (MakeVolume 'ClusterStorage_InfraVolume'  'Mirror' 2 ([int64]($INFRA_VOL_BYTES*2)) 'Fixed' $true)
    )
    capacityWaterfall = $wf2na
    healthChecks  = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 2: 3node-mixed-tier ──────────────────────────────────────────────
# 3 nodes · 2× 1.6 TB NVMe cache + 4× 1.92 TB SSD capacity per node · three-way mirror · healthy
Write-Host "[2/8] 3node-mixed-tier" -ForegroundColor DarkGray
$cacheDiskBytes = [int64]1600000000000   # 1.6 TB NVMe (cache)
$capDiskBytes   = [int64]1920000000000   # 1.92 TB SSD (capacity)
$nodes3m        = @('azl-iic-3mt-n01', 'azl-iic-3mt-n02', 'azl-iic-3mt-n03')
$disks3mt       = foreach ($n in $nodes3m) {
    foreach ($d in 1..2) { MakeDisk $n $d 'Cache'    'NVMe' $cacheDiskBytes 'INTEL SSDPED1K750GA' 'E2010420' 'Intel' 8 }
    foreach ($d in 3..6) { MakeDisk $n $d 'Capacity' 'SSD'  $capDiskBytes   'SAMSUNG MZ7LH1T9HMLT' 'HXT7904Q' 'Samsung' 5 }
}
$raw3mt   = [int64]($capDiskBytes * 12)  # 12 capacity disks
$alloc3mt = [int64]($raw3mt * 0.35)
$wf3mt    = MakeWaterfall $raw3mt 3 $capDiskBytes $alloc3mt 33.3

WritFixture '3node-mixed-tier' ([ordered]@{
    scenario      = '3node-mixed-tier'
    description   = '3-node, NVMe cache tier + SSD capacity tier, three-way mirror, healthy'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-3mt-01'
    nodeCount     = 3
    nodes         = $nodes3m
    diskConfig    = [ordered]@{ cacheDisksPerNode=2; capacityDisksPerNode=4; cacheDiskModel='INTEL SSDPED1K750GA'; cacheDiskSizeTB=1.6; capDiskModel='SAMSUNG MZ7LH1T9HMLT'; capDiskSizeTB=1.92; cacheTierMode='ReadWrite' }
    physicalDisks = @($disks3mt)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-3mt-01"; totalSizeBytes=[long]($raw3mt*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc3mt; freeSizeBytes=([long]($raw3mt*(1-$POOL_OVERHEAD))-$alloc3mt) }
    volumes       = @(
        (MakeVolume 'VMs'  'Mirror' 3 ([int64]($capDiskBytes*4)) 'Fixed')
        (MakeVolume 'ClusterStorage_InfraVolume' 'Mirror' 3 ([int64]($INFRA_VOL_BYTES*3)) 'Fixed' $true)
    )
    capacityWaterfall = $wf3mt
    healthChecks  = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 3: 4node-3way-mirror ─────────────────────────────────────────────
# 4 nodes · 4× 7.68 TB NVMe per node · three-way mirror · one thin-provisioned volume
Write-Host "[3/8] 4node-3way-mirror" -ForegroundColor DarkGray
$disk4n  = [int64]7680000000000   # 7.68 TB NVMe
$nodes4n = @('azl-iic-4n3-n01', 'azl-iic-4n3-n02', 'azl-iic-4n3-n03', 'azl-iic-4n3-n04')
$disks4n = foreach ($n in $nodes4n) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'NVMe' $disk4n 'SAMSUNG PM9A3 7.68TB' 'GXA7602Q' 'Samsung' 15 }
}
$raw4n3   = [int64]($disk4n * 16)
$alloc4n3 = [int64]($disk4n * 9)          # pool allocated (thin writes = 3 TB equivalent)
$wf4n3    = MakeWaterfall $raw4n3 4 $disk4n $alloc4n3 33.3
$thinAllocBytes = [int64]($disk4n * 2)   # only 2 drives worth actually written

WritFixture '4node-3way-mirror' ([ordered]@{
    scenario      = '4node-3way-mirror'
    description   = '4-node, 4x 7.68 TB NVMe, three-way mirror, one thin-provisioned volume with moderate writes'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-4n3-01'
    nodeCount     = 4
    nodes         = $nodes4n
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='SAMSUNG PM9A3 7.68TB'; diskSizeTB=7.68; cacheTierMode='None -- all-NVMe software storage bus' }
    physicalDisks = @($disks4n)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-4n3-01"; totalSizeBytes=[long]($raw4n3*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc4n3; freeSizeBytes=([long]($raw4n3*(1-$POOL_OVERHEAD))-$alloc4n3) }
    volumes       = @(
        (MakeVolume 'VMs-Fixed'  'Mirror' 3 ([int64]($disk4n*6)) 'Fixed')
        (MakeVolume 'Archive-Thin' 'Mirror' 3 ([int64]($disk4n*3)) 'Thin' $false $thinAllocBytes)
        (MakeVolume 'ClusterStorage_InfraVolume' 'Mirror' 3 ([int64]($INFRA_VOL_BYTES*3)) 'Fixed' $true)
    )
    capacityWaterfall = $wf4n3
    healthChecks  = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 4: 4node-mixed-resiliency ────────────────────────────────────────
# 4 nodes · 4× 7.68 TB NVMe · VMs=three-way mirror · Archive=dual parity · blended efficiency
Write-Host "[4/8] 4node-mixed-resiliency" -ForegroundColor DarkGray
$disk4mr  = [int64]7680000000000
$nodes4mr = @('azl-iic-4mr-n01', 'azl-iic-4mr-n02', 'azl-iic-4mr-n03', 'azl-iic-4mr-n04')
$disks4mr = foreach ($n in $nodes4mr) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'NVMe' $disk4mr 'SAMSUNG PM9A3 7.68TB' 'GXA7602Q' 'Samsung' 18 }
}
$raw4mr    = [int64]($disk4mr * 16)
$volVMsFP  = [int64]($disk4mr * 6)   # 3-way: 2 TiB usable per drive × 6 drives
$volArcFP  = [int64]($disk4mr * 4)   # dual parity (4-node): 50% eff → 2 drives usable
$alloc4mr  = $volVMsFP + $volArcFP + [int64]($INFRA_VOL_BYTES * 3)
# Blended: (33.3% × 6 + 50% × 4) / 10 ≈ 39.98% ≈ 40%
$blend4mr  = [Math]::Round((33.3 * 6 + 50.0 * 4) / 10, 1)
$wf4mr     = MakeWaterfall $raw4mr 4 $disk4mr $alloc4mr $blend4mr

WritFixture '4node-mixed-resiliency' ([ordered]@{
    scenario      = '4node-mixed-resiliency'
    description   = '4-node, VMs volume uses three-way mirror, Archive uses dual parity; used for blended waterfall testing'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-4mr-01'
    nodeCount     = 4
    nodes         = $nodes4mr
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='SAMSUNG PM9A3 7.68TB'; diskSizeTB=7.68 }
    physicalDisks = @($disks4mr)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-4mr-01"; totalSizeBytes=[long]($raw4mr*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc4mr; freeSizeBytes=([long]($raw4mr*(1-$POOL_OVERHEAD))-$alloc4mr) }
    volumes       = @(
        (MakeVolume 'VMs'     'Mirror'  3 $volVMsFP 'Fixed')
        (MakeVolume 'Archive' 'Parity'  2 $volArcFP 'Fixed')
        (MakeVolume 'ClusterStorage_InfraVolume' 'Mirror' 3 ([int64]($INFRA_VOL_BYTES*3)) 'Fixed' $true)
    )
    blendedResiliencyEfficiency = $blend4mr
    capacityWaterfall           = $wf4mr
    healthChecks                = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 5: 16node-enterprise ─────────────────────────────────────────────
# 16 nodes · 4× 15.36 TB NVMe per node · three-way mirror · reserve capped at 4 drives
Write-Host "[5/8] 16node-enterprise" -ForegroundColor DarkGray
$disk16n  = [int64]15360000000000  # 15.36 TB NVMe
$nodes16n = 1..16 | ForEach-Object { 'azl-iic-16e-n{0:D2}' -f $_ }
$disks16n = foreach ($n in $nodes16n) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'NVMe' $disk16n 'MICRON 9300 MAX 15.36TB' '5005' 'Micron' 10 }
}
$raw16n   = [int64]($disk16n * 64)
$alloc16n = [int64]($raw16n * 0.42)   # moderate allocation
$wf16n    = MakeWaterfall $raw16n 16 $disk16n $alloc16n 33.3

WritFixture '16node-enterprise' ([ordered]@{
    scenario      = '16node-enterprise'
    description   = '16-node enterprise cluster, 4x 15.36 TB NVMe per node, three-way mirror, reserve capped at min(16,4)=4 drives'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-16e-01'
    nodeCount     = 16
    nodes         = @($nodes16n)
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='MICRON 9300 MAX 15.36TB'; diskSizeTB=15.36 }
    physicalDisks = @($disks16n)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-16e-01"; totalSizeBytes=[long]($raw16n*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc16n; freeSizeBytes=([long]($raw16n*(1-$POOL_OVERHEAD))-$alloc16n) }
    capacityWaterfall = $wf16n
    healthChecks  = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 6: 2node-overcommitted ───────────────────────────────────────────
# 2 nodes · 4× 960 GB SSD per node · thin volumes summing more than usable → WARN
Write-Host "[6/8] 2node-overcommitted" -ForegroundColor DarkGray
$disk2oc  = [int64]960000000000   # 960 GB SSD
$nodes2oc = @('azl-iic-2oc-n01', 'azl-iic-2oc-n02')
$disks2oc = foreach ($n in $nodes2oc) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'SSD' $disk2oc 'SAMSUNG SM863A 960GB' 'MAV21K3Q' 'Samsung' 45 }
}
$raw2oc      = [int64]($disk2oc * 8)
$poolTotal2oc = [long]($raw2oc * (1 - $POOL_OVERHEAD))
$reserve2oc  = [int64]($disk2oc * 2)       # 2-node reserve = 2 drives
# Pool has only ~5% free (critical reserve), and thin provisioned > available
$alloc2oc    = [int64]($poolTotal2oc * 0.95)
$free2oc     = $poolTotal2oc - $alloc2oc
# Thin volumes: provisioned sum exceeds available after reserve
$thinVol1FP  = [int64]($raw2oc * 0.4)
$thinVol2FP  = [int64]($raw2oc * 0.5)   # combined provisions > available
$wf2oc       = [ordered]@{
    Raw         = [ordered]@{ Bytes=$raw2oc; TiB=(BytesToTiB $raw2oc); TB=(BytesToTB $raw2oc) }
    PoolTotal   = [ordered]@{ Bytes=$poolTotal2oc; TiB=(BytesToTiB $poolTotal2oc) }
    Reserve     = [ordered]@{ RecommendedBytes=$reserve2oc; RecommendedTiB=(BytesToTiB $reserve2oc); ActualFreeBytes=$free2oc; ActualFreeTiB=(BytesToTiB $free2oc); Status='Critical' }
    Usable      = [ordered]@{ Bytes=[long](($poolTotal2oc - $reserve2oc - $INFRA_VOL_BYTES) / 2); TiB=(BytesToTiB ([long](($poolTotal2oc - $reserve2oc - $INFRA_VOL_BYTES) / 2))) }
    Overcommit  = [ordered]@{
        TotalProvisionedBytes = ($thinVol1FP / 2 + $thinVol2FP / 2)
        TotalProvisionedTiB   = (BytesToTiB ([int64]($thinVol1FP / 2 + $thinVol2FP / 2)))
        OvercommitRatio       = [Math]::Round(($thinVol1FP/2 + $thinVol2FP/2) / [long](($poolTotal2oc - $reserve2oc - $INFRA_VOL_BYTES) / 2), 2)
    }
}

WritFixture '2node-overcommitted' ([ordered]@{
    scenario      = '2node-overcommitted'
    description   = '2-node, thin-provisioned volumes sum exceeds available capacity; triggers ThinOvercommit Warning and ReserveAdequacy Critical'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-2oc-01'
    nodeCount     = 2
    nodes         = $nodes2oc
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='SAMSUNG SM863A 960GB'; diskSizeTB=0.96 }
    physicalDisks = @($disks2oc)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-2oc-01"; totalSizeBytes=$poolTotal2oc; allocatedSizeBytes=$alloc2oc; freeSizeBytes=$free2oc }
    volumes       = @(
        (MakeVolume 'VMs'     'Mirror' 2 $thinVol1FP  'Thin' $false ([int64]($thinVol1FP * 0.6)))
        (MakeVolume 'Archive' 'Mirror' 2 $thinVol2FP  'Thin' $false ([int64]($thinVol2FP * 0.4)))
        (MakeVolume 'ClusterStorage_InfraVolume' 'Mirror' 2 ([int64]($INFRA_VOL_BYTES*2)) 'Fixed' $true)
    )
    capacityWaterfall = $wf2oc
    healthChecks  = (MakeHealthChecks -reserveOK $false -overcommit $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 7: 3node-insufficient-reserve ────────────────────────────────────
# 3 nodes · 4× 3.84 TB NVMe per node · pool nearly fully allocated → reserve CRITICAL
Write-Host "[7/8] 3node-insufficient-reserve" -ForegroundColor DarkGray
$disk3ir  = [int64]3840000000000
$nodes3ir = @('azl-iic-3ir-n01', 'azl-iic-3ir-n02', 'azl-iic-3ir-n03')
$disks3ir = foreach ($n in $nodes3ir) {
    foreach ($d in 1..4) { MakeDisk $n $d 'Capacity' 'NVMe' $disk3ir 'INTEL SSDPE2KX040T8' 'VCV10162' 'Intel' 22 }
}
$raw3ir      = [int64]($disk3ir * 12)
$poolTotal3ir = [long]($raw3ir * (1 - $POOL_OVERHEAD))
$reserveRec3ir = [int64]($disk3ir * 3)   # 3 nodes × largest disk
# Pool is 97% allocated — almost nothing free
$alloc3ir    = [long]($poolTotal3ir * 0.97)
$free3ir     = $poolTotal3ir - $alloc3ir  # only ~3% free — far below 50% of reserve rec
$wf3ir       = [ordered]@{
    Raw         = [ordered]@{ Bytes=$raw3ir; TiB=(BytesToTiB $raw3ir); TB=(BytesToTB $raw3ir) }
    PoolTotal   = [ordered]@{ Bytes=$poolTotal3ir; TiB=(BytesToTiB $poolTotal3ir) }
    Reserve     = [ordered]@{
        RecommendedBytes = $reserveRec3ir
        RecommendedTiB   = (BytesToTiB $reserveRec3ir)
        ActualFreeBytes  = $free3ir
        ActualFreeTiB    = (BytesToTiB $free3ir)
        DeficitBytes     = $reserveRec3ir - $free3ir
        DeficitTiB       = (BytesToTiB ($reserveRec3ir - $free3ir))
        Status           = 'Critical'
    }
    Usable = [ordered]@{ Bytes=[long](($poolTotal3ir - $reserveRec3ir - $INFRA_VOL_BYTES)/3); TiB=(BytesToTiB ([long](($poolTotal3ir - $reserveRec3ir - $INFRA_VOL_BYTES)/3))) }
}

WritFixture '3node-insufficient-reserve' ([ordered]@{
    scenario      = '3node-insufficient-reserve'
    description   = '3-node, 4x 3.84 TB NVMe per node, pool 97% allocated, unallocated free space far below reserve recommendation; triggers ReserveAdequacy Critical'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-3ir-01'
    nodeCount     = 3
    nodes         = $nodes3ir
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='INTEL SSDPE2KX040T8'; diskSizeTB=3.84 }
    physicalDisks = @($disks3ir)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-3ir-01"; totalSizeBytes=$poolTotal3ir; allocatedSizeBytes=$alloc3ir; freeSizeBytes=$free3ir }
    reserveRecommended = [ordered]@{ bytes=$reserveRec3ir; TiB=(BytesToTiB $reserveRec3ir) }
    reserveActual      = [ordered]@{ bytes=$free3ir;       TiB=(BytesToTiB $free3ir) }
    capacityWaterfall  = $wf3ir
    healthChecks  = (MakeHealthChecks -reserveOK $false)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

# ─── FIXTURE 8: single-node ───────────────────────────────────────────────────
# 1 node · 4× 1.92 TB NVMe · nested two-way mirror (~25% efficiency)
Write-Host "[8/8] single-node" -ForegroundColor DarkGray
$disk1n  = [int64]1920000000000   # 1.92 TB NVMe
$nodes1n = @('azl-iic-1n-n01')
$disks1n = foreach ($d in 1..4) { MakeDisk 'azl-iic-1n-n01' $d 'Capacity' 'NVMe' $disk1n 'INTEL SSDPE2KX020T8' 'VCV10162' 'Intel' 8 }
$raw1n   = [int64]($disk1n * 4)
$alloc1n = [int64]($raw1n * 0.50)
$wf1n    = [ordered]@{
    Raw       = [ordered]@{ Bytes=$raw1n; TiB=(BytesToTiB $raw1n); TB=(BytesToTB $raw1n) }
    PoolTotal = [ordered]@{ Bytes=[long]($raw1n*(1-$POOL_OVERHEAD)); TiB=(BytesToTiB ([long]($raw1n*(1-$POOL_OVERHEAD)))) }
    Reserve   = [ordered]@{ RecommendedBytes=$disk1n; RecommendedTiB=(BytesToTiB $disk1n); ActualFreeBytes=([long]($raw1n*(1-$POOL_OVERHEAD))-$alloc1n); Status='Adequate' }
    Resiliency = [ordered]@{ Type='Nested Two-Way Mirror'; EfficiencyPercent=25.0; Notes='Single-node: local mirror only, ~25% usable efficiency' }
    Usable    = [ordered]@{ Bytes=[long](($raw1n*(1-$POOL_OVERHEAD)-$disk1n-$INFRA_VOL_BYTES)*0.25); TiB=(BytesToTiB ([long](($raw1n*(1-$POOL_OVERHEAD)-$disk1n-$INFRA_VOL_BYTES)*0.25))) }
}

WritFixture 'single-node' ([ordered]@{
    scenario      = 'single-node'
    description   = '1-node cluster, 4x 1.92 TB NVMe, nested two-way mirror (~25% efficiency)'
    company       = $IIC_COMPANY
    clusterName   = 'azlocal-iic-1n-01'
    nodeCount     = 1
    nodes         = $nodes1n
    diskConfig    = [ordered]@{ cacheDisksPerNode=0; capacityDisksPerNode=4; diskModel='INTEL SSDPE2KX020T8'; diskSizeTB=1.92; resiliency='Nested Two-Way Mirror (local)'; efficiencyPct=25 }
    physicalDisks = @($disks1n)
    storagePool   = [ordered]@{ name="S2D on azlocal-iic-1n-01"; totalSizeBytes=[long]($raw1n*(1-$POOL_OVERHEAD)); allocatedSizeBytes=$alloc1n; freeSizeBytes=([long]($raw1n*(1-$POOL_OVERHEAD))-$alloc1n) }
    capacityWaterfall = $wf1n
    healthChecks  = (MakeHealthChecks -reserveOK $true)
    metadata      = [ordered]@{ tenantId=$IIC_TENANT; subscriptionId=$IIC_SUB; resourceGroup=$IIC_RG }
    generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    generatedBy   = 'New-S2DFixtures.ps1'
})

Write-Host "`n✅ All 8 fixtures generated in $fixturesDir" -ForegroundColor Green
