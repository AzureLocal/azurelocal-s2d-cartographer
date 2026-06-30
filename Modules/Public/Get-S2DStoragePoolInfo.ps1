function Get-S2DStoragePoolInfo {
    <#
    .SYNOPSIS
        Returns S2D storage pool configuration, capacity allocation, and overcommit status.

    .DESCRIPTION
        Queries the non-primordial storage pool for health, total/allocated/remaining
        capacity, resiliency settings, storage tiers, fault domain awareness, and thin
        provisioning overcommit ratio.

        Requires an active session established with Connect-S2DCluster, or pass
        -CimSession directly.

    .PARAMETER CimSession
        Override the module session and target this CimSession directly.

    .EXAMPLE
        Get-S2DStoragePoolInfo

    .EXAMPLE
        Get-S2DStoragePoolInfo | Select-Object FriendlyName, HealthStatus, TotalSize, RemainingSize

    .OUTPUTS
        S2DStoragePool
    #>
    [CmdletBinding()]
    [OutputType([S2DStoragePool])]
    param(
        [Parameter()]
        [CimSession] $CimSession
    )

    $usePSSession = -not $PSBoundParameters.ContainsKey('CimSession') -and
                    -not $Script:S2DSession.IsLocal -and
                    $null -ne $Script:S2DSession.PSSession

    $session = if ($usePSSession) { $null } else { Resolve-S2DSession -CimSession $CimSession }

    $rawPool            = $null
    $resiliencySettings = @()
    $storageTiers       = @()
    $provisionedBytes   = [int64]0

    if ($usePSSession) {
        $remoteResult = Invoke-Command -Session $Script:S2DSession.PSSession -ScriptBlock {
            $pool = Get-StoragePool -ErrorAction SilentlyContinue |
                    Where-Object IsPrimordial -eq $false |
                    Select-Object -First 1
            if (-not $pool) { return $null }

            $tiers         = @($pool | Get-StorageTier        -ErrorAction SilentlyContinue)
            $resilSettings = @($pool | Get-ResiliencySetting   -ErrorAction SilentlyContinue)
            $allVdisks     = @(Get-VirtualDisk                 -ErrorAction SilentlyContinue)
            $provBytes     = [int64]($allVdisks | Measure-Object -Property Size -Sum).Sum

            [PSCustomObject]@{
                Pool               = $pool
                Tiers              = $tiers
                ResiliencySettings = $resilSettings
                ProvisionedBytes   = $provBytes
            }
        }
        if (-not $remoteResult) {
            Write-Warning "No non-primordial storage pool found."
            return $null
        }
        $rawPool            = $remoteResult.Pool
        $resiliencySettings = $remoteResult.ResiliencySettings
        $storageTiers       = $remoteResult.Tiers
        $provisionedBytes   = $remoteResult.ProvisionedBytes
    }
    else {
        $rawPool = if ($session) {
            Get-S2DStoragePoolData -CimSession $session | Where-Object IsPrimordial -eq $false | Select-Object -First 1
        }
        else {
            Get-S2DStoragePoolData | Where-Object IsPrimordial -eq $false | Select-Object -First 1
        }

        if (-not $rawPool) {
            Write-Warning "No non-primordial storage pool found."
            return $null
        }

        $resiliencySettings = @(
            if ($session) { $rawPool | Get-S2DStoragePoolResiliencyData -CimSession $session }
            else          { $rawPool | Get-S2DStoragePoolResiliencyData }
        )

        $storageTiers = @(
            if ($session) { $rawPool | Get-S2DStoragePoolTierData -CimSession $session }
            else          { $rawPool | Get-S2DStoragePoolTierData }
        )

        $allVdisks = @(
            if ($session) { Get-S2DVirtualDiskData -CimSession $session }
            else          { Get-S2DVirtualDiskData }
        )
        # Empty-data safeguard: Measure-Object -Sum on an empty collection returns $null
        # for .Sum; explicitly coerce to [int64]0 to prevent downstream NullReferenceException.
        $provisionedBytes = if ($allVdisks.Count -gt 0) {
            [int64](($allVdisks | Measure-Object -Property Size -Sum).Sum)
        } else { [int64]0 }
    }

    $totalBytes     = [int64]$rawPool.Size
    $allocatedBytes = [int64]$rawPool.AllocatedSize
    $remainingBytes = $totalBytes - $allocatedBytes

    $overcommitRatio = if ($totalBytes -gt 0 -and $provisionedBytes -gt 0) {
        [math]::Round($provisionedBytes / $totalBytes, 3)
    }
    else { 0 }

    $faultDomain       = try { [string]$rawPool.FaultDomainAwarenessDefault } catch { 'Unknown' }
    $writeCacheDefault = try { [int64]$rawPool.WriteCacheSizeDefault }        catch { [int64]0 }

    $resiliencyObjects = @($resiliencySettings | ForEach-Object {
        [PSCustomObject]@{
            Name                   = $_.Name
            NumberOfDataCopies     = $(try { $_.NumberOfDataCopies }     catch { $null })
            PhysicalDiskRedundancy = $(try { $_.PhysicalDiskRedundancy } catch { $null })
            NumberOfColumns        = $(try { $_.NumberOfColumns }        catch { $null })
        }
    })

    $tierObjects = @($storageTiers | ForEach-Object {
        [PSCustomObject]@{
            FriendlyName  = $_.FriendlyName
            MediaType     = $(try { [string]$_.MediaType } catch { 'Unknown' })
            Size          = if ($_.Size -gt 0)          { [S2DCapacity]::new([int64]$_.Size) }          else { $null }
            AllocatedSize = if ($_.AllocatedSize -gt 0) { [S2DCapacity]::new([int64]$_.AllocatedSize) } else { $null }
        }
    })

    $result = [S2DStoragePool]::new()
    $result.FriendlyName          = $rawPool.FriendlyName
    $result.HealthStatus          = [string]$rawPool.HealthStatus
    $result.OperationalStatus     = [string]$rawPool.OperationalStatus
    $result.IsReadOnly            = [bool]$rawPool.IsReadOnly
    $result.TotalSize             = if ($totalBytes     -gt 0) { [S2DCapacity]::new($totalBytes) }     else { $null }
    $result.AllocatedSize         = if ($allocatedBytes -gt 0) { [S2DCapacity]::new($allocatedBytes) } else { $null }
    $result.RemainingSize         = if ($remainingBytes -gt 0) { [S2DCapacity]::new($remainingBytes) } else { $null }
    $result.ProvisionedSize       = if ($provisionedBytes -gt 0) { [S2DCapacity]::new($provisionedBytes) } else { $null }
    $result.OvercommitRatio       = $overcommitRatio
    $result.FaultDomainAwareness  = $faultDomain
    $result.WriteCacheSizeDefault = $writeCacheDefault
    $result.ResiliencySettings    = $resiliencyObjects
    $result.StorageTiers          = $tierObjects

    $Script:S2DSession.CollectedData['StoragePool'] = $result
    $result
}
