[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

<#
    3/14/2022: KLB
        Added email alerts for WARNINGS and ERRORS.  When a message is logged that matches "^\[(WARNING|ERROR)\s*\]", the message is added to a global
           StringBuilder object ($sbErrorLog).  At the end of the script, if the $sbErrorLog's length is greater than 0, then the contents are emailed
           to all recipient addresses listed in the config file for the script.
        Changed the way errors were logged.  Instead of logging an error/warning when 0 statistics are returned from Get-RemoteAccessConnectionStatistics,
           now an error is only logged when the call to Get-RemoteAccessConnectionStatistics throws an exception.  It's fine if there are 0 records returned.

#>
$Global:doDebug = $false

Import-Module RemoteAccess

# Default values to use for email alerts.
#   These are overridden if specified in the config file
$Global:SenderAddress = "AoVPN Stats Collector <statscollector@powereng.com>"
$Global:AlertRecipients = @("Briney, Ken <ken.briney@powereng.com>")
$Global:SMTPServer = "smtp.powereng.com"

# So we can ignore the certificate issue with NetScaler...
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

# Ignore certificate issues when collecting NetScaler data...
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12

class ConnectionStat
{
    [String] $DateTime = [String]::Empty
    [String] $Server = [String]::Empty
    [String] $Location = [String]::Empty
    [Int32] $ActiveConnections = 0
    [Int64] $TotalBytesIn = 0
    [Int64] $TotalBytesOut = 0

    ConnectionStat([DateTime] $dt, [String] $serverName, [String] $location, [Int32] $activeConnections, [Int64] $totalBytesIn, [Int64] $totalBytesOut)
    {
        $this.DateTime = $dt.ToString("yyyy-MM-dd HH:mm")
        $this.Server = $serverName
        $this.Location = $location
        $this.ActiveConnections = $activeConnections
        $this.TotalBytesIn = $totalBytesIn
        $this.TotalBytesOut = $totalBytesOut
    }
}

class BandwidthStat
{
    [String] $Site = [String]::Empty
    [String] $StartTime = [String]::Empty
    [String] $EndTime = [String]::Empty
    [Double] $GBph_In = 0.0
    [Double] $GBph_Out = 0.0
    [Double] $Total_GBph
    [Double] $Mbps_In = 0.0
    [Double] $Mbps_Out = 0.0
    [Double] $Total_Mbps

    BandwidthStat([DateTime] $startTime, [DateTime] $endTime, [String] $site, [Double] $bpsIn, [Double] $bpsOut)
    {
        $this.Site = $site
        $this.GBph_In = (($bpsIn * 3600) / 1073741824)
        $this.GBph_Out = (($bpsOut * 3600) / 1073741824)
        $this.Total_GBph = $this.GBph_In + $this.GBph_Out

        $this.Mbps_In = (($bpsIn * 8) / 1048576)
        $this.Mbps_Out = (($bpsOut * 8) / 1048576)
        $this.Total_Mbps = $this.Mbps_In + $this.Mbps_Out

        $this.StartTime = $startTime.ToString("yyyy-MM-dd HH:mm")
        $this.EndTime = $endTime.ToString("yyyy-MM-dd HH:mm")
    }
}

class LocationStat
{
    [String] $ServerName = [String]::Empty
    [String] $Location = [String]::Empty
    [String] $DateTime = [String]::Empty
    [Int32] $ActiveConnections = 0
    [Double] $Bps_In = 0.0
    [Double] $Bps_Out = 0.0
    [Double] $GBph_In = 0.0
    [Double] $GBph_Out = 0.0
    [Double] $Total_GBph = 0.0
    [Double] $Mbps_In = 0.0
    [Double] $Mbps_Out = 0.0
    [Double] $Total_Mbps = 0.0

    LocationStat([DateTime] $dt, [String] $serverName, [String] $location)
    {
        $this.ServerName = $serverName
        $this.Location = $location
        $this.DateTime = $dt.ToString("yyyy-MM-dd HH:mm")
    }

    [void] UpdateBandwidthStats([Double] $bpsIn, [Double] $bpsOut)
    {
        $this.Bps_In = $bpsIn
        $this.Bps_Out = $bpsOut
        $this.GBph_In = (($this.Bps_In * 3600) / 1073741824)
        $this.GBph_Out = (($this.Bps_Out * 3600) / 1073741824)
        $this.Total_GBph = $this.GBph_In + $this.GBph_Out

        $this.Mbps_In = (($this.Bps_In * 8) / 1048576)
        $this.Mbps_Out = (($this.Bps_Out * 8) / 1048576)
        $this.Total_Mbps = $this.Mbps_In + $this.Mbps_Out
    }
}

class StatsCollection
{
    [System.Collections.Generic.List[LocationStat]] $stats = $null

    StatsCollection()
    {
        $this.stats = [System.Collections.Generic.List[LocationStat]]::new()
    }

    [LocationStat] GetLocationStat([String] $location, [String] $serverName, [DateTime] $dt)
    {
        $stat = $this.stats | Where-Object { ($_.Location -eq $location) -and ($_.ServerName -eq $serverName) -and ($_.DateTime -eq $dt.ToString("yyyy-MM-dd HH:mm")) }
        if($null -eq $stat)
        {
            $stat = [LocationStat]::new($dt, $serverName, $location)
            $this.stats.Add($stat)
        }

        return $stat
    }
}

$Global:sbErrorLog = [System.Text.StringBuilder]::new()
function Log($message)
{
    $logMessage = [String]::Empty
    if(-not $Global:doDebug)
    {
        $logMessage = "{0} : {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HH:mm:ss"), $message)
    }
    else
    {
        $logMessage = "{0} : DEBUG:{1}" -f @([DateTime]::Now.ToString("yyyyMMdd HH:mm:ss"), $message)
    }
    if((Test-Path -Path $Global:config.logFile -IsValid))
    {
        $logMessage | Out-File -FilePath $Global:config.logFile -Append -Encoding ascii
    }
    else
    {
        Write-Error $logMessage
    }

    # If the message starts with [WARNING] or [ERROR  ] then add it to the error log.
    if($message  -match "^\[(WARNING|ERROR)\s*\]")
    {
        # If this is the first time we've logged an error, add some debug information.
        if($Global:sbErrorLog.Length -eq 0)
        {
            [void] $Global:sbErrorLog.AppendLine("Execution host: {0}" -f @($env:COMPUTERNAME))
            [void] $Global:sbErrorLog.AppendLine("Script Name: {0}" -f @($PSCommandPath))
            [void] $Global:sbErrorLog.AppendLine("")
        }
        [void] $Global:sbErrorLog.AppendLine($logMessage)
    }
}

function Get-NetScalerData($uri)
{
    $response = $null
    if(-not [String]::IsNullOrEmpty($uri))
    {
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("X-NITRO-USER", 'kbriney_api')
        $headers.Add("X-NITRO-PASS", '!QAZxsw2')

        try
        {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction SilentlyContinue
        }
        catch
        {
        }
    }
    return $response
}

function Get-NetscalerConnectionStats($startTime, $endTime)
{
    $uri = "https://cdc-nsvpxmas01.powereng.com/nitro/v1/appflow/vpn_active_sessions?report_start_time={0}&report_end_time={1}&pagesize=5000" -f @(([System.DateTimeOffset]::Parse($startTime)).ToUnixTimeSeconds(), ([System.DateTimeOffset]::Parse($endTime)).ToUnixTimeSeconds())
    $response = Get-NetScalerData $uri

    $activeConnections = 0
    $totalBytesIn = 0
    # If no response, then I can't populate the numbers for real, so they'll just be 0's.
    if($null -ne $response)
    {
        if($null -ne $response.vpn_active_sessions)
        {
            $locationActiveUserSessions = @($response.vpn_active_sessions | Where-Object { -not [String]::IsNullOrEmpty($_.vpn_user_name) })

            $activeConnections = $locationActiveUserSessions.Length
            $totalBytesIn = ($locationActiveUserSessions | Measure-Object -Sum -Property total_bytes).Sum
        }
    }

    $netScalerStats =  [ConnectionStat]::new($endTime, "NetScaler", "Denver", $activeConnections, $totalBytesIn, 0)


    # New Version  vvvvvvvvvvvvvvv
    $a = 0
    while($a -lt $Global:netScalers.Length)
    {
        $locationConnections = @($response.vpn_active_sessions | Where-Object { $_.device_ip_address -in $Global:netScalers[$a].Devices })
        $activeConnections = 0

        # If no response, then I can't populate the numbers for real, so they'll just be 0's.
        if($null -ne $response)
        {
            if($null -ne $response.vpn_active_sessions)
            {
                $locationActiveUserSessions = @($response.vpn_active_sessions | Where-Object { ($_.device_ip_address -in $Global:netScalers[$a].Devices) -and (-not [String]::IsNullOrEmpty($_.vpn_user_name)) })

                $activeConnections = $locationActiveUserSessions.Length
            }
        }

        $stat = $Global:statsCollection.GetLocationStat($Global:netScalers[$a].Location, $Global:netScalers[$a].ServerName, $endTime)
        if($null -ne $stat)
        {
            $stat.ActiveConnections = $activeConnections
        }

        $a++
    }
    # ^^^^^^^^^^^^^^^^^^^^^^


    return $netScalerStats
}

function Get-NetscalerBandwidthStats($startTime, $endTime)
{
    $uri = "https://cdc-nsvpxmas01.powereng.com/nitro/v1/config/perf_ssl_vpn_report?filter=device_ip_address:/10.245.69.20|10.247.69.20|10.247.69.101/,report_start_time:{0},report_end_time:{1},vsvrName:/connecteast.powereng.com_sslvpn|vdi.powereng.com_ssl|connectwest.powereng.com_sslvpn|connectwest-poc.powereng.com_sslvpn/&pagesize=5000" -f @(([System.DateTimeOffset]::Parse($startTime)).ToUnixTimeSeconds(), ([System.DateTimeOffset]::Parse($endTime)).ToUnixTimeSeconds())
    $response = Get-NetScalerData $uri

    $netScalerStats = @()

    if(($null -ne $response) -and ($null -ne $response.perf_ssl_vpn_report))
    {
        $uniqueGateways = @($response.perf_ssl_vpn_report | Select-Object -Unique -ExpandProperty vsvrName | Sort-Object)

        foreach($gw in $uniqueGateways)
        {
            $gwStats = @($response.perf_ssl_vpn_report | Where-Object { $_.vsvrName -eq $gw })
            $avgBPS_In = ($gwStats | Measure-Object -Property requestbytesrate -Average).Average
            $avgBPS_Out = ($gwStats | Measure-Object -Property responsebytesrate -Average).Average

            $siteBandwidthStats = [BandwidthStat]::new($startTime, $endTime, $gw, $avgBPS_In, $avgBPS_Out)
            $netScalerStats += $siteBandwidthStats
        }
    }

    return $netScalerStats
}

# New Way
function Get-NetscalerBandwidthStats2($startTime, $endTime)
{
    $deviceList = @($Global:netScalers.Devices | Select-Object -Unique | Sort-Object) -join "|"
    $gatewayList = @($Global:netScalers.Gateways | Select-Object -Unique | Sort-Object) -join "|"
    $uri = "https://cdc-nsvpxmas01.powereng.com/nitro/v1/config/perf_ssl_vpn_report?filter=device_ip_address:/{0}/,report_start_time:{1},report_end_time:{2},vsvrName:/{3}/&pagesize=5000" -f @($deviceList, ([System.DateTimeOffset]::Parse($startTime)).ToUnixTimeSeconds(), ([System.DateTimeOffset]::Parse($endTime)).ToUnixTimeSeconds(), $gatewayList)
    $response = Get-NetScalerData $uri

    $a = 0
    while($a -lt $Global:netScalers.Length)
    {
        # Report 0's for the location if no stats for the location were found.
        $avgBPS_In = 0
        $avgBPS_Out = 0

        if(($null -ne $response) -and ($null -ne $response.perf_ssl_vpn_report))
        {
            $locationStats = @($response.perf_ssl_vpn_report | Where-Object { $_.vsvrName -in $Global:netScalers[$a].Gateways })
            if($locationStats.Length -gt 0)
            {
                $avgBPS_In = ($locationStats | Measure-Object -Property requestbytesrate -Average).Average
                $avgBPS_Out = ($locationStats | Measure-Object -Property responsebytesrate -Average).Average
            }
        }

        # Even if no stats were found for the location, report something...
        $stat = $Global:statsCollection.GetLocationStat($Global:netScalers[$a].Location, $Global:netScalers[$a].ServerName, $endTime)
        if($null -ne $stat)
        {
            $stat.UpdateBandwidthStats($avgBPS_In, $avgBPS_Out)
        }

        $a++
    }
}

function LoadQueuedData($qFolder, $stdStatsFile, $bwStatsFile, $mergedFile)
{
    $aStats = @()
    $bStats = @()
    $sc = [StatsCollection]::new()

    $inFile = "{0}\\{1}" -f @($qFolder, $stdStatsFile)
    if([System.IO.File]::Exists($inFile))
    {
        $aStats = Import-CSV -Path $inFile
        Log ("[INFO   ] Imported {0} standard stats from {1}" -f @($aStats.Length, $inFile))
    }
    else
    {
        Log ("[INFO   ]  No standard stats queue file: {0}" -f @($inFile))
    }

    $inFile = "{0}\\{1}" -f @($qFolder, $bwStatsFile)
    if([System.IO.File]::Exists($inFile))
    {
        $bStats = Import-CSV -Path $inFile
        Log ("[INFO   ] Imported {0} bandwidth stats from {1}" -f @($bStats.Length, $inFile))
    }
    else
    {
        Log ("[INFO   ]  No bandwidth stats queue file: {0}" -f @($inFile))
    }

    $inFile = "{0}\\{1}" -f @($qFolder, $mergedFile)
    if([System.IO.File]::Exists($inFile))
    {
        $mergedData = Import-CSV -Path $inFile
        $a = 0
        while($a -lt $mergedData.Length)
        {
            $dt = [DateTime]::Parse($mergedData[$a].DateTime)

            $tStat = [LocationStat]::new($dt, $mergedData[$a].ServerName, $mergedData[$a].Location)

            $tStat.ActiveConnections = $mergedData[$a].ActiveConnections
            $tStat.GBph_In = $mergedData[$a].GBph_In
            $tStat.GBph_Out = $mergedData[$a].GBph_Out
            $tStat.Total_GBph = $mergedData[$a].Total_GBph
            $tStat.Mbps_In = $mergedData[$a].Mbps_In
            $tStat.Mbps_Out = $mergedData[$a].Mbps_Out
            $tStat.Total_Mbps = $mergedData[$a].Total_Mbps

            $sc.stats.Add($tStat)
            $a++
        }
        Log ("[INFO   ] Imported {0} merged stats from {1}" -f @($sc.stats.Count, $inFile))
    }
    else
    {
        Log ("[INFO   ]  No merged stats queue file: {0}" -f @($inFile))
    }

    return @($aStats, $bStats, $sc)
}

function GetServerRemoteAccessStats($serverName, $location, $startTime, $endTime)
{
    $activeConnections = 0
    $totalBytesIn = 0
    $totalBytesOut = 0
    $siteTotalBytesPerSecond_In = 0
    $siteTotalBytesPerSecond_Out = 0
    $newStat = $null

    $successful = $false
    $tries = 0
    $stats = @()
    Log ("[INFO   ] Pulling active connection statistics from {0}..." -f @($serverName))
    while((-not $successful) -and ($tries -lt $Global:config.maxRetries))
    {
        # Clear any outstanding error messages so we don't log anything extraneous
        $Error.Clear()

        $tries++
        try
        {
            # Get active connection statistics...
            #   If neither a start date nor an end date is specified, then statistics for active connections is retrieved.
            $stats = @(Get-RemoteAccessConnectionStatistics -ComputerName $serverName -ErrorAction Stop)

            # If the script doesn't jump to the catch clause, then signal a successful operation.
            $successful = $true
        }
        catch
        {
            # Only log an error for the final failed attempt.
            if($tries -eq $Global:config.maxRetries)
            {
                Log ("[ERROR  ] Unable to retrieve remote access active connection statistics from {0} after {1} tries." -f @($serverName, $tries))
                $Error | ForEach-Object { Log ("[ERROR  ] `t`t{0}" -f @($_.ToString())) }
            }
            else
            {
                # Nothing, we still have remaining retries
            }
        }
    }

    # If the script was able to get active connection stats...
    if($successful)
    {
        Log ("[INFO   ] `tProcessing {0} active connection statistic(s)..." -f @($stats.Length))
        $activeConnections = $stats.Length
        $totalBytesIn = ($stats | Measure-Object -Sum -Property TotalBytesIn).Sum
        $totalBytesOut = ($stats | Measure-Object -Sum -Property TotalBytesOut).Sum

        # Get any existing stats for location/serverName or create a new record for location/serverName if none exist
        $stat = $Global:statsCollection.GetLocationStat($location, $serverName, $endTime)
        if($null -ne $stat)
        {
            # This updates the stats collection record for this site/server with the number of active sessions.
            # At appears as though $stat (or $stat.ActiveConnections) is only ever assigned a value, but remember the entire stats collection structure exists globally.
            #    So updating $stat.ActiveConections here updates the global collection.
            $stat.ActiveConnections = $stats.Length
        }

        $newStat = [ConnectionStat]::new($endTime, $serverName, $location, $activeConnections, $totalBytesIn, $totalBytesOut)

        # Next pull historical statistics data.
        Log ("[INFO   ] Pulling hourly statistics from {0}." -f @($serverName))
        $successful = $false
        $tries = 0
        $stats = @()
        while((-not $successful) -and ($tries -lt $Global:config.maxRetries))
        {
            # Clear any outstanding error messages so we don't log anything extraneous
            $Error.Clear()

            $tries++
            try
            {
                # Get historical connection statistics...
                #     By providing start and end time for statistics, we get historical statistics for the time period specified.
                $stats = @(Get-RemoteAccessConnectionStatistics -ComputerName $serverName -StartDateTime $startTime -EndDateTime $endTime -ErrorAction SilentlyContinue)

                # If the script doesn't jump to the catch clause, then signal a successful operation.
                $successful = $true
            }
            catch
            {
                # Only log an error for the final failed attempt.
                if($tries -eq $Global:config.maxRetries)
                {
                    Log ("[ERROR  ] Unable to retrieve remote access historical connection statistics from {0} after {1} tries." -f @($serverName, $tries))
                    $Error | ForEach-Object { Log ("[ERROR  ] `t`t{0}" -f @($_.ToString())) }
                }
                else
                {
                    # Nothing, we still have remaining retries
                }
            }
        }

        if($successful)
        {
            Log ("[INFO   ] `tProcessing {0} hourly statistic(s)..." -f @($stats.Length))
            $a = 0
            while($a -lt $stats.Length)
            {
                if($stats[$a].ConnectionDuration -gt 0)
                {
                    $siteTotalBytesPerSecond_In +=  ($stats[$a].TotalBytesIn / $stats[$a].ConnectionDuration)
                    $siteTotalBytesPerSecond_Out += ($stats[$a].TotalBytesOut / $stats[$a].ConnectionDuration)
                }
                else
                {
                    # Nothing, just avoiding a division by zero error.
                }
                $a++
            }

            if($null -ne $stat)
            {
                # Update the site's bandwidth usage stats
                $stat.UpdateBandwidthStats($siteTotalBytesPerSecond_In, $siteTotalBytesPerSecond_Out)
            }
        }
        else
        {
            # Nothing, if no statistics were retrieved, then there is nothing to do
        }
    }
    else
    {
        # Nothing, an error was already logged
    }

    return $newStat
}

function GetSiteRemoteAccessStats($location, $siteCode, $servers, $startTime, $endTime)
{
    $site_TotalBytesPerSecond_In = 0
    $site_TotalBytesPerSecond_Out = 0
    if($null -ne $servers)
    {
        $a = 0
        while($a -lt $servers.Length)
        {
            $serverName = $servers[$a]
            $siteStats = GetServerRemoteAccessStats $serverName $location $startTime $endTime
            if($null -ne $siteStats)
            {
                $Global:allStats += $siteStats
                $stat = $statsCollection.GetLocationStat($location, $serverName, $endTime)
                if($null -ne $stat)
                {
                    $site_TotalBytesPerSecond_In += $stat.Bps_In
                    $site_TotalBytesPerSecond_Out += $stat.Bps_Out
                }
            }
            $a++
        }
    }

    $siteBandwidthStats = [BandwidthStat]::new($startTime, $endTime, $location,  $site_TotalBytesPerSecond_In,  $site_TotalBytesPerSecond_Out)
    $Global:bandwidthStats += $siteBandwidthStats
}

# If we are debugging, the generate at least 1 warning so an email alert is sent.
if($Global:doDebug)
{
    Log "[WARNING] Running in debug mode.  Creating a warning to ensure email alerting works."
}

# Config file -- For debugging
# $JSONArgsFile = "E:\Scripts\RemoteAccessStats\config.json"  #"C:\Users\kbriney-adm\PSScripts\RemoteAccessStats\sites.json"
$haveAllRequirements = $true

$Global:config = $null
$runtimeFileStamp = [DateTime]::Now.ToString("MMddyyyyHHmm")

if(-not [String]::IsNullOrEmpty($JSONArgsFile))
{
    if(Test-Path -Path $JSONArgsFile)
    {
        try
        {
            $Global:config = Get-Content -Path $JSONArgsFile | ConvertFrom-Json -ErrorAction Stop

            if($null -ne $Global:config)
            {
                if(-not [String]::IsNullOrEmpty($Global:config.logFile))
                {
                    if(-not (Test-Path -Path $Global:config.logFile -IsValid))
                    {
                        Log ("[WARNING] logFile value ({0}) is invalid.  Logging will be to the console only." -f @($Global:config.logFile))
                        Log ("[WARNING]`tExample: `"logFile`": `"E:\\DAStatsWork\\Logs\\DAStats_test.Log`"")
                        Log ("[WARNING]`t`t'\' characters in .json files need to be escaped to '\\'")

                        # No need to change $haveAllRequirements, logging will just be to the console.
                    }
                    else
                    {
                        # Nothing, $Global:config.logFile is valid
                    }
                }
                else
                {
                    Log ("[WARNING] Missing value for logFile.  Logging will be to the console only.")
                    Log ("[WARNING]`tExample: `"logFile`": `"E:\\DAStatsWork\\Logs\\DAStats_test.Log`"")
                    Log ("[WARNING]`t`t'\' characters in .json files need to be escaped to '\\'")

                    # No need to change $haveAllRequirements, logging will just be to the console.
                }

                if($null -ne $Global:config.maxRetries)
                {
                    if($Global:config.maxRetries -isnot [int])
                    {
                        Log ("[WARNING] maxTries is not an integer value in the range 1 - 10.")
                        Log ("[WARNING]`tExample: `"maxRetries`": 2")
                        Log ("[WARNING]`tDefaulting to 2.")
                        $Global:config.maxRetries = 2
                    }
                    else
                    {
                        if(($Global:config.maxRetries -lt 1) -or ($Global:config.maxRetries -gt 10))
                        {
                            Log ("[ERROR  ] maxTries is not an integer value in the range 1 - 10.")
                            Log ("[ERROR  ]`tExample: `"maxRetries`": 2")
                            Log ("[ERROR  ]`tDefaulting to 2.")
                            $Global:config.maxRetries = 2
                        }
                        else
                        {
                            # Nothing, $Global:config.maxRetries is fine
                        }
                    }
                }
                else
                {
                    Log ("[WARNING] maxTries value missing.  Defaulting to 2.")
                    Log ("[WARNING]`tExample: `"maxRetries`": 2")
                    $Global:config.maxRetries = 2
                }

                # Make sure there is a value for $Global:config.queueFolder
                if(-not [String]::IsNullOrEmpty($Global:config.queueFolder))
                {
                    # Test to see if the queueFolder is viable.
                    if(-not (Test-Path -Path $Global:config.queueFolder))
                    {
                        Log ("[ERROR  ] queueFolder ({0}) is not a viable folder to load queued statistics.", @($Global:config.queueFolder))

                        # Clear $Global:config.queueFolder to signifiy we have no viable load location.
                        $Global:config.queueFolder = [String]::Empty

                        $haveAllRequirements = $false
                    }
                    else
                    {
                        # Nothing, $Global:config.queueFolder is a viable folder to load queued statistics from
                        #   And potential to save stats to
                    }
                }
                else
                {
                    Log ("[ERROR  ] Missing value for queueFolder.")
                    Log ("[ERROR  ] `tExample: `"queueFolder`": `"E:\\DAStatsWork\\QueuedData`"")
                    Log ("[ERROR  ] `t`t'\' characters in .json files need to be escaped to '\\'")

                    $haveAllRequirements = $false
                }

                # Make sure there is a value for $Global:config.whereScapeFolder
                if(-not [String]::IsNullOrEmpty($Global:config.whereScapeFolder))
                {
                    # Test to see if the whereScapeFolder is viable.
                    if(-not (Test-Path -Path $Global:config.whereScapeFolder))
                    {
                        # If the whereScapeFolder is not viable, then make sure the queueFolder is viable
                        Log ("[WARNING] whereScapeFolder ({0}) is not a viable save location for statistics.", @($Global:config.whereScapeFolder))

                        # Already tested $Global:config.queueFolder, but is it viable?
                        if([String]::IsNullOrEmpty($Global:config.queueFolder))
                        {
                            Log ("[ERROR  ] Neither whereScapeFolder nor queueFolder is a viable save location for statistics.")

                            # Clear $Global:config.whereScapeFolder to signifiy we have no viable save location.
                            $Global:config.whereScapeFolder = [String]::Empty

                            $haveAllRequirements = $false
                        }
                        else
                        {
                            # Ok, whereScapeFolder is not viable, but queueFolder is, so change $Global:config.whereScapeFolder to match $Global:config.queueFolder and we'll just
                            #   save the stats and load them in the next run.

                            $Global:config.whereScapeFolder = $Global:config.queueFolder
                        }
                    }
                    else
                    {
                        # Nothing, $Global:config.whereScapeFolder is a viable save location
                    }

                    # If $Global:config.whereScapeFolder is not empty, then proceed
                    #   Rechecking this since it might have been set to [String]::Empty above to signal an error
                    if(-not [String]::IsNullOrEmpty($Global:config.whereScapeFolder))
                    {
                        if(-not [String]::IsNullOrEmpty($Global:config.standardStatsFile))
                        {
                            $standardStatDataSaveFile = "{0}\{1}{2}{3}" -f @($Global:config.whereScapeFolder, [System.IO.Path]::GetFileNameWithoutExtension($Global:config.standardStatsFile), $runtimeFileStamp, [System.IO.Path]::GetExtension($Global:config.standardStatsFile))

                            # Make sure $standardStatDataSaveFile is valid  NOTE:  -IsValid
                            if(-not (Test-Path -Path $standardStatDataSaveFile -IsValid))
                            {
                                Log ("[ERROR  ] Standard stats file ({0}) is not a viable save location for standard statistics" -f @($standardStatDataSaveFile))

                                $haveAllRequirements = $false
                            }
                        }
                        else
                        {
                            Log ("[ERROR  ] Missing value for standardStatsFile.")
                            Log ("[ERROR  ]`tExample: `"standardStatsFile`": `"daStats.csv`"")
                            $haveAllRequirements = $false
                        }

                        if(-not [String]::IsNullOrEmpty($Global:config.bandwidthStatsFile))
                        {
                            $bandwidthStatsDataSaveFile = "{0}\{1}{2}{3}" -f @($Global:config.whereScapeFolder, [System.IO.Path]::GetFileNameWithoutExtension($Global:config.bandwidthStatsFile), $runtimeFileStamp, [System.IO.Path]::GetExtension($Global:config.bandwidthStatsFile))
                            # Make sure $bandwidthStatsDataSaveFile is valid  NOTE:  -IsValid
                            if(-not (Test-Path -Path $bandwidthStatsDataSaveFile -IsValid))
                            {
                                Log ("[ERROR  ] Bandwidth stats file ({0}) is not a viable save location for bandwidth statistics" -f @($bandwidthStatsDataSaveFile))

                                $haveAllRequirements = $false
                            }
                        }
                        else
                        {
                            Log ("[ERROR  ] Missing value for bandwidthStatsFile.")
                            Log ("[ERROR  ]`tExample: `"bandwidthStatsFile`": `"daBandwidthStats.csv`"")

                            $haveAllRequirements = $false
                        }

                        if(-not [String]::IsNullOrEmpty($Global:config.bandwidthStatsFile))
                        {
                            $mergedStatsDataSaveFile = "{0}\{1}{2}{3}" -f @($Global:config.whereScapeFolder, [System.IO.Path]::GetFileNameWithoutExtension($Global:config.mergedStatsFile), $runtimeFileStamp, [System.IO.Path]::GetExtension($Global:config.mergedStatsFile))
                            # Make sure $mergedStatsDataSaveFile is valid  NOTE:  -IsValid
                            if(-not (Test-Path -Path $mergedStatsDataSaveFile -IsValid))
                            {
                                Log ("[ERROR  ] Merged stats file ({0}) is not a viable save location for statistics" -f @($mergedStatsDataSaveFile))

                                $haveAllRequirements = $false
                            }
                        }
                        else
                        {
                            Log ("[ERROR  ] Missing value for bandwidthStatsFile.")
                            Log ("[ERROR  ]`tExample: `"bandwidthStatsFile`": `"daBandwidthStats.csv`"")

                            $haveAllRequirements = $false
                        }
                    }
                    else
                    {
                        # Nothing, already logged an error about whereScapeFolder.
                    }
                }
                else
                {
                    Log ("[ERROR  ] Missing value for whereScapeFolder.")
                    Log ("[ERROR  ]`tExample: `"whereScapeFolder`": `"\\\\cdc-wherescape\\DA_Data`"")
                    Log ("[ERROR  ]`t`t'\' characters in .json files need to be escaped to '\\'")
                    $haveAllRequirements = $false
                }

                # Check to see if ToAddresses was defined in the configuration data
                if($null -eq $Global:config.ToAddresses)
                {
                    Log "[WARNING] Configuration data missing 'ToAddresses'."
                }
                else
                {
                    # Override the default recipients
                    if($Global:config.ToAddresses -isnot [Array])
                    {
                        $Global:AlertRecipients = @($Global:config.ToAddresses)
                    }
                    else
                    {
                        $Global:AlertRecipients = $Global:config.ToAddresses
                    }
                }

                foreach($recipient in $Global:AlertRecipients)
                {
                    Log ("[INFO   ] Alert email recipient: {0}" -f @($recipient))
                }

                # Check to see if SMTPServer was defined in the configuration data
                if([String]::IsNullOrEmpty($Global:config.SMTPServer))
                {
                    Log "[WARNING] Configuration data missing 'SMTPServer'"
                }
                else
                {
                    # Override the default SMTP server
                    $Global:SMTPServer = $Global:config.SMTPServer
                }
                Log ("[INFO   ] SMTP Relay: {0}" -f @($Global:SMTPServer))

                # Check to see if FromAddress was defined in the configuration data
                if([String]::IsNullOrEmpty($Global:config.FromAddress))
                {
                    Log "[WARNING] Configuration data missing 'FromAddress'."
                }
                else
                {
                    # Override the default sender address
                    $Global:SenderAddress = $Global:config.FromAddress
                }
                Log ("[INFO   ] Alert email From: {0}" -f @($Global:SenderAddress))

            }
            else
            {
                Log ("[ERROR  ] Unable to load script configuration data from {0}." -f @($JSONArgsFile))

                $haveAllRequirements = $false
            }
        }
        catch
        {
            Log ("[ERROR  ] 1Unable to read sites file: {0}" -f @($JSONArgsFile))
            $haveAllRequirements = $false
        }
    }
    else
    {
        Log ("[ERROR  ] 2Unable to read sites file: {0}" -f @($JSONArgsFile))
        $haveAllRequirements = $false
    }
}
else
{
    Log ("[ERROR  ] value for JSONArgsFile parameter is missing.")
    $haveAllRequirements = $false
}

if($haveAllRequirements)
{
    $Global:statsCollection = [StatsCollection]::new()
    $Global:allStats = @()
    $Global:bandwidthStats = @()

    $Global:netScalers = @()

    # Establish the reporting start and end date/time
    $endTime = [Datetime]::now
    $startTime = $endTime.AddHours(-1)

    if(-not $Global:doDebug)
    {
        # Clean up the log file
        $logRetentionDate = [DateTime]::Now.AddDays(-14).ToString("yyyyMMdd HH:mm:ss")
        try
        {
            $logData = Get-Content -Path $Global:config.logFile -ErrorAction Stop
            $logData = $logData | Sort-Object | Where-Object { $_ -ge $logRetentionDate }
            $logData | Out-File -LiteralPath $Global:config.logFile -Encoding ascii -ErrorAction Stop
        }
        catch
        {
            # Nothing... just trying to clean up the log file.
        }
    }

    if(-not $Global:doDebug)
    {
        # If there are any queue files in the queue folder, load them...
        $Global:allStats, $Global:bandwidthStats, $Global:statsCollection = LoadQueuedData $Global:config.queueFolder $Global:config.standardStatsFile $Global:config.bandwidthStatsFile $Global:config.mergedStatsFile
        Log ("[INFO   ] Loaded {0} standard stats, {1} bandwidth stats, and {2} merged stats from {3}." -f @($Global:allStats.Length, $Global:bandwidthStats.Length, $Global:statsCollection.stats.Count, $Global:config.queueFolder))
    }

    # First, collect DirectAccess and AlwaysOnVPN statistics for all sites...
    $a = 0
    while($a -lt $Global:config.Sites.Length)
    {
        GetSiteRemoteAccessStats $Global:config.Sites[$a].Name $Global:config.Sites[$a].SiteCode $Global:config.Sites[$a].VPNServers $startTime $endTime

        # If the site has any NetScalers, add them to the array of NetScalers...
        if(($null -ne $Global:config.Sites[$a].NetScaler) -and ($null -ne $Global:config.Sites[$a].NetScaler.Devices) -and ($null -ne $Global:config.Sites[$a].NetScaler.Gateways))
        {
            $netScalers += @{ServerName="NetScaler"; Location=$Global:config.Sites[$a].Name; Devices=$Global:config.Sites[$a].NetScaler.Devices; Gateways=$Global:config.Sites[$a].NetScaler.Gateways}
        }

        $a++
    }

    # If any NetScalers were included in the sites file, then collect NetScaler statistics...
    if($netScalers.Length -gt 0)
    {
        # Collect NetScaler collection stats...
        Log ("[INFO   ] Collecting NetScalers connection data...")

        $netScalerCollectionStats = Get-NetScalerConnectionStats $startTime $endTime
        $Global:allStats += $netScalerCollectionStats

        # Collect NetScaler bandwidth stats...
        Log ("[INFO   ] Collecting NetScalers bandwidth data...")

        $netScalerBandwidthStats = Get-NetScalerBandwidthStats $startTime $endTime

        # New
        Get-NetScalerBandwidthStats2 $startTime $endTime

        if($null -ne $netScalerBandwidthStats)
        {
            foreach($stat in $netScalerBandwidthStats)
            {
                $Global:bandwidthStats += $stat
            }
        }
    }

    # Finally, save all the collected data...

    if(-not $Global:doDebug)
    {
        # Remove any existing .bak files from the queue folder...
        Remove-Item -Path ("{0}\*.bak" -f @($Global:config.queueFolder)) -Force

        # Rename all the .csv files in the queue folder to .bak
        Get-ChildItem -Path ("{0}\*.csv" -f $Global:config.queueFolder) | ForEach-Object { $_ | Rename-Item -NewName ($_.Name -replace '.csv','.bak') -Force }

        # Export the standard stats to whatever save path we need to use
        Log ("[INFO   ] Saving {0} standard stats to {1}." -f @($Global:allStats.Length, $standardStatDataSaveFile))
        try
        {
            $Global:allStats | Export-Csv -Path $standardStatDataSaveFile -NoTypeInformation -Delimiter "," -Force -ErrorAction Stop
        }
        catch
        {
            Log ("[ERROR  ] Could not save standard stats to {0}." -f @($standardStatDataSaveFile))
        }

        # Just double check for the standard stats data file.
        if(-not (Test-Path $standardStatDataSaveFile))
        {
            Log ("[ERROR  ] Standard stats {0} not found." -f @($standardStatDataSaveFile))
        }

        # Export the bandwidth stats to whatever save path we need to use
        Log ("[INFO   ] Saving {0} bandwidth stats to {1}." -f @($Global:bandwidthStats.Length, $bandwidthStatsDataSaveFile))
        try
        {
            $Global:bandwidthStats | Export-Csv -Path $bandwidthStatsDataSaveFile -NoTypeInformation -Delimiter "," -Force -ErrorAction Stop
        }
        catch
        {
            Log ("[ERROR  ] Could not save bandwidth stats to {0}." -f @($bandwidthStatsDataSaveFile))
        }

        # Just double check for the bandwidth stats data file.
        if(-not (Test-Path $bandwidthStatsDataSaveFile))
        {
            Log ("[ERROR  ] Bandwidth stats {0} not found." -f @($bandwidthStatsDataSaveFile))
        }

        # Export the stats collection to whatever save path we need to use
        Log ("[INFO   ] Saving {0} merged stats to {1}." -f @($Global:statsCollection.stats.Count, $mergedStatsDataSaveFile))
        try
        {
            $Global:statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | Export-CSV -Path $mergedStatsDataSaveFile -Delimiter "," -NoTypeInformation -ErrorAction Stop
        }
        catch
        {
            Log ("[ERROR  ] Could not save merged stats to {0}." -f @($mergedStatsDataSaveFile))
        }

        # Just double check for the bandwidth stats data file.
        if(-not (Test-Path $mergedStatsDataSaveFile))
        {
            Log ("[ERROR  ] Merged stats {0} not found." -f @($mergedStatsDataSaveFile))
        }
    }
}
else
{
    # Nothing, already logged the appropriate errors.
}

if($Global:sbErrorLog.Length -gt 0)
{
    # Email the error log...
    $emailBody = $Global:sbErrorLog.ToString()
	$sendTo = $Global:AlertRecipients -join ","
	$subject = "{0}: Trouble with Remote Access stats collector" -f @([DateTime]::Now.ToString("yyyy-MM-dd HH:mm"))

	try
	{
		$smtp = [System.Net.Mail.SmtpClient]::new($Global:SMTPServer)
		$emailMessage = [System.Net.Mail.MailMessage]::new($Global:SenderAddress, $sendTo, $subject, $emailBody)
		$smtp.send($emailMessage)
#		Send-MailMessage -From $Global:SenderAddress -To $Global:AlertRecipients -Subject ("{0}: Trouble with Remote Access stats collector" -f @([DateTime]::Now.ToString("yyyy-MM-dd HH:mm"))) -Body $emailBody -SmtpServer $Global:SMTPServer -ErrorAction Stop
		Log ("[INFO   ] Email alert sent to: {0}." -f @($Global:AlertRecipients -join ", "))
	}
	catch
	{
		Log ("[ERROR  ] Failed to send email alert sent to: {0}." -f @($Global:AlertRecipients -join ", "))
	}
}

<#
$allStats | ConvertTo-Csv -NoTypeInformation -Delimiter "," | Set-Clipboard
$bandwidthStats | ConvertTo-Csv -NoTypeInformation -Delimiter ","  | Set-Clipboard
$statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | ConvertTo-CSV -Delimiter "," -NoTypeInformation | Set-Clipboard
#>
