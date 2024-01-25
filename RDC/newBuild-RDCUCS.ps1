<#
    Version 2 : Build post AT4

    NOTES:
        1. Make sure to run under Powershell 7.x
        2. Make sure $rdcConfigurationData.firmwarePackage is updated to the correct firmware packages before running starting.  You likely just upgraded the firmware...
        3. Make sure to create the FI port channels.
        4. Need to add: Add-UcsManagedObject -Ucs $at4UCS -ModifyPresent  -ClassId CommHttps -PropertyMap @{Dn="sys/svc-ext/https-svc"; AllowedSSLProtocols="tlsv1_2"; }
        5. Need to add backup configuration.

    Calgary: YYC01
    Seattle: SE4
    Chicago: CH3
    New York: NY7
    Las Vegas: LAS04
    Dallas: DA11
    Atlanta: AT4
#>

<#
    Steps:
        1. Log into UCS Manager
        2. Make sure blades are in the right slots
        3. Manually create DR login account
        4. ConnectTo ___, ucs
        5. Initialize powershell variables...
        6. SetManagementConfiguration
        7. Upgrade Firmware
        8. Reconnect to Ucs
        9. Reinitialize powershell variables
#>


# Source all the utility functions.
$rdcPrefix = "yyc01"

# Source in all the functions this script needs.
. .\RDC\RDCBuildUtilityFunctions.ps1

#region UCS Configuration...
$rdcConfigurationData = ConnectToUCS $rdcPrefix -Reconnect

ReportNotice ("Configuring UCS Manager: {0}" -f @($rdcConfigurationData.ucsManager.Name))

<#
    NOTES:
        1. Must be completed before the Trust point and key ring are created...
        2. Likely don't need to set the management interface addresses since we are already connected to it...
#>
if (SetManagementConfiguration -ucs $rdcConfigurationData.ucsManager -mgmtConfig $rdcConfigurationData.managementConfig)
{
    ReportSuccess "`tManagement configuration set."
} `
else
{
    ReportError "`tFailed to set management configuration."
}

$rdcConfigurationData = ConnectToUCS $rdcPrefix -Reconnect

# NOTE: Did not set the Link Grouping Preference...
#  Manually set equipment global policy | Chassis/FEX Discovery Policy | 2 Link, Port Channel
if (SetEquipmentGlobalPolicy -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tEquipment global policy set."
} `
else
{
    ReportError "`tFailed to set equipment global policy."
}

<# NOTES
        1. Set server ports (don't think I need to do this on a mini...)
        2. Create FI port channels
#>
if (SetUplinkPorts -ucs $rdcConfigurationData.ucsManager -uplinks $rdcConfigurationData.uplinkPorts)
{
    ReportSuccess "`tUplinks added."
} `
else
{
    ReportError "`tFailed to add uplinks."
}

<# Set port channels... #>

if (DeleteDefaultServerPool -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tRemoved default server pool."
} `
else
{
    ReportError "`tFailed to remove default server pool."
}

if (DeleteSANPools -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tRemoved default SAN pools."
} `
else
{
    ReportError "`tFailed to remove default SAN pools."
}

if (DeleteDefaultMACPool -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault MAC pool deleted."
} `
else
{
    ReportError "`tFailed to delete default MAC pool."
}

if(DeleteDefaultScrubPolicy -Ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault scrub policy removed."
} `
else
{
    ReportError "`tFailed to remove the default scrub policy."
}

if(DeleteDefaultNetworkControlPolicy -Ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault network control policy removed."
} `
else
{
    ReportError "`tFailed to remove the default network control policy."
}

if (CreateUUIDSuffixPool -ucs $rdcConfigurationData.ucsManager -uuidSuffixPoolStart $rdcConfigurationData.uuidSuffixPoolStart)
{
    ReportSuccess "`tCreated UUID suffix pool."
} `
else
{
    ReportError "`tFailed to create UUID pool."
}

if (CreateJumboFramesQoSPolicy -ucs $rdcConfigurationData.ucsManager -qosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName)
{
    ReportSuccess "`tCreated JUMBOFRAMES QoS policy."
} `
else
{
    ReportError "`tFailed to create JUMBOFRAMES QoS policy."
}

if (CreateBootPolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.bootPolicyName)
{
    ReportSuccess "`tBoot policy created (or validated)."
} `
else
{
    ReportError "`tFailed to create boot policy."
}

if (CreateUCSVlans -ucs $rdcConfigurationData.ucsManager -vlanDefinitions $rdcConfigurationData.vlans -createMissingVLANs)
{
    ReportSuccess "`tVLANs created."
} `
else
{
    ReportError "`tFailed to create VLANs."
}

if (CreateUCSVlanGroups -ucs $rdcConfigurationData.ucsManager -vlanGroupDefinitions $rdcConfigurationData.vlanGroups -createMissingVLANGroups -updateVLANGroupMembers)
{
    ReportSuccess "`tVLAN Groups created."
} `
else
{
    ReportError "`tFailed to create VLAN groups."
}

if (CreateMACPool -ucs $rdcConfigurationData.ucsManager -macPoolDefinition $rdcConfigurationData.macPool)
{
    ReportSuccess "`tMAC pool created."
} `
else
{
    ReportError "`tFailed to create MAC pool."
}

# First the disk group configuration policy...
<#
    NOTES:
        Threw an exception configuring DA11.  Seemed to work, but...
        Need to be wrapped in a transaction
#>
if(CreateDiskGroupConfigurationPolicy -Ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.diskGroupConfigurationPolicyName)
{
    ReportSuccess ("`tBuilt disk group configuration policy {0}." -f @($rdcConfigurationData.diskGroupConfigurationPolicyName))
} `
else
{
    ReportError ("`tFailed to build disk group configuration policy {0}." -f @($rdcConfigurationData.diskGroupConfigurationPolicyName))
}

# Then the storage profile...
if(CreateStorageProfile -Ucs $rdcConfigurationData.ucsManager -profileName $rdcConfigurationData.storageProfileName -dgcPolicyName $rdcConfigurationData.diskGroupConfigurationPolicyName)
{
    ReportSuccess ("`tBuilt storage profile {0}." -f @($rdcConfigurationData.storageProfileName))
} `
else
{
    ReportError ("`tFailed to build disk group configuration policy {0}." -f @($rdcConfigurationData.diskGroupConfigurationPolicyName))
}

if(CreateScrubPolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.scrubPolicyName)
{
    ReportSuccess ("`tCreated scrub policy: {0}." -f @($rdcConfigurationData.scrubPolicyName))
} `
else
{
    ReportError ("`tFailed to create scrub policy: {0}." -f @($rdcConfigurationData.scrubPolicyName))
}

if(CreateStandardNetworkControlPolicy -ucs $rdcConfigurationData.ucsManager -networkControlPolicyName $rdcConfigurationData.standardNetworkControlPolicyName)
{
    ReportSuccess "`tCreated standard network control policy."
} `
else
{
    ReportError "`tFailed to create standard network control policy: {0}."
}

# Easier to splat these ...
$ipAddressBlockParams = @{
    ucs = $rdcConfigurationData.ucsManager
    ipPoolName = $rdcConfigurationData.ipPool.name
    fromAddress = $rdcConfigurationData.ipPool.from
    toAddress = $rdcConfigurationData.ipPool.to
    subnetMask = $rdcConfigurationData.ipPool.subnetMask
    primaryDNS = $rdcConfigurationData.ipPool.primaryDNS
    secondaryDNS = $rdcConfigurationData.ipPool.secondaryDNS
    defaultGateway = $rdcConfigurationData.ipPool.defaultGateway
}

if(CreateIPBlock @ipAddressBlockParams)
{
    # TRUE
    ReportSuccess ("`tAdded IP address block {0} - {1} to IP pool {2}." -f @($rdcConfigurationData.ipPool.from, $rdcConfigurationData.ipPool.to, $rdcConfigurationData.ipPool.name))
} `
else # NOT (CreateIPBlock @ipAddressBlockParams)
{
    # FALSE

    ReportError ("`tFailed to add IP address block {0} - {1} to IP pool {2}." -f @($rdcConfigurationData.ipPool.from, $rdcConfigurationData.ipPool.to, $rdcConfigurationData.ipPool.name))
}

if (CreateMaintenancePolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.maintenancePolicyName)
{
    # TRUE

    ReportSuccess ("`tCreated {0} maintenance policy." -f @($rdcConfigurationData.maintenancePolicyName))
} `
else # NOT (CreateMaintenancePolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.maintenancePolicyName)
{
    # FALSE

    ReportError ("`tFailed to create maintenance policy {0}." -f @($rdcConfigurationData.maintenancePolicyName))
}

if (CreateBIOSPolicy -ucs $rdcConfigurationData.ucsManager -biosPolicy $rdcConfigurationData.BIOSPolicy)
{
    # TRUE

    ReportSuccess ("`tCreated {0} BIOS policy." -f @($rdcConfigurationData.BIOSPolicy.Name))
} `
else # NOT (CreateBIOSPolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.BIOSPolicy)
{
    # FALSE

    ReportError ("`tFailed to create BIOS policy.")
}

# Trust Point, Key ring, and Certificate.  Completed after systems management configuration is set.
if(CreateTrustPoint -Ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tCreated trust point: PEI_CA2_TP"
} `
else
{
    ReportError ("`tFailed to create trust point PEI_CA2_TP.")
}

<#
    NOTES:
        1. Test against the lab.
        2. Need to figure this out:  ERROR:  Certificate request for keyring CH3-UCS01_CERT does not contain the request string.
        3. Subject and DNS name cannot be the same.  Code changed to set subject to base host name with domain.
#>
# Still does not work after AT4...needs a delay...Added the delay to CreateKeyRing, but it's not tested yet.

# Send the SAN attribute string to the clipboard.
"san:dns={0}&dns={1}" -f ($rdcConfigurationData.ucsManager.Name.Tolower(), $rdcConfigurationData.ucsManager.Name.Tolower().Replace(".powereng.com","")) | Set-Clipboard

if(CreateKeyRing -ucs $rdcConfigurationData.ucsManager -location $rdcConfigurationData.keyring.location -state $rdcConfigurationData.keyring.state -country $rdcConfigurationData.keyring.country)
{
    ReportSuccess "`tCreated keyring."
} `
else
{
    ReportError ("`tFailed to create keyring.")
}

if (CreatevNICTemplates -ucs $rdcConfigurationData.ucsManager -vNICTemplateDefinitions $rdcConfigurationData.vNICTemplates -macPoolName $rdcConfigurationData.macPool.name -networkControlPolicyName $rdcConfigurationData.standardNetworkControlPolicyName -jumboFramesQosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName)
{
    ReportSuccess "`tvNIC Templates created."
} `
else
{
    ReportError "`tFailed to create vNIC Templates."
}

if (CreatePowerControlPolicy -ucs $rdcConfigurationData.ucsManager -powerControlPolicyName $rdcConfigurationData.powerControlPolicyName)
{
    ReportSuccess "`tPower control policy created."
} `
else
{
    # Nothing already reported an error
}

if (CreateSerialOverLANPolicy -ucs $rdcConfigurationData.ucsManager -solPolicyName $rdcConfigurationData.serialOverLANPolicyName)
{
    ReportSuccess "`tSerial over LAN policy created."
} `
else
{
    # Nothing already reported an error
}

<#
    NOTES:
        1. This will fail on UCS PE since we can't upload any firmware packages
        2. Make sure $rdcConfigurationData.firmwarePackage is updated to the correct firmware packages before running.
        3. Make sure firmware version is installed on UCS
#>
#
if (CreateHostFirmarePackage -ucs $rdcConfigurationData.ucsManager -fwPackageName $rdcConfigurationData.firmwarePackage.Name -bladeBundleVersion $rdcConfigurationData.firmwarePackage.bladeBundleVersion -rackBundleVersion $rdcConfigurationData.firmwarePackage.rackBundleVersion)
{
    ReportSuccess "`tHost firmware package created."
} `
else
{
    # Nothing already reported an error
}

if (SetLanCloudQoSBestEffortMTU -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tBest effort QoS MTU set."
} `
else
{
    ReportError "`tFailed to set best effort QoS MTU."
}

if (UpdateDefaultMaintenancePolicy -ucs $rdcConfigurationData.ucsManager)
{
    # TRUE

    ReportSuccess ("`tUpdated default maintenance policy.")
} `
else # NOT (UpdateDefaultMaintenancePolicy -ucs $rdcConfigurationData.ucsManager)
{
    # FALSE

    ReportError ("`tFailed to update default maintenance policy.")
}

#Create the LDAP providers
<#
    NOTES:

    *******************************************************************************************
        Make sure to set $rdcConfigurationData.ldapConfig.bindKey (srvcldap password)
    *******************************************************************************************
#>
if(CreateLDAPProvider -ucs $rdcConfigurationData.ucsManager -ldapConfig $rdcConfigurationData.ldapConfig)
{
    ReportSuccess "`tLDAP authentication configured."
} `
else
{
    # Nothing already reported an error
}

$rootOrg = Get-UcsOrg -Ucs $rdcConfigurationData.ucsManager -Level "root"
$uuidSuffixPoolName = "{0}-UUID" -f @($rdcConfigurationData.ucsManager.Name.Replace(".powereng.com","").ToUpper())

<#
    Internal Service Profile Template
#>

# Create the service profile template
$serviceProfileTemplate = Add-UcsServiceProfile -Ucs $rdcConfigurationData.ucsManager -Org $rootOrg -BiosProfileName $rdcConfigurationData.BIOSPolicy.Name -BootPolicyName $rdcConfigurationData.bootPolicyName -HostFwPolicyName "Latest" -IdentPoolName $uuidSuffixPoolName -MaintPolicyName $rdcConfigurationData.maintenancePolicyName -Name "VMWare.Int.M2" -PowerPolicyName $rdcConfigurationData.powerControlPolicyName -ScrubPolicyName $rdcConfigurationData.scrubPolicyName -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName -Type "updating-template"

$mo_1 = Add-UcsLogicalStorageProfileBinding -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -StorageProfileName $rdcConfigurationData.storageProfileName

# Add the vNIC templates (First the secondary vNIC, then the primary -- secondary must exist prior to referencing it when creating the primary. )
$mo_2 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "VMNMGT.INT.BA" -NwTemplName "VMNMGT.INT.BA" -SwitchId "B-A" -Order "2" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -NwCtrlPolicyName "" -PinToGroupName "" -StatsPolicyName "default" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName
$mo_3 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "MGTVMN.INT.AB" -NwTemplName "MGTVMN.INT.AB" -SwitchId "A-B" -Order "1"
$mo_4 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "STG.INT.BX"    -NwTemplName "STG.INT.BX"    -SwitchId "A"   -Order "4" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -NwCtrlPolicyName "" -PinToGroupName "" -StatsPolicyName "default" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName
$mo_5 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "STG.INT.AX"    -NwTemplName "STG.INT.AX"    -SwitchId "B"   -Order "3"
$mo_6 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "GST.INT.BX"    -NwTemplName "GST.INT.BX"    -SwitchId "B"   -Order "6" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 1500 -NwCtrlPolicyName "" -PinToGroupName "" -StatsPolicyName "default" -QosPolicyName ""
$mo_7 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "GST.INT.AX"    -NwTemplName "GST.INT.AX"    -SwitchId "A"   -Order "5"

$mo_8 = Add-UcsVnicFcNode -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Addr "pool-derived" -IdentPoolName "node-default"
$mo_9 = Add-UcsVnicDefBeh -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Action "none" -Descr "" -Name "" -NwTemplName "" -PolicyOwner "local" -Type "vhba"

# Set the vNIC placement...
$mo_10 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "1" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_11 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "2" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_12 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "3" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_13 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "4" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_14 = $serviceProfileTemplate  | Set-UcsServerPower -State "admin-up" -Force -Confirm:$false


<#
    DMZ Service Profile Template
#>
$serviceProfileTemplate = Add-UcsServiceProfile -Ucs $rdcConfigurationData.ucsManager -Org $rootOrg -BiosProfileName $rdcConfigurationData.BIOSPolicy.Name -BootPolicyName $rdcConfigurationData.bootPolicyName -HostFwPolicyName "Latest" -IdentPoolName $uuidSuffixPoolName -MaintPolicyName $rdcConfigurationData.maintenancePolicyName -Name "VMWare.DMZ.M2" -PowerPolicyName $rdcConfigurationData.powerControlPolicyName -ScrubPolicyName $rdcConfigurationData.scrubPolicyName -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName -Type "updating-template"
$mo_1 = Add-UcsLogicalStorageProfileBinding -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -StorageProfileName $rdcConfigurationData.storageProfileName

$mo_2 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "VMNMGT.DMZ.BA" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -NwCtrlPolicyName "" -NwTemplName "VMNMGT.DMZ.BA" -Order "2" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
$mo_3 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "MGTVMN.DMZ.AB" -NwTemplName "MGTVMN.DMZ.AB" -Order "1" -SwitchId "A-B"
$mo_4 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "STG.DMZ.BX"    -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -NwCtrlPolicyName "" -NwTemplName "STG.DMZ.BX" -Order "4" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
$mo_5 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "STG.DMZ.AX"    -NwTemplName "STG.DMZ.AX" -Order "3"
$mo_6 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "GST.DMZ.BX"    -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 1500 -NwCtrlPolicyName "" -NwTemplName "GST.DMZ.BX" -Order "6" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_7 = Add-UcsVnic -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -AdaptorProfileName "VMWare" -Name "GST.DMZ.AX"    -NwTemplName "GST.DMZ.AX" -Order "5"

$mo_8 = Add-UcsVnicFcNode -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Addr "pool-derived" -IdentPoolName "node-default"
$mo_9 = Add-UcsVnicDefBeh -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Action "none" -Descr "" -Name "" -NwTemplName "" -PolicyOwner "local" -Type "vhba"

$mo_10 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "1" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_11 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "2" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_12 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "3" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_13 = Add-UcsFabricVCon -Ucs $rdcConfigurationData.ucsManager -ServiceProfile $serviceProfileTemplate -ModifyPresent -Fabric "NONE" -Id "4" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_14 = $serviceProfileTemplate | Set-UcsServerPower -State "admin-up" -Force -Confirm:$false

# UCSUtilites for Service profiles...


#endregion

#region VMware Configuration

<#
    NOTES:
        Remember to change ESXi host serial numbers in .json files.
        Make sure you are connected to UCS and CDOT
        Make sure to set $virtualizationDefinition.ucsManager =
#>


# $virtualizationDefinition = (Get-Content -Path (".\RDC\configs\VMware\{0}-internal-v3.json" -f @($rdcPrefix))) | ConvertFrom-Json
# $virtualizationDefinition = (Get-Content -Path (".\RDC\configs\VMware\{0}-dmzv3.json" -f @($rdcPrefix))) | ConvertFrom-Json


$viServer = $vCenter
$doReportSuccess = $true
$ucs = $rdcConfigurationData.ucsManager
$Global:ucsData = $null
$DoIt = $true

# Credentials to join ESXi hosts to AD
$adCreds = Get-Credential -Message "Provide credentials to join ESXi host(s) to domain in the form: user@domain.name.net."

# Set the UCS Manager.
$virtualizationDefinition.ucsManager = $rdcConfigurationData.ucsManager

$viServer = $vCenter
$datacenter = Get-vSphereDatacenter -viServer $viServer -Name $virtualizationDefinition.datacenterName -createMissing
if ($null -ne $datacenter)
{
    $cluster = Get-vSphereCluster -viServer $viServer -Name $virtualizationDefinition.vSphereClusterName -Location $datacenter.Name -createMissing
    if ($null -ne $cluster)
    {
        # Initially disable cluster services.  -- If this is a new datacenter...
        Set-vSpherevCLSOnCluster -viServer $viServer -Name $virtualizationDefinition.vSphereClusterName -Disable

        $a = 0
        while($a -lt $virtualizationDefinition.hosts.Length)
        {
            $vmHost = Get-vSphereHost -viServer $viServer -Name $virtualizationDefinition.hosts[$a].vmHostName -addMissing -ClusterName $virtualizationDefinition.vSphereClusterName
            $a++
        }
    } `
    else # NOT ($null -ne $cluster)
    {
        # Nothing - Already reported an error
    }
} `
else # NOT ($null -ne $datacenter)
{
    # Nothing - Already reported an error
}

$newVDS = CreateVDS -viServer $viServer -datacenterName $virtualizationDefinition.datacenterName -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess
if ($null -ne $newVDS)
{
    if (CreatePortGroups -viServer $viServer -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
    {
        if (AddHostsToVDS -viServer $viServer -datacenterName $virtualizationDefinition.datacenterName -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
        {
            <# NOTE:
                Ensure connection to UCS us active
                Make sure to set: $virtualizationDefinition.ucsManager = $ucsManagers[$rdcUCSName]
                make sure to reset: $Global:ucsData = $null
            #>
            if (MigrateHostsVMNICsToVDS -viServer $viServer -ucs $virtualizationDefinition.ucsManager -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -ExcludevmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
            {
                if (MigrateHostsVMKsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                {
                    if (MigrateHostsVMNICsToVDS -viServer $viServer -ucs $virtualizationDefinition.ucsManager -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -OnlyvmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                    {
                        <#
                            NOTES:
                                Make sure hosts are in maintenance mode, or local datastores will not be removed.
                        #>
                        $a = 0
                        while($a -lt $virtualizationDefinition.hosts.Length)
                        {
                            RemoveVMHostStdSwitches -viServer $viServer -vmHostName $virtualizationDefinition.hosts[$a].vmHostName

                            RemoveVMHostLocalDatastores -viServer $viServer -vmHostName $virtualizationDefinition.hosts[$a].vmHostName

                            <#
                                NOTES: Update function so it does not prompt for ADCreds...
                            #>
                            UpdateESXiAdvSettings -viServer $viServer -vmHostName $virtualizationDefinition.hosts[$a].vmHostName
                            # UpdateESXiAdvSettings -viServer $viServer -vmHostName $virtualizationDefinition.hosts[$a].vmHostName -JoinAD -ADCreds $adCreds
                            $a++
                        }

                        <#
                            NOTE: Make sure $cDot contains a connection to Netapp.
                        #>
                        if (MountDatastoresToHosts -viServer $viServer -datastores $virtualizationDefinition.datastores -hostDefs $virtualizationDefinition.hosts -cDot $cDot -doReportSuccess:$doReportSuccess)
                        {

                        } `
                        else # NOT (MountDatastoresToESXiHosts -viServer $viServer -datastores $virtualizationDefinition.datastores -hosts $virtualizationDefinition.hosts -cDot $cDot -doReportSuccess:$doReportSuccess)
                        {
                            ReportError "Failed to mount datastores to hosts."
                        }
                    }
                    else # NOT (MigrateVMNICsToVDS -viServer $viServer -ucs $virtualizationDefinition.ucsManager -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -OnlyvmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                    {
                        ReportError ("Failed to migrate vmnic0 to {0}." -f @($virtualizationDefinition.switch.name))
                    }
                }
                else # NOT (MigrateVMKsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                {
                    ReportError ("Failed to migrate any/all VMKs to {0}." -f @($virtualizationDefinition.switch.name))
                }
            }
            else # NOT (MigrateVMNICsToVDS -viServer $viServer -ucs $virtualizationDefinition.ucsManager -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -ExcludevmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
            {
                ReportError ("Failed to migrate any/all VMNICs to {0}." -f @($virtualizationDefinition.switch.name))
            }
        }
        else # NOT (AddVMHostsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
        {
            ReportError ("Failed to add VM hosts to {0}." -f @($virtualizationDefinition.switch.name))
        }
    }
    else # NOT (CreatePortGroups -viServer $viServer -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
    {
        ReportError ("Failed to add port groups to {0}." -f @($virtualizationDefinition.switch.name))
    }
}
else # NOT ($null -ne $newVDS)
{
    ReportError ("Failed to create new distributed switch {0}." -f @($virtualizationDefinition.switch.name))
}

# When everything is done...
#   Enable cluster services.
Set-vSpherevCLSOnCluster -viServer $viServer -Name $virtualizationDefinition.vSphereClusterName -Enable



#endregion
