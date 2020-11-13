
Import-Module RemoteAccess
$endTime = [Datetime]::now
$startTime = $endTime.AddHours(-1)
$stats = Get-RemoteAccessConnectionStatistics -ComputerName BDCZ-DA01 -StartDateTime $startTime -EndDateTime $endTime

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

$myStats = [System.Collections.Generic.List[MyDAStatistic]]::new()
foreach($s in $stats)
{
    $myStat = [MyDAStatistic]::new("BDCZ-DA01", $s)
    $myStats.Add($myStat)
}

$totalBytesPerSecond_In = ($myStats | Measure-Object -Property BytesPerSecond_In -Sum).Sum
$totalBytesPerSecond_Out = ($myStats | Measure-Object -Property BytesPerSecond_Out -Sum).Sum
