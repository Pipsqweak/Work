#Requires -Version 5.1
#Requires -Module @{ ModuleName = 'Cisco.UCSManager'; ModuleVersion = '3.0.2.4' }

function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
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
    } `
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

function ReportError
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Red ("ERROR: {0}" -f @($message))
}

function ReportWarning
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Yellow ("WARNING: {0}" -f @($message))
}

function ReportNotice
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor White $message
}

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
        $myValueStr = $myValue.ToString()

        if (-not [String]::IsNullOrEmpty($myValueStr))
        {
            $quotedValue = "`"{0}`"" -f @($myValue.ToString())
        } `
        else # NOT (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $myValue)
    {
        # Nothing.
    }

    return $quotedValue
}

# InvokeUCSFunction was added late in the game, so not all calls to UCS functions use it.
function InvokeUCSFunction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $functionName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $failureMsg,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [HashTable] $cmdParams,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $noErrorOnNull,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $noErrorOnException
    )

    $success = $true
    $obj = $null

    if (-not ($cmdParams.ContainsKey("ErrorAction")))
    {
        $cmdParams.Add("ErrorAction", "Stop")
    } `
    else # NOT (-not ($cmdParams.ContainsKey("ErrorAction")))
    {
        # Nothing.
    }

    try
    {
        $obj = & $functionName @cmdParams

        if ((-not $noErrorOnNull) -and ($null -eq $obj))
        {
            ReportError ("`t{0}  {1} returned `$null." -f @($failureMsg, $functionName))
            $success = $false
        } `
        else # NOT (($errorOnNull) -and ($null -eq $obj))
        {
            # Nothing
        }
    }
    catch
    {
        if (-not $noErrorOnException)
        {
            ReportError ("`t{0} {1} threw an exception." -f @($failureMsg, $functionName))
            $success = $false
        } `
        else # NOT (-not $noErrorOnException)
        {
            # Nothing.
        }
    }

    return @($success, $obj)
}

function SetManagementConfiguration
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object] $mgmtConfig
    )
    <#
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
    #>

    $success = $true
    ReportNotice "Configuring communication management"
    try
    {
        $ucsSvcEndpoint = Get-UcsSvcEp -Ucs $ucs -ErrorAction Stop

        ReportNotice "`tSetting domain name"
        try
        {
            $managedObject = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId "CommDns" -PropertyMap @{ Domain = $mgmtConfig.domainName } -Parent $ucsSvcEndpoint -ErrorAction Stop

            if ($null -ne $managedObject)
            {
                # Nothing domain name was set.
            } `
            else # NOT ($null -ne $managedObject)
            {
                ReportError "Failed to set system domain name.  Add-UcsManagedObject returned `$null."
                $success = $false
            }
        }
        catch
        {
            ReportError "Failed to set system domain name.  Add-UcsManagedObject threw an exception."
            $success = $false
        }

        ReportNotice "`tSetting virtual IP address configuration."
        try
        {
            $virtualIPConfigParams = @{
                Name = $mgmtConfig.systemName;
                Owner = $mgmtConfig.systemOwner;
                Descr = $mgmtConfig.description;
                Site = $mgmtConfig.site;
                Dn ="sys";
            }

            $managedObject = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId "TopSystem" -PropertyMap $virtualIPConfigParams -ErrorAction Stop

            if ($null -ne $managedObject)
            {
                # Nothing Virtual IP configuration was set
            } `
            else # NOT ($null -ne $managedObject)
            {
                ReportError "Failed to set virtual IP configuration.  Add-UcsManagedObject returned `$null."
                $success = $false
            }
        }
        catch
        {
            ReportError "Failed to set virtual IP configuration.  Add-UcsManagedObject threw an exception."
            $success = $false
        }

        ReportNotice "`tSetting management interfaces monitoring to 'disabled'."
        try
        {
            $managedObject = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId "ExtmgmtIfMonPolicy" -PropertyMap @{AdminState = "disabled"; Dn = "sys/extmgmt-intf-monitor-policy"; } -ErrorAction Stop

            if ($null -ne $managedObject)
            {
                # Nothing management monitoring policy set to disabled.
            } `
            else # NOT ($null -ne $managedObject)
            {
                ReportError "Failed to set management interfaces monitoring to 'disabled'.  Add-UcsManagedObject returned `$null."
                $success = $false
            }
        }
        catch
        {
            ReportError "Failed to set management interfaces monitoring to 'disabled'.  Add-UcsManagedObject threw an exception."
            $success = $false
        }

        ReportNotice "`tSetting DNS servers."
        try
        {
            $ucsDNS = Get-UcsDns -Ucs $ucs -SvcEp $ucsSvcEndpoint -ErrorAction Stop

            if ($null -ne $ucsDNS)
            {
                $a = 0
                while($a -lt $mgmtConfig.dnsServers.Length)
                {
                    try
                    {
                        $Error.Clear()
                        $dnsServer = Add-UcsDnsServer -Ucs $ucs -Dns $ucsDNS -Name $mgmtConfig.dnsServers[$a] -ErrorAction Stop

                        if ($null -ne $dnsServer)
                        {
                            # Nothing DNS server added.
                        } `
                        else # NOT ($null -ne $managedObject)
                        {
                            ReportError ("Failed to add DNS server {0}.  Add-UcsDnsServer returned `$null." -f @($mgmtConfig.dnsServers[$a]))
                            $success = $false
                        }
                    }
                    catch
                    {
                        $isRealError = $true
                        $myError = Get-Error
                        if ($null -ne $myError)
                        {
                            if (-not [String]::IsNullOrEmpty($myError.Exception.Message))
                            {
                                if ($myError.Exception.Message -match "object already exists.")
                                {
                                    $isRealError = $false
                                } `
                                else # NOT ($myError.Message -match "object already exists.")
                                {
                                    # Nothing
                                }
                            } `
                            else # NOT (-not [String]::IsNullOrEmpty($myError.Message))
                            {
                                # Nothing
                            }
                        } `
                        else # NOT ($null -ne $myError)
                        {
                            # Nothing.
                        }

                        if ($isRealError)
                        {
                            ReportError ("Failed to add DNS server {0}.  Add-UcsDnsServer threw an exception." -f @($mgmtConfig.dnsServers[$a]))
                            $success = $false
                        } `
                        else # NOT ($isRealError)
                        {
                            # Nothing.
                        }
                    }

                    $a++
                }
            } `
            else # NOT ($null -ne $ucsDNS)
            {
                ReportError "`tFailed to retrieve UCS DNS configuration.  Get-UcsDns returned `$null."
            }
        }
        catch
        {
            ReportError "`tFailed to retrieve UCS DNS configuration.  Get-UcsDns threw an exception."
        }

        ReportNotice "`tSetting timezone"
        try
        {
            $managedObject = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId "CommDateTime" -PropertyMap @{ Timezone = $mgmtConfig.timezone } -Parent $ucsSvcEndpoint -ErrorAction Stop

            if ($null -ne $managedObject)
            {
                # Nothing timezone was set.
            } `
            else # NOT ($null -ne $managedObject)
            {
                ReportError "Failed to set timezone.  Add-UcsManagedObject returned `$null."
                $success = $false
            }
        }
        catch
        {
            ReportError "Failed to set timezone.  Add-UcsManagedObject threw an exception."
            $success = $false
        }

        ReportNotice "`tSetting NTP servers."
        try
        {
            $ucsTimezone = Get-UcsTimeZone -Ucs $ucs -SvcEp $ucsSvcEndpoint -ErrorAction Stop

            if ($null -ne $ucsTimezone)
            {
                $a = 0
                while($a -lt $mgmtConfig.ntpServers.Length)
                {
                    try
                    {
                        $Error.Clear()
                        $ntpServer = Add-UcsNtpServer -Ucs $ucs -Timezone $ucsTimezone -Name $mgmtConfig.ntpServers[$a] -ErrorAction Stop

                        if ($null -ne $ntpServer)
                        {
                            # Nothing DNS server added.
                        } `
                        else # NOT ($null -ne $ntpServer)
                        {
                            ReportError ("Failed to add NTP server {0}.  Add-UcsNtpServer returned `$null." -f @($mgmtConfig.ntpServers[$a]))
                            $success = $false
                        }
                    }
                    catch
                    {
                        $isRealError = $true
                        $myError = Get-Error
                        if ($null -ne $myError)
                        {
                            if (-not [String]::IsNullOrEmpty($myError.Exception.Message))
                            {
                                if ($myError.Exception.Message -match "object already exists.")
                                {
                                    $isRealError = $false
                                } `
                                else # NOT ($myError.Message -match "object already exists.")
                                {
                                    # Nothing
                                }
                            } `
                            else # NOT (-not [String]::IsNullOrEmpty($myError.Message))
                            {
                                # Nothing
                            }
                        } `
                        else # NOT ($null -ne $myError)
                        {
                            # Nothing.
                        }

                        if ($isRealError)
                        {
                            ReportError ("Failed to add NTP server {0}.  Add-UcsNtpServer threw an exception." -f @($mgmtConfig.ntpServers[$a]))
                            $success = $false
                        } `
                        else # NOT ($isRealError)
                        {
                            # Nothing.
                        }
                    }

                    $a++
                }
            } `
            else # NOT ($null -ne $ucsTimezone)
            {
                ReportError "`tFailed to retrieve UCS timezone configuration.  Get-UcsTimezone returned `$null."
                $success = $false
            }
        }
        catch
        {
            ReportError "`tFailed to retrieve UCS timezone configuration.  Get-UcsTimezone threw an exception."
            $success = $false
        }
    }
    catch
    {
        ReportError ("`tFailed to get a service endpoint from {0}." -f @($ucs.Name))
        $success = $false
    }

    return $success
}

function CreateUCSVlans
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object[]] $vlanDefinitions,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $createMissingVLANs
    )

    $success = $true
    ReportNotice "Creating VLANs"
    # Create all VLANS:
    try
    {
        $ucsLANCloud = Get-UcsLanCloud -Ucs $ucs -ErrorAction Stop

        if ($null -ne $ucsLANCloud)
        {
            try
            {
                $existingUCSVLANS = @(Get-UcsVlan -Ucs $ucs -LanCloud $ucsLANCloud -SwitchId "dual" -ErrorAction Stop)

                $a = 0
                while($a -lt $vlanDefinitions.Length)
                {
                    if($null -eq ($existingUCSVLANS | Where-Object { ($_.Id -eq $vlanDefinitions[$a].ID) -and ($_.Name -eq $vlanDefinitions[$a].Name) }))
                    {
                        if ($createMissingVLANs)
                        {
                            $newVLANParams = @{
                                Ucs = $ucs
                                LanCloud = $ucsLANCloud
                                Id = $vlanDefinitions[$a].ID
                                Name = $vlanDefinitions[$a].Name
                                CompressionType = "included"
                                DefaultNet = "no"
                                McastPolicyName = ""
                                PolicyOwner = "local"
                                PubNwName = ""
                                Sharing = "none"
                                ErrorAction = "Stop"
                            }

                            try
                            {
                                $newVLAN = Add-UcsVlan @newVLANParams

                                if($null -ne $newVLAN)
                                {
                                    # Write-Host -ForegroundColor Green ("`tCreated VLAN: {0}/{1}" -f @($newVLAN.Id, $newVLAN.Name))
                                } `
                                else #
                                {
                                    ReportError ("`tFailed to create VLAN: {0} :: {1}.  Add-UcsVlan returned `$null." -f @($newVLANParams.ID, $newVLANParams.Name))
                                    $success = $false
                                }
                            }
                            catch
                            {
                                ReportError ("`tFailed to create VLAN: {0} :: {1}.  Add-UcsVlan threw an exception." -f @($newVLANParams.ID, $newVLANParams.Name))
                                $success = $false
                            }
                        } `
                        else # NOT ($createMissingVLANs)
                        {
                            # Nothing.
                        }
                    } `
                    else  # NOT ($null -eq ($existingUCSVLANS | Where-Object { ($_.Id -eq $vlanDefinitions[$a].ID) -and ($_.Name -eq $vlanDefinitions[$a].Name) }))
                    {
                        # Nothing - VLAN already exists.
                    }
                    $a++
                }
            }
            catch
            {
                ReportError ("`tFailed to retrieve existing VLANs.  Get-UcsVlan threw an exception." -f @($ucs.Name))
                $success = $false
            }
        } `
        else # NOT ($null -ne $ucsLANCloud)
        {
            ReportError ("`tFailed to retrieve LAN cloud from {0}.  Get-UcsLanCloud returned `$null." -f @($ucs.Name))
            $success = $false
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve LAN cloud from {0}.  Get-UcsLanCloud threw and exception." -f @($ucs.Name))
        $success = $false
    }

    return $success
}

function CreateUCSVlanGroups
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object[]] $vlanGroupDefinitions,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $createMissingVLANGroups,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $updateVLANGroupMembers
    )

    $success = $true
    ReportNotice "Creating VLAN Groups"

    try
    {
        # Get the existing VLAN groups
        $ucsLANCloud = Get-UcsLanCloud -Ucs $ucs -ErrorAction Stop
        if ($null -ne $ucsLANCloud)
        {
            $existingUCSVLANGroups = @()
            try
            {
                Get-UcsFabricNetGroup -Ucs $ucs -LanCloud $ucsLANCloud -ErrorAction Stop | Foreach-Object { $existingUCSVLANGroups += $_ }

                # Create all VLAN Groups
                $a = 0
                while(($success) -and ($a -lt $vlanGroupDefinitions.Length))
                {
                    # Get the existing VLAN Group if it already exists.
                    $vlanGroup = $existingUCSVLANGroups | Where-Object { $_.Name -eq $vlanGroupDefinitions[$a].Name }

                    # If the VLAN group doesn't exist, then try to create it
                    if($null -eq $vlanGroup)
                    {
                        if ($createMissingVLANGroups)
                        {
                            try
                            {
                                $vlanGroup = Add-UcsFabricNetGroup -Ucs $ucs -LanCloud $ucsLANCloud -Name $vlanGroupDefinitions[$a].Name -ErrorAction Stop
                                if($null -ne $vlanGroup)
                                {
                                    $existingUCSVLANGroups += $vlanGroup
                                } `
                                else # NOT ($null -ne $vlanGroup)
                                {
                                    ReportError ("`tFailed to create VLAN group {0}.  Add-UcsFabricNetGroup returned `$null." -f @($vlanGroupDefinitions[$a].Name))
                                    $success = $false
                                }
                            }
                            catch
                            {
                                ReportError ("`tFailed to create VLAN group {0}.  Add-UcsFabricNetGroup threw an exception." -f @($vlanGroupDefinitions[$a].Name))
                                $success = $false
                            }
                        } `
                        else # NOT ($createMissingVLANGroups)
                        {
                            # Nothing.
                        }
                    }

                    # If we have $vlanGroup, check its members.
                    if($null -ne $vlanGroup)
                    {
                        try
                        {
                            $vlanGroupMembers = @(Get-UcsFabricPooledVlan -Ucs $ucs -FabricNetGroup $vlanGroup -ErrorAction Stop)

                            # First make sure everything we want is in the VLAN Group
                            $b = 0
                            while(($success) -and ($b -lt $vlanGroupDefinitions[$a].Members.Length))
                            {
                                if($null -eq ($vlanGroupMembers | Where-Object { $_.Name -eq $vlanGroupDefinitions[$a].Members[$b]}))
                                {
                                    # Write-Host -ForegroundColor Red ("VLAN Group: {0} is missing VLAN: {1}" -f @($vlanGroupDefinitions[$a].Name, $vlanGroupDefinitions[$a].Members[$b]))

                                    if ($updateVLANGroupMembers)
                                    {
                                        try
                                        {
                                            $vlanGroupMember = Add-UcsFabricPooledVlan -Ucs $ucs -ModifyPresent -FabricNetGroup $vlanGroup -Name $vlanGroupDefinitions[$a].Members[$b] -ErrorAction Stop
                                            # Write-Host -ForegroundColor Green ("`tAdded VLAN: {0} to VLAN Group: {1}" -f @($vlanGroupMember.Name, $vlanGroup.Name))
                                        }
                                        catch
                                        {
                                            ReportError ("`tFailed to add VLAN: {0} to VLAN Group: {1}" -f @($vlanGroupMember.Name, $vlanGroup.Name))
                                            $success = $false
                                        }
                                    } `
                                    else # NOT ($updateVLANGroupMembers)
                                    {
                                        # Nothing
                                    }
                                } `
                                else # NOT ($null -eq ($vlanGroupMembers | Where-Object { $_.Name -eq $vlanGroupDefinitions[$a].Members[$b]}))
                                {
                                    # Nothing
                                }
                                $b++
                            }

                            # Second, make sure only the VLANs we want are in the VLAN Group
                            #   No need to add any VLANs we added above, since they are needed.  Below we are only looking for "extra" members so we can remove them.
                            $b = 0
                            while(($success) -and ($b -lt $vlanGroupMembers.Length))
                            {
                                if($null -eq ($vlanGroupDefinitions[$a].Members | Where-Object { $_ -eq $vlanGroupMembers[$b].Name }))
                                {
                                    if ($updateVLANGroupMembers)
                                    {
                                        try
                                        {
                                            [void] (Remove-UcsFabricPooledVlan -Ucs $ucs -FabricPooledVlan $vlanGroupMembers[$b] -ErrorAction Stop)
                                            # Write-Host -ForegroundColor Green ("`Removed VLAN: {0} from VLAN Group: {1}" -f @($vlanGroupMembers[$b].Name, $vlanGroup.Name))
                                        }
                                        catch
                                        {
                                            ReportError ("`tFailed to remove VLAN: {0} from VLAN Group: {1}" -f @($vlanGroupMembers[$b].Name, $vlanGroup.Name))
                                            $success = $false
                                        }
                                    } `
                                    else # NOT ($updateVLANGroupMembers)
                                    {
                                        # Nothing
                                    }
                                } `
                                else # NOT ($null -eq ($vlanGroupDefinitions[$a].Members | Where-Object { $_ -eq $vlanGroupMembers[$b].Name }))
                                {
                                    # Nothing
                                }
                                $b++
                            }
                        }
                        catch
                        {
                            ReportError ("`Failed to retrieve VLAN group members for VLAN group: {0}.  Get-UcsFabricPooledVlan threw an exception." -f @($vlanGroup.Name))
                            $success = $false
                        }
                    } `
                    else # NOT ($null -ne $vlanGroup)
                    {
                        # Nothing, would have already reported an error.
                    }

                    $a++
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve exisint VLAN groups.  Get-UcsFabricNetGroup threw an exception."
                $success = $false
            }
        } `
        else # NOT ($null -ne $ucsLANCloud)
        {
            ReportError ("`tFailed to retrieve LAN cloud from {0}.  Get-UcsLanCloud returned `$null." -f @($ucs.Name))
            $success = $false
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve LAN cloud from {0}.  Get-UcsLanCloud threw an exception." -f @($ucs.Name))
        $success = $false
    }

    return $success
}

function DeleteDefaultMACPool
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

<#
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsOrg -ModifyPresent  -Name "root"
    $mo_1 = Get-UcsOrg -Level root | Get-UcsMacPool -Name "default" -LimitScope | Remove-UcsMacPool
    Complete-UcsTransaction
#>
    $success = $true

    ReportNotice "`tDeleting default MAC Pool"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $defaultMACPool = Get-UcsMacPool -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop
                if ($null -ne $defaultMACPool)
                {
                    try
                    {
                        $removedMACPool = $defaultMACPool | Remove-UcsMacPool -Force -Confirm:$false -ErrorAction Stop
                        if ($null -eq $removedMACPool)
                        {
                            ReportError "`tFailed to remove default MAC pool.  Remove-UcsMacPool returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $removedMACPool)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to remove default MAC pool.  Remove-UcsMacPool threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $defaultMACPool)
                {
                    ReportError "`tFailed to retrieve default MAC pool.  Get-UcsMacPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve default MAC pool.  Get-UcsMacPool threw an exception."
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}

function CreateMACPool
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [Object] $macPoolDefinition
    )

<#
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsMacPool -AssignmentOrder "sequential" -Name "klbMAC"
    $mo_1 = $mo | Add-UcsMacMemberBlock -From "00:25:B5:05:00:00" -To "00:25:B5:05:00:FF"
    Complete-UcsTransaction
#>
    $success = $true

    ReportNotice "`tCreating MAC address pool"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                [void] (Start-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                try
                {
                    $macPool = Add-UcsMacPool -Ucs $ucs -Org $rootOrg -AssignmentOrder "sequential" -Name $macPoolDefinition.Name -ErrorAction Stop
                    if ($null -ne $macPool)
                    {
                        try
                        {
                            $macBlock = Add-UcsMacMemberBlock -Ucs $ucs -MacPool $macPool -From $macPoolDefinition.From -To $macPoolDefinition.To -ErrorAction Stop
                            if ($null -eq $macBlock)
                            {
                                ReportError ("`tFailed to add member block [{0} - {1}] to MAC address pool {2}.  Add-UcsMacMemberBlock return `$null." -f @($macPoolDefinition.From, $macPoolDefinition.To, $macPoolDefinition.Name))
                                $success = $false
                            } `
                            else # NOT ($null -eq $macBlock)
                            {
                                try
                                {
                                    [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                }
                                catch
                                {
                                    ReportError ("`tFailed create MAC address pool {0}.  Complete-UcsTransaction threw an exception." -f @($macPoolDefinition.Name))
                                    $success = $false
                                }
                            }
                        }
                        catch
                        {
                            ReportError ("`tFailed to add member block [{0} - {1}] to MAC address pool {2}.  Add-UcsMacMemberBlock threw an exception." -f @($macPoolDefinition.From, $macPoolDefinition.To, $macPoolDefinition.Name))
                            $success = $false

                            try
                            {
                                [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                            }
                            catch
                            {
                                ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                                $success = $false
                            }
                        }
                    } `
                    else # NOT ($null -ne $macPool)
                    {
                        ReportError ("`tFailed to create MAC address pool {0}.  Add-UcsMacPool return `$null." -f @($macPoolDefinition.Name))
                        $success = $false

                        try
                        {
                            [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                        }
                        catch
                        {
                            ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                            $success = $false
                        }
                    }
                }
                catch
                {
                    ReportError ("`tFailed to create MAC address pool {0}.  Add-UcsMacPool threw an exception." -f @($macPoolDefinition.Name))
                    $success = $false

                    try
                    {
                        [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                    }
                    catch
                    {
                        ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                        $success = $false
                    }
                }
            }
            catch
            {
                ReportError ("`tFailed create MAC address pool {0}.  Start-UcsTransaction threw an exception." -f @($macPoolDefinition.Name))
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}

function CreateJumboFramesQoSPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $qosPolicyName
    )

<#
    # Create JUMBO Frames QoS Policy
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsQosPolicy -Name "klbJumbo"
    $mo_1 = $mo | Add-UcsVnicEgressPolicy -ModifyPresent -Burst 10240 -HostControl "none" -Name "" -Prio "best-effort" -Rate "line-rate"
    Complete-UcsTransaction
#>
    $success = $true

    ReportNotice "`tCreating JUMBOFRAMES QoS Policy."
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                [void] (Start-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                try
                {
                    $qosPolicy = Add-UcsQosPolicy -Ucs $ucs -Org $rootOrg -Name $qosPolicyName -ErrorAction Stop
                    if ($null -ne $qosPolicy)
                    {
                        try
                        {
                            $vnicEgressPolicy = Add-UcsVnicEgressPolicy -Ucs $ucs -QosPolicy $qosPolicy -Burst 10240 -HostControl "none" -Name "" -Prio "best-effort" -Rate "line-rate" -ErrorAction Stop
                            if ($null -ne $vnicEgressPolicy)
                            {
                                try
                                {
                                    [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                }
                                catch
                                {
                                    ReportError ("`tFailed to create QoS policy: {0}.  Complete-UcsTransaction threw an exception." -f @($qosPolicyName))
                                    $success = $false

                                    try
                                    {
                                        [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                    }
                                    catch
                                    {
                                        ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                                        $success = $false
                                    }
                                }
                            } `
                            else # NOT ($null -ne $mo)
                            {
                                ReportError ("`tFailed to set VNIC egress policy for QoS Policy: {0}.  Add-UcsVnicEgressPolicy returned `$null." -f @($qosPolicyName))
                                $success = $false

                                try
                                {
                                    [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                }
                                catch
                                {
                                    ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                                    $success = $false
                                }
                            }
                        }
                        catch
                        {
                            ReportError ("`tFailed to set VNIC egress policy for QoS Policy {0}.  Add-UcsVnicEgressPolicy threw an exception." -f @($qosPolicyName))
                            $success = $false
                        }
                    } `
                    else # NOT ($null -ne $qosPolicy)
                    {
                        ReportError ("`tFailed to create QoS policy: {0}.  Add-UcsQosPolicy returned `$null." -f @($qosPolicyName))
                        $success = $false

                        try
                        {
                            [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                        }
                        catch
                        {
                            ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                            $success = $false
                        }
                    }
                }
                catch
                {
                    ReportError ("`tFailed to create QoS policy: {0}.  Add-UcsQosPolicy threw an exception." -f @($qosPolicyName))
                    $success = $false

                    try
                    {
                        [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                    }
                    catch
                    {
                        ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                        $success = $false
                    }
                }
            }
            catch
            {
                ReportError ("`tFailed create QoS policy: {0}.  Start-UcsTransaction threw an exception." -f @($qosPolicyName))
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}


function CreatevNICTemplates
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [Object[]] $vNICTemplateDefinitions,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $macPoolName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [String] $networkControlPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNullOrEmpty()]
        [String] $jumboFramesQosPolicyName
    )

    $rootOrg = $null
    $ucsNetworkControlPolicy = $null
    $macPool = $null
    $jumboFramesPolicy = $null
    $ucsLANCloud = $null
    $existingUCSVLANGroups = $null
    $existingvNICTemplates = $null

    $success = $true   # Keep building vNIC templates until we have created them all, or hit an error.
    ReportNotice "Creating vNIC templates"

    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}

    if ($success)
    {
        $success, $ucsNetworkControlPolicy = InvokeUCSFunction -functionName "Get-UcsNetworkControlPolicy" -failureMsg ("Failed to retrieve network control policy: {0}." -f @($networkControlPolicyName)) -cmdParams @{Ucs=$ucs;Name=$networkControlPolicyName}
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $macPool = InvokeUCSFunction -functionName "Get-UcsMacPool" -failureMsg ("Failed to retrieve MAC pool: {0}." -f @($macPoolName)) -cmdParams @{Ucs=$ucs;Name=$macPoolName}
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $jumboFramesPolicy = InvokeUCSFunction -functionName "Get-UcsQosPolicy" -failureMsg ("Failed to retrieve jumbo frames QoS policy: {0}." -f @($jumboFramesQosPolicyName)) -cmdParams @{ Ucs = $ucs; Org = $rootOrg; Name = $jumboFramesQosPolicyName }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $ucsLANCloud = InvokeUCSFunction -functionName "Get-UcsLanCloud" -failureMsg "Failed to retrieve LAN cloud." -cmdParams @{ Ucs = $ucs }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $existingUCSVLANGroups = InvokeUCSFunction -functionName "Get-UcsFabricNetGroup" -failureMsg "Failed to retrieve VLAN Groups." -cmdParams @{ Ucs = $ucs; LanCloud = $ucsLANCloud }

        if ($success)
        {
            if($existingUCSVLANGroups -isnot [Array])
            {
                if ($null -ne $existingUCSVLANGroups)
                {
                    $existingUCSVLANGroups = @($existingUCSVLANGroups)
                } `
                else # NOT ($null -ne $existingUCSVLANGroups)
                {
                    $existingUCSVLANGroups = @()
                }
            }
            else # NOT ($existingUCSVLANGroups -isnot [Array])
            {
                # Nothing
            }

            # Test to make sure all the VLAN Groups used in the vNIC templates have been defined.
            $testedVLANGroupNames = @()
            $a = 0
            while(($existingUCSVLANGroups.Length -gt 0) -and ($a -lt $vNICTemplateDefinitions.Length))
            {
                $b = 0
                while($b -lt $vNICTemplateDefinitions[$a].Primary.VLANGroups.Length)
                {
                    if (-not ($testedVLANGroupName -contains $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b]))
                    {
                        $testedVLANGroupNames += $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b]
                        if ($null -eq ($existingUCSVLANGroups | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b] }))
                        {
                            ReportError ("`tVLAN Group {0} does not exist on {1}." -f @($vNICTemplateDefinitions[$a].Primary.VLANGroups[$b], $ucs.Name))
                            $success = $false
                        }
                        else # NOT ($null -eq ($existingUCSVLANGroups | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b] }))
                        {
                            # Nothing
                        }
                    } `
                    else # NOT (-not ($testedVLANGroupName -contains $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b]))
                    {
                        # Nothing.
                    }

                    $b++
                }
                $a++
            }
        } `
        else # NOT ($success)
        {
            # Nothing.
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $existingvNICTemplates = InvokeUCSFunction -functionName "Get-UcsVnicTemplate" -failureMsg "Failed to retrieve vNIC Templates." -cmdParams @{ Ucs = $ucs} -noErrorOnNull

        # For future code, ensure $existingvNICTemplates is an array.
        if ($success -and (-not ($existingvNICTemplates -is [Array])))
        {
            if ($null -eq $existingvNICTemplates)
            {
                $existingvNICTemplates = @()
            } `
            else # NOT ($null -eq $existingvNICTemplates)
            {
                $existingvNICTemplates = @($existingvNICTemplates)
            }
        } `
        else # NOT ($success -and (-not ($existingvNICTemplates -is [Array])))
        {
            # Nothing.
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    $success, $null = InvokeUCSFunction -functionName "Start-UcsTransaction" -failureMsg "Failed to start UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
    if ($success)
    {
        $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    $a = 0
    while($success -and ($a -lt $vNICTemplateDefinitions.Length))
    {
        ReportNotice ("`tCreating primary vNIC Template: {0}" -f @($vNICTemplateDefinitions[$a].Primary.Name))
        # Make sure there isn't already a vNIC template named: $vNICTemplateDefinitions[$a].Primary.Name
        if ($null -eq ($existingvNICTemplates | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Primary.Name }))
        {
            # Make sure there isn't already a vNIC template named: $vNICTemplateDefinitions[$a].Secondary.Name
            if ($null -eq ($existingvNICTemplates | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Secondary.Name }))
            {
                $primaryvNICTemplateParams = @{
                    Ucs = $ucs
                    Org = $rootOrg
                    Descr = $vNICTemplateDefinitions[$a].Primary.Description
                    IdentPoolName = $macPool.Name
                    Name = $vNICTemplateDefinitions[$a].Primary.Name
                    Mtu = $vNICTemplateDefinitions[$a].Primary.MTU
                    NwCtrlPolicyName = $ucsNetworkControlPolicy.Name
                    RedundancyPairType = "primary"
                    SwitchId = $vNICTemplateDefinitions[$a].Primary.Switch
                    TemplType = "updating-template"
                }

                if($vNICTemplateDefinitions[$a].Primary.MTU -eq 9000)
                {
                    $primaryvNICTemplateParams.Add("QosPolicyName", $jumboFramesPolicy.Name)
                } `
                else # NOT ($vNICTemplateDefinitions[$a].Primary.MTU -eq 9000)
                {
                    # Nothing
                }

                $success, $primaryvNICTemplate = InvokeUCSFunction -functionName "Add-UcsVnicTemplate" -failureMsg ("Failed to create primary vNIC template {0}." -f @($vNICTemplateDefinitions[$a].Primary.Name)) -cmdParams $primaryvNICTemplateParams
                if ($success)
                {
                    $b = 0
                    while($success -and ($b -lt $vNICTemplateDefinitions[$a].Primary.VLANGroups.Length))
                    {
                        ReportNotice ("`t`tAdding VLAN Group: {0}..." -f @($vNICTemplateDefinitions[$a].Primary.VLANGroups[$b]))
                        $success, $vlanGroup = InvokeUCSFunction -functionName "Add-UcsFabricNetGroupRef" -failureMsg ("Failed to add VLAN Group {0} to {1}." -f @($vNICTemplateDefinitions[$a].Primary.VLANGroups[$b], $vNICTemplateDefinitions[$a].Primary.Name)) -cmdParams @{ Ucs = $ucs; VnicTemplate = $primaryvNICTemplate; Name = $vNICTemplateDefinitions[$a].Primary.VLANGroups[$b]; ModifyPresent = $true }

                        $b++
                    }

                    if ($null -ne $vNICTemplateDefinitions[$a].Secondary)
                    {
                        ReportNotice ("`tCreating secondary vNIC Template: {0}" -f @($vNICTemplateDefinitions[$a].Secondary.Name))
                        $secondaryvNICTemplateParams = @{
                            Ucs = $ucs
                            Org = $rootOrg
                            Descr = $vNICTemplateDefinitions[$a].Secondary.Description
                            IdentPoolName = $macPool.Name
                            Name = $vNICTemplateDefinitions[$a].Secondary.Name
                            NwCtrlPolicyName = $ucsNetworkControlPolicy.Name
                            RedundancyPairType = "secondary"
                            PeerRedundancyTemplName = $primaryvNICTemplate.Name
                            SwitchId = $vNICTemplateDefinitions[$a].Secondary.Switch
                        }

                        $success, $secondaryvNICTemplate = InvokeUCSFunction -functionName "Add-UcsVnicTemplate" -failureMsg ("Failed to create secondary vNIC template {0}." -f @($vNICTemplateDefinitions[$a].Secondary.Name)) -cmdParams $secondaryvNICTemplateParams
                    } `
                    else # NOT ($null -ne $vNICTemplateDefinitions[$a].Secondary)
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing.
                }
            } `
            else # NOT ($null -eq ($existingvNICTemplates | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Secondary.Name }))
            {
                ReportError ("vNIC Template {0} already exists on {1}." -f @($vNICTemplateDefinitions[$a].Secondary.Name, $ucs.Name))
                $success = $false
            }
        } `
        else # NOT ($null -eq ($existingvNICTemplates | Where-Object { $_.Name -eq $vNICTemplateDefinitions[$a].Primary.Name }))
        {
            ReportError ("vNIC Template {0} already exists on {1}." -f @($vNICTemplateDefinitions[$a].Primary.Name, $ucs.Name))
            $success = $false
        }

        $a++
    }

    if ($success)
    {
        $success, $null = InvokeUCSFunction -functionName "Complete-UcsTransaction" -failureMsg "Failed to commit UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
    } `
    else # NOT ($success)
    {
        ReportError ("Rolling back UCS transaction to create vNIC templates.")
        $success, $null = InvokeUCSFunction -functionName "Undo-UcsTransaction" -failureMsg "Failed to rollback UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull

        # No matter the success of rolling back the transaction, make sure $success is $false
        $success = $false
    }

    return $success
}

function CreateIPBlock
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $ipPoolName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $fromAddress,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [String] $toAddress,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNullOrEmpty()]
        [String] $subnetMask,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [ValidateNotNullOrEmpty()]
        [String] $primaryDNS,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=6)]
        [ValidateNotNullOrEmpty()]
        [String] $secondaryDNS,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=7)]
        [ValidateNotNullOrEmpty()]
        [String] $defaultGateway
    )

    $success = $false
    $tempIP = [System.Net.IPAddress]::new(0)

    if ([System.Net.IPAddress]::TryParse($fromAddress, [ref] $tempIP))
    {
        $fromAddressUInt32 = INET_ATON -ipStr $fromAddress
        if ($fromAddressUInt32 -ne 0)
        {
            if ([System.Net.IPAddress]::TryParse($toAddress, [ref] $tempIP))
            {
                $toAddressUInt32 = INET_ATON -ipStr $toAddress
                if ($toAddressUInt32 -ne 0)
                {
                    if ($toAddressUInt32 -lt $fromAddressUInt32)
                    {
                        # Swap the to and from and reconvert to UInt32s
                        $tmpIP = $fromAddress
                        $fromAddress = $toAddress
                        $toAddress = $tmpIP
                        $fromAddressUInt32 = INET_ATON -ipStr $fromAddress
                        $toAddressUInt32 = INET_ATON -ipStr $toAddress
                    } `
                    else # NOT ($toAddressUInt32 -lt $fromAddressUInt32)
                    {
                        # Nothing.
                    }

                    if ([System.Net.IPAddress]::TryParse($defaultGateway, [ref] $tempIP))
                    {
                        $defaultGatewayUInt32 = INET_ATON -ipStr $defaultGateway
                        if ($defaultGatewayUInt32 -ne 0)
                        {
                            if (($defaultGatewayUInt32 -lt $fromAddressUInt32) -or ($defaultGatewayUInt32 -gt $toAddressUInt32))
                            {
                                if ([System.Net.IPAddress]::TryParse($primaryDNS, [ref] $tempIP))
                                {
                                    $primaryDNSUInt32 = INET_ATON -ipStr $primaryDNS
                                    if ($primaryDNSUInt32 -ne 0)
                                    {
                                        if (($primaryDNSUInt32 -lt $fromAddressUInt32) -or ($primaryDNSUInt32 -gt $toAddressUInt32))
                                        {
                                            if ([System.Net.IPAddress]::TryParse($secondaryDNS, [ref] $tempIP))
                                            {
                                                $secondaryDNSUInt32 = INET_ATON -ipStr $secondaryDNS
                                                if ($secondaryDNSUInt32 -ne 0)
                                                {
                                                    if ([System.Net.IPAddress]::TryParse($subnetMask, [ref] $tempIP))
                                                    {
                                                        $subnetMaskUInt32 = INET_ATON -ipStr $subnetMask
                                                        if ($subnetMaskUInt32 -ne -1)
                                                        {
                                                            try
                                                            {
                                                                $bitMask = [Convert]::ToString($subnetMaskUInt32, 2)
                                                                if (($bitMask.Length -eq 32) -and ($bitMask -match "^1+0+$"))
                                                                {
                                                                    $fromNetworkUInt32 = $fromAddressUInt32 -band $subnetMaskUInt32
                                                                    $toNetworkUInt32 = $toAddressUInt32 -band $subnetMaskUInt32
                                                                    $dgNetworkUInt32 = $defaultGatewayUInt32 -band $subnetMaskUInt32

                                                                    # Are $fromAddress and $toAddress in the same subnet?
                                                                    if ($fromNetworkUInt32 -eq $toNetworkUInt32)
                                                                    {
                                                                        # Are $fromAddress (and $toAddress) in the same subnet as $defaultGateway?
                                                                        if ($fromNetworkUInt32 -eq $dgNetworkUInt32)
                                                                        {
                                                                            if (($secondaryDNSUInt32 -lt $fromAddressUInt32) -or ($secondaryDNSUInt32 -gt $toAddressUInt32))
                                                                            {
                                                                                if ($primaryDNSUInt32 -ne $secondaryDNSUInt32)
                                                                                {
                                                                                    if ($primaryDNSUInt32 -ne $defaultGatewayUInt32)
                                                                                    {
                                                                                        if ($secondaryDNSUInt32 -ne $defaultGatewayUInt32)
                                                                                        {
                                                                                            $success, $orgRoot = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve UCS root organization." -cmdParams @{ Ucs = $ucs; Level = "root" }
                                                                                            if ($success)
                                                                                            {
                                                                                                $success, $ipPool = InvokeUCSFunction -functionName "Get-UcsIpPool" -failureMsg ("Failed to retrieve IP Pool {0}." -f @($ipPoolName)) -cmdParams @{ Ucs = $ucs; Org = $orgRoot; Name = $ipPoolName }
                                                                                                if ($success)
                                                                                                {
                                                                                                    # On a new install, there likely isn't an IP pool block, so don't error on null.
                                                                                                    $success, $ipPoolBlocks = InvokeUCSFunction -functionName "Get-UCSIPPoolBlock" -failureMsg ("Failed to retrieve IP pool address blocks for {0}." -f @($ipPool.Name)) -cmdParams @{ Ucs = $ucs; IpPool = $ipPool } -noErrorOnNull
                                                                                                    if ($success)
                                                                                                    {
                                                                                                        # Make sure $ipPoolBlocks is an [Array]
                                                                                                        if ($null -eq $ipPoolBlocks)
                                                                                                        {
                                                                                                            $ipPoolBlocks = @()
                                                                                                        } `
                                                                                                        else # NOT ($null -eq $ipPoolBlocks)
                                                                                                        {
                                                                                                            if (-not ($ipPoolBlocks -is [Array]))
                                                                                                            {
                                                                                                                $ipPoolBlocks = @($ipPoolBlocks)
                                                                                                            } `
                                                                                                            else # NOT (-not ($ipPoolBlocks -is [Array]))
                                                                                                            {
                                                                                                                # Nothing.
                                                                                                            }
                                                                                                        }

                                                                                                        $overLapped = $false
                                                                                                        $conversionFailed = $false

                                                                                                        $a = 0
                                                                                                        while((-not $conversionFailed) -and ($a -lt $ipPoolBlocks.Length))
                                                                                                        {
                                                                                                            $poolFromUInt32 = INET_ATON -ipStr $ipPoolBlocks[$a].From
                                                                                                            if ($poolFromUInt32 -ne 0)
                                                                                                            {
                                                                                                                $poolToUInt32 = INET_ATON -ipStr $ipPoolBlocks[$a].To
                                                                                                                if ($poolToUInt32 -ne 0)
                                                                                                                {
                                                                                                                    #   (          existingFrom  [  new from ]  existingTo      (new to is irrelevant)       ) -or (      existingFrom  [  new to ]  existingTo    (new from is irrelevant)         ) -or (                 new from [ existingFrom - existingTo ] new to                     )
                                                                                                                    if ((($fromAddressUInt32 -ge $poolFromUInt32) -and ($fromAddressUInt32 -le $poolToUInt32)) -or (($toAddressUInt32 -ge $poolFromUInt32) -and ($toAddressUInt32 -le $poolToUInt32)) -or (($fromAddressUInt32 -le $poolFromUInt32) -and ($toAddressUInt32 -ge $poolToUInt32)))
                                                                                                                    {
                                                                                                                        $overLapped = $true
                                                                                                                        ReportError ("IP pool {0} address block {1} - {2} overlaps {3} - {4}." -f @($ipPool.Name, $ipPoolBlocks[$a].From, $ipPoolBlocks[$a].To, $fromAddress, $toAddress))
                                                                                                                    } `
                                                                                                                    else # NOT ((($fromAddressUInt32 -ge $poolFromUInt32) -and ($fromAddressUInt32 -le $poolToUInt32)) -or (($toAddressUInt32 -ge $poolFromUInt32) -and ($toAddressUInt32 -le $poolToUInt32)) -or (($fromAddressUInt32 -le $poolFromUInt32) -and ($toAddressUInt32 -ge $poolToUInt32)))
                                                                                                                    {
                                                                                                                        # Nothing.
                                                                                                                    }
                                                                                                                } `
                                                                                                                else # NOT ($poolToUInt32 -ne 0)
                                                                                                                {
                                                                                                                    $conversionFailed = $true
                                                                                                                    ReportError ("Failed to convert IP pool {0} address block to address {1} into a UInt32." -f @($ipPool.Name, $ipPoolBlocks[$a].To))
                                                                                                                }
                                                                                                            } `
                                                                                                            else # NOT ($poolFromUInt32 -ne 0)
                                                                                                            {
                                                                                                                $conversionFailed = $true
                                                                                                                ReportError ("Failed to convert IP pool {0} address block from address {1} into a UInt32." -f @($ipPool.Name, $ipPoolBlocks[$a].From))
                                                                                                            }

                                                                                                            $a++
                                                                                                        }

                                                                                                        if ((-not $conversionFailed) -and (-not $overLapped))
                                                                                                        {
                                                                                                            try
                                                                                                            {
                                                                                                                $addIpPoolBlockParams = @{
                                                                                                                    Ucs = $ucs
                                                                                                                    IpPool = $ipPool
                                                                                                                    DefGw = $defaultGateway
                                                                                                                    Subnet = $subnetMask
                                                                                                                    From = $fromAddress
                                                                                                                    To = $toAddress
                                                                                                                    PrimDns = $primaryDNS
                                                                                                                    SecDns = $secondaryDNS
                                                                                                                }
                                                                                                                $success, $ipPoolBlock = InvokeUCSFunction "Add-UcsIpPoolBlock" -failureMsg ("Failed to create address block {0} - {1} in IP pool: {2}." -f @($fromAddress, $toAddress, $ipPool.Name)) -cmdParams $addIpPoolBlockParams
                                                                                                                # [void] (Add-UcsIpPoolBlock -Ucs $ucs -IpPool $ipPool -DefGw $defaultGateway -From $fromAddress -PrimDns $primaryDNS -SecDns $secondaryDNS -To $toAddress -Subnet $subnetMask -ErrorAction Stop)
                                                                                                                # $success = $true
                                                                                                                # Get-UcsOrg -Level root | Get-UcsIpPool -Name "ext-mgmt" -LimitScope | Add-UcsIpPoolBlock -DefGw "192.168.1.1" -From "192.168.1.50" -PrimDns "192.168.1.20" -SecDns "192.168.1.30" -To "192.168.1.74"
                                                                                                            }
                                                                                                            catch
                                                                                                            {
                                                                                                                ReportError ("Failed to create address block {0} - {1} in IP pool: {2}." -f @($fromAddress, $toAddress, $ipPool.Name))
                                                                                                            }

                                                                                                        } `
                                                                                                        else # NOT ((-not $conversionFailed) -and (-not $overLapped))
                                                                                                        {
                                                                                                            # Nothing, error reported above.
                                                                                                        }
                                                                                                    } `
                                                                                                    else # NOT ($success)
                                                                                                    {
                                                                                                        # Nothing.
                                                                                                    }
                                                                                                } `
                                                                                                else # NOT ($success)
                                                                                                {
                                                                                                    # Nothing.
                                                                                                }
                                                                                            } `
                                                                                            else # NOT ($success)
                                                                                            {
                                                                                                # Nothing.
                                                                                            }
                                                                                        } `
                                                                                        else # NOT ($secondaryDNSUInt32 -ne $defaultGatewayUInt32)
                                                                                        {
                                                                                            ReportError ("Secondary DNS ({0}) and default gateway ({1}) addresses match." -f @($secondaryDNS, $defaultGateway))
                                                                                        }
                                                                                    } `
                                                                                    else # NOT ($primaryDNSUInt32 -ne $defaultGatewayUInt32)
                                                                                    {
                                                                                        ReportError ("Primary DNS ({0}) and default gateway ({1}) addresses match." -f @($primaryDNS, $defaultGateway))
                                                                                    }
                                                                                } `
                                                                                else # NOT ($primaryDNSUInt32 -ne $secondaryDNSUInt32)
                                                                                {
                                                                                    ReportError ("Primary ({0}) and secondary ({1}) DNS addresses match." -f @($primaryDNS, $secondaryDNS))
                                                                                }
                                                                            } `
                                                                            else # NOT (($secondaryDNSUInt32 -lt $fromAddressUInt32) -or ($secondaryDNSUInt32 -gt $toAddressUInt32)))
                                                                            {
                                                                                ReportError ("Secondary DNS {0} cannot be contained in the range ({1} - {2})." -f @($secondaryDNS, $fromAddress, $toAddress))
                                                                            }
                                                                        } `
                                                                        else # NOT ($fromNetworkUInt32 -eq $dgNetworkUInt32)
                                                                        {
                                                                            ReportError ("Default gateway address {0} is not in the same subnet as from/to addresses {1} - {2}." -f @($defaultGateway, $fromAddress, $toAddress))
                                                                        }
                                                                    } `
                                                                    else # NOT ($fromNetworkUInt32 -eq $toNetworkUInt32)
                                                                    {
                                                                        ReportError ("From address {0} is not in the same subnet as to address {1}." -f @($fromAddress, $toAddress))
                                                                    }
                                                                } `
                                                                else # NOT (($bitMask.Length -eq 32) -and ($bitMask -match "^1+0+$"))
                                                                {
                                                                    ReportError ("Invalid subnet mask: {0}" -f @($subnetMask))
                                                                }
                                                            }
                                                            catch
                                                            {
                                                                ReportError ("Failed to validate subnet mask ({0}) via binary string." -f @($subnetMask))
                                                            }
                                                        } `
                                                        else # NOT ($subnetMaskUInt32 -ne -1)
                                                        {
                                                            ReportError ("Failed to convert subnet mask {0} into an int32." -f @($subnetMask))
                                                        }
                                                    } `
                                                    else # NOT ([System.Net.IPAddress]::TryParse($subnetMask, [ref] $tempIP))
                                                    {
                                                        ReportError ("Subnet mask {0} is invalid." -f @($subnetMask))
                                                    }
                                                } `
                                                else # NOT ($secondaryDNSUInt32 -ne 0)
                                                {
                                                    ReportError ("Failed to convert secondary DNS address {0} into an UInt32." -f @($secondaryDNS))
                                                }
                                            } `
                                            else # NOT ([System.Net.IPAddress]::TryParse($secondaryDNS, [ref] $tempIP))
                                            {
                                                ReportError ("Secondary DNS address {0} is invalid." -f @($secondaryDNS))
                                            }
                                        } `
                                        else # NOT (($primaryDNSUInt32 -lt $fromAddressUInt32) -or ($primaryDNSUInt32 -gt $toAddressUInt32)))
                                        {
                                            ReportError ("Primary DNS {0} cannot be contained in the range ({1} - {2})." -f @($primaryDNS, $fromAddress, $toAddress))
                                        }
                                    } `
                                    else # NOT ($primaryDNSUInt32 -ne 0)
                                    {
                                        ReportError ("Failed to convert primary DNS address {0} into an UInt32." -f @($primaryDNS))
                                    }
                                } `
                                else # NOT ([System.Net.IPAddress]::TryParse($primaryDNS, [ref] $tempIP))
                                {
                                    ReportError ("Primary DNS address {0} is invalid." -f @($primaryDNS))
                                }
                            } `
                            else # NOT (($defaultGatewayUInt32 -lt $fromAddressUInt32) -or ($defaultGatewayUInt32 -gt $toAddressUInt32))
                            {
                                ReportError ("Default gateway {0} cannot be contained in the range ({1} - {2})." -f @($defaultGateway, $fromAddress, $toAddress))
                            }
                        } `
                        else # NOT ($defaultGatewayUInt32 -ne 0)
                        {
                            ReportError ("Failed to convert default gateway address {0} into an UInt32." -f @($defaultGateway))
                        }
                    } `
                    else # NOT ([System.Net.IPAddress]::TryParse($defaultGateway, [ref] $tempIP))
                    {
                        ReportError ("Default gateway address {0} is invalid." -f @($defaultGateway))
                    }
                } `
                else # NOT ($toAddressUInt32 -ne 0)
                {
                    ReportError ("Failed to convert to address {0} into an UInt32." -f @($toAddress))
                }
            } `
            else # NOT ([System.Net.IPAddress]::TryParse($toAddress, [ref] $tempIP))
            {
                ReportError ("To address {0} is invalid." -f @($toAddress))
            }
        } `
        else # NOT ($fromAddressUInt32 -ne 0)
        {
            ReportError ("Failed to convert from address {0} into an UInt32." -f @($fromAddress))
        }
    } `
    else # NOT ([System.Net.IPAddress]::TryParse($fromAddress, [ref] $tempIP))
    {
        ReportError ("From address {0} is invalid." -f @($fromAddress))
    }

    return $success
}

function CreateDiskGroupConfigurationPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $policyName
    )

    <#
        Start-UcsTransaction
        $mo = Get-UcsOrg -Level root  | Add-UcsLogicalStorageDiskGroupConfigPolicy -Name "dspKLB" -RaidLevel "mirror"
        $mo_1 = $mo | Add-UcsLogicalStorageDiskGroupQualifier -ModifyPresent -DriveType "unspecified" -MinDriveSize "unspecified" -NumDedHotSpares "unspecified" -NumDrives "2" -NumGlobHotSpares "unspecified" -UseJbodDisks "yes" -UseRemainingDisks "no"
        $mo_2 = $mo | Set-UcsLogicalStorageVirtualDriveDef -AccessPolicy "platform-default" -DriveCache "platform-default" -IoPolicy "platform-default" -ReadPolicy "platform-default" -Security "no" -StripSize "platform-default" -WriteCachePolicy "platform-default"
        Complete-UcsTransaction
    #>

    $success = $false
    $transactionStarted = $false

    ReportNotice ("Creating disk group configuration policy {0} on {1}." -f @($policyName, $ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $existingPolicy = Get-UcsLogicalStorageDiskGroupConfigPolicy -Ucs $ucs -Org $rootOrg -Name $policyName -ErrorAction Stop

            if ($null -eq $existingPolicy)
            {
                try
                {
                    [void] (Start-UcsTransaction -Ucs $ucs)
                    $transactionStarted = $true

                    try
                    {
                        $newPolicy = Add-UcsLogicalStorageDiskGroupConfigPolicy -Ucs $ucs -Org $rootOrg -Name $policyName -RaidLevel "mirror" -ErrorAction Stop

                        if ($null -ne $newPolicy)
                        {

                            try
                            {
                                $diskGroupQualifierParams = @{
                                    Ucs = $ucs
                                    LogicalStorageDiskGroupConfigPolicy = $newPolicy
                                    ModifyPresent = $true
                                    DriveType = "unspecified"
                                    MinDriveSize = "unspecified"
                                    NumDedHotSpares = "unspecified"
                                    NumDrives = "2"
                                    NumGlobHotSpares = "unspecified"
                                    UseJbodDisks = "yes"
                                    UseRemainingDisks = "no"
                                    ErrorAction = "Stop"
                                }

                                $diskGroupQualifier = Add-UcsLogicalStorageDiskGroupQualifier @diskGroupQualifierParams

                                if ($null -ne $diskGroupQualifier)
                                {
                                    try
                                    {
                                        $virtDriveDefParams = @{
                                            Ucs = $ucs
                                            LogicalStorageDiskGroupConfigPolicy = $newPolicy
                                            AccessPolicy = "platform-default"
                                            DriveCache = "platform-default"
                                            IoPolicy = "platform-default"
                                            ReadPolicy = "platform-default"
                                            Security = "no"
                                            StripSize = "platform-default"
                                            WriteCachePolicy = "platform-default"
                                            Force = $true
                                            ErrorAction = "Stop"
                                        }
                                        [void] (Set-UcsLogicalStorageVirtualDriveDef @virtDriveDefParams -Confirm:$false)
                                        $success = $true
                                    }
                                    catch
                                    {
                                        ReportError "`tFailed to set virtual drive definition."
                                    }
                                } `
                                else # NOT ($null -ne $diskGroupQualifier)
                                {
                                    # Nothing.
                                }
                            }
                            catch
                            {
                                ReportError "`tFailed to add disk group qualifier to new disk group configuration policy."
                            }
                        } `
                        else # NOT ($null -ne $newPolicy)
                        {
                            ReportError "`tFailed to create new disk group configuration policy."
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed [exception] to create new disk group configuration policy."
                    }
                }
                catch
                {
                    ReportError "`tFailed to start UCS transaction."
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                ReportError "`tDisk group configuration policy already exists."
            }
        }
        catch
        {
            ReportError "`tFailed to check for existing disk group configuration policy."
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    if ($transactionStarted)
    {
        if ($success)
        {
            try
            {
                [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
            }
            catch
            {
                ReportError "`tFailed to complete UCS transaction to create new disk group configuration policy."
            }

        } `
        else # NOT ($success)
        {
            try
            {
                [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                ReportWarning "`tRolled back transaction to create new disk group configuration policy."
            }
            catch
            {
                ReportError "`tFailed to roll-back UCS transaction to create new disk group configuration policy."
            }
        }
    } `
    else # NOT ($transactionStarted)
    {
        # Nothing.
    }

    return $success
}

function CreateStorageProfile
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $profileName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $dgcPolicyName
    )
    # Create Storage Profile
    <#
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsLogicalStorageProfile -Name "klbstorprofile"
    $mo_1 = $mo | Add-UcsLogicalStorageDasScsiLun -ExpandToAvail "yes" -LocalDiskPolicyName "dspKLB" -Name "klbluntest" -Size "1"
    Complete-UcsTransaction
    #>

    $success = $false

    ReportNotice ("Creating storage profile {0} on {1}." -f @($profileName, $ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            # Make sure the logical storage disk group configuration policy exists.
            $diskGroupConfigPolicy = Get-UcsLogicalStorageDiskGroupConfigPolicy -Ucs $ucs -Org $rootOrg -Name $dgcPolicyName -ErrorAction Stop

            if ($null -ne $diskGroupConfigPolicy)
            {
                try
                {
                    # Make sure there isn't already a logical storage profile with name $profileName
                    $existingProfile = Get-UcsLogicalStorageProfile -Ucs $ucs -Org $rootOrg -Name $profileName -ErrorAction Stop

                    if ($null -eq $existingProfile)
                    {
                        try
                        {
                            $newProfile = Add-UcsLogicalStorageProfile -Ucs $ucs -Org $rootOrg -Name $profileName -ErrorAction Stop

                            if ($null -ne $newProfile)
                            {
                                try
                                {
                                    $localLUN = Add-UcsLogicalStorageDasScsiLun -Ucs $ucs -LogicalStorageProfile $newProfile -ExpandToAvail "yes" -LocalDiskPolicyName $diskGroupConfigPolicy.Name -Name $profileName -Size "1"

                                    if ($null -ne $localLUN)
                                    {
                                        $success = $true
                                    } `
                                    else # NOT ($null -ne $localLUN)
                                    {
                                        ReportError "`tFailed to create local lun.  Add-UcsLogicalStorageDasScsiLun returned `$null."
                                    }
                                }
                                catch
                                {
                                    ReportError "`tFailed to create local lun.  Add-UcsLogicalStorageDasScsiLun threw an exception."
                                }
                            } `
                            else # NOT ($null -ne $newPolicy)
                            {
                                ReportError "`tFailed to create new maintenance policy.  (Add-UcsMaintenancePolicy returned null)"
                            }
                        }
                        catch
                        {
                            ReportError "`tFailed to create new maintenance policy."
                        }
                    } `
                    else # NOT ($null -eq $existingProfile)
                    {
                        ReportError "`tStorage profile already exists."
                    }
                }
                catch
                {
                    ReportError "`tFailed to check for existing maintenance policy."
                }
            } `
            else # NOT ($null -ne $diskGroupConfigPolicy)
            {
                ReportError ("`tLogical storage disk group configuation policy: {0} does not exist on {1}." -f @($dgcPolicyName, $ucs.Name))
            }
        }
        catch
        {
            ReportError ("`tFailed to retrieve logical storage disk group configuation policy: {0} from {1}." -f @($dgcPolicyName, $ucs.Name))
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    return $success
}

function UpdateDefaultMaintenancePolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    <#
        Get-UcsOrg -Level root  | Add-UcsMaintenancePolicy -ModifyPresent  -Name "default" -TriggerConfig "on-next-boot" -UptimeDisr "user-ack"
    #>

    $success = $false
    $transactionStarted = $false

    ReportNotice ("Updating default maintenance policy {0}." -f @($ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $defPolicy = Get-UcsMaintenancePolicy -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop

            if ($null -ne $defPolicy)
            {
                try
                {
                    [void] (Start-UcsTransaction -Ucs $ucs)
                    $transactionStarted = $true

                    try
                    {
                        [void] (Add-UcsMaintenancePolicy -Ucs $ucs -ModifyPresent -Name "default" -TriggerConfig "on-next-boot" -UptimeDisr "user-ack" -ErrorAction Stop)
                        $success = $true
                    }
                    catch
                    {
                        ReportError "`tFailed update default maintenance policy."
                    }
                }
                catch
                {
                    ReportError "`tFailed to start UCS transaction."
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                ReportWarning "`tDefault maintenance policy does not exist."
            }
        }
        catch
        {
            ReportError "`tFailed to retrieve default maintenance policy."
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    if ($transactionStarted)
    {
        if ($success)
        {
            try
            {
                [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
            }
            catch
            {
                ReportError "`tFailed to complete UCS transaction to update default maintenance policy."
            }

        } `
        else # NOT ($success)
        {
            try
            {
                [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                ReportWarning "`tRolled back transaction to update default maintenance policy."
            }
            catch
            {
                ReportError "`tFailed to roll-back UCS transaction to update default maintenance policy."
            }
        }
    } `
    else # NOT ($transactionStarted)
    {
        # Nothing.
    }

    return $success
}

function CreateMaintenancePolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $policyName
    )

    <#
        Get-UcsOrg -Level root  | Add-UcsMaintenancePolicy -Name "USERACK" -TriggerConfig "on-next-boot" -UptimeDisr "user-ack"
    #>

    $success = $false

    ReportNotice ("Creating maintenance policy {0} on {1}." -f @($policyName, $ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $existingPolicy = Get-UcsMaintenancePolicy -Ucs $ucs -Org $rootOrg -Name $policyName -ErrorAction Stop

            if ($null -eq $existingPolicy)
            {
                try
                {
                    $newPolicy = Add-UcsMaintenancePolicy -Ucs $ucs -Org $rootOrg -Name $policyName -TriggerConfig "on-next-boot" -UptimeDisr "user-ack" -ErrorAction Stop

                    if ($null -ne $newPolicy)
                    {
                        $success = $true
                    } `
                    else # NOT ($null -ne $newPolicy)
                    {
                        ReportError "`tFailed to create new maintenance policy.  (Add-UcsMaintenancePolicy returned null)"
                    }
                }
                catch
                {
                    ReportError "`tFailed to create new maintenance policy."
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                ReportError "`tMaintenance policy already exists."
            }
        }
        catch
        {
            ReportError "`tFailed to check for existing maintenance policy."
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    return $success
}

function CreateBIOSPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object] $biosPolicy
    )

    ReportNotice ("Creating BIOS policy: {0} on {1}." -f @($biosPolicy.Name, $ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $existingPolicy = Get-UcsBiosPolicy -Ucs $ucs -Org $rootOrg -Name $biosPolicy.Name -ErrorAction Stop

            if ($null -eq $existingPolicy)
            {
                try
                {
                    # Create the base Policy -  This must be complete before Get-UcsBiosTokenFeatureGroup will retrieve BIOS token feature groups.
                    $newBIOSPolicy = Add-UcsBiosPolicy -Ucs $ucs -Org $rootOrg -Name $biosPolicy.Name -ErrorAction Stop

                    if ($null -ne $newBIOSPolicy)
                    {
                        try  # All encompassing try-catch.  Either all the settings get applied to the new policy, or we roll-back all the setting changes.
                        {
                            Start-UcsTransaction -Ucs $ucs -ErrorAction Stop
                            $transactionStarted = $true

                            # Apply all the settings.
                            $a = 0
                            while($a -lt $biosPolicy.Settings.Length)
                            {
                                Write-Host ("`tSetting {0}:{1}..." -f @($biosPolicy.Settings[$a].Name, $biosPolicy.Settings[$a].TargetTokenName))
                                $biosTokenFeatureGroup = Get-UcsBiosTokenFeatureGroup -Ucs $ucs -BiosPolicy $newBIOSPolicy -Name $biosPolicy.Settings[$a].Name -ErrorAction Stop
                                if ($null -ne $biosTokenFeatureGroup)
                                {
                                    $biosTokenParam = Get-UcsBiosTokenParam -Ucs $ucs -BiosTokenFeatureGroup $biosTokenFeatureGroup -TargetTokenName $biosPolicy.Settings[$a].TargetTokenName -ErrorAction Stop

                                    if ($null -ne $biosTokenParam)
                                    {
                                        $newManagedObject = Add-UcsManagedObject -Parent $biosTokenParam -ModifyPresent -ClassId "BiosTokenSettings" -PropertyMap @{SettingsMoRn=$biosPolicy.Settings[$a].PropertyMap.SettingsMoRn; IsAssigned=$biosPolicy.Settings[$a].PropertyMap.IsAssigned; } -ErrorAction Stop
                                        if ($null -ne $newManagedObject)
                                        {
                                            ReportSuccess ("`t`tSettingsMoRn: {0}, IsAssigned: {1}" -f @($biosPolicy.Settings[$a].PropertyMap.SettingsMoRn, $biosPolicy.Settings[$a].PropertyMap.IsAssigned))
                                            # Nothing, the setting was successfully set.
                                        } `
                                        else # NOT ($null -ne $newManagedObject)
                                        {
                                            ReportError ("`t`tAdd-UcsManagedObject failed to add setting: {0} to new BIOS policy: {1}." -f @($biosPolicy.Settings[$a].Name, $newBIOSPolicy.Name))
                                        }
                                    } `
                                    else # NOT ($null -ne $biosTokenParam)
                                    {
                                        ReportError ("`t`tFailed to get BIOS token parameter: {0}." -f @($biosPolicy.Settings[$a].TargetTokenName))
                                    }
                                } `
                                else # NOT ($null -ne $biosTokenFeatureGroup)
                                {
                                    ReportError ("`t`tFailed to get BIOS token feature group: {0}." -f @($biosPolicy.Settings[$a].Name))
                                }

                                $a++
                            }

                            # If we get here, then we didn't jump out of the while loop while we where setting BIOS settings... Yeah!
                            try
                            {
                                [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                $success = $true
                            }
                            catch
                            {
                                ReportError "`t`tFailed to complete UCS transaction to create new BIOS policy."
                            }
                        }
                        catch
                        {
                            ReportError ("Creation of BIOS policy failed.")
                            if ($transactionStarted)
                            {
                                try
                                {
                                    [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                    ReportWarning "`t`tRolled back transaction to update new BIOS policy settings."
                                }
                                catch
                                {
                                    ReportError "`t`tFailed to roll-back UCS transaction to update new BIOS policy settings."
                                }
                            } `
                            else # NOT ($transactionStarted)
                            {
                                ReportError "`t`tFailed to start UCS transaction to update new BIOS policy settings."
                            }

                            try
                            {
                                [void] (Remove-UCSBiosPolicy -BiosPolicy $newBIOSPolicy -ErrorAction Stop)
                                ReportNotice ("`tRemoved new BIOS policy: {0}." -f @($newBIOSPolicy.Name))
                            }
                            catch
                            {
                                ReportError ("`t`tFailed to remove newly created BIOS policy: {0}.  Please remove manually." -f @($newBIOSPolicy.Name))
                            }
                        }
                    } `
                    else # NOT ($null -ne $newBIOSPolicy)
                    {
                        ReportError ("`t`tFailed to create new BIOS policy: {0}.  Add-UcsBiosPolicy returned `$null." -f @($biosPolicy.Name))
                    }
                }
                catch
                {
                    ReportError ("`t`tFailed to create new BIOS policy: {0}.  Exception calling Add-UcsBiosPolicy." -f @($biosPolicy.Name))
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                ReportError "`t`tBIOS policy already exists."
            }
        }
        catch
        {
            $Error
            ReportError "`t`tFailed to check for existing BIOS policy."
        }
    }
    catch
    {
        ReportError ("`t`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    return $success
}

function DeleteDefaultNetworkControlPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $false

    ReportNotice ("Deleting default network control policy on {0}." -f @($ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            # Make sure network control policy "$policyName" does not already exist
            $existingPolicy = Get-UcsNetworkControlPolicy -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop

            if ($null -ne $existingPolicy)
            {
                try
                {
                    $oldPolicy = Remove-UcsNetworkControlPolicy -Ucs $ucs -NetworkControlPolicy $existingPolicy -Confirm:$false -Force -ErrorAction Stop

                    if ($null -ne $oldPolicy)
                    {
                        $success = $true
                    } `
                    else # NOT ($null -ne $oldPolicy)
                    {
                        ReportError "`tFailed to remove default network control policy.  (Remove-UcsNetworkControlPolicy returned null)."
                    }
                }
                catch
                {
                    ReportError "`tFailed to  remove default network control policy.  Remove-UcsNetworkControlPolicy threw an exception."
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                # Nothing, the default network control policy does not exist.
            }
        }
        catch
        {
            ReportError "`tFailed to check for default network control policy."
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    return $success
}

function CreateStandardNetworkControlPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $networkControlPolicyName
    )

    <#
        # Create Network Control Policy
        Start-UcsTransaction
        $mo = Get-UcsOrg -Level root  | Add-UcsNetworkControlPolicy -Cdp "enabled" -MacRegisterMode "all-host-vlans" -Name "klb"
        $mo_1 = $mo | Add-UcsPortSecurityConfig -ModifyPresent -Descr "" -Forge "allow" -Name "" -PolicyOwner "local"
        Complete-UcsTransaction
    #>

    $success = $false

    ReportNotice ("Creating standard network control policy on {0}." -f @($ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                # Make sure network control policy "$policyName" does not already exist
                $existingPolicy = Get-UcsNetworkControlPolicy -Ucs $ucs -Org $rootOrg -Name $networkControlPolicyName -ErrorAction Stop

                if ($null -eq $existingPolicy)
                {
                    try
                    {
                        $newPolicy = Add-UcsNetworkControlPolicy -Ucs $ucs -Org $rootOrg -Name $networkControlPolicyName -Cdp "enabled" -MacRegisterMode "all-host-vlans" -ErrorAction Stop

                        if ($null -ne $newPolicy)
                        {
                            try
                            {
                                $psc = Add-UcsPortSecurityConfig -Ucs $ucs -NetworkControlPolicy $newPolicy -ModifyPresent -Forge "allow" -PolicyOwner "local" -ErrorAction Stop
                                if ($null -ne $psc)
                                {
                                    $success = $true
                                } `
                                else # NOT ($null -ne $psc)
                                {
                                    ReportError ("`tFailed to set port security configuration on network control policy {0}.  Add-UcsPortSecurityConfig returned null." -f @($newPolicy.Name))
                                }
                            }
                            catch
                            {
                                ReportError ("`tFailed to set port security configuration on network control policy {0}.  Add-UcsPortSecurityConfig threw an exception." -f @($newPolicy.Name))
                            }
                        } `
                        else # NOT ($null -ne $newPolicy)
                        {
                            ReportError "`tFailed to create new network control policy.  Add-UcsNetworkControlPolicy returned `$null."
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to create new network control policy.  Add-UcsNetworkControlPolicy threw an exception."
                    }
                } `
                else # NOT ($null -eq $existingPolicy)
                {
                    ReportError "`tNetwork control policy already exists."
                }
            }
            catch
            {
                ReportError "`tFailed to check for existing network control policy."
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null." -f @($ucs.Name))
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception." -f @($ucs.Name))
    }

    return $success
}

function CheckExistingBootPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [Cisco.Ucsm.LsbootPolicy] $bootPolicy
    )

    $bootPolicyIsGood = $true

    ReportNotice ("`tChecking existing boot policy: {0}" -f @($bootPolicy.Name))
    # Check SecureBoot
    try
    {
        $bootSecurity = Get-UcsLsbootBootSecurity -Ucs $ucs -BootPolicy $bootPolicy -ErrorAction Stop
        if ($null -ne $bootSecurity)
        {
            if ($bootSecurity.SecureBoot -eq "no")
            {
                ReportNotice ("`t`tSecureBoot set correctly: {0}" -f @($bootSecurity.SecureBoot))
            } `
            else # NOT ($bootSecurity.SecureBoot -eq "no")
            {
                ReportError ("`t`tSecureBoot set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($bootSecurity.SecureBoot, "no"))
                $bootPolicyIsGood = $false
            }
        } `
        else # NOT ($null -ne $bootSecurity)
        {
            ReportError ("`t`tFailed to retrieve boot security setting for boot policy {0}.  Get-UcsLsbootBootSecurity returned `$null." -f @($bootPolicy.Name))
            $bootPolicyIsGood = $false
        }
    }
    catch
    {
        ReportError ("`t`tFailed to retrieve boot security setting for boot policy {0}.  Get-UcsLsbootBootSecurity threw nd exception." -f @($bootPolicy.Name))
        $bootPolicyIsGood = $false
    }

    # Check boot storage
    try
    {
        $bootStorage = Get-UcsLsbootStorage -Ucs $ucs -BootPolicy $bootPolicy -ErrorAction Stop
        if ($null -ne $bootStorage)
        {
            # Check boot storage order
            if ($bootStorage.Order -eq 1)
            {
                ReportNotice ("`t`tBoot storage order set correctly: {0}" -f @($bootStorage.Order))
            } `
            else # NOT ($bootStorage.Order -eq 1)
            {
                ReportError ("`t`tBoot storage order set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($bootStorage.Order, 1))
                $bootPolicyIsGood = $false
            }

            try
            {
                $bootLocalStorage = Get-UcsLsbootLocalStorage -Ucs $ucs -LsbootStorage $bootStorage -ErrorAction Stop
                if ($null -ne $bootLocalStorage)
                {
                    ReportNotice "`t`tBoot local storage settings are present."

                    try
                    {
                        $localLUN = Get-UcsLsbootEmbeddedLocalLunImage -Ucs $ucs -LsbootLocalStorage $bootLocalStorage -ErrorAction Stop
                        if ($null -ne $localLUN)
                        {
                            ReportNotice "`t`tBoot policy contains an embedded local LUN."

                            if ($localLUN.Order -eq 1)
                            {
                                ReportNotice ("`t`tLocal LUN boot order set correctly: {0}" -f @($localLUN.Order))
                            } `
                            else # NOT ($localLUN.Order -eq 1)
                            {
                                ReportError ("`t`tLocal LUN boot order set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($localLUN.Order, 1))
                                $bootPolicyIsGood = $false
                            }

                            try
                            {
                                $localLUNUEFIParams = Get-UcsLsbootUEFIBootParam -Ucs $ucs -LsbootEmbeddedLocalLunImage $localLUN -ErrorAction Stop
                                if ($null -ne $localLUNUEFIParams)
                                {
                                    if ($localLUNUEFIParams.BootDescription -eq "VMware ESXi")
                                    {
                                        ReportNotice ("`t`tLocal LUN UEFI boot parameter 'BootDescription' set correctly: {0}" -f @($localLUNUEFIParams.BootDescription))
                                    } `
                                    else # NOT ($localLUNUEFIParams.BootDescription -eq "VMware ESXi")
                                    {
                                        ReportWarning("`t`tLocal LUN UEFI boot parameter 'BootDescription' set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($localLUNUEFIParams.BootDescription, "VMWare ESXi"))
                                    }

                                    if ($localLUNUEFIParams.BootLoaderName -eq "BOOTx64.EFI")
                                    {
                                        ReportNotice ("`t`tLocal LUN UEFI boot parameter 'BootLoaderName' set correctly: {0}" -f @($localLUNUEFIParams.BootLoaderName))
                                    } `
                                    else # NOT ($localLUNUEFIParams.BootLoaderName -eq "BOOTx64.EFI")
                                    {
                                        ReportError ("`t`tLocal LUN UEFI boot parameter 'BootLoaderName' set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($localLUNUEFIParams.BootLoaderName, "BOOTx64.EFI"))
                                        $bootPolicyIsGood = $false
                                    }

                                    if ($localLUNUEFIParams.BootLoaderPath -eq "\EFI\BOOT")
                                    {
                                        ReportNotice ("`t`tLocal LUN UEFI boot parameter 'BootLoaderPath' set correctly: {0}" -f @($localLUNUEFIParams.BootLoaderPath))
                                    } `
                                    else # NOT ($localLUNUEFIParams.BootLoaderPath -eq "\EFI\BOOT")
                                    {
                                        ReportError ("`t`tLocal LUN UEFI boot parameter 'BootLoaderPath' set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($localLUNUEFIParams.BootLoaderPath, "\EFI\BOOT"))
                                        $bootPolicyIsGood = $false
                                    }
                                } `
                                else # NOT ($null -ne $localLUNUEFIParams)
                                {
                                    ReportError ("`t`tFailed to retrieve local LUN UEFI parameters boot policy {0}.  Get-UcsLsbootUEFIBootParam returned `$null." -f @($bootPolicy.Name))
                                    $bootPolicyIsGood = $false
                                }
                            }
                            catch
                            {
                                ReportError ("`t`tFailed to retrieve local LUN UEFI parameters boot policy {0}.  Get-UcsLsbootUEFIBootParam threw an exception." -f @($bootPolicy.Name))
                                $bootPolicyIsGood = $false
                            }
                        } `
                        else # NOT ($null -ne $localLUN)
                        {
                            ReportError ("`t`tFailed to retrieve embedded local LUN image for boot policy {0}.  Get-UcsLsbootEmbeddedLocalLunImage returned `$null." -f @($bootPolicy.Name))
                            $bootPolicyIsGood = $false
                        }
                    }
                    catch
                    {
                        ReportError ("`t`tFailed to retrieve embedded local LUN image for boot policy {0}.  Get-UcsLsbootEmbeddedLocalLunImage threw an exception." -f @($bootPolicy.Name))
                        $bootPolicyIsGood = $false
                    }
                } `
                else # NOT ($null -ne $bootLocalStorage)
                {
                    ReportError "`t`tLocal boot storage settings are missing."
                    $bootPolicyIsGood = $false
                }
            }
            catch
            {
                ReportError ("`t`tFailed to retrieve boot local storage settings for boot policy {0}.  Get-UcsLsbootLocalStorage threw an exception." -f @($bootPolicy.Name))
                $bootPolicyIsGood = $false
            }
        } `
        else # NOT ($null -ne $bootStorage)
        {
            ReportError ("`t`tFailed to retrieve boot storage for boot policy {0}.  Get-UcsLsbootStorage returned `$null." -f @($existingPolicy.Name))
            $bootPolicyIsGood = $false
        }
    }
    catch
    {
        ReportError ("`t`tFailed to retrieve boot storage for boot policy {0}.  Get-UcsLsbootStorage threw an exception." -f @($bootPolicy.Name))
        $bootPolicyIsGood = $false
    }

    try
    {
        $virtualMedia = Get-UcsLsbootVirtualMedia -Ucs $ucs -BootPolicy $bootPolicy -ErrorAction Stop

        if ($null -ne $virtualMedia)
        {
            if ($virtualMedia.Access -eq "read-only-remote")
            {
                ReportNotice ("`t`tVirtual boot media access set correctly: {0}" -f @($virtualMedia.Access))
            } `
            else # NOT ($virtualMedia.Access -eq "read-only-remote")
            {
                ReportError ("`t`tVirtual boot media access set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($virtualMedia.Access, "read-only-remote"))
                $bootPolicyIsGood = $false
            }

            if ($virtualMedia.LunId -eq "0")
            {
                ReportNotice ("`t`tVirtual boot media LUN ID set correctly: {0}" -f @($virtualMedia.LunId))
            } `
            else # NOT ($virtualMedia.LunId -eq "0")
            {
                ReportError ("`t`tVirtual boot media LUN ID set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($virtualMedia.LunId, "0"))
                $bootPolicyIsGood = $false
            }

            if ($virtualMedia.Order -eq 2)
            {
                ReportNotice ("`t`tVirtual boot media boot order set correctly: {0}" -f @($virtualMedia.Order))
            } `
            else # NOT ($virtualMedia.Order -eq 2)
            {
                ReportError ("`t`tVirtual boot media boot order set incorrectly.  Current value: {0}`t Correct Value: {1}" -f @($virtualMedia.Order, 2))
                $bootPolicyIsGood = $false
            }
        } `
        else # NOT ($null -ne $virtualMedia)
        {
            ReportError ("`t`tFailed to retrieve virtual boot media for boot policy {0}.  Get-UcsLsbootVirtualMedia returned `$null." -f @($bootPolicy.Name))
            $bootPolicyIsGood = $false
        }
    }
    catch
    {
        ReportError ("`t`tFailed to retrieve virtual boot media for boot policy {0}.  Get-UcsLsbootVirtualMedia threw an exception." -f @($bootPolicy.Name))
        $bootPolicyIsGood = $false
    }

    return $bootPolicyIsGood
}

function CreateBootPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $policyName
    )

    <#
        Start-UcsTransaction
        $mo = Get-UcsOrg -Level root  | Add-UcsBootPolicy -BootMode "uefi" -Name "M.2-Boot"
        $mo_1 = $mo | Add-UcsLsbootBootSecurity -SecureBoot "no"
        $mo_2 = $mo | Add-UcsLsbootStorage -Order 1
        $mo_2_1 = $mo_2 | Add-UcsLsbootLocalStorage
        $mo_2_1_1 = $mo_2_1 | Add-UcsLsbootEmbeddedLocalLunImage -ModifyPresent -Order 1
        $mo_2_1_1_1 = $mo_2_1_1 | Add-UcsLsbootUEFIBootParam -ModifyPresent -BootDescription "VMware ESXi" -BootLoaderName "BOOTx64.EFI" -BootLoaderPath "\EFI\BOOT"
        $mo_3 = $mo | Add-UcsLsbootVirtualMedia -Access "read-only-remote" -LunId "0" -Order 2
        Complete-UcsTransaction
    #>

    $success = $true

    ReportNotice ("`tCreating boot policy: {0}" -f @($policyName))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $existingPolicy = Get-UcsBootPolicy -Ucs $ucs -Org $rootOrg -Name $policyName -ErrorAction Stop

                if ($null -eq $existingPolicy)
                {
                    try
                    {
                        [void] (Start-UcsTransaction -Ucs $ucs -ErrorAction Stop)

                        try
                        {
                            $bootPolicy = Add-UcsBootPolicy -Ucs $ucs -Org $rootOrg -BootMode "uefi" -Name $policyName -ErrorAction Stop
                            if ($null -ne $bootPolicy)
                            {
                                try
                                {
                                    $lsBootBootSecurity = Add-UcsLsbootBootSecurity -Ucs $ucs -BootPolicy $bootPolicy -SecureBoot "no" -ErrorAction Stop
                                    if ($null -ne $lsBootBootSecurity)
                                    {
                                        # Nothing
                                    } `
                                    else # NOT ($null -ne $lsBootBootSecurity)
                                    {
                                        ReportError "`tFailed to set boot security on new boot policy.  Add-UcsLsbootBootSecurity returned `$null."
                                        $success = $false
                                    }
                                }
                                catch
                                {
                                    ReportError "`tFailed to set boot security on new boot policy.  Add-UcsLsbootBootSecurity threw an exception."
                                    $success = $false
                                }

                                try
                                {
                                    $lsBootStorage = Add-UcsLsbootStorage -Ucs $ucs -BootPolicy $bootPolicy -Order 1 -ErrorAction Stop
                                    if ($null -ne $lsBootStorage)
                                    {
                                        try
                                        {
                                            $lsBootLocalStorage = Add-UcsLsbootLocalStorage -Ucs $ucs -LsbootStorage $lsBootStorage -ErrorAction Stop
                                            if ($null -ne $lsBootLocalStorage)
                                            {
                                                try
                                                {
                                                    $lsBootEmbeddedLocalLunImage = Add-UcsLsbootEmbeddedLocalLunImage -Ucs $ucs -LsbootLocalStorage $lsBootLocalStorage -ModifyPresent -Order 1 -ErrorAction Stop
                                                    if ($null -ne $lsBootEmbeddedLocalLunImage)
                                                    {
                                                        try
                                                        {
                                                            $lsBootUEFIBootParams = Add-UcsLsbootUEFIBootParam -Ucs $ucs -LsbootEmbeddedLocalLunImage $lsBootEmbeddedLocalLunImage -ModifyPresent -BootDescription "VMware ESXi" -BootLoaderName "BOOTx64.EFI" -BootLoaderPath "\EFI\BOOT" -ErrorAction Stop
                                                            if ($null -ne $lsBootUEFIBootParams)
                                                            {
                                                            } `
                                                            else # NOT ($null -ne $lsBootUEFIBootParams)
                                                            {
                                                                ReportError "`tFailed to set embedded local LUN image UEFI boot parameters in new boot policy.  Add-UcsLsbootUEFIBootParam threw an exception."
                                                                $success = $false
                                                            }
                                                        }
                                                        catch
                                                        {
                                                            ReportError "`tFailed to set embedded local LUN image UEFI boot parameters in new boot policy.  Add-UcsLsbootUEFIBootParam threw an exception."
                                                            $success = $false
                                                        }

                                                    } `
                                                    else # NOT ($null -ne $lsBootEmbeddedLocalLunImage)
                                                    {
                                                        ReportError "`tFailed to add embedded local LUN image to new boot policy.  Add-UcsLsbootEmbeddedLocalLunImage returned `$null."
                                                        $success = $false
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError "`tFailed to add embedded local LUN image to new boot policy.  Add-UcsLsbootEmbeddedLocalLunImage threw an exception."
                                                    $success = $false
                                                }
                                            } `
                                            else # NOT ($null -ne $lsBootLocalStorage)
                                            {
                                                ReportError "`tFailed to add local storage to new boot policy.  Add-UcsLsbootLocalStorage returned `$null."
                                                $success = $false
                                            }
                                        }
                                        catch
                                        {
                                            ReportError "`tFailed to add local storage to new boot policy.  Add-UcsLsbootLocalStorage threw an exception."
                                            $success = $false
                                        }
                                    } `
                                    else # NOT ($null -ne $lsBootStorage)
                                    {
                                        ReportError "`tFailed to add boot storage to new boot policy.  Add-UcsLsbootStorage returned `$null."
                                        $success = $false
                                    }
                                }
                                catch
                                {
                                    ReportError "`tFailed to add boot storage to new boot policy.  Add-UcsLsbootStorage threw an exception."
                                    $success = $false
                                }

                                try
                                {
                                    $lsBootVirtualMedia = Add-UcsLsbootVirtualMedia -Ucs $ucs -BootPolicy $bootPolicy -Access "read-only-remote" -LunId "0" -Order 2 -ErrorAction Stop
                                    if ($null -ne $lsBootVirtualMedia)
                                    {
                                        # Nothing
                                    } `
                                    else # NOT ($null -ne $lsBootVirtualMedia)
                                    {
                                        ReportError "`tFailed to add virtual media to new boot policy.  Add-UcsLsbootVirtualMedia threw an exception."
                                        $success = $false
                                    }
                                }
                                catch
                                {
                                    ReportError "`tFailed to add virtual media to new boot policy.  Add-UcsLsbootVirtualMedia threw an exception."
                                    $success = $false
                                }
                            } `
                            else # NOT ($null -ne $bootPolicy)
                            {
                                ReportError "`tFailed to create new boot policy.  Add-UcsBootPolicy threw an exception."
                                $success = $false
                            }
                        }
                        catch
                        {
                            ReportError "`tFailed to create new boot policy.  Add-UcsBootPolicy threw an exception."
                            $success = $false
                        }

                        if ($success)
                        {
                            try
                            {
                                [void] (Complete-UcsTransaction -Ucs $ucs)
                            }
                            catch
                            {
                                ReportError ("`tFailed to complete transaction to create new boot policy: {0}." -f @($policyName))
                                $success = $false
                            }
                        } `
                        else # NOT ($success)
                        {
                            try
                            {
                                [void] (Undo-UcsTransaction -Ucs $ucs)
                            }
                            catch
                            {
                                ReportError ("`tFailed to rollback transaction to create new boot policy: {0}." -f @($policyName))
                                $success = $false
                            }
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to start UCS transaction."
                    }
                } `
                else # NOT ($null -eq $existingPolicy)
                {
                    # The boot policy already exists, so let's be diligent and check its settings.
                    $success = CheckExistingBootPolicy -ucs $ucs -bootPolicy $existingPolicy
                    if (-not $success)
                    {
                        ReportError ("`tExisting boot policy {0} is invalid, please correct." -f @($existingPolicy.Name))
                    }
                }
            }
            catch
            {
                ReportError  ("`Failed to check for existing boot policy: {0}.  Get-UcsBootPolicy threw an exception." -f @($policyName))
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null." -f @($ucs.Name))
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception." -f @($ucs.Name))
    }

    return $success
}

function DeleteDefaultScrubPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $false

    ReportNotice ("Deleting default scrub policy on {0}." -f @($ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            # Make sure scrub policy "default" exists
            $existingPolicy = Get-UcsScrubPolicy -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop

            if ($null -ne $existingPolicy)
            {
                try
                {
                    $oldPolicy = Remove-UcsScrubPolicy -Ucs $ucs -ScrubPolicy $existingPolicy -Confirm:$false -Force -ErrorAction Stop

                    if ($null -ne $oldPolicy)
                    {
                        $success = $true
                    } `
                    else # NOT ($null -ne $oldPolicy)
                    {
                        ReportError "`tFailed to remove default scrub policy.  Remove-UcsScrubPolicy returned `$null."
                    }
                }
                catch
                {
                    ReportError "`tFailed to  remove default network control policy.  Remove-UcsScrubPolicy threw an exception."
                }
            } `
            else # NOT ($null -eq $existingPolicy)
            {
                # Nothing, the default scrub policy does not exist.
            }
        }
        catch
        {
            ReportError "`tFailed to check for default scrub policy.  Get-UcsScrubPolicy threw an exception."
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}." -f @($ucs.Name))
    }

    return $success
}

function CreateScrubPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $policyName
    )

    $success = $false

    ReportNotice ("`tCreating scrub policy: {0}." -f @($policyName))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $scrubPolicy = Add-UcsScrubPolicy -Ucs $ucs -Org $rootOrg -Name $policyName -ErrorAction Stop
                if ($null -ne $scrubPolicy)
                {
                    $success = $true
                } `
                else # NOT ($null -ne $scrubPolicy)
                {
                    ReportError "`tFailed to create scrub policy.  Add-UcsScrubPolicy returned `$null."
                }
            }
            catch
            {
                ReportError "`tFailed to create scrub policy.  Add-UcsScrubPolicy threw an exception."
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null." -f @($ucs.Name))
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception." -f @($ucs.Name))
    }

    return $success
}

function CreateTrustPoint
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $false

    ReportNotice "Creating Trust Point: PEI_CA2_TP"
    try
    {
        $existingTrustPoint = Get-UcsTrustPoint -Ucs $ucs -Name "PEI_CA2_TP" -ErrorAction Stop

        if ($null -eq $existingTrustPoint)
        {
            try
            {
                $newTrustPoint = Add-UcsTrustPoint -Ucs $ucs -CertChain $rdcConfigurationData.pki_ca_chain -Name "PEI_CA2_TP" -ErrorAction Stop
                if ($null -ne $newTrustPoint)
                {
                    $success = $true
                } `
                else # NOT ($null -ne $newTrustPoint)
                {
                    ReportError "`tFailed to create new trust point `"PEI_CA2_TP`".  Add-UcsTrustPoint returned `$null."
                }
            }
            catch
            {
                ReportError "`tFailed to create new trust point `"PEI_CA2_TP`".  Add-UcsTrustPoint threw an exception."
            }
        } `
        else # NOT ($null -eq $existingTrustPoint)
        {
            ReportWarning "`tTrust point `"PEI_CA2_TP`" already exists.  Manually verify."
        }
    }
    catch
    {
        ReportError "`tFailed to check for existing trust point `"PEI_CA2_TP`".  Get-UcsTrustPoint threw an exception."
    }

    return $success
}

function CreateKeyRing
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $location,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $state,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $country
    )

    $success = $false

    $ucsName = "UCS"
    if (-not [String]::IsNullOrEmpty($ucs.Ucs))
    {
        $ucsName = $ucs.Ucs.ToUpper()
    } `
    else # NOT (-not [String]::IsNullOrEmpty($ucs.UCS))
    {
        if (-not [String]::IsNullOrEmpty($ucs.Name))
        {
            $ucsName = @($ucs.Name.ToUpper() -split '\.')[0]
        } `
        else # NOT (-not [String]::IsNullOrEmpty($ucs.Name))
        {
            # Nothing.
        }
    }

    $keyRingName = "{0}_CERT" -f @($ucs.UCS.ToUpper())

    ReportNotice ("`tCreating key ring: {0}." -f @($keyRingName))
    try
    {
        $keyRing = Get-UcsKeyRing -Ucs $ucs -Name $keyRingName -ErrorAction Stop

        if ($null -eq $keyRing)
        {
            # TRUE - $keyRingName doesn't exist

            try
            {
                $keyRing = Add-UcsKeyRing -Ucs $ucs -Modulus "mod4096" -Name $keyRingName -ErrorAction Stop

                if ($null -ne $keyRing)
                {
                    try
                    {
                        $certReq = Add-UcsCertRequest -Ucs $ucs -KeyRing $keyRing -Country $country -Dns $ucs.Name.ToLower() -Locality $location -OrgName "POWER Engineers, Inc." -OrgUnitName "Operations IT" -State $state -SubjName $ucs.Name.ToLower() -ErrorAction Stop
                        if ($null -ne $certReq)
                        {
                            try
                            {
                                $certReq = Get-UcsCertRequest -Ucs $ucs -KeyRing $keyRing -ErrorAction Stop
                                if ($null -ne $certReq)
                                {
                                    if (-not [String]::IsNullOrEmpty($certReq.Req))
                                    {
                                        try
                                        {
                                            $requestFileName = "{0}.req" -f @($keyRing.Name)
                                            $certReq.Req | Out-File -FilePath $requestFileName -Encoding ascii -ErrorAction Stop
                                            ReportNotice ("`tCertificate request for keyring {0} saved to {1}." -f @($keyRing.Name, $requestFileName))
                                            <#
                                                TODO: Consider automating submitting and retrieving the certificate.
                                            #>
                                        }
                                        catch
                                        {
                                            ReportWarning ("`tFailed to save certificate request for keyring {0}.  Manually retrieve it from UCS Manager." -f @($keyRing.Name))
                                        }
                                    } `
                                    else # NOT (-not [String]::IsNullOrEmpty($certReq.Req))
                                    {
                                        if ($ucs.Name -notmatch "ucspe")
                                        {
                                            ReportError ("`tCertificate request for keyring {0} does not contain the request string." -f @($keyRing.Name))
                                        } `
                                        else # NOT ($ucs.Name -match "ucspe")
                                        {
                                            ReportWarning ("`tCertificate request for keyring {0} does not contain the request string." -f @($keyRing.Name))
                                        }
                                    }
                                } `
                                else # NOT ($null -ne $certReq)
                                {
                                    ReportError ("`tFailed to retrieve certificate request for keyring {0}.  Get-UcsCertRequest returned `$null." -f @($keyRingName))
                                }
                            }
                            catch
                            {
                                ReportError ("`tFailed to retrieve certificate request for keyring {0}.  Get-UcsCertRequest threw an exception." -f @($keyRingName))
                            }
                        } `
                        else # NOT ($null -ne $certReq)
                        {
                            ReportError ("`tFailed to create certificate request for keyring {0}.  Add-UcsCertRequest returned `$null." -f @($keyRingName))
                        }
                    }
                    catch
                    {
                        ReportError ("`tFailed to create certificate request for keyring {0}.  Add-UcsCertRequest threw an exception." -f @($keyRingName))
                    }
                } `
                else # NOT ($null -ne $keyRing)
                {
                    ReportError ("`tFailed to create keyring {0}.  Add-UcsKeyRing returned `$null." -f @($keyRingName))
                }
            }
            catch
            {
                ReportError ("`tFailed to create keyring {0}.  Add-UcsKeyRing threw an exception." -f @($keyRingName))
            }

            $success = $true
        } `
        else # NOT ($null -eq $keyRing)
        {
            ReportError ("`tKeyring {0} already exists." -f @($keyRingName))
        }
    }
    catch
    {
        ReportError ("`tFailed to check for existing keyring {0}.  Get-UcsKeyRing threw an exception." -f @($keyRingName))
    }

    return $success
}

function SetEquipmentGlobalPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

<#
    Start-UcsTransaction
    Add-UcsManagedObject -ModifyPresent  -ClassId ComputeChassisDiscPolicy -PropertyMap @{Action="2-link"; Dn="org-root/chassis-discovery"; }
    Add-UcsManagedObject -ModifyPresent  -ClassId ComputeServerDiscPolicy -PropertyMap @{Dn="org-root/server-discovery"; ScrubPolicyName=""; Action="immediate"; }
    Get-UcsOrg -Level root  | Add-UcsManagedObject -ModifyPresent  -ClassId ComputeServerMgmtPolicy -PropertyMap @{Action="auto-acknowledged"; }
    Add-UcsManagedObject -ModifyPresent  -ClassId ComputePsuPolicy -PropertyMap @{Redundancy="grid"; Dn="org-root/psu-policy"; }
    Add-UcsManagedObject -ModifyPresent  -ClassId FabricLanCloud -PropertyMap @{Dn="fabric/lan"; MacAging="mode-default"; }
    Add-UcsManagedObject -ModifyPresent  -ClassId PowerMgmtPolicy -PropertyMap @{Style="intelligent-policy-driven"; Dn="org-root/pwr-mgmt-policy"; }
    Get-UcsOrg -Level root  | Add-UcsManagedObject -ModifyPresent  -ClassId FirmwareAutoSyncPolicy -PropertyMap @{SyncState="No Actions"; }
    Complete-UcsTransaction
#>

    $success = $true

    ReportNotice "`tSetting equipment global policy"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                Start-UcsTransaction -Ucs $ucs -ErrorAction Stop

                # While $success -eq $true, keep updating the equipment global policy
                try
                {
                    ReportNotice "`t`tSetting chassis/FEX discovery policy."
                    $computeChassisDiscPolicy = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId ComputeChassisDiscPolicy -PropertyMap @{Action="2-link"; Dn="org-root/chassis-discovery"; } -ErrorAction Stop
                    if ($null -eq $computeChassisDiscPolicy)
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                        $success = $false
                    } `
                    else # NOT ($null -eq $computeChassisDiscPolicy)
                    {
                        # Nothing.
                    }
                }
                catch
                {
                    ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                    $success = $false
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting rack server discovery policy."
                        $computeServerDiscPolicy = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId ComputeServerDiscPolicy -PropertyMap @{Dn="org-root/server-discovery"; ScrubPolicyName=""; Action="immediate"; } -ErrorAction Stop
                        if ($null -eq $computeServerDiscPolicy)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $computeServerDiscPolicy)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting rack management connection policy."
                        $computeServerMgmtPolicy = $rootOrg | Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId ComputeServerMgmtPolicy -PropertyMap @{Action="auto-acknowledged"; } -ErrorAction Stop
                        if ($null -eq $computeServerMgmtPolicy)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $computeServerMgmtPolicy)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting power policy."
                        $computePsuPolicy = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId ComputePsuPolicy -PropertyMap @{Redundancy="grid"; Dn="org-root/psu-policy"; } -ErrorAction Stop
                        if ($null -eq $computePsuPolicy)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $computePsuPolicy)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting MAC address table aging policy."
                        $fabricLanCloud = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId FabricLanCloud -PropertyMap @{Dn="fabric/lan"; MacAging="mode-default"; } -ErrorAction Stop
                        if ($null -eq $fabricLanCloud)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $fabricLanCloud)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting Global Power Allocation Policy."
                        $powerMgmtPolicy = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId PowerMgmtPolicy -PropertyMap @{Style="intelligent-policy-driven"; Dn="org-root/pwr-mgmt-policy"; } -ErrorAction Stop
                        if ($null -eq $powerMgmtPolicy)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $powerMgmtPolicy)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        ReportNotice "`t`tSetting firmware auto sync server policy."
                        $firmwareAutoSyncPolicy = $rootOrg | Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId FirmwareAutoSyncPolicy -PropertyMap @{SyncState="No Actions"; } -ErrorAction Stop
                        if ($null -eq $firmwareAutoSyncPolicy)
                        {
                            ReportError "`t`t`tFailed: Add-UcsManagedObject returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $firmwareAutoSyncPolicy)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`t`t`tFailed: Add-UcsManagedObject threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing -- Already reported the error
                }

                if ($success)
                {
                    try
                    {
                        [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                    }
                    catch
                    {
                        ReportError "`tFailed to complete UCS transaction.  Manually verify equipment global policy."
                        $success = $false
                    }
                } `
                else # NOT ($success)
                {
                    try
                    {
                        [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                    }
                    catch
                    {
                        ReportError "`tFailed to undo UCS transaction.  Manually verify equipment global policy."
                        $success = $false
                    }
                }
            }
            catch
            {
                ReportError "`tFailed to start transaction."
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null." -f @($ucs.Name))
            $success = $false
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception." -f @($ucs.Name))
        $success = $false
    }

    return $success
}

function SetUplinkPorts
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [System.Object[]] $uplinks
    )

    $success = $true

    ReportNotice "`tSetting fabric interconnect uplinks"

    $a = 0
    while($success -and ($a -lt $uplinks.Length))
    {
        try
        {
            $uplink = Add-UcsUplinkPort -Ucs $ucs -filancloud $uplinks[$a].filancloud -portid $uplinks[$a].portid -slotid $uplinks[$a].slotid
            if ($null -eq $uplink)
            {
                ReportError ("`tFailed to add uplink to fabric interconnect {0}, slot {1}, port {2}.  Add-UcsUplinkPort returned `$null." -f @($uplinks[$a].filancloud, $uplinks[$a].slotid, $uplinks[$a].portid))
                $success = $false
            } `
            else # NOT ($null -ne $rootOrg)
            {
                # Nothing
            }
        }
        catch
        {
            ReportError ("`tFailed to add uplink to fabric interconnect {0}, slot {1}, port {2}.  Add-UcsUplinkPort threw an exception." -f @($uplinks[$a].filancloud, $uplinks[$a].slotid, $uplinks[$a].portid))
            $success = $false
        }
        $a++
    }

    return $success
}

function SetLanCloudQoSBestEffortMTU
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $true

    ReportNotice "`tSetting LAN cloud best effort QoS."
    try
    {
        $qosClassEthBE = Add-UcsManagedObject -Ucs $ucs -ModifyPresent -ClassId QosclassEthBE -PropertyMap @{Mtu="9216"; Dn="fabric/lan/classes/class-best-effort"; } -ErrorAction Stop

        if ($null -eq $qosClassEthBE)
        {
            ReportError "`tFailed to set LAN cloud best effort QoS MTU.  Add-UcsManagedObject returned `$null"
            $success = $false
        } `
        else # NOT ($null -eq $qosClassEthBE)
        {
            # Nothing
        }
    }
    catch
    {
        ReportError "`tFailed to set LAN cloud best effort QoS MTU.  Add-UcsManagedObject threw an exception."
        $success = $false
    }

    return $success
}

function DeleteDefaultServerPool
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $true

    ReportNotice "`tRemoving default server pool."
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $defaultServerPool = $rootOrg | Get-UcsServerPool -Name "default" -LimitScope -ErrorAction Stop
                if ($null -ne $defaultServerPool)
                {
                    try
                    {
                        $deletedPool = $defaultServerPool | Remove-UcsServerPool -Confirm:$false -Force -ErrorAction Stop
                        if ($null -eq $deletedPool)
                        {
                            ReportError "`tFailed to remove default server pool.  Remove-UcsServerPool returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $deletedPool)
                        {
                            # Nothing
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to remove default server pool.  Remove-UcsServerPool threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $defaultServerPool)
                {
                    ReportError "`tFailed to retrieve default server pool.  Get-UcsServerPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve default server pool.  Get-UcsServerPool threw an exception."
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null." -f @($ucs.Name))
            $success = $false
        }
    }
    catch
    {
        ReportError ("`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception." -f @($ucs.Name))
        $success = $false
    }

    return $success
}

function CreateUUIDSuffixPool
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Int64] $uuidSuffixPoolStart
    )

<#
    Start-UcsTransaction
    $mo_1 = $rootOrg | Get-UcsUuidSuffixPool -Name "default" -LimitScope | Remove-UcsUuidSuffixPool
    Complete-UcsTransaction

    Start-UcsTransaction
    $mo = $rootOrg  | Add-UcsUuidSuffixPool -AssignmentOrder "sequential" -Name "UCSPE-UUID" -Prefix "DF88E734-D896-11EC"
    $mo_1 = $mo | Add-UcsUuidSuffixBlock -From "3000-000000000001" -To "3000-000000000100"
    Complete-UcsTransaction
#>
    $success = $true

    ReportNotice "Removing default UUID suffix pool and creating a new one."
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $defaultUUIDSuffixPool = Get-UcsUuidSuffixPool -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop
                if ($null -ne $defaultUUIDSuffixPool)
                {
                    $uuidSuffixPoolPrefix = $defaultUUIDSuffixPool.Prefix
                    if (-not [String]::IsNullOrEmpty($uuidSuffixPoolPrefix))
                    {
                        $uuidSuffixPoolName = "{0}-UUID" -f @($ucs.Name.Replace(".powereng.com","").ToUpper())
                        $poolStart = "{0:X4}-{1:X12}" -f @($uuidSuffixPoolStart, 1)
                        $poolEnd = "{0:X4}-{1:X12}" -f @($uuidSuffixPoolStart, 256)

                        try
                        {
                            $removedUUIDPool = $defaultUUIDSuffixPool | Remove-UcsUuidSuffixPool -Force -Confirm:$false -ErrorAction Stop
                            if ($null -ne $removedUUIDPool)
                            {
                                try
                                {
                                    $newUUIDSuffixPool = Add-UcsUuidSuffixPool -Ucs $ucs -Org $rootOrg -AssignmentOrder "sequential" -Name $uuidSuffixPoolName -Prefix $uuidSuffixPoolPrefix -ErrorAction Stop
                                    if ($null -ne $newUUIDSuffixPool)
                                    {
                                        try
                                        {
                                            $uuidSuffixPoolBlock = $newUUIDSuffixPool | Add-UcsUuidSuffixBlock -Ucs $ucs -From $poolStart -To $poolEnd -ErrorAction Stop
                                            if ($null -eq $uuidSuffixPoolBlock)
                                            {
                                                ReportError ("`tFailed to create UUID suffix pool block [{0} - {1}].  Add-UcsUuidSuffixBlock returned `$null." -f @($poolStart, $poolEnd))
                                                $success = $false
                                            } `
                                            else # NOT ($null -eq $uuidSuffixPoolBlock)
                                            {
                                                # Nothing.
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("`tFailed to create UUID suffix pool block [{0} - {1}].  Add-UcsUuidSuffixBlock threw an exception." -f @($poolStart, $poolEnd))
                                            $success = $false
                                        }
                                    } `
                                    else # NOT ($null -ne $newUUIDSuffixPool)
                                    {
                                        ReportError ("`tFailed to create UUID suffix pool {0}.  Add-UcsUuidSuffixPool returned `$null." -f @($uuidSuffixPoolName))
                                        $success = $false
                                    }
                                }
                                catch
                                {
                                    ReportError ("`tFailed to create UUID suffix pool {0}.  Add-UcsUuidSuffixPool threw an exception." -f @($uuidSuffixPoolName))
                                    $success = $false
                                }
                            } `
                            else # NOT ($null -ne $removedUUIDPool)
                            {
                                ReportError "`tFailed to remove default UUI suffix pool.  Remove-UcsUuidSuffixPool returned `$null."
                                $success = $false
                            }
                        }
                        catch
                        {
                            ReportError "`tFailed to remove default UUI suffix pool.  Remove-UcsUuidSuffixPool threw an exception."
                            $success = $false
                        }
                    } `
                    else # NOT (-not [String]::IsNullOrEmpty($uuidSuffixPoolPrefix))
                    {
                        ReportError "`tDefault UUID suffix pool prefix is missing.  Configure UUID suffix pool manually."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $defaultUUIDSuffixPool)
                {
                    ReportError "`tFailed to retrieve default UUID suffix pool.  Get-UcsUuidSuffixPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve default UUID suffix pool.  Get-UcsUuidSuffixPool threw an exception."
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization from {0}.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization from {0}.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}

function DeleteSANPools
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )
<#
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
#>
    $success = $true

    ReportNotice "`tRemoving default SAN pools."
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
                $nodeDefaultWWNNPool = Get-UcsWwnPool -Ucs $ucs -Org $rootOrg -Name "node-default" -ErrorAction Stop
                if ($null -ne $nodeDefaultWWNNPool)
                {
                    try
                    {
                        $removedWWNNPool = $nodeDefaultWWNNPool | Remove-UcsWwnPool -Force -Confirm:$false -ErrorAction Stop
                        if ($null -eq $removedWWNNPool)
                        {
                            ReportError "`tFailed to remove WWNN pool: node-default.  Remove-UcsWwnPool returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $removedWWNNPool)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to remove WWNN pool: node-default.  Remove-UcsWwnPool threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $nodeDefaultWWNNPool)
                {
                    ReportError "`tFailed to retrieve WWNN pool: node-default.  Get-UcsWwnPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve WWNN pool: node-default.  Get-UcsWwnPool threw an exception."
                $success = $false
            }

            try
            {
                $defaultWWPNPool = Get-UcsWwnPool -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop
                if ($null -ne $defaultWWPNPool)
                {
                    try
                    {
                        $removedWWPNPool = $defaultWWPNPool | Remove-UcsWwnPool -Force -Confirm:$false -ErrorAction Stop
                        if ($null -eq $removedWWPNPool)
                        {
                            ReportError "`tFailed to remove WWPN pool: default.  Remove-UcsWwnPool returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $removedWWPNPool)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to remove WWPN pool: default.  Remove-UcsWwnPool threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $defaultWWPNPool)
                {
                    ReportError "`tFailed to retrieve WWPN pool: default.  Get-UcsWwnPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve WWPN pool: default.  Get-UcsWwnPool threw an exception."
                $success = $false
            }

            try
            {
                $defaultIQNPool = Get-UcsIqnPoolPool -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop
                if ($null -ne $defaultIQNPool)
                {
                    try
                    {
                        $removedIQNPool = $defaultIQNPool | Remove-UcsIqnPoolPool -Force -Confirm:$false -ErrorAction Stop
                        if ($null -eq $removedIQNPool)
                        {
                            ReportError "`tFailed to remove IQN pool: default.  Remove-UcsIqnPoolPool returned `$null."
                            $success = $false
                        } `
                        else # NOT ($null -eq $removedIQNPool)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        ReportError "`tFailed to remove IQN pool: default.  Remove-UcsIqnPoolPool threw an exception."
                        $success = $false
                    }
                } `
                else # NOT ($null -ne $defaultIQNPool)
                {
                    ReportError "`tFailed to retrieve IQN pool: default.  Get-UcsIqnPoolPool returned `$null."
                    $success = $false
                }
            }
            catch
            {
                ReportError "`tFailed to retrieve IQN pool: default.  Get-UcsIqnPoolPool threw an exception."
                $success = $false
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}

function CreatePowerControlPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [String] $powerControlPolicyName
    )

    $success = $true

    ReportNotice ("`tCreating power control policy {0}..." -f @($powerControlPolicyName))
    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}

    if ($success)
    {
        $success, $pwrCtrlPolicy = InvokeUCSFunction -functionName "Add-UcsPowerPolicy" -failureMsg "Failed to create power control policy." -cmdParams @{ Ucs = $ucs; Org = $rootOrg; Name = $powerControlPolicyName; Prio = "no-cap" }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    return $success
}

function CreateSerialOverLANPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [String] $solPolicyName
    )

    $success = $true

    ReportNotice ("`tCreating serial over LAN policy" -f @($solPolicyName))
    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}

    if ($success)
    {
        $success, $pwrCtrlPolicy = InvokeUCSFunction -functionName "Add-UcsSolPolicy" -failureMsg "Failed to create serial over LAN policy." -cmdParams @{ Ucs = $ucs; Org = $rootOrg; Name = $solPolicyName }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    return $success
}


<#
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsFirmwareComputeHostPack -BladeBundleVersion "4.2(1m)B" -Name "test" -OverrideDefaultExclusion "yes" -RackBundleVersion "4.2(1m)C"
    $mo_1 = $mo | Add-UcsFirmwareExcludeServerComponent -ModifyPresent -ServerComponent "local-disk"
    Complete-UcsTransaction
#>

function CreateHostFirmarePackage
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [String] $fwPackageName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [String] $bladeBundleVersion,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNull()]
        [String] $rackBundleVersion
    )

    $success = $true

    ReportNotice "`tCreating host firmware package..."
    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}

    if ($success)
    {
        $success, $null = InvokeUCSFunction -functionName "Start-UcsTransaction" -failureMsg "Failed to start UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
        if ($success)
        {
            $success, $fwPackage = InvokeUCSFunction -functionName "Add-UcsFirmwareComputeHostPack" -failureMsg "Failed to create host firmware package." -cmdParams @{ Ucs = $ucs; Org = $rootOrg; Name = $fwPackageName; BladeBundleVersion = $bladeBundleVersion; RackBundleVersion = $rackBundleVersion; OverrideDefaultExclusion = "yes" }

            if ($success)
            {
                $success, $mo = InvokeUCSFunction "Add-UcsFirmwareExcludeServerComponent" -failureMsg ("Failed to modify server component local-disk for host firmware package: {0}" -f @($fwPackageName)) -cmdParams @{Ucs = $ucs; FirmwareComputeHostPack = $fwPackage; ServerComponent = "local-disk"; ModifyPresent = $true }
            } `
            else # NOT ($success)
            {
                # Nothing.
            }
        } `
        else # NOT ($success)
        {
            # Nothing.
        }

        if ($success)
        {
            $success, $mo = InvokeUCSFunction -functionName "Complete-UcsTransaction" -failureMsg "Failed to commit UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
        } `
        else # NOT ($success)
        {
            ReportError ("Failed to create host firmware package {0}.  UCS transaction rolled back." -f @($fwPackageName))
            $success, $null = InvokeUCSFunction -functionName "Undo-UcsTransaction" -failureMsg "Failed to rollback UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull

            # No matter the success of rolling back the transaction, make sure $success is $false
            $success = $false
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    return $success
}

function CreateServiceTemplates
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [String] $serviceTemplateName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [String] $biosProfileName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNull()]
        [String] $bootPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNull()]
        [String] $hostFwPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [ValidateNotNull()]
        [String] $identPoolName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=6)]
        [ValidateNotNull()]
        [String] $maintPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=7)]
        [ValidateNotNull()]
        [String] $powerPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=8)]
        [ValidateNotNull()]
        [String] $ScrubPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=9)]
        [ValidateNotNull()]
        [String] $SolPolicyName
    )

    $success = $true

    ReportNotice ("`tCreating service template {0}..." -f @($serviceTemplateName))
    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{Ucs=$ucs}

    if ($success)
    {
        $success, $null = InvokeUCSFunction -functionName "Start-UcsTransaction" -failureMsg "Failed to start UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
        if ($success)
        {
            $success, $serviceTemplate = InvokeUCSFunction -functionName "Add-UcsServiceProfile" -failureMsg "Failed to create host firmware package." -cmdParams  @{ Ucs = $ucs; Org = $rootOrg; Name = $serviceTemplateName; BiosProfileName = $biosProfileName; BootPolicyName = $bootPolicyName; HostFwPolicyName = $hostFwPolicyName; IdentPoolName = $identPoolName; MaintPolicyName = $maintPolicyName; PowerPolicyName = $powerPolicyName; ScrubPolicyName = $scrubPolicyName; SolPolicyName = $solPolicyName; Type = "updating-template" }

<# Right Here #>


            if ($success)
            {
                $success, $mo = InvokeUCSFunction "Add-UcsFirmwareExcludeServerComponent" -failureMsg ("Failed to modify server component local-disk for host firmware package: {0}" -f @($fwPackageName)) -cmdParams @{Ucs = $ucs; FirmwareComputeHostPack = $fwPackage; ServerComponent = "local-disk"; ModifyPresent = $true }
            } `
            else # NOT ($success)
            {
                # Nothing.
            }
        } `
        else # NOT ($success)
        {
            # Nothing.
        }

        if ($success)
        {
            $success, $mo = InvokeUCSFunction -functionName "Complete-UcsTransaction" -failureMsg "Failed to commit UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
        } `
        else # NOT ($success)
        {
            ReportError ("Failed to create service template profile {0}.  UCS transaction rolled back." -f @($serviceTemplateName))
            $success, $null = InvokeUCSFunction -functionName "Undo-UcsTransaction" -failureMsg "Failed to rollback UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull

            # No matter the success of rolling back the transaction, make sure $success is $false
            $success = $false
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    return $success
}


function p1()
{
    $rootOrg = Get-UcsOrg -Ucs $ch3UCS -Level "root"
    $serviceTemplate = Add-UcsServiceProfile -Ucs $ch3UCS -Org $rootOrg -BiosProfileName $rdcConfigurationData.BIOSPolicy.Name -BootPolicyName $rdcConfigurationData.bootPolicyName -HostFwPolicyName "Latest" -IdentPoolName "CH3-UCS01-UUID" -MaintPolicyName $rdcConfigurationData.maintenancePolicyName -Name "VMWare.Int.M2" -PowerPolicyName $rdcConfigurationData.powerControlPolicyName -ScrubPolicyName $rdcConfigurationData.scrubPolicyName -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName -Type "updating-template"
    $mo_1 = Add-UcsLogicalStorageProfileBinding -Ucs $ch3UCS -ServiceProfile $serviceTemplate -StorageProfileName $rdcConfigurationData.storageProfileName
    $mo_2 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -Name "INT.VMNMGT.BA" -NwCtrlPolicyName "" -NwTemplName "INT.VMNMGT.BA" -Order "2" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
    $mo_3 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "INT.MGTVMN.AB" -NwTemplName "INT.MGTVMN.AB" -Order "1" -SwitchId "A-B"
    $mo_4 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -Name "INT.STG.BX" -NwCtrlPolicyName "" -NwTemplName "INT.STG.BX" -Order "4" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
    $mo_5 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "INT.STG.AX" -NwTemplName "INT.STG.AX" -Order "3"
    $mo_6 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 1500 -Name "INT.GST.BX" -NwCtrlPolicyName "" -NwTemplName "INT.GST.BX" -Order "6" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
    $mo_7 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "INT.GST.AX" -NwTemplName "INT.GST.AX" -Order "5"
    $mo_8 = Add-UcsVnicFcNode -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Addr "pool-derived" -IdentPoolName "node-default"
    $mo_9 = Add-UcsVnicDefBeh -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Action "none" -Descr "" -Name "" -NwTemplName "" -PolicyOwner "local" -Type "vhba"
    $mo_10 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "1" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_11 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "2" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_12 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "3" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_13 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "4" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_14 = $serviceTemplate | Set-UcsServerPower -State "admin-up"


    $serviceTemplate = Add-UcsServiceProfile -Ucs $ch3UCS -Org $rootOrg -BiosProfileName $rdcConfigurationData.BIOSPolicy.Name -BootPolicyName $rdcConfigurationData.bootPolicyName -HostFwPolicyName "Latest" -IdentPoolName "CH3-UCS01-UUID" -MaintPolicyName $rdcConfigurationData.maintenancePolicyName -Name "VMWare.DMZ.M2" -PowerPolicyName $rdcConfigurationData.powerControlPolicyName -ScrubPolicyName $rdcConfigurationData.scrubPolicyName -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName -Type "updating-template"
    $mo_1 = Add-UcsLogicalStorageProfileBinding -Ucs $ch3UCS -ServiceProfile $serviceTemplate -StorageProfileName $rdcConfigurationData.storageProfileName
    $mo_2 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -Name "DMZ.VMNMGT.BA" -NwCtrlPolicyName "" -NwTemplName "DMZ.VMNMGT.BA" -Order "2" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
    $mo_3 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "DMZ.MGTVMN.AB" -NwTemplName "DMZ.MGTVMN.AB" -Order "1" -SwitchId "A-B"
    $mo_4 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 9000 -Name "DMZ.STG.BX" -NwCtrlPolicyName "" -NwTemplName "DMZ.STG.BX" -Order "4" -PinToGroupName "" -QosPolicyName $rdcConfigurationData.jumboFramesQosPolicyName -StatsPolicyName "default" -SwitchId "A"
    $mo_5 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "DMZ.STG.AX" -NwTemplName "DMZ.STG.AX" -Order "3"
    $mo_6 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Addr "derived" -AdminCdnName "" -AdminHostPort "ANY" -AdminVcon "any" -CdnPropInSync "yes" -CdnSource "vnic-name" -IdentPoolName $rdcConfigurationData.macPool.Name -Mtu 1500 -Name "DMZ.GST.BX" -NwCtrlPolicyName "" -NwTemplName "DMZ.GST.BX" -Order "6" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
    $mo_7 = Add-UcsVnic -Ucs $ch3UCS -ServiceProfile $serviceTemplate -AdaptorProfileName "VMWare" -Name "DMZ.GST.AX" -NwTemplName "DMZ.GST.AX" -Order "5"
    $mo_8 = Add-UcsVnicFcNode -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Addr "pool-derived" -IdentPoolName "node-default"
    $mo_9 = Add-UcsVnicDefBeh -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Action "none" -Descr "" -Name "" -NwTemplName "" -PolicyOwner "local" -Type "vhba"
    $mo_10 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "1" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_11 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "2" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_12 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "3" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_13 = Add-UcsFabricVCon -Ucs $ch3UCS -ServiceProfile $serviceTemplate -ModifyPresent -Fabric "NONE" -Id "4" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
    $mo_14 = $serviceTemplate | Set-UcsServerPower -State "admin-up"
}

<#
# Create LDAP provider...

    Start-UcsTransaction
    $mo = Add-UcsLdapProvider -Basedn "DC=powereng,DC=com" -EnableSSL "yes" -FilterValue "sAMAccountName=`$userid" -Key "THeKUTh33u" -Name "ch3-dc01.powereng.com" -Order "1" -Rootdn "CN=srvcldap,OU=Service Accounts,DC=powereng,DC=com" -Vendor "MS-AD"
    $mo_1 = $mo | Add-UcsLdapGroupRule -ModifyPresent -Authorization "enable" -Descr "" -Name "" -TargetAttr "memberOf" -Traversal "recursive" -UsePrimaryGroup "no"
    Complete-UcsTransaction
#>

function CreateLDAPProvider
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [String] $ldapProviderName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [String] $baseDN,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNull()]
        [String] $rootDN,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNull()]
        [String] $bindKey,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [int32] $order
    )

    $success = $true

    ReportNotice ("`tCreating LDAP provider: {0}..." -f @($ldapProviderName))

    $success, $null = InvokeUCSFunction -functionName "Start-UcsTransaction" -failureMsg "Failed to start UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
    if ($success)
    {
        $success, $ldapProvider = InvokeUCSFunction -functionName "Add-UcsLdapProvider" -failureMsg "Failed to create LDAP provider." -cmdParams @{ Ucs = $ucs; Name = $ldapProviderName; Basedn = $baseDN; Rootdn = $rootDN; EnableSSL = "yes"; FilterValue = "sAMAccountName=`$userid"; Vendor = "MS-AD"; Order = $order; Key = $bindKey }

        if ($success)
        {
            $success, $groupRule = InvokeUCSFunction "Add-UcsLdapGroupRule" -failureMsg ("Failed to modify LDAP provider: {0}" -f @($ldapProviderName)) -cmdParams @{Ucs = $ucs; LdapProvider = $ldapProvider; ModifyPresent = $true; Authorization = "enable"; Descr = ""; Name = ""; TargetAttr = "memberOf"; Traversal = "recursive"; UsePrimaryGroup = "no" }

            if ($success)
            {
                $success, $ldapGlobalConfig = InvokeUCSFunction "Get-UcsLdapGlobalConfig" -failureMsg "Failed to retrieve LDAP global config." -cmdParams @{ UCS = $ucs }
                if ($success)
                {
                    $success, $ldapProviders = InvokeUCSFunction "Get-UcsLdapProvider" -failureMsg "Failed to retrieve LDAP providers." -cmdParams @{ UCS = $ucs }

                    if (-not ($ldapProviders -is [Array]))
                    {
                        $ldapProviders = @($ldapProviders)
                    } `
                    else # NOT (-not ($ldapProviders -is [Array]))
                    {
                        # Nothing.
                    }

                    $ldapProviders = @($ldapProviders | Sort-Object Order)
                    if ($success)
                    {
                        $success, $ldapProviderGroup = InvokeUCSFunction "Add-UcsProviderGroup" -failureMsg "Failed to create LDAP provider group: POWERENG DCs" -cmdParams @{ UCS = $ucs; Name = "POWERENG DCs"; LdapGlobalConfig = $ldapGlobalConfig }

                        # Add the providers to the provider group
                        $a = 0
                        while(($a -lt $ldapProviders.Length) -and $success)
                        {
                            $success, $null = InvokeUCSFunction "Add-UcsProviderReference" -failureMsg ("Failed to add provider reference: {0} to {1}." -f @($ldapProviders[$a].Name, $ldapProviderGroup.Name)) -cmdParams @{Ucs = $ucs; ProviderGroup = $ldapProviderGroup; ModifyPresent = $true; Descr = ""; Name = $ldapProviders[$a].Name; Order = $ldapProviders[$a].Order }
                            $a++
                        }
                    } `
                    else # NOT ($success)
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($success)
                {
                    # Nothing.
                }
            } `
            else # NOT ($success)
            {
                # Nothing.
            }
        } `
        else # NOT ($success)
        {
            # Nothing.
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    if ($success)
    {
        $success, $mo = InvokeUCSFunction -functionName "Complete-UcsTransaction" -failureMsg "Failed to commit UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull
    } `
    else # NOT ($success)
    {
        ReportError ("Failed to LDAP provider {0}.  UCS transaction rolled back." -f @($ldapProviderName))
        $success, $null = InvokeUCSFunction -functionName "Undo-UcsTransaction" -failureMsg "Failed to rollback UCS transaction." -cmdParams @{Ucs=$ucs} -noErrorOnNull

        # No matter the success of rolling back the transaction, make sure $success is $false
        $success = $false
    }

    return $success
}


<#
function GenericShellFunction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $true

    ReportNotice "`tBLAH BLAH BLAH"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
            }
            catch
            {
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}
#>
