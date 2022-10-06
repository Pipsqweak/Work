$vdiCluster = Get-Cluster -Name "DDC-VDI-CLUSTER01" -Server $vCenter
$destinationDSwitch = Get-VDSwitch -Server $vCenter -Name "DDC Internal vDS 01"
$destinationPG = Get-VDPortgroup -Server $vCenter -VDSwitch $destinationDSwitch -Name "VL40-CLIENTLAN"
$destinationDS = Get-Datastore -Server $vCenter -Name "DDC_VM_SATA_02"
$destinationCluster = Get-Cluster -Server $vCenter -Name "DDC-INT-CLUSTER-01"

$vmNamesExcluded = @("DDC-P6-CTX-01","DDC-P6-CTX-MI")
$vdiVMs = @(Get-VM -Server $vCenter -Location $vdiCluster | Where-Object { ($_.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOff) -and ($vmNamesExcluded -notcontains $_.Name) })
$goodToGo = $true
$swOverall = [System.Diagnostics.Stopwatch]::new()
$swMigrate = [System.Diagnostics.Stopwatch]::new()
$swConsolidate = [System.Diagnostics.Stopwatch]::new()
while(($goodToGo) -and ($vdiVMs.Length -gt 0))
{
    [void] $swOverall.Reset()
    [void] $swMigrate.Reset()
    [void] $swConsolidate.Reset()

    [void] $swOverall.Start()
    try
    {
        $vmToMigrate = Get-VM -Server $vCenter -Name $vdiVMs[0].Name -Location $vdiCluster -ErrorAction Stop
        $vmNICs = @(Get-NetworkAdapter -VM $vmToMigrate -Server $vCenter)
        if($vmNICs.Length -eq 1)
        {
            if($vmNICs[0].NetworkName -eq "VMGuest-VLAN-40")
            {
                [void] $swMigrate.Start()
                Write-Host ("Migrating {0}..." -f @($vmToMigrate.Name))
                try
                {
                    Move-VM -VM $vmToMigrate -NetworkAdapter $vmNICs[0] -PortGroup $destinationPG -Datastore $destinationDS -Destination $destinationCluster -DiskStorageFormat Thin -Confirm:$false -ErrorAction Stop
                    Write-Host ("`tmigration took: {0}" -f @($swMigrate.Elapsed.ToString()))
                    try
                    {
                        $vmToMigrate = Get-VM -Server $vCenter -Name $vmToMigrate.Name -Location $destinationCluster -ErrorAction Stop
                        if ($vmToMigrate.ExtensionData.Runtime.ConsolidationNeeded)
                        {
                            Write-Host ("Consolidating disks for {0}..." -f @($vmToMigrate.Name))
                            [void] $swConsolidate.Start()
                            try
                            {
                                $vmToMigrate.ExtensionData.ConsolidateVMDisks()
                                Write-Host ("`tconsolidation took: {0}" -f @($swConsolidate.Elapsed.ToString()))
                            }
                            catch
                            {
                                Write-Host ("Failed to consolidate disks for VM: {0}." -f @($vmToMigrate.Name))
                                $vmNamesExcluded += $vmToMigrate.Name
                            }
                            [void] $swConsolidate.Stop()
                        } `
                        else # NOT ($vmToMigrate.ExtensionData.Runtime.ConsolidationNeeded)
                        {
                            # Nothing.
                        }
                    }
                    catch
                    {
                        Write-Host ("Failed to re-acquire VM: {0} post migration." -f @($vmToMigrate.Name))
                        $vmNamesExcluded += $vmToMigrate.Name
                    }
                }
                catch
                {
                    $goodToGo = $false
                }
                [void] $swMigrate.Stop()
            }
            else
            {
                $vmNamesExcluded += $vmToMigrate.Name
            }
        }
        else
        {
            $vmNamesExcluded += $vmToMigrate.Name
        }
    }
    catch { }
    [void] $swOverall.Stop()
    Write-Host ("`tOverall: {0}" -f @($swOverall.Elapsed.ToString()))

    $vdiVMs = @(Get-VM -Server $vCenter -Location $vdiCluster | Where-Object { ($_.PowerState -eq [VMware.VimAutomation.ViCore.Types.V1.Inventory.PowerState]::PoweredOff) -and ($vmNamesExcluded -notcontains $_.Name) })
}
