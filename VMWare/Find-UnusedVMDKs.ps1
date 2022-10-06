$vms = $null
$vms = Get-VM -Server $vCenter | Sort-Object Name

$diskBackingData = @()
$a = 0
while (($a -lt $vms.Length) -and ($a -gt -10))
{
    $vm = $vms[$a]
    $diskDevices = @($vm.ExtensionData.Config.Hardware.Device | Where-Object { $_.Backing -is [VMware.Vim.VirtualDeviceFileBackingInfo] })
    Write-Host ("`r`nVM: {0}, Drives: {1}" -f @($vm.Name, $diskDevices.Length))
    $b = 0
    while($b -lt $diskDevices.Length)
    {
        $backing = $diskDevices[$b].Backing
        do {
            if($null -ne $backing)
            {
                $d = "" | Select-Object VMName, DiskLabel, BackingFile, VMHostName
                $d.VMName = $vm.Name
                $d.DiskLabel = $diskDevices[$b].DeviceInfo.Label
                $d.BackingFile = $backing.FileName
                $d.VMHostName = $vm.VMHost.Name

                $diskBackingData += $d
                Write-Host ("`t{0}: {1}" -f @($d.DiskLabel, $d.BackingFile))

                if ($vm.ExtensionData.Config.ChangeTrackingEnabled)
                {
                    $d = "" | Select-Object VMName, DiskLabel, BackingFile, VMHostName
                    $d.VMName = $vm.Name
                    $d.DiskLabel = $diskDevices[$b].DeviceInfo.Label
                    $d.BackingFile = $backing.FileName.Replace(".vmdk","-ctk.vmdk")
                    $d.VMHostName = $vm.VMHost.Name
                    $diskBackingData += $d

                    Write-Host ("`t{0}: {1}" -f @($d.DiskLabel, $d.BackingFile))
                } `
                else # NOT ($vm.ExtensionData.Config.ChangeTrackingEnabled)
                {
                    # Nothing.
                }
            }
            $backing = $backing.Parent
        } while ($null -ne $backing)

        $b++
    }

    $a++
}

$datastores = @(Get-Datastore -Server $vCenter | Sort-Object Type, Name)
$uniqueDatastores = @()
$a = 0
while($a -lt $datastores.Length)
{
    if($datastores[$a].Type -eq "VMFS")
    {
        $uniqueDatastores += $datastores[$a]
    }
    else
    {
        # If the datastore is NFS, check for duplication via RemoveHost and RemotePath.
        if(@($uniqueDatastores | Where-Object { ($_.RemoteHost -eq $datastores[$a].RemoteHost) -and ($_.RemotePath -eq $datastores[$a].RemotePath)}).Length -eq 0)
        {
            $uniqueDatastores += $datastores[$a]
        }
    }
    $a++
}

$fileQueryFlags = [VMware.Vim.FileQueryFlags]::new()
$fileQueryFlags.FileSize = $true
$fileQueryFlags.FileType = $true
$fileQueryFlags.Modification = $true

$searchSpec = [VMware.Vim.HostDatastoreBrowserSearchSpec]::new()
$searchSpec.details = $fileQueryFlags
$searchSpec.sortFoldersFirst = $true
$searchSpec.MatchPattern = "*.vmdk"

$vmdkFiles = @()
$unusedVMDKs = @()

$a = 0
while($a -lt $uniqueDatastores.Length)
{
    $dsView = $uniqueDatastores[$a] | Get-View
    $dsBrowser = Get-View -Server $vCenter $dsView.browser

    $rootPath = "[{0}]" -f @($dsView.summary.Name)

    Write-Host ("Searching {0}..." -f @($rootPath))

    # Used to filter out folders/files that start with a '.'
    #   like:
    #       .snapshot
    #       .dvsData
    #       .vSphere-HA
    $folderExcludeStr = "\[{0}\] \." -f @($dsView.summary.Name)

    $searchResult = $dsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)
    $noSnaps = $searchResult | Where-Object { $_.FolderPath -notmatch $folderExcludeStr }

    foreach ($folder in $noSnaps)
    {
        foreach ($fileResult in $folder.File)
        {
            $file = "" | Select-Object Datastore, Name, Size, Modified, FullPath, Used
            $file.Datastore = $dsView.summary.Name
            $file.Name = $fileResult.Path
            $file.Size = $fileResult.Filesize
            $file.Modified = $fileResult.Modification
            $file.FullPath = $folder.FolderPath + $file.Name
            $file.Used = $true

            $used = " "
            $usedVMDKs = @($diskBackingData | Where-Object { $_.BackingFile -eq $file.FullPath })
            if($usedVMDKs.Length -eq 0)
            {
                $file.Used = $false
                $unusedVMDKs += $file
                $used = "*"
            }
            Write-Host ("{0}{1}`t{2}`t{3}`t{4}`t{5}" -f @($used,$file.Datastore,$file.Name, $file.Size, $file.Modified, $file.FullPath))
            $vmdkFiles += $file
        }
    }

    $a++
}


# $groups = @($vmdkFiles | Where-Object { -not $_.Used }) | Group-Object -Property Datastore
$groups = $unusedVMDKs | Group-Object -Property Datastore

$a = 0
while($a -lt $groups.Count)
{
    $grpSum = ($groups[$a].Group | Measure-Object -Property Size -Sum).Sum
    Write-Host ("{0}: {1:N2}GB" -f @($groups[$a].Name, ($grpSum / 1gb)))
    $a++
}

$unusedVMDKs | Out-GridView
$diskBackingData | Out-GridView

$sb = [System.Text.StringBuilder]::new()

$a = 0
while($a -lt $vms.Length)
{
    $hasSnapshots = " "
    if($null -ne $vms[$a].ExtensionData.Snapshot)
    {
        $hasSnapshots = "*"
    }
    $vmVMDKs = @($diskBackingData | Where-Object { $_.VMName -eq $vms[$a].Name })
    $uniqueDiskLabels = @($vmVMDKs | Select-Object -Unique -ExpandProperty DiskLabel | Sort-Object)

    $b = 0
    while($b -lt $uniqueDiskLabels.Length)
    {
        $diskVMDKs = @($vmVMDKs | Where-Object { $_.DiskLabel -eq $uniqueDiskLabels[$b]})

        if ($diskVMDKs.Length -gt 1)
        {
            [void] $sb.AppendLine("{0}{1}: {2}" -f @($hasSnapshots, $vms[$a].Name, $uniqueDiskLabels[$b]))
            $c = 0
            while($c -lt $diskVMDKs.Length)
            {
                [void] $sb.AppendLine("`t{0}" -f @($diskVMDKs[$c].BackingFile))
                $c++
            }
        } `
        else # NOT ($diskVMDKs.Length -gt 1)
        {
            # Nothing.
        }
        $b++
    }
    $a++
}

$vmToConsolidate = @(
    "DDC-SYR-W10-04", "DDC-SYR-W10-03", "DDC-SYR-W10-05", "DDC-VDI-SAS-02", "DDC-VDI-SAS-03",
    "DDC-VDI-SAS-06", "DDC-VDI-SAS-07", "DDC-VDI-SAS-08", "DDC-W10-CAPE-03", "DDC-W10-CAPE-06",
    "DDC-W10-CAPE-08", "DDC-W10-CAPE-09", "DDC-W10-CAPE-10", "DDC-W10-STD-003", "DDC-W10-STD-004",
    "DDC-W10-STD-005", "DDC-W10-STD-006", "DDC-W10-STD-008", "DDC-W10-STD-011", "DDC-W10-STD-012",
    "DDC-W10-STD-013", "DDC-W10-STD-014", "DDC-W10-STD-015", "DDC-W10-STD-016", "DDC-W10-STD-017",
    "DDC-W10-STD-018", "DDC-W10-STD-021", "DDC-W10-STD-023", "DDC-W10-STD-025", "DDC-W10-STD-026",
    "DDC-W10-STD-028", "DDC-W10-STD-029", "DDC-W10-STD-030", "DDC-W10-STD-031", "DDC-W10-STD-037",
    "DDC-W10-STD-038", "DDC-W10-STD-039", "DDC-W10-STD-041", "DDC-W10-STD-043", "DDC-W10-STD-044",
    "DDC-W10-STD-045", "DDC-W10-STD-047", "DDC-W10-STD-050", "DDC-W10-STD-053", "DDC-W10-STD-054",
    "DDC-W10-STD-055", "DDC-W10-STD-057", "DDC-W10-STD-059", "DDC-W10-STD-060", "DDC-W10-STD-061",
    "DDC-W10-STD-065", "DDC-W10-STD-067", "DDC-W10-STD-068", "DDC-W10-STD-069", "DDC-W10-STD-070",
    "DDC-W10-STD-072", "DDC-W10-STD-074", "DDC-W10-STD-075", "DDC-W10-STD-077", "DDC-W10-STD-078",
    "DDC-W10-STD-080", "DDC-W10-STD-081", "DDC-W10-STD-082", "DDC-W10-STD-084", "DDC-W10-STD-085",
    "DDC-W10-STD-086", "DDC-W10-STD-087", "DDC-W10-STD-091", "DDC-W10-STD-092", "DDC-W10-STD-095",
    "DDC-W10-STD-096", "DDC-W10-STD-097", "DDC-W10-STD-098", "DDC-W10-STD-101", "DDC-W10-STD-102",
    "DDC-W10-STD-104", "DDC-W10-STD-105", "DDC-W10-STD-107", "DDC-W10-STD-110", "DDC-W10-STD-111",
    "DDC-W10-STD-112", "DDC-W10-STD-113", "DDC-W10-STD-115", "DDC-W10-STD-116", "DDC-W10-STD-118",
    "DDC-W10-STD-119", "DDC-W10-STD-120", "DDC-W10-STD-122", "DDC-W10-STD-124", "DDC-W10-STD-125",
    "DDC-W10-STD-126", "DDC-W10-STD-127", "DDC-W10-STD-129", "DDC-W10-STD-131", "DDC-W10-STD-132",
    "DDC-W10-STD-133", "DDC-W10-STD-134", "DDC-W10-STD-137", "DDC-W10-STD-138", "DDC-W10-STD-141",
    "DDC-W10-STD-142", "DDC-W10-STD-143", "DDC-W10-STD-144", "DDC-W10-STD-145", "DDC-W10-STD-146"
)


$a = 0

while($a -lt $vmToConsolidate.Length)
{
    # If we are tracking a task, refresh it...
    if($null -ne $consolidateTask)
    {
        try
        {
            $consolidateTask = Get-Task -Id $consolidateTask.Id -ErrorAction Stop
        }
        catch
        {
            $consolidateTask = $null
        }
    }

    # If we have no task, or the task is not "Running", launch a new task...

    if((($null -eq $consolidateTask) -or ($consolidateTask.State -ne [VMware.VimAutomation.Sdk.Types.V1.TaskState]::Running)) -and ($a -lt $vmToConsolidate.Length))
    {
        if(($null -ne $vm) -and ($null -ne $consolidateTask))
        {
            $elapsed = [DateTime]::Now - $consolidateTask.StartTime
            Write-Host ("Time to consolidate: {0} = {1}" -f @($vm.Name, $elapsed.ToString()))
        }
        # Grab the next VM to consolidate...
        $vm = Get-VM -Server $vCenter -Name $vmToConsolidate[$a]

        # No matter what, advance the vm counter...
        $a++

        # If we have a VM to consolidate, then do it...
        if($null -ne $vm)
        {
            Write-Host ("Consolidating {0}" -f @($vm.Name))
            $consolidateTask = $vm.ExtensionData.ConsolidateVMDisks_Task()
            Start-Sleep -Seconds 5
            $consolidateTask = Get-Task -Id ("Task-{0}" -f @($consolidateTask.Value))
        }
    } `
    else
    {
        if($a -lt $vmToConsolidate.Length)
        {
            # Need to give the task more time to complete...
            if($consolidateTask.PercentComplete -lt 1)
            {
                $msToWait = 30000
            } `
            else
            {
                $elapsed = [DateTime]::Now - $consolidateTask.StartTime
                $msPerPercent = $elapsed.TotalMilliseconds / $consolidateTask.PercentComplete
                $msToWait = (100 - $consolidateTask.PercentComplete) * $msPerPercent
            }
            if($msToWait -lt 1000)
            {
                $msToWait = 1000
            }

            $msToWait = $msToWait % 600000
            $ts = [Timespan]::new(0,0,($msToWait / 1000))
            Write-Host ("Waiting {0} (Till {1})..." -f @($ts.ToString(), ([DateTime]::Now + $ts).ToString("hh:mm:ss")))
            Start-Sleep -Milliseconds $msToWait
        }
    }
}




$vm = Get-VM -Server $vCenter -Name "DDC-SYR-W10-02"
if($null -ne $vm)
{
    if($null -eq $vm.ExtensionData.Snapshot)
    {
        $consolidateTask = $vm.ExtensionData.ConsolidateVMDisks_Task()
    }
}
