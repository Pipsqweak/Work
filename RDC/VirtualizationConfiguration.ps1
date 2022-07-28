function ConnectToEnvironments
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $vCenterName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $ucsManagerName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $cdotClusterName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $doReportSuccess
    )

    $vCtr = $null
    $ucsManager = $null
    $ncController = $null

    $vCenterCredentials = Get-Credential -Message ("Provide logon credentials to {0}" -f @($vCenterName))
    if ($null -ne $vCenterCredentials)
    {
        # TRUE

        try
        {
            $vCtr = Connect-VIServer -Server $vCenterName -NotDefault -Credential $vCenterCredentials -ErrorAction Stop
            if ($doReportSuccess)
            {
                # TRUE

                ReportSuccess ("Connected to {0}." -f @((Quoted $vCtr.Name)))
            }
            else # NOT ($doReportSuccess)
            {
                # FALSE

                # Nothing.
            }

            $ucsCredentials = Get-Credential -Message ("Provide logon credentials to {0} ex: ucs-local\localUser" -f @($ucsManagerName))
            if ($null -ne $ucsCredentials)
            {
                # TRUE

                try
                {
                    $ucsManager = Connect-Ucs -Name $ucsManagerName -Credential $ucsCredentials -NotDefault -ErrorAction Stop

                    if ($doReportSuccess)
                    {
                        # TRUE

                        ReportSuccess ("Connected to {0}." -f @((Quoted $ucsManager.Name)))
                    }
                    else # NOT ($doReportSuccess)
                    {
                        # FALSE

                        # Nothing.
                    }

                    $cdotCredentials = Get-Credential -Message ("Provide logon credentials to {0}" -f @($cdotClusterName))
                    if ($null -ne $cdotCredentials)
                    {
                        # TRUE

                        try
                        {
                            $ncController = Connect-NcController -Name $cdotClusterName -Credential $cdotCredentials -Transient -ErrorAction Stop

                            if ($doReportSuccess)
                            {
                                # TRUE

                                ReportSuccess ("Connected to {0}." -f @((Quoted $ncController.Name)))
                            }
                            else # NOT ($doReportSuccess)
                            {
                                # FALSE

                                # Nothing.
                            }
                        }
                        catch
                        {
                            ReportError ("Failed to logon to {0} with provided credentials." -f @($cdotClusterName))
                        }
                    }
                    else # NOT ($null -ne $vCenterCredentials)
                    {
                        # FALSE

                        ReportWarning ("User cancelled logon to {0}." -f @($ucsManagerName))
                    }
                }
                catch
                {
                    ReportError ("Failed to logon to {0} with provided credentials." -f @($ucsManagerName))
                }
            }
            else # NOT ($null -ne $vCenterCredentials)
            {
                # FALSE

                ReportWarning ("User cancelled logon to {0}." -f @($ucsManagerName))
            }
        }
        catch
        {
            ReportError ("Failed to logon to {0} with provided credentials." -f @($vCenterName))
        }
    }
    else # NOT ($null -ne $vCenterCredentials)
    {
        # FALSE

        ReportWarning ("User cancelled logon to {0}." -f @($vCenterName))
    }

    return @($vCtr, $ucsManager, $ncController)
}

function AddAdministrativePropertyToVirtualizationDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Object] $parentObject,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $propertyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [System.Management.Automation.PSMemberTypes] $typeName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [AllowNull()]
        [Object] $initialValue,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $allowExisting,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $doReportSuccess
    )

    $successful = $false
    if ($null -ne $parentObject)
    {
        # TRUE

        try
        {
            if (@(Get-Member -InputObject $parentObject -Name $propertyName -ErrorAction Stop).Length -eq 0)
            {
                # TRUE

                try
                {
                    Add-Member -InputObject $parentObject -MemberType $typeName -Name $propertyName -Value $initialValue -ErrorAction Stop
                    $successful = $true
                    if ($doReportSuccess)
                    {
                        # TRUE

                        ReportSuccess ("Added {0} = {1} to parent object." -f @($propertyName, $initialValue))
                    }
                    else # NOT ($doReportSuccess)
                    {
                        # FALSE
                    }
                }
                catch
                {
                    ReportError ("Failed to add {0} to parent object." -f @((Quoted $propertyName)))
                }
            }
            else # NOT (@(Get-Member -InputObject $parentObject -Name $propertyName -ErrorAction Stop).Length -eq 0)
            {
                # FALSE

                if (-not $allowExisting)
                {
                    # TRUE

                    ReportError ("Parent object already contains a property named {0} [{1}].  Please remove." -f @((Quoted $propertyName), $parentObject.$($propertyName)))
                }
                else # NOT (-not $allowExisting)
                {
                    # FALSE

                    if ($doReportSuccess)
                    {
                        # TRUE

                        ReportNotice ("Parent object already contains a property named {0}." -f @((Quoted $propertyName)))
                    }
                    else # NOT ($doReportSuccess)
                    {
                        # FALSE

                        # Nothing.
                    }
                }
            }
        }
        catch
        {
            ReportError ("Unable to determine if parent object contains property {0}." -f @((Quoted $propertyName)))
        }
    }
    else # NOT ($null -ne $parentObject)
    {
        # FALSE

        ReportError ("Missing parent object in {0}" -f @($MyInvocation.MyCommand.Name))
    }

    return $successful
}

function ValidateExistingDistributedSwitch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $dsf,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $switchDefIsValid = $false

    # Make sure this function is only called from function:ValidateVirtualSwitchDefinition
    $caller = (Get-PSCallStack)[1].Command

    if ($caller -eq "ValidateVirtualSwitchDefinition")
    {
        # TRUE
    }
    else # NOT ($caller -eq "ValidateVirtualizationDefinition")
    {
        # FALSE

        ReportWarning ("Do not call {0} directly.  It should only be used from within ValidateVirtualSwitchDefinition." -f @($MyInvocation.MyCommand.Name))
    }

    return $switchDefIsValid
}

function ValidateNewDistributedSwitch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $dsf,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $switchDefIsValid = $false

    # Make sure this function is only called from function:ValidateVirtualSwitchDefinition
    $caller = (Get-PSCallStack)[1].Command

    if ($caller -eq "ValidateVirtualSwitchDefinition")
    {
        # TRUE
    }
    else # NOT ($caller -eq "ValidateVirtualizationDefinition")
    {
        # FALSE

        ReportWarning ("Do not call {0} directly.  It should only be used from within ValidateVirtualSwitchDefinition." -f @($MyInvocation.MyCommand.Name))
    }

    return $switchDefIsValid
}

function ValidateVirtualSwitchDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $dsf,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $switchDefIsValid = $false

    # Make sure this function is only called from function:ValidateVirtualizationDefinition
    $caller = (Get-PSCallStack)[1].Command

    if ($caller -eq "ValidateVirtualizationDefinition")
    {
        # TRUE


                    #region    Check the switch definition
                    if ($null -ne $dsf.switch)
                    {
                        # TRUE

                        #region Check the switch name
                        if (-not [String]::IsNullOrEmpty($dsf.switch.name))
                        {
                            # TRUE

                            if (AddAdministrativePropertyToVirtualizationDefinition -parentObject $dsf.switch -propertyName "vds" -typeName NoteProperty -initialValue $null -doReportSuccess:$doReportSuccess)
                            {
                                # TRUE

                                # Note: the distributed switch name must be unique acrossed the entire vCenter, so no need to look for a switch named $dsf.switch.name in $dsf.switch.dataCenterName
                                $dsf.switch.vds = Get-VDSwitch -Server $dsf.vCenter -Name $dsf.switch.name -ErrorAction SilentlyContinue

                                if ($null -ne $dsf.switch.vds)
                                {
                                    # TRUE

                                    $switchDefIsValid = ValidateExistingDistributedSwitch -dsf $dsf -doReportSuccess:$doReportSuccess
                                }
                                else # NOT ($null -ne $dsf.switch.vds)
                                {
                                    # FALSE

                                    $switchDefIsValid = ValidateNewDistributedSwitch -dsf $dsf -doReportSuccess:$doReportSuccess
                                }
                            }
                            else # NOT (AddAdministrativePropertyToVirtualizationDefinition -parentObject $dsf.switch -propertyName "vds" -typeName NoteProperty -initialValue $null -doReportSuccess:$doReportSuccess)
                            {
                                # FALSE

                                # Nothing.
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsf.switch.name))
                        {
                            # FALSE

                            ReportError ("Missing distributed switch name.")
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region Check the switch data center name
                        if (-not [String]::IsNullOrEmpty($dsf.dataCenterName))
                        {
                            # TRUE

                            $container = Get-Inventory -Server $vCtr -Name $dsf.dataCenterName -ErrorAction SilentlyContinue

                            if ($null -ne $container)
                            {
                                # TRUE

                                if($doReportSuccess)
                                {
                                    ReportSuccess ("Container {0} exists." -f @(Quoted $dsf.dataCenterName))
                                }
                            }
                            else # NOT ($null -ne $container)
                            {
                                # FALSE

                                ReportError ("Container {0} does not exist." -f @(Quoted $dsf.dataCenterName))
                                $definitionIsValid = $false
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsf.dataCenterName))
                        {
                            # FALSE

                            ReportError ("Missing distributed switch container name.")
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region    Check the distributed switch version
                        if (-not [String]::IsNullOrEmpty($dsf.version))
                        {
                            # TRUE

                            if($doReportSuccess)
                            {
                                ReportSuccess ("Distributed switch version {0}." -f @(Quoted $dsf.version))
                            }
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($dsf.version))
                        {
                            # FALSE

                            ReportError ("Missing distrubuted switch version.")
                        }
                        #endregion Check the distributed switch version

                        #region Check MTU
                        if ($null -ne $dsf.mtu)
                        {
                            # TRUE

                            if ($dsf.mtu -match "^\d+$")
                            {
                                # TRUE

                                if ($dsf.mtu -in @(1500,9000))
                                {
                                    # TRUE

                                    if($doReportSuccess)
                                    {
                                        ReportSuccess ("Switch MTU: {0} is valid." -f @($dsf.mtu))
                                    }
                                }
                                else # NOT ($dsf.mtu -in @(1500,9000))
                                {
                                    # FALSE

                                    if ($dsf.mtu -gt 0)
                                    {
                                        # TRUE

                                        ReportWarning ("Check switch MTU value: {0}." -f @($dsf.mtu))
                                    }
                                    else # NOT ($dsf.mtu -gt 0)
                                    {
                                        # FALSE

                                        ReportError ("Switch MTU value {0} is invalid." -f @($dsf.mtu))
                                        $definitionIsValid = $false
                                    }
                                }
                            }
                            else # NOT ($dsf.mtu -match "^\d+$")
                            {
                                # FALSE

                                ReportError ("Switch MTU value {0} is invalid." -f @($dsf.mtu))
                                $definitionIsValid = $false
                            }
                        }
                        else # NOT ($null -ne $dsf.mtu)
                        {
                            # FALSE

                            ReportError "Missing switch MTU in distributed switch definition."
                            $definitionIsValid = $false
                        }
                        #endregion

                        #region    Check all the uplink mappings
                        if ($null -ne $dsf.uplinkMappings)
                        {
                            # TRUE

                            if ($dsf.uplinkMappings -isnot [Array])
                            {
                                # TRUE

                                $dsf.uplinkMappings = @($dsf.uplinkMappings)
                                ReportWarning ("Check switch uplink mappings.")
                            }
                            else # NOT ($dsf.uplinkMappings -isnot [Array])
                            {
                                # FALSE

                                # Nothing
                            }

                            $a = 0
                            while($a -lt $dsf.uplinkMappings.Length)
                            {
                                #region Check the uplink name.
                                if (-not [String]::IsNullOrEmpty($dsf.uplinkMappings[$a].uplinkName))
                                {
                                    # TRUE

                                    if (@($dsf.uplinkMappings | Select-Object -ExpandProperty uplinkName | Where-Object { $_ -eq $dsf.uplinkMappings[$a].uplinkName}).Length -eq 1)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Uplink {0} is valid." -f @($dsf.uplinkMappings[$a].uplinkName))
                                        }
                                    }
                                    else # NOT (@($dsf.uplinkMappings | Select-Object -ExpandProperty uplinkName | Where-Object { $_ -eq $dsf.uplinkMappings[$a].uplinkName}).Length -gt 1)
                                    {
                                        # FALSE

                                        ReportError ("Multiple definitions for uplink {0} [idx: {1}]" -f @($dsf.uplinkMappings[$a].uplinkName, ($a + 1)))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsf.uplinkMappings[$a].uplinkName))
                                {
                                    # FALSE

                                    ReportError ("Missing value for uplink mapping #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion

                                #region Check the vNIC name.
                                if (-not [String]::IsNullOrEmpty($dsf.uplinkMappings[$a].vNICName))
                                {
                                    # TRUE

                                    if (@($dsf.uplinkMappings | Select-Object -ExpandProperty vNICName | Where-Object { $_ -eq $dsf.uplinkMappings[$a].vNICName}).Length -ge 1)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("vNIC {0} is valid." -f @($dsf.uplinkMappings[$a].vNICName))
                                        }
                                    }
                                    else # NOT (@($dsf.uplinkMappings | Select-Object -ExpandProperty vNICName | Where-Object { $_ -eq $dsf.uplinkMappings[$a].vNICName}).Length -ge 1)
                                    {
                                        # FALSE

                                        ReportError ("No vNIC definition found for {0}" -f @($dsf.uplinkMappings[$a].vNICName))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsf.uplinkMappings[$a].vNICName))
                                {
                                    # FALSE

                                    ReportError ("Missing value for vNIC name #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion

                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsf.uplinkMappings)
                        {
                            # FALSE

                            ReportError "Missing distributed switch definition uplink mappings."
                            $definitionIsValid = $false

                            # Make $dsf.uplinkMappings and empty array so later logic will work
                            $dsf.uplinkMappings = @()
                        }
                        #endregion Check all the uplink mappings

                        #region    Check port groups
                        if ($null -ne $dsf.portGroups)
                        {
                            # TRUE

                            if ($dsf.portGroups -isnot [Array])
                            {
                                # TRUE

                                $dsf.portGroups = @($dsf.portGroups)
                                ReportWarning ("Check switch port groups.")
                            }
                            else # NOT ($dsf.portGroups -isnot [Array])
                            {
                                # FALSE

                                # Nothing
                            }

                            $a = 0
                            while($a -lt $dsf.portGroups.Length)
                            {
                                #region    Check the port group name.
                                if (-not [String]::IsNullOrEmpty($dsf.portGroups[$a].name))
                                {
                                    # TRUE

                                    if (@($dsf.portGroups | Select-Object -ExpandProperty name | Where-Object { $_ -eq $dsf.portGroups[$a].name}).Length -eq 1)
                                    {
                                        # TRUE

                                        try
                                        {
                                            $otherVPGs = Get-VirtualPortGroup -Name $dsf.portGroups[$a].name -Datacenter $dsf.dataCenterName -ErrorAction Stop
                                            ReportError ("Port group {0} is invalid.  There is an other port group with the same name in {1}." -f @($dsf.portGroups[$a].name, $dsf.dataCenterName))
                                        }
                                        catch
                                        {
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Port group {0} is valid." -f @($dsf.portGroups[$a].name))
                                            }
                                        }
                                    }
                                    else # NOT (@($dsf.portGroups | Select-Object -ExpandProperty name | Where-Object { $_ -eq $dsf.portGroups[$a].name}).Length -eq 1)
                                    {
                                        # FALSE

                                        ReportError ("Multiple definitions for port group {0} [idx: {1}]" -f @($dsf.portGroups[$a].name, ($a + 1)))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsf..portGroups[$a].name))
                                {
                                    # FALSE

                                    ReportError ("Missing value for port group name #{0}." -f @($a+1))
                                    $definitionIsValid = $false
                                }
                                #endregion Check the port group name.

                                #region    Check the port group port binding.
                                if ($dsf.portGroups[$a].portBinding -match "^STATIC|EPHEMERAL$")
                                {
                                    # TRUE

                                    if($doReportSuccess)
                                    {
                                        ReportSuccess ("{0} port binding {1} is valid." -f @((Quoted $dsf.portGroups[$a].name), (Quoted $dsf.portGroups[$a].portBinding)))
                                    }
                                }
                                else # NOT ($dsf.portGroups[$a].portBinding -match "^STATIC|EPHEMERAL$")
                                {
                                    # FALSE

                                    ReportError ("{0} port binding {1} is invalid." -f @((Quoted $dsf.portGroups[$a].name), (Quoted $dsf.portGroups[$a].portBinding)))
                                    $definitionIsValid = $false
                                }
                                #endregion Check the port group port binding.

                                #region    Check port group VLAN
                                if ($null -ne $dsf.portGroups[$a].vlanID)
                                {
                                    # TRUE

                                    if (($dsf.portGroups[$a].vlanID -ge 1) -and ($dsf.portGroups[$a].vlanID -le 4094))
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Port group `"{0}'s`" VLAN {1} is valid." -f @($dsf.portGroups[$a].name, $dsf.portGroups[$a].vlanID))
                                        }
                                    }
                                    else # NOT (($dsf.portGroups[$a].vlanID -ge 1) -and ($dsf.portGroups[$a].vlanID -le 4094))
                                    {
                                        # FALSE

                                        ReportError ("Port group {0}'s VLAN {1} is invalid." -f @($dsf.portGroups[$a].name, $dsf.portGroups[$a].vlanID))
                                        $definitionIsValid = $false
                                    }

                                }
                                else # NOT ($null -ne $dsf.portGroups[$a].vlanID)
                                {
                                    # FALSE

                                    ReportWarning ("Port group {0} is missing a VLAN ID." -f @(Quoted $dsf.portGroups[$a].name))
                                }
                                #endregion Check port group VLAN

                                #region    Check port group uplinks
                                if ($null -ne $dsf.portGroups[$a].activeUplinkNames)
                                {
                                    # TRUE

                                    if ($dsf.portGroups[$a].activeUplinkNames -isnot [Array])
                                    {
                                        # TRUE

                                        $dsf.portGroups[$a].activeUplinkNames = @($dsf.portGroups[$a].activeUplinkNames)
                                    }
                                    else # NOT ($dsf.portGroups[$a].activeUplinkNames -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing
                                    }
                                }
                                else # NOT ($null -ne $dsf.portGroups[$a].activeUplinkNames)
                                {
                                    # FALSE

                                    ReportError ("Missing active uplink name(s) for port group {0}." -f @(Quoted $dsf.portGroups[$a].name))
                                    $definitionIsValid = $false

                                    # Make $dsf.portGroups[$a].activeUplinkNames an empty array do the logic below works
                                    $dsf.portGroups[$a].activeUplinkNames = @()
                                }

                                if ($null -ne $dsf.portGroups[$a].standbyUplinkNames)
                                {
                                    # TRUE

                                    if ($dsf.portGroups[$a].standbyUplinkNames -isnot [Array])
                                    {
                                        # TRUE

                                        $dsf.portGroups[$a].standbyUplinkNames = @($dsf.portGroups[$a].standbyUplinkNames)
                                    }
                                    else # NOT ($dsf.portGroups[$a].standbyUplinkNames -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing
                                    }
                                }
                                else # NOT ($null -ne $dsf.portGroups[$a].standbyUplinkNames)
                                {
                                    # FALSE

                                    ReportError ("Missing standby uplink name(s) for port group {0}." -f @(Quoted $dsf.portGroups[$a].name))
                                    $definitionIsValid = $false

                                    # Make $dsf.portGroups[$a].standbyUplinkNames an empty array do the logic below works
                                    $dsf.portGroups[$a].standbyUplinkNames = @()
                                }

                                #region    Check the port group's active uplinks
                                $b = 0
                                while($b -lt $dsf.portGroups[$a].activeUplinkNames.Length)
                                {
                                    if (-not [String]::IsNullOrEmpty($dsf.portGroups[$a].activeUplinkNames[$b]))
                                    {
                                        # TRUE

                                        if (@($dsf.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # TRUE

                                            if (@($dsf.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # TRUE

                                                if (@($dsf.uplinkMappings | Where-Object { $_.uplinkName -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("Active uplink {0} for port group {1} is valid." -f @((Quoted $dsf.portGroups[$a].activeUplinkNames[$b]), ($dsf.portGroups[$a].name)))
                                                    }
                                                }
                                                else # NOT (@($dsf.uplinkMappings | Where-Object { $_.uplinkName -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for active uplink {0} on port group {1}." -f @((Quoted $dsf.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsf.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Active uplink {0} cannot also be a standby uplink for port group {1}." -f @((Quoted $dsf.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsf.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].activeUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate active uplink {0} for port group {1}." -f @((Quoted $dsf.portGroups[$a].activeUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsf.portGroups[$a].activeUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank active uplink name [idx: {0}] for port group {1}." -f @(($b + 1), (Quoted $dsf.portGroups[$a].name)))
                                        $definitionIsValid = $false
                                    }

                                    $b++
                                }
                                #endregion Check the port group's active uplinks

                                #region    Check the port group's standby uplinks
                                $b = 0
                                while($b -lt $dsf.portGroups[$a].standbyUplinkNames.Length)
                                {
                                    if (-not [String]::IsNullOrEmpty($dsf.portGroups[$a].standbyUplinkNames[$b]))
                                    {
                                        # TRUE

                                        if (@($dsf.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # TRUE

                                            if (@($dsf.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # TRUE

                                                if (@($dsf.uplinkMappings | Where-Object { $_.uplinkName -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("Standby uplink {0} for port group {1} is valid." -f @((Quoted $dsf.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                                    }
                                                }
                                                else # NOT (@($dsf.uplinkMappings | Where-Object { $_.uplinkName -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -gt 0)
                                                {
                                                    # FALSE

                                                    ReportError ("Switch definition does not contain an uplink mapping for standby uplink {0} on port group {1}." -f @((Quoted $dsf.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                                    $definitionIsValid = $false
                                                }
                                            }
                                            else # NOT (@($dsf.portGroups[$a].activeUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 0)
                                            {
                                                # FALSE

                                                ReportError ("Standby uplink {0} cannot also be an active uplink for port group {1}." -f @((Quoted $dsf.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT (@($dsf.portGroups[$a].standbyUplinkNames | Where-Object { $_ -eq $dsf.portGroups[$a].standbyUplinkNames[$b] }).Length -eq 1)
                                        {
                                            # FALSE

                                            ReportError ("Duplicate standby uplink {0} for port group {1}." -f @((Quoted $dsf.portGroups[$a].standbyUplinkNames[$b]), (Quoted $dsf.portGroups[$a].name)))
                                            $definitionIsValid = $false
                                        }
                                    }
                                    else # NOT (-not [String]::IsNullOrEmpty($dsf.portGroups[$a].standbyUplinkNames[$b]))
                                    {
                                        # FALSE

                                        ReportError ("Blank standby uplink name [idx: {0}] for port group {1}." -f @(($b + 1), (Quoted $dsf.portGroups[$a].name)))
                                        $definitionIsValid = $false
                                    }

                                    $b++
                                }
                                #endregion Check the port group's standby uplinks

                                #endregion Check port group uplinks
                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsf.portGroups)
                        {
                            # FALSE

                            ReportError "Missing distributed switch port groups."
                            $definitionIsValid = $false

                            # Make $dsf.portGroups and empty array so later logic will work
                            $dsf.portGroups = @()
                        }
                        #endregion Check port groups

                        #region    Check Connected hosts
                        if ($null -ne $dsf.connectedHosts)
                        {
                            # TRUE

                            if ($dsf.connectedHosts -isnot [Array])
                            {
                                # TRUE

                                $dsf.connectedHosts = @($dsf.connectedHosts)
                            }
                            else # NOT ($dsf.connectedHosts -isnot [Array])
                            {
                                # FALSE

                                # Nothing.
                            }

                            $a = 0
                            while($a -lt $dsf.connectedHosts.Length)
                            {
                                $vmHost = $null
                                $ucsServer = $null
                                $hostUCSAdaptors = $null
                                #region    Check connected host's vmHostName
                                if (-not [String]::IsNullOrEmpty($dsf.connectedHosts[$a].vmHostName))
                                {
                                    # TRUE

                                    try
                                    {
                                        $vmHost = Get-VMHost -Server $vCtr -Location $dsf.dataCenterName -Name $dsf.connectedHosts[$a].vmHostName -ErrorAction SilentlyContinue
                                    }
                                    catch { }

                                    if ($null -ne $vmHost)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Located VM host: {0} on {1}." -f @((Quoted $dsf.connectedHosts[$a].vmHostName), (Quoted $vCtr.Name)))
                                        }
                                    }
                                    else # NOT ($null -eq (Get-VMHost -Server $vCtr -Name $dsf.connectedHosts[$a].vmHostName -ErrorAction SilentlyContinue))
                                    {
                                        # FALSE

                                        ReportError ("Unable to locate a VM host named {0} in cluster {1}." -f @((Quoted $dsf.connectedHosts[$a].vmHostName), (Quoted $dsf.dataCenterName)))
                                        $definitionIsValid = $false
                                    }
                                }
                                else # NOT (-not [String]::IsNullOrEmpty($dsf.connectedHosts[$a].vmHostName))
                                {
                                    # FALSE

                                    ReportError ("Missing connected host name at idx: [{0}]." -f @($a + 1))
                                    $definitionIsValid = $false

                                    # Set a bogus value for the connected host's vmHostName for later logic
                                    $dsf.connectedHosts[$a].vmHostName = "<MISSING>"
                                }

                                #endregion Check connected host's vmHostName

                                #region    Check connected host's serial number (and UCS vNICs)
                                if (-not [String]::IsNullOrEmpty($dsf.connectedHosts[$a].serial))
                                {
                                    # TRUE

                                    $ucsServer = $dsf.ucsData.Servers | Where-Object { $_.serial -eq $dsf.connectedHosts[$a].serial }

                                    if ($null -ne $ucsServer)
                                    {
                                        # TRUE

                                        if($doReportSuccess)
                                        {
                                            ReportSuccess ("Located UCS compute node with serial number {0}." -f @(Quoted $ucsServer.Serial))
                                        }

                                        #region    Check to make sure there are vNICs defined in UCS for this server
                                        $hostUCSAdaptors = @($dsf.ucsData.Adaptors | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) })
                                        $b = 0
                                        while($b -lt $dsf.uplinkMappings.Length)
                                        {
                                            if (@($hostUCSAdaptors | Where-Object { $_.Name -eq $dsf.uplinkMappings[$b].vNICName }).Length -eq 1)
                                            {
                                                # TRUE

                                                if($doReportSuccess)
                                                {
                                                    ReportSuccess ("UCS vNIC {0} found for {1}." -f @((Quoted $dsf.uplinkMappings[$b].vNICName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                                }
                                            }
                                            else # NOT (@($hostUCSAdaptors | Where-Object { $_.Name -eq $dsf.uplinkMappings[$b].vNICName }).Length -eq 1)
                                            {
                                                # FALSE

                                                ReportWarning ("UCS vNIC {0} not found for {1}." -f @((Quoted $dsf.uplinkMappings[$b].vNICName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
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
                                else # NOT (-not [String]::IsNullOrEmpty($dsf.connectedHosts[$a].serial))
                                {
                                    # FALSE

                                    ReportError ("Missing serial number for connected host {0}." -f @(Quoted $dsf.connectedHosts[$a].vmHostName))
                                    $definitionIsValid = $false
                                }
                                #endregion Check connected host's serial number (and UCS vNICs)

                                #region    Check connected host's vmks
                                if ($null -ne $dsf.connectedHosts[$a].vmks)
                                {
                                    # TRUE

                                    if ($dsf.connectedHosts[$a].vmks -isnot [Array])
                                    {
                                        # TRUE

                                        $dsf.connectedHosts[$a].vmks = @($dsf.connectedHosts[$a].vmks)
                                    }
                                    else # NOT ($dsf.connectedHosts[$a].vmks -isnot [Array])
                                    {
                                        # FALSE

                                        # Nothing.
                                    }

                                    # Sort connected host's vmks by vmkName
                                    $dsf.connectedHosts[$a].vmks = $dsf.connectedHosts[$a].vmks | Sort-Object vmkName

                                    $b = 0
                                    while($b -lt $dsf.connectedHosts[$a].vmks.Length)
                                    {
                                        $vmkPortGroup = $null
                                        $vmHostVMK = $null

                                        #region    Check the vmk's port group name
                                        # Since we've already checked the switch's port groups, all I'll do here is make sure
                                        #   the vmk's port group is among the switches port groups.
                                        $vmkPortGroup = $dsf.portGroups | Where-Object { $_.name -eq $dsf.connectedHosts[$a].vmks[$b].portGroupName }
                                        if ($null -ne $vmkPortGroup)
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Port group {0} for VMK {1} on {2} is valid." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].portGroupName), (Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                            }
                                        }
                                        else # NOT ($null -ne $vmkPortGroup)
                                        {
                                            # FALSE

                                            ReportError ("Port group {0} for VMK {1} on {2} is invalid." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].portGroupName), (Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check the vmk's port group name

                                        #region    Check vmk's name
                                        if ($dsf.connectedHosts[$a].vmks[$b].vmkName -match "^vmk\d+$")
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("VMK {0} for {1} is valid." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                            }

                                            if ($null -ne $vmHost)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    $vmHostVMK = Get-VMHostNetworkAdapter -Server $vCtr -VMHost $vmHost -VMKernel -Name $dsf.connectedHosts[$a].vmks[$b].vmkName -ErrorAction SilentlyContinue
                                                }
                                                catch { }

                                                if ($null -ne $vmHostVMK)
                                                {
                                                    # TRUE

                                                    if ($vmHostVMK.PortGroupName -eq $dsf.connectedHosts[$a].vmks[$b].portGroupName)
                                                    {
                                                        # TRUE

                                                        if($doReportSuccess)
                                                        {
                                                            ReportSuccess ("VMK {0} for {1} is already connected to {2}." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName), (Quoted $vmHostVMK.PortGroupName)))
                                                        }
                                                    }
                                                    else # NOT ($vmHostVMK.PortGroupName -eq $dsf.connectedHosts[$a].vmks[$b].portGroupName)
                                                    {
                                                        # FALSE

                                                        if($doReportSuccess)
                                                        {
                                                            ReportSuccess ("VMK {0} for {1} will be migrated to {2}." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName), (Quoted $dsf.connectedHosts[$a].vmks[$b].portGroupName)))
                                                        }
                                                    }
                                                }
                                                else # NOT ($null -ne $vmHostVMK)
                                                {
                                                    # FALSE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("VMK {0} for {1} is will be created." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                                    }
                                                }

                                            }
                                            else # NOT ($null -ne $vmHost)
                                            {
                                                # FALSE

                                                # Nothing.
                                            }
                                        }
                                        else # NOT ($dsf.connectedHosts[$a].vmks[$b].vmkName -match "^vmk\d")
                                        {
                                            # FALSE

                                            ReportError ("VMK {0} for {1} is invalid." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].vmkName), (Quoted $dsf.connectedHosts[$a].vmHostName)))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's name

                                        #region    Check vmk's MTU
                                        if ($null -ne $dsf.connectedHosts[$a].vmks[$b].mtu)
                                        {
                                            # TRUE

                                            if ($dsf.connectedHosts[$a].vmks[$b].mtu -match "^\d+$")
                                            {
                                                # TRUE

                                                if ($dsf.connectedHosts[$a].vmks[$b].mtu -in @(1500,9000))
                                                {
                                                    # TRUE

                                                    if($doReportSuccess)
                                                    {
                                                        ReportSuccess ("{0} MTU: {1} is valid." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].mtu))
                                                    }
                                                }
                                                else # NOT ($dsf.connectedHosts[$a].vmks[$b].mtu -in @(1500,9000))
                                                {
                                                    # FALSE

                                                    if ($dsf.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # TRUE

                                                        ReportWarning ("Check MTU value: {0} for {1}." -f @($dsf.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                    }
                                                    else # NOT ($dsf.connectedHosts[$a].vmks[$b].mtu -gt 0)
                                                    {
                                                        # FALSE

                                                        ReportError ("{0} MTU: {1} is invalid." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].mtu))
                                                        $definitionIsValid = $false
                                                    }
                                                }

                                                if ($null -ne $hostUCSAdaptors)
                                                {
                                                    # TRUE

                                                    $vmkUplinkNames = @(($vmkPortGroup.activeUplinkNames + $vmkPortGroup.standbyUplinkNames) | Select-Object -Unique)
                                                    $vmkvNICNames = @($dsf.uplinkMappings | Where-Object { ($_.uplinkName -in $vmkUplinkNames) } | Select-Object -Unique -ExpandProperty vNICName)

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
                                                                if ($dsf.connectedHosts[$a].vmks[$b].mtu -eq $vmkAdaptors[$d].Mtu)
                                                                {
                                                                    # TRUE

                                                                    if($doReportSuccess)
                                                                    {
                                                                        ReportSuccess ("MTU: {0} for {1} matches it's uplink's MTU ({2} MTU: {3})." -f @($dsf.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                    }
                                                                }
                                                                else # NOT ($dsf.connectedHosts[$a].vmks[$b].mtu -eq $vmkAdaptors[$d].Mtu)
                                                                {
                                                                    # FALSE

                                                                    ReportWarning ("MTU: {0} for {1} does not match it's uplink's MTU ({2} MTU: {3})." -f @($dsf.connectedHosts[$a].vmks[$b].mtu, (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $vmkAdaptors[$d].Name, $vmkAdaptors[$d].MTU))
                                                                }
                                                                $d++
                                                            }
                                                        }
                                                        else # NOT ($vmkAdaptors.Length -gt 0)
                                                        {
                                                            # FALSE

                                                            ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                            $definitionIsValid = $false
                                                        }

                                                        $c++
                                                    }
                                                }
                                                else # NOT ($null -ne $hostUCSAdaptors)
                                                {
                                                    # FALSE

                                                    ReportError ("Unable to verify MTU for {0} against it's uplink." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                                    $definitionIsValid = $false
                                                }


                                            }
                                            else # NOT ($dsf.connectedHosts[$a].vmks[$b].mtu -match "^\d+$")
                                            {
                                                # FALSE

                                                ReportError ("{0} MTU: {1} is invalid." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].mtu))
                                                $definitionIsValid = $false
                                            }
                                        }
                                        else # NOT ($null -ne $dsf.mtu)
                                        {
                                            # FALSE

                                            ReportError "Missing switch MTU in distributed switch definition."
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's MTU

                                        #region    Check vmk's ipAddress
                                        try
                                        {
                                            $ipAddr = [System.Net.IPAddress]::Parse($dsf.connectedHosts[$a].vmks[$b].ipAddress)
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("IP Address {0} is valid for {1}." -f @((Quoted $ipAddr.IPAddressToString), (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("IP Address {0} is invalid for {1}." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].ipAddress), (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's ipAddress

                                        #region    Check vmk's subnet mask
                                        try
                                        {
                                            $ipAddr = [System.Net.IPAddress]::Parse($dsf.connectedHosts[$a].vmks[$b].subnetMask)
                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("Subnet mask {0} is valid for {1}." -f @((Quoted $ipAddr.IPAddressToString), (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Subnet mask {0} is invalid for {1}." -f @((Quoted $dsf.connectedHosts[$a].vmks[$b].subnetMask), (Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":"))))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's subnet mask

                                        #region    Check vmk's mgmtEnabled
                                        if (($null -ne $dsf.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsf.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("mgmtEnabled for {0} is valid [{1}]." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsf.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsf.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("mgmtEnabled for {0} is invalid [{1}]." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].mgmtEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's mgmtEnabled

                                        #region    Check vmk's vMotionEnabled
                                        if (($null -ne $dsf.connectedHosts[$a].vmks[$b].vMotionEnabled) -and ($dsf.connectedHosts[$a].vmks[$b].vMotionEnabled -is [bool]))
                                        {
                                            # TRUE

                                            if($doReportSuccess)
                                            {
                                                ReportSuccess ("vMotionEnabled for {0} is valid [{1}]." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            }
                                        }
                                        else # NOT (($null -ne $dsf.connectedHosts[$a].vmks[$b].mgmtEnabled) -and ($dsf.connectedHosts[$a].vmks[$b].mgmtEnabled -is [bool]))
                                        {
                                            # FALSE

                                            ReportError ("vMotionEnabled for {0} is invalid [{1}]." -f @((Quoted (@($dsf.connectedHosts[$a].vmHostName, $dsf.connectedHosts[$a].vmks[$b].vmkName) -join ":")), $dsf.connectedHosts[$a].vmks[$b].vMotionEnabled))
                                            $definitionIsValid = $false
                                        }
                                        #endregion Check vmk's vMotionEnabled

                                        $b++
                                    }

                                }
                                else # NOT ($null -ne $dsf.connectedHosts[$a].vmks)
                                {
                                    # FALSE

                                    ReportError ("Missing VMK definitions for {0}." -f @(Quoted $dsf.connectedHosts[$a].vmHostName))
                                    $definitionIsValid = $false
                                }
                                #endregion Check connected host's vmks
                                $a++
                            }
                        }
                        else # NOT ($null -ne $dsf.connectedHosts)
                        {
                            # FALSE

                            ReportError ("Missing connected hosts in switch definition.")
                            $definitionIsValid = $false
                        }
                        #endregion Check Connected hosts
                    }
                    else # NOT ($null -ne $dsf.switch)
                    {
                        # FALSE

                        ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                        $definitionIsValid = $false
                    }
                    #endregion Check the switch definition

    }
    else # NOT ($caller -eq "ValidateVirtualizationDefinition")
    {
        # FALSE

        ReportWarning ("Do not call {0} directly.  It should only be used from within ValidateVirtualizationDefinition." -f @($MyInvocation.MyCommand.Name))
    }

    return $switchDefIsValid
}

function ValidateVirtualizationDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $dsf,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    if (($null -ne $dsf.vCenter) -and ($null -ne $dsf.ucsManager) -and ($null -ne $dsf.ncController))
    {
        # TRUE


    }
    else # NOT (($null -ne $vCtr) -and ($null -ne $ucsManager) -and ($null -ne $ncController))
    {
        # FALSE

        ReportWarning ("Not connected to all required environments.")
    }

        if ($dsf.vCenter.IsConnected)
        {
            # TRUE

                if ($null -ne $dsf.ucsData)
                {
                    # TRUE

                    if (ValidateVirtualSwitchDefinition -dsf $dsf -doReportSuccess:$doReportSuccess)
                    {
                        # TRUE

                    }
                    else # NOT (ValidateVirtualSwitchDefinition -dsf $dsf -doReportSuccess:$doReportSuccess)
                    {
                        # FALSE

                        # Nothing.
                    }
                }
                else # NOT ($null -ne $dsf.ucsData)
                {
                    # FALSE

                    ReportError ("Unable to continue without UCS Data.")
                    $definitionIsValid = $false
                }

        }
        else # NOT ($vCtr.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @((Quoted $vCtr.Name), $MyInvocation.MyCommand.Name))
            $definitionIsValid = $false
        }

    return $definitionIsValid
}

function LoadVirtualizationDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateScript({ (-not [String]::IsNullOrEmpty($_)) -and (Test-Path -Path $_) })]
        [String] $fileName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $virtualizationDefinition = $null
    try
    {
        $virtualizationDefinitionRaw = Get-Content -Path $fileName -ErrorAction Stop
        if ($doReportSuccess)
        {
            # TRUE

            ReportSuccess ("Loaded raw virtualization definition from: {0}." -f @((Quoted $fileName)))
        }
        else # NOT ($doReportSuccess)
        {
            # FALSE

            # Nothing.
        }

        try
        {
            $virtualizationDefinitionTemp = $virtualizationDefinitionRaw | ConvertFrom-Json -ErrorAction Stop
            if ($doReportSuccess)
            {
                # TRUE

                ReportSuccess "Parsed raw virtualization definition from json to an object."
            }
            else # NOT ($doReportSuccess)
            {
                # FALSE

                # Nothing.
            }

            # Top level properties used during the processing of the virtualization definition
            $adminProperties = @(
                @{Name = "IsValid"; InitialValue = $false },
                @{Name = "vCenter"; InitialValue = $null },
                @{Name = "ucsManager"; InitialValue = $null },
                @{Name = "ncController"; InitialValue = $null },
                @{Name = "ucsData"; InitialValue = $null }
            )

            $a = 0
            $successful = $true
            while($successful -and ($a -lt $adminProperties.Length))
            {
                $successful = AddAdministrativePropertyToVirtualizationDefinition -virtualizationDefinition $virtualizationDefinitionTemp -propertyName $adminProperties[$a].Name -typeName NoteProperty -initialValue $adminProperties[$a].InitialValue -doReportSuccess:$doReportSuccess -allowExisting:$false
                $a++
            }

            if ($successful)
            {
                # TRUE

                $virtualizationDefinition = $virtualizationDefinitionTemp
            }
            else # NOT ($successful)
            {
                # FALSE

                # Nothing.
            }
        }
        catch
        {
            ReportError "Failed to parse raw virtualization definition from JSON format to an object."
        }
    }
    catch
    {
        ReportError ("Failed to load raw virtualization definition from {0}." -f @((Quoted $fileName)))
    }

    return $virtualizationDefinition
}

function GetUCSData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $dsf,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $successful = $false
    if ($null -ne $dsf)
    {
        # TRUE

        if ($null -ne $dsf.ucsManager)
        {
            # TRUE

            $dsf.ucsData = "" | Select-Object Adaptors, Servers, VLANs

            # Retrieve required data from UCS

            #region    Collect UCS Compute node details
            try  # Just to subdue any error messages.
            {
                $dsf.ucsData.Servers = @(Get-UCSServer -Ucs $dsf.ucsManager -ErrorAction SilentlyContinue)
            }
            catch { }

            if ($dsf.ucsData.Servers.Length -gt 0)
            {
                # TRUE

                if($doReportSuccess)
                {
                    ReportSuccess ("Retrieved {0} compute node details from {1}." -f @($dsf.ucsData.Servers.Length, $dsf.ucsManager.Name))
                }

                #region    Collect UCS vNIC information
                try  # Just to subdue any error messages.
                {
                    $dsf.ucsData.Adaptors = @(Get-UCSAdaptorHostEthIf -Ucs $dsf.ucsManager -ErrorAction SilentlyContinue)
                }
                catch { }

                if ($dsf.ucsData.Adaptors.Length -gt 0)
                {
                    # TRUE

                    if($doReportSuccess)
                    {
                        ReportSuccess ("Retrieved {0} vNIC details from {1}." -f @($dsf.ucsData.Adaptors.Length, $dsf.ucsManager.Name))
                    }

                    #region    Collect UCS VLAN information
                    try  # Just to subdue any error messages.
                    {
                        $dsf.ucsData.VLANs = @(Get-UcsVlan -Ucs $dsf.ucsManager -ErrorAction SilentlyContinue)
                    }
                    catch { }

                    if ($dsf.ucsData.VLANs.Length -gt 0)
                    {
                        # TRUE

                        $successful = $true
                        if($doReportSuccess)
                        {
                            ReportSuccess ("Retrieved {0} VLANs from {1}." -f @($dsf.ucsData.VLANs.Length, $dsf.ucsManager.Name))
                        }
                    }
                    else # NOT ($dsf.ucsData.VLANs.Length -gt 0)
                    {
                        # FALSE

                        ReportError ("Failed to retrieve VLAN details from {0}." -f @($dsf.ucsManager.Name))
                        $dsf.ucsData = $null
                    }
                    #endregion Collect UCS VLAN information
                }
                else # NOT ($dsf.ucsData.Adaptors.Length -gt 0)
                {
                    # FALSE

                    ReportError ("Failed to retrieve vNIC details from {0}." -f @($dsf.ucsManager.Name))
                    $dsf.ucsData = $null
                }
                #endregion Collect UCS vNIC information
            }
            else # NOT ($dsf.ucsData.Servers.Length -gt 0)
            {
                # FALSE

                ReportError ("Failed to retrieve compute node details from {0}." -f @($dsf.ucsManager.Name))
                $dsf.ucsData = $null
            }
            #endregion Collect UCS Compute node details
        }
        else # NOT ($null -ne $dsf.ucsManager)
        {
            # FALSE

            ReportError ("Not connected to UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $dsf)
    {
        # FALSE

        ReportError ("Missing virtualization definition in {0}." -f @($MyInvocation.MyCommand.Name))
    }

    return $successful
}

function ProcessVirtualizationDefinition
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $vCenterName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $ucsManagerName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $cdotClusterName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [ValidateScript({ (-not [String]::IsNullOrEmpty($_)) -and (Test-Path -Path $_) })]
        [String] $virtualizationDefinitionFileName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $dsf = LoadVirtualizationDefinition -fileName $virtualizationDefinitionFileName -doReportSuccess:$doReportSuccess
    if ($null -ne $dsf)
    {
        # TRUE

        # Connect to the various environments required to validate the configuration
        $dsf.vCenter, $dsf.ucsManager, $dsf.ncController = ConnectToEnvironments -vCenterName "vcenter.powereng.com" -ucsManagerName "cdc-ucs01.powereng.com" -cdotClusterName "cdc-cdotclst01.powereng.com" -doReportSuccess:$doReportSuccess

        if (($null -ne $dsf.vCenter) -and ($null -ne $dsf.ucsManager) -and ($null -ne $dsf.ncController))
        {
            # TRUE

            if (GetUCSData -dsf $dsf -doReportSuccess:$doReportSuccess)
            {
                # TRUE

                # $definitionIsValid = ValidateVirtualizationDefinition -vCenter $vCtr -ucsManager $ucsManager -ncController $ncController -dsf $dsf -doReportSuccess:$doReportSuccess
            }
            else # NOT (GetUCSData -dsf $dsf -doReportSuccess:$doReportSuccess)
            {
                # FALSE

                # Nothing GetUCSData would have reported any errors.
            }
        }
        else # NOT (($null -ne $vCtr) -and ($null -ne $ucsManager) -and ($null -ne $ncController))
        {
            # FALSE

            ReportWarning ("Not connected to all required environments.")
        }
    }
    else # NOT ($null -ne $dsf)
    {
        # FALSE

        # Nothing -- already posted an error/warning
    }

    return $dsf
}
