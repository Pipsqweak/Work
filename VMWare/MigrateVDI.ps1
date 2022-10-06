$vdiCluster = Get-Cluster -Name "DDC-VDI-CLUSTER01" -Server $vCenter
$destinationDSwitch = Get-VDSwitch -Server $vCenter -Name "DDC Internal vDS 01"
$destinationPG = Get-VDPortgroup -Server $vCenter -VDSwitch $destinationDSwitch -Name "VL40-CLIENTLAN"
$destinationDS = Get-Datastore -Server $vCenter -Name "DDC_VM_SATA_02"
$destinationCluster = Get-Cluster -Server $vCenter -Name "DDC-INT-CLUSTER-01"
$vdiResourcePool = Get-ResourcePool -Server $vCenter -Name "VDI" -Location $destinationCluster
$vmNamesExcluded = @("DDC-P6-CTX-01","DDC-P6-CTX-MI")

# Limit the number of running tasks by category
$maximumComputeRelocation_Tasks = 5
$maximumStorageRelocation_Tasks = 3
$maximumConsolidation_Tasks = 3
$maximumResourcePoolRelocation_Tasks = 5

# Get a list of hosts in the destination cluster
$internalClusterHosts = @(Get-VMHost -Server $vCenter -Location $destinationCluster -State Connected)

$internalDS = Get-Datastore -Server $vCenter -Name "DDC_VM_SATA_02" -RelatedObject $internalClusterHosts[0]
# Which host is the next to receive a VM...
$nextDestinationHost = 0

# Get an array of the VDI VMs
$vdiVMs = Get-VM -Server $vCenter -Location $vdiCluster | Where-Object { ($vmNamesExcluded -notcontains $_.Name) -and ($_.Name -notmatch "^vCLS") }

$vdiResourcePoolVMs = @(Get-VM -Server $vCenter -Location $vdiResourcePool)

# VMS that haven't been migrated to the VDI Resource Pool
$clusterRPVMs = Get-VM -Server $vCenter -Location $clusterRP | Where-Object { ($_.ResourcePoolId -eq "ResourcePool-resgroup-25094") -and ($_.Name -notmatch "^vCLS") }
$vdiVMs = $clusterRPVMs

# Build an array of all VM migration/consolidation data
$vmMigrationData = @()

# Populate the migration data...
$a = 0
while ($a -lt $vdiVMs.Length)
{
    $d = "" | Select-Object VM, MigratedToInternalCompute, MigratedToInternalStorage, Consolidated, MigratedToResourcePool, MigrateToInternalCompute_Task, MigrateToInternalStorage_Task, Consolidation_Task, MigrateToResourcePool_Task, IsInError
    $d.VM = $vdiVMs[$a]
    $d.MigratedToInternalCompute = $internalClusterHosts -contains $d.VM.VMHost
    $d.MigratedToInternalStorage = $d.VM.DatastoreIdList -contains $internalDS.Id
    $d.MigratedToResourcePool = $false
    $d.Consolidated = $false
    $d.MigrateToInternalCompute_Task = $null
    $d.MigrateToInternalStorage_Task = $null
    $d.MigrateToResourcePool_Task = $null
    $d.Consolidation_Task = $null
    $d.IsInError = $false

    $vmMigrationData += $d
    $a++
}

# Do the work...
do {

    # First update all _Tasks...
    $vmTasks = @(Get-Task -Server $vCenter)

    # Track the running task numbers
    $runningMigratingToInternalCompute_Tasks = 0
    $runningMigratingToInternalStorage_Tasks = 0
    $runningConsolidation_Tasks = 0
    $runningMigratingToResourcePool_Tasks = 0

    $a = 0
    while($a -lt $vmTasks.Length)
    {
        $b = 0
        while($b -lt $vmMigrationData.Length)
        {
            # Does this task belong to the VM tracked in this element?
            if($vmTasks[$a].ObjectId -eq $vmMigrationData[$b].VM.Id)
            {
                # Unless we decide otherwise, do not re-acquire the VM object
                $reaquireVMObject = $false

                # Is the task the migrate to internal compute task?
                if(($null -ne $vmMigrationData[$b].MigrateToInternalCompute_Task) -and ($vmMigrationData[$b].MigrateToInternalCompute_Task.Id -eq $vmTasks[$a].Id))
                {
                    $vmMigrationData[$b].MigrateToInternalCompute_Task = $vmTasks[$a]
                    if($vmMigrationData[$b].MigrateToInternalCompute_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $vmMigrationData[$b].IsInError = $vmMigrationData[$b].MigrateToInternalCompute_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success
                        if(($vmMigrationData[$b].MigrateToInternalCompute_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success) -and (-not $vmMigrationData[$b].MigratedToInternalCompute))
                        {
                            Write-Host ("{0} has been migrated to the internal cluster." -f @($vmMigrationData[$b].VM.Name))
                            $vmMigrationData[$b].MigratedToInternalCompute = $true
                        }
                        $reaquireVMObject = (-not $vmMigrationData[$b].IsInError) -and ($vmMigrationData[$b].MigratedToInternalCompute)
                    }
                    elseif($vmMigrationData[$b].MigrateToInternalCompute_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $runningMigratingToInternalCompute_Tasks++
                    }
                }
                # ...perhaps it's the migrate to internal storage task...
                elseif(($null -ne $vmMigrationData[$b].MigrateToInternalStorage_Task) -and ($vmMigrationData[$b].MigrateToInternalStorage_Task.Id -eq $vmTasks[$a].Id))
                {
                    $vmMigrationData[$b].MigrateToInternalStorage_Task = $vmTasks[$a]
                    if($vmMigrationData[$b].MigrateToInternalStorage_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $vmMigrationData[$b].IsInError = $vmMigrationData[$b].MigrateToInternalStorage_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success
                        if((-not $vmMigrationData[$b].MigratedToInternalStorage) -and ($vmMigrationData[$b].MigrateToInternalStorage_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success))
                        {
                            Write-Host ("{0} has been migrated to the internal storage." -f @($vmMigrationData[$b].VM.Name))
                            $vmMigrationData[$b].MigratedToInternalStorage = $true
                        }
                        $reaquireVMObject = (-not $vmMigrationData[$b].IsInError) -and ($vmMigrationData[$b].MigratedToInternalStorage)
                    }
                    elseif($vmMigrationData[$b].MigrateToInternalStorage_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $runningMigratingToInternalStorage_Tasks++
                    }
                }
                # ...perhaps it's the disk consolidation task...
                elseif(($null -ne $vmMigrationData[$b].Consolidate_Task) -and ($vmMigrationData[$b].Consolidate_Task.Id -eq $vmTasks[$a].Id))
                {
                    $vmMigrationData[$b].Consolidate_Task = $vmTasks[$a]
                    if($vmMigrationData[$b].Consolidate_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $vmMigrationData[$b].IsInError = $vmMigrationData[$b].Consolidate_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success
                        if((-not $vmMigrationData[$b].Consolidated) -and ($vmMigrationData[$b].Consolidate_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success))
                        {
                            Write-Host ("{0}'s disks have been consolidated." -f @($vmMigrationData[$b].VM.Name))
                            $vmMigrationData[$b].Consolidated = $true
                        }
                    }
                    elseif($vmMigrationData[$b].Consolidate_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $runningConsolidation_Tasks++
                    }
                }
                # ...ok, how about the migrate to resource pool task?
                elseif(($null -ne $vmMigrationData[$b].MigrateToResourcePool_Task) -and ($vmMigrationData[$b].MigrateToResourcePool_Task.Id -eq $vmTasks[$a].Id))
                {
                    $vmMigrationData[$b].MigrateToResourcePool_Task = $vmTasks[$a]
                    if($vmMigrationData[$b].MigrateToResourcePool_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $vmMigrationData[$b].IsInError = $vmMigrationData[$b].MigrateToResourcePool_Task.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success
                        if((-not $vmMigrationData[$b].MigratedToResourcePool) -and ($vmMigrationData[$b].MigrateToResourcePool_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Success))
                        {
                            Write-Host ("{0} has been migrated to the VDI resource pool." -f @($vmMigrationData[$b].VM.Name))
                            $vmMigrationData[$b].MigratedToResourcePool = $true
                        }
                        $reaquireVMObject = (-not $vmMigrationData[$b].IsInError) -and ($vmMigrationData[$b].MigratedToResourcePool)
                    }
                    elseif($vmMigrationData[$b].MigrateToResourcePool_Task.State -eq [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)
                    {
                        $runningMigratingToResourcePool_Tasks++
                    }
                }
                else
                {
                    # Nothing, not a task I'm concerned with... perhaps an internal vCenter task.
                }

                # If we need to re-acquire the VM object for this element, then do so.
                if($reaquireVMObject)
                {
                    try
                    {
                        # Get a new VM object after it has been migrated.
                        $vmMigrationData[$b].VM = Get-VM -Server $vCenter -Id $vmMigrationData[$b].VM.Id -ErrorAction Stop
                    }
                    catch
                    {
                        $vmMigrationData[$b].IsInError = $true
                    }
                }
            }

            $b++
        }
        $a++
    }

    $needsMigratedToInternalCompute = @($vmMigrationData | Where-Object { (-not $_.IsInError) -and (-not $_.MigratedToInternalCompute) -and ($null -eq $_.MigrateToInternalCompute_Task) })
    $needsMigratedToInternalStorage = @($vmMigrationData | Where-Object { (-not $_.IsInError) -and ($_.MigratedToInternalCompute) -and (-not $_.MigratedToInternalStorage) -and ($null -eq $_.MigrateToInternalStorage_Task) })
    $needsConsolidation = @($vmMigrationData | Where-Object { (-not $_.IsInError) -and ($_.MigratedToInternalCompute) -and ($_.MigratedToInternalStorage) -and (-not $_.Consolidated) -and ($null -eq $_.Consolidation_Task) })
    $needsMigratedToResourcePool = @($vmMigrationData | Where-Object { (-not $_.IsInError) -and ($_.MigratedToInternalCompute) -and ($_.MigratedToInternalStorage) -and ($_.Consolidated) -and (-not $_.MigratedToResourcePool) -and ($null -eq $_.MigrateToResourcePool_Task) })

    # If there are no VMs to migrate to internal compute, or migrate to internal storage, or have its disks consolidated, or moved to the VDI resource pool, then we are done...
    $complete = ($needsMigratedToInternalCompute.Length + $needsMigratedToInternalStorage.Length + $needsConsolidation.Length + $needsMigratedToResourcePool.Length) -eq 0

    # Below here, we start, at most, 4 new tasks, 1 of each type, depending on what needs to be done...

    # If there is a VM needing to be migrated to internal compute...
    if($needsMigratedToInternalCompute.Length -gt 0)
    {
        # ...and there is an available task slot...
        if($runningMigratingToInternalCompute_Tasks -lt $maximumComputeRelocation_Tasks)
        {
            # Only migrate the VM if it has a single NIC...
            $vmNICs = @(Get-NetworkAdapter -Server $vCenter -VM $needsMigratedToInternalCompute[0].VM)
            if($vmNICs.Length -eq 1)
            {
                # ...and only if it is currently connected to "VMGuest-VLAN-40"
                if($vmNICs[0].NetworkName -eq "VMGuest-VLAN-40")
                {
                    $vmDatastores = @(Get-Datastore -Server $vCenter -RelatedObject $needsMigratedToInternalCompute[0].VM)
                    if($vmDatastores.Length -eq 1)
                    {
                        $destinationDatastore = Get-Datastore -Server $vCenter -RelatedObject $destinationHost -Name $vmDatastores[0].Name
                        $destinationHost = $internalClusterHosts[$nextDestinationHost]
                        $destinationDatastore = Get-Datastore -Server $vCenter -RelatedObject $destinationHost -Name $vmDatastores[0].Name
                        try
                        {
                            Write-Host ("Migrating {0} to the {1}." -f @($needsMigratedToInternalCompute[0].VM.Name, $destinationHost.Name))
                            $needsMigratedToInternalCompute[0].MigrateToInternalCompute_Task = Move-VM -Server $vCenter -VM $needsMigratedToInternalCompute[0].VM -NetworkAdapter $vmNICs[0] -PortGroup $destinationPG -Destination $destinationHost -Datastore $destinationDatastore -Confirm:$false -RunAsync -ErrorAction Stop
                            $nextDestinationHost = (($nextDestinationHost + 1) % $internalClusterHosts.Length)
                        }
                        catch
                        {
                            $needsMigratedToInternalCompute[0].IsInError = $true
                        }
                    }
                    else
                    {
                        $needsMigratedToInternalCompute[0].IsInError = $true
                    }
                }
                else
                {
                    $needsMigratedToInternalCompute[0].IsInError = $true
                }
            }
            else
            {
                $needsMigratedToInternalCompute[0].IsInError = $true
            }
        }
    }

    # If there is a VM needing to be migrated to internal storage...
    if($needsMigratedToInternalStorage.Length -gt 0)
    {
        # ...and there is an available task slot...
        if($runningMigratingToInternalStorage_Tasks -lt $maximumStorageRelocation_Tasks)
        {
            try
            {
                # Don't need to worry about NICs, since the VM has already been migrated to the internal cluster.
                $needsMigratedToInternalStorage[0].VM = Get-VM -Server $vCenter -Name $needsMigratedToInternalStorage[0].VM.Name -ErrorAction Stop
                Write-Host ("Migrating {0} to the internal storage." -f @($needsMigratedToInternalStorage[0].VM.Name))
                try
                {
                    $needsMigratedToInternalStorage[0].MigrateToInternalStorage_Task = Move-VM -VM $needsMigratedToInternalStorage[0].VM -Datastore $destinationDS -DiskStorageFormat Thin -Confirm:$false -RunAsync -ErrorAction Stop
                }
                catch
                {
                    $needsMigratedToInternalStorage[0].IsInError = $true
                }
            }
            catch
            {
                $needsMigratedToInternalStorage[0].IsInError = $true
            }
        }
    }

    # If there is a VM that needs its disks consolidated...
    if($needsConsolidation.Length -gt 0)
    {
        # ...and there is an available task slot...
        if($runningConsolidation_Tasks -lt $maximumConsolidation_Tasks)
        {
            # Only consolidate the VM's disks if it's needed.
            if($needsConsolidation[0].VM.ExtensionData.Runtime.ConsolidationNeeded)
            {
                try
                {
                    $needsConsolidation[0].VM = Get-VM -Server $vCenter -Name $needsConsolidation[0].VM.Name -ErrorAction Stop
                    Write-Host ("Consolidating {0}'s disks." -f @($needsConsolidation[0].VM.Name))
                    $needsConsolidation[0].Consolidation_Task = $needsConsolidation[0].VM.ExtensionData.ConsolidateVMDisks_Task()
                }
                catch
                {
                    $needsConsolidation[0].IsInError = $true
                }
            }
            else
            {
                # Doesn't need to consolidate, so flag it done.
                $needsConsolidation[0].Consolidated = $true
            }
        }
    }

    # If there is a VM that needs to be moved to the VDI resource pool...
    if($needsMigratedToResourcePool.Length -gt 0)
    {
        # ...and there is an available task slot...
        if($runningMigratingToResourcePool_Tasks -lt $maximumResourcePoolRelocation_Tasks)
        {
            try
            {
                # Don't need to worry about NICs, since the VM has already been migrated to the internal cluster and internal storage
                $needsMigratedToResourcePool[0].VM = Get-VM -Server $vCenter -Name $needsMigratedToResourcePool[0].VM.Name -ErrorAction Stop
                Write-Host ("Moving {0} to the VDI resource pool." -f @($needsMigratedToResourcePool[0].VM.Name))
                try
                {
                    $needsMigratedToResourcePool[0].MigrateToResourcePool_Task = Move-VM -VM $needsMigratedToResourcePool[0].VM -Destination $vdiResourcePool -Confirm:$false -RunAsync -ErrorAction Stop
                }
                catch
                {
                    $needsMigratedToResourcePool[0].IsInError = $true
                }
            }
            catch
            {
                $needsMigratedToResourcePool[0].IsInError = $true
            }
        }
    }

    # Wait a bit before starting at the top again...
    Start-Sleep -Seconds 5

} while(-not $complete)
