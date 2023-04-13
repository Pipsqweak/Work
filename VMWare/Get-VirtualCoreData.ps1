$a = 0
while($a -lt $ddcIntWindowsVM.Length)
{
    $vmCores = ([int]($ddcIntWindowsVM[$a] / 8) + 1) *
    $a++
}


$windowsLicenseData = [System.Collections.Generic.List[System.Object]]::new()
$clusters = Get-Cluster -Server $vCtr
$a = 0
while($a -lt $clusters.Length)
{
    $clusterStats = "" | Select-Object ClusterName, PhysicalHosts, PhysicalCores, WindowsVMsPwrOn, WindowsVMvCPUsPwrOn, WindowsVMsPwrOff, WindowsVMvCPUsPwrOff
    $clusterWindowsVMs = @(Get-VM -Server $vCtr -Location $clusters[$a] | Where-Object { ($_.GuestId -match "windows") -and (($_.GuestId -match "srv") -or ($_.GuestId -match "server")) })
    $clusterWindowsVMsPwrOn = @($clusterWindowsVMs | Where-Object { $_.PowerState -eq "PoweredOn"} )
    $clusterVMHosts = @(Get-VMHost -Server $vCtr -Location $clusters[$a])
    $clusterStats.ClusterName = $clusters[$a].Name
    $clusterStats.PhysicalHosts = $clusterVMHosts.Length
    $clusterStats.PhysicalCores = [int] ($clusterVMHosts | Measure-Object -Sum -Property NumCpu).Sum
    $clusterStats.WindowsVMs = $clusterWindowsVMs.Length
    $clusterStats.WindowsVMvCPUs = [int]($clusterWindowsVMs | Measure-Object -Sum -Property NumCpu).Sum
    $windowsLicenseData.Add($clusterStats)
    $clusterStats

    $a++
}
