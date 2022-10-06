function Disable-PortGroupNetflow
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.Vds.Types.V1.VmwareVDPortgroup] $portGroup,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter
    )

    if($portGroup.ExtensionData.Config.DefaultPortConfig.ipfixEnabled.value)
    {
        Write-Host ("Disabling netflow on {0}:{1}:{2}." -f @($portgroup.VDSwitch.Datacenter.Name, $portGroup.VDSwitch.Name, $portGroup.Name))
        $portgroupConfigSpec = [VMware.Vim.DVPortgroupConfigSpec]::new()
        $portgroupConfigSpec.configversion = $portGroup.Extensiondata.Config.ConfigVersion
        $portgroupConfigSpec.defaultPortConfig = [VMware.Vim.VMwareDVSPortSetting]::new()
        $portgroupConfigSpec.defaultPortConfig.ipfixEnabled = [VMware.Vim.BoolPolicy]::new()
        $portgroupConfigSpec.defaultPortConfig.ipfixEnabled.inherited = $false
        $portgroupConfigSpec.defaultPortConfig.ipfixEnabled.value = $false

        $pgView = Get-View -Server $vCenter -Id $portGroup.Id
        $task = $pgView.ReconfigureDVPortgroup_Task($portgroupConfigSpec)
        Start-Sleep -Seconds 1
    }
    else
    {
        Write-Host -ForegroundColor Yellow ("Netflow on {0}:{1}:{2} is already disabled." -f @($portgroup.VDSwitch.Datacenter.Name, $portGroup.VDSwitch.Name, $portGroup.Name))
    }
}

function Disable-VDSwitchNetFlow
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.Vds.Types.V1.VmwareVDSwitch] $distributedSwitch,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter
    )

    $portGroups = @(Get-VDPortgroup -VDSwitch $distributedSwitch -Server $vCenter)

    $a = 0
    while($a -lt $portGroups.Length)
    {
        Disable-PortGroupNetflow $portGroups[$a] $vCenter
        $a++
    }

    $distributedSwitch = Get-VDSwitch -Server $vCenter -Name $distributedSwitch.Name
    if(-not [String]::IsNullOrEmpty($distributedSwitch.ExtensionData.Config.IpfixConfig.CollectorIpAddress))
    {
        Write-Host ("Disabling NetFlow on {0}:{1}." -f @($distributedSwitch.Datacenter.Name, $distributedSwitch.Name))
        Write-Host ("`tCollector Address: [{0}]" -f @($distributedSwitch.ExtensionData.Config.IpfixConfig.CollectorIpAddress))
        $dvsConfigSpec = [VMware.Vim.VMwareDVSConfigSpec]::new()
        $dvsConfigSpec.IpfixConfig = [VMware.Vim.VMwareIpfixConfig]::new()

        $dvsConfigSpec.IpfixConfig.CollectorIpAddress = ""
        $dvsConfigSpec.IpfixConfig.CollectorPort = 0
        $dvsConfigSpec.IpfixConfig.ActiveFlowTimeout = 60
        $dvsConfigSpec.IpfixConfig.IdleFlowTimeout = 15
        $dvsConfigSpec.IpfixConfig.InternalFlowsOnly = $false
        $dvsConfigSpec.IpfixConfig.SamplingRate = 0

        $dvsConfigSpec.ConfigVersion = $distributedSwitch.ExtensionData.Config.ConfigVersion

        $distributedSwitch.ExtensionData.ReconfigureDvs($dvsConfigSpec)
    }
    else
    {
        Write-Host -ForegroundColor Yellow ("NetFlow on {0}:{1} is already disabled." -f @($distributedSwitch.Datacenter.Name, $distributedSwitch.Name))
    }
}

$distributedSwitches = @(Get-VDSwitch -Server $vcenter)
$a = 0
while($a -lt $distributedSwitches.Length)
{
    Disable-VDSwitchNetFlow $distributedSwitches[$a] $vcenter

    Start-Sleep -Seconds 10
    $a++
}
