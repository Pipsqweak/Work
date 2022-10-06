#$rdcConfigurationData = Get-Content -Path ".\UCS\rdcConfig.json" | ConvertFrom-Json
#$rdcConfigurationData = Get-Content -Path ".\UCS\labConfig.json" | ConvertFrom-Json
#$rdcConfigurationData = Get-Content -Path ".\UCS\ucspe.json" | ConvertFrom-Json
$rdcConfigurationData = Get-Content -Path ".\UCS\ch3-rdc-ucs.json" | ConvertFrom-Json

# Need to fix up the embedded certificate chain
$rdcConfigurationData.pki_ca_chain = $rdcConfigurationData.pki_ca_chain -join "`n"

# Connect to the UCS manager for the RDC...
$rdcConfigurationData.ucsManager = $ch3UCS
$rdcConfigurationData.ucsManager = Connect-Ucs -Name $rdcConfigurationData.ucsManager -NotDefault

$Global:standardNetworkControlPolicyName = "STANDARD"
$Global:jumboFramesQosPolicyName = "JUMBOFRAMES"



ReportNotice ("Configuring UCS Manager: " -f @($rdcConfigurationData.ucsManager.Name))

# NOTES:  Did not set the Link Grouping Preference...
if (SetEquipmentGlobalPolicy -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tEquipment global policy set."
} `
else
{
    ReportError "`tFailed to set equipment global policy."
}

# NOTES: Set server ports...
if (SetUplinkPorts -ucs $rdcConfigurationData.ucsManager -uplinks $rdcConfigurationData.uplinkPorts)
{
    ReportSuccess "`tUplinks added."
} `
else
{
    ReportError "`tFailed to add uplinks."
}

if (DeleteDefaultServerPool -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tRemoved default server pool."
} `
else
{
    ReportError "`tFailed to remove default server pool."
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

if (DeleteSANPools -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tRemoved default SAN pools."
} `
else
{
    ReportError "`tFailed to remove default SAN pools."
}

if (SetLanCloudQoSBestEffortMTU -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tBest effort QoS MTU set."
} `
else
{
    ReportError "`tFailed to set best effort QoS MTU."
}

if (CreateBootPolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.bootPolicyName)
{
    ReportSuccess "`tBoot policy created (or validated)."
} `
else
{
    ReportError "`tFailed to create boot policy."
}

<#
    NOTE: Likely don't need to set the management interface addresses since we are already connected to it...
#>
if (SetManagementConfiguration -ucs $rdcConfigurationData.ucsManager -mgmtConfig $rdcConfigurationData.managementConfig)
{
    ReportSuccess "`tManagement configuration set."
} `
else
{
    ReportError "`tFailed to set management configuration."
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

if (DeleteDefaultMACPool -ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault MAC pool deleted."
} `
else
{
    ReportError "`tFailed to delete default MAC pool."
}

if (CreateMACPool -ucs $rdcConfigurationData.ucsManager -macPoolDefinition $rdcConfigurationData.macPool)
{
    ReportSuccess "`tMAC pool created."
} `
else
{
    ReportError "`tFailed to create MAC pool."
}

if(CreateDiskGroupConfigurationPolicy -Ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.diskGroupConfigurationPolicyName)
{
    ReportSuccess ("`tBuilt disk group configuration policy {0}." -f @((Quoted $rdcConfigurationData.diskGroupConfigurationPolicyName)))
    if(CreateStorageProfile -Ucs $rdcConfigurationData.ucsManager -profileName $rdcConfigurationData.storageProfileName -dgcPolicyName $rdcConfigurationData.diskGroupConfigurationPolicyName)
    {
        ReportSuccess ("`tBuilt storage profile {0}." -f @((Quoted $rdcConfigurationData.storageProfileName)))
    } `
    else
    {
        ReportError ("`tFailed to build disk group configuration policy {0}." -f @((Quoted $rdcConfigurationData.diskGroupConfigurationPolicyName)))
    }
} `
else
{
    ReportError ("`tFailed to build disk group configuration policy {0}." -f @((Quoted $rdcConfigurationData.diskGroupConfigurationPolicyName)))
}

if(DeleteDefaultScrubPolicy -Ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault scrub policy removed."
} `
else
{
    ReportError "`tFailed to remove the default scrub policy."
}

if(CreateScrubPolicy -ucs $rdcConfigurationData.ucsManager -policyName $rdcConfigurationData.scrubPolicyName)
{
    ReportSuccess ("`tCreated scrub policy: {0}." -f @($rdcConfigurationData.scrubPolicyName))
} `
else
{
    ReportError ("`tFailed to create scrub policy: {0}." -f @($rdcConfigurationData.scrubPolicyName))
}

if(DeleteDefaultNetworkControlPolicy -Ucs $rdcConfigurationData.ucsManager)
{
    ReportSuccess "`tDefault network control policy removed."
} `
else
{
    ReportError "`tFailed to remove the default network control policy."
}

if(CreateStandardNetworkControlPolicy -ucs $rdcConfigurationData.ucsManager -networkControlPolicyName $rdcConfigurationData.standardNetworkControlPolicyName)
{
    ReportSuccess "`tCreated standard network control policy."
} `
else
{
    ReportError "`tFailed to create standard network control policy: {0}."
}

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

<# TODO: Test against the lab. #>
<# Notes: ERROR:  Certificate request for keyring CH3-UCS01_CERT does not contain the request string. #>
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

# This will fail on UCS PE since we can't upload any firmware packages
if (CreateHostFirmarePackage -ucs $rdcConfigurationData.ucsManager -fwPackageName $rdcConfigurationData.firmwarePackage.Name -bladeBundleVersion $rdcConfigurationData.firmwarePackage.bladeBundleVersion -rackBundleVersion $rdcConfigurationData.firmwarePackage.rackBundleVersion)
{
    ReportSuccess "`tHost firmware package created."
} `
else
{
    # Nothing already reported an error
}


# Change this to "IntegrateWithAD"
#Create the LDAP providers
$a = 0
while($a -lt $rdcConfigurationData.ldapConfig.providerNames.Length)
{
    if(CreateLDAPProvider -ucs $rdcConfigurationData.ucsManager -ldapProviderName $rdcConfigurationData.ldapConfig.providerNames[$a] -baseDN $rdcConfigurationData.ldapConfig.baseDN -rootDN $rdcConfigurationData.ldapConfig.rootDN -bindKey $rdcConfigurationData.ldapConfig.bindKey -order ($a + 1))
    {
        ReportSuccess ("`tLDAP provider {0} created." -f @($rdcConfigurationData.ldapConfig.providerNames[$a]))
    } `
    else
    {
        # Nothing already reported an error
    }
    $a++
}
