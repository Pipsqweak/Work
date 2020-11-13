Import-Module RemoteAccess

class MyDAStatistic
{
    [String] $AuthMethod
    [String] $ConnectionType
    [String] $HostName
    [String] $TransitionTechnology
    [String] $TunnelType
    [String] $UserName
    [String] $DAServerName

    [UInt32] $ConnectionDuration
    [UInt64] $TotalBytesIn
    [UInt64] $TotalBytesOut
    [UInt64] $SessionId

    [DateTime] $ConnectionStartTime
    [DateTime] $ConnectionEndTime

    [Decimal] $BytesPerSecond_In
    [Decimal] $BytesPerSecond_Out

    [System.Net.IPAddress] $ClientExternalAddress
    [System.Net.IPAddress[]] $ClientIPAddress
    [System.Net.IPAddress] $ClientIPv4Address
    [System.Net.IPAddress] $ClientIPv6Address

    MyDAStatistic([String] $daServerName, [Object] $stat)
    {
        $this.AuthMethod = $stat.AuthMethod
        $this.ConnectionType = $stat.ConnectionType
        $this.HostName = $stat.HostName
        $this.TransitionTechnology = $stat.TransitionTechnology
        $this.TunnelType = $stat.TunnelType
        $this.UserName = $stat.UserName
        $this.DAServerName = $daServerName

        $this.ConnectionDuration = $stat.ConnectionDuration
        $this.TotalBytesIn = $stat.TotalBytesIn
        $this.TotalBytesOut = $stat.TotalBytesOut
        $this.SessionId = $stat.SessionId

        $this.ConnectionStartTime = $stat.ConnectionStartTime
        $this.ConnectionEndTime = $stat.ConnectionStartTime.AddSeconds($stat.ConnectionDuration)

        if($this.ConnectionDuration -gt 0)
        {
            $this.BytesPerSecond_In = ($this.TotalBytesIn / $this.ConnectionDuration)
            $this.BytesPerSecond_Out = ($this.TotalBytesOut / $this.ConnectionDuration)
        }

        $this.ClientExternalAddress = $stat.ClientExternalAddress
        $this.ClientIPAddress = $stat.ClientIPAddress
        $this.ClientIPv4Address = $stat.ClientIPv4Address
        $this.ClientIPv6Address = $stat.ClientIPv6Address
    }
}

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
        $this.Total_Mbps = $this.Mbps_In + $this.Mbps_Out
        $this.DateTime = $dt.ToString("yyyy-MM-dd HH:mm")
    }

    [void] UpdateBandwidthStats([Double] $bpsIn, [Double] $bpsOut)
    {
        $this.GBph_In = (($bpsIn * 3600) / 1073741824)
        $this.GBph_Out = (($bpsOut * 3600) / 1073741824)
        $this.Total_GBph = $this.GBph_In + $this.GBph_Out

        $this.Mbps_In = (($bpsIn * 8) / 1048576)
        $this.Mbps_Out = (($bpsOut * 8) / 1048576)
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


# So we can ignore the cert from NetScaler...
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

function Log($message)
{
    ("{0} : {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HH:mm:ss"), $message)) | Out-File -FilePath $Global:logFile -Append
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
    $uri = "https://cdc-nsvpxmas01.powereng.com/nitro/v1/config/perf_ssl_vpn_report?filter=device_ip_address:/10.245.69.20|10.245.69.20|10.247.69.20|10.247.69.101/,report_start_time:{0},report_end_time:{1},vsvrName:/connecteast.powereng.com_sslvpn|vdi.powereng.com_ssl|connectwest.powereng.com_sslvpn|connectwest-poc.powereng.com_sslvpn/&pagesize=5000" -f @(([System.DateTimeOffset]::Parse($startTime)).ToUnixTimeSeconds(), ([System.DateTimeOffset]::Parse($endTime)).ToUnixTimeSeconds())
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
    }

    $inFile = "{0}\\{1}" -f @($qFolder, $bwStatsFile)
    if([System.IO.File]::Exists($inFile))
    {
        $bStats = Import-CSV -Path $inFile
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
    }

    return @($aStats, $bStats, $sc)
}

$queueFolder = "E:\DAStatsWork\QueuedData"
$whereScapeFolder = "\\cdc-wherescape\DA_Data"
$standardStatsFile = "daStats.csv"
$bandwidthStatsFile = "daBandwidthStats.csv"
$mergedStatsFile = "daMergedStats.csv"

$Global:statsCollection = [StatsCollection]::new()
$allStats = @()
$bandwidthStats = @()

# If there are any queue files in the queue folder, load them...
$allStats, $bandwidthStats, $statsCollection = LoadQueuedData $queueFolder $standardStatsFile $bandwidthStatsFile $mergedStatsFile

$logFile = "E:\DAStatsWork\Logs\DAStats.Log"

$endTime = [Datetime]::now
$startTime = $endTime.AddHours(-1)

$newStatsFile = "E:\DAStatsWork\mergedDAStats_{0}.csv" -f @($startTime.ToString("yyyyMMdd_HHmm"))

# Collect stats from the different DA servers
$daSites = @(
    @{SiteCode="ADC"; Location="Calgary" },
    @{SiteCode="AST"; Location="Austin" },
    @{SiteCode="BDC"; Location="Denver" },
    @{SiteCode="BOI"; Location="Boise"},
    @{SiteCode="CDC"; Location="Chicago" },
    @{SiteCode="FMC"; Location="Fort Mill" },
    @{SiteCode="FTW"; Location="Fort Worth" },
    @{SiteCode="OPK"; Location="Overland Park" },
    @{SiteCode="ORA"; Location="Oradell" },
    @{SiteCode="STL"; Location="St Louis" }
)

$Global:netScalers = @(
    @{ServerName="NetScaler"; Location="Chicago"; Devices=@("10.247.69.20","10.247.69.101"); Gateways=@("connecteast.powereng.com_sslvpn","vdi.powereng.com_ssl","citrix.powereng.com_ssl")},
    @{ServerName="NetScaler"; Location="Denver"; Devices=@("10.245.69.20"); Gateways=@("connectwest.powereng.com_sslvpn","citrix-test.powereng.com_ssl","connectwest-poc.powereng.com_sslvpn")}
)

$a = 0
while($a -lt $daSites.Length)
{
    $totalBytesPerSecond_In = 0
    $totalBytesPerSecond_Out = 0

    for($b = 1; $b -le 2; $b++)
    {
        $daServerName = "{0}Z-DA0{1}" -f @($daSites[$a].SiteCode, $b)

        # New
        $stat = $Global:statsCollection.GetLocationStat($Global:daSites[$a].Location, $daServerName, $endTime)


        Log ("Checking {0}..." -f @($daServerName))
        $Error.Clear()

        # First get statistics for the standard stats data
        $stats = $null
        $stats = Get-RemoteAccessConnectionStatistics -ComputerName $daServerName -ErrorAction SilentlyContinue
        $activeConnections = 0
        $totalBytesIn = 0
        $totalBytesOut = 0

        if($null -ne $stats)
        {
            $activeConnections = $stats.Length
            $totalBytesIn = ($stats | Measure-Object -Sum -Property TotalBytesIn).Sum
            $totalBytesOut = ($stats | Measure-Object -Sum -Property TotalBytesOut).Sum

            if($null -ne $stat)
            {
                $stat.ActiveConnections = $stats.Length
            }
        }
        else
        {
            Log ("Could not extract connection statistics from {0}" -f @($daServerName))
            $Error | ForEach-Object { Log ("ERROR : {0}" -f @($_.ToString())) }
            $Error.Clear()
        }

        $newStat = [ConnectionStat]::new($endTime, $daServerName, $daSites[$a].Location, $activeConnections, $totalBytesIn, $totalBytesOut)
        $allStats += $newStat

        # Next pull statistics for the bandwidth data.  In the future, I might try to reuse the same data, but for now, I'll pull new stats.
        #    Prior to inbox accounting being enabled, I could only get a point in time set of statistics.  With inbox accounting enabled, I can get
        #    statistics that also include sessions that where not connected at the time the statistics were pulled.
        $stats = $null
        Log ("Pulling bandwidth statistics from {0}..." -f @($daServerName))
        $stats = Get-RemoteAccessConnectionStatistics -ComputerName $daServerName -StartDateTime $startTime -EndDateTime $endTime -ErrorAction SilentlyContinue
        if($null -ne $stats)
        {
            Log ("`tProcessing {0} statistics..." -f @($stats.Length))
            foreach($s in $stats)
            {
                $myStat = [MyDAStatistic]::new($daServerName, $s)
                $totalBytesPerSecond_In += $myStat.BytesPerSecond_In
                $totalBytesPerSecond_Out += $myStat.BytesPerSecond_Out
            }

            if($null -ne $stat)
            {
                $stat.UpdateBandwidthStats($totalBytesPerSecond_In, $totalBytesPerSecond_Out)
            }

        }
        else
        {
            Log ("Could not extract bandwidth statistics from {0}" -f @($daServerName))
            $Error | ForEach-Object { Log ("ERROR : {0}" -f @($_.ToString())) }
            $Error.Clear()
        }
    }

    $siteBandwidthStats = [BandwidthStat]::new($startTime, $endTime, $daSites[$a].Location,  $totalBytesPerSecond_In,  $totalBytesPerSecond_Out)
    $bandwidthStats += $siteBandwidthStats

    $a++
}

# Ignore certificate issues when collecting NetScaler data...
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12

# Collect NetScaler collection stats...
Log ("Collecting NetScalers connection data...")

$netScalerCollectionStats = Get-NetScalerConnectionStats $startTime $endTime
$allStats += $netScalerCollectionStats

# Collect NetScaler bandwidth stats...
Log ("Collecting NetScalers bandwidth data...")

$netScalerBandwidthStats = Get-NetScalerBandwidthStats $startTime $endTime

# New
Get-NetScalerBandwidthStats2 $startTime $endTime

if($null -ne $netScalerBandwidthStats)
{
    foreach($stat in $netScalerBandwidthStats)
    {
        $bandwidthStats += $stat
    }
}

# Save all the collected data...

# Remove any existing .bak files from the queue folder...
Remove-Item -Path ("{0}\*.bak" -f @($queueFolder))

# Rename all the .csv files in the queue folder to .bak
Get-ChildItem -Path ("{0}\*.csv" -f $queueFolder) | Rename-Item -NewName { $_.Name -replace '.csv','.bak' }

# This is extra... saved because... I want to :P
$statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | Export-CSV -Path $newStatsFile -Delimiter "," -NoTypeInformation

if(Test-Path -Path $whereScapeFolder)
{
    # If we can access the WhereScape server, then save the files to it...

    # Ok, we don't have to do anything, the file names are created using the $whereScapeFolder variable... so if we can't get to that folder,
    #    just set $whereScapeFolder to $queueFolder and then the data file names will use the queue folder instead... tricky....
}
else
{
    # Tricky, tricky... just substitute the queue folder for the WhereScape folder...
    $whereScapeFolder = $queueFolder
}

$standardStatDataSaveFile = "{0}\{1}" -f @($whereScapeFolder, $standardStatsFile)
$bandwidthStatsDataSaveFile = "{0}\{1}" -f @($whereScapeFolder, $bandwidthStatsFile)
$mergedStatsDataSaveFile  = "{0}\{1}" -f @($whereScapeFolder, $mergedStatsFile)

# Export the standard stats to whatever save path we need to use
$allStats | Export-Csv -Path $standardStatDataSaveFile -NoTypeInformation -Delimiter "," -Force

# Export the bandwidth stats to whatever save path we need to use
$bandwidthStats | Export-Csv -Path $bandwidthStatsDataSaveFile -NoTypeInformation -Delimiter "," -Force

# Export the stats collection to whatever save path we need to use
$statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | Export-CSV -Path $mergedStatsDataSaveFile -Delimiter "," -NoTypeInformation

# SIG # Begin signature block
# MIIPMgYJKoZIhvcNAQcCoIIPIzCCDx8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUXwGa1LEVHvksxxvvPf3G/7F
# i++gggyXMIIF3zCCBMegAwIBAgITFQAAAALU9Lz04Hi9mwAAAAAAAjANBgkqhkiG
# 9w0BAQ0FADBGMRMwEQYKCZImiZPyLGQBGRYDY29tMRgwFgYKCZImiZPyLGQBGRYI
# cG93ZXJlbmcxFTATBgNVBAMTDFBFSSBSb290IENBMjAeFw0xNTA4MTIyMDQ2MDVa
# Fw0zNTA4MTIyMDA4MDVaME0xEzARBgoJkiaJk/IsZAEZFgNjb20xGDAWBgoJkiaJ
# k/IsZAEZFghwb3dlcmVuZzEcMBoGA1UEAxMTUEVJIFN1Ym9yZGluYXRlIENBMjCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKVLzra7Ww5Nmy+NM14MdRZW
# wEhw09fhAIC6jDl90IGt1D0zvB9xrM1XTrSfEWgCNnveOnNSvXBSHjfWYd7KAs8N
# EDLyIjWluCB66bdi/xY2fascuYJvy2ZmA6Voh005/nRS7lPGq6yfZEjc6LXfiaHS
# Wo+kbrFw/ICoq79kEIympaHeO7TYFOcHoP7T/nfWvD0OrJZLrou9m53qQzZXduBV
# pYwfI91CsGR1DpXKwcgC4yPqLdaP9GmWjYYddT6jQTGD/aCIfYo/29z2vXVafaHx
# 90i8OIF7frlhOL39P3GhxIlDk7espdSKxHWF6772N0XXc7NVaq+Jdw7vtpG02yMC
# AwEAAaOCAr0wggK5MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBQFk+663K25
# Xljs+Tik5+qrsUUojTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8E
# BAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBSwdElPGrGwpa46Uu+0
# SWDcXSTY9TCCAQ8GA1UdHwSCAQYwggECMIH/oIH8oIH5hoG6bGRhcDovLy9DTj1Q
# RUklMjBSb290JTIwQ0EyLENOPUJPSS1SQ0EwMixDTj1DRFAsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1w
# b3dlcmVuZyxEQz1jb20/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29i
# amVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50hjpodHRwOi8vY2VydHMyLnBv
# d2VyZW5nLmNvbS9DZXJ0RW5yb2xsL1BFSSUyMFJvb3QlMjBDQTIuY3JsMIIBFwYI
# KwYBBQUHAQEEggEJMIIBBTCBsAYIKwYBBQUHMAKGgaNsZGFwOi8vL0NOPVBFSSUy
# MFJvb3QlMjBDQTIsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENO
# PVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9cG93ZXJlbmcsREM9Y29tP2NB
# Q2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9y
# aXR5MFAGCCsGAQUFBzAChkRodHRwOi8vY2VydHMyLnBvd2VyZW5nLmNvbS9DZXJ0
# RW5yb2xsL0JPSS1SQ0EwMl9QRUklMjBSb290JTIwQ0EyLmNydDANBgkqhkiG9w0B
# AQ0FAAOCAQEAcpv1ZhjtPnt9puHEI7ex1y8Y5l9KFw9/H0d05h104MDMGuD07HDG
# lQfgvSrmghZP86z2WsssNFbUisjr+aQlCtK8kTdfO/lf3agg/GJBPnzqxiJxIlb9
# Y1v0JT4gJf9sZMsXNiiYwatYGecK8DR2UbWDFUMjcIF7MaECWNedh/aWMb4cah2i
# sNP7FbCftZmP4LJ5VynBGTHb3P6DxYG2YzRxpSFeIlDP1aAABoFuKDGIK72izBG2
# QyeB1W2e7/sjFRiSLbyw2GuSuzHm0o4w3PkHQ0H1yiv50jiX02Sl30J/uP4bNAQF
# kC2U3Ov3RefYTwqj4uLKMmkNEqmpxLoySDCCBrAwggWYoAMCAQICE2YAABLaelh+
# 7dzdJlYAAAAAEtowDQYJKoZIhvcNAQENBQAwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyMB4XDTE2MDMyNDEzNTQzOVoXDTI2MDMyMjEzNTQzOVowgbAxCzAJ
# BgNVBAYTAlVTMQ4wDAYDVQQIEwVJZGFobzEPMA0GA1UEBxMGSGFpbGV5MR0wGwYD
# VQQKExRQT1dFUiBFbmdpbmVlcnMgSW5jLjEWMBQGA1UECxMNT3BlcmF0aW9ucyBJ
# VDFJMEcGA1UEAxNAUE9XRVIgRW5naW5lZXJzIEluZm9ybWF0aW9uIFRlY2hub2xv
# Z3kgSW5mcmFzdHJ1Y3R1cmUgRGVwYXJ0bWVudDCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBANo3WBVO5y8uBMYMzLPqdqDkyMcQoJVQR7yPHPKOh/0DeNoZ
# yVM0qXwdV6sZGaotW0+UR2DzyyMvmwxl5zqIIBEvIwjtHFLU/tAEOWamTf9vMwn+
# LxbUVysZ/RCKkv+V56dOnhtYE3vg+NxRBfEZKViQMXHq6FbmpL1LZcDKlYq1t3RO
# gYhbEHYjG5tEJftg11rznA379+K9yWkybUYEEVCavYNQGp/WHlroK9jMg8RtXIaQ
# pI7O/5CLFondPga3eqEU6fjbE3uDsY2ex7Q1+YnjFhvKt7GkosZo+1yWPeykOPra
# TGxqnig+7c8hKHO+ibV9/xfX8q/iWzlLAPQhMZUCAwEAAaOCAyMwggMfMD4GCSsG
# AQQBgjcVBwQxMC8GJysGAQQBgjcVCIHNilODqvxmhZmNOoHT7HuB1rU5gSGC5vp+
# hMywSwIBZAIBCjATBgNVHSUEDDAKBggrBgEFBQcDAzALBgNVHQ8EBAMCB4AwGwYJ
# KwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUY/0hsMlcQdPeIB7Z
# eh3nuq3RuZ8wHwYDVR0jBBgwFoAUBZPuutytuV5Y7Pk4pOfqq7FFKI0wggEjBgNV
# HR8EggEaMIIBFjCCARKgggEOoIIBCoaBwWxkYXA6Ly8vQ049UEVJJTIwU3Vib3Jk
# aW5hdGUlMjBDQTIsQ049Qk9JLVNDQTAyLENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0
# Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGRGh0dHA6Ly9CT0ktU0NBMDIucG93
# ZXJlbmcuY29tL0NlcnRFbnJvbGwvUEVJJTIwU3Vib3JkaW5hdGUlMjBDQTIuY3Js
# MIIBNQYIKwYBBQUHAQEEggEnMIIBIzCBtwYIKwYBBQUHMAKGgapsZGFwOi8vL0NO
# PVBFSSUyMFN1Ym9yZGluYXRlJTIwQ0EyLENOPUFJQSxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jQUNlcnRpZmljYXRlP2Jhc2U/b2JqZWN0Q2xhc3M9Y2VydGlm
# aWNhdGlvbkF1dGhvcml0eTBnBggrBgEFBQcwAoZbaHR0cDovL0JPSS1TQ0EwMi5w
# b3dlcmVuZy5jb20vQ2VydEVucm9sbC9CT0ktU0NBMDIucG93ZXJlbmcuY29tX1BF
# SSUyMFN1Ym9yZGluYXRlJTIwQ0EyLmNydDANBgkqhkiG9w0BAQ0FAAOCAQEAcMQQ
# HArQMPorMDdTv0PIeU80NpxlZm6ZjMLHJIWtyKWNRmuG1Oc+Ti762snW05yq5aEY
# kwmmWtm/00ukV4z/DhYrlCuxbmKeQP4kIZoVo4/7K7HrdG0u6QN4SmG9rTJGCuXz
# EXlKZIeHiwgD2EsNa7varVK3jX8CEik1jJh8II0VIbBzvetAMm1QGUCk9/WtllYG
# 76CLyPasgcfFsOlMeRWoHKNw/oV4AvMab0yuQCDJ9uNG3dU+6jGoxDz+ksAKl9OO
# u+zBNs+EOR/TWBD0JfE9hdChCzrbyG6JPIQdOsBoqo822QoIGc8emp4MTeDnCTTh
# ojIQLkYA7bMGDxIxHjGCAgUwggIBAgEBMGQwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyAhNmAAAS2npYfu3c3SZWAAAAABLaMAkGBSsOAwIaBQCgeDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRs
# WatSd5itknYPTBalOwG//1YNPzANBgkqhkiG9w0BAQEFAASCAQCev35mn/yK7wBe
# KdOLUJAWGg/3VXAvBcAGaBTnWQtWR9abQaOAp4X7uugUohDtbRvDkuGG3r97P6s/
# PWEUhgSdnqBo8k6n9ZpyWASUmH72Hehp1THpk0wGPfXvfN5vJCAw4mricGrDmBOI
# b0kutmbC0lLKfbLVdYZXG2A8EoVOqo9S6UehNwmQRgF4bfxCkUSi+L6XeTmOcvb1
# 1Dt9WWRXz7zsfMLRVtnzQtwp5ge8duDBIjY3YvO6Lv9iKxzmscaJWCTq0QvGuvLJ
# dGpeP2ZHVqe/rLHtpL0NhzJPxyzTzqwBGmOqzzBOn+m2ySd3qoWs1oIkZ8rz5Fv3
# 7xD0yDO0
# SIG # End signature block
