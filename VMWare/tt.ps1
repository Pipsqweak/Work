# $dsf = Get-Content -Path 'C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\VMWare\ddcInternal.json' | ConvertFrom-Json

$vmNICName = "vmnic1"
$uplinkName = "VMOTIONMGMT"
$vmHostName = "ddc-esx-c1-b6.powereng.com"
$vds = Get-VDSwitch -Server $vCenter -Name $dsf.switchName -ErrorAction SilentlyContinue
$vmHost = Get-VMHost -Server $vCenter -Name $vmHostName -ErrorAction SilentlyContinue
$netSys = Get-View -Id $vmHost.ExtensionData.ConfigManager.NetworkSystem -ErrorAction SilentlyContinue
$uplinkPG = Get-VDPortgroup -VDSwitch $vds -Name "~Uplinks"
$uplinks = @(Get-VDPort -VDSwitch $vds -Uplink -ErrorAction SilentlyContinue | Where-Object { $_.ProxyHost.Name -eq $vmHost.Name })
$proxy = [VMware.Vim.HostProxySwitchConfig]::new()
# $proxy.Uuid = $vds.ExtensionData.Uuid
$proxy.Uuid = $vds.Key
# $proxy.ChangeOperation = [VMware.Vim.HostConfigChangeOperation]::edit
$proxy.ChangeOperation = "edit"
$proxy.Spec = [VMware.Vim.HostProxySwitchSpec]::new()
$proxy.Spec.Backing = [VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking]::new()

$a = 0
while($a -lt $uplinks.Length)
{
    $pNICSpec = [VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec]::new()
    $pNICSpec.UplinkPortgroupKey = $uplinkPG.Key
    $pNICSpec.UplinkPortKey = $uplinks[$a].Key

    if ($uplinks[$a].Name -eq $uplinkName)
    {
        $pNICSpec.PnicDevice = $vmNICName
    }
    else # NOT ($uplinks[$a].Name -eq $uplinkName)
    {
        $pNICSpec.PnicDevice = $uplinks[$a].ConnectedEntity
        <#
        if ($null -ne $uplinks[$a].ConnectedEntity)
        {
            $pNICSpec.PnicDevice = $uplinks[$a].ConnectedEntity.Name
        }
        else # NOT ($null -ne $uplinks[$a].ConnectedEntity)
        {
            $pNICSpec.PnicDevice = $null
        }
        #>
    }

    $proxy.Spec.Backing.pNICSpec += $pNICSpec
    $a++
}

$config = [VMware.Vim.HostNetworkConfig]::new()
$config.ProxySwitch += $proxy
$mo = $netSys.UpdateNetworkConfig($config, "modify")
