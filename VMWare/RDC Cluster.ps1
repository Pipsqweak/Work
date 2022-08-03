
# $virtualizationDefinition = Get-Content -Path ".\VMware\cdcDMZv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv3.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMware\ddcInternalv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json


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
.SYNOPSIS
Display a red error message on the host.

.DESCRIPTION
Prepend "ERROR" to the specified message and display it in red on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays an error message on the host.

.EXAMPLE
PS> ReportError "This is an error."
ERROR: This is an error.

.LINK
None
#>
function ReportError
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Red ("ERROR: {0}" -f @($message))
}

<#
.SYNOPSIS
Display a yellow warning message on the host.

.DESCRIPTION
Prepend "WARNING" to the specified message and display it in yellow on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a warning message on the host.

.EXAMPLE
PS> ReportWarning "This is a warning."
WARNING: This is a warning.

.LINK
None
#>
function ReportWarning
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Yellow ("WARNING: {0}" -f @($message))
}

<#
.SYNOPSIS
Display a white message on the host.

.DESCRIPTION
Display the specified message in white on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a message on the host.

.EXAMPLE
PS> ReportNotice "This is a notice."
This is a notice.

.LINK
None
#>
function ReportNotice
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor White $message
}

<#
.SYNOPSIS
Display a green message on the host.

.DESCRIPTION
Display the specified message in green on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a message on the host.

.EXAMPLE
PS> ReportSuccess "This is a successful message."
This is a successful message.

.LINK
None
#>
function ReportSuccess
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Green $message
}

function Quoted
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Object] $myValue
    )

    $quotedValue = ""
    if ($null -ne $myValue)
    {
        # TRUE

        $myValueStr = $myValue.ToString()

        if (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # TRUE

            $quotedValue = "`"{0}`"" -f @($myValue.ToString())
        }
        else # NOT (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ($null -ne $myValue)
    {
        # FALSE

        # Nothing.
    }

    return $quotedValue
}

function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # TRUE

        # Using -match to parse out the octets.
        if($ipStr -match "^((\d+)\.(\d+)\.(\d+)\.(\d+))$")
        {
            $a = 0
            while($a -lt 4)
            {
                $octet = [Convert]::ToUInt32($Matches[$a + 2], 10)
                $ipAddr += ($octet -shl (24 - (8 * $a)))
                $a++
            }
        }
    }
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # FALSE

        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

function GetUCSData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Cisco.Ucsm.UcsHandle] $ucsManager,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $Global:ucsData = "" | Select-Object Adaptors, Servers, VLANs

    # Retrieve required data from UCS

    #region    Collect UCS Compute node details
    try  # Just to subdue any error messages.
    {
        $Global:ucsData.Servers = @(Get-UCSServer -Ucs $ucsManager -ErrorAction SilentlyContinue)
    }
    catch { }

    if ($Global:ucsData.Servers.Length -gt 0)
    {
        # TRUE

        if($doReportSuccess)
        {
            ReportSuccess ("Retrieved {0} compute node details from {1}." -f @($Global:ucsData.Servers.Length, $ucsManager.Name))
        }

        #region    Collect UCS vNIC information
        try  # Just to subdue any error messages.
        {
            $Global:ucsData.Adaptors = @(Get-UCSAdaptorHostEthIf -Ucs $ucsManager -ErrorAction SilentlyContinue)
        }
        catch { }

        if ($Global:ucsData.Adaptors.Length -gt 0)
        {
            # TRUE

            if($doReportSuccess)
            {
                ReportSuccess ("Retrieved {0} vNIC details from {1}." -f @($Global:ucsData.Adaptors.Length, $ucsManager.Name))
            }

            #region    Collect UCS VLAN information
            try  # Just to subdue any error messages.
            {
                $Global:ucsData.VLANs = @(Get-UcsVlan -Ucs $ucsManager -ErrorAction SilentlyContinue)
            }
            catch { }

            if ($Global:ucsData.VLANs.Length -gt 0)
            {
                # TRUE

                if($doReportSuccess)
                {
                    ReportSuccess ("Retrieved {0} VLANs from {1}." -f @($Global:ucsData.VLANs.Length, $ucsManager.Name))
                }
            }
            else # NOT ($Global:ucsData.VLANs.Length -gt 0)
            {
                # FALSE

                ReportError ("Failed to retrieve VLAN details from {0}." -f @($ucsManager.Name))
                $Global:ucsData = $null
            }
            #endregion Collect UCS VLAN information

        }
        else # NOT ($Global:ucsData.Adaptors.Length -gt 0)
        {
            # FALSE

            ReportError ("Failed to retrieve vNIC details from {0}." -f @($ucsManager.Name))
            $Global:ucsData = $null
        }
        #endregion Collect UCS vNIC information
    }
    else # NOT ($Global:ucsData.Servers.Length -gt 0)
    {
        # FALSE

        ReportError ("Failed to retrieve compute node details from {0}." -f @($ucsManager.Name))
        $Global:ucsData = $null
    }
    #endregion Collect UCS Compute node details
}

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
        [Cisco.Ucsm.UcsHandle] $ucsManager,

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

            if ($null -ne $ucsManager)
            {
                # TRUE

                if ($null -eq $Global:ucsData)
                {
                    # TRUE

                    GetUCSData -ucsManager $ucsManager -doReportSuccess:$doReportSuccess
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
                                    ReportSuccess ("Distributed switch {0} does not exist." -f @(Quoted $dsConfig.name))
                                }
                            }
                            else # NOT ($null -ne $vds)
                            {
                                # FALSE

                                ReportError ("Distributed switch {0} already exists under {1}." -f @((Quoted $vds.Name), (Quoted $vds.Datacenter.Name)))
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
                                    ReportSuccess ("Container {0} exists." -f @(Quoted $dsConfig.containerName))
                                }
                            }
                            else # NOT ($null -ne $container)
                            {
                                # FALSE

                                ReportError ("Container {0} does not exist." -f @(Quoted $dsConfig.containerName))
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
                                ReportSuccess ("Distributed switch version {0}." -f @(Quoted $dsConfig.version))
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
                                        ReportSuccess ("{0} port binding {1} is valid." -f @((Quoted $dsConfig.portGroups[$a].name), (Quoted $dsConfig.portGroups[$a].portBinding)))
                                    }
                                }
                                else # NOT ($dsConfig.portGroups[$a].portBinding -match "^STATIC|EPHEMERAL$")
                                {
                                    # FALSE

                                    ReportError ("{0} port binding {1} is invalid." -f @((Quoted $dsConfig.portGroups[$a].name), (Quoted $dsConfig.portGroups[$a].portBinding)))
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

                                    ReportWarning ("Port group {0} is missing a VLAN ID." -f @(Quoted $dsConfig.portGroups[$a].name))
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

                                    ReportError ("Missing active uplink name(s) for port group {0}." -f @(Quoted $dsConfig.portGroups[$a].name))
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

                                    ReportError ("Missing standby uplink name(s) for port group {0}." -f @(Quoted $dsConfig.portGroups[$a].name))
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
                                                        ReportSuccess ("Active uplink {0} for port group {1} is valid." -f @((Quoted $dsConfig.portGroups[$a].activeUplinkNames[$b]), ($dsConfig.portGroups[$a].name)))
                                                    }
                                                }
                                                else # NOT (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for active uplink {0} on port group {1}." -f @((Quoted $dsConfig.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Active uplink {0} cannot also be a standby uplink for port group {1}." -f @((Quoted $dsConfig.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].activeUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate active uplink {0} for port group {1}." -f @((Quoted $dsConfig.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].activeUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank active uplink name [idx: {0}] for port group {1}." -f @(($b + 1), (Quoted $dsConfig.portGroups[$a].name)))
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
                                                        ReportSuccess ("Standby uplink {0} for port group {1} is valid." -f @((Quoted $dsConfig.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                                    }
                                                }
                                                else # NOT (@($dsConfig.uplinkMappings | Where-Object { $_.uplinkName -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for standby uplink {0} on port group {1}." -f @((Quoted $dsConfig.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsConfig.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Standby uplink {0} cannot also be an active uplink for port group {1}." -f @((Quoted $dsConfig.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsConfig.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsConfig.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate standby uplink {0} for port group {1}." -f @((Quoted $dsConfig.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsConfig.portGroups[$a].name)))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsConfig.portGroups[$a].standbyUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank standby uplink name [idx: {0}] for port group {1}." -f @(($b + 1), (Quoted $dsConfig.portGroups[$a].name)))
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
                                            ReportSuccess ("Located VM host: {0} on {1}." -f @((Quoted $dsConfig.connectedHosts[$a].vmHostName), (Quoted $viServer.Name)))
                                        }
                                    }
                                    else # NOT ($null -eq (Get-VMHost -Server $viServer -Name $dsConfig.connectedHosts[$a].vmHostName -ErrorAction SilentlyContinue))
                                    {
                                        # FALSE

                                        ReportError ("Unable to locate a VM host named {0} in cluster {1}." -f @((Quoted $dsConfig.connectedHosts[$a].vmHostName), (Quoted $dsConfig.containerName)))
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
                                            ReportSuccess ("Located UCS compute node with serial number {0}." -f @(Quoted $ucsServer.Serial))
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
                                                    ReportSuccess ("UCS vNIC {0} found for {1}." -f @((Quoted $dsConfig.uplinkMappings[$b].vNICName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
                                                }
                                            }
                                            else # NOT (@($hostUCSAdaptors | Where-Object { $_.Name -eq $dsConfig.uplinkMappings[$b].vNICName }).Length -eq 1)
                                            {
                                                # FALSE

                                                ReportWarning ("UCS vNIC {0} not found for {1}." -f @((Quoted $dsConfig.uplinkMappings[$b].vNICName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
                                            }
                                            $b++
                                        }
                                        #endregion Check to make sure there are vNICs defined in UCS for this server
                                    }
                                    else # NOT ($null -ne $ucsServer)
                                    {
                                        # FALSE

                                        ReportError ("Failed to locate UCS compute node with serial number {0}." -f @(Quoted $ucsServer.Serial))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsConfig.connectedHosts[$a].serial))
                                {
                                    # FALSE

                                    ReportError ("Missing serial number for connected host {0}." -f @(Quoted $dsConfig.connectedHosts[$a].vmHostName))
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
                                                ReportSuccess ("Port group {0} for VMK {1} on {2} is valid." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].portGroupName), (Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
                                            }
                                        }
                                        else # NOT ($null -ne $vmkPortGroup)
                                        {
                                            # FALSE

                                            ReportError ("Port group {0} for VMK {1} on {2} is invalid." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].portGroupName), (Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check the vmk's port group name

                                        #region    Check vmk's name
                                        if ($dsConfig.connectedHosts[$a].vmks[$b].vmkName -match "^vmk\d+$")
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("VMK {0} for {1} is valid." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
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
                                                            ReportSuccess ("VMK {0} for {1} is already connected to {2}." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName), (Quoted $vmHostVMK.PortGroupName)))
                                                        }
                                                    }
                                                    else # NOT ($vmHostVMK.PortGroupName -eq $dsConfig.connectedHosts[$a].vmks[$b].portGroupName)
                                                    {
                                                        # FALSE

                                                        if($doReportSuccess)
                                                        {
                                                            ReportSuccess ("VMK {0} for {1} will be migrated to {2}." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName), (Quoted $dsConfig.connectedHosts[$a].vmks[$b].portGroupName)))
                                                        }
                                                    }
                                                }
                                                else # NOT ($null -ne $vmHostVMK)
                                                {
                                                    # FALSE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("VMK {0} for {1} is will be created." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
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

                                            ReportError ("VMK {0} for {1} is invalid." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsConfig.connectedHosts[$a].vmHostName)))
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
                                                        ReportSuccess ("{0} MTU: {1} is valid." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
                                                    }
                                                }
                                                else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -in @(1500,9000))
                                                {
                                                    # FALSE

                                                    if ($dsConfig.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # TRUE

                                                        ReportWarning ("Check MTU value: {0} for {1}." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                    }
                                                    else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # FALSE

                                                        ReportError ("{0} MTU: {1} is invalid." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
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
                                                                        ReportSuccess ("MTU: {0} for {1} matches it's uplink's MTU ({2} MTU: {3})." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                    }
                                                                }
                                                                else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -eq $vmkAdaptors[$d].Mtu)
                                                                {
                                                                    # FALSE

                                                                    ReportWarning ("MTU: {0} for {1} does not match it's uplink's MTU ({2} MTU: {3})." -f @($dsConfig.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                }
                                                                $d++
                                                            }
                                                        }
                                                        else # NOT ($vmkAdaptors.Length -gt 0)
                                                        {
                                                            # FALSE

                                                            ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                            $definitionIsValid = $false
                                                        }

                                                        $c++
                                                    }
                                                }
                                                else # NOT ($null -ne $hostUCSAdaptors)
                                                {
                                                    # FALSE

                                                    ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                    $definitionIsValid = $false
                                                }


                                            }
                                            else # NOT ($dsConfig.connectedHosts[$a].vmks[$b].mtu -match "^\d+$")
                                            {
                                                # FALSE

                                                ReportError ("{0} MTU: {1} is invalid." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mtu))
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
                                                ReportSuccess ("IP Address {0} is valid for {1}." -f @((Quoted $ipAddr.IPAddressToString), (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("IP Address {0} is invalid for {1}." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].ipAddress), (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's ipAddress

                                        #region    Check vmk's subnet mask
                                        try
                                        {
                                            $ipAddr = [System.Net.IPAddress]::Parse($dsConfig.connectedHosts[$a].vmks[$b].subnetMask)
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Subnet mask {0} is valid for {1}." -f @((Quoted $ipAddr.IPAddressToString), (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Subnet mask {0} is invalid for {1}." -f @((Quoted $dsConfig.connectedHosts[$a].vmks[$b].subnetMask), (Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's subnet mask

                                        #region    Check vmk's mgmtEnabled
                                        if (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("mgmtEnabled for {0} is valid [{1}]." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("mgmtEnabled for {0} is invalid [{1}]." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's mgmtEnabled

                                        #region    Check vmk's vMotionEnabled
                                        if (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("vMotionEnabled for {0} is valid [{1}]." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsConfig.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("vMotionEnabled for {0} is invalid [{1}]." -f @((Quoted (@($dsConfig.connectedHosts[$a].vmHostName, $dsConfig.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsConfig.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's vMotionEnabled

                                        $b++
                                    }

                                }
                                else # NOT ($null -ne $dsConfig.connectedHosts[$a].vmks)
                                {
                                    # FALSE

                                    ReportError ("Missing VMK definitions for {0}." -f @(Quoted $dsConfig.connectedHosts[$a].vmHostName))
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
            else # NOT ($null -ne $ucsManager)
            {
                # FALSE

                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $definitionIsValid = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
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

<#
.SYNOPSIS
Create and configure a new distributed switch based on the configuration provided.

.DESCRIPTION
Create a new distributed switch, rename the uplink port group to "~Uplinks", rename each of the uplinks based on the configuration provided, and enable network I/O control on the switch.

.PARAMETER vCenter
Connection object for the vCenter to host the distributed switch.

.PARAMETER dsf
A data structure (read from a .JSON file) representing the configuration of the distributed switch.  See the top of this file for a description.

.PARAMETER DoIt
Take action?

.PARAMETER doReportSuccess
Report successful actions?

.INPUTS
None.

.OUTPUTS
VMware.VimAutomation.Vds.Impl.V1.VmwareVDSwitchImpl representing the newly created distributed switch

.EXAMPLE
PS> $newVDS = CreateVDS -viServer $viServer -datacenterName $virtualizationDefinition.datacenterName -dsConfig $virtualizationDefinition.switch -Doit -doReportSuccess


.LINK
None
#>
function CreateVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $datacenterName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $false
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                $uplinkNames = @($dsConfig.uplinkMappings | Select-Object -Unique -ExpandProperty uplinkName)

                if ($uplinkNames.Length -gt 0)
                {
                    # TRUE

                    # The following is sort of backwards, but the expected behavior is for Get-VDSwitch to throw an
                    #   exception if there in no distributed switch named $dsConfig.switchName -- which is what we want.
                    try
                    {
                        $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                        ReportError ("Distributed switch {0} already exists." -f @(Quoted $dsConfig.name))
                        $vds = $null    # So we don't report the switch needs to be removed.
                    }
                    catch
                    {
                        try
                        {
                            # Get the datacenter where the new distributed switch will live
                            $vdsDatacenter = Get-Datacenter -Server $viServer -Name $datacenterName -ErrorAction Stop

                            # Create the new distributed switch
                            try
                            {
                                $vds = New-VDSwitch -Server $viServer -Name $dsConfig.name -Location $vdsDatacenter -NumUplinkPorts $dsConfig.uplinkMappings.Length -LinkDiscoveryProtocol "CDP" -LinkDiscoveryProtocolOperation "BOTH" -Mtu $dsConfig.mtu -Version $dsConfig.version -ErrorAction Stop

                                if ($doReportSuccess)
                                {
                                    # TRUE

                                    ReportSuccess ("Created distributed switch {0} under {1}." -f @((Quoted $vds.Name), (Quoted $vdsDatacenter.Name)))
                                }
                                else # NOT ($doReportSuccess)
                                {
                                    # FALSE

                                    # Nothing.
                                }

                                # It is not imperative we rename the uplink port group, it's just cleaner to me.
                                try
                                {
                                    # Retrieve the uplinks port group on the new distributed switch
                                    $uplinkPortGroup = Get-VDPortGroup -VDSwitch $vds -ErrorAction Stop | Where-Object { $_.IsUplink }
                                    $uplinkName = "~{0} Uplinks" -f @($vds.Name)

                                    try
                                    {
                                        # Rename the uplinks port group on the new distributed switch
                                        $uplinkPortGroup | Set-VDPortgroup -Name $uplinkName -ErrorAction Stop

                                        if ($doReportSuccess)
                                        {
                                            # TRUE

                                            ReportNotice ("`tRenamed uplink port group to {0}." -f @(Quoted $uplinkName))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # FALSE

                                            # Nothing.
                                        }
                                    }
                                    catch
                                    {
                                        ReportWarning ("Failed to rename uplink port group to {0}." -f @(Quoted $uplinkName))
                                    }
                                }
                                catch
                                {
                                    ReportWarning ("Failed to retrieve default uplinks port group for {0}." -f @(Quoted $vds.Name))
                                }

                                # Rename all the uplinks

                                try
                                {
                                    $vds = $null
                                    # Re-aquire the distributed switch so we have a valid ConfigVersion below
                                    $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                                    # Create a new spec to rename an uplink
                                    $spec = [VMware.Vim.DVSConfigSpec]::new()
                                    $spec.ConfigVersion = $vds.ExtensionData.Config.ConfigVersion
                                    $spec.UplinkPortPolicy = [VMware.Vim.DVSNameArrayUplinkPortPolicy]::new()

                                    # Add all the uplink names to the specification
                                    $dsConfig.uplinkMappings | ForEach-Object { $spec.UplinkPortPolicy.UplinkPortName += $_.uplinkName }

                                    try
                                    {
                                        # Submit the reconfigure DVS task to vCenter.
                                        $vds.ExtensionData.ReconfigureDvs($spec)

                                        if ($doReportSuccess)
                                        {
                                            # TRUE

                                            ReportSuccess ("`tRenamed uplinks to {0}." -f @(@((@($dsConfig.uplinkmappings | Select-Object -SkipLast 1 -ExpandProperty uplinkName) -join ", "), ($dsConfig.uplinkmappings | Select-Object -Last 1 -ExpandProperty uplinkName)) -join " and "))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # FALSE

                                            # Nothing.
                                        }

                                        try
                                        {
                                            # Enable Network I/O Control for the new distributed switch
                                            $vds.ExtensionData.EnableNetworkResourceManagement($true)

                                            $goodToGo = $true
                                            if ($doReportSuccess)
                                            {
                                                # TRUE

                                                ReportSuccess ("`tEnabled network I/O control on {0}." -f @(Quoted $vds.Name))
                                            }
                                            else # NOT ($doReportSuccess)
                                            {
                                                # FALSE

                                                # Nothing.
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to enable network I/O control on {0}.  Check vCenter logs." -f @(Quoted $vds.Name))
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Failed to rename uplink {0}.  Check vCenter logs." -f @(Quoted $uplinkNames[$a]))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to re-acquire distributed switch {0}." -f @(Quoted $dsConfig.name))
                                }
                            }
                            catch
                            {
                                ReportError ("Failed to create distributed switch {0}.  Consult vCenter logs." -f @(Quoted $dsConfig.name))
                            }
                        }
                        catch
                        {
                            ReportError ("Unable to locate datacenter {0} in vCenter." -f @(Quoted $datacenterName))
                        }
                    }
                }
                else # NOT ($uplinkNames.Length -gt 0)
                {
                    # FALSE

                    ReportError "No uplink names found in distributed switch definition."
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }

    if (-not $goodToGo)
    {
        # TRUE

        if ($null -ne $vds)
        {
            # TRUE

            ReportWarning ("Please manually continue the creation of {0}, or correct the problem, remove the distributed switch if possible and retry to create it." -f @(Quoted $dsConfig.name))
        }
        else # NOT ($null -ne $vds)
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT (-not $goodToGo)
    {
        # FALSE

        # Nothing.
    }

    return $vds
}

function CreatePortGroups
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                try
                {
                    $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                    $a = 0
                    while($goodToGo -and ($a -lt $dsConfig.portGroups.Length))
                    {
                        $vpg = $null
                        try
                        {
                            $vpg = Get-VDPortgroup -Server $viServer -VDSwitch $vds -Name $dsConfig.portGroups[$a].name -ErrorAction Stop

                            ReportWarning ("{0} already contains a distributed port group named {1}." -f @($vds.Name, $vpg.Name))
                        }
                        catch
                        {
                            # Set up the parameters to create a new port group
                            $newPortGroupParams = @{
                                VDSwitch = $vds
                                Name = $dsConfig.portGroups[$a].name
                                VlanId = $dsConfig.portGroups[$a].vlanID
                                PortBinding = $dsConfig.portGroups[$a].portBinding
                                ErrorAction = "Stop"
                            }

                            # Not all port groups are bound to a VLAN
                            if ($null -eq $dsConfig.portGroups[$a].vlanID)
                            {
                                # TRUE

                                $newPortGroupParams.Remove("VlanID")
                            }
                            else # NOT ($null -eq $dsConfig.portGroups[$a].vlanID)
                            {
                                # FALSE

                                # Nothing.
                            }

                            if ($doIt)
                            {
                                # TRUE

                                try
                                {
                                    $vpg = New-VDPortgroup @newPortGroupParams

                                    if ($doReportSuccess)
                                    {
                                        # TRUE

                                        ReportSuccess ("`tCreated port group {0} on {1}." -f @((Quoted $vpg.Name), (Quoted $vds.Name)))
                                    }
                                    else # NOT ($doReportSuccess)
                                    {
                                        # FALSE

                                        # Nothing.
                                    }

                                    # Now set the teaming policy for the port group.

                                    $teamingPolicyParams = @{
                                        ActiveUplinkPort = $dsConfig.portGroups[$a].activeUplinkNames
                                        StandbyUplinkPort = $dsConfig.portGroups[$a].standbyUplinkNames
                                        UnusedUplinkPort = @(@($dsConfig.uplinkMappings | Select-Object -Unique -ExpandProperty uplinkName) | Where-Object { ($_ -notin $dsConfig.portGroups[$a].activeUplinkNames) -and ($_ -notin $dsConfig.portGroups[$a].standbyUplinkNames) })
                                    }

                                    # Remove any of the teaming policy parameters that are empty
                                    if($teamingPolicyParams.ActiveUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("ActiveUplinkPort")
                                    }
                                    if($teamingPolicyParams.StandbyUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("StandbyUplinkPort")
                                    }
                                    if($teamingPolicyParams.UnusedUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("UnusedUplinkPort")
                                    }

                                    if ($teamingPolicyParams.Count -gt 0)
                                    {
                                        # TRUE

                                        try
                                        {
                                            $teamingPolicy = $vpg | Get-VDUplinkTeamingPolicy -Server $viServer -ErrorAction Stop

                                            if ($null -ne $teamingPolicy)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    [void] ($teamingPolicy | Set-VDUplinkTeamingPolicy @teamingPolicyParams -ErrorAction Stop)

                                                    if ($doReportSuccess)
                                                    {
                                                        # TRUE

                                                        ReportSuccess ("`tTeaming policy successfully set.")
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # FALSE

                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to set teaming policy for {0}." -f @(Quoted $vpg.Name))
                                                    $goodToGo = $false
                                                }
                                            }
                                            else # NOT ($null -ne $teamingPolicy)
                                            {
                                                # FALSE

                                                ReportError ("Failed to retrieve teaming policy for {0}." -f @(Quoted $vpg.Name))
                                                $goodToGo = $false
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to retrieve teaming policy for {0}." -f @($vpg.Name))
                                            $goodToGo = $false
                                        }
                                    }
                                    else # NOT ($teamingPolicyParams.Count -gt 0)
                                    {
                                        # FALSE

                                        ReportWarning ("{0} has no uplinks." -f @(Quoted $vpg.Name))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to add distributed port group {0} to {1}." -f @((Quoted $dsConfig.portGroups[$a].name), (Quoted $vds.Name)))
                                    $goodToGo = $false
                                }
                            }
                            else # NOT ($doIt)
                            {
                                # FALSE

                                ReportNotice ("Simulated creating port group {0} on {1}." -f @((Quoted $dsConfig.portGroups[$a].name), (Quoted $vds.Name)))
                            }
                        }
                        $a++
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @(Quoted $dsConfig.name))
                    $goodToGo = $false
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                $goodToGo = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $goodToGo = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $goodToGo = $false
    }

    return $goodToGo
}

function AddHostToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.Vds.Types.V1.VDSwitch] $vds,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $hostDef,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $true
    try
    {
        $vmHost = Get-VMHost -Server $viServer -Name $hostDef.vmHostName -ErrorAction Stop

        # Make sure $vmHost is not already attached to $vds
        if ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
        {
            # TRUE

            if ($DoIt)
            {
                # TRUE

                try
                {
                    Add-VDSwitchVMHost -VDSwitch $vds -VMHost $vmHost -Server $viServer -ErrorAction Stop
                    ReportSuccess ("Added {0} to {1}." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
                }
                catch
                {
                    ReportError ("Failed to add {0} to {1}." -f @((Quoted $hostDef.vmHostName), (Quoted $vds.Name)))
                    $goodToGo = $false
                }
            }
            else # NOT ($DoIt)
            {
                # FALSE

                ReportNotice ("Simulated adding {0} to {1}." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
            }
        }
        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
        {
            # FALSE

            ReportWarning ("{0} is already attached to {1}." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
        }
    }
    catch
    {
        ReportError ("Unable to find a VM host named: {0}." -f @((Quoted $hostDef.vmHostName)))
        $goodToGo = $false
    }

    return $goodToGo
}

function AddHostsToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $datacenterName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Object[]] $hostDefs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                try
                {
                    $vds = Get-VDSwitch -Server $viServer -Location $datacenterName -Name $dsConfig.name -ErrorAction Stop

# TODO: Add check of $hosts here.

                    $a = 0
                    while($goodToGo -and ($null -ne $vds) -and ($a -lt $hostDefs.Length))
                    {
                        $goodToGo = AddHostToVDS -viServer $viServer -vds $vds -host $hostDefs[$a] -DoIt:$DoIt -doReportSuccess:$doReportSuccess

                        $a++
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @(Quoted $dsConfig.name))
                    $goodToGo = $false
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                $goodToGo = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $goodToGo = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $goodToGo = $false
    }

    return $goodToGo
}

function LiberateVMNIC
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $vmNICName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $doReportSuccess
    )

    # Flag if the vmnic is unassigned...assume it is not.
    $vmnicIsFree = $false
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if (-not [String]::IsNullOrEmpty($vmHostName))
            {
                # TRUE

                if (-not [String]::IsNullOrEmpty($vmNICName))
                {
                    # TRUE

                    try
                    {
                        $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction SilentlyContinue
                    }
                    catch { }

                    if ($null -ne $vmHost)
                    {
                        # TRUE

                        # Try to shortcircuit the hunt for a switch $vmHost is connected to using a vmnic named $vmNICName...
                        try
                        {
                            $vmnic = Get-VMHostNetworkAdapter -Server $viServer -Physical -Name $vmNICName -VMHost $vmHost -ErrorAction Stop

                            # Use the following to determine if a matching vmnic was found on a standard or distributed switch...
                            $vNICStandardSwitch = $null
                            $vmnicUplink = $null

                            # Ok, didn't throw an error looking for vmnic, so let's try to see where it's connected

                            # If $vmNICName is connected to a standard switch, try to remove it
                            try
                            {
                                $vNICStandardSwitch = Get-VirtualSwitch -VMHost $vmHost -Standard -ErrorAction Stop | Where-Object { $_.Nic -contains $vmNICName }

                                # Did we find a standard switch with a NIC name of $vmNICName for $vmHost
                                if ($null -ne $vNICStandardSwitch)
                                {
                                    try
                                    {
                                        $vmnic = Get-VMHostNetworkAdapter -Server $viServer -VirtualSwitch $vNICStandardSwitch -Physical -Name $vmNICName -VMHost $vmHost -ErrorAction Stop

                                        if ($DoIt)
                                        {
                                            # TRUE

                                            try
                                            {
                                                Remove-VirtualSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmnic -Confirm:$false -ErrorAction Stop

                                                if ($doReportSuccess)
                                                {
                                                    # TRUE

                                                    ReportSuccess ("Removed {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vNICStandardSwitch.Name))
                                                }
                                                else # NOT ($doReportSuccess)
                                                {
                                                    # FALSE

                                                    # Nothing.
                                                }

                                                # We have liberated the vmnic from it's owning switch
                                                $vmnicIsFree = $true
                                            }
                                            catch
                                            {
                                                ReportError ("Failed to remove {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vNICStandardSwitch.Name))
                                            }
                                        }
                                        else # NOT ($DoIt)
                                        {
                                            # FALSE

                                            ReportNotice ("Simulated removing {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vNICStandardSwitch.Name))

                                            # We have simulated liberating the vmnic from it's owning switch
                                            $vmnicIsFree = $true
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Failed to locate {0}:{1} on {1}." -f @($vmHost.Name, $vmNICName, $vNICStandardSwitch.Name))
                                    }
                                }
                                else # NOT ($null -ne $vNICStandardSwitch)
                                {
                                    # FALSE

                                    # Nothing, vmnic isn't connected to a standard switch
                                }
                            }
                            catch
                            {
                                # Nothing, This vmHost is not connected to any standard switches.
                            }

                            # If the vmnic was not found on a standard switch, check to see if it's assigned to a distributed switch.
                            if ($null -eq $vNICStandardSwitch)
                            {
                                # TRUE

                                try
                                {
                                    # Get all the distributed switches $vmHost is connected to.
                                    $vDSwitches = @(Get-VDSwitch -Server $viServer -VMHost $vmHost -ErrorAction Stop)

                                    # If vmHost is not connected to any distributed switches, then it stands to reason, its vmnic named $vmNICName is also not connected to a distributed switch
                                    $vmnicIsFree = $vDSwitches.Length -eq 0

                                    $a = 0
                                    while(($null -eq $vmnicUplink) -and ($a -lt $vDSwitches.Length))
                                    {
                                        try
                                        {
                                            $vmnicUplink = Get-VDPort -Server $viServer -VDSwitch $vDSwitches[$a] -Uplink -ErrorAction Stop | Where-Object { ($_.ProxyHost.Name -eq $vmHost.Name) -and  ($_.ConnectedEntity.DeviceName -eq $vmNICName) }

                                            # Did we find a vmnic on $vDSwitches[$a] for $vmHost:$vmNICName?
                                            if ($null -ne $vmnicUplink)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $vmnic = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -Physical -Name $vmnicUplink.ConnectedEntity.DeviceName -ErrorAction Stop

                                                    if ($null -ne $vmnic)
                                                    {
                                                        # TRUE

                                                        if ($DoIt)
                                                        {
                                                            # TRUE

                                                            try
                                                            {
                                                                Remove-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmnic -ErrorAction Stop

                                                                if ($doReportSuccess)
                                                                {
                                                                    # TRUE

                                                                    ReportSuccess ("Removed {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vDSwitches[$a].Name))
                                                                }
                                                                else # NOT ($doReportSuccess)
                                                                {
                                                                    # FALSE

                                                                    # Nothing.
                                                                }

                                                                # We have liberated the vmnic from it's owning switch
                                                                $vmnicIsFree = $true
                                                            }
                                                            catch
                                                            {
                                                                ReportError ("Failed to remove {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vDSwitches[$a].Name))
                                                            }
                                                        }
                                                        else # NOT ($DoIt)
                                                        {
                                                            # FALSE

                                                            ReportNotice ("Simulated removing {0}:{1} from {2}." -f @($vmHost.Name, $vmnic.Name, $vDSwitches[$a].Name))

                                                            # We have liberated the vmnic from it's owning switch
                                                            $vmnicIsFree = $true
                                                        }
                                                    }
                                                    else # NOT ($null -ne $vmnic)
                                                    {
                                                        # FALSE

                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to locate {0} on {1} that is connected to {2}." -f @($vmNICName, $vmHost.Name, $vDSwitches[$a].Name))
                                                }
                                            }
                                            else # NOT ($null -ne $vmnicUplink)
                                            {
                                                # FALSE

                                                # Nothing -- vmnic not found on this distributed switch.
                                            }
                                        }
                                        catch
                                        {
                                            # Nothing, $vmNICName is not on this distributed switch
                                        }

                                        $a++
                                    }
                                }
                                catch
                                {
                                    # Nothing, $vmHost is not connected to any distributed switches.
                                }
                            }
                            else # NOT ($null -eq $vNICStandardSwitch)
                            {
                                # FALSE

                                # Nothing.  The vmnic was attached to a standard switch -- and hopefully removed.
                            }

                            # Did we unassign the vmnic ... OR ... was it not assigned to either a standard switch or a distributed switch
                            $vmnicIsFree = $vmnicIsFree -or (($null -eq $vNICStandardSwitch) -and ($null -eq $vmnicUplink))
                        }
                        catch
                        {
                            # Nothing, there is no vmnic on $vmHost named $vNICName ...
                        }
                    }
                    else # NOT ($null -ne $vmHost)
                    {
                        # FALSE

                        ReportError ("Unable to acquire VM host with name {0} in {1}." -f @($vmHostName, $MyInvocation.MyCommand.Name))
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($vmNICName))
                {
                    # FALSE

                    ReportError ("Missing virtual NIC name in {0}." -f @($MyInvocation.MyCommand.Name))
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($vmHostName))
            {
                # FALSE

                ReportError ("Missing VM host name in {0}." -f @($MyInvocation.MyCommand.Name))
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }

    return $vmnicIsFree
}

function SetVDSUplink
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $distributedSwitchName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [String] $vmNICName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [String] $uplinkName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $doReportSuccess
    )

    $retval = $false
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if (-not [String]::IsNullOrEmpty($vmHostName))
            {
                # TRUE

                if (-not [String]::IsNullOrEmpty($distributedSwitchName))
                {
                    # TRUE

                    if (-not [String]::IsNullOrEmpty($vmNICName))
                    {
                        # TRUE

                        if (-not [String]::IsNullOrEmpty($uplinkName))
                        {
                            # TRUE

                            try
                            {
                                $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop
                                try
                                {
                                    $netSys = Get-View -Server $viServer -Id $vmHost.ExtensionData.ConfigManager.NetworkSystem -ErrorAction Stop

                                    try
                                    {
                                        $vds = Get-VDSwitch -Server $viServer -Name $distributedSwitchName -ErrorAction Stop

                                        try
                                        {
                                            $uplinks = @(Get-VDPort -VDSwitch $vds -Uplink -ErrorAction Stop | Where-Object { ($_.ProxyHost.Name -eq $vmHost.Name) })

                                            $config = [VMware.Vim.HostNetworkConfig]::new()
                                            $proxySwitchCfg = [VMware.Vim.HostProxySwitchConfig]::new()
                                            $proxySwitchCfg.Uuid = $vds.ExtensionData.Uuid
                                            $proxySwitchCfg.ChangeOperation = [VMware.Vim.HostConfigChangeOperation]::edit
                                            $proxySwitchCfg.Spec = [VMware.Vim.HostProxySwitchSpec]::new()
                                            $proxySwitchCfg.Spec.Backing = [VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking]::new()

                                            $a = 0
                                            while($a -lt $uplinks.Length)
                                            {
                                                $pNICSpec = [VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec]::new()
                                                $pNICSpec.UplinkPortKey = $uplinks[$a].Key

                                                if ($uplinks[$a].Name -eq $uplinkName)
                                                {
                                                    # TRUE

                                                    $pNICSpec.PnicDevice = $vmNICName
                                                }
                                                else # NOT ($uplinks[$a].Name -eq $uplinkName)
                                                {
                                                    # FALSE

                                                    if ($null -ne $uplinks[$a].ConnectedEntity)
                                                    {
                                                        # TRUE

                                                        $pNICSpec.PnicDevice = $uplinks[$a].ConnectedEntity.Name
                                                    }
                                                    else # NOT ($null -ne $uplinks[$a].ConnectedEntity)
                                                    {
                                                        # FALSE

                                                        $pNICSpec = $null
                                                    }
                                                }

                                                # Only add $pNICSpec to $proxySwitchCfg.Spec.Backing.pNICSpec if there is a physical device name.
                                                if ($null -ne $pNICSpec)
                                                {
                                                    # TRUE
                                                    $proxySwitchCfg.Spec.Backing.pNICSpec += $pNICSpec
                                                }
                                                else # NOT ($null -ne $pNICSpec.PnicDevice)
                                                {
                                                    # FALSE

                                                    # Nothing.
                                                }

                                                $a++
                                            }

                                            $config.ProxySwitch += $proxySwitchCfg

                                            if ($DoIt)
                                            {
                                                # TRUE

                                                # Make sure the vmnic is not in use...
                                                if (LiberateVMNIC -viServer $viServer -vmHostName $vmHostName -vmNICName $vmNICName -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                                                {
                                                    # TRUE

                                                    try
                                                    {
                                                        $Error.Clear()
                                                        $netSys.UpdateNetworkConfig($config,[VMware.Vim.HostConfigChangeMode]::modify)

                                                        if ($doReportSuccess)
                                                        {
                                                            # TRUE

                                                            ReportSuccess ("Attached {0}:{1} to {2}:{3}" -f @($vmHost.Name, $vmNicName, $vds.Name, $uplinkName))
                                                        }
                                                        else # NOT ($doReportSuccess)
                                                        {
                                                            # FALSE

                                                            # Nothing.
                                                        }

                                                        $retval = $true
                                                    }
                                                    catch
                                                    {
                                                        ReportError ("Failed to attach {0}:{1} to {2}:{3}" -f @($vmHost.Name, $vmNicName, $vds.Name, $uplinkName))
                                                    }
                                                }
                                                else # NOT (LiberateVMNIC -viServer $viServer -vmHostName $vmHostName -vmNICName $vmNICName -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                                                {
                                                    # FALSE

                                                    ReportError ("{0}:{1} must first be removed from any switches it is connected to." -f @($vmHost.Name, $vmNICName))
                                                }
                                            }
                                            else # NOT ($DoIt)
                                            {
                                                # FALSE

                                                ReportNotice ("Simulated adding {0}:{1} to {2}:{3}" -f @($vmHostName, $vmNICName, $distributedSwitchName, $uplinkName))
                                                $retval = $true
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("No uplink ports found on distributed switch with name {0} in {1}." -f @($distributedSwitchName, $MyInvocation.MyCommand.Name))
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Unable to acquire distributed switch with name {0} in {1}." -f @($distributedSwitchName, $MyInvocation.MyCommand.Name))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Unable to acquire a view to {0}'s network system in {1}." -f @($vmHost.Name, $MyInvocation.MyCommand.Name))
                                }
                            }
                            catch
                            {
                                ReportError ("Unable to acquire VM host with name {0} in {1}." -f @($vmHostName, $MyInvocation.MyCommand.Name))
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($uplinkName))
                        {
                            # FALSE

                            ReportError ("Missing uplink port name in {0}." -f @($MyInvocation.MyCommand.Name))
                        }
                    }
                    else # NOT (-not [String]::IsNullOrEmpty($vmNICName))
                    {
                        # FALSE

                        ReportError ("Missing virtual NIC name in {0}." -f @($MyInvocation.MyCommand.Name))
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($distributedSwitchName))
                {
                    # FALSE

                    ReportError ("Missing distributed switch name in {0}." -f @($MyInvocation.MyCommand.Name))
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($vmHostName))
            {
                # FALSE

                ReportError ("Missing VM host name in {0}." -f @($MyInvocation.MyCommand.Name))
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }

    return $retval
}

function MigrateHostVMNICsToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Cisco.Ucsm.UcsHandle] $ucsManager,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $vdsName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Object] $hostDef,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="ExcludeVMNIC0")]
        [Switch] $AllvmNICs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="ExcludeVMNIC0")]
        [Switch] $ExcludevmNIC0,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="OnlyVMNIC0")]
        [Switch] $OnlyvmNIC0,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $doReportSuccess
    )

    $vmNICsMigrated = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        if ($viServer.IsConnected)
        {
            if ($null -ne $ucsManager)
            {
                if ($null -eq $Global:ucsData)
                {
                    GetUCSData -ucsManager $ucsManager -doReportSuccess:$doReportSuccess
                }
                else # NOT ($null -eq $Global:ucsData)
                {
                    # Nothing, already have UCS Data
                }

                # Since we might have tried to get UCS data just above, I need to check again.
                if ($null -ne $Global:ucsData)
                {
                    if (-not [String]::IsNullOrEmpty($vdsName))
                    {
                        try
                        {
                            $vds = Get-VDSwitch -Server $viServer -Name $vdsName -ErrorAction Stop

                            if ($null -ne $vds)
                            {
                                try
                                {
                                    $vmHost = Get-VMHost -Server $viServer -Name $hostDef.vmHostName -ErrorAction Stop

                                    if ($null -ne $vmHost)
                                    {
                                        # Make sure $vmHost is attached to $vds
                                        if ($null -ne ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                                        {
                                            $ucsServer = $Global:ucsData.Servers | Where-Object { $_.Serial -eq $hostDef.serial }

                                            if ($null -ne $ucsServer)
                                            {
                                                try
                                                {
                                                    $vmNICs = @(Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -Physical -ErrorAction Stop)

                                                    # Drop vmnic0 if we have been requested to $ExcludeVMNIC0
                                                    if ($ExcludeVMNIC0)
                                                    {
                                                        $vmNICs = @($vmNICs | Where-Object { $_.Name -ne "vmnic0" })
                                                    }
                                                    else # NOT ($ExcludeVMNIC0)
                                                    {
                                                        # Nothing.
                                                    }

                                                    # Drop all BUT vmnic0 if we have been requested to migrate $OnlyVMNIC0
                                                    if ($OnlyVMNIC0)
                                                    {
                                                        $vmNICs = @($vmNICs | Where-Object { $_.Name -eq "vmnic0" })
                                                    }
                                                    else # NOT ($OnlyVMNIC0)
                                                    {
                                                        # Nothing.
                                                    }

                                                    if ($vmNICs.Length -gt 0)
                                                    {
                                                        $b = 0
                                                        while($vmNICsMigrated -and ($b -lt $vmNICs.Length))
                                                        {
                                                            $ucsVMNICAdaptor = $Global:ucsData.Adaptors | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) -and ($_.Mac -eq $vmNICs[$b].Mac) }

                                                            if ($null -ne $ucsVMNICAdaptor)
                                                            {
                                                                $vmNICUplinkName = $null    # Reset for each loop.
                                                                $vmNICUplinkName = $dsConfig.uplinkMappings | Where-Object { $_.vNICName -eq $ucsVMNICAdaptor.Name } | Select-Object -Unique -ExpandProperty uplinkName

                                                                if (-not [String]::IsNullOrEmpty($vmNICUplinkName))
                                                                {
                                                                    [void] (SetVDSUplink -viServer $viServer -vmHostName $vmHost.Name -distributedSwitchName $vds.name -vmNICName $vmNICs[$b].Name -uplinkName $vmNICUplinkName -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                                                                }
                                                                else # NOT (-not [String]::IsNullOrEmpty($vmNICUplinkName))
                                                                {
                                                                    ReportError ("Unable to determine uplink name for {0}." -f @(Quoted (@($vmHost.Name, $vmNICs[$b].Name) -join ":")))
                                                                    $vmNICsMigrated = $false
                                                                }
                                                            }
                                                            else # NOT ($null -ne $ucsVMNICAdaptor)
                                                            {
                                                                ReportError ("Unable to determine uplink adaptor for {0}." -f @(Quoted (@($vmHost.Name, $vmNICs[$b].Name) -join ":")))
                                                                $vmNICsMigrated = $false
                                                            }
                                                            $b++
                                                        }
                                                    }
                                                    else # NOT ($vmNICs.Length -gt 0)
                                                    {
                                                        ReportError ("Unable to retrieve vmnics for {0}." -f @(Quoted $vmHost.Name))
                                                        $vmNICsMigrated = $false
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Unable to retrieve VMNICs from VM host {0}." -f @(Quoted $hostDef.vmHostName))
                                                    $vmNICsMigrated = $false
                                                }
                                            }
                                            else # NOT ($null -ne $ucsServer)
                                            {
                                                ReportError ("No UCS compute node found for {0} serial number {1}" -f @((Quoted $vmHost.Name), (Quoted $hostDef.serial)))
                                                $vmNICsMigrated = $false
                                            }
                                        }
                                        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                                        {
                                            ReportError ("{0} must be attached to {1} before it's vmnics can be migrated." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
                                            $vmNICsMigrated = $false
                                        }
                                    }
                                    else # NOT ($null -ne $vmHost)
                                    {
                                        ReportError ("Unable to locate VM host named {0}." -f @(Quoted $hostDef.vmHostName))
                                        $vmNICsMigrated = $false
                                    }
                                }
                                catch
                                {
                                    ReportError ("Unable to locate VM host named {0}." -f @(Quoted $hostDef.vmHostName))
                                    $vmNICsMigrated = $false
                                }
                            }
                            else # NOT ($null -ne $vds)
                            {
                                ReportError ("Distributed switch {0} does not exist." -f @(Quoted $dsConfig.name))
                                $vmNICsMigrated = $false
                            }
                        }
                        catch
                        {
                            ReportError ("Distributed switch {0} does not exist." -f @(Quoted $vdsName))
                            $vmNICsMigrated = $false
                        }
                    }
                    else # NOT (-not [String]::IsNullOrEmpty($vdsName))
                    {
                        ReportError ("No distributed switch name provided.")
                        $vmNICsMigrated = $false
                    }
                }
                else # NOT ($null -ne $Global:ucsData)
                {
                    ReportError ("Unable to continue without UCS Data.")
                    $vmNICsMigrated = $false
                }
            }
            else # NOT ($null -ne $ucsManager)
            {
                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmNICsMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $vmNICsMigrated = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $vmNICsMigrated = $false
    }

    return $vmNICsMigrated
}

function MigrateHostsVMNICsToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Cisco.Ucsm.UcsHandle] $ucsManager,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Object[]] $hostDefs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="ExcludeVMNIC0")]
        [Switch] $AllvmNICs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="ExcludeVMNIC0")]
        [Switch] $ExcludevmNIC0,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4, ParameterSetName="OnlyVMNIC0")]
        [Switch] $OnlyvmNIC0,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $doReportSuccess
    )

    $vmNICsMigrated = $true

    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $ucsManager)
            {
                # TRUE

                if ($null -eq $Global:ucsData)
                {
                    # TRUE

                    GetUCSData -ucsManager $ucsManager -doReportSuccess:$doReportSuccess
                }
                else # NOT ($null -eq $Global:ucsData)
                {
                    # FALSE

                    # Nothing, already have UCS Data
                }

                # Since we might have tried to get UCS data just above, I need to check again.
                if ($null -ne $Global:ucsData)
                {
                    # TRUE

                    if ($null -ne $dsConfig)
                    {
                        $a = 0
                        while($a -lt $hostDefs.Length)
                        {
                            if ($AllvmNICS)
                            {
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucsManager $ucsManager -vdsName $dsConfig.name -host $hostDefs[$a] -AllvmNICs -DoIt -doReportSuccess
                            } `
                            elseif ($ExcludevmNIC0)
                            {
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucsManager $ucsManager -vdsName $dsConfig.name -host $hostDefs[$a] -ExcludevmNIC0 -DoIt -doReportSuccess
                            }
                            elseif ($OnlyvmNIC0)
                            {
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucsManager $ucsManager -vdsName $dsConfig.name -host $hostDefs[$a] -OnlyvmNIC0 -DoIt -doReportSuccess
                            }
                            else
                            {
                                # Nothing.
                            }

                            $a++
                        }
                    }
                    else # NOT ($null -ne $dsConfig)
                    {
                        # FALSE

                        ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                        $vmNICsMigrated = $false
                    }
                }
                else # NOT ($null -ne $Global:ucsData)
                {
                    # FALSE

                    ReportError ("Unable to continue without UCS Data.")
                    $vmNICsMigrated = $false
                }
            }
            else # NOT ($null -ne $ucsManager)
            {
                # FALSE

                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmNICsMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $vmNICsMigrated = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $vmNICsMigrated = $false
    }

    return $vmNICsMigrated
}

function MigrateVMK
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl] $vmHost,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.Vds.Types.V1.VDSwitch] $vds,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [VMware.VimAutomation.Vds.Types.V1.VmwareVDPortgroup] $vpg,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.Nic.HostVMKernelVirtualNicImpl] $existingVMK,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Object] $vmkDef,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $doReportSuccess
    )

    $vmkChanged = $false
    $vmksMigrated = $false
    if ($DoIt)
    {
        try
        {
            $vmk = Set-VMHostNetworkAdapter -VirtualNic $existingVMK -PortGroup $vpg -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue

            if ($doReportSuccess)
            {
                ReportSuccess ("Migrated {0}:{1} (IP/subnet mask: {2}/{3}) to Switch/portgroup: {4}/{5}" -f @($vmHost.Name, $vmk.Name, $vmk.IP, $vmk.SubnetMask, $vds.Name, $vpg.Name))
                $vmkChanged = $true
                $vmksMigrated = $true
            }
            else # NOT ($doReportSuccess)
            {
                # Nothing.
            }
        }
        catch
        {
            ReportError ("Failed to migrate {0}:{1} to (IP/subnet mask: {2}/{3}), Switch/portgroup: {4}/{5}" -f @($vmHost.Name, $vmkDef.vmkName, $vmkDef.ipAddress, $vmkDef.subnetMask, $vds.Name, $vpg.Name))
        }
    }
    else # NOT ($DoIt)
    {
        ReportNotice ("Simulated migrating {0}:{1} ({2}/{3}) to {4}:{5}" -f @($vmHost.Name, $existingVMK.Name, $existingVMK.IP, $existingVMK.SubnetMask, $vds.Name, $vpg.Name))
        $vmkChanged = $false
        $vmksMigrated = $true   # We simulated it...
    }

    return @($vmkChanged, $vmksMigrated)
}

function MigrateHostVMKsToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [String] $vdsName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $hostDef,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $vmksMigrated = $true
    $success = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        if ($viServer.IsConnected)
        {
            if (-not [String]::IsNullOrEmpty($vdsName))
            {
                try
                {
                    $vds = Get-VDSwitch -Server $viServer -Name $vdsName -ErrorAction Stop

                    try
                    {
                        $vmHost = Get-VMHost -Server $viServer -Name $hostDef.vmHostName -ErrorAction Stop

                        # Make sure $vmHost is attached to $vds
                        if ($null -ne ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                        {
                            $a = 0
                            while($vmksMigrated -and ($a -lt $hostDef.vmks.Length))
                            {
                                # Make sure the port group the vmk is to be assigned to exists.
                                try
                                {
                                    $vpg = Get-VDPortGroup -Server $viServer -VDSwitch $vds -Name $hostDef.vmks[$a].portGroupName -ErrorAction Stop

                                    # There might need to be 2 passes when updating the VMK...
                                    #   If the VMK exists, but is on the wrong switch and/or port group, then it is migrated to the correct switch/port group.  A second pass
                                    #   is used to ensure IP/subnet mask/management enabled/vMotion enabled/MTU is correctly set.
                                    #
                                    #  If the VMK exists and is on the right switch/port group, then IP/subnet mask/management enabled/vMotion enabled, MTU is checked and potentially updated.

                                    # Set $vmkChange = $true to ensure we run through the loop at least once...
                                    $vmkChanged = $true
                                    while($vmkChanged -and $success)
                                    {
                                        # Now that we've entered the loop, don't run it again, unless we need to...
                                        $vmkChanged = $false


                                    }
                                    # Later version might update the settings of the VMK...
                                    $needToSetVMK = $false
                                    $existingVMK = $null
                                    try
                                    {
                                        # First, check to see if VMKx exists and is connected to the correct switch/port group.
                                        $existingVMK = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -VMKernel -Name $hostDef.vmks[$a].vmkName -VirtualSwitch $vds -PortGroup $vpg -ErrorAction Stop

                                        # There is an existing VMK already connected to the right switch and port group or the previous line would have thrown an error.
                                        ReportNotice ("{0}:{1} is already connected to {2}/{3}." -f @($vmHost.Name, $hostDef.vmks[$a].vmkName, $vds.Name, $vpg.Name))

                                        # Check IP
                                        if ($existingVMK.IP -ne $hostDef.vmks[$a].ipAddress)
                                        {
                                            ReportWarning ("`tIP address mismatch.  Should be: {0}, Is: {1}." -f @($hostDef.vmks[$a].ipAddress, $existingVMK.IP))
                                            $needToSetVMK = $true
                                        } `
                                        else # NOT ($existingVMK.IP -ne $hostDef.vmks[$a].ipAddress)
                                        {
                                            # Nothing.
                                        }

                                        # Check subnet mask
                                        if ($existingVMK.SubnetMask -ne $hostDef.vmks[$a].subnetMask)
                                        {
                                            ReportWarning ("`tSubnet mask mismatch.  Should be: {0}, Is: {1}." -f @($hostDef.vmks[$a].subnetMask, $existingVMK.SubnetMask))
                                            $needToSetVMK = $true
                                        } `
                                        else # NOT ($existingVMK.SubnetMask -ne $hostDef.vmks[$a].subnetMask)
                                        {
                                            # Nothing.
                                        }

                                        # Check management enabled..
                                        if ($existingVMK.ManagementTrafficEnabled -ne $hostDef.vmks[$a].mgmtEnabled)
                                        {
                                            ReportWarning ("`tManagement enablement mismatch.  Should be: {0}. Is: {1}." -f @($hostDef.vmks[$a].mgmtEnabled, $existingVMK.ManagementTrafficEnabled))
                                            $needToSetVMK = $true
                                        } `
                                        else # NOT ($existingVMK.ManagementTrafficEnabled -ne $hostDef.vmks[$a].mgmtEnabled)
                                        {
                                            # Nothing.
                                        }

                                        # Check vMotion enabled..
                                        if ($existingVMK.vMotionEnabled -ne $hostDef.vmks[$a].vMotionEnabled)
                                        {
                                            ReportWarning ("`tvMotion enablement mismatch.  Should be: {0}, Is: {1}." -f @($hostDef.vmks[$a].vMotionEnabled, $existingVMK.vMotionEnabled))
                                            $needToSetVMK = $true
                                        } `
                                        else # NOT ($existingVMK.vMotionEnabled -ne $hostDef.vmks[$a].vMotionEnabled)
                                        {
                                            # Nothing.
                                        }

                                        # Check MTU..
                                        if ($existingVMK.Mtu -ne $hostDef.vmks[$a].mtu)
                                        {
                                            ReportWarning ("`tMTU mismatch.  Should be: {0}, Is: {1}." -f @($hostDef.vmks[$a].mtu, $existingVMK.Mtu))
                                            $needToSetVMK = $true
                                        } `
                                        else # NOT ($existingVMK.Mtu -ne $hostDef.vmks[$a].mtu)
                                        {
                                            # Nothing.
                                        }

                                        if ($needToSetVMK)
                                        {
                                            $setVMKParams = @{
                                                VirtualNic = $existingVMK
                                                VMotionEnabled = $hostDef.vmks[$a].vMotionEnabled
                                                ManagementTrafficEnabled = $hostDef.vmks[$a].mgmtEnabled
                                                IP = $hostDef.vmks[$a].ipAddress
                                                SubnetMask = $hostDef.vmks[$a].subnetMask
                                                Mtu = $hostDef.vmks[$a].mtu
                                                Confirm = $false
                                                ErrorAction = "Stop"
                                                WarningAction = "SilentlyContinue"
                                            }

                                            if ($DoIt)
                                            {
                                                try
                                                {
                                                    $vmk = Set-VMHostNetworkAdapter @setVMKParams

                                                    if ($doReportSuccess)
                                                    {
                                                        ReportSuccess ("Updated {0}:{1} (IP/subnet mask: {2}/{3}), Switch/portgroup: {4}/{5}, Management Enabled: {6}, vMotion Enabled: {7}" -f @($vmHost.Name, $vmk.Name, $vmk.IP, $vmk.SubnetMask, $vds.Name, $vpg.Name, $vmk.ManagementTrafficEnabled, $vmk.vMotionEnabled))
                                                        $vmkChanged = $true
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to updated {0}:{1} to (IP/subnet mask: {2}/{3}), Switch/portgroup: {4}/{5}, Management Enabled: {6}, vMotion Enabled: {7}" -f @($vmHost.Name, $hostDef.vmks[$a].vmkName, $hostDef.vmks[$a].ipAddress, $hostDef.vmks[$a].subnetMask, $vds.Name, $vpg.Name, $hostDef.vmks[$a].mgmtEnabled,$hostDef.vmks[$a].vMotionEnabled))
                                                    $vmksMigrated = $false
                                                }
                                            }
                                            else # NOT ($DoIt)
                                            {
                                                ReportNotice ("Simulated updating {0}:{1} to (IP/subnet mask: {2}/{3}), Switch/portgroup: {4}/{5}, Management Enabled: {6}, vMotion Enabled: {7}" -f @($vmHost.Name, $hostDef.vmks[$a].vmkName, $hostDef.vmks[$a].ipAddress, $hostDef.vmks[$a].subnetMask, $vds.Name, $vpg.Name, $hostDef.vmks[$a].mgmtEnabled,$hostDef.vmks[$a].vMotionEnabled))
                                            }
                                        } `
                                        else # NOT ($needToSetVMK)
                                        {
                                            # Nothing.
                                        }
                                    }
                                    catch
                                    {
                                        # No perfectly matching VMK was found, so an exception was thrown...

                                        try
                                        {
                                            # Check for a less specific VMK... one that is connected to the right switch, but wrong portgroup...
                                            $existingVMK = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -VMKernel -Name $hostDef.vmks[$a].vmkName -VirtualSwitch $vds -ErrorAction Stop

                                            # No exception was thrown, so we found VMKx... but it's on the wrong port group...so move it.
                                            $vmkChanged, $vmksMigrated = MigrateVMK -vmHost $vmHost -vds $vds -vpg $vpg -existingVMK $existingVMK -vmkDef $hostDef.vmks[$a] -DoIt:$doIt -doReportSuccess:$doReportSuccess
                                        }
                                        catch
                                        {
                                            # Nope, VMKx is not connected to the correct switch...

                                            try
                                            {
                                                # Check for a less specific VMK... does VMKx even exist?
                                                $existingVMK = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -VMKernel -Name $hostDef.vmks[$a].vmkName  -ErrorAction Stop

                                                # No exception was thrown, so the VMK exists... Need to migrate the VMK to the correct switch/port group...
                                                $vmkChanged, $vmksMigrated = MigrateVMK -vmHost $vmHost -vds $vds -vpg $vpg -existingVMK $existingVMK -vmkDef $hostDef.vmks[$a] -DoIt:$doIt -doReportSuccess:$doReportSuccess
                                            }
                                            catch
                                            {
                                                # Nope, VMKx does not exist...

                                                # Create a new VMK
                                                $newVMKParams = @{
                                                    VMHost = $vmHost
                                                    PortGroup = $vpg.Name
                                                    VirtualSwitch = $vds
                                                    IP = $hostDef.vmks[$a].ipAddress
                                                    SubnetMask = $hostDef.vmks[$a].subnetMask
                                                    VMotionEnabled = $hostDef.vmks[$a].vMotionEnabled
                                                    ManagementTrafficEnabled = $hostDef.vmks[$a].mgmtEnabled
                                                    Mtu = $hostDef.vmks[$a].mtu
                                                }

                                                if ($DoIt)
                                                {
                                                    try
                                                    {
                                                        $vmk = New-VMHostNetworkAdapter @newVMKParams

                                                        if ($doReportSuccess)
                                                        {
                                                            ReportSuccess ("Created {0}:{1} ({2}/{3}) on {4}:{5}" -f @($vmHost.Name, $vmk.Name, $vmk.IP, $vmk.SubnetMask, $vds.Name, $vpg.Name))
                                                            # Don't need to reset $vmkChanged since we already set everything when the VMK was created.
                                                        }
                                                        else # NOT ($doReportSuccess)
                                                        {
                                                            # Nothing.
                                                        }
                                                    }
                                                    catch
                                                    {
                                                        ReportError ("Failed to create vmk adapter on {0} connected to {1}:{2}." -f @($vmHost.Name, $vds.name, $vpg.Name))
                                                        $vmksMigrated = $false
                                                    }
                                                }
                                                else # NOT ($DoIt)
                                                {
                                                    ReportNotice ("Simulated creating {0}:{1} ({2}/{3}) on {4}:{5}" -f @($vmHost.Name, $hostDef.vmks[$a].vmkName, $hostDef.vmks[$a].ipAddress, $hostDef.vmks[$a].subnetMask, $vds.Name, $vpg.Name))
                                                }
                                            }
                                        }
                                    }
                                }
                                catch
                                {
                                    ReportError ("Distributed port group {0} does not exist on {1}." -f @((Quoted $hostDef.vmks[$a].portGroupName), (Quoted $vds.Name)))
                                    $vmksMigrated = $false
                                }

                                $a++
                            }
                        }
                        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                        {
                            ReportError ("{0} must be attached to {1} before it's VM kernel adapters can be migrated." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
                            $vmksMigrated = $false
                        }
                    }
                    catch
                    {
                        ReportError ("Unable to locate VM host named {0}." -f @(Quoted $hostDef.vmHostName))
                        $vmksMigrated = $false
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @(Quoted $vdsName))
                    $vmksMigrated = $false
                }
            }
            else # NOT ([String]::IsNullOrEmpty($vdsName))
            {
                ReportError ("Missing distributed switch name in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmksMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $vmksMigrated = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $vmksMigrated = $false
    }

    return $vmksMigrated
}

function MigrateHostsVMKsToVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object[]] $hostDefs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $vmksMigrated = $true
    if ($null -ne $viServer)
    {
        if ($viServer.IsConnected)
        {
            if ($null -ne $dsConfig)
            {
                $a = 0
                while($vmksMigrated -and ($a -lt $hostDefs.Length))
                {
                    $vmksMigrated = MigrateHostVMKsToVDS -viServer $viServer -vdsName $dsConfig.name -host $hostDefs[$a] -DoIt:$DoIt -doReportSuccess:$doReportSuccess

                    $a++
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmksMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $vmksMigrated = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $vmksMigrated = $false
    }

    return $vmksMigrated
}

function MigrateVMKsToVDS_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object[]] $hosts,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $vmksMigrated = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                try
                {
                    $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                    $a = 0
                    while($vmksMigrated -and ($a -lt $hosts.Length))
                    {
                        try
                        {
                            $vmHost = Get-VMHost -Server $viServer -Name $hosts[$a].vmHostName -ErrorAction Stop

                            # Make sure $vmHost is attached to $vds
                            if ($null -ne ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                            {
                                # TRUE

                                $b = 0
                                while($vmksMigrated -and ($b -lt $hosts[$a].vmks.Length))
                                {
                                    # Make sure the port group the vmk is to be assigned to exists.
                                    try
                                    {
                                        $vpg = Get-VDPortGroup -Server $viServer -VDSwitch $vds -Name $hosts[$a].vmks[$b].portGroupName -ErrorAction Stop

                                        $existingVMK = $null
                                        try
                                        {
                                            $existingVMK = Get-VMHostNetworkAdapter -Server $viServer -VMHost $vmHost -VMKernel -Name $hosts[$a].vmks[$b].vmkName -ErrorAction Stop

                                            # There is an existing VMK or the previous line would have thrown an error.
                                            if ($DoIt)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $vmk = Set-VMHostNetworkAdapter -VirtualNic $existingVMK -PortGroup $vpg -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue
# TODO: Change for manangement/vMotion Enablement.
                                                    if ($doReportSuccess)
                                                    {
                                                        # TRUE

                                                        ReportSuccess ("Migrated {0}:{1} ({2}/{3}) to {4}:{5}" -f @($vmHost.Name, $vmk.Name, $vmk.IP, $vmk.SubnetMask, $vds.Name, $vpg.Name))
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # FALSE

                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to migrate {0}:{1} to {2}:{3}." -f @($vmHost.Name, $existingVMK.Name, $vds.name, $vpg.Name))
                                                    $vmksMigrated = $false
                                                }
                                            }
                                            else # NOT ($DoIt)
                                            {
                                                # FALSE

                                                ReportNotice ("Simulated migrating {0}:{1} ({2}/{3}) to {4}:{5}" -f @($vmHost.Name, $existingVMK.Name, $existingVMK.IP, $existingVMK.SubnetMask, $vds.Name, $vpg.Name))
                                            }
                                        }
                                        catch
                                        {
                                            # No matching VMK, so an exception was thrown...
                                            # Create a new VMK

                                            $newVMKParams = @{
                                                VMHost = $vmHost
                                                PortGroup = $vpg.Name
                                                VirtualSwitch = $vds
                                                IP = $hosts[$a].vmks[$b].ipAddress
                                                SubnetMask = $hosts[$a].vmks[$b].subnetMask
                                                VMotionEnabled = $hosts[$a].vmks[$b].vMotionEnabled
                                                ManagementTrafficEnabled = $hosts[$a].vmks[$b].mgmtEnabled
                                                Mtu = $hosts[$a].vmks[$b].mtu
                                            }

                                            if ($DoIt)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $vmk = New-VMHostNetworkAdapter @newVMKParams

                                                    if ($doReportSuccess)
                                                    {
                                                        # TRUE

                                                        ReportSuccess ("Created {0}:{1} ({2}/{3}) on {4}:{5}" -f @($vmHost.Name, $vmk.Name, $vmk.IP, $vmk.SubnetMask, $vds.Name, $vpg.Name))
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # FALSE

                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to create vmk adapter on {0} connected to {1}:{2}." -f @($vmHost.Name, $vds.name, $vpg.Name))
                                                    $vmksMigrated = $false
                                                }
                                            }
                                            else # NOT ($DoIt)
                                            {
                                                # FALSE

                                                ReportNotice ("Simulated creating {0}:{1} ({2}/{3}) on {4}:{5}" -f @($vmHost.Name, $hosts[$a].vmks[$b].vmkName, $hosts[$a].vmks[$b].ipAddress, $hosts[$a].vmks[$b].subnetMask, $vds.Name, $vpg.Name))
                                            }
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Distributed port group {0} does not exist on {1}." -f @((Quoted $hosts[$a].vmks[$b].portGroupName), (Quoted $vds.Name)))
                                        $vmksMigrated = $false
                                    }

                                    $b++
                                }
                            }
                            else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                            {
                                # FALSE

                                ReportError ("{0} must be attached to {1} before it's VM kernel adapters can be migrated." -f @((Quoted $vmHost.Name), (Quoted $vds.Name)))
                                $vmksMigrated = $false
                            }
                        }
                        catch
                        {
                            ReportError ("Unable to locate VM host named {0}." -f @(Quoted $hosts[$a].vmHostName))
                            $vmksMigrated = $false
                        }

                        $a++
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @(Quoted $dsConfig.name))
                    $vmksMigrated = $false
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmksMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $viServer.Name), $MyInvocation.MyCommand.Name))
            $vmksMigrated = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $vmksMigrated = $false
    }

    return $vmksMigrated
}

function FindDatastoreVMK
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $hostDef,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $datastoreDef
    )

    $vmk = $null

    # Convert the datastore NFS host's alphanumeric IPv4 into a UInt32
    $dsipA = INET_ATON $datastoreDef.nfsHost

    $found = $false
    $a = 0
    while((-not $found) -and ($a -lt $hostDef.vmks.Length))
    {
        # Convert the VMK's address and subnet mask into UInt32s
        $vmkipA = INET_ATON $hostDef.vmks[$a].ipAddress
        $vmksnM = INET_ATON $hostDef.vmks[$a].subnetMask

        $found = ($dsipA -band $vmksnM) -eq ($vmkipA -band $vmksnM)

        if (-not $found)
        {
            $a++
        } `
        else # NOT (-not $found)
        {
            $vmk = $hostDef.vmks[$a]
        }
    }

    return $vmk
}

function AllowESXiAccessToVolume
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [DataONTAP.C.Types.Volume.VolumeAttributes] $ncVolume,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $esxiHostAddress,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $modifyAccess,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $doReportSuccess
    )

    $clientIPAddr = INET_ATON -ipStr $esxiHostAddress
    $accessAllowed = $false
    $accessType = "read-only"
    if ($modifyAccess)
    {
        # TRUE
        $accessType = "modify"
    }
    else # NOT ($modifyAccess)
    {
        # FALSE

        # Nothing.
    }

    if($clientIPAddr -ne 0)
    {
        try
        {
            $exportPolicyRules = @(Get-NcExportRule -Controller $ncVolume.NcController -Vserver $ncVolume.Vserver -Policy $ncVolume.VolumeExportAttributes.Policy -ErrorAction Stop)

            $a = 0
            while((-not $accessAllowed) -and ($a -lt $exportPolicyRules.Length))
            {
                # Is this rule's ClientMatch a CIDR?  ex: 192.168.1.0/24
                if($exportPolicyRules[$a].ClientMatch -match "^(\d+\.\d+\.\d+\.\d+)/(\d+)$")
                {
                    $cidrMask = [Convert]::ToInt32($Matches[2], 10)
                    $netAddr = INET_ATON $Matches[1]
                    $bm = [Math]::Pow(2, (32 - $cidrMask)) - 1

                    $minIPAddr = $netAddr + 1               # Drop the network address
                    $maxIPAddr = ($netAddr -bor $bm) - 1    # Drop the multicast address

                    if(($minIPAddr -le $clientIPAddr) -and ($clientIPAddr -le $maxIPAddr))
                    {
                        $accessAllowed = $true
                    }
                }

                # Not a CIDR, then just an address?
                elseif ($exportPolicyRules[$a].ClientMatch -match "^(\d+\.\d+\.\d+\.\d+)$")
                {
                    $ruleAddr = INET_ATON $Matches[1]

                    if($clientIPAddr -eq $ruleAddr)
                    {
                        $accessAllowed = $true
                    }
                }
                else
                {
                    ReportWarning ("`t`tExport policy: {0}, rule index: {1} has an unknown ClientMatch: {2}." -f @($ncVolume.VolumeExportAttributes.Policy, ($a + 1), $exportPolicyRules[$a].ClientMatch))
                }

                if ($accessAllowed)
                {
                    # TRUE
                    ReportSuccess ("`t`tAccess type: {0} granted to {1} on {2}:{3}:{4} ({5}) via policy: {6}, rule index: {7}" -f @($accessType, $esxiHostAddress, $ncVolume.NcController.Name, $ncVolume.Vserver, $ncVolume.Name, $ncVolume.JunctionPath, $ncVolume.VolumeExportAttributes.Policy, ($a + 1)))
                }
                else # NOT ($accessAllowed)
                {
                    # FALSE

                    # Nothing.
                }

                $a++
            }

            if (-not $accessAllowed)
            {
                # TRUE - Need to add an export rule for $esxiHostAddress

                # Parameters to create a new "read-only" export rule:
                $newExportRuleParams = @{
                    ClientMatch = $esxiHostAddress
                    ReadOnlySecurityFlavor = "none"
                    ReadWriteSecurityFlavor = "none"
                    ChownMode = "restricted"
                    DisableDev = $false
                    DisableSetUid = $false
                    EnableDev = $true
                    EnableSetUid = $true
                    Index = $exportPolicyRules.Length + 1
                    NtfsUnixSecurityOps = "fail"
                    Protocol = "nfs"
                    SuperUserSecurityFlavor = "any"
                    Policy = $ncVolume.VolumeExportAttributes.Policy
                    VserverContext = $ncVolume.Vserver
                    NcController = $ncVolume.NcController
                    ErrorAction = "Stop"
                }

                if ($modifyAccess)
                {
                    # TRUE

                    $newExportRuleParams.ReadOnlySecurityFlavor = "sys"
                    $newExportRuleParams.ReadWriteSecurityFlavor = "sys"
                }
                else # NOT ($modifyAccess)
                {
                    # FALSE

                    # Nothing.
                }

                try
                {
                    New-NCExportRule @newExportRuleParams
                    if ($doReportSuccess)
                    {
                        ReportSuccess ("`t`tAccess type: {0} granted to {1} on {2}:{3}:{4} ({5}) via policy: {6}, rule index: {7}" -f @($accessType, $esxiHostAddress, $ncVolume.NcController.Name, $ncVolume.Vserver, $ncVolume.Name, $ncVolume.JunctionPath, $ncVolume.VolumeExportAttributes.Policy, $newExportRuleParams.Index))
                    }
                    else # NOT ($doReportSuccess)
                    {
                        # Nothing.
                    }

                    $accessAllowed = $true
                }
                catch
                {
                    ReportError ("`t`tFailed to create new export rule for {0} in policy {1}." -f @($esxiHostAddress, $ncVolume.VolumeExportAttributes.Policy))
                }
            }
            else # NOT (-not $allowedAccess)
            {
                # FALSE

                # Nothing.
            }
        }
        catch
        {
            ReportError ("`t`tFailed to retrieve export rules for policy {0} on {1}:{2}:{3}." -f @($ncVolume.VolumeExportAttributes.Policy, $ncVolume.NcController.Name, $ncVolume.Vserver, $ncVolume.Name))
        }
    }
    else
    {
        ReportError ("`t`tOdd!! Unable to convert {0} into an int32!" -f @($esxiHostAddress))
    }

    return $accessAllowed
}

function MountDatastoreToHost
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $datastoreDef,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [Object] $hostDef,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]]
         $cDot,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $success = $true
    if ($doReportSuccess)
    {
        ReportSuccess ("`tMounting datastore {0}:{1} {2}:{3} ({4}) to host {5}." -f @($a, $datastoreDef.Name, $datastoreDef.nfsHost, $datastoreDef.nfsPath, $datastoreDef.filer, $hostDef.vmHostName))
    }
    else # NOT ($doReportSuccess)
    {
        # Nothing.
    }

    # Identify which VMK will be used for connectivity to the datastore
    $storageVMKDef = FindDatastoreVMK $hostDef $datastoreDef
    if ($null -ne $storageVMKDef)
    {
        $hostStorageAddress = $storageVMKDef.ipAddress

        try
        {
            $vmHost = @(Get-VMHost -Server $viServer -Name $hostDef.vmHostName -ErrorAction Stop)

            if ($vmHost.Length -eq 1)
            {
                # TRUE

                $vmHost = $vmHost[0]
                if ($doReportSuccess)
                {
                    ReportSuccess ("`t`tVMHost: {0}" -f @($vmHost.Name))
                }
                else # NOT ($doReportSuccess)
                {
                    # Nothing.
                }

                try
                {
                    [void] (Get-Datastore -Server $viServer -RelatedObject $vmHost -Name $datastoreDef.Name -ErrorAction Stop)

                    ReportNotice ("`t`tDatastore {0} is already mounted to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                }
                catch
                {
                    # Nothing, the datastore is not mounted to the ESXi Host...

                    if ($cdot.Keys -contains $datastoreDef.filer)
                    {
                        $ncController = $cdot[$datastoreDef.filer]

                        if ($null -ne $ncController)
                        {
                            if ($doReportSuccess)
                            {
                                ReportSuccess ("`t`tNcController: {0}" -f @($ncController.Name))
                            }
                            else # NOT ($doReportSuccess)
                            {
                                # Nothing.
                            }
                            $nfsLIF = $null
                            try
                            {
                                $nfsLIF = @(Get-NCNetInterface -Controller $ncController -DataProtocols "nfs" | Where-Object { $_.Address -eq $datastoreDef.nfsHost } )

                                if ($nfsLIF.Length -eq 1)
                                {
                                    $nfsLIF = $nfsLIF[0]
                                }
                                elseif($nfsLIF.Length -eq 0)
                                {
                                    # No NFS LIFs matching $datastoreDef.nfsHost

                                    ReportError ("Failed to retrieve NFS network interface on {0} with IP Address: {1}." -f @($ncController.Name, $datastoreDef.nfsHost))
                                    $nfsLIF = $null
                                    $success = $false
                                }
                                else
                                {
                                    # Mulitple NFS LIFs matching $datastoreDef.nfsHost -- Is there a single VServer for them all??

                                    ReportWarning ("`tMultiple NFS LIFs ({0}) found with address: {1}" -f @($nfsLIF.Length, $datastoreDef.nfsHost))
                                    foreach($lif in $nfsLIF)
                                    {
                                        ReportWarning ("`t`tVServer: {0}, Name: {1}" -f @($lif.Vserver, $lif.Name))
                                    }
                                    $vServerNames = @($nfsLIF | Select-Object -Unique -ExpandProperty VServer)

                                    if ($vServerNames.Length -eq 1)
                                    {
                                        # TRUE

                                        # Saved, all the NFS LIFs matching $datastoreDef.nfsHost are on the same vServer, so arbitarily use [0]...
                                        $nfsLIF = $nfsLIF[0]

                                        ReportWarning ("`tAll NFS LIFS are hosted on the same VServer.  Using {0} going forward." -f @($nfsLIF.VServer))
                                    }
                                    else # NOT ($vServerNames.Length -eq 1)
                                    {
                                        ReportError ("`tUnable to determine VServer for {0}:{1}." -f @($datastoreDef.nfsHost, $datastoreDef.nfsPath))
                                        $nfsLIF = $null
                                    }
                                }

                                if ($null -ne $nfsLIF)
                                {
                                    try
                                    {
                                        $datastoreVolume = @(Get-NCVol -Controller $ncController -Vserver $nfsLIF.Vserver -ErrorAction Stop | Where-Object { $_.JunctionPath -eq $datastoreDef.nfsPath })

                                        if ($datastoreVolume.Length -eq 1)
                                        {
                                            # 1 volume found

                                            $datastoreVolume = $datastoreVolume[0]

                                            if ($doReportSuccess)
                                            {
                                                ReportSuccess ("`t`tDatastore Volume: {0}:{1}:{2}" -f @($datastoreVolume.NcController.Name, $datastoreVolume.Vserver, $datastoreVolume.Name))
                                            }
                                            else # NOT ($doReportSuccess)
                                            {
                                                # Nothing.
                                            }
                                            $junctionPaths = $datastoreVolume.JunctionPath -split '/'
                                            if ($doReportSuccess)
                                            {
                                                ReportSuccess ("`t`tJunction path splits: {0}" -f @(($junctionPaths -join '|')))
                                            }
                                            else # NOT ($doReportSuccess)
                                            {
                                                # Nothing.
                                            }
                                            $c = 0
                                            $accessAllowed = $true
                                            while($success -and $accessAllowed -and ($c -lt $junctionPaths.Length))
                                            {
                                                if ([String]::IsNullOrEmpty($junctionPaths[$c]))
                                                {
                                                    # Need to check the SVM root volume

                                                    try
                                                    {
                                                        $ncVolume = Get-NCVol -Controller $datastoreVolume.NcController -Vserver $datastoreVolume.Vserver -ErrorAction Stop | Where-Object { ($_.VolumeStateAttributes.IsVserverRoot) -and (-not $_.VolumeMirrorAttributes.IsLoadSharingMirror) }
                                                    }
                                                    catch
                                                    {
                                                        ReportError ("`t`tUnable to retrieve SVM root volume for {0}:{1}." -f @($ncController.Name, $datastoreVolume.VServer))
                                                        $success = $false
                                                    }
                                                }
                                                else # NOT ($junctionPaths[$c] -eq '')
                                                {
                                                    # Not the SVM root volume...
                                                    try
                                                    {
                                                        $ncVolume = Get-NCVol -Controller $datastoreVolume.NcController -Vserver $datastoreVolume.VServer -ErrorAction Stop | Where-Object { $_.JunctionPath -eq ($junctionPaths[0..$c] -join '/') }
                                                    }
                                                    catch
                                                    {
                                                        ReportError ("`t`tUnable to retrieve volume with junction path: {0} from {1}:{2}." -f @(($junctionPaths[0..$c] -join '/'), $ncController.Name, $datastoreVolume.VServer))
                                                        $success = $false
                                                    }
                                                }

                                                if ($null -ne $ncVolume)
                                                {
                                                    $modifyAccess = $datastoreVolume.VolumeIdAttributes.Uuid -eq $ncVolume.VolumeIdAttributes.Uuid
                                                    if ($doReportSuccess)
                                                    {
                                                        ReportSuccess ("`t`tMount with modify access: {0}" -f @($modifyAccess))
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # Nothing.
                                                    }
                                                    $accessAllowed = AllowESXiAccessToVolume -ncVolume $ncVolume -esxiHostAddress $hostStorageAddress -modifyAccess:$modifyAccess
                                                }
                                                else # NOT ($null -ne $ncVolume)
                                                {
                                                    $success = $false
                                                }

                                                $c++
                                            }

                                            if ($success -and $accessAllowed)
                                            {
                                                # Mount the datastore to the ESXi Host.
                                                try
                                                {
                                                    [void] (New-Datastore -Server $viServer -Name $datastoreDef.Name -NFS -NfsHost $datastoreDef.nfsHost -Path $datastoreDef.nfsPath -VMHost $vmHost -ErrorAction Stop)
                                                    if ($doReportSuccess)
                                                    {
                                                        ReportSuccess ("`t`tMounted {0} to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("`t`tFailed to mounted {0} to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                                                    $success = $false
                                                }
                                            }
                                            else # NOT ($accessAllowed)
                                            {
                                                ReportError ("`t`tFailed to grant access to NetApp volume {0}." -f @($datastoreDef.Name))
                                                $success = $false
                                            }
                                        }
                                        elseif($datastoreVolume.Length -eq 0)
                                        {
                                            # No volume found

                                            ReportError ("`t`tFailed to retrieve NetApp volume with junction path: {0}." -f @($datastoreDef.nfsPath))
                                            $success = $false
                                        }
                                        else
                                        {
                                            # Multiple volumes found.  WTH!

                                            ReportError ("`t`tFailed multiple NetApp volumes with junction path: {0}." -f @($datastoreDef.nfsPath))

                                            $c = 0
                                            while($c -lt $datastoreVolume.Length)
                                            {
                                                ReportError ("`t`t{0}: {1}:{2}" -f @(($c+1), $datastoreVolume[$c].VServer, $datastoreVolume[$c].Name))
                                                $c++
                                            }
                                            $success = $false
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("`t`tFailed to retrieve NetApp volumes from: {0}." -f @($ncController.Name))
                                        $success = $false
                                    }
                                }
                                else # NOT ($null -ne $nfsLIF)
                                {
                                    $success = $false
                                }
                            }
                            catch
                            {
                                ReportError ("`t`tFailed to retrieve NFS network interfaces from: {0}." -f @($ncController.Name))
                                $success = $false
                            }
                        }
                        else # NOT ($null -ne $ncController)
                        {
                            ReportError ("`t`tNo connection to {0} available." -f @($datastoreDef.filer))
                            $success = $false
                        }
                    }
                    else # NOT ($cdot.Keys -contains $datastoreDef[0].filer)
                    {
                        ReportError ("`t`tNo connection to {0} available." -f @($datastoreDef.filer))
                        $success = $false
                    }
                }
            }
            elseif($vmHost.Length -eq 0)
            {
                ReportError ("`t`tUnable to find an ESXi host named: {0}." -f @($hostDef.vmHostName))
                $success = $false
            }
            else
            {
                ReportError ("`t`tFound {0} ESXi hosts named: {1}." -f @($vmHost.Length, $hostDef.vmHostName))
                $success = $false
            }
        }
        catch
        {
            ReportError ("`t`tFailed to retrieve an ESXi host named: {0}." -f @($hostDef.vmHostName))
            $success = $false
        }
    } `
    else # NOT ($null -ne $storageVMKDef)
    {
        ReportError ("`t`tNo storage VMK was found for datastore: {0} [{1}:{2}] on {3}." -f @($datastoreDef.name, $datastoreDef.nfsHost, $datastoreDef.nfsPath, $hostDef.vmHostName))
        $success = $false
    }

    return $success
}

function MountDatastoresToHost
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object[]] $datastores,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [Object] $hostDef,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]] $cDot,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $success = $true
    if ($doReportSuccess)
    {
        ReportSuccess ("Mounting datastores to {0}..." -f @($hostDef.vmHostName))
    }
    else # NOT ($doReportSuccess)
    {
        # Nothing.
    }

    $a = 0
    while(($success) -and ($a -lt $hostDef.datastores.Length))
    {
        $datastoreDef = @($datastores | Where-Object { $_.Name -eq $hostDef.datastores[$a] })

        if ($datastoreDef.Length -eq 1)
        {
            # Only 1 definition found

            $datastoreDef = $datastoreDef[0]
            $success = MountDatastoreToHost -viServer $viServer -datastoreDef $datastoreDef -host $hostDef -cDot $cdot -doReportSuccess:$doReportSuccess
        }
        elseif ($datastoreDef.Length -eq 0)
        {
            # No definitions found

            ReportError ("`tNo datastore definition found for {0}." -f @($hostDef.datastores[$a]))
            $success = $false
        }
        else  # NOT ($datastoreDef.Length -eq 0)
        {
            # Multiple definitions found

            ReportError ("`tMultiple datastore definitions found for {0}." -f @($hostDef.datastores[$a]))
            $success = $false
        }

        $a++
    }

    return $success
}

function MountDatastoresToHosts
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object[]] $datastores,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [Object[]] $hostDefs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]] $cDot,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $success = $true
    $a = 0
    while($success -and ($a -lt $hostDefs.Length))
    {
        $success = MountDatastoresToHost -viServer $viServer -datastores $datastores -host $hostDefs[$a] -cDot $cDot -doReportSuccess:$doReportSuccess

        $a++
    }

    return $success
}

function MountDatastoresToESXiHosts_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object[]] $datastores,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [Object[]] $hosts,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]] $cDot,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $a = 0
    while($a -lt $hosts.Length)
    {
        if ($doReportSuccess)
        {
            ReportSuccess ("Processing {0}:{1}..." -f @($a, $hosts[$a].vmHostName))
        }
        else # NOT ($doReportSuccess)
        {
            # Nothing.
        }

        $b = 0
        while($b -lt $hosts[$a].datastores.Length)
        {
            $datastoreDef = @($datastores | Where-Object { $_.Name -eq $hosts[$a].datastores[$b] })

            if ($datastoreDef.Length -eq 1)
            {
                # Only 1 definition found

                $datastoreDef = $datastoreDef[0]
                if ($doReportSuccess)
                {
                    ReportSuccess ("`tDatastore {0}:{1} {2}:{3} ({4})" -f @($b, $datastoreDef.Name, $datastoreDef.nfsHost, $datastoreDef.nfsPath, $datastoreDef.filer))
                }
                else # NOT ($doReportSuccess)
                {
                    # Nothing.
                }

                # Identify which VMK will be used for connectivity to the datastore
                $storageVMKDef = FindDatastoreVMK $hosts[$a] $datastoreDef
                if ($null -ne $storageVMKDef)
                {
                    $hostStorageAddress = $storageVMKDef.ipAddress

                    try
                    {
                        $vmHost = @(Get-VMHost -Server $viServer -Name $hosts[$a].vmHostName -ErrorAction Stop)

                        if ($vmHost.Length -eq 1)
                        {
                            # TRUE

                            $vmHost = $vmHost[0]
                            if ($doReportSuccess)
                            {
                                ReportSuccess ("`tVMHost: {0}" -f @($vmHost.Name))
                            }
                            else # NOT ($doReportSuccess)
                            {
                                # Nothing.
                            }

                            try
                            {
                                [void] (Get-Datastore -Server $viServer -RelatedObject $vmHost -Name $datastoreDef.Name -ErrorAction Stop)

                                ReportNotice ("Datastore {0} is already mounted to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                            }
                            catch
                            {
                                # Nothing, the datastore is not mounted to the ESXi Host...

                                if ($cdot.Keys -contains $datastoreDef.filer)
                                {
                                    # TRUE

                                    $ncController = $cdot[$datastoreDef.filer]

                                    if ($null -ne $ncController)
                                    {
                                        # TRUE
                                        if ($doReportSuccess)
                                        {
                                            ReportSuccess ("`tNcController: {0}" -f @($ncController.Name))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # Nothing.
                                        }
                                        $nfsLIF = $null
                                        try
                                        {
                                            $nfsLIF = @(Get-NCNetInterface -Controller $ncController -DataProtocols "nfs" | Where-Object { $_.Address -eq $datastoreDef.nfsHost } )

                                            if ($nfsLIF.Length -eq 1)
                                            {
                                                # TRUE

                                                $nfsLIF = $nfsLIF[0]
                                            }
                                            elseif($nfsLIF.Length -eq 0)
                                            {
                                                # No NFS LIFs matching $datastoreDef.nfsHost

                                                ReportError ("Failed to retrieve NFS network interface on {0} with IP Address: {1}." -f @($ncController.Name, $datastoreDef.nfsHost))
                                                $nfsLIF = $null
                                            }
                                            else
                                            {
                                                # Mulitple NFS LIFs matching $datastoreDef.nfsHost -- Is there a single VServer for them all??

                                                ReportWarning ("`tMultiple NFS LIFs ({0}) found with address: {1}" -f @($nfsLIF.Length, $datastoreDef.nfsHost))
                                                foreach($lif in $nfsLIF)
                                                {
                                                    ReportWarning ("`t`tVServer: {0}, Name: {1}" -f @($lif.Vserver, $lif.Name))
                                                }
                                                $vServerNames = @($nfsLIF | Select-Object -Unique -ExpandProperty VServer)

                                                if ($vServerNames.Length -eq 1)
                                                {
                                                    # TRUE

                                                    # Saved, all the NFS LIFs matching $datastoreDef.nfsHost are on the same vServer, so arbitarily use [0]...
                                                    $nfsLIF = $nfsLIF[0]

                                                    ReportWarning ("`tAll NFS LIFS are hosted on the same VServer.  Using {0} going forward." -f @($nfsLIF.VServer))
                                                }
                                                else # NOT ($vServerNames.Length -eq 1)
                                                {
                                                    # FALSE

                                                    ReportError ("`tUnable to determine VServer for {0}:{1}." -f @($datastoreDef.nfsHost, $datastoreDef.nfsPath))
                                                    $nfsLIF = $null
                                                }
                                            }

                                            if ($null -ne $nfsLIF)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $datastoreVolume = @(Get-NCVol -Controller $ncController -Vserver $nfsLIF.Vserver -ErrorAction Stop | Where-Object { $_.JunctionPath -eq $datastoreDef.nfsPath })

                                                    if ($datastoreVolume.Length -eq 1)
                                                    {
                                                        # 1 volume found

                                                        $datastoreVolume = $datastoreVolume[0]

                                                        if ($doReportSuccess)
                                                        {
                                                            ReportSuccess ("`tDatastore Volume: {0}:{1}:{2}" -f @($datastoreVolume.NcController.Name, $datastoreVolume.Vserver, $datastoreVolume.Name))
                                                        }
                                                        else # NOT ($doReportSuccess)
                                                        {
                                                            # Nothing.
                                                        }
                                                        $junctionPaths = $datastoreVolume.JunctionPath -split '/'
                                                        if ($doReportSuccess)
                                                        {
                                                            ReportSuccess ("`tJunction path splits: {0}" -f @(($junctionPaths -join '|')))
                                                        }
                                                        else # NOT ($doReportSuccess)
                                                        {
                                                            # Nothing.
                                                        }
                                                        $c = 0
                                                        $accessAllowed = $true
                                                        while($accessAllowed -and ($c -lt $junctionPaths.Length))
                                                        {
                                                            if ([String]::IsNullOrEmpty($junctionPaths[$c]))
                                                            {
                                                                # TRUE - Need to check the SVM root volume

                                                                try
                                                                {
                                                                    $ncVolume = Get-NCVol -Controller $datastoreVolume.NcController -Vserver $datastoreVolume.Vserver -ErrorAction Stop | Where-Object { ($_.VolumeStateAttributes.IsVserverRoot) -and (-not $_.VolumeMirrorAttributes.IsLoadSharingMirror) }
                                                                }
                                                                catch
                                                                {
                                                                    ReportError ("Unable to retrieve SVM root volume for {0}:{1}." -f @($ncController.Name, $datastoreVolume.VServer))
                                                                }
                                                            }
                                                            else # NOT ($junctionPaths[$c] -eq '')
                                                            {
                                                                # FALSE

                                                                try
                                                                {
                                                                    $ncVolume = Get-NCVol -Controller $datastoreVolume.NcController -Vserver $datastoreVolume.VServer -ErrorAction Stop | Where-Object { $_.JunctionPath -eq ($junctionPaths[0..$c] -join '/') }
                                                                }
                                                                catch
                                                                {
                                                                    ReportError ("Unable to retrieve volume with junction path: {0} from {1}:{2}." -f @(($junctionPaths[0..$c] -join '/'), $ncController.Name, $datastoreVolume.VServer))
                                                                }
                                                            }

                                                            if ($null -ne $ncVolume)
                                                            {
                                                                # TRUE

                                                                $modifyAccess = $datastoreVolume.VolumeIdAttributes.Uuid -eq $ncVolume.VolumeIdAttributes.Uuid
                                                                if ($doReportSuccess)
                                                                {
                                                                    ReportSuccess ("`tMount with modify access: {0}" -f @($modifyAccess))
                                                                }
                                                                else # NOT ($doReportSuccess)
                                                                {
                                                                    # Nothing.
                                                                }
                                                                $accessAllowed = AllowESXiAccessToVolume -ncVolume $ncVolume -esxiHostAddress $hostStorageAddress -modifyAccess:$modifyAccess
                                                            }
                                                            else # NOT ($null -ne $ncVolume)
                                                            {
                                                                # FALSE

                                                                # Nothing.
                                                            }

                                                            $c++
                                                        }

                                                        if ($accessAllowed)
                                                        {
                                                            # TRUE

                                                            # Mount the datastore to the ESXi Host.
                                                            try
                                                            {
                                                                [void] (New-Datastore -Server $viServer -Name $datastoreDef.Name -NFS -NfsHost $datastoreDef.nfsHost -Path $datastoreDef.nfsPath -VMHost $vmHost -ErrorAction Stop)
                                                                if ($doReportSuccess)
                                                                {
                                                                    ReportSuccess ("Mounted {0} to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                                                                }
                                                                else # NOT ($doReportSuccess)
                                                                {
                                                                    # Nothing.
                                                                }
                                                            }
                                                            catch
                                                            {
                                                                ReportError ("Fail to mounted {0} to {1}." -f @($datastoreDef.Name, $vmHost.Name))
                                                            }
                                                        }
                                                        else # NOT ($accessAllowed)
                                                        {
                                                            # FALSE

                                                        }
                                                    }
                                                    elseif($datastoreVolume.Length -eq 0)
                                                    {
                                                        # No volume found

                                                        ReportError ("Failed to retrieve NetApp volume with junction path: {0}." -f @($datastoreDef.nfsPath))
                                                    }
                                                    else
                                                    {
                                                        # Multiple volumes found.  WTH!

                                                        ReportError ("Failed multiple NetApp volumes with junction path: {0}." -f @($datastoreDef.nfsPath))

                                                        $c = 0
                                                        while($c -lt $datastoreVolume.Length)
                                                        {
                                                            ReportError ("{0}: {1}:{2}" -f @(($c+1), $datastoreVolume[$c].VServer, $datastoreVolume[$c].Name))
                                                            $c++
                                                        }
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to retrieve NetApp volumes from: {0}." -f @($ncController.Name))
                                                }
                                            }
                                            else # NOT ($null -ne $nfsLIF)
                                            {
                                                # FALSE

                                                # Nothing -- already reported an error
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to retrieve NFS network interfaces from: {0}." -f @($ncController.Name))
                                        }
                                    }
                                    else # NOT ($null -ne $ncController)
                                    {
                                        # FALSE

                                        ReportError ("No connection to {0} available." -f @($datastoreDef.filer))
                                    }
                                }
                                else # NOT ($cdot.Keys -contains $datastoreDef[0].filer)
                                {
                                    # FALSE

                                    ReportError ("No connection to {0} available." -f @($datastoreDef.filer))
                                }
                            }
                        }
                        elseif($vmHost.Length -eq 0)
                        {
                            # FALSE

                            ReportError ("Unable to find an ESXi host named: {0}." -f @($hosts[$a].vmHostName))
                        }
                        else
                        {
                            ReportError ("Found {0} ESXi hosts named: {1}." -f @($vmHost.Length, $hosts[$a].vmHostName))
                        }
                    }
                    catch
                    {
                        ReportError ("Failed to retrieve an ESXi host named: {0}." -f @($hosts[$a].vmHostName))
                    }
                } `
                else # NOT ($null -ne $storageVMKDef)
                {
                    ReportError ("No storage VMK was found for datastore: {0} [{1}:{2}] on {3}." -f @($datastoreDef.name, $datastoreDef.nfsHost, $datastoreDef.nfsPath, $hosts[$a].vmHostName))
                }
            }
            elseif ($datastoreDef.Length -eq 0)
            {
                # No definitions found

                ReportError ("No datastore definition found for {0}." -f @($hosts[$a].datastores[$b]))
            }
            else  # NOT ($datastoreDef.Length -eq 0)
            {
                # Multiple definitions found

                ReportError ("Multiple datastore definitions found for {0}." -f @($hosts[$a].datastores[$b]))
            }

            $b++
        }

        $a++
    }
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

function RemoveVMHostStdSwitch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualSwitchImpl] $stdSwitch
    )

    try
    {
        $stdSwitchVMs = @(Get-VM -VirtualSwitch $stdSwitch -ErrorAction Stop)
        if ($stdSwitchVMs.Length -eq 0)
        {
            # No VMs on the standard switch...

            try
            {
                $stdSwitchVMKs = @(Get-VMHostNetworkAdapter -VMHost $stdSwitch.VMHost -VirtualSwitch $stdSwitch -VMKernel -ErrorAction Stop)
                if ($stdSwitchVMKs.Length -eq 0)
                {
                    # No VMKs on the standard switch...

                    try
                    {
                        $stdSwitchPNICs = @(Get-VMHostNetworkAdapter -VMHost $stdSwitch.VMHost -VirtualSwitch $stdSwitch -Physical)
                        if ($stdSwitchPNICs.Length -eq 0)
                        {
                            # No physical NICs on the standard switch...

                            # Should be safe to remove the standard switch...
                            try
                            {
                                Remove-VirtualSwitch -VirtualSwitch $stdSwitch -Confirm:$false -ErrorAction Stop
                                ReportSuccess ("Removed {0}/{1}." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
                            }
                            catch
                            {
                                ReportError ("Failed to remove {0}/{1}." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
                            }
                        } `
                        else # NOT ($stdSwitchPNICs.Length -eq 0)
                        {
                            ReportWarning ("{0}/{1} still has physical NICs attached." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
                        }
                    }
                    catch
                    {
                        ReportError ("Unable to determine if {0}/{1} has any physical NICs attached." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
                    }
                } `
                else # NOT ($stdSwitchVMKs.Length -eq 0)
                {
                    ReportWarning ("{0}/{1} still has {2} VMK(s) attached." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name, $stdSwitchVMKs.Lnegth))
                }
            }
            catch
            {
                ReportError ("Unable to determine if {0}/{1} has any physical NICs attached." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
            }
        } `
        else # NOT ($stdSwitchVMs.Length -eq 0)
        {
            ReportWarning ("{0}/{1} still has VMs attached." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
        }
    }
    catch
    {
        ReportError ("Unable to determine if {0}/{1} has any VMs attached to it." -f @($stdSwitch.VMHost.Name, $stdSwitch.Name))
    }
}

function RemoveVMHostStdSwitches
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $vmHostName
    )

    if ($viServer.IsConnected)
    {
        try
        {
            $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop

            try
            {
                $stdSwitches = @(Get-VirtualSwitch -VMHost $vmHost -Standard -ErrorAction Stop)
                if ($stdSwitches.Length -gt 0)
                {
                    $a = 0
                    while($a -lt $stdSwitches.Length)
                    {
                        RemoveVMHostStdSwitch -stdSwitch $stdSwitches[$a]

                        $a++
                    }
                } `
                else # NOT ($stdSwitches.Length -gt 0)
                {
                    ReportNotice ("No standard switches located on {0}." -f @($vmHost.Name))
                }
            }
            catch
            {
                ReportNotice ("No standard switched located on {0}." -f @($vmHost.Name))
            }
        }
        catch
        {
            ReportWarning ("Could not locate VM host named: {0} on {1} in {2}." -f @($vmHostName, $viServer, $MyInvocation.MyCommand))
        }
    } `
    else # NOT ($viServer.IsConnected)
    {
        ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand))
    }
}

<#
    Get $datacenterName from $viServer
        Optionally create it if it doesn't exist
#>

function Get-vSphereDatacenter
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $Name,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $createMissing
    )

    $dataCenter = $null
    if ($viServer.IsConnected)
    {
        try
        {
            $datacenter = Get-Datacenter -Server $viServer -Name $Name -ErrorAction Stop
        }
        catch
        {
            if ($createMissing)
            {
                try
                {
                    $rootFolder = Get-Folder -Server $viServer -NoRecursion -ErrorAction Stop
                    try
                    {
                        $datacenter = New-Datacenter -Location $rootFolder -Name $Name -Server $viServer -ErrorAction Stop
                    }
                    catch
                    {
                        ReportError ("Failed to create datacenter {0} in folder {1} in {2}." -f @($Name, $rootFolder.Name, $MyInvocation.MyCommand))
                    }
                }
                catch
                {
                    ReportError ("Failed to acquire root folder in {0}." -f @($MyInvocation.MyCommand))
                }
            } `
            else # NOT ($createMissing)
            {
                ReportError ("Unable to locate datacenter: {0} in {1}." -f @($Name, $MyInvocation.MyCommand))
            }
        }
    } `
    else # NOT ($viServer.IsConnected)
    {
        ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand))
    }

    return $datacenter
}

function Get-vSphereCluster
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $Name,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2, ParameterSetName = "DoCreation")]
        [Switch] $createMissing,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3, ParameterSetName = "DoCreation")]
        [Object] $Location
    )

    $cluster = $null
    if ($viServer.IsConnected)
    {
        try
        {
            $cluster = Get-Cluster -Server $viServer -Name $Name -ErrorAction Stop
        }
        catch
        {
            if ($createMissing)
            {
                if (-not [String]::IsNullOrEmpty($Location))
                {
                    try
                    {
                        $locationEntity = Get-Inventory -Server $viServer -Name $Location -ErrorAction Stop
                        try
                        {
                            $cluster = New-Cluster -Server $viServer -Name $Name -Location $locationEntity -DrsEnabled -HAEnabled -HAAdmissionControlEnabled -DrsAutomationLevel FullyAutomated -ErrorAction Stop
                        }
                        catch
                        {
                            ReportError ("Failed to create cluster {0} in {1} in {2}." -f @($Name, $Location, $MyInvocation.MyCommand))
                        }
                    }
                    catch
                    {
                        ReportError ("Failed to acquire object for inventory entity: {0} in {1}." -f @($Location, $MyInvocation.MyCommand))
                    }
                } `
                else # NOT (-not [String]::IsNullOrEmpty($Location))
                {
                    ReportError ("Missing location for new cluster {0} in {1)." -f @($Name, $MyInvocation.MyCommand))
                }
            } `
            else # NOT ($createIfMissing)
            {
                ReportError ("Failed to locate cluster: {0} in {1}." -f @($Name, $MyInvocation.MyCommand))
            }
        }
    } `
    else # NOT ($viServer.IsConnected)
    {
        ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand))
    }

    return $cluster
}

function Set-vSpherevCLSOnCluster
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $Name,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2, ParameterSetName = "Status")]
        [switch] $Enable,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2, ParameterSetName = "Status")]
        [switch] $Disable
    )

    if ($viServer.IsConnected)
    {
        $advSettingValue = "false"
        if ($Enable)
        {
            $advSettingValue = "true"
        } `
        else # NOT ($Enable)
        {
            # Nothing.
        }

        $cluster = Get-vSphereCluster -viServer $viServer -Name $Name
        if ($null -ne $cluster)
        {
            if ($cluster.Id -match "^ClusterComputeResource\-domain\-(.*)$")
            {
                $advSettingName = "config.vcls.clusters.domain-{0}.enabled" -f @($Matches[1])
                $advSetting = Get-AdvancedSetting -Entity $viServer -Name $advSettingName
                if ($null -eq $advSetting)
                {
                    try
                    {
                        $advSetting = New-AdvancedSetting -Server $viServer -Name $advSettingName -Entity $viServer -Value $advSettingValue -Confirm:$false -ErrorAction Stop
                    }
                    catch
                    {
                        ReportError ("Failed to set new advanced setting {0} to {1} in {2}." -f @((Quoted $advSettingName), (Quoted $advSettingValue), $MyInvocation.MyCommand))
                    }
                } `
                else # NOT ($null -ne $advSetting)
                {
                    $advSetting | Set-AdvancedSetting -Value $advSettingValue -Confirm:$false
                }
            } `
            else # NOT ($cluster.Id -match "")
            {
                ReportError ("Unable to determine cluster unique ID from: {0} in {1}." -f @((Quoted $cluster.Id), $MyInvocation.MyCommand))
            }
        } `
        else # NOT ($null -ne $cluster)
        {
            # Nothing - Already reported an error
        }
    } `
    else # NOT ($viServer.IsConnected)
    {
        ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand))
    }
}

function Get-vSphereHost
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $Name,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2, ParameterSetName = "AddMissingHost")]
        [Switch] $addMissing,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3, ParameterSetName = "AddMissingHost")]
        [string] $clusterName
    )

    $vmHost = $null
    if ($viServer.IsConnected)
    {
        try
        {
            $vmHost = Get-VMHost -Server $viServer -Name $Name -ErrorAction Stop
        }
        catch
        {
            if ($addMissing)
            {
                if (-not [String]::IsNullOrEmpty($clusterName))
                {
                    $cluster = Get-vSphereCluster -viServer $viServer -Name $clusterName
                    if ($null -ne $cluster)
                    {
                        # If we do not have credentials to add the host to the cluster, prompt for them.
                        if ($null -eq $Global:vmHostAddCredentials)
                        {
                            $Global:vmHostAddCredentials = Get-Credential -Message ("Provide credentials to add {0} to {1}." -f @($Name, $clusterName))
                        } `
                        else # NOT ($null -eq $Global:vmHostAddCredentials)
                        {
                            # Nothing.
                        }

                        # Since we may have just prompted for credentials, check again to make sure we have them.
                        if ($null -ne $Global:vmHostAddCredentials)
                        {
                            try
                            {
                                $Error.Clear()
                                $vmHost = Add-VMHost -Server $viServer -Name $Name -Location $cluster -Credential $Global:vmHostAddCredentials -Confirm:$false -Force -ErrorAction Stop
                            }
                            catch
                            {
                                ReportError ("Failed to add {0} to {1}.`r`n{2}." -f @($Name, $cluster.Name, (Get-Error).Exception.Message))
                            }
                        } `
                        else # NOT ($null -eq $Global:vmHostAddCredentials)
                        {
                            ReportError ("Not adding {0} to {1}.  Missing credentials." -f @($Name, $cluster.Name))
                        }
                    } `
                    else # NOT ($null -ne $cluster)
                    {
                        # Nothing -- already displayed a message
                    }
                } `
                else # NOT (-not [String]::IsNullOrEmpty($clusterName))
                {
                    ReportError ("Missing cluster name in {0} with -addMissing specified." -f @($MyInvocation.MyCommand))
                }
            } `
            else # NOT ($addMissing)
            {
                ReportError ("Failed to locate host: {0} in {1}." -f @($Name, $MyInvocation.MyCommand))
            }
        }
    } `
    else # NOT ($viServer.IsConnected)
    {
        ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand))
    }

    return $vmHost
}



# TODO: Consider connecting to vCenter based on $virtualizationDefinition...

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

        # Enable cluster services.
        Set-vSpherevCLSOnCluster -viServer $viServer -Name $virtualizationDefinition.vSphereClusterName -Enable
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


& {
    $viServer = $vCenter
    $doReportSuccess = $true
    $ucs = $cdcUCS
    $Global:ucsData = $null
    $DoIt = $true

    # TODO: Fix ValidateSwitchDefinition to work with v2
    # TODO: Fix functions that use $hosts -- check $hosts before use

#    if (ValidateSwitchDefinition -viServer $viServer -ucsManager $ucs -dsf $dsConfig -doReportSuccess:$doReportSuccess)
#    {
        # TRUE

        $newVDS = CreateVDS -viServer $viServer -datacenterName $virtualizationDefinition.datacenterName -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess
        if ($null -ne $newVDS)
        {
            if (CreatePortGroups -viServer $viServer -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
            {
                if (AddHostsToVDS -viServer $viServer -datacenterName $virtualizationDefinition.datacenterName -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                {
                    if (MigrateHostsVMNICsToVDS -viServer $viServer -ucsManager $ucs -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -ExcludevmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                    {
                        if (MigrateHostsVMKsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                        {
                            if (MigrateHostsVMNICsToVDS -viServer $viServer -ucsManager $ucs -dsConfig $virtualizationDefinition.switch -hostDefs $virtualizationDefinition.hosts -OnlyvmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                            {
                                $a = 0
                                while($a -lt $virtualizationDefinition.hosts.Length)
                                {
                                    RemoveVMHostStdSwitches -viServer $viServer -vmHostName $virtualizationDefinition.hosts[$a].vmHostName
                                    $a++
                                }

                                if (MountDatastoresToHosts -viServer $viServer -datastores $virtualizationDefinition.datastores -hostDefs $virtualizationDefinition.hosts -cDot $cDot -doReportSuccess:$doReportSuccess)
                                {

                                } `
                                else # NOT (MountDatastoresToESXiHosts -viServer $viServer -datastores $virtualizationDefinition.datastores -hosts $virtualizationDefinition.hosts -cDot $cDot -doReportSuccess:$doReportSuccess)
                                {
                                    ReportError "Failed to mount datastores to hosts."
                                }
                            }
                            else # NOT (MigrateVMNICsToVDS -viServer $viServer -ucsManager $ucs -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -OnlyvmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                            {
                                ReportError ("Failed to migrate vmnic0 to {0}." -f @($virtualizationDefinition.switch.name))
                            }
                        }
                        else # NOT (MigrateVMKsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                        {
                            ReportError ("Failed to migrate any/all VMKs to {0}." -f @($virtualizationDefinition.switch.name))
                        }
                    }
                    else # NOT (MigrateVMNICsToVDS -viServer $viServer -ucsManager $ucs -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -ExcludevmNIC0 -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                    {
                        ReportError ("Failed to migrate any/all VMNICs to {0}." -f @($virtualizationDefinition.switch.name))
                    }
                }
                else # NOT (AddVMHostsToVDS -viServer $viServer -dsConfig $virtualizationDefinition.switch -hosts $virtualizationDefinition.hosts -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
                {
                    ReportError ("Failed to add VM hosts to {0}." -f @(Quoted $virtualizationDefinition.switch.name))
                }
            }
            else # NOT (CreatePortGroups -viServer $viServer -dsConfig $virtualizationDefinition.switch -DoIt:$DoIt -doReportSuccess:$doReportSuccess)
            {
                ReportError ("Failed to add port groups to {0}." -f @(Quoted $virtualizationDefinition.switch.name))
            }
        }
        else # NOT ($null -ne $newVDS)
        {
            ReportError ("Failed to create new distributed switch {0}." -f @(Quoted $virtualizationDefinition.switch.name))
        }
#    }
#    else # NOT (ValidateSwitchDefinition -viServer $viServer -ucsManager $ddcUCS -dsf $dsConfig -doReportSuccess)
#    {
#        ReportError "Unable to valid the distributed switch configuration."
#    }
}
