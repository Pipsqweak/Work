$hostsToReIP = @(
    "ddc-esx-c1-b1.powereng.com",
    "ddc-esx-c1-b2.powereng.com",
    "ddc-esx-c1-b3.powereng.com",
    "ddc-esx-c1-b4.powereng.com",
    "ddc-esx-c1-b5.powereng.com",
    "ddc-esxvcad01.powereng.com",
    "ddc-esxvcad02.powereng.com",
    "ddc-esxvcad03.powereng.com",
    "ddc-esxvcad04.powereng.com",
    "cdc-esx-c1-b1.powereng.com",
    "cdc-esx-c1-b2.powereng.com",
    "cdc-esx-c1-b3.powereng.com",
    "cdc-esxvcad01.powereng.com",
    "cdc-esxvcad02.powereng.com"
)

$vCtr = $vCenter
$configData = @()
$a = 0
while($a -lt $hostsToReIP.Length)
{
    $z = "" | Select-Object Name, VDSwitches, Datastores, VMKs, VMNICs, LogDir
    $z.Name = $vmHost.Name
    $z.VDSwitches = @()
    $z.Datastores = @()
    $z.VMKs = @()
    $z.VMNICs = @()

    $vmHost = Get-VMHost -Server $vCtr -Name $hostsToReIP[$a]
    $vdSwitches = @(Get-VDSwitch -Server $vCtr -VMHost $vmHost)

    $b = 0
    while($b -lt $vdSwitches.Length)
    {
        $vdsConfig = "" | Select-Object Name, Uplinks
        $vdsConfig.Name = $vdSwitches[$b].Name
        $vdsConfig.Uplinks = @(Get-VDPort -VDSwitch $vdSwitches[$b] -Uplink | Where-Object { $_.ProxyHost -eq $vmHost } | Select-Object Name, @{N="VMNICMAC"; E={ $_.ConnectedEntity.Mac }})

        $z.VDSwitches += $vdsConfig
        $b++
    }

    $z.Datastores = @(Get-Datastore -Server $vCtr -RelatedObject $vmHost | Where-Object { $_.Type -eq "NFS" } | Select-Object -ExpandProperty Name)

    $vmks = @(Get-VMHostNetworkAdapter -VMHost $vmHost -VMKernel)
    $b = 0
    while($b -lt $vmks.Length)
    {
        $y = "" | Select-Object Name, VMotionEnabled, ManagementTrafficEnabled, Mtu, PortGroupName, IP, SubnetMask

        $y.Name = $vmks[$b].Name
        $y.VMotionEnabled = $vmks[$b].VMotionEnabled
        $y.ManagementTrafficEnabled = $vmks[$b].ManagementTrafficEnabled
        $y.Mtu = $vmks[$b].Mtu
        $y.PortGroupName = $vmks[$b].PortGroupName
        $y.IP = $vmks[$b].IP
        $y.SubnetMask = $vmks[$b].SubnetMask

        $z.VMKs += $y
        $b++
    }

    $vmnics = @(Get-VMHostNetworkAdapter -VMHost $vmHost -Physical)
    $b = 0
    while($b -lt $vmnics.Length)
    {
        $y = "" | Select-Object Name, Mac

        $y.Name = $vmnics[$b].Name
        $y.Mac = $vmnics[$b].Mac

        $z.VMNICs += $y
        $b++
    }

    $advsetting = Get-AdvancedSetting -Entity $vmHost -Name "Syslog.global.logDir"
    $z.LogDir = $advsetting.Value

    $configData += $z
    $a++
}



$configData | ConvertTo-Json -Depth 10 | Set-Clipboard
