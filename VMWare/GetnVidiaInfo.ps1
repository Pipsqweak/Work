$vmHosts = Get-VMHost -Server $vcenter
$vcadHosts = @($vmHosts | Where-Object { $_.ExtensionData.Hardware.PciDevice | Where-Object { ($_.VendorName -match "Nvidia") -and ($_.DeviceName -match "Tesla") } } | Sort-Object Name)
$vCADData = @()
$sb = [System.Text.StringBuilder]::new()
$a = 0
while($a -lt $vcadHosts.Length)
{
    $j = "" | Select-Object Host, MemoryTotal, MemoryUsed, GPUs, VMs
    $j.Host = $vcadHosts[$a].Name
    $j.MemoryTotal = $vcadHosts[$a].MemoryTotalMB
    $j.MemoryUsed = $vcadHosts[$a].MemoryUsageMB
    $j.GPUs = @()
    $j.VMs = @()
    [void] $sb.AppendLine(("`r`n{0}, Memory (MB): Total: {1:N2} / Used {2:N2}" -f @($vcadHosts[$a].Name, $vcadHosts[$a].MemoryTotalMB, $vcadHosts[$a].MemoryUsageMB)))
    $hostVMS = @(Get-VM -Server $vcenter -Location $vcadHosts[$a])
    $esxcli = Get-EsxCli -VMHost $vcadHosts[$a] -V2
    if($null -ne $esxcli)
    {
        $gridCards = @($esxcli.graphics.device.list.Invoke())

        if($gridCards.Length -gt 0)
        {
            [void] $sb.AppendLine("`tGPUs:")
            $b = 0
            while($b -lt $gridCards.Length)
            {
                $k = "" | Select-Object Name, Memory
                [void] $sb.AppendLine(("`t`tName: {0}`tMemory: {1:N2}GB" -f @($gridCards[$b].DeviceName, ($gridCards[$b].MemorySizeinKB / 1MB))))
                $k.Name = $gridCards[$b].DeviceName
                $k.Memory = $gridCards[$b].MemorySizeinKB / 1MB
                $j.GPUs += $k
                $b++
            }
        }
    }

    if($hostVMS.Length -gt 0)
    {
        [void] $sb.AppendLine("`tHost VMs:")
        $b = 0
        while($b -lt $hostVMS.Length)
        {
            if($hostVMS[$b].Name -notmatch "vcls")
            {
                $d = ""  | Select-Object VM, PowerState, vGPUProfile, MemoryMB, MemoryReservedMB

                $d.VM = $hostVMs[$b].Name
                $d.PowerState = $hostVMs[$b].PowerState
                $d.MemoryMB = $hostVMs[$b].MemoryMB
                $d.MemoryReservedMB = $hostVMs[$b].ExtensionData.Config.MemoryAllocation.Reservation
                [void] $sb.Append(("`t`t{0,-17} {1,-11} Memory (MB):  Assigned: {2,6:N0} / Reserved: {3,6:N0} " -f @($hostVMS[$b].Name, $hostVMs[$b].PowerState, $hostVMs[$b].MemoryMB, $hostVMs[$b].ExtensionData.Config.MemoryAllocation.Reservation)))
                if($hostVMs[$b].PowerState -eq "PoweredOn")
                {
                    $vgpuInfo = $hostVMS[$b].ExtensionData.Config.Hardware.Device |  Where-Object { $_.Backing.vgpu } | Select-Object -ExpandProperty DeviceInfo
                    if($null -ne $vgpuInfo)
                    {
                        [void] $sb.Append(("  {0}" -f @($vgpuInfo.Summary.Replace("NVIDIA GRID vGPU ", ""))))
                        $d.vGPUProfile = $vgpuInfo.Summary.Replace("NVIDIA GRID vGPU ", "")
                    }
                }
                [void] $sb.AppendLine("")

                $j.VMs += $d
            }
            $b++
        }
    }

    $vCADData += $j
    $a++
}

$sb.ToString()
