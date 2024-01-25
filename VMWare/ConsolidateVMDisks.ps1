$maxConsolidations = 3

function GetVMsNeedingConsolidation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCtr
    )

    $vmDiskConsolidations = [System.Collections.Generic.List[System.Object]]::new()

    try
    {
        @(Get-VM -Server $vCtr -ErrorAction Stop | Where-Object { $_.ExtensionData.Runtime.ConsolidationNeeded }) | ForEach-Object {
            $d = "" | Select-Object VM, Task

            $d.VM = $_
            $d.Task = $null

            $vmDiskConsolidations.Add($d)
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to acquire VMs needing consolidation from {0}.  Exception thrown." -f @($vCtr.Name))
    }

    return @( ,$vmDiskConsolidations)
}

function UpdateDiskConsolidationTasks
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCtr,

        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]] $vmDCs
    )

    $vmDiskConsolidationTasks = @()

    try
    {
        # Get all ConsolidateVMDisks_Task vCenter tasks...
        $vmDiskConsolidationTasks = @(Get-Task -Server $vCtr -ErrorAction Stop | Where-Object { $_.Name -eq "ConsolidateVMDisks_Task"})
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Exception thrown trying to get tasks from {0}." -f @($vCtr.Name))
    }

    if ($vmDiskConsolidationTasks.Length -gt 0)
    {
        # Update our monitored tasks...
        $a = 0
        while($a -lt $vmDCs.Count)
        {
            $vmDiskConsolidation = $vmDCs[$a]

            # If $vmDiskConsolidation.Task has not been set, then look for its task based on (task).ObjectId -eq $vmDiskConsolidation.VM.Id
            if ($null -eq $vmDiskConsolidation.Task)
            {
                # Find a task with .ObjectId -eq .VM.Id
                $task = $vmDiskConsolidationTasks | Where-Object { $_.ObjectId -eq $vmDiskConsolidation.VM.Id }
                if ($null -ne $task)
                {
                    $vmDiskConsolidation.Task = $task
                } `
                else # NOT ($null -ne $task)
                {
                    # Nothing -- no task matching $vmDiskConsolidation.VM.Id
                }
            } `
            else # NOT ($null -eq $vmDiskConsolidation.Task)
            {
                # There is already a task associated with $vmDiskConsolidation.Task, so let's try to update it...
                $task = $vmDiskConsolidationTasks | Where-Object { $_.Id -eq $vmDiskConsolidation.Task.Id }
                if ($null -ne $task)
                {
                    # Task found, update $vmDiskConsolidation.Task
                    $vmDiskConsolidation.Task = $task
                    Write-Progress -ParentId 1 -Id ([int] ($vmDiskConsolidation.Task.Id.Replace("Task-task-",""))) -Activity ("{0}" -f @($vmDiskConsolidation.VM.Name)) -Status ("{0}% complete" -f @($vmDiskConsolidation.Task.PercentComplete)) -PercentComplete $vmDiskConsolidation.Task.PercentComplete
                   Write-Host ("`r`n{0} - {1}" -f @($vmDiskConsolidation.VM.Name, $vmDiskConsolidation.Task.PercentComplete))
                } `
                else # NOT ($null -ne $task)
                {
                    # Evidently, the task associated with $vmDiskConsolidation has completed and dropped off the radar...
                    #  So remove it from the list.
                    Write-Progress -ParentId 1 -Id ([int] ($vmDiskConsolidation.Task.Id.Replace("Task-task-",""))) -Activity ("{0}" -f @($vmDiskConsolidation.VM.Name)) -Status "100% complete" -PercentComplete 100
                    [void] $vmDCs.Remove($vmDiskConsolidation)
                    $vmDiskConsolidation = $null
                }
            }

            # Remove $vmDiskConsolidation from the list if the task is complete.
            if (($null -ne $vmDiskConsolidation) -and ($null -ne $vmDiskConsolidation.Task) -and ($null -ne $vmDiskConsolidation.Task.FinishTime))
            {
                [void] $vmDCs.Remove($vmDiskConsolidation)
                $vmDiskConsolidation = $null
            } `
            else
            {
                # Nothing, the task is not complete
            }

            if($null -ne $vmDiskConsolidation)
            {
                $a++
            } `
            else
            {
                # Nothing -- only increment $a if we did not just remove $vmDiskConsolidation from $vmDiskConsolidations
            }
        }
    } `
    else # NOT ($vmDiskConsolidationTasks.Length -gt 0)
    {
        # Nothing.
    }

    return $vmDiskConsolidationTasks.Length
}

function StartDiskConsolidationsTask
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCtr,

        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]] $vmDCs
    )

    # if there are more VMs needing to have their disks consolidated...
    if (($vmDCs.Count -gt 0)) # -and (@($vmDCs | Where-Object { $null -eq $_.Task }).Length -gt 0))
    {
        # If there are $maxConsolidations or more consolidations already running...
        if ((UpdateDiskConsolidationTasks -vCtr $vCtr -vmDCs $vmDCs) -ge $maxConsolidations)
        {
            # Pause until a slot is available..
            Write-Host -NoNewline -ForegroundColor Yellow "Pausing to allow time for current consolidation tasks to run."
            while ((UpdateDiskConsolidationTasks -vCtr $vCtr -vmDCs $vmDCs) -ge $maxConsolidations)
            {
                Write-Host -NoNewline -ForegroundColor Yellow "."
                Start-Sleep -Seconds 10
            }
            Write-Host
        } `
        else # NOT ($vmDiskConsolidationTasks.Length -ge $maxConsolidations)
        {
            # Nothing.
        }

        $nextConsolidation = $vmDCs | Where-Object { ($null -eq $_.Task) } | Select-Object -First 1

        if ($null -ne $nextConsolidation)
        {
            try
            {
                Write-Host -ForegroundColor Green ("Starting disk consolidation on {0}." -f @($nextConsolidation.VM.Name))
                $nextConsolidation.VM.ExtensionData.ConsolidateVMDisks_Task() | Out-Null
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Exception thrown trying to initiate disk consolidation for {0}." -f @($nextConsolidation.VM.Name))
            }
        } `
        else # NOT ($null -ne $nextConsolidation)
        {
            # Nothing.
        }
    } `
    else # NOT (($vmDCs.Count -gt 0))
    {
        # Nothing.
    }
}

$vmDiskConsolidations = GetVMsNeedingConsolidation -vCtr $vCenter
$totalConsolidationsNeeded = $vmDiskConsolidations.Length
$MonitorUntilComplete = $true

while ($vmDiskConsolidations.Count -gt 0)
{
    $percentComplete = (($totalConsolidationsNeeded - $vmDiskConsolidations.Length) / $totalConsolidationsNeeded) * 100
    Write-Progress -Id 1 -Activity "Consolidating VM Disks" -Status ("{0:N2}% complete" -f @($percentComplete)) -PercentComplete $percentComplete
    StartDiskConsolidationsTask -vCtr $vCenter -vmDCs $vmDiskConsolidations

    # If there are no more disk consolidations to start, and we are not monitoring until everything is complete, then...
    if (-not $MonitorUntilComplete -and @($vmDiskConsolidations | Where-Object { $null -eq $_.Task }).Length -eq 0)
    {
        # Clear the $vmDiskConsolidations so the while loop will terminate...
        $vmDiskConsolidations.Clear()
    } `
    else # NOT (-not $MonitorUntilComplete -and @($vmDiskConsolidations | Where-Object { $null -eq $_.Task }).Length -eq 0)
    {
        # Nothing.
    }
}
