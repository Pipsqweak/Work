ConnectTo vCenter,prod

# CDC
# $cluster = Get-Cluster -Server $vCenter -Name "CDC-INT-CLUSTER-01"

#  DDC
# $cluster = Get-Cluster -Server $vCenter -Name "DDC-INT-CLUSTER-01"

# Common
# $dtNow = [DateTime]::Now
# $start = $dtNow.adddays(-1).ToString("M/dd/yyyy HH:mm:ss")
# $finish = $dtNow.ToString("M/dd/yyyy  HH:mm:ss")
# $statAverages = [System.Collections.Generic.List[System.Object]]::new()

$dtNow = [DateTime]::Now
$start = $dtNow.AddHours(-1).ToString("M/dd/yyyy HH:mm:ss")
$finish = $dtNow.ToString("M/dd/yyyy  HH:mm:ss")
$statAverages = [System.Collections.Generic.List[System.Object]]::new()

Import-CSV -Path "E:\Data\ClusterStats.csv" -Delimiter "`t" -ErrorAction SilentlyContinue | Sort-Object Timestamp | ForEach-Object { $_.Timestamp = [DateTime] ($_.Timestamp); $statAverages.Add($_) }

$maxDT = $null
if($statAverages.Count -gt 0)
{
    $maxDT = ([DateTime] ($statAverages | Measure-Object -Property Timestamp -Maximum).Maximum).AddMinutes(5)
    $start = $maxDT.ToString("M/dd/yyyy  HH:mm:ss")
}

$statAverages.Clear()


$clusterNames = @("CDC-PRD-VCAD-01", "DDC-PRD-VCAD-1")
$a = 0
while($a -lt $clusterNames.Length)
{
    $clusterName = $clusterNames[$a]
    $dcMemStatName = "{0}Memory" -f @($clusterName.Substring(0, 3))
    $dcCPUStatName = "{0}CPU" -f @($clusterName.Substring(0, 3))

    $cluster = Get-Cluster -Server $vCenter -Name $clusterName
    $clusterHosts = Get-VMHost -Server $vCenter -Location $cluster | Where-Object { $_.State -ne [VMware.VimAutomation.ViCore.Types.V1.Host.VMHostState]::Maintenance }
    $clusterVMS = Get-VM -Server $vCenter -Location $cluster

    $totalMemKB = ($clusterHosts | Measure-Object -Property MemoryTotalGB -Sum).Sum * 1MB  # Convert GB to KB since memory stats are in KB
    $totalMHz = ($clusterHosts | Measure-Object -Property CpuTotalMhz -Sum).Sum

    $clusterStats = Get-Stat -Entity $clusterVMS -Stat "cpu.ready.summation" -Start $start -Finish $finish -IntervalSecs 5
#    $memStats = $clusterStats | Where-Object { $_.MetricId -eq "mem.consumed.average" }
#    $cpuStats = $clusterStats | Where-Object { $_.MetricId -ne "mem.consumed.average" }

    $uniqueTimestamps = @($clusterStats | Select-Object -Unique -ExpandProperty Timestamp | Sort-Object | Where-Object { ($null -ne $maxDT) -and ($_ -ge $maxDT) })

    $b = 0
    while($b -lt $uniqueTimestamps.Length)
    {
        $ts = $uniqueTimestamps[$b]

        $memstat = $clusterStats | Where-Object { ($_.Timestamp -eq $ts) -and ($_.MetricId -eq "mem.consumed.average") }
        $cpustat = $clusterStats | Where-Object { ($_.Timestamp -eq $ts) -and ($_.MetricId -eq "cpu.usagemhz.average") }

        $statIdx = $statAverages.IndexOf(($statAverages | Where-Object { $_.Timestamp -eq $ts }))
        $d = $null
        if($statIdx -eq -1)
        {
            $d = "" | Select-Object Timestamp, CDCMemory, CDCCPU, DDCMemory, DDCCPU
            $d.Timestamp = $ts

            $statAverages.Add($d)
        }
        else
        {
            $d = $statAverages[$statIdx]
        }

        $d.$dcMemStatName = $memstat.Value / $totalMemKB
        $d.$dcCPUStatName = $cpustat.Value / $totalMHz

        $b++
    }

    $a++
}

$statAverages | Export-Csv -Append -Path "E:\Data\ClusterStats.csv" -Delimiter "`t" -NoTypeInformation -Confirm:$false


<#
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
#>

# $memStats | Measure-Object -Maximum -Minimum -Average -Property Value
# $totalMemTB = $totalMemKB / 1GB
# $maxMemConsumedTB = (($memStats | Measure-Object -Maximum -Property Value).Maximum * 1KB) / 1TB
# $excessMemTB = $totalMemTB - $maxMemConsumedTB
# ($maxMemConsumedTB / $totalMemTB) * 100
# ($excessMemTB / $totalMemTB) * 100


#$cpuStats | Measure-Object -Maximum -Minimum -Average -Property Value
#$maxMHzConsumed = ($cpuStats | Measure-Object -Maximum -Property Value).Maximum
#$excessMHz = $totalMHz - $maxMHzConsumed
#($maxMHzConsumed / $totalMHz) * 100
#($excessMHz / $totalMHz) * 100

#$maxMHzConsumed.ToString("N0") | Set-Clipboard
#$excessMHz.ToString("N0") | Set-Clipboard
#$totalMHz.ToString("N0") | Set-Clipboard
