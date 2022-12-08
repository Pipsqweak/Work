
Add-PSSnapin Citrix.*

function Quoted
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $str
    )


    $s = [String]::Empty
    if(-not [String]::IsNullOrEmpty($str))
    {
        $s = "`"{0}`"" -f @($str.Trim('`"'))
    }

    return $s
}

function ShutdownVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        # [VMware.VimAutomation.ViCore.Impl.V1.VM.VirtualMachineImpl] $vm2Shutdown,
        [Object] $vm2Shutdown,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch]
        $Simulated
    )

    $shutdownInitiatedSuccessfully = $false

    if($vm2Shutdown.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
    {
        try
        {
            # Write-Host "Attempting shutdown..."
            if (-not $Simulated)
            {
                $vm2Shutdown.ExtensionData.ShutdownGuest()
                $shutdownInitiatedSuccessfully = $true
            } `
            else # NOT (-not $Simulated)
            {
#                $shutdownInitiatedSuccessfully = Get-Random @($true, $false)
                $shutdownInitiatedSuccessfully = $true
                if (-not $shutdownInitiatedSuccessfully)
                {
                    throw "VMware Tools is not running"
                } `
                else # NOT (-not $shutdownInitiatedSuccessfully)
                {
                    # Nothing.
                }
            }
        }
        catch
        {
            if (($null -ne $_) -and ($null -ne $_.Exception))
            {
                $ex = $_.Exception
                if ($ex.Message -match "VMware Tools is not running")
                {
                    # Write-Host "Attempting power off"
                    if (-not $Simulated)
                    {
                        try
                        {
                            $vm2Shutdown.ExtensionData.PowerOffVM_Task()
                            $shutdownInitiatedSuccessfully = $true
                        }
                        catch
                        {
                            # $ee = $_.Exception
                        }
                    } `
                    else # NOT (-not $Simulated)
                    {
#                        $shutdownInitiatedSuccessfully = Get-Random @($true, $false)
                        $shutdownInitiatedSuccessfully = $true
                    }
                } `
                else # NOT ($ex.Message)
                {
                    # Nothing.
                }
            } `
            else # NOT (($null -ne $_) -and ($null -ne $_.Exception))
            {
                # Nothing
            }
        }
    } `
    else
    {
        # VM is not powered on, so pretend we shut it down...
        $shutdownInitiatedSuccessfully = $true
    }


    return $shutdownInitiatedSuccessfully
}

function ShutdownVMs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCtr,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $citrixHost,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String[]] $vmLocations,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String[]] $vmExceptions,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch]
        $Simulated
    )

    $simulatedStr = " (simulated)"
    if(-not $Simulated)
    {
        $simulatedStr = [String]::Empty
    }

    # $vmExceptions = @("BDC-DC01","BDC-DC02")
    $powerstateSavePath = "{0}\{1}-vmPowerState.json" -f @($env:TEMP, [DateTime]::Now.ToString("yyyyMMdd_HHmmss"))
    $allVMs = @()
    $allVDI = @()
    $locations = @()
    $continueShutdown = $true

    try
    {
        $locations = @(Get-Inventory -Server $vCtr -Name $vmLocations -ErrorAction Stop)
        if($locations.Length -ne $vmLocations.Length)
        {
            Write-Host -ForegroundColor Red ("Unable to get VI Inventory object(s) for one or more of: {0}." -f @(($vmLocations -join ", ")))
            $continueShutdown = $false
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Unable to get VI Inventory object(s) for {0}." -f @(($vmLocations -join ", ")))
        $continueShutdown = $false
    }

    if($continueShutdown)
    {
        for($pass = 0; $continueShutdown -and ($pass -lt 2); $pass++)
        {
            try
            {
                # Get all the VMs under $location...
                #   Only filter out vSphere cluster services VM here.  We need to know the powerstate for all other VMs.
                Write-Host -ForegroundColor Green ("Collecting VM information from: {0}." -f @(($vmLocations -join ", ")))
                $allVMs = @(Get-VM -Server $vCtr -Location $locations -ErrorAction Stop | Where-Object { $_.Name -notmatch "^vCLS" })
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Unable to get virtual machines from one or more of: {0}." -f @((($locations | Select-Object -Unique -ExpandProperty Name) -join ", ")))
                $continueShutdown = $false
            }

            try
            {
                Write-Host -ForegroundColor Green ("Collecting VDI information from: {0}." -f @($citrixHost))
                $allVDI = Get-BrokerMachine -AdminAddress $citrixHost -MaxRecordCount 10000 -ErrorAction Stop
            }
            catch
            {
                Write-Host -ForegroundColor Red "Unable to get VDI machines data."
                $continueShutdown = $false
            }

            if($continueShutdown -and ($allVMs.Length -gt 0) -and ($allVDI.Length -gt 0))
            {
                Write-Host -ForegroundColor Green "Building VM shutdown array..."
                # Create an array of relevent information...
                #   NOTE: Some of the properties listed here are used in the StartVMs function.
                #     As such, they need to be added to the object here and written to the save file so they will
                #     be available later.
                #
                #     Additionally, it might seem redundant to include VM and VDI properties when the same information could be
                #        obtained via the .VM/.VDI properties, and while this is true in this function, the same is not true in StartVMs.  Therefore,
                #        the VM name, powerstate, and CTXMaintenanceMode properties have to be available independent of the objects they come from when reading in
                #        the JSON data in StartVMs.
                $totalActions = 0
                $vmPowerData = @($allVMs | ForEach-Object {
                    $d = "" | Select-Object Id,Name,PowerState,VMHostId,VMHost,ShutdownInitiated,StartupInitiated,StartupTask,IsVDI,CTXMaintenanceMode,VM,VDI
                    $d.Id = $_.Id
                    $d.Name = $_.Name
                    $d.PowerState = $_.PowerState.ToString()

                    if ($_.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                    {
                        $totalActions++  # Re-acquire VM object (to verify VM is still powered on)
                        $totalActions++  # Shutdown the VM
                    } `
                    else # NOT ($_.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                    {
                        # Nothing.
                    }
                    $d.VMHostId = $_.VMHostId
                    $d.VMHost = $_.VMHost.Name
                    # If $vmExceptions contains $_.Name, set .ShutdownInitiated to $true so we skip it.  These will have to be shutdown manually
                    $d.ShutdownInitiated = $vmExceptions -contains $_.Name
                    $d.StartupInitiated = $false
                    $d.StartUpTask = $null    # Used in StartVMs to track the VM task used to power on the VM
                    $d.IsVDI = $false
                    $d.CTXMaintenanceMode = $false
                    $d.VM = $_   # Used to track the actual [VMware.VimAutomation.ViCore.Impl.V1.VM.UniversalVirtualMachineImpl] as returned from vCenter
                    $d.VDI = $allVDI | Where-Object { $_.MachineName -eq ("POWERENG\{0}" -f @($d.Name)) }   # Used to track the actual [Citrix.Broker.Admin.SDK.Machine] as returned from Citrix (if the VM is a VDI at all)
                    if ($null -ne $d.VDI)
                    {
                        $d.IsVDI = $true
                        $d.CTXMaintenanceMode = $d.VDI.InMaintenanceMode
                        if (-not $d.CTXMaintenanceMode)
                        {
                            $totalActions++   # Place VDI in maintenance mode
                        } `
                        else # NOT ($d.CTXMaintenanceMode)
                        {
                            # Nothing.
                        }
                    } `
                    else # NOT ($null -ne $d.VDI)
                    {
                        # Nothing.
                    }

                    $d
                })

                if ($pass -eq 0)
                {
                    try
                    {
                        # The calculated properties below are written to the save file as $null since the actual values would be meaningless in StartVMs.
                        #    However, the properties are required to be written to the save file so when objects are instantiated in StartVMs, the
                        #    properties are available to be used.

                        $vmPowerData | Sort-Object VMHost,Name | Select-Object `
                            Id,
                            Name,
                            PowerState,
                            VMHostId,
                            VMHost,
                            IsVDI,
                            CTXMaintenanceMode,
                            @{N='ShutdownInitiated'; E={$null}},
                            @{N='StartupInitiated'; E={$null}},
                            @{N='StartupTask'; E={$null}},
                            @{N='VM'; E={$null}},
                            @{N='VDI'; E={$null}} | ConvertTo-Json | Set-Content -LiteralPath $powerstateSavePath
                        Write-Host -ForegroundColor Green ("`r`nPre-shutdown virtual machine powerstate saved to {0}.`r`n" -f @((Quoted $powerstateSavePath)))
                        $continueShutdown = $true
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("Unable to save virtual machine powerstate to {0}." -f @((Quoted $powerstateSavePath)))
                        $continueShutdown = $false
                    }
                } `
                else # NOT ($pass -eq 0)
                {
                    # Nothing -- only save the VM powerstate data on pass 1
                }

                if ($continueShutdown)
                {
                    # Pare $vmPowerData down to only the VMs we need to power down or VDIs that need to be placed in maintenance mode
                    $vmPowerData = @($vmPowerData | Where-Object { `
                        (-not $_.ShutdownInitiated) -and `
                        (($null -ne $_.VM) -and ($_.VM.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)) `
                        -or `
                        (($null -ne $_.VDI) -and (-not $_.VDI.InMaintenanceMode) -and (-not $_.CTXMaintenanceMode))
                     })

                    # How many actions have we executed (whether they are successful or not)
                    $actionPerformed = 0

                    # Progress bar Id
                    $progressBarId = 1

                    # Get an array of the unique VM Hosts which have powered on VMs...
                    $uniqueVMHosts = @($vmPowerData | Select-Object @{N='VMHost'; E={ $_.VM.VMHost.Name }} | Select-Object -Unique -ExpandProperty VMHost | Sort-Object)

                    # Sanity check -- don't know how $uniqueVMHosts.Length could NOT be -gt 0, but best to check...
                    if ($uniqueVMHosts.Length -gt 0)
                    {
                        # Start shutting down VMs on $uniqueVMHosts[$nextHostToHaveVMShutdown]...
                        $nextHostToHaveVMShutdown = 0

                        while ($vmPowerData.Length -gt 0)    # We will pare down $vmPowerState at the bottom of the while loop
                        {
                            # Select the next VM on to process...
                            $vmToShutdown = $vmPowerData | Where-Object { `
                                ($_.VM.VMHost.Name -eq $uniqueVMHosts[$nextHostToHaveVMShutdown]) `
                                -and `
                                ( `
                                    ( `
                                        ($null -ne $_.VM) `
                                        -and ($_.VM.PowerState -eq "PoweredOn") `
                                        -and (-not $_.ShutdownInitiated)
                                    ) `
                                    -or `
                                    ( `
                                        ($null -ne $_.VDI) `
                                        -and (-not $_.VDI.InMaintenanceMode) `
                                        -and (-not $_.CTXMaintenanceMode)
                                    )
                                ) `
                            } | Select-Object -First 1

                            $vmToShutdown = $vmPowerData | Where-Object { $_.VM.VMHost.Name -eq $uniqueVMHosts[$nextHostToHaveVMShutdown] } | Select-Object -First 1

                            if ($null -ne $vmToShutdown)
                            {
                                # No matter what the state of the actual VM, we will still mark $vmToShutdown as if we initiated shutdown.  This is required for the while loop to terminate
                                #    Since we pare down $vmPowerData by removing all objects where .ShutdownInitiated -eq $true
                                $vmToShutdown.ShutdownInitiated = $true

                                $percentComplete = ($actionPerformed / $totalActions) * 100
                                if($percentComplete -ge 100) { $percentComplete = 100 }
                                Write-Progress -Id $progressBarId -Activity ("Processing {0}{1}" -f @($vmToShutdown.VM.Name, $simulatedStr)) -Status ("{0:N2}% complete" -f @($percentComplete)) -PercentComplete $percentComplete

                                # If the VM is also a VDI, and is not already in maintenance mode, place it into maintenance mode before initiating shutdown.
                                if(($null -ne $vmToShutdown.VDI) -and (-not $vmToShutdown.VDI.InMaintenanceMode) -and (-not $vmToShutdown.CTXMaintenanceMode))
                                {
                                    Write-Host -NoNewline -ForegroundColor Green ("Placing VDI: {0} into maintenance mode." -f @($vmToShutdown.VDI.MachineName))
                                    $actionPerformed++     # Set VDI Maintenance Mode
                                    $percentComplete = ($actionPerformed / $totalActions) * 100
                                    if($percentComplete -ge 100) { $percentComplete = 100 }
                                    Write-Progress -Id $progressBarId -Activity ("Processing {0}{1}" -f @($vmToShutdown.VM.Name, $simulatedStr)) -Status ("Placing VDI into maintenance mode | {0:N2}% complete" -f @($percentComplete)) -PercentComplete $percentComplete

                                    if (-not $Simulated)
                                    {
                                        try
                                        {
                                            # Set-BrokerMachineMaintenanceMode -AdminAddress $citrixHost -InputObject $vmToShutdown.VDI -MaintenanceMode $true -ErrorAction Stop

                                            # Update .CTXMaintenanceMode to indicate we have placed the VDI into maintenance mode
                                            $vmToShutdown.CTXMaintenanceMode = $true
                                        }
                                        catch
                                        {
                                            # Nothing, we'll display a message below.
                                        }
                                    } `
                                    else
                                    {
                                        Write-Host -NoNewline -ForegroundColor Yellow " (Simulated)"
#                                        $vmToShutdown.CTXMaintenanceMode = Get-Random @($true, $true, $true, $false)  # Better odds it succeeding (simulated of course)
                                        $vmToShutdown.CTXMaintenanceMode = $true
                                    }

                                    if ($vmToShutdown.CTXMaintenanceMode)
                                    {
                                        Write-Host -ForegroundColor Green ("  Successful")
                                    } `
                                    else # NOT (-not $vmToShutdown.CTXMaintenanceMode)
                                    {
                                        Write-Host -NoNewline -ForegroundColor Red "  Failed."
                                        if($vmToShutdown.VM.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                                        {
                                            Write-Host -NoNewLine -ForegroundColor Red "  VM shutdown will be skipped."

                                            # Simulate we actually re-acquired VM for purposes of the progress bar since we are skipping the VM shutdown process
                                            $actionPerformed++

                                            # Simulate we actually shut the VM down for purposes of the progress bar since we are skipping the VM shutdown process
                                            $actionPerformed++
                                        }
                                        Write-Host
                                    }
                                } `
                                else
                                {
                                    # Nothing, not a VDI...
                                }

                                # Only try to re-acquire the VM if we are going to shut it down.
                                if(($null -eq $vmToShutdown.VDI) -or (($null -ne $vmToShutdown.VDI) -and $vmToShutdown.CTXMaintenanceMode))
                                {
                                    try
                                    {
                                        $actionPerformed++
                                        $percentComplete = ($actionPerformed / $totalActions) * 100
                                        if($percentComplete -ge 100) { $percentComplete = 100 }
                                        Write-Progress -Id $progressBarId -Activity ("Processing {0}{1}" -f @($vmToShutdown.VM.Name, $simulatedStr)) -Status ("Re-acquiring VM | {0:N2}% complete" -f @($percentComplete)) -PercentComplete $percentComplete

                                        # Re-acquire the VM object from vCenter (if -not $Simulated) just to make sure the VM was not shutdown by an external source
                                        if (-not $Simulated)
                                        {
                                            $vm = Get-VM -Server $vCtr -Name $vmToShutdown.VM.Name -ErrorAction Stop
                                            if ($null -ne $vm)
                                            {
                                                # Only update $vmToShutdown.VM if we successfully re-acquire the VM...
                                                $vmToShutdown.VM = $vm
                                            } `
                                            else # NOT ($null -ne $vm)
                                            {
                                                Write-Host -ForegroundColor Yellow ("While re-acquiring VM Object for {0}, Get-VM returned null.  Shutdown will continue based on previously acquired data." -f @($vmToShutdown.VM.Name))
                                            }
                                        } `
                                        else # NOT (-not $Simulated)
                                        {
                                            # Nothing
                                        }
                                    }
                                    catch
                                    {
                                        Write-Host -ForegroundColor Yellow ("Unable to re-acquire VM Object for {0}.  Shutdown will continue based on previously acquired data." -f @($vmToShutdown.VM.Name))
                                    }

                                    # We might have just re-acquired $vmPowerData.VM, so check its powerstate...
                                    if($vmToShutdown.VM.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                                    {
                                        Write-Host -NoNewline -ForegroundColor Green ("Initiated shutdown of {0} on {1}." -f @($vmToShutdown.VM.Name, $vmToShutdown.VM.VMHost.Name))

                                        $actionPerformed++
                                        $percentComplete = ($actionPerformed / $totalActions) * 100
                                        if($percentComplete -ge 100) { $percentComplete = 100 }
                                        Write-Progress -Id $progressBarId -Activity ("Processing {0}{1}" -f @($vmToShutdown.VM.Name, $simulatedStr)) -Status ("Shutting VM down | {0:N2}% complete" -f @($percentComplete)) -PercentComplete $percentComplete

                                        if((ShutdownVM -vm2Shutdown $vmToShutdown.VM -Simulated:$Simulated))
                                        {
                                            Write-Host -NoNewline -ForegroundColor Green "  Successful"
                                        } `
                                        else
                                        {
                                            Write-Host -NoNewline -ForegroundColor Red "  Failed"
                                        }
                                        if($Simulated)
                                        {
                                            Write-Host -NoNewline -ForegroundColor Yellow " (Simulated)"
                                        }
                                        Write-Host
                                    } `
                                    else
                                    {
                                        # Write-Host -ForegroundColor Yellow ("VM {0} has PowerState: {1}, shut down not initiated." -f @($vmToShutdown.VM.Name, $vmToShutdown.VM.PowerState.ToString()))
                                    }
                                } `
                                else
                                {
                                    # Nothing
                                }
                            } `
                            else # NOT ($null -ne $vmToShutdown)
                            {
                                # Nothing.
                            }

                            # Cycle to the next VM host to have a VM shutdown, or wrap back to the start of the array.
                            #   Complete this prior to updating $uniqueVMHosts so we maintain the right sequence.
                            #   If $uniqueVMHosts contains 7 hosts, and $nextHostToHaveVMShutdown == 5, then
                            #     the next statement will increment $nextHostToHaveVMShutdown to 6.
                            $nextHostToHaveVMShutdown = ($nextHostToHaveVMShutdown + 1) % $uniqueVMHosts.Length
                            #     However, after $uniqueVMHosts is updated, it may only contain 6.
                            #
                            #     This will cause an exception if we try to access $uniqueVMHosts[6] since 6 is now out of bounds for $uniqueVMHosts.
                            #     To prevent this, the last thing I will do is $nextHostToHaveVMShutdown = $nextHostToHaveVMShutdown % $uniqueVMHosts.Length.
                            #
                            #     If I were to simply increment $nextHostToHaveVMShutdown here and do the mod below, we could potentially skip [0] ...
                            #
                            #     Consider:
                            #
                            #         $uniqueVMHosts.Length = 7
                            #         $nextHostToHaveVMShutdown = 6
                            #
                            #         $nextHostToHaveVMShutdown++  (Now = 7) -- we should've wrapped to [0]...
                            #
                            #   Assume now, after the next couple statements, that:
                            #
                            #         $uniqueVMHosts.Length = 6
                            #         $nextHostToHaveVMShutdown = $nextHostToHaveVMShutdown % $uniqueVMHosts.Length   (7 % 6 = 1)
                            #
                            #   We just skipped [0], not critical, but it's still not the logical flow we expected.

                            # Continue to pare $vmPowerData down...
                            $vmPowerData = @($vmPowerData | Where-Object { -not $_.ShutdownInitiated })

<#
                            $vmPowerData = @($vmPowerData | Where-Object { `
                                (-not $_.ShutdownInitiated) -and `
                                ($_.VM.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn) `
                                -or `
                                (($null -ne $_.VDI) -and (-not $_.VDI.InMaintenanceMode) -and (-not $_.CTXMaintenanceMode))
                             })
#>
                            # Update the array of the unique VM Hosts which have powered on VMs, we are, after all shutting VMs down...
                            $uniqueVMHosts = @($vmPowerData | Select-Object @{N='VMHost'; E={ $_.VM.VMHost.Name }} | Select-Object -Unique -ExpandProperty VMHost | Sort-Object)

                            # Avoid a division by zero exception.
                            if ($uniqueVMHosts.Length -gt 0)
                            {
                                # Make sure $nextHostToHaveVMShutdown is valid.  After updating $uniqueVMHosts, there may be fewer hosts.
                                $nextHostToHaveVMShutdown = $nextHostToHaveVMShutdown % $uniqueVMHosts.Length
                            } `
                            else # NOT ($uniqueVMHosts.Length -gt 0)
                            {
                                # Nothing.
                            }
                        }

                        if((-not $Simulated) -and ($pass -eq 0))
                        {
                            Write-Host -ForegroundColor Yellow "Taking a commercial break to allow VMs to shutdown prior to running pass 2!`r`nWe'll be back in 60 seconds..."
                            Start-Sleep -Seconds 60
                        }
                    } `
                    else # NOT ($uniqueVMHosts.Length -gt 0)
                    {
                        Write-Host -ForegroundColor Yellow "WARNING: no unique VMHosts."
                    }
                } `
                else
                {
                    # Nothing
                }
            } `
            else # NOT ($continueShutdown -and ($allVMs.Length -gt 0))
            {
                # Write-Host -ForegroundColor Red "VM shutdown terminated do to inability to save the current VM powerstate data."
            }

            if ($Simulated)
            {
                $pass = 10
            } `
            else # NOT ($Simulated)
            {
                # Nothing.
            }
        }
    } `
    else # NOT ($continueShutdown)
    {

    }

    if ($continueShutdown)
    {
        Write-Host -ForegroundColor Yellow ("`r`nConsider copying {0} to a more suitable location.`r`nPath copied to the clipboard." -f @((Quoted $powerstateSavePath)))
        $powerstateSavePath | Set-Clipboard
    } `
    else # NOT ($continueShutdown)
    {
        # Nothing.
    }

    [int] $percentComplete = 100
    Write-Progress -Id $progressBarId -Activity "Complete" -Status ("{0}% complete" -f @($percentComplete)) -PercentComplete $percentComplete
}

function StartVM
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VM.UniversalVirtualMachineImpl] $vm2Start,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $citrixHost,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch]
        $Simulated
    )

    # Try to start the VM on the host it is assigned to.
    [void] $vmToStart.ExtensionData.PowerOnVM_Task($vmToStart.VMHost.ExtensionData.MoRef)

    $vdiName = "POWERENG\{0}" -f @($vmData[$a].VMName)
    try
    {
        $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName $vdiName -ErrorAction Stop
        if($null -ne $vdi)
        {
            if($vdi.InMaintenanceMode)
            {
                try
                {
                    Write-Host -ForegroundColor Yellow ("Taking Citrix VDI: {0} out of maintenance mode." -f @($vdi.MachineName))
                    Set-BrokerMachineMaintenanceMode -AdminAddress $citrixHost -InputObject $vdi -MaintenanceMode $false -ErrorAction Stop
                    Start-Sleep -Seconds 1

                    try
                    {
                        $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName $vdiName -ErrorAction Stop
                        if($vdi.InMaintenanceMode)
                        {
                            Write-Host -ForegroundColor Red ("Failed to take Citrix VDI {0} out of maintenance mode." -f @($vdi.MachineName))
                        }
                        else
                        {
                            Write-Host -ForegroundColor Gree ("Citrix VDI {0} back in service." -f @($vdi.MachineName))
                        }
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("Failed to reacquire Citrix VDI: {0}." -f @($vdiName))
                        $vdi = $null
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to place Citrix VDI {0} into maintenance mode." -f @($vdiName))
                }
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("Could not locate Citrix VDI: {0}." -f @($vdiName))
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Could not locate Citrix VDI: {0}." -f @($vdiName))
    }
}

function StartVMs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCtr,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $powerstateSavePath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $citrixHost,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch]
        $Simulated
    )

    # Flag to signal whether to continue powering up VMs or not...
    $continueStartup = $true

    # TimeSpan representing how long to wait before starting another VM on a host.
    $delayStart = [timespan]::new(0, 0, 5)
    if ($Simulated)
    {
        $delayStart = [timespan]::new(0, 0, 2)
    } `
    else # NOT ($Simulated)
    {
        # Nothing.
    }

    # Load the saved power state data...
    $vmPowerData = @()

    # How many actions (VM Start, CTX Maintenance mode) predicted to take place.  Only used if I implement a progress bar
    $totalActions = 0

    # Dictionary used to organize hosts, VMs and tasks.
    $vmProcessDict = [System.Collections.Generic.SortedDictionary[[System.String],[System.Object]]]::new()

    # Load VM power state data...
    try
    {
        Write-Host -ForegroundColor Green ("Loading VM power state data from: {0}." -f @($powerstateSavePath))
        $vmPowerData = Get-Content -LiteralPath $powerstateSavePath -ErrorAction Stop |  ConvertFrom-Json | Sort-Object VMHost,Name

        if ($vmPowerData.Length -le 0)
        {
            Write-Host -ForegroundColor Red "No VM power state data available."
            $continueStartup = $false
        } `
        else # NOT ($vmPowerData.Length -le 0)
        {
            # Nothing.
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red "`tFailed to load VM power state data."
        $continueStartup = $false
    }

    # Filter VM power state data
    if ($continueStartup)
    {
        Write-Host -ForegroundColor Green "Filtering VM power state data to include only:"
        Write-Host -ForegroundColor Green "`tVMs that were powered on at shutdown (regardless if they are VDI machines or not) or"
        Write-Host -ForegroundColor Green "`tVDI machines that were not in maintenance mode, regardless of power state"

        # Pare the data down to only the VMs that need to be processed...
        #    1. VMs that were powered on at shutdown (regardless if they are VDI machines or not)
        #    2. VDI machines that were not in maintenance mode, regardless of power state
        $vmPowerData = @($vmPowerData | Where-Object { ($_.PowerState -eq "PoweredOn") -or ($_.IsVDI -and (-not $_.CTXMaintenanceMode)) })

        if ($vmPowerData.Length -le 0)
        {
            Write-Host -ForegroundColor Red "No VM power state data left to process."
            $continueStartup = $false
        } `
        else # NOT ($vmPowerData.Length -le 0)
        {
            # Nothing.
        }
    } `
    else
    {
        # Nothing
    }

    # Collect unique VM host names...
    if ($continueStartup)
    {
        Write-Host -ForegroundColor Green "Collecting unique VM host names..."

        # Unique VM Hosts represented in the power state data...
        $uniqueVMHosts = @($vmPowerData | Select-Object -Unique -ExpandProperty VMHost | Sort-Object)

        if ($uniqueVMHosts.Length -le 0)
        {
            Write-Host -ForegroundColor Red "`tNo VM host names present in power state data."
            $continueStartup = $false
        } `
        else # NOT (-not $cont)
        {
            # Nothing.
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing
    }

    # Collect unique VM names...
    if ($continueStartup)
    {
        Write-Host -ForegroundColor Green "Collecting unique VM names..."

        # Unique VMs represented in the power state data...
        $uniqueVMNames = @($vmPowerData | Select-Object -Unique -ExpandProperty Name | Sort-Object)

        if ($uniqueVMNames.Length -le 0)
        {
            Write-Host -ForegroundColor Red "`tNo VM names present in power state data."
            $continueStartup = $false
        } `
        else # NOT ($uniqueVMNames.Length -le 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing
    }

    # Retrieve VM host objects from vCenter...
    if ($continueStartup)
    {
        try
        {
            Write-Host -ForegroundColor Green "Retrieving VM host objects from vCenter..."

            # Get all the possible VM Hosts we might need in order to power up VMs...
            #  Much quicker to get all at once vs 1 by 1
            $vmHosts = @(Get-VMHost -Server $vCtr -Name $uniqueVMHosts -ErrorAction Stop)

            if ($vmHosts.Length -le 0)
            {
                Write-Host -ForegroundColor Red "`tFailed to retrieve all required VM host objects."
                $continueStartup = $false
            } `
            else # NOT ($vmHosts.Length -le 0)
            {
                # Nothing.
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red "`tFailed to retrieve required VM Host objects (exception thrown)."
            $continueStartup = $false
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing.
    }

    # Retrieve VM objects from vCenter...
    if ($continueStartup)
    {
        try
        {
            Write-Host -ForegroundColor Green "Retrieving VM objects from vCenter..."

            # Get VM objects for all VMs we need to process...
            #  Much quicker to get all at once vs 1 by 1
            $vms = @(Get-VM -Server $vCtr -Name $uniqueVMNames -ErrorAction Stop)

            if ($vms.Length -le 0)
            {
                Write-Host -ForegroundColor Red "`tFailed to retrieve required VM objects."
                $continueStartup = $false
            } `
            else # NOT ($vms.Length -le 0)
            {
                # Nothing.
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red "`tFailed to retrieve required VM objects (exception thrown)."
            $continueStartup = $false
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing
    }

    # Collect VDI machine objects from Citrix...
    if ($continueStartup)
    {
        try
        {
            Write-Host -ForegroundColor Green ("Collecting VDI information from: {0}." -f @($citrixHost))
            $vdis = Get-BrokerMachine -AdminAddress $citrixHost -MaxRecordCount 10000 -ErrorAction Stop

            if ($vdis.Length -le 0)
            {
                Write-Host -ForegroundColor Red "`tFailed to retrieve VDI objects."
                $continueStartup = $false
            } `
            else # NOT ($vdis.Length -le 0)
            {
                # Nothing.
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red "`tFailed to retrieve required VDI objects (exception thrown)."
            $continueStartup = $false
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing
    }

    # Build VM process dictionary...
    if ($continueStartup)
    {
        Write-Host -ForegroundColor Green "Building VM process dictionary..."

        # Build $vmProcessDict...
        $a = 0
        while($a -lt $vmPowerData.Length)
        {
            $vmHost = $vmHosts | Where-Object { $_.Name -eq $vmPowerData[$a].VMHost }
            if($null -ne $vmHost)
            {
                $vmPowerData[$a].VMHost = $vmHost

                # Make sure the VM process dictionary has an entry for this VM host
                if (-not $vmProcessDict.ContainsKey($vmPowerData[$a].VMHost.Name))
                {
                    $d = "" | Select-Object NextVMIdxToProcess, VMs, CurrentTask, NextTimeVMCanBeProcessed

                    $d.NextVMIdxToProcess = 0
                    $d.VMs = [System.Collections.Generic.List[System.Object]]::new()
                    $d.CurrentTask = $null
                    $d.NextTimeVMCanBeProcessed = [DateTime]::Now   # Used to help prevent a "boot storm".  Once a VM has been started on the VM, I'll ensure I don't try to start another one for $delayStart ...

                    $vmProcessDict.Add($vmPowerData[$a].VMHost.Name, $d)
                } `
                else # NOT (-not $vmProcessDict.ContainsKey($vmPowerData[$a].VMHost.Name))
                {
                    # Nothing.
                }

                # Find the VM represented by $vmPowerData[$a].Name
                $vm = $vms | Where-Object { $_.Name -eq $vmPowerData[$a].Name }
                if($null -ne $vm)
                {
                    $vmPowerData[$a].VM = $vm

                    # If the VM needs to be powered on, increment $totalActions
                    if($vmPowerData[$a].PowerState -eq "PoweredOn")
                    {
                        $totalActions++
                    } `
                    else # NOT ($vmPowerData[$a].PowerState -eq "PoweredOn")
                    {
                        # Nothing
                    }

                    # If VM is a VDI and was not in maintenance mode when it was powered down...
                    if ($vmPowerData[$a].IsVDI -and (-not $vmPowerData[$a].CTXMaintenanceMode))
                    {
                        $vdi = $vdis | Where-Object { $_.HostedMachineName -eq $vmPowerData[$a].VM.Name }
                        if ($null -ne $vdi)
                        {
                            # Have to remove the VDI from maintenance mode...
                            $totalActions++

                            $vmPowerData[$a].VDI = $vdi
                        } `
                        else # NOT ($null -ne $vdi)
                        {
                            Write-Host -ForegroundColor Red ("`tMissing VDI object for {0}." -f @($vmPowerData[$a].VM.Name))
                            $continueStartup = $false
                        }
                    } `
                    else # NOT ($vmPowerData[$a].IsVDI -and (-not $vmPowerData[$a].CTXMaintenanceMode))
                    {
                        # Nothing.
                    }

                    if ($vmProcessDict.ContainsKey($vmPowerData[$a].VMHost.Name))
                    {
                        $vmProcessDict[$vmPowerData[$a].VMHost.Name].VMs.Add($vmPowerData[$a])
                    } `
                    else # NOT (-not $vmProcessDict.ContainsKey($vmPowerData[$a].VMHost.Name))
                    {
                        Write-Host -ForegroundColor Red ("VM process dictionary missing entry for {0}." -f @($vmPowerData[$a].VMHost.Name))
                        $continueStartup = $false
                    }
                } `
                else # NOT ($null -ne $vm)
                {
                    Write-Host -ForegroundColor Red ("`tMissing VM object for {0}." -f @($vmPowerData[$a].Name))
                    $continueStartup = $false
                }
            } `
            else # NOT ($null -ne $vmHost)
            {
                Write-Host -ForegroundColor Red ("`tMissing VM host object {0}." -f @($vmPowerData[$a].VMHost))
                $continueStartup = $false
            }
            $a++
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing
    }

    if ($continueStartup)
    {
        Write-Host -ForegroundColor Green "Processing VMs..."

        # While there are more VMs to process...
        while(@(@($vmProcessDict.Values) | Where-Object { $_.NextVMIdxToProcess -lt $_.VMs.Count }).Length -gt 0)
        {
            # Select the first host entry where:
            #   1) The host's .CurrentTask is:
            #       1a) $null
            #       1b) -or ((-not $null) -and (.CurrentTask.State -eq Success))
            #   2) -and there are more VMs to process for the host (.NextVMIdxToProcess -lt .VMs.Count)
            #   3) -and enough time has passed since the last VM was processed (.NextTimeVMCanBeProcessed -le [DateTime]::Now))
            #   the next host where a VM can be started... if any are available -- all might have start tasks running.
            $hostWithIdleTaskAndMoreVMsToProcess = @($vmProcessDict.Values) | Where-Object {
                (($null -eq $_.CurrentTask) `
                    -or ($_.CurrentTask.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success)) `
                -and ($_.NextVMIdxToProcess -lt $_.VMs.Count) `
                -and ($_.NextTimeVMCanBeProcessed -le [DateTime]::Now)} | Select-Object -First 1

            # If there is a host entry available to process, then let's try...
            if ($null -ne $hostWithIdleTaskAndMoreVMsToProcess)
            {
                $vmHostName = @($vmProcessDict.Keys) | Where-Object { $vmProcessDict[$_] -eq $hostWithIdleTaskAndMoreVMsToProcess }
                if ([String]::IsNullOrEmpty($vmHostName))
                {
                    $vmHostName = "!!UNKNOWN!!"
                } `
                else # NOT ([String]::IsNullOrEmpty($vmHostName))
                {
                    # Nothing.
                }

                $vmToProcess = $hostWithIdleTaskAndMoreVMsToProcess.VMs[$hostWithIdleTaskAndMoreVMsToProcess.NextVMIdxToProcess]

                if ($null -ne $vmToProcess)
                {
                    Write-Host -ForegroundColor Green ("`tProcessing {0}..." -f @($vmToProcess.Name))

                    # The following it to give the host at least $delayStart before processing another VM...
                    $hostWithIdleTaskAndMoreVMsToProcess.NextTimeVMCanBeProcessed = [DateTime]::Now + $delayStart

                    <#
                        If the VM has not been started up yet, then we'll do that.
                            If the VM is not a VDI machine, then I'll advance .NextVMIdxToProcess.  If it is
                            a VDI machine, I will skip advancing .NextVMIdxToProcess so the same object will be picked
                            up the next time this host entry is processed -- except, the 2nd time, we'll remove the VDI
                            from maintenance mode.
                        If the VM has been started up, then the only other reason we'd see the same object
                        again is because it is also a VDI machine that needs to be removed from maintenance mode.
                        Of course, I'll verify first.
                    #>

                    # If the VM has not been powered on, then do so...
                    if (-not $vmToProcess.StartupInitiated)
                    {
                        Write-Host -ForegroundColor Green ("`t`tStartup proccess initiated for {0}..." -f @($vmToProcess.VM.Name))
                        Write-Host -ForegroundColor Green ("`t`tDoubling checking {0}'s power state..." -f @($vmToProcess.VM.Name))
                        $vmToProcess.StartupInitiated = $true

                        # Get the latest data about the VM incase it was powered up external to this script.
                        try
                        {
                            $vm = Get-VM -Server $vCtr -Name $vmToProcess.VM.Name -ErrorAction Stop
                            if ($null -ne $vm)
                            {
                                $vmToProcess.VM = $vm
                            } `
                            else # NOT ($null -ne $vm)
                            {
                                # Nothing.
                            }
                        }
                        catch
                        {
                            # Nothing, just carry on the with existing VM object...
                        }

                        # Sanity check to make sure the VM is not already powered on...
                        if ($vmToProcess.VM.PowerState -ne [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                        {
                            if (-not $Simulated)
                            {
                                try
                                {
                                    # Try to power on the VM...
                                    Write-Host -ForegroundColor Green ("`t`tPowering up {0}..." -f @($vmToProcess.VM.Name))
                                    $vmToProcess.VM.ExtensionData.PowerOnVM_Task($vmToProcess.VMHost.ExtensionData.MoRef)
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Red ("`t`tException thrown while trying to power on: {0}." -f @($vmToProcess.VM.Name))
                                }

                                # Capture the vCenter task related to this VM power up.
                                try
                                {
                                    # NOTE:  I don't like doing this here, then more or less repeating it at the end of the while loop,
                                    #   but I didn't want to create more complex code just to prevent sort-of repeated code.  If a VM isn't started
                                    #   during an iteration of the while-loop, then getting the running vCenter tasks here wouldn't happen, which in turn
                                    #   means I can't rely on have accurate task information later without having retrieved it when it was actually needed.

                                    # Get all "PowerOnVM_Tasks"...
                                    $vmTasks = @(Get-Task -Server $vCtr -ErrorAction Stop | Where-Object { $_.Name -eq "PowerOnVM_Task" } | Sort-Object StartTime )

                                    # Set .CurrentTask to PowerOnVM_Task for the VM that was just started...
                                    #   If I don't get the task, that's fine, we'll just rely on $delayStart...
                                    $hostWithIdleTaskAndMoreVMsToProcess.CurrentTask = $vmTasks | Where-Object { ($_.ObjectId -eq $vmToProcess.VM.Id) -and ($_.Name -eq "PowerOnVM_Task") } | Select-Object -Last 1
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Red ("`t`tException thrown trying to retrieve tasks from {0}." -f @($vCtr.Name))
                                }
                            } `
                            else # NOT (-not $Simulated)
                            {
                                Write-Host -ForegroundColor Yellow "`t`t`tSimulated"
                            }
                        } `
                        else # NOT ($vmToProcess.VM.PowerState -ne [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
                        {
                            Write-Host -ForegroundColor Yellow ("`t`t{0} is already powered up." -f @($vmToProcess.VM.Name))
                        }

                        # If the VM is a VDI machine and was not in maintainence mode when it was shut down and Citrix still shows it in maintenance mode...
                        if (($null -ne $vmToProcess.VDI) -and (-not $vmToProcess.CTXMaintenanceMode) -and ($vmToProcess.VDI.InMaintenanceMode))
                        {
                            # ... then do not increment .NextVMIdxToProcess -- still need to take the VDI associated with this VM out of maintenance mode
                        } `
                        else # NOT (($null -ne $vmToProcess.VDI) -and (-not $vmToProcess.CTXMaintenanceMode) -and ($vmToProcess.VDI.InMaintenanceMode))
                        {
                            # Either this VM is not a VDI machine, or it is and was already in maintenance mode when it was shut down, or it wasn't in
                            #   maintenance mode when it was shut down, but Citrix shows the VDI is not currently in maintenance mode, so we can move to the next VM.
                            $hostWithIdleTaskAndMoreVMsToProcess.NextVMIdxToProcess++
                        }
                    } `
                    else # NOT (-not $vmToProcess.StartupInitiated)
                    {
                        Write-Host -ForegroundColor Green ("`t`tStartup has already been initiated for {0} must be a VDI..." -f @($vmToProcess.VM.Name))

                        # We already tried to power up the VM, so chances are this is a VDI machine that needs to be taken out of maintenance mode...

                        # If the VM is a VDI machine, it was not in maintain mode when it was shut down, and Citrix still shows it in maintenance mode...
                        if (($null -ne $vmToProcess.VDI) -and (-not $vmToProcess.CTXMaintenanceMode) -and ($vmToProcess.VDI.InMaintenanceMode))
                        {
                            # ... then take the VDI associated with this VM out of maintenance mode

                            Write-Host -ForegroundColor Green ("`t`tTaking VDI: {0} out of maintenance mode." -f @($vmToProcess.VDI.MachineName))

                            # Not need to delay further for this host...
                            $hostWithIdleTaskAndMoreVMsToProcess.NextTimeVMCanBeProcessed = [DateTime]::Now
                            if (-not $Simulated)
                            {
                                try
                                {
                                    Set-BrokerMachineMaintenanceMode -AdminAddress $citrixHost -InputObject $vmToProcess.VDI -MaintenanceMode $false -ErrorAction Stop | Out-Null

                                    # Pause for a second before trying to verify the action stuck...
                                    Start-Sleep -Seconds 1

                                    try
                                    {
                                        $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName $vmToProcess.VDI.MachineName -ErrorAction Stop
                                        if(($null -ne $vdi) -and $vdi.InMaintenanceMode)
                                        {
                                            Write-Host -ForegroundColor Red ("`t`t`tFailed to take VDI {0} out of maintenance mode." -f @($vdi.MachineName))
                                        }
                                        else
                                        {
                                            Write-Host -ForegroundColor Green ("`t`t`tVDI {0} back in service." -f @($vdi.MachineName))
                                        }
                                    }
                                    catch
                                    {
                                        Write-Host -ForegroundColor Red ("`t`t`tFailed to re-acquire VDI machine: {0}." -f @($vmToProcess.VDI.MachineName))
                                    }
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Red ("`t`t`tException thrown trying to take VDI {0} out of maintenance mode." -f @($vmToProcess.VDI.MachineName))
                                }
                            } `
                            else # NOT (-not $Simulated)
                            {
                                Write-Host -ForegroundColor Yellow "`t`t`tSimulated"
                            }
                        } `
                        else # NOT (($null -ne $vmToProcess.VDI) -and (-not $vmToProcess.CTXMaintenanceMode) -and ($vmToProcess.VDI.InMaintenanceMode))
                        {
                            # Nothing, not a VDI, or it is and doesn't need to be taken out of maintenance mode.
                            if ($null -eq $vmToProcess.VDI)
                            {
                                Write-Host -ForegroundColor Green ("`t`t{0} is not a VDI." -f @($vmToProcess.VM.Name))
                            } `
                            else # NOT ($null -eq $vmToProcess.VDI)
                            {
                                if (-not $vmToProcess.CTXMaintenanceMode)
                                {
                                    Write-Host -ForegroundColor Green ("`t`t{0} is a VDI but was not in maintenance mode when it was shutdown." -f @($vmToProcess.VM.Name))
                                } `
                                else # NOT (-not $vmToProcess.CTXMaintenanceMode)
                                {
                                    Write-Host -ForegroundColor Green ("`t`t{0} is a VDI and was in maintenance mode when it was shutdown." -f @($vmToProcess.VM.Name))
                                    if ($vmToProcess.VDI.InMaintenanceMode)
                                    {
                                        Write-Host -ForegroundColor Green ("`t`t{0} is a VDI, was in maintenance mode when it was shutdown, and is still in maintenance mode." -f @($vmToProcess.VM.Name))
                                    } `
                                    else # NOT ($vmToProcess.VDI.InMaintenanceMode)
                                    {
                                        # Nothing.
                                    }
                                }
                            }
                        }

                        # Move to the next VM to process
                        $hostWithIdleTaskAndMoreVMsToProcess.NextVMIdxToProcess++
                    }
                } `
                else # NOT ($null -ne $vmToProcess)
                {
                    Write-Host -ForegroundColor Red ("`t`tNull VM found for {0}, index {1}." -f @($vmHostName, $hostWithIdleTaskAndMoreVMsToProcess.NextVMIdxToProcess))

                    # Move to the next VM to process
                    $hostWithIdleTaskAndMoreVMsToProcess.NextVMIdxToProcess++
                }
            } `
            else # NOT ($null -ne $hostWithIdleTaskAndMoreVMsToStart)
            {
<#
                # Everything is busy... let's give it time to soak...
                Write-Host -ForegroundColor Green "`r`nPausing for station identification..."
                Start-Sleep -Milliseconds $delayStart.TotalMilliseconds
                Write-Host
#>
            }

            # If we get here, then we KNOW there were VMs left to start, even if we didn't actually start one -- all hosts might have active power on VM tasks.
            #   So, let's get the current PowerOnVM_Tasks from vCenter and update our task trackers accordingly...

            try
            {
                # See NOTES above -- after a VM is powered on...
                $vmTasks = @(Get-Task -Server $vCtr -ErrorAction Stop | Where-Object { $_.Name -eq "PowerOnVM_Task" } | Sort-Object StartTime )
                @($vmProcessDict.Values) | ForEach-Object {
                    $thisHost = $_

                    if ($null -ne $thisHost.CurrentTask)
                    {
                        $thisHost.CurrentTask = $vmTasks | Where-Object { $_.ObjectId -eq $thisHost.CurrentTask.ObjectId } | Select-Object -Last 1
                    } `
                    else # NOT ($null -ne $thisHost.CurrentTask)
                    {
                        # Nothing.
                    }
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red "`tException thrown for Get-Task."
            }
        }
    } `
    else # NOT ($continueStartup)
    {
        # Nothing.
    }

}

# ConnectTo -keywords prod,vcenter
# ShutdownVMs -vCtr $vCenter -citrixHost "cdc-ctx-dc01.powereng.com" -vmLocations @("DDC","DDC-VDI") -vmExceptions @("BDC-DC01","BDC-DC02") -Simulated

# StartVMs -vCtr $vCenter -powerstateSavePath "C:\Users\kbriney-adm\AppData\Local\Temp\2\20221105_132603-vmPowerState.json" -citrixHost "cdc-ctx-dc01.powereng.com" -Simulated


# REMEMBER TO UNCOMMENT THE ACTION LINES IN STARTVMS...
# StartVMs -vCtr $vCenter -powerstateSavePath "C:\Users\kbriney-adm\Desktop\20221105_060354-vmPowerState.json" -citrixHost "cdc-ctx-dc01.powereng.com" -Simulated



<#
$error.Clear()
try
{
    Write-Host "Attempting shutdown..."
    $k.ExtensionData.ShutdownGuest()
}
catch
{
    if (($null -ne $_) -and ($null -ne $_.Exception))
    {
        $ex = $_.Exception
        if ($ex.Message -eq "Exception calling `"ShutdownGuest`" with `"0`" argument(s): `"Cannot complete operation because VMware Tools is not running in this virtual machine.`"")
        {
            try
            {
                Write-Host "Attempting power off"
                $k.ExtensionData.PowerOffVM()
            }
            catch
            {
                $ee = $_.Exception
            }
        } `
        else # NOT ($ex.Message)
        {
            # Nothing.
        }
    } `
    else # NOT (($null -ne $_) -and ($null -ne $_.Exception))
    {
        # Nothing
    }
}


$error.Clear()
try
{
    $t1 = $k.ExtensionData.PowerOnVM_Task($k.VMHost.ExtensionData.MoRef)
    $vmTasks = Get-Task -Server $labvCenter
}
catch
{

}
#>
