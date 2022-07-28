# UCS Stuff...

$labUCS = Connect-Ucs -Name $labUCSCreds.Server -Credential $labUCSCreds.Credential -NotDefault
$cdcUCS = Connect-Ucs -Name $labUCSCreds.Server -Credential $labUCSCreds.Credential -NotDefault
$ddcUCS = Connect-Ucs -Name $labUCSCreds.Server -Credential $labUCSCreds.Credential -NotDefault
$ucsPE = Connect-Ucs -Name "ucspe.powereng.com" -NotDefault


# Create a standard VLAN
Get-UcsLanCloud -Ucs $ddcUCS | Add-UcsVlan -Ucs $ddcUCS -CompressionType "included" -DefaultNet "no" -Id 80 -McastPolicyName "" -Name "VL80-DEV1" -PolicyOwner "local" -PubNwName "" -Sharing "none"

# Create VLAN Group
Start-UcsTransaction
$mo = Get-UcsLanCloud -Ucs $labUCS | Add-UcsFabricNetGroup -Ucs $labUCS -Name "VLANGROUP1"
$mo_1 = $mo | Add-UcsFabricPooledVlan -Ucs $labUCS -ModifyPresent -Name "VL03-SERVERDATA-SIM"
$mo_2 = $mo | Add-UcsFabricPooledVlan -Ucs $labUCS -ModifyPresent -Name "VL05-INFRAMGMT"
Complete-UcsTransaction

# Add VLAN Group Member
Start-UcsTransaction
$lanCloud = Get-UcsLanCloud -Ucs $ddcUCS
$vlanID = 1
$vlanDescr = "PSRV"
$vlanName = "VL{0:D2}-{1}" -f @($vlanID, $vlanDescr)
$vlanGrp = "MGMT-VMOTION"
$netGrp = $lanCloud | Add-UcsFabricNetGroup -Ucs $ddcUCS -ModifyPresent -Name $vlanGrp
$result = $netGrp | Add-UcsFabricPooledVlan -Ucs $ddcUCS -ModifyPresent -Name $vlanName
Complete-UcsTransaction

$a = 0
$ucsManagers = @($labUCS, $cdcUCS, $ddcUCS)
$basePath = "E:\UCS Backups\"
while($a -lt $ucsManagers.Length)
{
    $mo = Backup-Ucs -Type config-all -PathPattern ($basePath + '${ucs}\${yyyy}${MM}${dd}-${HH}${mm}-config-all.xml') -Ucs $ucsManagers[$a] -Xml
    $mo = Backup-Ucs -Type full-state -PathPattern ($basePath + '${ucs}\${yyyy}${MM}${dd}-${HH}${mm}-full-state.bak') -Ucs $ucsManagers[$a]

    $a++
}

# Create VLAN add it to a VLAN GROUP
$ucs = $ddcUCS
Start-UcsTransaction -Ucs $ucs
$lanCloud = Get-UcsLanCloud -Ucs $ucs
$vlanID = 84
$vlanDescr = "TEST1"
$vlanName = "VL{0:D2}-{1}" -f @($vlanID, $vlanDescr)
$vlanGrp = "VM-Guest"
$newVLAN = $lanCloud | Add-UcsVlan -Ucs $ucs -CompressionType "included" -DefaultNet "no" -Id $vlanID -McastPolicyName "" -Name $vlanName -PolicyOwner "local" -PubNwName "" -Sharing "none"
if(-not [String]::IsNullOrEmpty($vlanGrp))
{
    $netGrp = $lanCloud | Add-UcsFabricNetGroup -Ucs $ucs -ModifyPresent -Name $vlanGrp
    $result = $netGrp | Add-UcsFabricPooledVlan -Ucs $ucs -ModifyPresent -Name $vlanName
}
Complete-UcsTransaction -Ucs $ucs

# Remove VLAN from VLAN Group

Start-UcsTransaction
$mo = Get-UcsLanCloud | Add-UcsFabricNetGroup -ModifyPresent  -Name "DMZ-GUEST"
$mo_1 = Get-UcsLanCloud | Get-UcsFabricNetGroup -Name "DMZ-GUEST" -LimitScope | Get-UcsFabricPooledVlan -Name "INFOSEC-MGMT" | Remove-UcsFabricPooledVlan
Complete-UcsTransaction



# Create Fabric-A/Fabric-B Guest No Failover vNIC templates
$ucs = $ddcUCS
#Start-UcsTransaction -Ucs $ucs
$mtu = 1500
$macPoolName = "BDC-UCS01-MAC"
$netCtrlPolicy = "Standard"
$primarySwitchID = "A"
$secondarySwitchID = if($primarySwitchID -eq "A") { "B" } else { "A" }
$primarySwitchName = "Guest-Fab{0}-NF" -f @($primarySwitchID)
$secondarySwitchName = "Guest-Fab{0}-NF" -f @($secondarySwitchID)
$primarySwitchDescr = "Guest | Fabric {0} | NoFailover" -f @($primarySwitchID)
$secondarySwitchDescr = "Guest | Fabric {0} | NoFailover" -f @($secondarySwitchID)
$primarySwitch = $null
$secondarySwitch = $null
#$rootOrg = Get-UcsOrg -Ucs $ucs -Level root
$primarySwitch = Add-UcsVnicTemplate -Ucs $ucs -Descr $primarySwitchDescr -IdentPoolName $macPoolName -Name $primarySwitchName -NwCtrlPolicyName $netCtrlPolicy -RedundancyPairType "primary" -SwitchId $primarySwitchID -TemplType "updating-template" -Target "adaptor" -CdnSource "vnic-name" -Mtu $mtu
$secondarySwitch = Add-UcsVnicTemplate -Ucs $ucs -Descr $secondarySwitchDescr -IdentPoolName $macPoolName -Name $secondarySwitchName -NwCtrlPolicyName $netCtrlPolicy -PeerRedundancyTemplName $primarySwitchName -RedundancyPairType "secondary" -SwitchId $secondarySwitchID -TemplType "updating-template" -Target "adaptor" -CdnSource "vnic-name" -Mtu $mtu
#Complete-UcsTransaction -Ucs $ucs



# Remove vNIC template
$ucs = $labUCS
#Start-UcsTransaction -Ucs $ucs
Get-UcsVnicTemplate -Ucs $ucs -Name "GBN" -LimitScope | Remove-UcsVnicTemplate -Ucs $ucs -Confirm:$false -Force
Get-UcsVnicTemplate -Ucs $ucs -Name "GAN" -LimitScope | Remove-UcsVnicTemplate -Ucs $ucs -Confirm:$false -Force
#Complete-UcsTransaction -Ucs $ucs


# Create Disk Group Config Policy
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsLogicalStorageDiskGroupConfigPolicy -Name "dspKLB" -RaidLevel "mirror"
$mo_1 = $mo | Add-UcsLogicalStorageDiskGroupQualifier -ModifyPresent -DriveType "unspecified" -MinDriveSize "unspecified" -NumDedHotSpares "unspecified" -NumDrives "2" -NumGlobHotSpares "unspecified" -UseJbodDisks "yes" -UseRemainingDisks "no"
$mo_2 = $mo | Set-UcsLogicalStorageVirtualDriveDef -AccessPolicy "platform-default" -DriveCache "platform-default" -IoPolicy "platform-default" -ReadPolicy "platform-default" -Security "no" -StripSize "platform-default" -WriteCachePolicy "platform-default"
Complete-UcsTransaction

# Create Storage Profile
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsLogicalStorageProfile -Name "klbstorprofile"
$mo_1 = $mo | Add-UcsLogicalStorageDasScsiLun -ExpandToAvail "yes" -LocalDiskPolicyName "dspKLB" -Name "klbluntest" -Size "1"
Complete-UcsTransaction

# Create Network Control Policy
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsNetworkControlPolicy -Cdp "enabled" -MacRegisterMode "all-host-vlans" -Name "klb"
$mo_1 = $mo | Add-UcsPortSecurityConfig -ModifyPresent -Descr "" -Forge "allow" -Name "" -PolicyOwner "local"
Complete-UcsTransaction

# Create JUMBO Frames QoS Policy
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsQosPolicy -Name "klbJumbo"
$mo_1 = $mo | Add-UcsVnicEgressPolicy -ModifyPresent -Burst 10240 -HostControl "none" -Name "" -Prio "best-effort" -Rate "line-rate"
Complete-UcsTransaction

# Create IP Pool
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsIpPool -Name "klbippool"
$mo_1 = $mo | Add-UcsIpPoolBlock -DefGw "192.168.1.1" -From "192.168.1.15" -PrimDns "192.168.3.20" -SecDns "192.168.3.30" -To "192.168.1.46"
Complete-UcsTransaction

# Create BIOS Policy
$biosProfileConfig = Get-Content -Path .\UCS\biosPolicySettings.json | ConvertFrom-Json

# Create the base Policy
Start-UcsTransaction -Ucs $cdcUCS
$ucsOrg = Get-UcsOrg -Ucs $cdcUCS -Level "root"
$biosProfile = $ucsOrg | Add-UcsBiosPolicy -Ucs $cdcUCS -Name $biosProfileConfig.Name
$newBIOSProfile = Complete-UcsTransaction -Ucs $cdcUCS

# Apply all the settings.
Start-UcsTransaction -Ucs $cdcUCS
$a = 0
$newBIOSSettings = @()
while($a -lt $biosProfileConfig.Settings.Length)
{
    $d = "" | Select-Object Name, Setting
    $d.Name = $biosProfileConfig.Settings[$a].Name
    Write-Host ("Setting {0}:{1}..." -f @($biosProfileConfig.Settings[$a].Name, $biosProfileConfig.Settings[$a].TargetTokenName))
    $d.Setting =  Get-UcsBiosTokenFeatureGroup -BiosPolicy $biosProfile -Name $biosProfileConfig.Settings[$a].Name | Get-UcsBiosTokenParam -TargetTokenName $biosProfileConfig.Settings[$a].TargetTokenName | Add-UcsManagedObject -ModifyPresent -ClassId BiosTokenSettings -PropertyMap @{SettingsMoRn=$biosProfileConfig.Settings[$a].PropertyMap.SettingsMoRn; IsAssigned=$biosProfileConfig.Settings[$a].PropertyMap.IsAssigned; }

    $newBIOSSettings += $d
    $a++
}
$tranSettings = Complete-UcsTransaction -Ucs $cdcUCS

# Set management config

Start-UcsTransaction
Get-UcsSvcEp | Add-UcsManagedObject -ModifyPresent  -ClassId CommDns -PropertyMap @{Domain="powereng.com"; }
Add-UcsManagedObject -ModifyPresent  -ClassId TopSystem -PropertyMap @{Name="ucsPE"; Owner="Infrastructure"; Descr="Lab UCS Platform Emulator1"; Site="ucsPE1"; Dn="sys"; }
Complete-UcsTransaction

Add-UcsManagedObject -ModifyPresent  -ClassId ExtmgmtIfMonPolicy -PropertyMap @{AdminState="disabled"; Dn="sys/extmgmt-intf-monitor-policy"; }
Get-UcsSvcEp | Get-UcsDns | Add-UcsDnsServer -Name "10.86.3.10"
Get-UcsSvcEp | Get-UcsDns | Add-UcsDnsServer -Name "10.247.3.10"

Get-UcsSvcEp | Get-UcsTimezone | Add-UcsNtpServer -Name "ntp1.powereng.com"
Get-UcsSvcEp | Get-UcsTimezone | Add-UcsNtpServer -Name "ntp2.powereng.com"
Get-UcsSvcEp | Add-UcsManagedObject -ModifyPresent  -ClassId CommDateTime -PropertyMap @{Timezone="America/Boise (Mountain Time - south Idaho & east Oregon)"; }


# Set equipment global policy

Start-UcsTransaction
Add-UcsManagedObject -ModifyPresent  -ClassId ComputeChassisDiscPolicy -PropertyMap @{Action="2-link"; Dn="org-root/chassis-discovery"; }
Add-UcsManagedObject -ModifyPresent  -ClassId ComputeServerDiscPolicy -PropertyMap @{Dn="org-root/server-discovery"; ScrubPolicyName=""; Action="immediate"; }
Get-UcsOrg -Level root  | Add-UcsManagedObject -ModifyPresent  -ClassId ComputeServerMgmtPolicy -PropertyMap @{Action="auto-acknowledged"; }
Add-UcsManagedObject -ModifyPresent  -ClassId ComputePsuPolicy -PropertyMap @{Redundancy="grid"; Dn="org-root/psu-policy"; }
Add-UcsManagedObject -ModifyPresent  -ClassId FabricLanCloud -PropertyMap @{Dn="fabric/lan"; MacAging="mode-default"; }
Add-UcsManagedObject -ModifyPresent  -ClassId PowerMgmtPolicy -PropertyMap @{Style="intelligent-policy-driven"; Dn="org-root/pwr-mgmt-policy"; }
Get-UcsOrg -Level root  | Add-UcsManagedObject -ModifyPresent  -ClassId FirmwareAutoSyncPolicy -PropertyMap @{SyncState="No Actions"; }
Complete-UcsTransaction

# Delete builtin boot policies

Start-UcsTransaction -Ucs $ucs
$rootOrg = Get-UcsOrg -Ucs $ucs -Level "root"
foreach($bpName in @("default", "default-UEFI", "diag", "utility"))
{
    $bootPolicy = Get-UcsBootPolicy -Ucs $ucs -Org $rootOrg -Name $bpName -ErrorAction Stop
    if($null -ne $bootPolicy)
    {
        $removedBootPolicy = Remove-UcsBootPolicy -Ucs $ucs -BootPolicy $bootPolicy -Confirm:$false -Force -ErrorAction Stop
    }
}
[void] (Complete-UcsTransaction -Ucs $ucs)


# Create boot policy

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsBootPolicy -BootMode "uefi" -Name "M.2-Boot"
$mo_1 = $mo | Add-UcsLsbootBootSecurity -SecureBoot "no"
$mo_2 = $mo | Add-UcsLsbootStorage -Order 1
$mo_2_1 = $mo_2 | Add-UcsLsbootLocalStorage
$mo_2_1_1 = $mo_2_1 | Add-UcsLsbootEmbeddedLocalLunImage -ModifyPresent -Order 1
$mo_2_1_1_1 = $mo_2_1_1 | Add-UcsLsbootUEFIBootParam -ModifyPresent -BootDescription "VMware ESXi" -BootLoaderName "BOOTx64.EFI" -BootLoaderPath "\EFI\BOOT"
$mo_3 = $mo | Add-UcsLsbootVirtualMedia -Access "read-only-remote" -LunId "0" -Order 2
Complete-UcsTransaction

# Delete Scrub policy

Start-UcsTransaction -Ucs $ucs
$mo = Get-UcsOrg -Ucs $ucs -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Ucs $ucs -Level root | Get-UcsScrubPolicy -Name "default" -LimitScope | Remove-UcsScrubPolicy -Confirm:$false -Force
[void] (Complete-UcsTransaction -Ucs $ucs)

# Create Scrub Policy

Get-UcsOrg -Level root  | Add-UcsScrubPolicy -Name "NOSCRUB"


# Create Key Ring

$keyRing = Add-UcsKeyRing -Ucs $ucs -Modulus "mod4096" -Name "ucsPE_cert"
$newCertReq = Add-UcsCertRequest -Ucs $ucs -KeyRing $keyRing -Country "US" -Dns "ucspe.powereng.com" -Locality "Meridian" -OrgName "POWER Engineers, Inc." -OrgUnitName "Operations IT" -State "ID" -SubjName "ucspe.powereng.com"
$certReq = Get-UcsCertRequest -Ucs $ucs -KeyRing $keyRing

# Create Trusted Point

Add-UcsTrustPoint -CertChain $rdcConfigurationData.pki_ca_chain -Name "new_TP" -Ucs $cdcUCS

"WebServer10YearSHA2WebEnrollment"
Get-Certificate -  # -Template "WebServer10YearSHA2WebEnrollment"

# Configure uplink ports

Start-UcsTransaction
$mo = Add-UcsManagedObject -ModifyPresent  -ClassId FabricEthLan -PropertyMap @{Dn="fabric/lan/A"; Id="A"; }
$mo_1 = $mo | Add-UcsUplinkPort -ModifyPresent -AdminSpeed "10gbps" -AdminState "enabled" -AutoNegotiate "yes" -EthLinkProfileName "default" -Fec "auto" -FlowCtrlPolicy "default" -Name "" -PortId 1 -SlotId 1 -UsrLbl ""
$mo_2 = $mo | Add-UcsUplinkPort -ModifyPresent -AdminSpeed "10gbps" -AdminState "enabled" -AutoNegotiate "yes" -EthLinkProfileName "default" -Fec "auto" -FlowCtrlPolicy "default" -Name "" -PortId 2 -SlotId 1 -UsrLbl ""
Complete-UcsTransaction



Start-UcsTransaction
$mo = Add-UcsManagedObject -ModifyPresent  -ClassId FabricEthLan -PropertyMap @{Dn="fabric/lan/B"; Id="B"; }
$mo_1 = $mo | Add-UcsUplinkPort -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -AutoNegotiate "yes" -EthLinkProfileName "default" -Fec "auto" -FlowCtrlPolicy "default" -Name "" -PortId 107 -SlotId 1 -UsrLbl ""
$mo_2 = $mo | Add-UcsUplinkPort -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -AutoNegotiate "yes" -EthLinkProfileName "default" -Fec "auto" -FlowCtrlPolicy "default" -Name "" -PortId 108 -SlotId 1 -UsrLbl ""
Complete-UcsTransaction


# Set LAN Cloud Best Effort QoS
Add-UcsManagedObject -ModifyPresent  -ClassId QosclassEthBE -PropertyMap @{Mtu="9216"; Dn="fabric/lan/classes/class-best-effort"; }

# Delete default server pool
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsServerPool -Name "default" -LimitScope | Remove-UcsServerPool
Complete-UcsTransaction

# Create UUID Suffix pool
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsUuidSuffixPool -Name "default" -LimitScope | Remove-UcsUuidSuffixPool
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsUuidSuffixPool -AssignmentOrder "sequential" -Name "UCSPE-UUID" -Prefix "DF88E734-D896-11EC"
$mo_1 = $mo | Add-UcsUuidSuffixBlock -From "3000-000000000001" -To "3000-000000000100"
Complete-UcsTransaction

# Delete SAN pools
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsWwnPool -Name "node-default" -LimitScope | Remove-UcsWwnPool
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsWwnPool -Name "default" -LimitScope | Remove-UcsWwnPool
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsIqnPoolPool -Name "default" -LimitScope | Remove-UcsIqnPoolPool
Complete-UcsTransaction

# Delete default MAC pool

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
$mo_1 = Get-UcsOrg -Level root | Get-UcsMacPool -Name "default" -LimitScope | Remove-UcsMacPool
Complete-UcsTransaction

# Create MAC Pool
Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsMacPool -AssignmentOrder "sequential" -Name "klbMAC"
$mo_1 = $mo | Add-UcsMacMemberBlock -From "00:25:B5:05:00:00" -To "00:25:B5:05:00:FF"
Complete-UcsTransaction

# Set User Label, Description and Asset Tag

Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsServiceProfile -ModifyPresent  -Descr "CDC-ESX-C2-B1" -Name "CDC-ESX-C2-B1" -UsrLbl "CDC-ESX-C2-B1"
$mo_1 = $mo | Add-UcsManagedObject -ModifyPresent  -ClassId LsServerExtension -PropertyMap @{AssetTag="48769"; }
Complete-UcsTransaction
