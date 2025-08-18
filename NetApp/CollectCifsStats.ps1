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

function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # Using -match to parse out the octets.
        if($ipStr -match "^((\d+)\.(\d+)\.(\d+)\.(\d+))$")
        {
            $a = 0
            while($a -lt 4)
            {
                $octet = [Convert]::ToUInt32($Matches[$a + 2], 10)
                $ipAddr += ($octet -shl (24 - (8 * $a)))
                $a++
            }
        }
    } `
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

function IsInSubnet
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $ipStr,

        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $netIPStr,

        [Parameter(Mandatory=$true, Position=0)]
        [int]
        $bm
    )

    $ip = [int64] (INET_ATON $ipStr)
    $netIP = [int64] (INET_ATON $netIPStr)
    $mask = (($Global:baseBM -shr (32 - $bm)) -shl (32 - $bm))
    $maskedIP = $mask -band $ip
    $maskedNetIP = $mask -band $netIP

    return $maskedIP -eq $maskedNetIP
}

function IPAMSubnetsForAddress
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $ipStr
    )

    $ip = [int64] (INET_ATON $ipStr)

    $sns = @($Global:ipamSubnets | Where-Object { ($_.Mask -band $ip) -eq $_.MaskedNetIPN })
    if ($sns.Length -gt 0)
    {
        $sns2 = @($sns | Where-Object { $_.rootnet -eq 0 })
        if($sns2.Length -gt 0)
        {
            $sns = $sns2[0]
        } `
        else # NOT ($sns2.Length -gt 0)
        {
            $sns = $sns[0]
        }
    } `
    else # NOT ($sns.Length -gt 0)
    {
        # Nothing.
    }

    return $sns
}


try
{
    $Global:ipamSubnets = [System.Collections.Generic.List[System.Object]]::new()
    @(Import-CSV -Path "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\NetApp\ipamNetworks.csv").ForEach({
        $d = [PSCustomObject]@{
            red = $_.red
            BM = $_.BM
            loc = $_.loc
            comentario = $_.comentario
            rootnet = $_.rootnet
            NetIPN = [int64] $_.NetIPN
            Mask = [int64] $_.Mask
            MaskedNetIPN = [int64] $_.MaskedNetIPN
        }

        $Global:ipamSubnets.Add($d)
    })


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

    $cifsSessions | Select-Object -Unique @{N='NC';E={($_.NCController.Name.ToUpper().Replace("BDC","DE2").Replace("CDC","CH3") -split "`-")[0]}}

    $clientConnections = @()
    $a = 0
    Write-Host ("{0}" -f @(([String]::new(".", [int32] ($cifsSessions.Length / 100)))))
    while($a -lt $cifsSessions.Length)
    {
        # $dc = "{0}/{1}" -f @(($cifsSessions[$a].NCController.Name.ToUpper().Replace("BDC","DE2").Replace("CDC","CH3") -split "`-")[0], $cifsSessions[$a].Vserver.ToUpper())
        $dc = @($cifsSessions[$a].NCController.Name.ToUpper().Replace("BDC","DE2").Replace("CDC","CH3") -split "`-")[0]
        $vserver = $cifsSessions[$a].Vserver.ToUpper()

        $src = IPAMSubnetsForAddress -ipStr $cifsSessions[$a].Address
        if ($null -ne $src)
        {
            $src = $src.loc.ToUpper()
        } `
        else # NOT ($null -ne $cl)
        {
            $src = $cifsSessions[$a].Address
        }

        $cc = $clientConnections | Where-Object { ($_.Datacenter -eq $dc) -and ($_.Source -eq $src) -and ($_.VServer -eq $vserver)}
        if ($null -eq $cc)
        {
            $cc = [PSCustomObject]@{
                CollectionTime = $collectionTime.ToOADate()
                Datacenter = $dc
                VServer = $vserver
                Source = $src
                Connections = 0
            }
            $clientConnections += $cc
        } `
        else # NOT ($null -eq $cc)
        {
            # Nothing.
        }

        $cc.Connections++

        $a++

        <#
        if (($a % 100) -eq 0)
        {
            Write-Host -NoNewline "."
        } `
        else # NOT (($a % 100) -eq 0)
        {
            # Nothing.
        }
        #>
    }
    # Write-Host

    $clientConnections | Export-Excel -Append -WorksheetName "Data" -Path "E:\Data\CifsConnections.xlsx"


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
