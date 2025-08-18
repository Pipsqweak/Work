$vmClusters = @("CDC-INT-CLUSTER-01","DDC-INT-CLUSTER-01")
# $a = 0
$a = 1
while($a -lt $vmClusters.Length)
{
    $clusterRPStats = [System.Collections.Generic.List[System.Object]]::new()

    $clusterResourcePools = Get-ResourcePool -Server $vCenter -Location $vmClusters[$a]
    $clusterResourcePool = $clusterResourcePools | Where-Object { $_.Name -eq "Resources" }
    $clusterChildResourcePools = $clusterResourcePools | Where-Object { $_.Name -ne $clusterResourcePool.Name }

    $b = 0
    while($b -lt $clusterChildResourcePools.Length)
    {
        $d = "" | Select-Object RPName, VMCount, VMMemMB, CPUUsageMHz, CPULimitMHz, MemLimitMB
        $d.RPName = $clusterChildResourcePools[$b].Name
        $d.CPULimitMHz = $clusterChildResourcePools[$b].CpuLimitMHz
        $d.MemLimitMB = $clusterChildResourcePools[$b].MemLimitMB

        $rpVMs = Get-VM -Server $vCenter -Location $clusterChildResourcePools[$b] | Where-Object { $_.PowerState -eq "PoweredOn" }
        $d.VMCount = $rpVMs.Length
        $d.VMMemMB = ($rpVMs | Measure-Object -Sum -Property MemoryGB).Sum

        $rpCPUActive = Get-Stat -Server $vCenter -Entity $rpVMs -Stat "cpu.usagemhz.average" -IntervalSecs 1 -Start ([DateTime]::Now.AddMinutes(-5)) -Finish ([DateTime]::Now) -Instance ""
        $d.CPUUsageMHz = ($rpCPUActive | Measure-Object -Average -Property Value).Average * $rpVMs.Length
        $clusterRPStats.Add($d)

        $b++
    }
    $a++
}
