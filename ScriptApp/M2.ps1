class DAStat
{
    [String] $AuthMethod = [String]::Empty
    [uint32] $Bandwidth = 0
    [uint32] $ConnectionDuration = 0
    [long] $ConnectionStartTime = 0
    [string] $ConnectionType = [String]::Empty
    [string] $HealthStatus = [String]::Empty
    [string] $HostName = [String]::Empty
    [string] $RoutingDomain = [String]::Empty
    [uint64] $TotalBytesIn = 0
    [uint64] $TotalBytesOut = 0
    [string] $TransitionTechnology = [String]::Empty
    [string] $TunnelType = [String]::Empty
    [string] $UserActivityState = [String]::Empty
    [System.Collections.Generic.List[String]] $UserNames = $null

    DAStat([System.Object] $stat)
    {
        $this.AuthMethod = $stat.AuthMethod
        $this.Bandwidth = $stat.Bandwidth
        $this.ConnectionDuration = $stat.ConnectionDuration
        if($stat.ConnectionStartTime -is [DateTime])
        {
            $this.ConnectionStartTime = $stat.ConnectionStartTime.ToFileTimeUtc()
        }
        else
        {
            $this.ConnectionStartTime = $stat.ConnectionStartTime
        }
        $this.ConnectionType = $stat.ConnectionType
        $this.HealthStatus = $stat.HealthStatus
        $this.HostName = $stat.HostName
        $this.RoutingDomain = $stat.RoutingDomain
        $this.TotalBytesIn = $stat.TotalBytesIn
        $this.TotalBytesOut = $stat.TotalBytesOut
        $this.TransitionTechnology = $stat.TransitionTechnology
        $this.TunnelType = $stat.TunnelType
        $this.UserActivityState = $stat.UserActivityState
        $this.UserNames = [System.Collections.Generic.List[String]]::new()
        foreach($user in $stat.UserName)
        {
            $i = $this.UserNames.BinarySearch($user)
            if($i -lt 0)
            {
                $this.UserNames.Insert(-bnot $i, $user)
            }
        }
    }

    [void] UpdateStat([DAStat] $other)
    {
        if($this.Key() -eq $other.Key())
        {
            $this.Bandwidth = $other.Bandwidth
            $this.ConnectionDuration = $other.ConnectionDuration
            $this.ConnectionType = $other.ConnectionType
            $this.HealthStatus = $other.HealthStatus
            $this.RoutingDomain = $other.RoutingDomain
            $this.TotalBytesIn = $other.TotalBytesIn
            $this.TotalBytesOut = $other.TotalBytesOut
            $this.TransitionTechnology = $other.TransitionTechnology
            $this.TunnelType = $other.TunnelType
            $this.UserActivityState = $other.UserActivityState
        }
        else
        {
            # Nothing, $other is for a different host.
        }
    }

    [void] MergeStats([DAStat] $other)
    {
        if($this.ShortKey() -eq $other.ShortKey())
        {
            $this.Bandwidth = $other.Bandwidth
            $this.ConnectionStartTime = [Math]::Max($this.ConnectionStartTime, $other.ConnectionStartTime)
            $this.ConnectionDuration += $other.ConnectionDuration
            $this.ConnectionType = $other.ConnectionType
            $this.HealthStatus = $other.HealthStatus
            $this.RoutingDomain = $other.RoutingDomain
            $this.TotalBytesIn += $other.TotalBytesIn
            $this.TotalBytesOut += $other.TotalBytesOut
            $this.TransitionTechnology = $other.TransitionTechnology
            $this.TunnelType = $other.TunnelType
            $this.UserActivityState = $other.UserActivityState
        }
        else
        {
            # Nothing, $other is for a different host.
        }
    }

    [String] ShortKey()
    {
        $key = "{0}:{1}:{2}" -f @($this.HostName, $this.AuthMethod, [String]::Join(":", $this.UserNames))

        return $key
    }

    [String] Key()
    {
        $key = "{0}:{1}:{2}:{3}" -f @($this.HostName, $this.ConnectionStartTime, $this.AuthMethod, [String]::Join(":", $this.UserNames))

        return $key
    }
}

class DAStatCollection
{
    [System.Collections.Generic.SortedDictionary[String, DAStat]] $dictionary = $null

    DAStatCollection()
    {
        $this.dictionary = [System.Collections.Generic.SortedDictionary[String, DAStat]]::new()
    }

    [void] AddUpdateStat([System.Object] $stat)
    {
        $newStat = $stat
        if($newStat -isnot [DAStat])
        {
            $newStat = [DAStat]::new($stat)
        }
        $newKey = $newStat.Key()

        if ($this.dictionary.ContainsKey($newKey))
        {
            # TRUE

            $this.dictionary[$newKey].UpdateStat($newStat)
        }
        else # NOT ($this.dictionary.ContainsKey($newKey))
        {
            # FALSE

            $shortKey = $newStat.ShortKey()

            $hostStat = @($this.dictionary.Values) | Where-Object { $_.ShortKey() -eq $shortKey }

            if($null -ne $hostStat)
            {
                # Save the key for the existing (non-merged stat)
                $key = $hostStat.Key()

                # Merge the existing stat with the new stat
                $newStat.MergeStats($hostStat)

                # Remove the existing stat...
                $this.dictionary.Remove($key) | Out-Null

                # Grab a new key from the newStat after it was merged with the existing stat...
                $newKey = $newStat.Key()
            }

            # Finally, no matter if we merged a stat or not, add the newStat to the dictionary
            $this.dictionary.Add($newKey, $newStat)
        }
    }

    [void] Save([String] $fileName)
    {
        # $this.collection | ConvertTo-Json -Compress -Depth 2 | Out-File -FilePath $fileName -Force
    }

    static [DAStatCollection] Load([String] $fileName)
    {
        $newColl = [DAStatCollection]::new()

        <#
        if([System.IO.File]::Exists($fileName))
        {
            $rawStats = Get-Content -Path $fileName -Raw | ConvertFrom-Json

            $rawStats | ForEach-Object {
                $newStat = [DAStat]::new($_)
                $newColl.AddUpdateStat($newStat)
            }
        }
        #>

        return $newColl
    }
}

Import-Module RemoteAccess

$daSites = @(
    @{SiteCode="BOI"; Location="Boise"},
    @{SiteCode="OPK"; Location="Overland Park" },
    @{SiteCode="FMC"; Location="Fort Mills" },
    @{SiteCode="AST"; Location="Austin" },
    @{SiteCode="ORA"; Location="Oradell" },
    @{SiteCode="BDC"; Location="Denver" },
    @{SiteCode="CDC"; Location="Chicago" }
)
$statCollection = [DAStatCollection]::new()
$a = 0
while($a -lt $daSites.Length)
{
    for($b = 1; $b -le 2; $b++)
    {
        $stats = $null
        $daServerName = "{0}Z-DA0{1}" -f @($daSites[$a].SiteCode, $b)

        Write-Host ("Checking {0}..." -f @($daServerName))
        $Error.Clear()
        $stats = Get-RemoteAccessConnectionStatistics -ComputerName $daServerName -ErrorAction SilentlyContinue
        if($null -ne $stats)
        {
            $cntBefore = $statCollection.collection.Count
            $stats | Foreach-Object { $statCollection.AddUpdateStat($_) }
            $cntAfter = $statCollection.collection.Count

            Write-Host ("`tAdded {0} entries.  Total entries pulled: {1}" -f @(($cntAfter - $cntBefore), $stats.Length))
        }
        else
        {
            Write-Host ("Could not extract statistics from {0}" -f @($daServerName))
        }
    }

    $a++
}

$stats1 = Get-RemoteAccessConnectionStatistics -ComputerName BOIZ-DA01
$stats2 = Get-RemoteAccessConnectionStatistics -ComputerName BOIZ-DA02

$fileName = "C:\tmp\DAStatCollection.json"
$statCollection = [DAStatCollection]::new()
$stats1 | Foreach-Object { $statCollection.AddUpdateStat($_) }
$stats2 | Foreach-Object { $statCollection.AddUpdateStat($_) }


$rawStats = Get-Content -Path $fileName -Raw | ConvertFrom-Json
$s = [DAStat]::new($rawStats[0])


$statCollection.Save($fileName)

$statCollection.collection[0] | fl *

$statCollection = [DAStatCollection]::Load($fileName)
$statCollection.collection[0] | fl *


$statCollection = [DAStatCollection]::new()

$summaries = @()
$a = 0
while($a -lt $daSites.Length)
{
    for($b = 1; $b -le 2; $b++)
    {
        $serverName = "{0}Z-DA0{1}" -f @($daSites[$a].SiteCode, $b)
        Write-Host ("Collecting stats for {0}..." -f @($serverName))
        $stats = @(Get-RemoteAccessConnectionStatistics -ComputerName $serverName -ErrorAction SilentlyContinue)
        $statsSummary = Get-RemoteAccessConnectionStatisticsSummary -ComputerName $serverName -ErrorAction SilentlyContinue
        $summaries += $statsSummary
        if($stats.Length -gt 0)
        {
            $cntBefore = $statCollection.collection.Count
            $stats | Foreach-Object { $statCollection.AddUpdateStat($_) }
            $cntAfter = $statCollection.collection.Count

            Write-Host ("`tAdded {0} entries.  Total entries pulled: {1}" -f @(($cntAfter - $cntBefore), $stats.Length))
        }
        else
        {
            Write-Host ("`tNo stats returned")
        }
    }
    $a++
}
