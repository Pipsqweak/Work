$hyperVServers = @("BOSHPV01","DEN-HPV01","MIN-HPV01","ORL-HPV01","SAN-HPV01")



$windowsLicenseData = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $hyperVServers.Length)
{
    $clusterStats = "" | Select-Object ClusterName, PhysicalHosts, PhysicalCores, WindowsVMs, WindowsVMvCPUs
    $clusterStats.ClusterName = $hyperVServers[$a]
    $clusterStats.PhysicalHosts = 1
    $procData = Get-CimInstance -ComputerName $hyperVServers[$a] -ClassName Win32_Processor
    $clusterStats.PhysicalCores = ($procData | Measure-Object -Sum -Property NumberOfCores).Sum
    $hyperVVMs = @(Invoke-Command -ComputerName $hyperVServers[$a] -ScriptBlock { Get-VM  })
    $clusterStats.WindowsVMs = $hyperVVMs.Length
    $clusterStats.WindowsVMvCPUs = ($hyperVVMs | Measure-Object -Sum -Property ProcessorCount).Sum

    $windowsLicenseData.Add($clusterStats)
    $clusterStats
    $a++
}

$physicalServers = @(
    "ARBPRDPS2", "VANPRDPS2"
)
