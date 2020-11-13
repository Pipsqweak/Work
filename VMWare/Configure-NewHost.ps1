$vmHost = Get-VMHost -Server $vcenter -Name "cdc-esx-c1-b3.powereng.com"
$vmHosts = Get-VMHost -Server $vcenter

$a = 0
$hostSettings = @(
    while ($a -lt $vmHosts.Length)
    {
        $d = "" | Select-Object HostName, SettingValue

        $d.HostName = $vmHosts[$a].Name
        $setting = Get-AdvancedSetting -Entity $vmHosts[$a] -Name Syslog.Global.logdir -ErrorAction SilentlyContinue

        $d.SettingValue = $setting.Value

        $d
        $a++
    }
)

$hostSettings | ft -AutoSize



$null = Get-AdvancedSetting -Entity $vmHost -Name UserVars.SuppressShellWarning | Set-AdvancedSetting -Value 1 -Confirm:$False
$null = Get-AdvancedSetting -Entity $vmHost -Name UserVars.SuppressHyperThreadWarning | Set-AdvancedSetting -Value '1' -Confirm:$false
$null = Get-AdvancedSetting -Entity $vmHost -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup | Set-AdvancedSetting -Value 'pgVCenterAdmin' -Confirm:$False


$vds = Get-VDSwitch -Server $vcenter -Name "CDC-Test"
Get-VDUplinkLacpPolicy -VDSwitch $vds | Set-VDUplinkLacpPolicy -Enabled $true -Mode Active


$mgmtIP = "10.245.1.72"
$mgmtSubnetMask = "255.255.255.0"

$storageIP = "10.245.11.105"
$storageSubnetMask = "255.255.255.0"

$vMotionIP = "10.245.11.106"
$vMotionSubnetMask = "255.255.255.0"

$vmHost = Get-VMHost -Server $vcenter -Name "cdc-esx-c1-b3.powereng.com" 
$profile = $null
$profile = Get-VMHostProfile -Server $vcenter -Name "KLB Test Host Profile"
$vmk0 = Get-VMHostNetworkAdapter -VMHost $vmHost -VMKernel -Name "vmk0"

$settings = Invoke-VMHostProfile -Server $vcenter -Entity $vmHost -Profile $profile -Confirm:$false

# If we were unable to get the real vmk0 adapter, then create mock one
if($null -eq $vmk0)
{
    $vmk0 = "" | Select-Object IP, SubnetMask
    $vmk0.IP = $mgmtIP
    $vmk0.SubnetMask = $mgmtSubnetMask
}

$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-MgmtVLAN1-vmk0"].ipConfig.IpAddressPolicy.address'] = $vmk0.IP
$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-MgmtVLAN1-vmk0"].ipConfig.IpAddressPolicy.subnetmask'] = $vmk0.SubnetMask

$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-vMotionVLAN11-vmk2"].ipConfig.IpAddressPolicy.address'] = $vMotionIP
$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-vMotionVLAN11-vmk2"].ipConfig.IpAddressPolicy.subnetmask'] = $vMotionSubnetMask

$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-StorageVLAN11-vmk1"].ipConfig.IpAddressPolicy.address'] = $storageIP
$settings['network.dvsHostNic["key-vim-profile-host-DvsHostVnicProfile-CDC-Test-StorageVLAN11-vmk1"].ipConfig.IpAddressPolicy.subnetmask'] = $storageSubnetMask

Invoke-VMHostProfile -Server $vcenter -Entity $vmHost -Profile $profile -Variable $settings -Confirm:$false
