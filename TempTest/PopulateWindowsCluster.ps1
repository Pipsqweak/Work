$sourceClusterName = "DDC-INT-CLUSTER-01"
$destinationClusterName = "DDC-INT-CLUSTER-01"
$sourceCluster = Get-Cluster -Server $vCenter -Name $sourceClusterName
$destinationCluster = Get-Cluster -Server $vCenter -Name $destinationClusterName

$clusterWindowsVMs = @(Get-VM -Server $vCenter -Location $sourceCluster | Where-Object { ($_.GuestId -match "windows") -and (($_.GuestId -match "srv") -or ($_.GuestId -match "server")) })

$clusterWindowsVMs = @(Get-VM -Server $vCenter  | Where-Object { ($_.GuestId -match "windows") -and (($_.GuestId -match "srv") -or ($_.GuestId -match "server")) })


function RelocateWindowServerVM
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $vmName
    )

    try
    {
        $vm = Get-VM -Server $vCenter -Name $vmName -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Unable to acquire Windows Server VM with name: {0}.")
    }

}

$clusters = @(
    "LAS04-DMZ-CLUSTER-01",
    "LAS04-INT-CLUSTER-01",
    "SE4-DMZ-CLUSTER-01",
    "SE4-INT-CLUSTER-01",
    "DA11-INT-CLUSTER-01",
    "DA11-DMZ-CLUSTER-01",
    "AT4-DMZ-CLUSTER-01",
    "AT4-INT-CLUSTER-01",
    "CDC-DMZ-CLUSTER-01",
    "CDC-INT-CLUSTER-01",
    "CH3-DMZ-CLUSTER-01",
    "CH3-INT-CLUSTER-01",
    "DDC-INT-CLUSTER-01",
    "DDC-DMZ-CLUSTER-01",
    "NY7-INT-CLUSTER-01",
    "NY7-DMZ-CLUSTER-01",
    "ADC-PRD-CLUSTER-01",
    "LAB-DMZ-CLUSTER-01",
    "LAB-PRD-CLUSTER-01"
)

$licenseCount = 0
$n = 0
while($n -lt $clusters.Length)
{
    $vms = @(Get-VM -Location $clusters[$n] | Where-Object { ($_.GuestId -match "windows") -and (($_.Guest.GuestId -match "srv") -or ($_.Guest.GuestId -match "server")) })
    $a = 0
    $clusterLicenses = 0
    while($a -lt $vms.Length)
    {
        $clusterLicenses += 8

        if($vms[$a].NumCpu -gt 8)
        {
            $clusterLicenses += ([Math]::Ceiling(($vms[$a].NumCpu - 8) / 2) * 2)
        }

        $a++
    }

    Write-Host ("{0}: {1} Windows Server VMs, {2}: licenses needed" -f @($clusters[$n], $vms.Length, $clusterLicenses))
    Write-Host ("`t{0}" -f @((@($vms | ForEach-Object { "{0}:{1}:{2}:{3}" -f @($_.Name, $_.NumCpu, $_.PowerState, $_.Guest.GuestId)}) -join "`r`n`t")))
    $licenseCount += $clusterLicenses

    $n++
}
