$rpSAS = Get-ResourcePool -Server $vCenter -Name "DDC - SAS"
$rpVDI = Get-ResourcePool -Server $vCenter -Name "CDC - VDI"
$vdiVMs = @(Get-VM -Server $vCenter -Location $rpVDI | Where-Object { $_.Name -notmatch "^vCLS" })

$vdiVMs = Get-VM -Server $vCenter | Where-Object { $_.Name -notmatch "^vCLS" }
$datastores = @(Get-Datastore -Server $vCenter)
($datastores | Select-Object Name,@{N='Capacity';E={$_.ExtensionData.Summary.Capacity}},@{N='Available';E={$_.ExtensionData.Summary.Freespace}},@{N='Used';E={$_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.Freespace}},@{N='Provisioned';E={($_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.Freespace) + $_.ExtensionData.Summary.Uncommitted}},@{N='OverProvisioned';E={[Math]::Max([int64]0,($_.ExtensionData.Summary.Uncommitted - $_.ExtensionData.Summary.Freespace))}} | Measure-Object -Sum -Property OverProvisioned).Sum




$report = @()
$a = 0
while($a -lt $vdiVMs.Length)
{
    $vm = $vdiVMs[$a]
    # $vmHDs = @(Get-HardDisk -Server $vCenter -VM $vm)
    # $vmVw = $vm | Get-View

    # Extract the unique datastore names from the list of files for the VM
    # $uniqueDatastoreNames = @($vmVw.LayoutEx.File | Select-Object -ExpandProperty Name | Where-Object { $_  -match "\[(.*?)\]" } | Foreach-Object { $Matches[1] } | Select-Object -Unique)

    $b = 0
    while($b -lt $vm.ExtensionData.Storage.PerDatastoreUsage.Length)
    {
        $datastore = $datastores | Where-Object { $_.Id -eq $vm.ExtensionData.Storage.PerDatastoreUsage[$b].Datastore }
        if($null -ne $datastore)
        {
            $d = "" | Select-Object VM, Datastore, Used, Available
            $d.VM = $vm.Name
            $d.Datastore = $datastore.Name
            $d.Used = ($vm.ExtensionData.Storage.PerDatastoreUsage | Where-Object { $_.Datastore -eq $datastore.Id } | Measure-Object -Property Committed -Sum).Sum
            $d.Available = ($vm.ExtensionData.Storage.PerDatastoreUsage | Where-Object { $_.Datastore -eq $datastore.Id } | Measure-Object -Property Uncommitted -Sum).Sum
        }
        $datastoreFiles = @($vmVw.LayoutEx.File | Where-Object { $_.Name -match ("[{0}]" -f @($uniqueDatastoreNames[$b])) })

        $d = "" | Select-Object VM,SSDUsed,NonSSDUsed,TotalUsed, StorageCapacity, StorageUsed, StorageUnused, Datastore
        $d.VM = $vm.Name
        $d.SSDUsed = ($datastoreFiles | Where-Object { $_.Name -match "SSD" } | Measure-Object -Property Size -Sum).Sum
        $d.NonSSDUsed = ($datastoreFiles | Where-Object { $_.Name -notmatch "SSD" } | Measure-Object -Property Size -Sum).Sum
        $d.TotalUsed = ($datastoreFiles | Measure-Object -Property Size -Sum).Sum

        #$d.StorageUsed = ($vm.ExtensionData.Storage.PerDatastoreUsage | Measure-Object -Property Committed -Sum).Sum
        #$d.StorageCapacity = $d.StorageUsed + ($vm.ExtensionData.Storage.PerDatastoreUsage | Measure-Object -Property Uncommitted -Sum).Sum
        #$d.StorageUnused = $d.StorageCapacity - $d.StorageUsed

        $report += $d

        $b++
    }

    $d
<#
    $b = 0
    while($b -lt $vmHDs.Length)
    {
        $hd = $vmHDs[$b]

        if($hd.FileName -notmatch "^[DDC_VM_SSD_01]")
        {
            $row = "" | Select-Object VMName, Cluster, VM, GuestName, Datastore, VMDKpath, HardDisk, DiskType, CapacityKB, DiskFreespace, TotalStorageConsumed, ProvisionType
            $row.Hostname = $vm.VMHost.Name
            $row.Cluster = (Get-Cluster -VM $vm ).Name
            $row.VM = $VM.Name
            $row.GuestName = $vm.Guest.HostName
            $row.Datastore = $hd.Filename.Split("]")[0].TrimStart("[")
            $row.VMDKpath = $hd.FileName
            $row.HardDisk = $hd.Name
            $row.CapacityKB = $hd.CapacityKB
            $row.DiskFreespace = $vm.Guest.Disks | Measure-Object FreeSpaceGB -Sum | Select-Object -ExpandProperty Sum
            $row.DiskType = $hd.get_DiskType()
            $row.TotalStorageConsumedKB = $vm.get_UsedSpaceGB() * 1MB
            $row.ProvisionType = $hd.StorageFormat
            $report += $row

            $row
        }
        $b++
    }
#>
    $a++

}

$hdDevices = $vm.ExtensionData.Config.Hardware.Device | Where-Object { $_.DeviceInfo.Label -match "Hard disk" }


$vm = Get-VM -Server $vCenter -Name "CDC-NTAPMGMT01"
$v = $vm | Get-View
($v.LayoutEx.File | Where-Object { $_.Name -match "SSD" } | Measure-Object -Property Size -Sum).Sum

$v.LayoutEx.File | Out-GridView
