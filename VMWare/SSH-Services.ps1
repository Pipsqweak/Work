
function Check-SSHService()
{
    $vmHosts = Get-VMHost | Sort-Object Name
    $a = 0
    while($a -lt $vmHosts.Length)
    {
        Write-Host -NoNewline ("Checking SSH service details on {0}..." -f @($vmHosts[$a].Name))
        try
        {
            $sshService = Get-VMHostService -VMHost $vmHosts[$a] -ErrorAction Stop | Where-Object { $_.Key -eq "TSM-SSH" }
            if($null -ne $sshService)
            {
                if($sshService.Running)
                {
                    Write-Host -ForegroundColor Red "SSH Service is running"
                }
                else
                {
                    Write-Host -ForegroundColor Green "SSH service not running"
                }
            }
            else
            {
                Write-Host -ForegroundColor Red "SSH service not found."
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red "Failed to acquire host SSH service status."
        }

        $a++
    }
}

function Start-SSHService
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $vmHost
    )

    if($null -ne $vmHost)
    {
        if($vmHost -is [String])
        {
            try
            {
                $tObj = Get-VMHost -Name $vmHost -ErrorAction Stop
                if($null -ne $tObj)
                {
                    if($tObj -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])
                    {
                        Start-SSHService $tObj
                    }
                }
            }
            catch
            {
                throw
            }
        }
        else
        {
            if($vmHost -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])
            {
                Write-Host ("Attempting to start SSH service on {0}" -f @($vmHost.Name))
                $sshService = Get-VMHostService -VMHost $vmHost -ErrorAction Stop | Where-Object { $_.Key -eq "TSM-SSH" }

                if($null -ne $sshService)
                {
                    if($sshService.Policy -ne "off")
                    {
                        Write-Host "`tReconfiguring SSH service to manually start/stop."
                        $messageColor = [ConsoleColor]::Green
                        try
                        {
                            Set-VMHostService -HostService $sshService -Policy Off -Confirm:$false -ErrorAction Stop | Out-Null
                            Write-Host -ForegroundColor $messageColor -NoNewline "`t`tSuccessfully"
                        }
                        catch
                        {
                            $messageColor = [ConsoleColor]::Red
                            Write-Host -ForegroundColor $messageColor -NoNewline "`t`tFailed to"
                        }
                        Write-Host -ForegroundColor $messageColor " set SSH service start up policy to OFF"
                    }
                    else
                    {
                        Write-Host "`tSSH service start up policy already set to off."
                    }

                    if(-not $sshService.Running)
                    {
                        $messageColor = [ConsoleColor]::Green
                        try
                        {
                            Start-VMHostService -HostService $sshService -Confirm:$false -ErrorAction Stop | Out-Null
                            Write-Host -ForegroundColor $messageColor -NoNewline "`tSuccessfully started"
                        }
                        catch
                        {
                            $messageColor = [ConsoleColor]::Red
                            Write-Host -ForegroundColor $messageColor -NoNewline "`tFailed to start"
                        }
                        Write-Host -ForegroundColor $messageColor " SSH service"
                    }
                    else
                    {
                        Write-Host "`tSSH service already running"
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red "`tSSH service not found."
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("`$vmHost is not an appropriate type in Stop-SSHService.  [{0}]" -f @($vmHost.GetType().FullName))
            }
        }
    }
}

function Stop-SSHService
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $vmHost
    )

    if($null -ne $vmHost)
    {
        if($vmHost -is [String])
        {
            try
            {
                $tObj = Get-VMHost -Name $vmHost -ErrorAction Stop
                if($null -ne $tObj)
                {
                    if($tObj -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])
                    {
                        Stop-SSHService $tObj
                    }
                }
            }
            catch
            {
                throw
            }
        }
        else
        {
            if($vmHost -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])
            {
                Write-Host ("Attempting to stop SSH service on {0}" -f @($vmHost.Name))

                try
                {
                    $sshService = Get-VMHostService -VMHost $vmHost -ErrorAction Stop | Where-Object { $_.Key -eq "TSM-SSH" }

                    if($null -ne $sshService)
                    {
                        if($sshService.Policy -ne "off")
                        {
                            Write-Host "`tReconfiguring SSH service to manually start/stop."
                            $messageColor = [ConsoleColor]::Green
                            try
                            {
                                Set-VMHostService -HostService $sshService -Policy Off -Confirm:$false -ErrorAction Stop | Out-Null
                                Write-Host -ForegroundColor $messageColor -NoNewline "`t`tSuccessfully"
                            }
                            catch
                            {
                                $messageColor = [ConsoleColor]::Red
                                Write-Host -ForegroundColor $messageColor -NoNewline "`t`tFailed to"
                            }
                            Write-Host -ForegroundColor $messageColor " set SSH service start up policy to OFF"
                        }
                        else
                        {
                            Write-Host "`tSSH service start up policy already set to off."
                        }

                        if($sshService.Running)
                        {
                            $messageColor = [ConsoleColor]::Green
                            try
                            {
                                Stop-VMHostService -HostService $sshService -Confirm:$false -ErrorAction Stop | Out-Null
                                Write-Host -ForegroundColor $messageColor -NoNewline "`tSuccessfully stopped"
                            }
                            catch
                            {
                                $messageColor = [ConsoleColor]::Red
                                Write-Host -ForegroundColor $messageColor -NoNewline "`tFailed to stop"
                            }
                            Write-Host -ForegroundColor $messageColor " SSH service"
                        }
                        else
                        {
                            Write-Host "`tSSH service already running"
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red "`tSSH service not found."
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red "`tFailed to acquire host services"
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("`$vmHost is not an appropriate type in Stop-SSHService.  [{0}]" -f @($vmHost.GetType().FullName))
            }
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "Missing VM Host in Stop-SSHService."
    }
}
