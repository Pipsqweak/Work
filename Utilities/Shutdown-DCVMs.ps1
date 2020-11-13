$powerState = @()
foreach($dc in @("DDC","DDC-VDI"))
{
    $vms = Get-VM -Server $vCenter -Location $dc
    foreach($vm in $vms)
    {
        $powerState += ($vm | Select-Object Name, PowerState)

        if($vm.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn)
        {
           # Stop-VMGuest -Server $vCenter -VM $vm -Confirm:$false
        }
    }
}
@($powerState | Where-Object { $_.PowerState -eq "PoweredOn" }).Length

$powerState | ConvertTo-Json | Set-Content -path "C:\Tmp\preshutdown.json"

$creds = Get-Credential -Message "vCenter"
$vcenter = Connect-VIServer -Server "tdcprdvctr1.powereng.com" -Credential $creds

# Change to where you saved the file....
$powerState = Get-Content -Path "C:\Tmp\preshutdown.json" | ConvertFrom-Json

foreach($vmPS in $powerState)
{
    if($vmPS.PowerState -eq 1)
    {
        Write-Host ("Checking {0}..." -f @($vmPS.Name))
        $vm = Get-VM -Server $vCenter -Name $vmPS.Name
        if(($null -ne $vm) -and ($vm.PowerState -ne [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOn))
        {
            Write-Host ("Powering on {0}..." -f @($vm.Name))

            # Uncomment the next 2 lines to actually power the VMs up...

            # Start-VM -Server $vCenter -VM $vm -Confirm:$false
            # Start-Sleep -Seconds 2
        }
    }
}
