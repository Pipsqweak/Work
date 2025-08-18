$vmHosts = Get-VMHost -Server @($vCenterServers.Values) | Sort-Object Name
$hostCoreData = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $vmHosts.Length)
{
    $d = "" | Select-Object Cluster, Name, Sockets, Cores, CoresPerSocket

    $cluster = $vmHosts[$a] | Get-Cluster -Server @($vCenterServers.Values)
    $d.Cluster = $cluster.Name
    $d.Name = $vmhosts[$a].name
    $d.Sockets = $vmhosts[$a].ExtensionData.Hardware.CpuInfo.NumCpuPackages
    $d.Cores = $vmhosts[$a].ExtensionData.Hardware.CpuInfo.NumCpuCores
    $d.CoresPerSocket = ($d.Cores / $d.Sockets)

    $hostCoreData.Add($d)
    $d
    $a++
}
