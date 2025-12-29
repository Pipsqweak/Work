ConnectTo vCenter
$masterServerData = Import-CSV -Path "E:\tmp\WSPMasterServerStuff\compute.csv" -Delimiter "`t"

$esxiHosts = @(Get-VMHost -Server @($vCenter,$labvCenter))

$a = 0
while ($a -lt $esxiHosts.Length)
{
    $serverData = @($masterServerData | Where-Object { $esxiHosts[$a].Name -match ("{0}\." -f @($_.ServerName)) })

    if($serverData.Length -eq 0)
    {
        Write-Host ("Missing ESXi host: {0}" -f @($esxiHosts[$a].Name))
    } `
    elseif ($serverData.Length -eq 1)
    {
        $serverData[0].AccountedFor = $true
    }
    else
    {
        Write-Host ("Multiple found for: {0}" -f @($esxiHosts[$a].Name))
        $serverData.ForEach({
            Write-Host ("`t{0}" -f @($_.ServerName))
        })
    }
    $a++
}

$vms = @(Get-VM -Server @($vCenter, $labvCenter) | Where-Object { $_.Name -notmatch "^vCLS"} | Sort-Object Name)
$a = 0
while ($a -lt $vms.Length)
{
    $serverData = @($masterServerData | Where-Object { $vms[$a].Name -eq $_.ServerName })

    if($serverData.Length -eq 0)
    {
        Write-Host ("Missing VM: {0}" -f @($vms[$a].Name))
    } `
    elseif ($serverData.Length -eq 1)
    {
        $serverData[0].AccountedFor = $true
    }
    else
    {
        Write-Host ("Multiple found for: {0}" -f @($vms[$a].Name))
        $serverData.ForEach({
            Write-Host ("`t{0}" -f @($_.ServerName))
        })
        break
    }
    $a++
}
