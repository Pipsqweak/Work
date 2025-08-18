<#
    UCS DNS RE-IP
#>

$ucsDNSWithBDCDNS = Get-UcsDnsServer -Ucs @($ucsManagers.Values) | Where-Object { $_.Name -match "10\.247\.3\." }
$loopCtrl = @($ucsDNSWithBDCDNS | Where-Object { $_.Dn -match "comm-pol-system" })

$a = 0
while($a -lt $loopCtrl.Length)
{
    $newDNSIP = $loopCtrl[$a].Name.Replace(".3.",".105.")
    $ucs = @($ucsManagers.Values) | Where-Object { $_.Ucs -eq $loopCtrl[$a].Ucs }
    $ucsSvcEndpoint = Get-UcsSvcEp -Ucs $ucs
    $ucsDNS = Get-UcsDns -Ucs $ucs -SvcEp $ucsSvcEndpoint
    $ucsDNSServerToRemove = @($ucsDNSWithBDCDNS | Where-Object { ($_.Ucs -eq $ucs.Ucs) -and ($_.Name -eq $loopCtrl[$a].Name) })
    $null = $ucsDNSServerToRemove | Remove-UcsDnsServer -Ucs $ucs -Force -Confirm:$false
    $currentUCSDNSServers = @(Get-UcsDnsServer -Ucs $ucs)
    if(@($currentUCSDNSServers | Where-Object { $_.Name -eq $newDNSIP }).Length -eq 0)
    {
        $null = Add-UcsDnsServer -Ucs $ucs -Dns $ucsDNS -Name $newDNSIP
    }

    $a++
}

<#
    VM Host Re-IP stuff
#>

$clusterName = "DDC-INT-CLUSTER-01"
$cluster = Get-Cluster -Server $vCenter -Name $clusterName

Stop-SSHService -vmHost $vmh

$vmHostName = "ddc-esx-c2-b8.powereng.com"
$vmh = Get-VMHost -Server $vCenter -Name $vmHostName
Start-SSHService -vmHost $vmh
$nonIsoRule = Get-DrsVMHostRule -Server $vCenter -Cluster $cluster.Name -Name "NonIsolatedVMsToNonIsolatedHosts"
$isoRule = Get-DrsVMHostRule -Server $vCenter -Cluster $cluster.Name -Name "IsolatedVMsToIsolatedHosts"

$isoHostGroup = Get-DrsClusterGroup -Server $vCenter -Cluster $isoRule.Cluster -Name $isoRule.VMHostGroup
if(($isoHostGroup.Member | Where-Object { $_.Name -eq $vmh.Name }).Length -eq 0)
{
    Set-DrsClusterGroup -DrsClusterGroup $isoHostGroup -VMHost $vmh -Add
}

$isoHostGroup.Member.ForEach({
    if($_.Name -ne $vmh.Name)
    {
        Set-DrsClusterGroup -DrsClusterGroup $isoHostGroup -VMHost $_ -Remove
    }
})

$cluster.ExtensionData.RefreshRecommendation()

$wrongDNSServersMatch = "10\.247\.3\."
$correctDNSServers = @("10.247.105.10","10.247.105.20")
$vmHostNetwork = Get-VMHostNetwork -Server $vCenter -VMHost $vmh
$wrongDNSServers = @($vmHostNetwork.DnsAddress | Where-Object { $_ -match $wrongDNSServersMatch })
if($wrongDNSServers.Length -gt 0)
{
    $vmHostNetwork | Set-VMHostNetwork -DnsAddress $correctDNSServers
}

Write-Host "WAIT FOR VMs to move!!"

do
{
    $vms = @(Get-VM -Server $vCenter -Location $vmh | Where-Object { ($_.Name -notmatch "^vCLS\-") -and ($_.Name -notmatch "#OFF" )})
    $onlyMyVM = ($vms.Length -eq 1) -and ($vms[0].Name -eq "DDC-VDISTD-224")
    if(-not $onlyMyVM)
    {
        Start-Sleep -Seconds 5
    }
} while(-not $onlyMyVM)

$vmHosts = @(Get-VMHost -Server $vCenter)
$a = 0
while($a -lt $vmHosts.Length)
{
    $vmh = $vmHosts[$a]
    Write-Host ("Checking {0}" -f @($vmh.Name))

    $vmHostNetwork = Get-VMHostNetwork -Server $vCenter -VMHost $vmh
    $wrongDNSServers = @($vmHostNetwork.DnsAddress | Where-Object { $_ -match $wrongDNSServersMatch })
    if($wrongDNSServers.Length -gt 0)
    {
        $b = 0
        while($b -lt $wrongDNSServers.Length)
        {
            Write-Host ("`tWrong DNS server: {0}" -f @($wrongDNSServers[$b]))
            $b++
        }
        # $vmHostNetwork | Set-VMHostNetwork -DnsAddress $correctDNSServers
    }
    $a++
}
