
# $virtualizationDefinition = Get-Content -Path ".\VMware\configs\cdcDMZv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\configs\cdcInternalv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\configs\cdcInternalv3.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMware\configs\ddcInternalv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\configs\ddc-vdivcadv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\configs\ddcDMZv3.json" | ConvertFrom-Json

# $virtualizationDefinition = Get-Content -Path ".\RDC\configs\VMware\ny7-internal-v3.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\configs\ny7-dmzv3.json" | ConvertFrom-Json

<#

Verified: 20220629 Using DDC Internal vDS 01

The functions in this file are used to configure ESXi hosts, distributed switches and datastores for the RDC vSphere Clusters.

Some assumptions:
    1. The UCS blades have been configured in UCS Manager.
        a. There are 2 vNICs available for management.
    2. The ESXi hosts are in a default configuration.  Meaning:
        a. They have just been built
        b. Just not been added to vCenter
        c. vmk0 and vmnic0 are attached to vSwitch0 (the default standard switch created while installing ESXi)
            1) The management address assigned to the ESXi host matches the address assigned to vmk0 in the configuration file.
    3. The ESXi hosts have already be placed at or below the same container the distributed switch belows to.

The configuration of the distributed switch is based on the contents of a .JSON file.

    Top level elements:
        switchName     - The name to be assigned to the new distributed switch
        containerName  - The name of the cluster or datacenter where the distributed switch will be created.
        mtu            - The default MTU for the distributed switch
        version        - The version of distributed switch to create
        uplinkMappings - An array of uplink mappings
        portGroups     - An array of distributed port group definitions
        connectedHosts - An array defining what UCS blades/ESXi hosts are to be added to the distributed switch

    Uplink Mappings:
        uplinkName - The name representing the uplink on the distributed switch in vCenter
        vNICName   - The name assigned to the vNIC within UCS Manager

    Port Group definitions:
        vlanID             - The VLAN ID for the port group (1 - 4094)
        name               - The name of the port group
        portBinding        - The port binding for the port group (Ephemeral or Static)
        activeUplinkNames  - An array of uplink names representing the active uplinks for the port group (There must be an uplinkMapping with a matching uplinkName)
        standbyUplinkNames - An array of uplink names representing the standby uplinks for the port group (There must be an uplinkMapping with a matching uplinkName)

        *** NOTE ***  When the port groups are created, any uplink named in uplinkMappings that are not included in activeUplinkNames or standbyUplinkNames will be added to the
                      port group's 'Unused uplinks'

    Connected hosts:
        serial     - The serial number of the blade as it appears in UCS Manager
        vmHostName - The name of the ESXi host from vCenter
        vmks       - An array of VM kernel adapters for the VM host

    VM Kernel adapters:
        vmkName        - The name of the VMK
        mtu            - The MTU for the VMK
        portGroupName  - The name of the port group the VMK will be assigned to (There must be a port group defined with a matching name)
        ipAddress      - The IP address to assign to the VMK
        subnetMask     - The subnet mask for the VMK
        mgmtEnabled    - true if the VMK will be used for management, otherwise false
        vMotionEnabled - true if the VMK will be used for vMotion, otherwise false

Validation of the configuration is completed as follows.  Please note, when possible, validation continues even if an issue is found.  This is to facilitate multiple corrections to the
configuration file without the need to recheck the configuration for each issue.

    1. Details about the UCS blades, vNICs and VLANs are collected from UCS manager to be used in validating the rest of the configuration.
    2. Verify the configuration contains a name for the distributed switch.
    3. Verify there is not an existing distributed switch with a matching name.  NOTE: This name must be unique on the vCenter server.
    4. Verify a container name for the distributed switch is provided.
    5. Verify the container exists in vCenter.
    6. Verify a non-empty version for the distributed switch is provided.
    7. Verify a positive integer value has been provided for MTU.  NOTE: Only 1500 or 9000 with result in a success, any other positive value is valid, but a warning is issued.
    8. Verify each of the uplink mappings.
        a. Verify the mapping contains an uplinkName
        b. Verify the uplinkName is unique
        c. Verify the mapping contains a vNICName
        d. Verify the vNICName is unique
    9. Verify each of the port groups.
        a. Verify the port group contains a name
        b. Verify the name is unique for the switch
        c. Verify the port binding is provided and is Ephemeral or Static
        d. Verify the a VLAN ID has been specified and is valid (1 - 4094)
        e. Verify active uplinks have been provided (even if it is an empty array)
        f. Verify standby uplinks have been proviced (even if it is an empty array)
        g. Verify each active uplink
            1) Verify a non-empty uplink name has been provided
            2) Verify the uplink name is unique
            3) Verify the uplink name has not also been listed as a standby uplink
            4) Verify the uplink name exists in uplinkMappings
        h. Verify each standby uplink
            1) Verify a non-empty uplink name has been provided
            2) Verify the uplink name is unique
            3) Verify the uplink name has not also been listed as an active uplink
            4) Verify the uplink name exists in uplinkMappings
    10. Verify each connected host
        a. Verify a non-empty VM host name has been provided
        b. Verify a matching ESXi host can be found at or below the same container as the distributed switch
        c. Verify a non-empty serial number has been provided for the compute node
        d. Verify a compute node with a matching serial number can be found in UCS Manager
        e. Verify the UCS compute node has vNICs defined for each vNICName list in uplinkMappings
        f. Verify the hosts VMKs
            1) Verify the VMKs port group exists in the list of port groups for the distributed switch
            2) Verify the VMK name matches: "^vmk\d+$"
                a) Report whether the VMK will be migrated or created
            3) Verify the VMK has a valid value for MTU.  Same here as for the distributed switch
                a) Verify the VMK's MTU matches it's uplink's MTU (Only a warning if the MTUs do not match)
            4) Verify an IP address is provided for the VMK
                a) Verify the IP is a valid IP address.  No VLAN correlation is done.  [System.Net.IPAddress]::Parse
            5) Verify a subnet mask is provided for the VMK
                a) Verify the subnet mask is a valid IP address.
            6) Verify a value for mgmtEnabled has been provided and is true or false
            7) Verify a value for vMotionEnabled has been provided and is true or false


#>

$Global:validDistributedSwitchVersions = @(
    @{DSVersion = "7.0.3"; ESXiVersion = "7.0.3" },
    @{DSVersion = "7.0.2"; ESXiVersion = "7.0.2" },
    @{DSVersion = "7.0.0"; ESXiVersion = "7.0" },
    @{DSVersion = "6.6.0"; ESXiVersion = "6.7" },
    @{DSVersion = "6.5.0"; ESXiVersion = "6.5" }
)



<#
    TODO:  Needs significant re-working.
#>
function ValidateSwitchDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $doReportSuccess
    )

    $definitionIsValid = $true

    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $ucs)
            {
                # TRUE

                if ($null -eq $Global:ucsData)
                {
                    # TRUE

                    GetUCSData -ucs $ucs -doReportSuccess:$doReportSuccess
                }
                else # NOT ($null -eq $Global:ucsData)
                {
                    # FALSE

                    # Nothing.
                }

                if ($null -ne $Global:ucsData)
                {
                    # TRUE

                    #region    Check the switch definition
                    if ($null -ne $dsConfig)
                    {
                        # TRUE

                        #region Check the switch name
                        if (-not [String]::IsNullOrEmpty($dsConfig.name))
                        {
                            # TRUE

                            $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.switchName -ErrorAction SilentlyContinue

                            if ($null -eq $vds)
                            {
                                # TRUE

                                if($doReportSuccess)
                                {
                                    ReportSuccess ("Distributed switch {0} does not exist." -f @($dsConfig.name))
                                }
                            }
                            else # NOT ($null -ne $vds)
                            {
                                # FALSE

                                ReportError ("Distributed switch {0} already exists under {1}." -f @($vds.Name, $vds.Datacenter.Name))
                                $definitionIsValid = $false
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsConfig.switchName))
                        {
                            # FALSE

                            ReportError ("Missing distrubuted switch name.")
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region Check the switch container
                        if (-not [String]::IsNullOrEmpty($dsConfig.containerName))
                        {
                            # TRUE

                            $container = Get-Inventory -Server $viServer -Name $dsConfig.containerName -ErrorAction SilentlyContinue

                            if ($null -ne $container)
                            {
                                # TRUE

                                if($doReportSuccess)
                                {
                                    ReportSuccess ("Container {0} exists." -f @($dsConfig.containerName))
                                }
                            }
                            else # NOT ($null -ne $container)
                            {
                                # FALSE

                                ReportError ("Container {0} does not exist." -f @($dsConfig.containerName))
                                $definitionIsValid = $false
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsConfig.containerName))
                        {
                            # FALSE

                            ReportError ("Missing distributed switch container name.")
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region    Check the distributed switch version
                        if (-not [String]::IsNullOrEmpty($dsConfig.version))
                        {
                            # TRUE

                            if($doReportSuccess)
                            {
                                ReportSuccess ("Distributed switch version {0}." -f @($dsConfig.version))
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsConfig.version))
                        {
                            # FALSE

                            ReportError ("Missing distrubuted switch version.")
                        }
                        #endregion Check the distributed switch version

                        #region Check MTU
                        if ($null -ne $dsConfig.mtu)
                        {
                            # TRUE

                            if ($dsConfig.mtu -match "^\d+$")
                            {
                                # TRUE

                                if ($dsConfig.mtu -in @(1500,9000))
                                {
                                    # TRUE

                                    if($doReportSuccess)
                                    {
                                        ReportSuccess ("Switch MTU: {0} is valid." -f @($dsConfig.mtu))
                                    }
                                }
                                else # NOT ($dsConfig.mtu -in @(1500,9000))
                                {
                                    # FALSE

                                    if ($dsConfig.mtu -gt 0)
                                    {
                                        # TRUE

                                        ReportWarning ("Check switch MTU value: {0}." -f @($dsConfig.mtu))
                                    }
                                    else # NOT ($dsConfig.mtu -gt 0)
                                    {
                                        # FALSE

                                        ReportError ("Switch MTU value {0} is invalid." -f @($dsConfig.mtu))
                                        $definitionIsValid = $false
                                    }
                                }
                            }
                            else # NOT ($dsConfig.mtu -match "^\d+$")
                            {
                                # FALSE

                                ReportError ("Switch MTU value {0} is invalid." -f @($dsConfig.mtu))
                                $definitionIsValid = $false
                            }
                        }
                        else # NOT ($null -ne $dsConfig.mtu)
                        {
                            # FALSE

                            ReportError "Missing switch MTU in distributed switch definition."
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region    Check all the uplink mappings
                        if ($null -ne $dsConfig.uplinkMappings)
                        {
                            # TRUE

                            if ($dsConfig.uplinkMappings -isnot [Array])
                            {
                                # TRUE

                                $dsConfig.uplinkMappings = @($dsConfig.uplinkMappings)
                                ReportWarning ("Check switch uplink mappings.")
                            }
                            else # NOT ($dsConfig.uplinkMappings -isnot [Array])
                            {
                                # FALSE

                                # Nothing
                            }

                            $a = 0
                            while($a -lt $dsConfig.uplinkMappings.Length)
                            {
                                #region Check the uplink name.
                                if (-not [String]::IsNullOrEmpty($dsConfig.uplinkMappings[$a].uplinkName))
                                {
                                    # TRUE

                                    if (@($dsConfig.uplinkMappings | Select-Object -ExpandProperty uplinkName | Where-Object { $_ -eq $dsConfig.uplinkMappings[$a].uplinkName}).Length -eq 1)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Uplink {0} is valid." -f @($dsConfig.uplinkMappings[$a].uplinkName))
                                        }
                                    }
                                    else # NOT (@($dsConfig.uplinkMappings | Select-Object -ExpandProperty uplinkName | Where-Object { $_ -eq $dsConfig.uplinkMappings[$a].uplinkName}).Length -gt 1)
                                    {
                                        # FALSE

                                        ReportError ("Multiple definitions for uplink {0} [idx: {1}]" -f @($dsConfig.uplinkMappings[$a].uplinkName, ($a + 1)))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig.uplinkMappings[$a].uplinkName))
                                {
                                    # FALSE

                                    ReportError ("Missing value for uplink mapping #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion

                                #region Check the vNIC name.
                                if (-not [String]::IsNullOrEmpty($dsConfig.uplinkMappings[$a].vNICName))
                                {
                                    # TRUE

                                    if (@($dsConfig.uplinkMappings | Select-Object -ExpandProperty vNICName | Where-Object { $_ -eq $dsConfig.uplinkMappings[$a].vNICName}).Length -ge 1)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("vNIC {0} is valid." -f @($dsConfig.uplinkMappings[$a].vNICName))
                                        }
                                    }
                                    else # NOT (@($dsConfig.uplinkMappings | Select-Object -ExpandProperty vNICName | Where-Object { $_ -eq $dsConfig.uplinkMappings[$a].vNICName}).Length -ge 1)
                                    {
                                        # FALSE

                                        ReportError ("No vNIC definition found for {0}" -f @($dsConfig.uplinkMappings[$a].vNICName))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig.uplinkMappings[$a].vNICName))
                                {
                                    # FALSE

                                    ReportError ("Missing value for vNIC name #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion

                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsConfig.uplinkMappings)
                        {
                            # FALSE

                            ReportError "Missing distributed switch definition uplink mappings."
                            $definitionIsValid = $false

                            # Make $dsConfig.uplinkMappings and empty array so later logic will work
                            $dsConfig.uplinkMappings = @()
                        }
                        #endregion Check all the uplink mappings

                        #region    Check port groups
                        if ($null -ne $dsConfig.portGroups)
                        {
                            # TRUE

                            if ($dsConfig.portGroups -isnot [Array])
                            {
                                # TRUE

                                $dsConfig.portGroups = @($dsConfig.portGroups)
                                ReportWarning ("Check switch port groups.")
                            }
                            else # NOT ($dsConfig.portGroups -isnot [Array])
                            {
                                # FALSE

                                # Nothing
                            }

                            $a = 0
                            while($a -lt $dsConfig.portGroups.Length)
                            {
                                #region    Check the port group name.
                                if (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].name))
                                {
                                    # TRUE

                                    if (@($dsConfig.portGroups | Select-Object -ExpandProperty name | Where-Object { $_ -eq $dsConfig.portGroups[$a].name}).Length -eq 1)
                                    {
                                        # TRUE

                                        try
                                        {
                                            $otherVPGs = Get-VirtualPortGroup -Name $dsConfig.portGroups[$a].name -Datacenter $dsConfig.containerName -ErrorAction Stop
                                            ReportError ("Port group {0} is invalid.  There is an other port group with the same name in {1}." -f @($dsConfig.portGroups[$a].name, $dsConfig.containerName))
                                        }
                                        catch
                                        {
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Port group {0} is valid." -f @($dsConfig.portGroups[$a].name))
                                            }
                                        }
                                    }
                                    else # NOT (@($dsConfig.portGroups | Select-Object -ExpandProperty name | Where-Object { $_ -eq $dsConfig.portGroups[$a].name}).Length -eq 1)
                                    {
                                        # FALSE

                                        ReportError ("Multiple definitions for port group {0} [idx: {1}]" -f @($dsConfig.portGroups[$a].name, ($a + 1)))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig..portGroups[$a].name))
                                {
                                    # FALSE

                                    ReportError ("Missing value for port group name #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion Check the port group name.

                                #region    Check the port group port binding.
                                if ($dsConfig.portGroups[$a].portBinding -match "^STATIC|EPHEMERAL$")
                                {
                                    # TRUE

                                    if($doReportSuccess)
                                    {
                                        ReportSuccess ("{0} port binding {1} is valid." -f @($dsConfig.portGroups[$a].name, $dsConfig.portGroups[$a].portBinding))
                                    }
                                }
                                else # NOT ($dsConfig.portGroups[$a].portBinding -match "^STATIC|EPHEMERAL$")
                                {
                                    # FALSE

                                    ReportError ("{0} port binding {1} is invalid." -f @($dsConfig.portGroups[$a].name, $dsConfig.portGroups[$a].portBinding))
                                    $definitionIsValid = $false
                                }
                                #endregion Check the port group port binding.

                                #region    Check port group VLAN
                                if ($null -ne $dsConfig.portGroups[$a].vlanID)
                                {
                                    # TRUE

                                    if (($dsConfig.portGroups[$a].vlanID -ge 1) -and ($dsConfig.portGroups[$a].vlanID -le 4094))
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Port group `"{0}'s`" VLAN {1} is valid." -f @($dsConfig.portGroups[$a].name, $dsConfig.portGroups[$a].vlanID))
                                        }
                                    }
                                    else # NOT (($dsConfig.portGroups[$a].vlanID -ge 1) -and ($dsConfig.portGroups[$a].vlanID -le 4094))
                                    {
                                        # FALSE

                                        ReportError ("Port group {0}'s VLAN {1} is invalid." -f @($dsConfig.portGroups[$a].name, $dsConfig.portGroups[$a].vlanID))
                                        $definitionIsValid = $false
                                    }

                                }
                                else # NOT ($null -ne $dsConfig.portGroups[$a].vlanID)
                                {
                                    # FALSE

                                    ReportWarning ("Port group {0} is missing a VLAN ID." -f @($dsConfig.portGroups[$a].name))
                                }
                                #endregion Check port group VLAN

                                #region    Check port group uplinks
                                if ($null -ne $dsConfig.portGroups[$a].activeUplinkNames)
                                {
                                    # TRUE

                                    if ($dsConfig.portGroups[$a].activeUplinkNames -isnot [Array])
                                    {
                                        # TRUE

                                        $dsConfig.portGroups[$a].activeUplinkNames = @($dsConfig.portGroups[$a].activeUplinkNames)
                                    }
                                    else # NOT ($dsConfig.portGroups[$a].activeUplinkNames -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing
                                    }
                                }
                                else # NOT ($null -ne $dsConfig.portGroups[$a].activeUplinkNames)
                                {
                                    # FALSE

                                    ReportError ("Missing active uplink name(s) for port group {0}." -f @($dsConfig.portGroups[$a].name))
                                    $definitionIsValid = $false

                                    # Make $dsConfig.portGroups[$a].activeUplinkNames an empty array do the logic below works
                                    $dsConfig.portGroups[$a].activeUplinkNames = @()
                                }

                                if ($null -ne $dsConfig.portGroups[$a].standbyUplinkNames)
                                {
                                    # TRUE

                                    if ($dsConfig.portGroups[$a].standbyUplinkNames -isnot [Array])
                                    {
                                        # TRUE

                                        $dsConfig.portGroups[$a].standbyUplinkNames = @($dsConfig.portGroups[$a].standbyUplinkNames)
                                    }
                                    else # NOT ($dsConfig.portGroups[$a].standbyUplinkNames -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing
                                    }
                                }
                                else # NOT ($null -ne $dsConfig.portGroups[$a].standbyUplinkNames)
                                {
                                    # FALSE

                                    ReportError ("Missing standby uplink name(s) for port group {0}." -f @($dsConfig.portGroups[$a].name))
                                    $definitionIsValid = $false

                                    # Make $dsConfig.portGroups[$a].standbyUplinkNames an empty array do the logic below works
                                    $dsConfig.portGroups[$a].standbyUplinkNames = @()
                                }

                                #region    Check the port group's active uplinks
                                $b = 0
                                while($b -lt $dsConfig.portGroups[$a].activeUplinkNames.Length)
                                {
                                    if (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].activeUplinkNames[$b]))
                                    {
                                        # TRUE

                                        if (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # TRUE

                                            if (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # TRUE

                                                if (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("Active uplink {0} for port group {1} is valid." -f @($dsConfig.portGroups[$a].activeUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                    }
                                                }
                                                else # NOT (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for active uplink {0} on port group {1}." -f @($dsConfig.portGroups[$a].activeUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Active uplink {0} cannot also be a standby uplink for port group {1}." -f @($dsConfig.portGroups[$a].activeUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate active uplink {0} for port group {1}." -f @($dsConfig.portGroups[$a].activeUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].activeUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank active uplink name [idx: {0}] for port group {1}." -f @(($b + 1), $dsConfig.portGroups[$a].name))
                                        $definitionIsValid = $false
                                    }

                                    $b++
                                }
                                #endregion Check the port group's active uplinks

                                #region    Check the port group's standby uplinks
                                $b = 0
                                while($b -lt $dsConfig.portGroups[$a].standbyUplinkNames.Length)
                                {
                                    if (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].standbyUplinkNames[$b]))
                                    {
                                        # TRUE

                                        if (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # TRUE

                                            if (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # TRUE

                                                if (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("Standby uplink {0} for port group {1} is valid." -f @($dsConfig.portGroups[$a].standbyUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                    }
                                                }
                                                else # NOT (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for standby uplink {0} on port group {1}." -f @($dsConfig.portGroups[$a].standbyUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Standby uplink {0} cannot also be an active uplink for port group {1}." -f @($dsConfig.portGroups[$a].standbyUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate standby uplink {0} for port group {1}." -f @($dsConfig.portGroups[$a].standbyUplinkNames[$b], $dsConfig.portGroups[$a].name))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].standbyUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank standby uplink name [idx: {0}] for port group {1}." -f @(($b + 1), $dsConfig.portGroups[$a].name))
                                        $definitionIsValid = $false
                                    }

                                    $b++
                                }
                                #endregion Check the port group's standby uplinks

                                #endregion Check port group uplinks
                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsConfig.portGroups)
                        {
                            # FALSE

                            ReportError "Missing distributed switch port groups."
                            $definitionIsValid = $false

                            # Make $dsConfig.portGroups and empty array so later logic will work
                            $dsConfig.portGroups = @()
                        }
                        #endregion Check port groups

                        #region    Check Connected hosts
                        if ($null -ne $dsConfig.connectedHosts)
                        {
                            # TRUE

                            if ($dsConfig.connectedHosts -isnot [Array])
                            {
                                # TRUE

                                $dsConfig.connectedHosts = @($dsConfig.connectedHosts)
                            }
                            else # NOT ($dsConfig.connectedHosts -isnot [Array])
                            {
                                # FALSE

                                # Nothing.
                            }

                            $a = 0
                            while($a -lt $dsConfig.connectedHosts.Length)
                            {
                                $vmHost = $null
                                $ucsServer = $null
                                $hostUCSAdaptors = $null
                                #region    Check connected host's vmHostName
                                if (-not [String]::IsNullOrEmpty($dsConfig.connectedHosts[$a].vmHostName))
                                {
                                    # TRUE

                                    try
                                    {
                                        $vmHost = Get-VMHost -Server $viServer -Location $dsConfig.containerName -Name $dsConfig.connectedHosts[$a].vmHostName -ErrorAction SilentlyContinue
                                    }
                                    catch { }

                                    if ($null -ne $vmHost)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Located VM host: {0} on {1}." -f @($dsConfig.connectedHosts[$a].vmHostName, $viServer.Name))
                                        }
                                    }
                                    else # NOT ($null -eq (Get-VMHost -Server $viServer -Name $dsConfig.connectedHosts[$a].vmHostName -ErrorAction SilentlyContinue))
                                    {
                                        # FALSE

                                        ReportError ("Unable to locate a VM host named {0} in cluster {1}." -f @($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.containerName))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig.connectedHosts[$a].vmHostName))
                                {
                                    # FALSE

                                    ReportError ("Missing connected host name at idx: [{0}]." -f @($a + 1))
                                    $definitionIsValid = $false

                                    # Set a bogus value for the connected host's vmHostName for later logic
                                    $dsConfig.connectedHosts[$a].vmHostName = "<MISSING>"
                                }

                                #endregion Check connected host's vmHostName

                                #region    Check connected host's serial number (and UCS vNICs)
                                if (-not [String]::IsNullOrEmpty($dsConfig.connectedHosts[$a].serial))
                                {
                                    # TRUE

                                    $ucsServer = $Global:ucsData.Servers | Where-Object { $_.serial -eq $dsConfig.connectedHosts[$a].serial }

                                    if ($null -ne $ucsServer)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Located UCS compute node with serial number {0}." -f @($ucsServer.Serial))
                                        }

                                        #region    Check to make sure there are vNICs defined in UCS for this server
                                        $hostUCSAdaptors = @($Global:ucsData.Adaptors | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) })
                                        $b = 0
                                        while($b -lt $dsConfig.uplinkMappings.Length)
                                        {
                                            if (@($hostUCSAdaptors | Where-Object { $_.Name -eq $dsConfig.uplinkMappings[$b].vNICName }).Length -eq 1)
                                            {
                                                # TRUE

                                                if($doReportSuccess)
                                                {
                                                    ReportSuccess ("UCS vNIC {0} found for {1}." -f @($dsConfig.uplinkMappings[$b].vNICName, $dsConfig.connectedHosts[$a].vmHostName))
                                                }
                                            }
                                            else # NOT (@($hostUCSAdaptors | Where-Object { $_.Name -eq $dsConfig.uplinkMappings[$b].vNICName }).Length -eq 1)
                                            {
                                                # FALSE

                                                ReportWarning ("UCS vNIC {0} not found for {1}." -f @($dsConfig.uplinkMappings[$b].vNICName, $dsConfig.connectedHosts[$a].vmHostName))
                                            }
                                            $b++
                                        }
                                        #endregion Check to make sure there are vNICs defined in UCS for this server
                                    }
                                    else # NOT ($null -ne $ucsServer)
                                    {
                                        # FALSE

                                        ReportError ("Failed to locate UCS compute node with serial number {0}." -f @($ucsServer.Serial))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig.connectedHosts[$a].serial))
                                {
                                    # FALSE

                                    ReportError ("Missing serial number for connected host {0}." -f @($dsConfig.connectedHosts[$a].vmHostName))
                                    $definitionIsValid = $false
                                }
                                #endregion Check connected host's serial number (and UCS vNICs)

                                #region    Check connected host's vmks
                                if ($null -ne $dsConfig.connectedHosts[$a].vmks)
                                {
                                    # TRUE

                                    if ($dsConfig.connectedHosts[$a].vmks -isnot [Array])
                                    {
                                        # TRUE

                                        $dsConfig.connectedHosts[$a].vmks = @($dsConfig.connectedHosts[$a].vmks)
                                    }
                                    else # NOT ($dsConfig.connectedHosts[$a].vmks -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing.
                                    }

                                    # Sort connected host's vmks by vmkName
                                    $dsConfig.connectedHosts[$a].vmks = $dsConfig.connectedHosts[$a].vmks | Sort-Object vmkName

                                    $b = 0
                                    while($b -lt $dsConfig.connectedHosts[$a].vmks.Length)
                                    {
                                        $vmkPortGroup = $null
                                        $vmHostVMK = $null

                                        #region    Check the vmk's port group name
                                        # Since we've already checked the switch's port groups, all I'll do here is make sure
                                        #   the vmk's port group is among the switches port groups.
                                        $vmkPortGroup = $dsConfig.portGroups | Where-Object { $_.name -eq $dsConfig.connectedHosts[$a].vmks[$b].portGroupName }
                                        if ($null -ne $vmkPortGroup)
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Port group {0} for VMK {1} on {2} is valid." -f @($dsConfig.connectedHosts[$a].vmks[$b].portGroupName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName))
                                            }
                                        }
                                        else # NOT ($null -ne $vmkPortGroup)
                                        {
                                            # FALSE

                                            ReportError ("Port group {0} for VMK {1} on {2} is invalid." -f @($dsConfig.connectedHosts[$a].vmks[$b].portGroupName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check the vmk's port group name

                                        #region    Check vmk's name
                                        if ($dsConfig.connectedHosts[$a].vmks[$b].vmkName -match "^vmk\d+$")
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("VMK {0} for {1} is valid." -f @($dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName))
                                            }

                                            if ($null -ne $vmHost)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $vmHostVMK = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -VMKernel -Name $dsConfig.connectedHosts[$a].vmks[$b].vmkName -ErrorAction SilentlyContinue
                                                }
                                                catch { }

                                                if ($null -ne $vmHostVMK)
                                                {
                                                    # TRUE

                                                    if ($vmHostVMK.PortGroupName -eq $dsConfig.connectedHosts[$a].vmks[$b].portGroupName)
                                                    {
                                                        # TRUE

                                                        if($doReportSuccess)
                                                        {
                                                            ReportSuccess ("VMK {0} for {1} is already connected to {2}." -f @($dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName, $vmHostVMK.PortGroupName))
                                                        }
                                                    }
                                                    else # NOT ($vmHostVMK.PortGroupName -eq $dsConfig.connectedHosts[$a].vmks[$b].portGroupName)
                                                    {
                                                        # FALSE

                                                        if($doReportSuccess)
                                                        {
                                                            ReportSuccess ("VMK {0} for {1} will be migrated to {2}." -f @($dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].portGroupName))
                                                        }
                                                    }
                                                }
                                                else # NOT ($null -ne $vmHostVMK)
                                                {
                                                    # FALSE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("VMK {0} for {1} is will be created." -f @($dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName))
                                                    }
                                                }

                                            }
                                            else # NOT ($null -ne $vmHost)
                                            {
                                                # FALSE

                                                # Nothing.
                                            }
                                        }
                                        else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].vmkName -match "^vmk\d")
                                        {
                                            # FALSE

                                            ReportError ("VMK {0} for {1} is invalid." -f @($dsConfig.connectedHosts[$a].vmks[$b].vmkName, $dsConfig.connectedHosts[$a].vmHostName))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's name

                                        #region    Check vmk's MTU
                                        if ($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mtu)
                                        {
                                            # TRUE

                                            if ($dsConfig.connectedHosts[$a].vmks[$b].mtu -match "^\d+$")
                                            {
                                                # TRUE

                                                if ($dsConfig.connectedHosts[$a].vmks[$b].mtu -in @(1500,9000))
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("{0} MTU: {1} is valid." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
                                                    }
                                                }
                                                else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -in @(1500,9000))
                                                {
                                                    # FALSE

                                                    if ($dsConfig.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # TRUE

                                                        ReportWarning ("Check MTU value: {0} for {1}." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                                    }
                                                    else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # FALSE

                                                        ReportError ("{0} MTU: {1} is invalid." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
                                                        $definitionIsValid = $false
                                                    }
                                                }

                                                if ($null -ne $hostUCSAdaptors)
                                                {
                                                    # TRUE

                                                    $vmkUplinkNames = @(($vmkPortGroup.activeUplinkNames + $vmkPortGroup.standbyUplinkNames) | Select-Object -Unique)
                                                    $vmkvNICNames = @($dsConfig.uplinkMappings | Where-Object { ($_.uplinkName -in $vmkUplinkNames) } | Select-Object -Unique -ExpandProperty vNICName)

                                                    $c = 0
                                                    while($c -lt $vmkvNICNames.Length)
                                                    {
                                                        $vmkAdaptors = @($hostUCSAdaptors | Where-Object { $_.Name -eq $vmkvNICNames[$c] })

                                                        if ($vmkAdaptors.Length -gt 0)
                                                        {
                                                            # TRUE

                                                            $d = 0
                                                            while($d -lt $vmkAdaptors.Length)
                                                            {
                                                                if ($dsConfig.connectedHosts[$a].vmks[$b].mtu -eq $vmkAdaptors[$d].Mtu)
                                                                {
                                                                    # TRUE

                                                                    if($doReportSuccess)
                                                                    {
                                                                        ReportSuccess ("MTU: {0} for {1} matches it's uplink's MTU ({2} MTU: {3})." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                    }
                                                                }
                                                                else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -eq $vmkAdaptors[$d].Mtu)
                                                                {
                                                                    # FALSE

                                                                    ReportWarning ("MTU: {0} for {1} does not match it's uplink's MTU ({2} MTU: {3})." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                }
                                                                $d++
                                                            }
                                                        }
                                                        else # NOT ($vmkAdaptors.Length -gt 0)
                                                        {
                                                            # FALSE

                                                            ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                                            $definitionIsValid = $false
                                                        }

                                                        $c++
                                                    }
                                                }
                                                else # NOT ($null -ne $hostUCSAdaptors)
                                                {
                                                    # FALSE

                                                    ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                                    $definitionIsValid = $false
                                                }


                                            }
                                            else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -match "^\d+$")
                                            {
                                                # FALSE

                                                ReportError ("{0} MTU: {1} is invalid." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT ($null -ne $dsConfig.mtu)
                                        {
                                            # FALSE

                                            ReportError "Missing switch MTU in distributed switch definition."
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's MTU

                                        #region    Check vmk's ipAddress
                                        try
                                        {
                                            $ipAddr = [System.Net.IPAddress]::Parse($dsConfig.connectedHosts[$a].vmks[$b].ipAddress)
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("IP Address {0} is valid for {1}." -f @($ipAddr.IPAddressToString, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("IP Address {0} is invalid for {1}." -f @($dsConfig.connectedHosts[$a].vmks[$b].ipAddress, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's ipAddress

                                        #region    Check vmk's subnet mask
                                        try
                                        {
                                            $ipAddr = [System.Net.IPAddress]::Parse($dsConfig.connectedHosts[$a].vmks[$b].subnetMask)
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Subnet mask {0} is valid for {1}." -f @($ipAddr.IPAddressToString, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Subnet mask {0} is invalid for {1}." -f @($dsConfig.connectedHosts[$a].vmks[$b].subnetMask, (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's subnet mask

                                        #region    Check vmk's mgmtEnabled
                                        if (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("mgmtEnabled for {0} is valid [{1}]." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("mgmtEnabled for {0} is invalid [{1}]." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's mgmtEnabled

                                        #region    Check vmk's vMotionEnabled
                                        if (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("vMotionEnabled for {0} is valid [{1}]." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("vMotionEnabled for {0} is invalid [{1}]." -f @((@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"), $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's vMotionEnabled

                                        $b++
                                    }

                                }
                                else # NOT ($null -ne $dsConfig.connectedHosts[$a].vmks)
                                {
                                    # FALSE

                                    ReportError ("Missing VMK definitions for {0}." -f @($dsConfig.connectedHosts[$a].vmHostName))
                                    $definitionIsValid = $false
                                }
                                #endregion Check connected host's vmks
                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsConfig.connectedHosts)
                        {
                            # FALSE

                            ReportError ("Missing connected hosts in switch definition.")
                            $definitionIsValid = $false
                        }
                        #endregion Check Connected hosts
                    }
                    else # NOT ($null -ne $dsConfig)
                    {
                        # FALSE

                        ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                        $definitionIsValid = $false
                    }
                    #endregion Check the switch definition



                }
                else # NOT ($null -ne $Global:ucsData)
                {
                    # FALSE

                    ReportError ("Unable to continue without UCS Data.")
                    $definitionIsValid = $false
                }
            }
            else # NOT ($null -ne $ucs)
            {
                # FALSE

                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $definitionIsValid = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
            $definitionIsValid = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $definitionIsValid = $false
    }

    return $definitionIsValid
}

function RemoveVMHostDatastores
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName
    )

    $vmHostName = ("{0}.powereng.com" -f @($vmHostName)).ToLower().Replace(".powereng.com.powereng.com",".powereng.com")
    try
    {
        $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop
        if ($vmHost.ConnectionState -eq [VMware.VimAutomation.ViCore.Types.V1.Host.VMHostState]::Maintenance)
        {
            try
            {
                $datastores = @(Get-Datastore -Server $viServer -RelatedObject $vmHost -ErrorAction Stop | Where-Object { $_.Type -eq "NFS"})
                $a = 0
                while($a -lt $datastores.Length)
                {
                    try
                    {
                        Remove-Datastore -Server $viServer -Datastore $datastores[$a] -VMHost $vmHost -Confirm:$false
                    }
                    catch
                    {
                        ReportError ("Failed to remove datastore: {0} from {1}." -f @($datastores[$a].Name, $vmHost.Name))
                    }
                    $a++
                }
            }
            catch
            {
                ReportError ("Failed to acquire datastores on {0}." -f @($vmHost.Name))
            }
        } `
        else # NOT ($vmHost.ConnectionState -eq )
        {
            ReportWarning ("RemoveVMHostDatastores will only remove datastores from hosts in maintenance mode.")
        }
    }
    catch
    {
        ReportError ("Failed to acquire VM host: {0}" -f @($vmHostName))
    }
}

function GetHostDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $virtualizationDefinition,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $hostName
    )

    $hostDef = $virtualizationDefinition.hosts | Where-Object { $_.vmHostName -match $hostName }

    return $hostDef
}

function CaptureVMHostVMs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName
    )

    $vmHostName = ("{0}.powereng.com" -f @($vmHostName)).ToLower().Replace(".powereng.com.powereng.com",".powereng.com")
    try
    {
        $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop
        try
        {
            $hostVMs = @(Get-VM -Server $viServer -Location $vmHost -ErrorAction Stop | Where-Object { $_.Name -notmatch "^vCLS"})

            $saveFile = "{0}\{1}.txt" -f @($env:TEMP, $vmHost.Name)
            "# {0}'s VMs @{1}" -f @($vmHost.Name, [DateTime]::Now.ToString("yyyyMMdd HHmmss.fff")) | Out-File -FilePath $saveFile -Force

            $a = 0
            while($a -lt $hostVMs.Length)
            {
                ("{0},{1}" -f @($hostVMs[$a].Name, $hostVMs[$a].PowerState)) | Out-File -FilePath $saveFile -Append
                $a++
            }
            ReportSuccess ("Captured {0} VM for host: {1}." -f @($hostVMs.Length, $vmHost.Name))
        }
        catch
        {
            ReportError ("Failed to acquire VMs on {0}." -f @($vmHost.Name))
        }
    }
    catch
    {
        ReportError ("Failed to acquire VM host: {0}" -f @($vmHostName))
    }
}

$portGroupTranslations = @()
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL60-EXTDMZ";             $d.OldName="DMZ VL60-EXTDMZ1";             $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL61-INTDMZ";             $d.OldName="DMZ VL61-INTDMZ1";             $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL63-WSINTDMZ";           $d.OldName="DMZ VL63-WSINTDMZ1";           $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL68-STORAGE";            $d.OldName="DMZ VL68-STORAGE1";            $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL68-VMOTION";            $d.OldName="DMZ VL68-VMOTION1";            $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "DMZ VL69-DMZMGMT";            $d.OldName="DMZ VL69-DMZMGMT1";            $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL03-SERVERDATA";             $d.OldName="VL03-SERVERDATA1";             $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL03-SERVERDATA (Ephemeral)"; $d.OldName="VL03-SERVERDATA1 (Ephemeral)"; $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL05-INFRAMGMT";              $d.OldName="VL05-INFRAMGMT1";              $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL07-NLS";                    $d.OldName="VL07-NLS1";                    $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL09-LB-FARM";                $d.OldName="VL09-LB-FARM1";                $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL11-STORAGE";                $d.OldName="VL11-STORAGE1";                $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL11-VMOTION";                $d.OldName="VL11-VMOTION1";                $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL20-VOICE-ELAN";             $d.OldName="VL20-VOICE-ELAN1";             $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL21-INFOSEC-MGMT";           $d.OldName="VL21-INFOSEC-MGMT1";           $portGroupTranslations += $d
    $d = "" | Select-Object NewName, OldName; $d.NewName = "VL40-CLIENTLAN";              $d.OldName="VL40-CLIENTLAN1";              $portGroupTranslations += $d

function RestoreVMHostVMs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName
    )

    $vmHostName = ("{0}.powereng.com" -f @($vmHostName)).ToLower().Replace(".powereng.com.powereng.com",".powereng.com")
    try
    {
        $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop

        try
        {
            $existingVMs = @(Get-VM -Server $viServer -Location $vmHost -ErrorAction Stop | Where-Object { $_.Name -notmatch "^vCLS \(\d+\)$"})
            try
            {
                $vds = Get-VDSwitch -Server $viServer -VMHost $vmHost -ErrorAction Stop
                try
                {
                    $vpgs = @(Get-VDPortgroup -Server $viServer -VDSwitch $vds -ErrorAction Stop)
                    $saveFile = "{0}\{1}.txt" -f @($env:TEMP, $vmHost.Name)
                    try
                    {
                        $hostVMNames = @(Get-Content -Path $saveFile -ErrorAction Stop | Where-Object { (-not $_.StartsWith("#")) -and ($_ -notmatch "vCLS") })

                        $a = 0
                        while($a -lt $hostVMNames.Length)
                        {
                            if (@($existingVMs | Where-Object { $_.Name -eq $hostVMNames[$a] }).Length -eq 0)
                            {
                                try
                                {
                                    $vm = Get-VM -Server $viServer -Name $hostVMNames[$a] -ErrorAction Stop
                                    try
                                    {
                                        $vmGoodToGo = $true
                                        $vmNetworkAdapters = @(Get-NetworkAdapter -Server $viServer -VM $vm -ErrorAction Stop)
                                        $portGroups = @()

                                        $b = 0
                                        while($b -lt $vmNetworkAdapters.Length)
                                        {
                                            $existingPortGroup = $vpgs | Where-Object { $_.Name -eq $vmNetworkAdapters.NetworkName }
                                            if ($null -ne $existingPortGroup)
                                            {
                                                $portGroups += $existingPortGroup
                                            } `
                                            else # NOT ($null -ne $existingPortGroup)
                                            {
                                                $newPortGroupTranslation = $portGroupTranslations | Where-Object { $_.OldName -eq $vmNetworkAdapters[$b].NetworkName }
                                                if ($null -ne $newPortGroupTranslation)
                                                {
                                                    $newPortGroupName = $newPortGroupTranslation.NewName
                                                    $newPortGroup = $vpgs | Where-Object { $_.Name -eq $newPortGroupName }
                                                    if ($null -ne $newPortGroup)
                                                    {
                                                        $portGroups += $newPortGroup
                                                    } `
                                                    else # NOT ($null -ne $newPortGroup)
                                                    {
                                                        ReportError ("Failed to locate existing *translated* port group {0} for VM: {0}." -f @($newPortGroupName, $vm.Name))
                                                        $vmGoodToGo = $false
                                                    }
                                                } `
                                                else # NOT ($null -ne $newPortGroupTranslation)
                                                {
                                                    ReportError ("Failed to locate port group translation for {0} / {1}." -f @($vm.Name, $vmNetworkAdapters[$b].NetworkName))
                                                    $vmGoodToGo = $false
                                                }
                                            }

                                            $b++
                                        }

                                        if ($vmGoodToGo -and ($vmNetworkAdapters.Length -eq $portGroups.Length))
                                        {
                                            <#
                                                To Move-VM:
                                                    -VM: VM to move
                                                    -Destination: ESXi Host to move the VM to
                                                    -NetworkAdapter: [] of VM network adapters (Get-NetworkAdapter) same order as -PortGroup
                                                    -PortGroup: [] of port groups to attach NetworkAdapter(s)
                                            #>
                                            try
                                            {
                                                [void] (VMWare.VimAutomation.Core\Move-VM -VM $vm -Destination $vmHost -NetworkAdapter $vmNetworkAdapters -PortGroup $portGroups -ErrorAction Stop -RunAsync)
                                                ReportSuccess ("Starting migration of VM: {0} to {1}." -f @($vm.Name, $vmHost.Name))
                                            }
                                            catch
                                            {
                                                ReportError ("Failed to start migration of VM: {0} to {1}." -f @($vm.Name, $vmHost.Name))
                                            }
                                        } `
                                        else # NOT ($vmGoodToGo -and ($vmNetworkAdapters.Length -eq $portGroups.Length))
                                        {
                                            # Nothing.
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Failed to retrieve network adapters from VM: {0}." -f @($vm.Name))
                                    }

                                }
                                catch
                                {
                                    ReportError ("Failed to acquire VM named: {0}." -f @($hostVMNames[$a]))
                                }
                            } `
                            else # NOT (@($existingVMs | Where-Object { $_.Name -eq $hostVMNames[$a] }).Length -eq 0)
                            {
                                ReportNotice ("VM: {0} is already running on {1}." -f @($hostVMNames[$a], $vmHost.Name))
                            }

                            $a++
                        }
                    }
                    catch
                    {
                        ReportError ("Failed to read save file for {0} VMs." -f @($vmHost.Name))
                    }
                }
                catch
                {
                    ReportError ("Failed to acquire port groups associated with {0}." -f @($vds.Name))
                }

            }
            catch
            {
                ReportError ("Failed to acquire distributed switch associated with {0}." -f @($vmHost.Name))
            }
        }
        catch
        {

        }
    }
    catch
    {
        ReportError ("Failed to acquire VM host: {0}" -f @($vmHostName))
    }
}

<#
    Get $datacenterName from $viServer
        Optionally create it if it doesn't exist
#>

# TODO: Consider connecting to vCenter based on $virtualizationDefinition...


& {
    $virtualizationDefinition = Get-Content -Path ".\VMWare\ch3-dmzv3.json" | ConvertFrom-Json

    if ($null -eq $Global:ucsManagers)
    {
        ConnectTo -keywords $virtualizationDefinition.ucsManager
        if (($null -ne $Global:ucsManagers) -and ($Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager)))
        {

            $goodToGo = ($null -ne $virtualizationDefinition.ucsManager) -and ($virtualizationDefinition.ucsManager -is [Cisco.Ucsm.UcsHandle])
        } `
        else # NOT (-not $Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager))
        {
            ReportError ("Not connected to UCS Manager: {0}" -f @($virtualizationDefinition.ucsManager))
        }
    } `
    else # NOT ($null -eq $Global:ucsManagers)
    {
        # Nothing.
    }

    if ($null -ne $Global:ucsManagers)
    {
        if (-not $Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager))
        {
            ConnectTo -keywords $virtualizationDefinition.ucsManager
            if ($Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager))
            {
                $virtualizationDefinition.ucsManager = $Global:ucsManagers[$virtualizationDefinition.ucsManager]
                $goodToGo = ($null -ne $virtualizationDefinition.ucsManager) -and ($virtualizationDefinition.ucsManager -is [Cisco.Ucsm.UcsHandle])
            } `
            else # NOT (-not $Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager))
            {
                ReportError ("Not connected to UCS Manager: {0}" -f @($virtualizationDefinition.ucsManager))
            }
        } `
        else # NOT (-not $Global:ucsManagers.ContainsKey($virtualizationDefinition.ucsManager))
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $Global:ucsManagers)
    {
        # Nothing.
    }

    if ($goodToGo)
    {
        $viServer = $vCenter
        $doReportSuccess = $true
        $ucs = $da11UCS
        $Global:ucsData = $null
        $DoIt = $true
        $virtualizationDefinition.ucsManager = $ucs

        # TODO: Fix ValidateSwitchDefinition to work with v2
        # TODO: Fix functions that use $hosts -- check $hosts before use

    #    if (ValidateSwitchDefinition -viServer $viServer -ucs $ucs -dsf $dsConfig -doReportSuccess:$doReportSuccess)
    #    {
            # TRUE


    #    }
    #    else # NOT (ValidateSwitchDefinition -viServer $viServer -ucs $ddcUCS -dsf $dsConfig -doReportSuccess)
    #    {
    #        ReportError "Unable to valid the distributed switch configuration."
    #    }
    } `
    else # NOT ($goodToGo)
    {
        # Nothing.
    }
}
