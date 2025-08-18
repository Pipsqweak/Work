ConnectTo vCenter,Prod


<#

    MIGRATE ESXi host from distributed switch to standard switch

#>
$viServer = $cdcesxc2b7
$vmHostName = "cdc-esx-c2-b7.powereng.com"
$vmHost = Get-VMHost -Server $viServer -Name $vmHostName

$vSwitch0 = New-VirtualSwitch -Server $viServer -VMHost $vmHost -Name "vSwitch0" -Mtu 9000

$vSwitch0_VL01PSRV = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "PSRV VLAN 1" -VLanId 1
$vSwitch0_VL02ServerData = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "SERVERDATA VLAN 2" -VLanId 2
$vSwitch0_VL03ServerData = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "SERVERDATA VLAN 3" -VLanId 3
$vSwitch0_VL5Mgmt = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "MGMT VLAN 5" -VLanId 5
$vSwitch0_VL07NLS = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "NLS VLAN 7" -VLanId 7
$vSwitch0_VL08LBFRONTEND = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "LBFRONTEND VLAN 8" -VLanId 8
$vSwitch0_VL09LBFARM = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "LBFARM VLAN 9" -VLanId 9
$vSwitch0_VL11Storage = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "STORAGE VLAN 11" -VLanId 11
$vSwitch0_VL11vMotion = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "VMOTION VLAN 11" -VLanId 11
$vSwitch0_VL20VOICEELAN = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "VOICE-ELAN VLAN 20" -VLanId 20
$vSwitch0_VL21INFOSECMGMT = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "INFOSEC MGMT VLAN 21" -VLanId 21
$vSwitch0_VL29ENTPROV = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "ENTPROV VLAN 29" -VLanId 29
$vSwitch0_VL40CLIENTLAN = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "CLIENTLAN VLAN 40" -VLanId 40
$vSwitch0_VL80DEV1 = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "DEV1 VLAN 80" -VLanId 80
$vSwitch0_VLTRUNKLBBACKEND = New-VirtualPortGroup -Server $viServer -VirtualSwitch $vSwitch0 -Name "LBBACKEND VLAN TRUNK"

$pgsToAffect = @($vSwitch0_VL01PSRV, $vSwitch0_VL02ServerData, $vSwitch0_VL03ServerData, $vSwitch0_VL5Mgmt, $vSwitch0_VL07NLS, $vSwitch0_VL08LBFRONTEND, $vSwitch0_VL09LBFARM, $vSwitch0_VL11Storage, $vSwitch0_VL11vMotion, $vSwitch0_VL20VOICEELAN, $vSwitch0_VL21INFOSECMGMT, $vSwitch0_VL29ENTPROV, $vSwitch0_VL40CLIENTLAN, $vSwitch0_VL80DEV1, $vSwitch0_VLTRUNKLBBACKEND)
$pgsToAffect = @($vSwitch0_VL5Mgmt, $vSwitch0_VL11Storage, $vSwitch0_VL11vMotion)

foreach($pg in $pgsToAffect)
{
    ClearPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $pg
}

# Get the VM Host networking...
$vmHostNetwork = Get-VMHostNetwork -Server $viServer -VMHost $vmHost

# Migrate vmNIC1 from the vDS to the new standard switch first so we can migrate vmk0 from the vDS to the std switch without losing connectivity
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic1"
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL5Mgmt -activeAdapters $null -standbyAdapters @("vmnic1")

# Migrate management vmk0 to the standard switch
MigrateVMK2StdSwitch -viServer $viServer -vmHost $vmHost -portGroupName $vSwitch0_VL5Mgmt.Name -vmkName "vmk0"

# Set the port teaming for the vMotion port group
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL11vMotion -activeAdapters @("vmnic1") -standbyAdapters $null

# Migrate vMotion vmk2 to the standard switch
MigrateVMK2StdSwitch -viServer $viServer -vmHost $vmHost -portGroupName $vSwitch0_VL11vMotion -vmkName "vmk2"

# Migrate one of the storage vmNICs to the standard switch
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic3"
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL11Storage -activeAdapters @("vmnic3") -standbyAdapters $null

# Migrate the storage VMK to the standard switch
MigrateVMK2StdSwitch -viServer $viServer -vmHost $vmHost -portGroupName $vSwitch0_VL11Storage.Name -vmkName "vmk1"

# Migrate one of the guest vmNICs to the standard switch
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic5"
foreach($pg in $pgsToAffect)
{
    SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $pg -activeAdapters @("vmnic5") -standbyAdapters $null
}

# Migrate vmnic0 to the standard switch
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic0"

# Update port group teaming
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL5Mgmt -activeAdapters @("vmnic0") -standbyAdapters @("vmnic1")
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL11vMotion -activeAdapters @("vmnic1") -standbyAdapters @("vmnic0")

# Migrate the other storage vmNIC to the standard switch
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic2"
SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $vSwitch0_VL11Storage -activeAdapters @("vmnic2","vmnic3") -standbyAdapters $null

# Finally, migrate the other guest network vmnic and update the port group teaming
MigrateVMNIC2StdSwitch -viServer $viServer -vmHost $vmHost -vSwitch $vSwitch0 -vmNICName "vmnic4"
foreach($pg in $pgsToAffect)
{
    SetPortGroupTeaming -viServer $viServer -vSwitch $vSwitch0 -portGroup $pg -activeAdapters @("vmnic4","vmnic5") -standbyAdapters $null
}

# Finally, remove the host from the distributed switch
$vds = Get-VDSwitch -Server $viServer -Name "CDC Internal vDS 01"
Remove-VDSwitchVMHost -Server $viServer -VMHost $vmHost -VDSwitch $vds -Confirm:$false

function MigrateVMK2StdSwitch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl]
        $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]
        $vmHost,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String]
        $portGroupName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [String]
        $vmkName
    )

    $vmHostNetwork = Get-VMHostNetwork -Server $viServer -VMHost $vmHost

    # Migrate vmk to the standard switch
    $nicSpec = [VMware.Vim.HostVirtualNicSpec]::new()
    $nicSpec.Portgroup = $portGroupName
    $vmHostNetwork.ExtensionData2.UpdateVirtualNic($vmkName, $nicSpec)
}

function ClearPortGroupTeaming
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualSwitchImpl]
        $vSwitch,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl]
        $portGroup
    )

    # Clear teaming on the port group
    $pgSpec = [VMware.Vim.HostPortGroupSpec]::new()
    $pgSpec.VswitchName = $vSwitch.Name
    $pgSpec.VlanId = $portGroup.VLanId
    $pgSpec.Name = $portGroup.Name
    $pgSpec.Policy = [VMware.Vim.HostNetworkPolicy]::new()
    $pgSpec.Policy.Security = [VMware.Vim.HostNetworkSecurityPolicy]::new()
    $pgSpec.Policy.ShapingPolicy = [VMware.Vim.HostNetworkTrafficShapingPolicy]::new()
    $pgSpec.Policy.NicTeaming = [VMware.Vim.HostNicTeamingPolicy]::new()
    $pgSpec.Policy.NicTeaming.NicOrder = [VMware.Vim.HostNicOrderPolicy]::new()
    $pgSpec.Policy.NicTeaming.NicOrder.ActiveNic = [String[]]::new(0)
    $pgSpec.Policy.NicTeaming.NicOrder.StandbyNic = [String[]]::new(0)
    $vmHostNetwork = Get-VMHostNetwork -Server $viServer -VMHost $vmHost
    $vmHostNetwork.ExtensionData2.UpdatePortGroup($portGroup.Name, $pgSpec)
}

function SetPortGroupTeaming
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualSwitchImpl]
        $vSwitch,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl]
        $portGroup,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [String[]]
        $activeAdapters,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [String[]]
        $standbyAdapters
    )

    $pgSpec = [VMware.Vim.HostPortGroupSpec]::new()
    $pgSpec.VswitchName = $vSwitch.Name
    $pgSpec.VlanId = $portGroup.VLanId
    $pgSpec.Name = $portGroup.Name
    $pgSpec.Policy = [VMware.Vim.HostNetworkPolicy]::new()
    $pgSpec.Policy.Security = [VMware.Vim.HostNetworkSecurityPolicy]::new()
    $pgSpec.Policy.ShapingPolicy = [VMware.Vim.HostNetworkTrafficShapingPolicy]::new()
    $pgSpec.Policy.NicTeaming = [VMware.Vim.HostNicTeamingPolicy]::new()
    $pgSpec.Policy.NicTeaming.NicOrder = [VMware.Vim.HostNicOrderPolicy]::new()
    $pgSpec.Policy.NicTeaming.NicOrder.ActiveNic = $activeAdapters
    $pgSpec.Policy.NicTeaming.NicOrder.StandbyNic = $standbyAdapters
    $vmHostNetwork = Get-VMHostNetwork -Server $viServer -VMHost $vmHost
    $vmHostNetwork.ExtensionData2.UpdatePortGroup($portGroup.Name, $pgSpec)
}

function MigrateVMNIC2StdSwitch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl]
        $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]
        $vmHost,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualSwitchImpl]
        $vSwitch,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [String]
        $vmNICName
    )
    $vmnic = Get-VMHostNetworkAdapter -Server $viServer -Physical -Name $vmNICName -VMHost $vmHost -ErrorAction Stop
    Remove-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmnic -Confirm:$false
    Add-VirtualSwitchPhysicalNetworkAdapter -Server $viServer -VirtualSwitch $vSwitch -VMHostPhysicalNic $vmnic -Confirm:$false
}


<#

    Migrate ESXi host from standard switch to distributed switch...

#>
