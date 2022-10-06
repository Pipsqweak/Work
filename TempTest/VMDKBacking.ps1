$vms = Get-VM -Server $vCenter

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
                $d = "" | Select-Object VMName, DiskLabel, BackingFile
                $d.VMName = $vm.Name
                $d.DiskLabel = $diskDevices[$b].DeviceInfo.Label
                $d.BackingFile = $backing.FileName

                $diskBackingData += $d
                Write-Host ("`t{0}: {1}" -f @($d.DiskLabel, $d.BackingFile))
            }
            $backing = $backing.Parent
        } while ($null -ne $backing)

        $b++
    }

  #  Write-Host
    $a++
}
