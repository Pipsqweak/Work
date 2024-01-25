$profileMatrix = @()
$d = "" | Select-Object ProfileName, MemoryMB
$d.ProfileName = "grid_p40-2q"
$d.MemoryMB = 2048
$profileMatrix += $d

$d = "" | Select-Object ProfileName, MemoryMB
$d.ProfileName = "grid_p6-2q"
$d.MemoryMB = 2048
$profileMatrix += $d

$d = "" | Select-Object ProfileName, MemoryMB
$d.ProfileName = "grid_t4-2q"
$d.MemoryMB = 2048
$profileMatrix += $d

$d = "" | Select-Object ProfileName, MemoryMB
$d.ProfileName = "nvidia_a16-4q"
$d.MemoryMB = 4096
$profileMatrix += $d

$d = "" | Select-Object ProfileName, MemoryMB
$d.ProfileName = "nvidia_a16-2q"
$d.MemoryMB = 2048
$profileMatrix += $d


$vmHosts = Get-VMHost -Server $vcenter
$vcadHosts = @($vmHosts | Where-Object { $_.ExtensionData.Hardware.PciDevice | Where-Object { ($_.VendorName -match "Nvidia") -and (($_.DeviceName -match "Tesla") -or ($_.DeviceName -match "nVidia")) } } | Sort-Object Name)
$vCADData = @()
$sb = [System.Text.StringBuilder]::new()
[int] $a = 0
while($a -lt $vcadHosts.Length)
{
    $j = "" | Select-Object Host, MemoryTotal, MemoryUsed, GPUs, VMs, TotalGPUMemoryGB, GPUMemoryAvailableGB
    $j.Host = $vcadHosts[$a].Name
    $j.MemoryTotal = $vcadHosts[$a].MemoryTotalMB
    $j.MemoryUsed = $vcadHosts[$a].MemoryUsageMB
    $j.TotalGPUMemoryGB = 0
    $j.GPUMemoryAvailableGB = 0
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

                $j.TotalGPUMemoryGB += $k.Memory
                $j.GPUMemoryAvailableGB += $k.Memory
                $j.GPUs += $k
                $b++
            }
            [void] $sb.AppendLine("`tTotal GPU Memory: {0:N2}GB" -f @($j.TotalGPUMemoryGB))
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
#                if($hostVMs[$b].PowerState -eq "PoweredOn")
#                {
                    $vgpuInfo = $hostVMS[$b].ExtensionData.Config.Hardware.Device |  Where-Object { $_.Backing.vgpu } | Select-Object -ExpandProperty DeviceInfo
                    if($null -ne $vgpuInfo)
                    {
                        [void] $sb.Append(("  {0}" -f @($vgpuInfo.Summary.Replace("NVIDIA GRID vGPU ", ""))))
                        $d.vGPUProfile = $vgpuInfo.Summary.Replace("NVIDIA GRID vGPU ", "")

                        $gridProfile = $profileMatrix | Where-Object { $_.ProfileName -eq $d.vGPUProfile }
                        if ($null -ne $gridProFile)
                        {
                            $j.GPUMemoryAvailableGB -= ($gridProfile.MemoryMB / 1kb)
                        } `
                        else # NOT ($null -ne $gridProfile)
                        {
                            Write-Host ("Unknown profile: {0}:{1}" -f @($d.VM, $d.vGPUProfile))
                        }
                    }
#                }
                [void] $sb.AppendLine("")

                $j.VMs += $d
            }

            $b++
        }
        $availableHostMemoryMB = $vcadHosts[$a].MemoryTotalMB - $vcadHosts[$a].MemoryUsageMB
        $availableGPUMemoryMB = $j.GPUMemoryAvailableGB * 1KB
        [void] $sb.AppendLine("`tResources Available: Host Memory: {0:N2}GB, GPU Memory: {1:N2}GB" -f @(($availableHostMemoryMB / 1KB), $j.GPUMemoryAvailableGB))

        $o = 16384
        while($o -le 32768)
        {
            $p = 2048
            while($p -le 4096)
            {
                $vmsBasedOnHostMemory = [int]([Math]::Floor($availableHostMemoryMB  / $o))
                $vmsBasedOnGPUMemory = [int]([Math]::Floor($availableGPUMemoryMB / $p))

                $maxVMs = [Math]::Min($vmsBasedOnHostMemory, $vmsBasedOnGPUMemory)

                if($maxVMs -gt 0)
                {
                    [void] $sb.AppendLine("`t`tVMs with {0}GB RAM, {1}GB GPU Memory: {2}" -f @(($o / 1KB), ($p / 1KB),  $maxVMs))
                }

                $p += 2048
            }
            $o += 8192
        }
    }

    $vCADData += $j
    $a++
}

$sb.ToString() | Set-Clipboard
