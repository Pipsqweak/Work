
function Check-SSHService()
{
    $vmHosts = Get-VMHost -Server $vCenter
    $a = 0
    while($a -lt $vmHosts.Length)
    {
        Write-Host ("`r`nChecking SSH service details on {0}" -f @($vmHosts[$a].Name))
        $vmHostServices = $null
        try
        {
            $vmHostServices = @(Get-VMHostService -VMHost $vmHosts[$a] -ErrorAction Stop)
        }
        catch
        {
            Write-Host -ForegroundColor Red "`tFailed to acquire host services"
        }

        if($null -ne $vmHostServices)
        {
            $sshService = $vmHostServices | Where-Object { $_.Key -eq "TSM-SSH" }
            if($null -ne $sshService)
            {
                if($sshService.Running)
                {
                    Write-Host -ForegroundColor Red "`tSSH Service is running"
                }
                else
                {
                    Write-Host -ForegroundColor Green "`tSSH service not running"
                }
            }
            else
            {
                Write-Host -ForegroundColor Red "`tSSH service not found."
            }
        }

        $a++
    }

}

function Start-SSHService($vmHost)
{
    Write-Host ("Attempting to start SSH service on {0}" -f @($vmHost.Name))
    $vmHostServices = $null
    try
    {
        $vmHostServices = @(Get-VMHostService -VMHost $vmHost -ErrorAction Stop)
    }
    catch
    {
        Write-Host -ForegroundColor Red "`tFailed to acquire host services"
    }

    if($null -ne $vmHostServices)
    {
        $sshService = $vmHostServices | Where-Object { $_.Key -eq "TSM-SSH" }
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
        Write-Host -ForegroundColor Red ("Failed to detect SSH service on {0}." -f @($vmHost.Name))
    }
}

function Stop-SSHService($vmHost)
{
    Write-Host ("Attempting to stop SSH service on {0}" -f @($vmHost.Name))
    $vmHostServices = $null
    try
    {
        $vmHostServices = @(Get-VMHostService -VMHost $vmHost -ErrorAction Stop)
    }
    catch
    {
        Write-Host -ForegroundColor Red "`tFailed to acquire host services"
    }

    if($null -ne $vmHostServices)
    {
        $sshService = $vmHostServices | Where-Object { $_.Key -eq "TSM-SSH" }
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
    else
    {
        Write-Host -ForegroundColor Red ("Failed to detect SSH service on {0}." -f @($vmHost.Name))
    }
}
