# (@(Get-BrokerDesktop -AdminAddress "cdc-ctx-dc01.powereng.com" -Filter {(HostedMachineName -like "*vcad*") -or (HostedMachineName -like "*vgis*") } -MaxRecordCount 1000 | Select-Object -ExpandProperty AssociatedUserUPNs -Unique) -join "; " ) | Set-Clipboard
#$hh = Get-BrokerDesktop -AdminAddress "cdc-ctx-dc01.powereng.com"
Add-PSSnapin Citrix.*

function GetVDIAffectedUsersAndVMs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $citrixHost,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String[]] $vmHostNames
    )

    # $citrixHost = "cdc-ctx-dc01.powereng.com"

    # $userHostsInMaintenance = @("DDC-ESXVCAD02", "DDC-ESXVCAD03" )
    $affectedUsers = @()
    $affectedVMs = @()

    $a = 0
    while($a -lt $vmHostNames.Length)
    {
        $matchExpr = "{0}*" -f @($vmHostNames[$a])

        $brokerData = @(Get-BrokerDesktop -AdminAddress $citrixHost -Filter { (HostingServerName -like $matchExpr) } -MaxRecordCount 5000)
        $hostUsers = @($brokerData | Select-Object -ExpandProperty AssociatedUserUPNs -Unique | Sort-Object)
        $hostVMs = @($brokerData | Select-Object -ExpandProperty HostedMachineName -Unique | Sort-Object)
        $b = 0
        while($b -lt $hostUsers.Length)
        {
            if($affectedUsers -notcontains $hostUsers[$b])
            {
                $affectedUsers += $hostUsers[$b]
            }
            $b++
        }

        $b = 0
        while($b -lt $hostVMs.Length)
        {
            if($affectedVMs -notcontains $hostVMs[$b])
            {
                $affectedVMs += $hostVMs[$b]
            }
            $b++
        }

        $a++
    }

    return @($affectedUsers, $affectedVMs)
}


# (@(Get-BrokerDesktop -AdminAddress $citrixHost -Filter { (HostingServerName -like $matchExpr) } -MaxRecordCount 5000 | Select-Object -ExpandProperty AssociatedUserUPNs -Unique) -join "; " )

# $maintenanceWindow = "Monday, 9/19 from 7pm MDT to 10pm MDT"

function GetVDIVMData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $citrixHost,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String[]] $vmHostNames,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [Object[]] $affectedVMs
    )

    $vmData = @()

    $a = 0
    while($a -lt $vmHostNames.Length)
    {
        try
        {
            $vmHost = Get-VMHost -Server $viServer -Name ("{0}.powereng.com" -f @($vmHostNames[$a])) -ErrorAction Stop

            try
            {
                $hostVMs = Get-VM -Server $viServer -Location $vmHost -ErrorAction Stop
                $b = 0
                while($b -lt $hostVMs.Length)
                {
                    if($hostVMs[$b].Name -notmatch "vCLS")
                    {
                        if($affectedVMs -notcontains $hostVMs[$b].Name)
                        {
                            Write-Host ("Added {0} to affected VMs list." -f @($hostVMs[$b].Name))
                            $affectedVMs += $hostVMs[$b].Name
                        }
                    }
                    $b++
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to retrieve VMs for host: {0}." -f @(("{0}.powereng.com" -f @($vmHostNames[$a]))))
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to retrieve VM host: {0}." -f @(("{0}.powereng.com" -f @($vmHostNames[$a]))))
        }
        $a++
    }

    $a = 0
    while ($a -lt $affectedVMs.Length)
    {
        $d = "" | Select-Object VMName,VMHost,PowerState,InMaintenanceMode,VMXPath,Networks
        $d.VMName = $affectedVMs[$a]

        $vm = Get-VM -Server $viServer -Name $d.VMName
        $d.VMHost = $vm.VMHost.Name

        if($null -ne $vm)
        {
            $d.PowerState = $vm.PowerState.ToString()
            $d.VMXPath = $vm.Extensiondata.Summary.Config.VmPathName
            try
            {
                $vmNIC = @(Get-NetworkAdapter -Server $viServer -VM $vm)
                $d.Networks = @($vmNIC | ForEach-Object { "{0}:{1}" -f @($_.Name,$_.NetworkName) }) -join ";"
            }
            catch
            {
                Write-Host -ForegroundColor Yellow ("Failed to get network adapters for {0}." -f @($vm.Name))
            }
            try
            {
                $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName ("POWERENG\{0}" -f @($affectedVMs[$a])) -ErrorAction Stop
                if($null -ne $vdi)
                {
                    $d.InMaintenanceMode = $vdi.InMaintenanceMode
                }
                else
                {
                    Write-Host -ForegroundColor Yellow ("Could not locate Citrix VDI: POWERENG\{0}." -f @($d.VMName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Yellow ("Could not locate Citrix VDI machine for: {0}" -f @($d.VMName))
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($d.VMName))
        }

        $vmData += $d
        $a++
    }

    try
    {
        $tmpFileName = [System.IO.Path]::GetTempFileName()
        $vmData | Sort-Object VMHost,VMName | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Out-File -FilePath $tmpFileName
        Write-Host -ForegroundColor Gree ("VM data saved to temporary file: {0}" -f @($tmpFileName))
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed to same VM data to temporary file."
    }

    return $vmData
}

# Save $vmData to file..

# Place Citrix VDIs in maintenance mode.
function ShutdownVDIs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $citrixHost,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [Object[]] $vmData,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $takeAction
    )

    $a = 0
    while($a -lt $vmData.Length)
    {
        $vdiName = "POWERENG\{0}" -f @($vmData[$a].VMName)
        try
        {
            $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName $vdiName -ErrorAction Stop
            if($null -ne $vdi)
            {
                if(-not $vdi.InMaintenanceMode)
                {
                    try
                    {
                        Write-Host -ForegroundColor Yellow ("Placing Citrix VDI: {0} into maintenance mode." -f @($vdi.MachineName))
                        if ($takeAction)
                        {
                            Set-BrokerMachineMaintenanceMode -AdminAddress $citrixHost -InputObject $vdi -MaintenanceMode $true -ErrorAction Stop
                            # Start-Sleep -Seconds 5
                        } `
                        else # NOT ($takeAction)
                        {
                            Write-Host -ForegroundColor Yellow ("Simulated placing {0} into maintenance mode." -f @($vdiName))
                        }

                        # If we aren't taking action, then there is no reason to make another call to the Citrix server
                        if($takeAction)
                        {
                            try
                            {
                                $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName $vdiName -ErrorAction Stop
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("Failed to reacquire Citrix VDI: {0}." -f @($vdiName))
                                $vdi = $null
                            }
                        }
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("Failed to place Citrix VDI {0} into maintenance mode." -f @($vdiName))
                    }
                }

                if($null -ne $vdi)
                {
                    if((-not $takeAction) -or ($vdi.InMaintenanceMode))
                    {
                        Write-Host -ForegroundColor Green ("Citrix VDI: {0} in maintenance mode." -f @($vdi.MachineName))
                        if(-not $takeAction)
                        {
                            Write-Host -ForegroundColor Green "`tSimulated"
                        }

                        try
                        {
                            $vm = Get-VM -Server $viServer -Name $vmData[$a].VMName -ErrorAction Stop
                            if($null -ne $vm)
                            {
                                if($vm.PowerState -ne "PoweredOff")
                                {
                                    Write-Host -ForegroundColor Yellow ("Shutting down VM: {0}..." -f @($vmData[$a].VMName))
                                    if(-not $takeAction)
                                    {
                                        Write-Host -ForegroundColor Yellow "`tSimulated"
                                    }
                                    else
                                    {
                                        try
                                        {
                                            Stop-VMGuest -VM $vm -Server $viServer -Confirm:$false -ErrorAction Stop | Out-Null
                                        }
                                        catch
                                        {
                                            Write-Host -ForegroundColor Red ("Failed to shutdown VM: {0}" -f @($vm.Name))
                                        }
                                    }
                                }
                                else
                                {
                                    Write-Host -ForegroundColor Green ("VM: {0} is already powered off." -f @($vm.Name))
                                }
                            }
                            else
                            {
                                Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
                            }
                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red ("Citrix VDI: {0} not in maintenance mode." -f @($vdi.MachineName))
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
        $a++
    }
}

function RestartVDIs
{
    # Power VDI VMs back on.
    $a = 0
    while($a -lt $vmData.Length)
    {
        if($vmData[$a].PowerState -eq "PoweredOn")
        {
            try
            {
                $vm = Get-VM -Server $vCenter -Name $vmData[$a].VMName -ErrorAction Stop
                if($null -ne $vm)
                {
                    if($vm.PowerState -ne "PoweredOn")
                    {
                        Write-Host ("Starting VM: {0}..." -f @($vmData[$a].VMName))
                        try
                        {
                            Start-VM -VM $vm -Server $vCenter -Confirm:$false -ErrorAction Stop -RunAsync | Out-Null
                            Start-Sleep -Seconds 1
                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red ("Failed to start VM: {0}" -f @($vm.Name))
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Green ("VM: {0} is already powered off." -f @($vm.Name))
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
            }
        }
        $a++
    }
}

# Take Citrix VDIs out of maintenance mode
$a = 0
while($a -lt $vmData.Length)
{
    if(-not $vmData[$a].InMaintenanceMode)
    {
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
    $a++
}


# Test connection to each VDI...
$a = 0
while($a -lt $vmData.Length)
{
    if($vmData[$a].PowerState -eq "PoweredOn")
    {
        try
        {
            $vm = Get-VM -Server $vCenter -Name $vmData[$a].VMName -ErrorAction Stop
            if($null -ne $vm)
            {
                if($vm.PowerState -eq "PoweredOn")
                {
                    Write-Host ("Testing VM: {0}..." -f @($vmData[$a].VMName))
                    try
                    {
                        if(Test-Connection -ComputerName $vmData[$a].VMName -Quiet)
                        {
                            Write-Host -ForegroundColor Green ("VDI {0} is alive" -f @($vmData[$a].VMName))
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red ("VDI {0} is not online" -f @($vmData[$a].VMName))
                        }
                    }
                    catch
                    {
                       Write-Host -ForegroundColor Red ("VDI {0} is not online" -f @($vmData[$a].VMName))
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red ("VM: {0} is not running." -f @($vm.Name))
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Could not locate VM: {0}." -f @($vmData[$a].VMName))
        }
    }
    $a++
}


$affectedHosts = @("CDC-ESXVCAD01") # ,"CDC-ESXVCAD02","DDC-ESXVCAD01","DDC-ESXVCAD02","DDC-ESXVCAD03","DDC-ESXVCAD04","DDC-ESXVCAD05","DDC-ESX-C1-B4")
$vdiUsers,$vdiVMs = GetVDIAffectedUsersAndVMs -citrixHost "cdc-ctx-dc01.powereng.com" -vmHostNames $affectedHosts

$vdiUsers -join "; " | Set-Clipboard


$vmData = GetVDIVMData -viServer $vCenter -citrixHost "cdc-ctx-dc01.powereng.com" -vmHostNames $affectedHosts -affectedVMs $vdiVMs
ShutdownVDIs -viServer $vCenter -citrixHost $citrixHost -vmData $vmData -takeAction





try
{
    $vdi = Get-BrokerMachine -AdminAddress $citrixHost -MachineName "POWERENG\BDC-DC01" -ErrorAction Stop
    if(-not $vdi.InMaintenanceMode)
    {
        Write-Host ("Placing {0} in maintenance mode." -f @($vdi.HostedMachineName))
    }
}
catch
{
    Write-Host "Not a VDI"
}
