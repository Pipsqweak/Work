<#
    This is the script I use to sync Dan's IPAM changes to DNS...  Start at line 50!
        Just update line: 152: $myRows = $ipamDT.Rows | Where-Object { $_.address.StartsWith("10.236.") -or $_.address.StartsWith("151.122.192.") -or $_.address.StartsWith("151.122.193.")}
#>


$dnsServer = "cdc-dc01.powereng.com"

$aRecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName "powereng.com" -RRType A
$ptrRecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName "10.in-addr.arpa" -RRType Ptr

$ipamRecords = Import-CSV -Delimiter "," -LiteralPath "C:\Users\kbriney-adm\Tmp\ipamrecords.csv"

$ttl = [TimeSpan]::new(1,0,0)
$a = 0
while($a -lt $ipamRecords.Length)
{
    Write-Host -NoNewline ("{2,4:D}) Testing for: {0}/{1}..." -f @($ipamRecords[$a].HostName, $ipamRecords[$a].Address, $a))
    $aRecByName = $aRecords | Where-Object { $_.HostName -eq $ipamRecords[$a].HostName }
    $aRecByIP = $aRecords | Where-Object { $_.RecordData.IPv4Address -eq $ipamRecords[$a].Address }

    $octets = $ipamRecords[$a].Address -split "\."
    $ptrHostName = "{0}.{1}.{2}" -f @($octets[3], $octets[2], $octets[1])
    $ptrDomainName = "{0}.powereng.com." -f @($ipamRecords[$a].HostName.ToLower())

    $ptrRecByName = $ptrRecords | Where-Object { $_.RecordData.PtrDomainName -eq $ptrDomainName }
    $ptrRecByIP = $ptrRecords | Where-Object { $_.HostName -eq $ptrHostName }

    if (($null -eq $aRecByName) -and ($null -eq $aRecByIP) -and  ($null -eq $ptrRecByName) -and ($null -eq $ptrRecByIP))
    {
        Write-Host -ForegroundColor Green -NoNewline "No DNS A or PTR record.  Creating..."
        try
        {
            Add-DnsServerResourceRecord -ZoneName "powereng.com" -ComputerName "CDC-DC01" -CreatePtr -IPv4Address $ipamRecords[$a].Address -Name $ipamRecords[$a].HostName -A -AgeRecord -TimeToLive $ttl
            Write-Host -ForegroundColor Green "Success"
        }
        catch
        {
            Write-Host -ForegroundColor Red "Error"
        }
    } `
    else # NOT (($null -eq $aRecByName) -and ($null -eq $aRecByIP) -and  ($null -eq $ptrRecByName) -and ($null -eq $ptrRecByIP))
    {
        Write-Host -ForegroundColor Yellow ("ARecByName: {0}`tARecByIP: {1}`tPTRRecByName: {2}`tPTRRecByIP: {3}" -f @($aRecByName.RecordData.IPv4Address, $aRecByIP.HostName, $ptrRecByName.HostName, $ptrRecByIP.RecordData.PtrDomainName))
    }

    $a++
}

$dnsServer = "cdc-dc01.powereng.com"


# To load powereng-dev.local, rerun loading the A and PTR records with after:  Note, have to be authenticated to powereng-dev.local first...
# $dnsServer = "DDCD-DC01"

. .\Log.ps1

$logPath = "{0}\FixDNSPTR.log" -f @($env:TEMP)
[Log]::Init($logPath, "SyncIPAMDNS", 14, 1, [LogLevel]::INFO)
[Log]::Info("Logging initialized...")

. .\DBConnectionMYSQL.ps1

#  Build a connection string from the configuration data and the credential
$dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};Default Command Timeout=600;" -f @(
    "ddc-ipam02.powereng.com",
    3306,
    "gestioip",
    "gestioip",
    "1n33dmCB!"
)

#  Make a connection to the database
$ipamDB = [MySQLDBConnection]::new($dbConnectionString)

Write-Host "Loading IPAM data..."
$ipamDT = $ipamDB.GetDataTable("select h.hostname, INET_NTOA(h.ip) as address, cnce2.entry as aZone, cnce3.entry as ptrZone from host h inner join net n on h.red_num = n.red_num left join custom_net_column_entries cnce2 on (n.red_num = cnce2.net_id) and (cnce2.cc_id = 2) left join custom_net_column_entries cnce3 on (n.red_num = cnce3.net_id) and (cnce3.cc_id = 3) where h.hostname <> '' order by h.ip;")
$ipamSubnetsDT = $ipamDB.GetDataTable("SELECT * FROM net WHERE red LIKE '10.%' ORDER BY INET_ATON(red);")
# $ipamSubnets = [System.Collections.Generic.List[System.Data.DataRow]]::new()
# $ipamSubnetsDT.Rows | ForEach-Object { $ipamSubnets.Add($_) }
$ipamRecords = [System.Collections.Generic.List[System.Data.DataRow]]::new()
$ipamDT.Rows | ForEach-Object { $ipamRecords.Add($_) }

Write-Host ("Loaded {0} IPAM records." -f @($ipamDT.Rows.Count))

$aRecordZoneNames = @($ipamDT | Select-Object -Unique -ExpandProperty aZone | Where-Object { -not [String]::IsNullOrEmpty($_) })
$ptrZoneNames = @($ipamDT | Select-Object -Unique -ExpandProperty ptrZone | Where-Object { -not [String]::IsNullOrEmpty($_) })

$aRecordCollections = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]]]::new()
$ptrRecordCollections = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]]]::new()




$a = 0
while($a -lt $aRecordZoneNames.Length)
{
    Write-Host -ForegroundColor Green -NoNewline ("Loading A records from {0} zone {1}..." -f @($dnsServer, $aRecordZoneNames[$a]))
    try
    {
        $rrs = @(Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $aRecordZoneNames[$a] -RRType A -ErrorAction Stop)
        $records = [System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]::new()

        $rrs | ForEach-Object { $records.Add($_) }
        $aRecordCollections.Add($aRecordZoneNames[$a], $records)
        Write-Host -ForegroundColor Green ("loaded {0} records." -f @($records.Count))
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed..."
    }

    $a++
}

$a = 0
while($a -lt $ptrZoneNames.Length)
{
    Write-Host -ForegroundColor Green -NoNewline ("Loading PTR records from {0} zone {1}..." -f @($dnsServer, $ptrZoneNames[$a]))
    try
    {
        $rrs = @(Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $ptrZoneNames[$a] -RRType PTR -ErrorAction Stop)
        $records = [System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]::new()

        $rrs | ForEach-Object { $records.Add($_) }
        $ptrRecordCollections.Add($ptrZoneNames[$a], $records)
        Write-Host -ForegroundColor Green ("loaded {0} records." -f @($records.Count))
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed..."
    }

    $a++
}
<#
    To check for synchronicity between IPAM and DNS many items must be checked.
        IPAM to DNS:
            Make sure any A record with a matching host name also has a matching IP address
                Make note of multiple matching A records
                Remove all A records from the list where host name and IP address match

            Make sure any PTR record with a matching IP address also has a matching host name
                Make not of multiple matching PTR records
                Remove all PTR records from the list where host name and IP address match

            Remove IPAM record from list of all A and PTR records are a match

            Any IPAM records which remain after all records have been checked are "suspicious"

        DNS to IPAM:


    #>
$badRecs = @()
$allData = @()
$myRows = $ipamDT.Rows | Where-Object { $_.address.StartsWith("10.232.") -or $_.address.StartsWith("151.122.160.") -or $_.address.StartsWith("151.122.161.")}
$a = 0
while($a -lt $myRows.Length)
{
    $row = $myRows[$a]
    $d = "" | Select-Object HostName, Address, AZone, PTRZone, HaveAZone, ARecsByName, ARecsByIP, ARecsByNameIncorrectIPs, HavePTRZone, PTRRecsByName, PTRRecsByIP, PTRRecsByNameIncorrectIPs, ARecsByIPIncorrectNames, PTRRecsByIPIncorrectNames
    if (-not [String]::IsNullOrEmpty($row.hostname))
    {
        $d.HostName = $row.hostname.ToLower()
    } `
    else # NOT (-not [String]::IsNullOrEmpty($row.hostname))
    {
        # Nothing.
    }

    if (-not [String]::IsNullOrEmpty($row.address))
    {
        $d.Address = $row.address
    } `
    else # NOT (-not [String]::IsNullOrEmpty($row.address))
    {
        # Nothing.
    }
    $d.AZone = $row.aZone
    $d.PTRZone = $row.ptrZone
    $d.HaveAZone = (-not [String]::IsNullOrEmpty($d.AZone)) -and (@($aRecordCollections.Keys) -contains $d.AZone) -and ($aRecordCollections[$d.AZone].Count -gt 0)
    $d.ARecsByName = @()
    $d.ARecsByIP = @()
    $d.HavePTRZone = (-not [String]::IsNullOrEmpty($d.PTRZone)) -and (@($ptrRecordCollections.Keys) -contains $d.PTRZone) -and ($ptrRecordCollections[$d.PTRZone].Count -gt 0)
    $d.PTRRecsByName = @()
    $d.PTRRecsByIP = @()
    $d.ARecsByIPIncorrectNames = @()
    $d.ARecsByNameIncorrectIPs = @()
    $d.PTRRecsByIPIncorrectNames = @()
    $d.PTRRecsByNameIncorrectIPs = @()

    if (-not [String]::IsNullOrEmpty($d.HostName))
    {
        if ($d.HaveAZone)
        {
            $aRecs = @($aRecordCollections[$d.AZone] | Where-Object { $_.HostName -eq $d.HostName })

            $b = 0
            while($b -lt $aRecs.Length)
            {
                if($aRecs[$b].RecordData.IPv4Address.IPAddressToString -eq $d.Address)
                {
                    $d.ARecsByName += $aRecs[$b]
                } `
                else
                {
                    $d.ARecsByNameIncorrectIPs += $aRecs[$b]
                }
                $b++
            }
        } `
        else # NOT ($d.HaveAZone)
        {
            # Nothing.
        }

        if ($d.HavePTRZone)
        {
            # working on splitting the PTR zone to get the IP address for the PTR record...Might be another way...
            $netAddrStart = @($d.PTRZone.Replace(".in-addr.arpa","").Split('.'))
            [Array]::Reverse($netAddrStart)

            $ptrDomainName = "{0}.{1}." -f @($d.HostName, $d.AZone.ToLower())
            $ptrRecs = @($ptrRecordCollections[$d.PTRZone] | Where-Object { $_.RecordData.PtrDomainName -eq $ptrDomainName })

            # Check for PTR records where the record's address does not match IPAM
            $b = 0
            while($b -lt $ptrRecs.Length)
            {
                $hostAddrOctets = $ptrRecs[$b].HostName -split '\.'
                $netAddrStart | Foreach-Object { $hostAddrOctets += $_ }
                [Array]::Reverse($hostAddrOctets)
                $ptrRecIPAddress = $hostAddrOctets -join "."

                if ($d.Address -eq $ptrRecIPAddress)
                {
                    $d.PTRRecsByName += $ptrRecs[$b]
                } `
                else
                {
                    $d.PTRRecsByNameIncorrectIPs += $ptrRecs[$b]
                }

                $b++
            }
        } `
        else # NOT ($d.HavePTRZone)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($d.HostName))
    {
        # Nothing.
    }

    if (-not [String]::IsNullOrEmpty($d.Address))
    {
        if ($d.HaveAZone)
        {
            $aRecs = @($aRecordCollections[$d.AZone] | Where-Object { $_.RecordData.IPv4Address -eq $d.Address })

            $b = 0
            while($b -lt $aRecs.Length)
            {
                if($aRecs[$b].HostName -eq $d.HostName)
                {
                    $d.ARecsByIP += $aRecs[$b]
                } `
                else
                {
                    $d.ARecsByIPIncorrectNames += $aRecs[$b]
                }
                $b++
            }

        } `
        else # NOT ($d.HaveAZone)
        {
            # Nothing.
        }

        if ($d.HavePTRZone)
        {
            $octets = $d.Address -split "\."
            $ptrHostName = "{0}.{1}.{2}" -f @($octets[3], $octets[2], $octets[1])
            $ptrRecs =  @($ptrRecordCollections[$d.PTRZone] | Where-Object { $_.HostName -eq $ptrHostName })
            $fqdn = "{0}.{1}." -f @($d.HostName, $d.AZone)
            $b = 0
            while($b -lt $ptrRecs.Length)
            {
                if($fqdn -eq $ptrRecs[$b].RecordData.PtrDomainName)
                {
                    $d.PTRRecsByIP += $ptrRecs[$b]
                } `
                else
                {
                    $d.PTRRecsByIPIncorrectNames += $ptrRecs[$b]
                }
                $b++
            }
        } `
        else # NOT ($d.HavePTRZone)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($d.Address))
    {
        # Nothing.
    }

    if(($d.ARecsByNameIncorrectIPs.Length -ne 0) -or
        ($d.ARecsByIPIncorrectNames.Length -ne 0) -or
        (($d.HavePTRZone) -and ($d.PTRRecsByNameIncorrectIPs.Length -ne 0)) -or
        (($d.HavePTRZone) -and ($d.PTRRecsByIPIncorrectNames.Length -ne 0)) -or
        ($d.ARecsByName.Length -eq 0) -or
        ($d.ARecsByIP.Length -eq 0) -or
        (($d.HavePTRZone) -and ($d.PTRRecsByIP.Length -eq 0)) -or
        (($d.HavePTRZone) -and ($d.PTRRecsByName.Length -eq 0)))
    {
        $badRecs += $d
    }

    $allData += $d
    Write-Host ("H: {0}, A:{1}, AZ:{2}, PZ:{3}, ABN:{4} ({5}), ABI:{6} ({7}), PBN:{8} ({9}), PBI:{10} ({11})" -f @(
        $d.HostName,
        $d.Address,
        $d.AZone,
        $d.PTRZone,
        $d.ARecsByName.Length,
        $d.ARecsByNameIncorrectIPs.Length,
        $d.ARecsByIP.Length,
        $d.ARecsByIPIncorrectNames.Length,
        $d.PTRRecsByName.Length,
        $d.PTRRecsByNameIncorrectIPs.Length,
        $d.PTRRecsByIP.Length,
        $d.PTRRecsByIPIncorrectNames.Length))

    $a++
}

$sbCommand = [System.Text.StringBuilder]::new()
$doAdditions = $true
$doRemovals = $false
$a = 0
while($a -lt $badRecs.Length)
{
    $d = $badRecs[$a]

    $z = "" | Select-Object NeedARec, NeedPTRRec
    $z.NeedARec = $false
    $z.NeedPTRRec = $false

    $b = 0
    while($b -lt $d.ARecsByIPIncorrectName.Length)
    {
        # Need to remove bad A Record...

        Write-Host ("{4}: Removing A Record (by IP w/Incorrect Name): zone: {0}, IPAM Hostname: {1}, IPAM Address: {2}, A Record IP: {3}" -f @($d.AZone, $d.HostName, $d.Address, $d.ARecsByIPIncorrectName[$b].RecordData.IPv4Address.IPAddressToString, $doRemovals))
        if($doRemovals)
        {
            try
            {
                # $d.ARecsByIPIncorrectName[$a] | Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $d.AZone -Force -ErrorAction Stop
            }
            catch { }
        }

        $b++
    }

    $b = 0
    while($b -lt $d.ARecsByNameIncorrectIPs.Length)
    {
        # Need to remove bad A Record...

        Write-Host ("{4}: Removing A Record (by IP w/Incorrect Name): zone: {0}, IPAM Hostname: {1}, IPAM Address: {2}, A Record IP: {3}" -f @($d.AZone, $d.HostName, $d.Address, $d.ARecsByNameIncorrectIPs[$b].RecordData.IPv4Address.IPAddressToString, $doRemovals))
        if($doRemovals)
        {
            try
            {
                # $d.ARecsByNameIncorrectIP[$a] | Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $d.AZone -Force -ErrorAction Stop
            }
            catch { }
        }
        $b++
    }

    if($d.HavePTRZone)
    {
        $b = 0
        while($b -lt $d.PTRRecsByIPIncorrectName.Length)
        {
            # Need to remove bad PTR Record...

            Write-Host ("{4}: Removing PTR Record (by IP w/Incorrect Name): zone: {0}, IPAM Hostname: {1}, IPAM Address: {2}, PTR Record Hostname: {3}" -f @($d.PTRZone, $d.Address, $d.PTRRecsByIPIncorrectName[$b].RecordData.PtrDomainName, $doRemovals))
            if($doRemovals)
            {
                try
                {
                    # $d.PTRRecsByIPIncorrectName[$a] | Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $d.PTRZone -Force
                }
                catch { }
            }

            $b++
        }

        $b = 0
        while($b -lt $d.PTRRecsByNameIncorrectIP.Length)
        {
            # Need to remove bad PTR Record...

            Write-Host ("{4}: Removing PTR Record (by Name w/Incorrect IP): zone: {0}, IPAM Hostname: {1}, IPAM Address: {2}, PTR Record Hostname: {3}" -f @($d.PTRZone, $d.Address, $d.PTRRecsByNameIncorrectIP[$b].RecordData.PtrDomainName, $doRemovals))
            if($doRemovals)
            {
                try
                {
                    # $d.PTRRecsByNameIncorrectIP[$a] | Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $d.PTRZone -Force -ErrorAction Stop
                }
                catch { }
            }

            $b++
        }
    }
    if(($d.HaveAZone) -and ($d.ARecsByName.Length -eq 0))
    {
        # Need to create an A Record
        $z.NeedARec = $true
    }

    if(($d.HavePTRZone) -and ($d.PTRRecsByIP.Length -eq 0))
    {
        # Need PTR Record
        $z.NeedPTRRec = $true
    }

    if($z.NeedARec)
    {
        Write-Host -NoNewline ("{2}: Creating A Record for: {0}:{1}" -f @($d.HostName, $d.Address, $doAdditions))
        if(($d.HavePTRZone) -and ($z.NeedPTRRec))
        {
            Write-Host -NoNewline " with PTR record"
        }
        Write-Host

        if($doAdditions)
        {
            try
            {
                # Add-DnsServerResourceRecordA -ComputerName $dnsServer -ZoneName $d.AZone -Name $d.HostName -IPv4Address ([IPAddress]::Parse($d.Address)) -TimeToLive ([TimeSpan]::new(0,10,0)) -AgeRecord -CreatePtr:($d.HavePTRZone -and $z.NeedPTRRec) -ErrorAction Stop
                [void] $sbCommand.AppendLine( ("Add-DnsServerResourceRecordA -ComputerName `"{0}`" -ZoneName `"{1}`" -Name `"{2}`" -IPv4Address `"{3}`" -TimeToLive {4} -AgeRecord -CreatePtr:`${5} -ErrorAction Stop" -f @($dnsServer, $d.AZone, $d.HostName, ([IPAddress]::Parse($d.Address)), ([TimeSpan]::new(0,10,0)), ($d.HavePTRZone -and $z.NeedPTRRec))) )
                $z.NeedARec = $false
                $z.NeedPTRRec = $false  # Created the PTR record when the A record was created, so we no longer need a PTR record (if we did to start with)
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to created A record for: {0}:{1}" -f @($d.HostName, $d.Address))
            }
        }
    }

    if($d.HavePTRZone)
    {
        if($z.NeedPTRRec)
        {
            $octets = $d.Address -split "\."
            $netName = $d.PTRZone.Replace(".in-addr.arpa","")
            $netNameOctets = $netName -split "\."

            $ptrHostNameSB = [System.Text.StringBuilder]::new()
            for($o = 3; $o -ge $netNameOctets.Length; $o--)
            {
                [void] $ptrHostNameSB.Append(("{0}." -f $($octets[$o])))
            }
            $ptrHostName = $ptrHostNameSB.ToString().TrimEnd(@('.'))

            $ptrDomainName = "{0}.{1}." -f @($d.HostName, $d.AZone.ToLower())
            Write-Host ("{4}: Creating PTR Record for: {0}:{1} [{2}:{3}]" -f @($d.HostName, $d.Address, $ptrHostName, $ptrDomainName, $doAdditions))
            if($doAdditions)
            {
                try
                {
                    # Add-DnsServerResourceRecordPtr -ComputerName $dnsServer -ZoneName $d.PTRZone -Name $ptrHostName -PtrDomainName $ptrDomainName -TimeToLive ([TimeSpan]::new(0,10,0)) -AgeRecord -ErrorAction Stop
                    [void] $sbCommand.AppendLine(("Add-DnsServerResourceRecordPtr -ComputerName `"{0}`" -ZoneName `"{1}`" -Name `"{2}`" -PtrDomainName `"{3}`" -TimeToLive `"{4}`" -AgeRecord -ErrorAction Stop" -f @($dnsServer, $d.PTRZone, $ptrHostName, $ptrDomainName, ([TimeSpan]::new(0,10,0)))))
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to created PTR record for: {0}:{1} [{2}:{3}]" -f @($d.HostName, $d.Address, $ptrHostName, $ptrDomainName))
                }
            }
        }
    }

    $a++
}

$sbCommand.ToString() | Set-Clipboard
