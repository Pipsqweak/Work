$aRecords = Get-DnsServerResourceRecord -ComputerName "CDC-DC01" -ZoneName "powereng.com" -RRType A
$ptrRecords = Get-DnsServerResourceRecord -ComputerName "CDC-DC01" -ZoneName "10.in-addr.arpa" -RRType Ptr
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

$dnsServer = "CDC-DC01"

. .\Log.ps1   # Once the [Log] class is loaded

$logPath = "{0}\SyncIPAMDNS.log" -f @($env:TEMP)
[Log]::Init($logPath, "SyncIPAMDNS", 14, 1, [LogLevel]::INFO)
[Log]::Info("Logging initialized...")

. .\DBConnectionMYSQL.ps1

#  Build a connection string from the configuration data and the credential
$dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};Default Command Timeout=600;" -f @(
    "ddc-ipam01.powereng.com",
    3306,
    "gestioip",
    "gestioip",
    "1n33dmCB!"
)

#  Make a connection to the database
$ipamDB = [MySQLDBConnection]::new($dbConnectionString)

$ipamDT = $ipamDB.GetDataTable("select h.hostname, INET_NTOA(h.ip) as address, cnce2.entry as aZone, cnce3.entry as ptrZone from host h inner join net n on h.red_num = n.red_num left join custom_net_column_entries cnce2 on (n.red_num = cnce2.net_id) and (cnce2.cc_id = 2) left join custom_net_column_entries cnce3 on (n.red_num = cnce3.net_id) and (cnce3.cc_id = 3) where h.hostname <> '' order by h.ip;")

$aRecordZoneNames = @($ipamDT | Select-Object -Unique -ExpandProperty aZone | Where-Object { -not [String]::IsNullOrEmpty($_) })
$ptrZoneNames = @($ipamDT | Select-Object -Unique -ExpandProperty ptrZone | Where-Object { -not [String]::IsNullOrEmpty($_) })

$aRecordCollections = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]]]::new()
$ptrRecordCollections = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]]]::new()

$ipamRecords = [System.Collections.Generic.List[System.Data.DataRow]]::new()
$ipamDT.Rows | ForEach-Object { $ipamRecords.Add($_) }



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
$a = 0
while($a -lt $ipamDT.Rows.Count)
{
    $d = "" | Select-Object HostName, Address, HaveAZone, ARecsByName, ARecsByIP, ARecsByNameIncorrectIPs, HavePTRZone, PTRRecsByName, PTRRecsByIP, PTRRecsByNameIncorrectIPs
    if (-not [String]::IsNullOrEmpty($ipamDT.Rows[$a].hostname))
    {
        $d.HostName = $ipamDT.Rows[$a].hostname.ToLower()
    } `
    else # NOT (-not [String]::IsNullOrEmpty($ipamDT.Rows[$a].hostname))
    {
        # Nothing.
    }

    if (-not [String]::IsNullOrEmpty($ipamDT.Rows[$a].address))
    {
        $d.Address = $ipamDT.Rows[$a].address
    } `
    else # NOT (-not [String]::IsNullOrEmpty($ipamDT.Rows[$a].address))
    {
        # Nothing.
    }
    $d.HaveAZone = -not [String]::IsNullOrEmpty($ipamDT.Rows[$a].aZone)
    $d.ARecsByName = @()
    $d.ARecsByIP = @()
    $d.HavePTRZone = -not [String]::IsNullOrEmpty($ipamDT.Rows[$a].ptrZone)
    $d.PTRRecsByName = @()
    $d.PTRRecsByIP = @()
    $d.ARecsByNameIncorrectIPs = @()
    $d.PTRRecsByNameIncorrectIPs = @()

    if (-not [String]::IsNullOrEmpty($d.HostName))
    {
        if ($d.HaveAZone)
        {
            $d.ARecsByName = @($aRecordCollections[$ipamDT.Rows[$a].aZone] | Where-Object { $_.HostName -eq $d.HostName })

            # Check for A records where the record's address does not match IPAM
            $d.ARecsByNameIncorrectIPs = @($d.ARecsByName | Select-Object -ExpandProperty RecordData | Select-Object -ExpandProperty IPv4Address | Select-Object -ExpandProperty IPAddressToString)
        } `
        else # NOT ($d.HaveAZone)
        {
            # Nothing.
        }

        if ($d.HavePTRZone)
        {
            # working on splitting the PTR zone to get the IP address for the PTR record...Might be another way...
            $netAddrStart = @($ipamDT.Rows[$a].ptrZone.Replace(".in-addr.arpa","").Split('.'))
            [Array]::Reverse($netAddrStart)

            $ptrDomainName = "{0}.{1}." -f @($d.HostName, $ipamDT.Rows[$a].aZone.ToLower())
            $d.PTRRecsByName = @($ptrRecordCollections[$ipamDT.Rows[$a].ptrZone] | Where-Object { $_.RecordData.PtrDomainName -eq $ptrDomainName })

            # Check for PTR records where the record's address does not match IPAM
            $r = 0
            while($r -lt $d.PTRRecsByName.Length)
            {
                $hostAddrOctets = $d.PTRRecsByName[$r].HostName -split '\.'
                $netAddrStart | Foreach-Object { $hostAddrOctets += $_ }
                [Array]::Reverse($hostAddrOctets)
                $ptrRecIPAddress = $hostAddrOctets -join "."

                if ($ipamDT.Rows[$a].address -ne $ptrRecIPAddress)
                {
                    $d.PTRRecsByNameIncorrectIPs += $ptrRecIPAddress
                } `
                else # NOT ($ipamDT.Rows[$a].address -ne $ptrRecIPAddress)
                {
                    # Nothing -- Addresses match.
                }

                $r++
            }

            $d.PTRRecsByNameIncorrectIPs = @($d.PTRRecsByName | Select-Object -ExpandProperty RecordData | Select-Object -ExpandProperty IPv4Address | Select-Object -ExpandProperty IPAddressToString)
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
            $d.ARecsByIP = @($aRecordCollections[$ipamDT.Rows[$a].aZone] | Where-Object { $_.RecordData.IPv4Address -eq $d.Address })
        } `
        else # NOT ($d.HaveAZone)
        {
            # Nothing.
        }

        if ($d.HavePTRZone)
        {
            $octets = $d.Address -split "\."
            $ptrHostName = "{0}.{1}.{2}" -f @($octets[3], $octets[2], $octets[1])
            $d.PTRRecsByIP = @($ptrRecordCollections[$ipamDT.Rows[$a].ptrZone] | Where-Object { $_.HostName -eq $ptrHostName })
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

    $d

    $a++
}
