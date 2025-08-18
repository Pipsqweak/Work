$endTime = [DateTime]::Now()
$startTime = $endTime.AddMonths(-3)

$vmHostStats = [System.Collections.Generic.List[System.Object]]::new()
$vmHosts = @(Get-VMHost -Server $vCenter | Sort-Object Name)
$a = 0
while($a -lt $vmHosts.Length)
{
    Write-Host ("Getting stats for {0}..." -f @($vmHosts[$a].Name))
    $cpuStats = @(Get-Stat -Entity $vmHosts[$a] -Stat cpu.usage.average -Start $startTime -Finish $endTime -IntervalMins 1440 -Instance ([String]::Empty) | Sort-Object Timestamp)
    $b = 0
    while($b -lt $cpuStats.Length)
    {
        $d = "" | Select-Object Host,Timestamp,Value
        $d.Host = $vmHosts[$a].Name
        $d.Timestamp = $cpuStats[$b].Timestamp
        $d.Value = $cpuStats[$b].Value

        $vmHostStats.Add($d)
        $b++
    }
    $a++
}



$vmHostStats2 = [System.Collections.Generic.List[System.Object]]::new()
$uniqueTimestamps = @($vmHostStats | Select-Object -Unique -ExpandProperty Timestamp | Sort-Object)

$a = 0
while($a -lt $vmHosts.Length)
{
    $cpuStats = @($vmHostStats | Where-Object { $_.Host -eq $vmHosts[$a].Name } | Sort-Object Timestamp)
    $d = "" | Select-Object Host
    $d.Host = $vmHosts[$a].Name
    $b = 0
    while($b -lt $uniqueTimestamps.Length)
    {
        $v = $cpuStats | Where-Object { $_.Timestamp -eq $uniqueTimestamps[$b] }
        $val = 0.0
        if($null -ne $v)
        {
            $val = $v.Value
        }
        $d | Add-Member -Name $uniqueTimestamps[$b].ToString("yyyy-MM-dd") -Value $val -MemberType NoteProperty

        $b++
    }
    $vmHostStats2.Add($d)

    $a++
}
