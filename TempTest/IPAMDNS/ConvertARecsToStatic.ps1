function GetIPAMData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [Int32]
        $lastUpdate = -1
    )

    $ipamDB = $null

    try
    {
        #  Make a connection to the database
        $ipamDB = [MySQLDBConnection]::new($Global:dbConnectionString)
        if ($null -ne $ipamDB)
        {
            $ipamDT = $ipamDB.GetDataTable("SELECT version FROM global_config;")
            if (($null -ne $ipamDT) -and ($ipamDT.Rows.Count -gt 0))
            {
                [Log]::Info("Gestioip version: {0}" -f @($ipamDT.Rows[0].version))
            } `
            else # NOT (($null -ne $ipamDT) -and ($ipamDT.Rows.Count -gt 0))
            {
                [Log]::Warning("Unable to get Gestioip version from IPAM DB.")
            }
        } `
        else # NOT ($null -ne $ipamDB)
        {
            [Log]::Error("Unable to connect to IPAM DB.")
        }
    }
    catch
    {
        [Log]::Error("Failed to connect to IPAM database.")
        $ipamDB = $null
    }

    if ($null -ne $ipamDB)
    {
        $lastUpdateClause = [String]::Empty
        if ($lastUpdate -ne -1)
        {
            $lastUpdateClause = "(last_update >= {0}) AND " -f @($lastUpdate)
        } `
        else # NOT ($lastUpdate -ne -1)
        {
            # Nothing.
        }

        $selectStatement = "SELECT h.id as id, h.hostname, INET_NTOA(h.ip) AS address, cnce2.entry AS aZone, cnce3.entry AS ptrZone, h.last_update FROM host h INNER JOIN net n ON h.red_num = n.red_num LEFT JOIN custom_net_column_entries cnce2 ON (n.red_num = cnce2.net_id) AND (cnce2.cc_id = 2) LEFT JOIN custom_net_column_entries cnce3 ON (n.red_num = cnce3.net_id) AND (cnce3.cc_id = 3) WHERE {0}(h.hostname <> '') ORDER BY h.ip;" -f @($lastUpdateClause)
        $ipamDT = $ipamDB.GetDataTable($selectStatement)
        if ($null -ne $ipamDT)
        {
            $Global:ipamRecordsByAddress = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Data.DataRow]]]::new()
            $ipamDT.Rows | ForEach-Object {
                if (-not $Global:ipamRecordsByAddress.ContainsKey($_.address))
                {
                    $nl = [System.Collections.Generic.List[System.Data.DataRow]]::new()
                    $Global:ipamRecordsByAddress.Add($_.address, $nl)
                } `
                else # NOT (-not $Global:ipamRecordsByAddress.ContainsKey($_.address))
                {
                    # Nothing.
                }
                $Global:ipamRecordsByAddress[$_.address].Add($_)
            }
        } `
        else # NOT ($null -ne $ipamDT)
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $ipamDB)
    {
        # Nothing.
    }
}

function FixDynamicARecords
{
    $startDT = [DateTime]::Now.AddHours(-12)
    $past = [DateTime]::Parse("1970-01-01T00:00:00Z")
    $timestamp = [int32] [Math]::Floor(($startDT - $past).TotalSeconds)

    GetIPAMData -lastUpdate $timestamp
    if ($null -ne $Global:ipamRecordsByAddress)
    {
        $addresses = @($Global:ipamRecordsByAddress.Keys)

        # Only bother loading DNS records if there is a possibility we need to convert one to static...
        if ($addresses.Length -gt 0)
        {
            $dnsServers = @()
            try
            {
                $dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses.Length -gt 0 })
            }
            catch
            {
                [Log]::Error("Failed to retrieve client DNS servers.")
            }

            $aRecs = @()
            $b = 0
            while(($b -lt $dnsServers.Length) -and ($aRecs.Length -eq 0))
            {
                $c = 0
                while(($c -lt $dnsServers[$b].ServerAddresses.Length) -and ($aRecs.Length -eq 0))
                {
                    try
                    {
                        # Filter the A records down to only the ones that are not static.
                        $aRecs = @(Get-DnsServerResourceRecord -ComputerName $dnsServers[$b].ServerAddresses[$c] -ZoneName "powereng.com" -RRType "A" -ErrorAction Stop | Where-Object { $null -ne $_.Timestamp })
                    }
                    catch
                    {
                        $aRecs = @()
                    }
                    $c++
                }
                $b++
            }

            if ($aRecs.Length -gt 0)
            {
                $a = 0
                while($a -lt $addresses.Length)
                {
                    # Already filtered $aRecs to only dynamic records, so no need to check .Timestamp
                    $dynamicARec = $aRecs | Where-Object { $_.RecordData.IPv4Address.ToString()-eq $addresses[$a]}
                    if ($null -ne $dynamicARec)
                    {
                        if ((MakeDNSRecordStatic -dnsRec $dynamicARec))
                        {
                            [Log]::Info("Converted {0}/{1} to static record." -f @($addresses[$a], $dynamicARec.HostName))
                        } `
                        else # NOT ((MakeDNSRecordStatic -dnsRec $dynamicARec))
                        {
                            [Log]::Warning("Failed to convert {0}/{1} to static record." -f @($addresses[$a], $dynamicARec.HostName))
                        }
                    } `
                    else # NOT ($null -ne $dynamicARec)
                    {
                        # Nothing.
                    }
                    $a++
                }
            } `
            else # NOT ($aRecs.Length -gt 0)
            {
                [Log]::Error("No DNS A records loaded.")
            }
        } `
        else # NOT ($addresses.Length -gt 0)
        {
            [Log]::Info("No IPAM records changed since {0}." -f @($startDT.ToString()))
        }
    } `
    else # NOT ($null -ne $Global:ipamRecordsByAddress)
    {
        # Nothing.
    }
}

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\TempTest\Log.ps1

$logPath = $env:TEMP
[Log]::Init($logPath, "FixDynamicARecords", 14, 1, [LogLevel]::INFO)
[Log]::Info("Logging initialized...")

$mysqlAssemblyAvailable = $true
if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
{
    try
    {
        [System.Reflection.Assembly]::LoadWithPartialName("MySQL.Data") | Out-Null

        if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
        {
            [Log]::Error("Unable to load MySQL.Data assembly.")
            $mysqlAssemblyAvailable = $false
        } `
        else
        {
            # Nothing.
        }
    }
    catch
    {
        [Log]::Error("Unable to load MySQL.Data assembly.")
        $mysqlAssemblyAvailable = $false
    }
} `
else
{
    # Nothing.
}

if ($mysqlAssemblyAvailable)
{
    #  Build a connection string from the configuration data and the credential
    $Global:dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};Default Command Timeout=600;" -f @(
        "ddc-ipam02.powereng.com",
        3306,
        "gestioip",
        "gestioip",
        "1n33dmCB!"
    )

    . C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\TempTest\DBConnectionMYSQL.ps1

    FixDynamicARecords
} `
else # NOT ($mysqlAssemblyAvailable)
{
    [Log]::Warning("MySQL assembly not available.")
}
