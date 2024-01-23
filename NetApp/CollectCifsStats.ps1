function ConvertTo-Timespan
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $duration
    )

    [int] $days = 0
    [int] $hours = 0
    [int] $minutes = 0
    [int] $seconds = 0
    if($duration -match "([\d]+)d")
    {
        $days = [int] $Matches[1]
    }

    if($duration -match "([\d]+)h")
    {
        $hours = [int] $Matches[1]
    }

    if($duration -match "([\d]+)m")
    {
        $minutes = [int] $Matches[1]
    }

    if($duration -match "([\d]*)s")
    {
        $seconds = [int] $Matches[1]
    }

    $ts = [TimeSpan]::new($days, $hours, $minutes, $seconds)
    return $ts
}

try
{
    # Connect to all the Production CDOT clusters...
    ConnectTo cdot,prod

    # Capture the time the data is being collected
    $now = [DateTime]::Now
    $collectionTime = [DateTime]::new($now.Year, $now.Month, $now.Day, $now.Hour, $now.Minute, 0, 0, 0)

    # Capture all the current CIFS sessions on all the CDOT clusters...
    $cifsSessions = @(Get-NcCifsSession -Controller @($cdot.Values))

    # Get a list of all the shares on the CDOT clusters to facilitate creating a list of unique locations.
    $cifsShares = [System.Collections.Generic.List[Object]]::new()
    @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object { $cifsShares.Add($_) }

    # Create a list of unique CIFS VServers
    $smbVServers = [System.Collections.Generic.List[String]]::new()
    $cifsShares | Select-Object -Unique -ExpandProperty CifsServer | ForEach-Object { $smbVServers.Add($_) }

    # Next create a list of unique locations based on the names of the VServers.
#    $locations = @($cifsShares | Select-Object -Unique @{N='DC';E={ ($_.NCController.Name -split "`-")[0]}}, @{N='Site';E={ $s = ($_.CifsServer -split "`-")[0]; if($s.EndsWith("DR")) { $s = $s.SubString(0, $s.Length-2) } if($s.EndsWith("Z")) { $s = $s.SubString(0, $s.Length-1) } $s }})
    $locations = @($cifsShares | Select-Object -Unique @{N='DC';E={ ($_.NCController.Name.ToUpper().Replace("BDC","DDC") -split "`-")[0]}}, @{N='Site';E={ ($_.CifsServer.ToUpper() -split "`-")[0] }})

<#
    $locations = @(
        $smbVServers | Foreach-Object {
            $parts = ($_ -split "\-")
            if($parts.Length -gt 1)
            {
                $loc = $parts[0]
                if($loc.Endswith("DR"))
                {
                    $loc = $loc.SubString(0, $loc.Length - 2)
                }

                if($loc.Endswith("Z"))
                {
                    $loc = $loc.SubString(0, $loc.Length - 1)
                }

                $loc
            }
        } | Sort-Object | Select-Object -Unique
    )
#>

# Here is where I capture the session data...
    $cifsData = [System.Collections.Generic.List[Object]]::new()

    # For each of the unique locations, tally up the count of active CIFS sessions from all the VServers at the location...
    $a = 0
    while($a -lt $locations.Length)
    {
        $d = "" | Select-Object CollectionTime, DC, Site, Count
        $d.CollectionTime = $collectionTime.ToOADate()

        $d.DC = $locations[$a].DC
        $d.Site = $locations[$a].Site
        $locationCifsSessions = @($cifsSessions | Where-Object { ($_.NCController.Name.ToUpper().Replace("BDC","DDC").StartsWith($locations[$a].DC)) -and ($_.VServer.ToUpper().StartsWith($locations[$a].Site)) -and ((ConvertTo-Timespan $_.IdleTime).TotalSeconds -lt 120) })
        $d.Count = $locationCifsSessions.Length
        # Write-Host ("DC/Site: {0}/{1} -> {2}" -f @($d.DC, $d.Site, $d.Count)) # (($locationCifsSessions | Select-Object -Unique -ExpandProperty VServer | Sort-Object) -join ", ")))

        $cifsData.Add($d)
        $a++
    }

    # Add the current data to the pre-existing data...
    $cifsData | Export-CSV -Append -Path "E:\Data\CifsSessions.csv" -Delimiter "`t" -NoTypeInformation
    $cifsData | Export-Excel -Append -Path "E:\Data\Stats\CifsSessions.xlsx"
}
catch {
    # Only save data if nothing bad happens...
}

<#
$cifsData2 = Import-CSV -Path "E:\Data\CifsSessions.csv" -Delimiter "`t"
$a = 0
while($a -lt $cifsData2.Length)
{
    $year = [int] $cifsData2[$a].CollectionTime.Substring(0,4)
    $month = [int] $cifsData2[$a].CollectionTime.Substring(4,2)
    $day = [int] $cifsData2[$a].CollectionTime.Substring(6,2)
    $hour = $cifsData2[$a].CollectionTime.Substring(9,2)
    $minute = $cifsData2[$a].CollectionTime.Substring(11,2)
    $dt = [DateTime]::new($year, $month, $day, $hour, $minute, 0, 0, 0)
    $cifsData2[$a].CollectionTime = $dt.ToOADate()
    $a++
}
$cifsData2 | Export-Excel -Path "E:\Data\Stats\CIFSSessions.xlsx"
#>
