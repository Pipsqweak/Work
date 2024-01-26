$start = [DateTime]::now.AddDays(-30).ToString("M/dd/yyyy")
$finish = [DateTime]::now.ToString("M/dd/yyyy")
Get-Stat -Entity $vmHost -Stat "mem.granted.average" -Start $start -Finish $finish
$memAvg =Get-Stat -Entity $vmHost -Stat "mem.granted.average" -Start $start -Finish $finish
$memAvg
Get-StatType
Get-StatType -Entity $vmHost
Get-StatType -Entity $vmHost | Sort-Object
$memAvg =Get-Stat -Entity $vmHost -Stat "mem.granted.average" -Start $start -Finish $finish -IntervalMins *
$memAvg | OGV
$memStats =Get-Stat -Entity $vmHost -Stat "mem.granted.average","mem.totalCapacity.average" -Start $start -Finish $finish -IntervalMins *
$memStats | OGV
$memStats =Get-Stat -Entity $vmHost -Stat "mem.active.average","mem.totalCapacity.average" -Start $start -Finish $finish -IntervalMins *
$start = [DateTime]::now.adddays(-30).ToString("M/dd/yyyy")$finish = [DateTime]::now.ToString("M/dd/yyyy"); $memStats =Get-Stat -Entity $vmHost -Stat "mem.active.average","mem.totalCapacity.average","mem.cons...
$start = [DateTime]::now.adddays(-30).ToString("M/dd/yyyy");$finish = [DateTime]::now.ToString("M/dd/yyyy"); $memStats =Get-Stat -Entity $vmHost -Stat "mem.active.average","mem.totalCapacity.average","mem.con...
$memStatTypes = Get-StatType -Entity (Get-Cluster -VMHost $vmHost)
$memStatTypes
$memStats | oGV

# CDC
$cluster = Get-Cluster -Server $vCenter -Name "CDC-INT-CLUSTER-01"
$clusterHosts = Get-VMHost -Server $vCenter -Location $cluster

#  DDC
$cluster = Get-Cluster -Server $vCenter -Name "DDC-INT-CLUSTER-01"
$clusterHosts = Get-VMHost -Server $vCenter -Location $cluster

# Common

$start = [DateTime]::now.adddays(-30).ToString("M/dd/yyyy")
$finish = [DateTime]::now.ToString("M/dd/yyyy")

$memStats = Get-Stat -Entity $cluster -Stat "mem.consumed.average" -Start $start -Finish $finish -IntervalMins *
$memStats | Measure-Object -Maximum -Minimum -Average -Property Value

$maxMemConsumed = (($memStats | Measure-Object -Maximum -Property Value).Maximum * 1KB) / 1TB
$totalMem = (($clusterHosts | Measure-Object -Property MemoryTotalGB -Sum).Sum * 1GB) / 1TB
$excessMem = $totalMem - $maxMemConsumed
($maxMemConsumed / $totalMem) * 100
($excessMem / $totalMem) * 100


$cpuStats = Get-Stat -Entity $cluster -Stat "cpu.usagemhz.average" -Start $start -Finish $finish -IntervalMins *
$cpuStats | Measure-Object -Maximum -Minimum -Average -Property Value
$maxMHzConsumed = ($cpuStats | Measure-Object -Maximum -Property Value).Maximum
$totalMHz = ($clusterHosts | Measure-Object -Property CpuTotalMhz -Sum).Sum
$excessMHz = $totalMHz - $maxMHzConsumed
($maxMHzConsumed / $totalMHz) * 100
($excessMHz / $totalMHz) * 100

$maxMHzConsumed.ToString("N0") | Set-Clipboard
$excessMHz.ToString("N0") | Set-Clipboard
$totalMHz.ToString("N0") | Set-Clipboard
