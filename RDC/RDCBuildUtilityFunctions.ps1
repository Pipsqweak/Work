#region General Utility Functions
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
#endregion

#region UCS Utility Functions
function ConnectToUCS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
        [ValidateNotNullOrEmpty()]
        [String] $rdcPrefix,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false)]
        [Switch] $Reconnect
    )

    $rdcConfigurationDataFilename = ".\RDC\configs\UCS\{0}-rdc-ucs.json" -f @($rdcPrefix)

    $configData = Get-Content -Path $rdcConfigurationDataFilename | ConvertFrom-Json

    # Need to fix up the embedded certificate chain
    $configData.pki_ca_chain = $configData.pki_ca_chain -join "`n"

    # Connect to the UCS manager for the RDC...
    $rdcUCSName = ("{0}UCS" -f @($rdcPrefix)).ToUpper()

    if(($null -eq $Global:ucsManagers) -or (-not $Global:ucsManagers.ContainsKey($rdcUCSName)) -or $Reconnect)
    {
        if($null -ne $Global:ucsManagers)
        {
            if($Global:ucsManagers.ContainsKey($rdcUCSName))
            {
                $Global:ucsManagers.Remove($rdcUCSName)
                $Global:credsInitialized = $false
            }
        }
        ConnectTo prod,$rdcPrefix,ucs
    }

    # Set the UCS Manager for the configuration
    if(($null -ne $Global:ucsManagers) -and ($Global:ucsManagers.ContainsKey($rdcUCSName)))
    {
        $configData.ucsManager = $Global:ucsManagers[$rdcUCSName]
    }

    return $configData
}

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

function SetEquipmentGlobalPolicy
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $true

    ReportNotice "`tSetting equipment global policy"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
<#
            try
            {
                Start-UcsTransaction -Ucs $ucs -ErrorAction Stop
#>
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

<#
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
#>
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

function DeleteSANPools
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

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

function DeleteDefaultMACPool
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

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
<#
                    try
                    {
                        [void] (Start-UcsTransaction -Ucs $ucs -ErrorAction Stop)
#>
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
<#
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
#>
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

    $success = $true

    ReportNotice "`tCreating MAC address pool"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
<#
            try
            {
                [void] (Start-UcsTransaction -Ucs $ucs -ErrorAction Stop)
#>
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
<#
                                try
                                {
                                    [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                                }
                                catch
                                {
                                    ReportError ("`tFailed create MAC address pool {0}.  Complete-UcsTransaction threw an exception." -f @($macPoolDefinition.Name))
                                    $success = $false
                                }
#>
                            }
                        }
                        catch
                        {
                            ReportError ("`tFailed to add member block [{0} - {1}] to MAC address pool {2}.  Add-UcsMacMemberBlock threw an exception." -f @($macPoolDefinition.From, $macPoolDefinition.To, $macPoolDefinition.Name))
                            $success = $false
<#
                            try
                            {
                                [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                            }
                            catch
                            {
                                ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                                $success = $false
                            }
#>
                        }
                    } `
                    else # NOT ($null -ne $macPool)
                    {
                        ReportError ("`tFailed to create MAC address pool {0}.  Add-UcsMacPool return `$null." -f @($macPoolDefinition.Name))
                        $success = $false
<#
                        try
                        {
                            [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                        }
                        catch
                        {
                            ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                            $success = $false
                        }
#>
                    }
                }
                catch
                {
                    ReportError ("`tFailed to create MAC address pool {0}.  Add-UcsMacPool threw an exception." -f @($macPoolDefinition.Name))
                    $success = $false
<#
                    try
                    {
                        [void] (Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                    }
                    catch
                    {
                        ReportError "`tFailed to undo UCS transaction.  Undo-UcsTransaction threw an exception."
                        $success = $false
                    }
#>
                }
<#
            }
            catch
            {
                ReportError ("`tFailed create MAC address pool {0}.  Start-UcsTransaction threw an exception." -f @($macPoolDefinition.Name))
                $success = $false
            }
#>
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

    $success = $false
#    $transactionStarted = $false

    ReportNotice ("Creating disk group configuration policy {0} on {1}." -f @($policyName, $ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $existingPolicy = Get-UcsLogicalStorageDiskGroupConfigPolicy -Ucs $ucs -Org $rootOrg -Name $policyName -ErrorAction Stop

            if ($null -eq $existingPolicy)
            {
<#
                try
                {
                    [void] (Start-UcsTransaction -Ucs $ucs)
                    $transactionStarted = $true
#>
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
<#
                }
                catch
                {
                    ReportError "`tFailed to start UCS transaction."
                }
#>
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

<#
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
#>

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

    $transactionStarted = $false
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
                        $certReq = Add-UcsCertRequest -Ucs $ucs -KeyRing $keyRing -Country $country -Dns $ucs.Name.ToLower() -Locality $location -OrgName "POWER Engineers, Inc." -OrgUnitName "Operations IT" -State $state -SubjName $ucs.Name.ToLower().Replace(".powereng.com","") -ErrorAction Stop
                        if ($null -ne $certReq)
                        {
                            try
                            {
                                <#
                                    NOTE:
                                        Seems there needs to be a delay in here...
                                #>
                                ReportNotice ("`tPausing for cerificate request to be generated...")
                                $sw = [System.Diagnostics.Stopwatch]::new()
                                $sw.Start()
                                do
                                {
                                    $certReq = Get-UcsCertRequest -Ucs $ucs -KeyRing $keyRing -ErrorAction Stop
                                    if(($null -eq $certReq) -or ([String]::IsNullOrEmpty($certReq.Req)))
                                    {
                                        Start-Sleep -Seconds 5
                                    }
                                } until((($null -ne $certReq) -and (-not [String]::IsNullOrEmpty($certReq.Req))) -or ($sw.Elapsed.TotalSeconds -ge 90))

                                if ($null -ne $certReq)
                                {
                                    if (-not [String]::IsNullOrEmpty($certReq.Req))
                                    {
                                        try
                                        {
                                            $requestFileName = "{0}.req" -f @($keyRing.Name)
                                            $certReq.Req | Out-File -FilePath $requestFileName -Encoding ascii -ErrorAction Stop
                                            $certReq.Req | Set-Clipboard
                                            ReportNotice ("`tCertificate request for keyring {0} saved to {1}, and copied to clipboard." -f @($keyRing.Name, $requestFileName))
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
<#
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
#>
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
#    $transactionStarted = $false

    ReportNotice ("Updating default maintenance policy {0}." -f @($ucs.Name))
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        try
        {
            $defPolicy = Get-UcsMaintenancePolicy -Ucs $ucs -Org $rootOrg -Name "default" -ErrorAction Stop

            if ($null -ne $defPolicy)
            {
<#
                try
                {
                    [void] (Start-UcsTransaction -Ucs $ucs)
                    $transactionStarted = $true
#>
                    try
                    {
                        [void] (Add-UcsMaintenancePolicy -Ucs $ucs -ModifyPresent -Name "default" -TriggerConfig "on-next-boot" -UptimeDisr "user-ack" -ErrorAction Stop)
                        $success = $true
                    }
                    catch
                    {
                        ReportError "`tFailed update default maintenance policy."
                    }
<#
                }
                catch
                {
                    ReportError "`tFailed to start UCS transaction."
                }
#>
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
<#
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
#>
    return $success
}

function CreateLDAPProvider
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [Object] $ldapConfig
    )


    $success = $true

    ReportNotice "`tSetting up LDAP authentication..."

    $ldapProviders = [System.Collections.Generic.List[Object]]::new()
    $a = 0
    while($success -and ($a -lt $ldapConfig.providers.Length))
    {
        # 1. Create the LDAP Provider...
        ReportNotice ("`t`tCreating LDAP Provider: {0}..." -f @($ldapConfig.providerNames[$a]))
        $cmdParams = @{
            Ucs = $ucs;
            Name = $ldapConfig.providers[$a].Name;
            Basedn = $ldapConfig.baseDN;
            Rootdn = $ldapConfig.rootDN;
            EnableSSL = "yes";
            FilterValue = "sAMAccountName=`$userid";
            Vendor = "MS-AD";
            Order = $ldapConfig.providers[$a].Order;
            Key = $ldapConfig.bindKey
        }
        $success, $ldapProvider = InvokeUCSFunction -functionName "Add-UcsLdapProvider" -failureMsg "Failed to create LDAP provider." -cmdParams @{ Ucs = $ucs; Name = $ldapConfig.providerNames[$a]; Basedn = $ldapConfig.baseDN; Rootdn = $ldapConfig.rootDN; EnableSSL = "yes"; FilterValue = "sAMAccountName=`$userid"; Vendor = "MS-AD"; Order = ($a + 1); Key = $ldapConfig.bindKey }

        if($success)
        {
            $ldapProviders.Add($ldapProvider)

            #2. Set the LDAP Group Rule for the LDAP Provider
            ReportNotice "`t`t`tSetting group rule..."
            $success, $groupRule = InvokeUCSFunction "Add-UcsLdapGroupRule" -failureMsg ("Failed to modify LDAP provider: {0}" -f @($ldapConfig.providerNames[$a])) -cmdParams @{Ucs = $ucs; LdapProvider = $ldapProvider; ModifyPresent = $true; Authorization = "enable"; Descr = ""; Name = ""; TargetAttr = "memberOf"; Traversal = "recursive"; UsePrimaryGroup = "no" }
        }
        $a++
    }

    # If LDAP providers were created...
    if($success)
    {
        $ldapProviders = @($ldapProviders | Sort-Object Order)
        $success, $ldapGlobalConfig = InvokeUCSFunction "Get-UcsLdapGlobalConfig" -failureMsg "Failed to retrieve LDAP global config." -cmdParams @{ UCS = $ucs }

        if($success)
        {
            # 3. Create the LDAP Provider Group...
            ReportNotice "`t`tCreating LDAP Provider Group: POWERENG DCs..."
            $success, $ldapProviderGroup = InvokeUCSFunction "Add-UcsProviderGroup" -failureMsg "Failed to create LDAP provider group: POWERENG DCs" -cmdParams @{ UCS = $ucs; Name = "POWERENG DCs"; LdapGlobalConfig = $ldapGlobalConfig }
            if($success)
            {
                # 4. Add all of the LDAP Providers to the LDAP Provider Group.
                $a = 0
                while(($a -lt $ldapProviders.Length) -and $success)
                {
                    ReportNotice ("`t`tAdding LDAP Provider reference {0} to POWERENG DCs..." -f @($ldapConfig.providerNames[$a]))
                    $success, $null = InvokeUCSFunction "Add-UcsProviderReference" -failureMsg ("Failed to add provider reference: {0} to {1}." -f @($ldapProviders[$a].Name, $ldapProviderGroup.Name)) -cmdParams @{Ucs = $ucs; ProviderGroup = $ldapProviderGroup; ModifyPresent = $true; Descr = ""; Name = $ldapProviders[$a].Name; Order = $ldapProviders[$a].Order }
                    $a++
                }
            }

            $a = 0
            while($success -and ($a -lt $ldapConfig.groupMaps.Length))
            {
                ReportNotice ("`t`tCreating LDAP Group mapping: {0}..." -f @($ldapConfig.groupMaps[$a].groupDN))
                $success, $ldapGroupMap = InvokeUCSFunction "Add-UcsLdapGroupMap" -failureMsg ("Failed to create group mapping for {0}." -f @($ldapConfig.groupMaps[$a].groupDN)) -cmdParams @{Ucs = $ucs; Name = $ldapConfig.groupMaps[$a].groupDN }

                $b = 0
                while($success -and ($null -ne $ldapGroupMap) -and ($b -lt $ldapConfig.groupMaps[$a].roles.Length))
                {
                    ReportNotice ("`t`t`tAdding role: {0}" -f @($ldapConfig.groupMaps[$a].roles[$b]))
                    $success, $newLDAPGroupMapRole = InvokeUCSFunction "Add-UcsUserRole" -failureMsg ("Failed to add role: {0} to {1}." -f @($ldapConfig.groupMaps[$a].roles[$b], $ldapConfig.groupMaps[$a].groupDN)) -cmdParams @{Ucs = $ucs; Name = $ldapConfig.groupMaps[$a].roles[$b]; LdapGroupMap = $ldapGroupMap; Descr = "" }
                    $b++
                }

                $a++
            }

            if($success)
            {
                ReportNotice "`t`tCreating authentication domain: local..."
                $success, $localAuthDomain = InvokeUCSFunction "Add-UcsAuthDomain" -failureMsg "Failed to create local authentication domain." -cmdParams @{Ucs = $ucs; Name = "local" }
                if($success -and ($null -ne $localAuthDomain))
                {
                    ReportNotice "`t`t`tSetting authentication defaults..."
                    $success, $null = InvokeUCSFunction "Set-UcsAuthDomainDefaultAuth" -failureMsg "Failed to set authentication domain local's default authentication." -cmdParams @{Ucs = $ucs; AuthDomain = $localAuthDomain; Realm = "local"; Use2Factor = "no"; Confirm = $false; Force = $true }
                }
            }

            if($success)
            {
                ReportNotice "`t`tCreating authentication domain: powereng.com..."
                $success, $peiAuthDomain = InvokeUCSFunction "Add-UcsAuthDomain" -failureMsg "Failed to create powereng.com authentication domain." -cmdParams @{Ucs = $ucs; Name = "powereng.com" }
                if($success -and ($null -ne $peiAuthDomain))
                {
                    ReportNotice "`t`t`tSetting authentication defaults..."
                    $success, $null = InvokeUCSFunction "Set-UcsAuthDomainDefaultAuth" -failureMsg "Failed to set authentication domain powereng.com's default authentication." -cmdParams @{Ucs = $ucs; AuthDomain = $peiAuthDomain; Realm = "ldap"; ProviderGroup = "POWERENG DCs"; Use2Factor = "no"; Confirm = $false; Force = $true }
                }
            }
        }
    }

    if(-not $success)
    {
        ReportError ("Failed to setup LDAP authentication.")
    }

    return $success
}

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

    return $success
}

function GetUCSData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $doReportSuccess
    )

    $Global:ucsData = "" | Select-Object Adaptors, Servers, VLANs

    # Retrieve required data from UCS

    #region    Collect UCS Compute node details
    try  # Just to subdue any error messages.
    {
        $Global:ucsData.Servers = @(Get-UCSServer -Ucs $ucs -ErrorAction SilentlyContinue)
    }
    catch { }

    if ($Global:ucsData.Servers.Length -gt 0)
    {
        # TRUE

        if($doReportSuccess)
        {
            ReportSuccess ("Retrieved {0} compute node details from {1}." -f @($Global:ucsData.Servers.Length, $ucs.Name))
        }

        #region    Collect UCS vNIC information
        try  # Just to subdue any error messages.
        {
            $Global:ucsData.Adaptors = @(Get-UCSAdaptorHostEthIf -Ucs $ucs -ErrorAction SilentlyContinue)
        }
        catch { }

        if ($Global:ucsData.Adaptors.Length -gt 0)
        {
            # TRUE

            if($doReportSuccess)
            {
                ReportSuccess ("Retrieved {0} vNIC details from {1}." -f @($Global:ucsData.Adaptors.Length, $ucs.Name))
            }

            #region    Collect UCS VLAN information
            try  # Just to subdue any error messages.
            {
                $Global:ucsData.VLANs = @(Get-UcsVlan -Ucs $ucs -ErrorAction SilentlyContinue)
            }
            catch { }

            if ($Global:ucsData.VLANs.Length -gt 0)
            {
                # TRUE

                if($doReportSuccess)
                {
                    ReportSuccess ("Retrieved {0} VLANs from {1}." -f @($Global:ucsData.VLANs.Length, $ucs.Name))
                }
            }
            else # NOT ($Global:ucsData.VLANs.Length -gt 0)
            {
                # FALSE

                ReportError ("Failed to retrieve VLAN details from {0}." -f @($ucs.Name))
                $Global:ucsData = $null
            }
            #endregion Collect UCS VLAN information

        }
        else # NOT ($Global:ucsData.Adaptors.Length -gt 0)
        {
            # FALSE

            ReportError ("Failed to retrieve vNIC details from {0}." -f @($ucs.Name))
            $Global:ucsData = $null
        }
        #endregion Collect UCS vNIC information
    }
    else # NOT ($Global:ucsData.Servers.Length -gt 0)
    {
        # FALSE

        ReportError ("Failed to retrieve compute node details from {0}." -f @($ucs.Name))
        $Global:ucsData = $null
    }
    #endregion Collect UCS Compute node details
}

#endregion

#region VMware Utility Functions
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
                        ReportError ("Failed to set new advanced setting {0} to {1} in {2}." -f @($advSettingName, $advSettingValue, $MyInvocation.MyCommand))
                    }
                } `
                else # NOT ($null -ne $advSetting)
                {
                    $advSetting | Set-AdvancedSetting -Value $advSettingValue -Confirm:$false
                }
            } `
            else # NOT ($cluster.Id -match "")
            {
                ReportError ("Unable to determine cluster unique ID from: {0} in {1}." -f @($cluster.Id, $MyInvocation.MyCommand))
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

                        ReportError ("Distributed switch {0} already exists." -f @($dsConfig.name))
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

                                    ReportSuccess ("Created distributed switch {0} under {1}." -f @($vds.Name, $vdsDatacenter.Name))
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

                                            ReportNotice ("`tRenamed uplink port group to {0}." -f @($uplinkName))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # FALSE

                                            # Nothing.
                                        }
                                    }
                                    catch
                                    {
                                        ReportWarning ("Failed to rename uplink port group to {0}." -f @($uplinkName))
                                    }
                                }
                                catch
                                {
                                    ReportWarning ("Failed to retrieve default uplinks port group for {0}." -f @($vds.Name))
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

                                                ReportSuccess ("`tEnabled network I/O control on {0}." -f @($vds.Name))
                                            }
                                            else # NOT ($doReportSuccess)
                                            {
                                                # FALSE

                                                # Nothing.
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to enable network I/O control on {0}.  Check vCenter logs." -f @($vds.Name))
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Failed to rename uplink {0}.  Check vCenter logs." -f @($uplinkNames[$a]))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to re-acquire distributed switch {0}." -f @($dsConfig.name))
                                }
                            }
                            catch
                            {
                                ReportError ("Failed to create distributed switch {0}.  Consult vCenter logs." -f @($dsConfig.name))
                            }
                        }
                        catch
                        {
                            ReportError ("Unable to locate datacenter {0} in vCenter." -f @($datacenterName))
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

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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

            ReportWarning ("Please manually continue the creation of {0}, or correct the problem, remove the distributed switch if possible and retry to create it." -f @($dsConfig.name))
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

                                        ReportSuccess ("`tCreated port group {0} on {1}." -f @($vpg.Name, $vds.Name))
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
                                                    ReportError ("Failed to set teaming policy for {0}." -f @($vpg.Name))
                                                    $goodToGo = $false
                                                }
                                            }
                                            else # NOT ($null -ne $teamingPolicy)
                                            {
                                                # FALSE

                                                ReportError ("Failed to retrieve teaming policy for {0}." -f @($vpg.Name))
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

                                        ReportWarning ("{0} has no uplinks." -f @($vpg.Name))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to add distributed port group {0} to {1}." -f @($dsConfig.portGroups[$a].name, $vds.Name))
                                    $goodToGo = $false
                                }
                            }
                            else # NOT ($doIt)
                            {
                                # FALSE

                                ReportNotice ("Simulated creating port group {0} on {1}." -f @($dsConfig.portGroups[$a].name, $vds.Name))
                            }
                        }
                        $a++
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @($dsConfig.name))
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

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
                    ReportSuccess ("Added {0} to {1}." -f @($vmHost.Name, $vds.Name))
                }
                catch
                {
                    ReportError ("Failed to add {0} to {1}." -f @($hostDef.vmHostName, $vds.Name))
                    $goodToGo = $false
                }
            }
            else # NOT ($DoIt)
            {
                # FALSE

                ReportNotice ("Simulated adding {0} to {1}." -f @($vmHost.Name, $vds.Name))
            }
        }
        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
        {
            # FALSE

            ReportWarning ("{0} is already attached to {1}." -f @($vmHost.Name, $vds.Name))
        }
    }
    catch
    {
        ReportError ("Unable to find a VM host named: {0}." -f @($hostDef.vmHostName))
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
                    ReportError ("Distributed switch {0} does not exist." -f @($dsConfig.name))
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

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
        [Cisco.Ucsm.UcsHandle] $ucs,

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
            if ($null -ne $ucs)
            {
                if ($null -eq $Global:ucsData)
                {
                    GetUCSData -ucs $ucs -doReportSuccess:$doReportSuccess
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
                                                                    ReportError ("Unable to determine uplink name for {0}." -f @((@($vmHost.Name, $vmNICs[$b].Name) -join ":")))
                                                                    $vmNICsMigrated = $false
                                                                }
                                                            }
                                                            else # NOT ($null -ne $ucsVMNICAdaptor)
                                                            {
                                                                ReportError ("Unable to determine uplink adaptor for {0}." -f @((@($vmHost.Name, $vmNICs[$b].Name) -join ":")))
                                                                $vmNICsMigrated = $false
                                                            }
                                                            $b++
                                                        }
                                                    }
                                                    else # NOT ($vmNICs.Length -gt 0)
                                                    {
                                                        ReportError ("Unable to retrieve vmnics for {0}." -f @($vmHost.Name))
                                                        $vmNICsMigrated = $false
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Unable to retrieve VMNICs from VM host {0}." -f @($hostDef.vmHostName))
                                                    $vmNICsMigrated = $false
                                                }
                                            }
                                            else # NOT ($null -ne $ucsServer)
                                            {
                                                ReportError ("No UCS compute node found for {0} serial number {1}" -f @($vmHost.Name, $hostDef.serial))
                                                $vmNICsMigrated = $false
                                            }
                                        }
                                        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                                        {
                                            ReportError ("{0} must be attached to {1} before it's vmnics can be migrated." -f @($vmHost.Name, $vds.Name))
                                            $vmNICsMigrated = $false
                                        }
                                    }
                                    else # NOT ($null -ne $vmHost)
                                    {
                                        ReportError ("Unable to locate VM host named {0}." -f @($hostDef.vmHostName))
                                        $vmNICsMigrated = $false
                                    }
                                }
                                catch
                                {
                                    ReportError ("Unable to locate VM host named {0}." -f @($hostDef.vmHostName))
                                    $vmNICsMigrated = $false
                                }
                            }
                            else # NOT ($null -ne $vds)
                            {
                                ReportError ("Distributed switch {0} does not exist." -f @($dsConfig.name))
                                $vmNICsMigrated = $false
                            }
                        }
                        catch
                        {
                            ReportError ("Distributed switch {0} does not exist." -f @($vdsName))
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
            else # NOT ($null -ne $ucs)
            {
                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmNICsMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
        [Cisco.Ucsm.UcsHandle] $ucs,

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
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucs $ucs -vdsName $dsConfig.name -hostDef $hostDefs[$a] -AllvmNICs -DoIt -doReportSuccess
                            } `
                            elseif ($ExcludevmNIC0)
                            {
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucs $ucs -vdsName $dsConfig.name -hostDef $hostDefs[$a] -ExcludevmNIC0 -DoIt -doReportSuccess
                            }
                            elseif ($OnlyvmNIC0)
                            {
                                $vmNICsMigrated = MigrateHostVMNICsToVDS -viServer $viServer -ucs $ucs -vdsName $dsConfig.name -hostDef $hostDefs[$a] -OnlyvmNIC0 -DoIt -doReportSuccess
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
            else # NOT ($null -ne $ucs)
            {
                # FALSE

                ReportError ("Missing UCS Manager in {0}." -f @($MyInvocation.MyCommand.Name))
                $vmNICsMigrated = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
                                    ReportError ("Distributed port group {0} does not exist on {1}." -f @($hostDef.vmks[$a].portGroupName, $vds.Name))
                                    $vmksMigrated = $false
                                }

                                $a++
                            }
                        }
                        else # NOT ($null -eq ($vds.ExtensionData.Config.Host | Where-Object {$_.Config.Host -eq $vmHost.Id }))
                        {
                            ReportError ("{0} must be attached to {1} before it's VM kernel adapters can be migrated." -f @($vmHost.Name, $vds.Name))
                            $vmksMigrated = $false
                        }
                    }
                    catch
                    {
                        ReportError ("Unable to locate VM host named {0}." -f @($hostDef.vmHostName))
                        $vmksMigrated = $false
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @($vdsName))
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
            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
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
        [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]] $cDot,

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
                                                else # NOT ([String]::IsNullOrEmpty($junctionPaths[$c]))
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

function SetAdvancedSettingForVMHost($viServer, $vmHost, $setting, $value)
{
    try
    {
        $advSetting = Get-AdvancedSetting -Server $viServer -Entity $vmHost -Name $setting -ErrorAction Stop

        if($advSetting.Value -ne $value)
        {
            try
            {

                $newAdvSetting = $advSetting | Set-AdvancedSetting -Value $value -Confirm:$false -ErrorAction Stop
                Write-Host -ForegroundColor Green ("{0,-30}{1,-50}{2,25}{3,25} (Updated)" -f @($vmHost.Name, $advSetting.Name, $advSetting.Value, $newAdvSetting.Value))
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to set {0} to {1} on {2}." -f @($setting, $value, $vmHost.Name))
            }
        }
        else
        {
            Write-Host -ForegroundColor White ("{0,-30}{1,-50}{2,25}{3,25}" -f @($vmHost.Name, $advSetting.Name, $advSetting.Value, $value))
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to retrieve advanced setting {0} from {1}." -f @($setting, $vmHost.Name))
    }
}

function SetAdvancedSettingsForVMhost($viServer, $vmHost)
{
    $b = 0
    while($b -lt $settingsToCheck.Length)
    {
        SetAdvancedSettingForVMHost $viServer $vmHost $Global:settingsToCheck[$b].Name $Global:settingsToCheck[$b].RecommendedValue
        $b++
    }
}

function JoinESXiToDomain
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl] $vmHost,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $ouToJoin,

        [Parameter(Mandatory=$false, Position=3)]
        [PSCredential] $adCredentials
    )

    if ($null -ne $viServer)
    {
        # TRUE

        if ($null -ne $vmHost)
        {
            # TRUE

            if (-not [String]::IsNullOrEmpty($ouToJoin))
            {
                # TRUE

                if ($null -ne $adCredentials)
                {
                    # TRUE

                    try
                    {
                        $adDomain = Get-ADDomain -ErrorAction SilentlyContinue
                    }
                    catch { }

                    if ($null -ne $adDomain)
                    {
                        # TRUE

                        try
                        {
                            $adOU = Get-ADOrganizationalUnit -Identity $ouToJoin -Properties "CanonicalName" -ErrorAction SilentlyContinue
                        }
                        catch {}

                        if ($null -ne $adOU)
                        {
                            # TRUE

                            if (-not [String]::IsNullOrEmpty($adOU.CanonicalName))
                            {
                                # TRUE

                                try
                                {
                                    $vmHostAuthentication = Get-VMHostAuthentication -Server $viServer -VMHost $vmHost -ErrorAction SilentlyContinue
                                }
                                catch { }

                                if ($null -ne $vmHostAuthentication)
                                {
                                    # TRUE

                                    if ($vmHostAuthentication.Domain -ne $adDomain.DNSRoot)
                                    {
                                        # TRUE

                                        $canonicalName = $adOU.CanonicalName.Replace($adDomain.DNSRoot, $adDomain.DNSRoot.ToUpper())
                                        try
                                        {
                                            # $newVMHostAuthentication = $vmHostAuthentication |
                                            $null = Set-VMHostAuthentication -Domain $canonicalName -JoinDomain -Credential $adCredentials -VMHostAuthentication $vmHostAuthentication -Confirm:$false -ErrorAction Stop
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to join {0} to {1}." -f @($vmHost.Name, $canonicalName))
                                        }
                                    }
                                    else # NOT ($vmHostAuthentication.Domain -ne $adDomain.DNSRoot)
                                    {
                                        # FALSE

                                        # Nothing.
                                    }
                                }
                                else # NOT ($null -ne $vmHostAuthentication)
                                {
                                    # FALSE

                                    ReportError ("Failed to retrieve VM host authentication for `"{0}`"." -f @($vmHost.Name))
                                }
                            }
                            else # NOT (-not [String]::IsNullOrEmpty($adOU.CanonicalName))
                            {
                                # FALSE

                                ReportError ("CanonicalName for `"{0}`" not returned from Active Directory." -f @($ouToJoin))
                            }
                        }
                        else # NOT ($null -ne $adOU)
                        {
                            # FALSE

                            ReportError ("Unable to retrieve Active Directory OU matching `"{0}`"." -f @($ouToJoin))
                        }
                    }
                    else # NOT ($null -ne $adDomain)
                    {
                        # FALSE

                        ReportError "Failed to retrieve Active Directory domain information."
                    }
                }
                else # NOT ($null -ne $adCredentials)
                {
                    # FALSE

                    ReportError ("Missing credential used to join {0} to domain in {1}." -f @($vmHost.Name, $MyInvocation.MyCommand.Name))
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($ouToJoin))
            {
                # FALSE

                ReportError ("Missing OU where {0} should be joined in {1}." -f @($vmHost.Name, $MyInvocation.MyCommand.Name))
            }

        }
        else # NOT ($null -ne $vmHost)
        {
            # FALSE

            ReportError ("Missing vmHost in {0}." -f @($MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }
}

function RemoveVMHostLocalDatastores
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
                $datastores = @(Get-Datastore -Server $viServer -RelatedObject $vmHost -ErrorAction Stop | Where-Object { $_.Type -eq "VMFS"})
            }
            catch
            {
                ReportWarning ("No local datastores found on {0}." -f @($vmHost.Name))
            }

            $a = 0
            while($a -lt $datastores.Length)
            {
                try
                {
                    Remove-Datastore -Server $viServer -Datastore $datastores[$a] -VMHost $vmHost -Confirm:$false -ErrorAction Stop
                }
                catch
                {
                    ReportError ("Failed to remove datastore: {0} from {1}." -f @($datastores[$a].Name, $vmHost.Name))
                }
                $a++
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

$Global:settingsToCheck = @(
    @{Name = "Net.TcpipHeapSize";                               RecommendedValue = 32 },
    @{Name = "Net.TcpipHeapMax";                                RecommendedValue = 1536 },
    @{Name = "NFS.MaxVolumes";                                  RecommendedValue = 256 },
    @{Name = "NFS.MaxQueueDepth";                               RecommendedValue = 128 },
    @{Name = "NFS.HeartbeatMaxFailures";                        RecommendedValue = 10 },
    @{Name = "NFS.HeartbeatFrequency";                          RecommendedValue = 12 },
    @{Name = "NFS.HeartbeatTimeout";                            RecommendedValue = 5 },
    @{Name = "SunRPC.MaxConnPerIP";                             RecommendedValue = 128 },
    @{Name = "UserVars.SuppressCoredumpWarning";                RecommendedValue = 1 },
    @{Name = "Config.HostAgent.plugins.hostsvc.esxAdminsGroup"; RecommendedValue = "pgVCenterAdmin" }
)

$Global:ntpServers = @(
    "ntp1.powereng.com",
    "ntp2.powereng.com"
)

function UpdateESXiAdvSettings
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $vmHostName,

        [Parameter(Mandatory=$false,ParameterSetName="JoinAD")]
        [Switch] $JoinAD,

        [Parameter(Mandatory=$false,ParameterSetName="JoinAD")]
        [System.Management.Automation.PSCredential] $ADCreds
    )

    $vmHostName = ("{0}.powereng.com" -f @($vmHostName)).ToLower().Replace(".powereng.com.powereng.com",".powereng.com")
    try
    {
        $vmHost = Get-VMHost -Server $viServer -Name $vmHostName -ErrorAction Stop
    }
    catch
    {
        <#Do this if a terminating exception happens#>
    }

    if($null -ne $vmHost)
    {
        $vmHostNTPServers = @(Get-VMHostNtpServer -Server $viServer -VMHost $vmHost)
        $b = 0
        while($b -lt $vmHostNTPServers.Length)
        {
            if ($ntpServers -notcontains $vmHostNTPServers[$b])
            {
                # TRUE

                ReportNotice ("Removing NTP server: {0} from {1}" -f @($vmHostNTPServers[$b], $vmHost.Name))
                Remove-VMHostNtpServer -Server $viServer -VMHost $vmHost -NtpServer $vmHostNTPServers[$b]
            }
            else # NOT ($ntpServers -notcontains $vmHostNTPServers[$b)
            {
                # FALSE

                # Nothing.
            }

            $b++
        }

        $vmHostNTPServers = Get-VMHostNtpServer -Server $viServer -VMHost $vmHost
        $b = 0
        while($b -lt $ntpServers.Length)
        {
            if ($vmHostNTPServers -notcontains $ntpServers[$b])
            {
                # TRUE

                ReportNotice ("Adding NTP server: {0} to {1}" -f @($ntpServers[$b], $vmHost.Name))
                Add-VMHostNtpServer -Server $viServer -VMHost $vmHost -NtpServer $ntpServers[$b]
            }
            else # NOT ($vmHostNTPServers -notcontains $ntpServers[$b])
            {
                # FALSE

                # Nothing.
            }

            $b++
        }

        $ntpService = Get-VMHostService -Server $viServer -VMHost $vmHost | Where-Object { $_.Key -eq "ntpd" }
        if ($null -ne $ntpService)
        {
            # TRUE

            if ($ntpService.Policy -ne "automatic")
            {
                # TRUE

                ReportNotice ("Setting {0} {1} service policy to automatic." -f @($vmHost.Name, $ntpService.Label))
                Set-VMHostService -HostService $ntpService -Policy "Automatic"
            }
            else # NOT ($ntpService.Policy -ne "automatic")
            {
                # FALSE

                # Nothing.
            }

            if (-not $ntpService.Running)
            {
                # TRUE

                ReportNotice ("Starting {0} {1} service." -f @($vmHost.Name, $ntpService.Label))
                Start-VMHostService $ntpService
            }
            else # NOT (-not $ntpService.Running)
            {
                # FALSE

                # Nothing.
            }
        } `
        else # NOT ($null -ne $ntpService)
        {
            # FALSE

            # Nothing.
        }

        # Must happen after the ESXi host is joined to the domain.  -- well sort of ... or the admin group makes sense.
        SetAdvancedSettingsForVMhost $viServer $vmHost

        # Think this might have to wait until the local DC is up and running.
        if($JoinAD)
        {
            # JoinESXiToDomain -vCenter $viServer -vmHost $vmHost -ouToJoin "OU=VMware,OU=Servers,OU=PEI,DC=powereng,DC=com" -adCredentials $ADCreds
        }
    }
}

function RenameLocalDatastores($viServer, $vmHost)
{
    $localDataStores = @(Get-Datastore -Server $viServer -RelatedObject $vmHost | Where-Object { $_.Type -eq "VMFS" })

    $a = 0
    while($a -lt $localDataStores.Length)
    {
        $newDSName = "~{0} local storage" -f @(($vmHost.Name.ToUpper().Replace(".POWERENG.COM", "")))

        if($localDataStores[$a].Name -ne $newDSName)
        {
            Write-Host -ForegroundColor Green ("Renaming {0}:{1} to {2}." -f @($vmHost.Name, $localDataStores[$a].Name, $newDSName))
            try
            {
                [void] (Set-Datastore -Server $viServer -Datastore $localDataStores[$a] -Name $newDSName -ErrorAction Stop)
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to rename {0}:{1} to {2}." -f @($vmHost.Name, $localDataStores[$a].Name, $newDSName))
            }
        }
        $a++
    }
}

#endregion

function MonitorSnapmirror()
{
    do {
        $sm = Get-NCSnapmirror -Controller $las04CDot -Destination "vol_vmware_RDC_SATA_01"
        $pc = ($sm.SnapshotProgress / $src.VolumeSpaceAttributes.LogicalUsed) * 100.0
        $status = "{0:N0} of {1:N0} transferred.  {2:N2}% Complete " -f @($sm.SnapshotProgress, $src.VolumeSpaceAttributes.LogicalUsed, $pc)
        Write-Progress -Activity "Snapmirror" -id 1 -Status $status -PercentComplete ([int] $pc)
        if(($sm.Status -ne "idle") -or ($sm.MirrorState -ne "snapmirrored"))
        {
            Start-Sleep -Seconds 15
        }
    } until ($sm.Status -eq "idle") -and ($sm.MirrorState -eq "snapmirrored")
    Write-Host ""

    if(($sm.Status -eq "idle") -and ($sm.MirrorState -eq "snapmirrored"))
    {
        $anonUsername = "anonymous"
        $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
        $anonCredentials = [System.Management.Automation.PSCredential]::new($anonUsername, $anonPassword)

        Send-MailMessage -From "donotreply@powereng.com" -To "ken.briney@powereng.com" -SmtpServer "smtp.powereng.com" -Subject "Snapmirror complete." -Body "Read the subject..." -Credential $anonCredentials
    }
}
