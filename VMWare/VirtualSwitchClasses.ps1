
class clsUplinkVLAN
{
    [int32] $vlanID
    [string] $name

    clsUplinkVLAN([string] $name, [int32] $vlanID)
    {
        $this.name = $name
        $this.vlanID = $vlanID
    }
}   # clsUplinkVLAN

class clsUplinkHost
{
    [string] $vmNICName
    [string] $vmHostName

    clsUplinkHost([string] $vmHostName, [string] $vmNICName)
    {
        $this.vmHostName = $vmHostName
        $this.vmNICName = $vmNICName
    }
}   # clsUplinkHost

class clsUplink
{
    [string] $uplinkName
    [string] $nicName
    [System.Collections.Generic.List[clsUplinkVLAN]] $vlans
    [System.Collections.Generic.List[clsUplinkHost]] $uplinkHosts

    clsUplink([string] $uplinkName, [string] $nicName)
    {
        $this.uplinkName = $uplinkName
        $this.nicName = $nicName
        $this.vlans = [System.Collections.Generic.List[clsUplinkVLAN]]::new()
        $this.uplinkHosts = [System.Collections.Generic.List[clsUplinkHost]]::new()
    }

    [clsUplinkVLAN[]] VLANsWithID([int32] $vlanID)
    {
        $retval = @($this.vlans | Where-Object { $_.vlanID -eq $vlanID })

        return $retval
    }

    [bool] SupportsVLAN([int32] $vlanID)
    {
        $matchingVLANS = $this.VLANsWithID($vlanID)

        return ($matchingVLANS.Length -gt 0)
    }

    [clsUplinkVLAN] AddVLAN([string] $name, [int32] $vlanID)
    {
        $newVLAN = $null
        $existingVLANs = $this.VLANsWithID($vlanID)
        if ($existingVLANs.Length -eq 0)
        {
            # TRUE
            $newVLAN = [clsUplinkVLAN]::new($name, $vlanID)
            $this.vlans.Add($newVLAN)
        }
        else # NOT ($null -eq $existingVLANs)
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Possible duplicate VLANs:")
            foreach($vl in $existingVLANs)
            {
                Write-Host -ForegroundColor Red ("`t{0}:{1}" -f @($vl.name, $vl.vlanID))
            }
        }

        return $newVLAN
    }

    [clsUplinkHost] AddUplinkHost([string] $vmHostName, [string] $vmNICName)
    {
        $newUplinkHost = $null

        $matchingUplinkHosts = $this.uplinkHosts | Where-Object { ($_.vmHostName -eq $vmHostName) -and ($_.vmNICName -eq $vmNICName) }
        if($null -eq $matchingUplinkHosts)
        {
            # TRUE

            $newUplinkHost = [clsUplinkHost]::new($vmHostName, $vmNICName)
            $this.uplinkHosts.Add($newUplinkHost)
        }
        else # NOT ($null -eq $matchingUplinkHost)
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Possible duplicate host uplinks:")
            foreach($uh in $matchingUplinkHosts)
            {
                Write-Host -ForegroundColor Red ("`t{0}:{1}" -f @($uh.vmHostName, $uh.vmNICName))
            }
        }

        return $newUplinkHost
    }
}   # clsUplink

class clsVirtualPortGroupHostVMKDefinition
{
    [string] $vmkName
    [int32] $mtu
    [string] $vmHostName
    [string] $portGroupName
    [string] $ipAddress
    [string] $subnetMask
    [bool] $mgmtEnabled
    [bool] $vMotionEnabled

    # If $mtu -eq -1, then use the MTU of the
    clsVirtualPortGroupHostVMKDefinition([string] $vmHostName, [string] $portGroupName, [string] $vmkName, [string] $ipAddress, [string] $subnetMask, [int32] $mtu=-1, [bool] $mgmtEnabled=$false, [bool] $vMotionEnabled=$false)
    {
        $this.vmkName = $vmkName
        $this.mtu = $mtu
        $this.vmHostName = $vmHostName
        $this.portGroupName = $portGroupName
        $this.mgmtEnabled = $mgmtEnabled
        $this.vMotionEnabled = $vMotionEnabled

        try
        {
            $newIP = [System.Net.IPAddress]::Parse($ipAddress)
            $this.ipAddress = $newIP.IPAddressToString
        }
        catch
        {
            throw
        }
        try
        {
            $newIP = [System.Net.IPAddress]::Parse($subnetMask)
            $this.subnetMask = $newIP.IPAddressToString
        }
        catch
        {
            throw
        }
    }
}   # clsVirtualPortGroupHostVMKDefinition

class clsVirtualPortGroupHostVMK
{
    [string] $vmkName
    [int32] $mtu
    [string] $vmHostName
    [string] $ipAddress
    [string] $subnetMask
    [bool] $mgmtEnabled
    [bool] $vMotionEnabled

    # If $mtu -eq -1, then use the MTU of the
    clsVirtualPortGroupHostVMK([string] $vmHostName, [string] $vmkName, [string] $ipAddress, [string] $subnetMask, [int32] $mtu=-1, [bool] $mgmtEnabled=$false, [bool] $vMotionEnabled=$false)
    {
        $this.vmkName = $vmkName
        $this.mtu = $mtu
        $this.vmHostName = $vmHostName
        $this.mgmtEnabled = $mgmtEnabled
        $this.vMotionEnabled = $vMotionEnabled

        try
        {
            $newIP = [System.Net.IPAddress]::Parse($ipAddress)
            $this.ipAddress = $newIP.IPAddressToString
        }
        catch
        {
            throw
        }
        try
        {
            $newIP = [System.Net.IPAddress]::Parse($subnetMask)
            $this.subnetMask = $newIP.IPAddressToString
        }
        catch
        {
            throw
        }
    }
}   # clsVirtualPortGroupHostVMK

class clsVirtualPortGroupDefinition
{
    [int32] $vlanID
    [string] $name
    [string] $portBinding
    [string[]] $activeUplinkNames
    [string[]] $standbyUplinkNames

    clsVirtualPortGroupDefinition([string] $name, [int32] $vlanID, [string] $portBinding, [string[]] $activeUplinkNames, [string[]] $standbyUplinkNames)
    {
        $this.vlanID = $vlanID
        $this.name = $name
        $this.portBinding = $portBinding
        $this.activeUplinkNames = $activeUplinkNames
        $this.standbyUplinkNames = $standbyUplinkNames
    }
}

class clsVirtualPortGroup
{
    [int32] $vlanID
    [string] $name
    [string] $portBinding
    [System.Collections.Generic.List[clsUplink]] $activeUplinks
    [System.Collections.Generic.List[clsUplink]] $standbyUplinks
    [System.Collections.Generic.List[clsUplink]] $unusedUplinks
    [System.Collections.Generic.List[[clsVirtualPortGroupHostVMK]]] $hostVMKs

    clsVirtualPortGroup([string] $name, [int32] $vlanID, [string] $portBinding)
    {
        $this.vlanID = $vlanID
        $this.name = $name
        $this.portBinding = $portBinding
        $this.activeUplinks = [System.Collections.Generic.List[clsUplink]]::new()
        $this.standbyUplinks = [System.Collections.Generic.List[clsUplink]]::new()
        $this.unusedUplinks = [System.Collections.Generic.List[clsUplink]]::new()
        $this.hostVMKs = [System.Collections.Generic.List[[clsVirtualPortGroupHostVMK]]]::new()
    }

    [clsVirtualPortGroupHostVMK] AddHostVMK([string] $vmHostName, [string] $vmkName, [string] $ipAddress, [string] $subnetMask, [int32] $mtu=-1, [bool] $mgmtEnabled=$false, [bool] $vMotionEnabled=$false)
    {
        $newVMK = $null
        $matchingVMKs = $this.hostVMKs | Where-Object { ($_.vmkName -eq $vmkName) -and ($_.vmHostName -eq $vmHostName) -and ($_.ipAddress -eq $ipAddress) }
        if ($null -eq $matchingVMKs)
        {
            # TRUE
            try
            {
                $newVMK = [clsVirtualPortGroupHostVMK]::new($vmHostName, $vmKName, $ipAddress, $subnetMask, $mtu, $mgmtEnabled, $vMotionEnabled)
                $this.hostVMKs.Add($newVMK)
            }
            catch
            {
                $newVMK = $null
            }
        }
        else # NOT ($null -eq $matchingVMKs)
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Possible duplicate vmk(s):")
            foreach($vmk in $matchingVMKs)
            {
                Write-Host -ForegroundColor Red ("`t{0}:{1}" -f @($vmk.vmHostName, $vmk.ipAddress))
            }
        }

        return $newVMK
    }

    [void] RemoveUplinkFromUnused([clsUplink] $uplink)
    {
        if ($this.IsUnusedUplink($uplink))
        {
            # TRUE

            # Remove uplink from the list of unused uplinks
            foreach($ul in @($this.unusedUplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
            {
                [void] $this.unusedUplinks.Remove($ul)
            }
        }
        else # NOT ($this.IsUnusedUplink($uplink))
        {
            # FALSE

            # Nothing.
        }
    }

    [bool] IsUnusedUplink([clsUplink] $uplink)
    {
        $retval = $false

        $retval = ($null -ne ($this.unusedUplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
        return $retval
    }

    [bool] IsStandByUplink([clsUplink] $uplink)
    {
        $retval = $false

        $retval = ($null -ne ($this.standbyUplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
        return $retval
    }

    [bool] IsActiveUplink([clsUplink] $uplink)
    {
        $retval = $false

        $retval = ($null -ne ($this.activeUplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
        return $retval
    }

    [bool] AddActiveUplink([clsUplink] $uplink)
    {
        $retval = $false

        if (-not $this.IsActiveUplink($uplink))
        {
            # TRUE

            if (-not $this.IsStandByUplink($uplink))
            {
                # TRUE

                if($uplink.SupportsVLAN($this.vlanID))
                {
                    $this.activeUplinks.Add($uplink)
                    $this.RemoveUplinkFromUnused($uplink)
                    $retval = $true
                }
                else #
                {
                    Write-Host -ForegroundColor Red ("ERROR: Uplink {0} does not support VLAN: {1}" -f @($uplink.uplinkName, $this.vlanID))
                }
            }
            else # NOT (-not $this.IsStandByUplink($uplink))
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: {0} is already a standby uplink." -f @($uplink.nicName))
            }
        }
        else # NOT (-not $this.IsActiveUplink($uplink))
        {
            # FALSE

            Write-Host -ForegroundColor Yellow ("WARNING: {0} is already an active uplink." -f @($uplink.nicName))
        }

        return $retval
    }

    [bool] AddStandByUplink([clsUplink] $uplink)
    {
        $retval = $false

        if (-not $this.IsActiveUplink($uplink))
        {
            # TRUE

            if (-not $this.IsStandByUplink($uplink))
            {
                # TRUE

                if($uplink.SupportsVLAN($this.vlanID))
                {
                    $this.standbyUplinks.Add($uplink)
                    $this.RemoveUplinkFromUnused($uplink)
                    $retval = $true
                }
                else #
                {
                    Write-Host -ForegroundColor Red ("ERROR: Uplink {0} does not support VLAN: {1}" -f @($uplink.uplinkName, $this.vlanID))
                }
            }
            else # NOT (-not $this.IsStandByUplink($uplink))
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: {0} is already a standby uplink." -f @($uplink.nicName))
            }
        }
        else # NOT (-not $this.IsActiveUplink($uplink))
        {
            # FALSE

            Write-Host -ForegroundColor Yellow ("WARNING: {0} is already an active uplink." -f @($uplink.nicName))
        }

        return $retval
    }

    [bool] AddUnusedUplink([clsUplink] $uplink)
    {
        $retval = $false

        if (-not $this.IsActiveUplink($uplink))
        {
            # TRUE

            if (-not $this.IsStandByUplink($uplink))
            {
                # TRUE

                $this.unusedUplinks.Add($uplink)
                $retval = $true
            }
            else # NOT (-not $this.IsStandByUplink($uplink))
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: {0} is already a standby uplink." -f @($uplink.nicName))
            }
        }
        else # NOT (-not $this.IsActiveUplink($uplink))
        {
            # FALSE

            Write-Host -ForegroundColor Yellow ("WARNING: {0} is already an active uplink." -f @($uplink.nicName))
        }

        return $retval
    }
}   # clsVirtualPortGroup


class clsDVS
{
    [string] $name
    [string] $container
    [int32] $mtu
    [System.Collections.Generic.List[String]] $vmHostNames
    [System.Collections.Generic.List[clsUplink]] $uplinks
    [System.Collections.Generic.List[clsVirtualPortGroup]] $portGroups

    clsDVS([string] $name, [string] $container, [int32] $mtu)
    {
        $this.name = $name
        $this.container = $container
        $this.mtu = $mtu
        $this.uplinks = [System.Collections.Generic.List[clsUplink]]::new()
        $this.portGroups = [System.Collections.Generic.List[clsVirtualPortGroup]]::new()
        $this.vmHostNames = [System.Collections.Generic.List[String]]::new()
    }

    [bool] AddVMHost([string] $vmHostName)
    {
        $retval = $false
        if (-not [String]::IsNullOrEmpty($vmHostName))
        {
            # TRUE

            $i = $this.vmHostNames.BinarySearch($vmHostName)
            if($i -lt 0)
            {
                $this.vmHostNames.Insert(-bnot $i, $vmHostName)
                $retval = $true
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($vmHostName))
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Missing VM host name in {0}." -f @($MyInvocation.MyCommand.Name))
        }

        return $retval
    }

    [bool] AddUplink([clsUplink] $uplink)
    {
        $retval = $false

        if ($null -eq ($this.uplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
        {
            # TRUE

            $this.uplinks.Add($uplink)

            # Add the new uplink to all existing port group's unused uplinks
            $a = 0
            while($a -lt $this.portGroups.Count)
            {
                if(-not $this.portGroups[$a].IsActiveUplink($uplink))
                {
                    if(-not $this.portGroups[$a].IsStandByUplink($uplink))
                    {
                        if(-not $this.portGroups[$a].IsUnusedUplink($uplink))
                        {
                            [void] $this.portGroups[$a].AddUnusedUplink($uplink)
                        }
                    }
                }

                $a++
            }
            $retval = $true
        }
        else # NOT ($null -eq ($this.uplinks | Where-Object { $_.nicName -eq $uplink.nicName}))
        {
            # FALSE

            Write-Host -ForegroundColor Yellow ("WARNING: {0} is already an uplink on this switch." -f @($uplink.nicName))
        }

        return $retval
    }

    [clsUplink] NewUplink([string] $uplinkName, [string] $nicName)
    {
        $newUplink = [clsUplink]::new($uplinkName, $nicName)
        if(-not $this.AddUplink($newUplink))
        {
            $newUplink = $null
        }

        return $newUplink
    }

    [bool] AddPortGroup([clsVirtualPortGroup] $portGroup)
    {
        $retval = $false

        if ($null -eq ($this.portGroups | Where-Object { ($_.vlanID -eq $portGroup.vlanID) -and ($_.name -eq $portGroup.name) -and ($_.portBinding -eq $portGroup.portBinding) }))
        {
            # TRUE

            $this.portGroups.Add($portGroup)
            $retval = $true
        }
        else # NOT ($null -eq ($this.portGroups | Where-Object { ($_.vlanID -eq $portGroup.vlanID) -and ($_.name -eq $portGroup.name) -and ($_.portBinding -eq $portGroup.portBinding) }))
        {
            # FALSE

            Write-Host -ForegroundColor Yellow ("WARNING: {0}:{1}:{2} is already a portgroup on this switch." -f @($portGroup.vlanID, $portGroup.name, $portGroup.portBinding))
        }

        return $retval
    }

    [System.Collections.Generic.List[clsUplink]] GetUplinksByName([string[]] $uplinkNames)
    {
        $testUplinkNames = @($uplinkNames | Select-Object -Unique)
        $testUplinks = [System.Collections.Generic.List[clsUplink]]::new()
        $goodToGo = $true
        $a = 0
        while($goodToGo -and ($a -lt $testUplinkNames.Length))
        {
            $tUplinks = $this.uplinks | Where-Object { $_.uplinkName -eq $testUplinkNames[$a] }
            if($null -ne $tUplinks)
            {
                foreach($uplink in $tUplinks)
                {
                    if($null -eq ($testUplinks | Where-Object { $_.uplinkName -eq $uplink.uplinkName }))
                    {
                        $testUplinks.Add($uplink)
                    }
                    else #
                    {
                        Write-Host -ForegroundColor YELLOW ("WARNING: Duplicate uplink {0} found.  Ignoring." -f @($uplink.uplinkName))
                    }
                }
            }
            else #
            {
                Write-Host -ForegroundColor Red ("ERROR: {0} contains no uplinks named {1}." -f @($this.Name, $testUplinkNames[$a]))
                $goodToGo = $false
            }
            $a++
        }

        if(-not $goodToGo)
        {
            $testUplinks = $null
        }

        return $testUplinks
    }

    [clsVirtualPortGroup] NewPortGroup([string] $name, [int32] $vlanID, [string] $portBinding, [string[]] $activeUplinkNames=$null, [string[]] $standbyUplinkNames=$null)
    {
        $newVPG = $null
        $activeUplinks = $this.GetUplinksByName($activeUplinkNames)
        $standByUplinks = $this.GetUplinksByName($standbyUplinkNames)

        if ($null -ne $activeUplinks)
        {
            # TRUE

            if ($null -ne $standByUplinks)
            {
                # TRUE

                $newVPG = [clsVirtualPortGroup]::new($name, $vlanID, $portBinding)

                if($this.AddPortGroup($newVPG))
                {
                    # Add all uplinks to the new port group
                    $a = 0
                    while($a -lt $this.uplinks.Count)
                    {
                        if($null -ne ($activeUplinks | Where-Object { $_.uplinkName -eq $this.uplinks[$a].uplinkName}))
                        {
                            $newVPG.AddActiveUplink($this.uplinks[$a])
                        }
                        elseif ($null -ne ($standByUplinks | Where-Object { $_.uplinkName -eq $this.uplinks[$a].uplinkName}))
                        {
                            $newVPG.AddStandByUplink($this.uplinks[$a])
                        }
                        else
                        {
                            $newVPG.AddUnusedUplink($this.uplinks[$a])
                        }

                        $a++
                    }
                }
                else #
                {
                    $newVPG = $null
                }
            }
            else # NOT ($null -ne $standByUplinks)
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: Invalid standby uplink(s) specified: {0}" -f @([String]::Join(", ", $standbyUplinkNames)))
            }
        }
        else # NOT ($null -ne $activeUplinks)
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Invalid active uplink(s) specified: {0}" -f @([String]::Join(", ", $activeUplinkNames)))
        }

        return $newVPG
    }
}   # clsDVS

class clsUplinkMapping
{
    [string] $uplinkName
    [string] $vNICName

    clsUplinkMapping([string] $uplinkName, [string] $vNICName)
    {
        $this.uplinkName = $uplinkName
        $this.vNICName = $vNICName
    }
}   # clsUplinkMapping[string] $uplinkName
