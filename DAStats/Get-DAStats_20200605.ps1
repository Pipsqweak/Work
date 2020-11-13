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

$Global:statsCollection = [StatsCollection]::new()

$whereScapeFolder = "\\cdc-wherescape\DA_Data"
$standardStatsFile = "{0}\daStats.csv" -f @($whereScapeFolder)
$bandwidthStatsFile = "{0}\daBandwidthStats.csv" -f @($whereScapeFolder)
$mergedStatsFile = "{0}\daMergedStats.csv" -f @($whereScapeFolder)

$allStats = @()
$logFile = "E:\DAStatsWork\Logs\DAStats.Log"

$endTime = [Datetime]::now
$startTime = $endTime.AddHours(-1)

$newStatsFile = "E:\DAStatsWork\mergedDAStats_{0}.csv" -f @($startTime.ToString("yyyyMMdd_HHmm"))


$bandwidthStats = @()

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

# If the bandwidth stats file is still there, import it and combine the new stats with it.
if([System.IO.File]::Exists($bandwidthStatsFile))
{
    $bandwidthStats = Import-Csv -Path $bandwidthStatsFile
}

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

# Export the standard stats to the WhereScape server.
$allStats | Export-Csv -Path $standardStatsFile -NoTypeInformation -Delimiter "," -Force

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

# Export the bandwidth stats to the WhereScape Server.
$bandwidthStats | Export-Csv -Path $bandwidthStatsFile -NoTypeInformation -Delimiter "," -Force

$statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | Export-CSV -Path $mergedStatsFile -Delimiter "," -NoTypeInformation
$statsCollection.stats | Sort-Object DateTime,Location,ServerName | Select-Object DateTime,Location,ServerName,ActiveConnections,Mbps_In,Mbps_out,Total_Mbps,GBph_In,GBph_Out,Total_GBph | Export-CSV -Path $newStatsFile -Delimiter "," -NoTypeInformation

