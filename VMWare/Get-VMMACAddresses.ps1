
$macData = [System.Collections.Generic.List[System.Object]]::new()
$clusters = Get-Cluster -Server $vCenter
$a = 0
while($a -lt $clusters.Length)
{
    $clusterVMs = Get-VM -Server $vCenter -Location $clusters[$a] | Where-Object { $_.Name -notmatch "vCLS\-" }

    $b = 0
    while($b -lt $clusterVMs.Length)
    {
        $vmNAs = $clusterVMs[$b] | Get-NetworkAdapter

        $c = 0
        while($c -lt $vmNAs.Length)
        {
            $d = "" | Select-Object Cluster,VM,NA,NAType,NetworkName,MAC,MACType

            $d.Cluster = $clusters[$a].Name
            $d.VM = $clusterVMs[$b].Name
            $d.NA = $vmNAs[$c].Name
            $d.NAType = $vmNAs[$c].Type
            $d.NetworkName = $vmNAs[$c].NetworkName
            $d.MAC = $vmNAs[$c].MacAddress
            $d.MACType = $vmNAs[$c].ExtensionData.AddressType

            if($d.MACType -ne "assigned")
            {
                Write-Host ("{0}" -f @(@($d.Cluster, $d.VM, $d.NA, $d.NAType, $d.NetworkName, $d.MAC, $d.MACType) -join ", "))
            }

            $macData.Add($d)
            $c++
        }
        $b++
    }
    $a++
}
