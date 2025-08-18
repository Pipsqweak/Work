$nfsDatastores = Get-Datastore -Server $vcenter | Where-Object { $_.Type -eq "NFS" }
$cdotInterfaces = @(Get-NcNetInterface -Controller @($cDot.Values))

$dataStoreLIF = $cdotInterfaces | Where-Object { $_.Address -eq $nfsDatastores[0].RemoteHost }

$datastoreVInfo = $vInfos | Where-Object { ($_.baseVolume.VServer -eq $dataStoreLIF.Vserver) -and ($_.baseVolume.JunctionPath -eq $nfsDatastores[0].RemotePath) }

# [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]] $cDot
# [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter


$a = 0
while($a -lt $vInfos.Count)
{
    # Find all VMware datastores where the datastore remote path matches this volumes junction path.
    $dsMatchingPath = @()
    @($nfsDatastores | Where-Object { $_.RemotePath -eq $vInfos[$a].baseVolume.JunctionPath } ) | ForEach-Object {
        $ds = $_
        if(@($dsMatchingPath | Where-Object { ($_.RemoteHost -eq $ds.RemoteHost) -and ($_.RemotePath -eq $ds.RemotePath) }).Length -eq 0)
        {
            $dsMatchingPath += $ds
        }
    }

    if($dsMatchingPath.Length -gt 0)
    {
        # Found at least one datastore with a matching path

        # Build an array of unique remote host addresses for the matching datastores
        $dsRemoteHostAddresses = @()
        $dsMatchingPath | ForEach-Object {
            $_.RemoteHost | ForEach-Object {
                if($dsRemoteHostAddresses -notcontains $_)
                {
                    $dsRemoteHostAddresses += $_
                }
            }
        }

        # Now find all NFS LIFs that match one of the matching datastores' remote addresses AND are hosted on the same VServer this volume is on.
        $datastoreLIFS = @($cdotInterfaces | Where-Object { ($dsRemoteHostAddresses -contains $_.Address) -and ($_.VServer -eq $vInfos[$a].baseVolume.Vserver) -and ($_.NCController.Name -eq $vInfos[$a].baseVolume.NcController.Name) })

        # If there is at least 1 LIF that matches this volume's VServer and NC Controller after already matching the junction path to the datastore remote path, I think we're good..
        if($dataStoreLIFS.Length -gt 0)
        {
            $dataStoreLIFS | ForEach-Object {
                $lif = $_
                $ds = $dsMatchingPath | Where-Object { ($_.RemoteHost -eq $lif.Address) -and ($_.RemotePath -eq $vInfos[$a].baseVolume.JunctionPath) }

                $dsVMs = @($ds.ExtensionData.Vm | ForEach-Object { $vmId = "{0}-{1}" -f @($_.Type, $_.Value); $vm = Get-VM -Server $vCenter -Id $vmId -ErrorAction SilentlyContinue; <# Write-Host ("{0}:{1}" -f @($vm.Name, $vmID));#> if(($null -ne $vm) -and (-not $vm.Name.StartsWith("vCLS"))) { $vm } })

                $ds.RemoteHost | ForEach-Object {
                    Write-Host ("{5}) {0}:{1} --> {2}:{3}:{4}" -f @($_, $ds.RemotePath, $vInfos[$a].baseVolume.NcController.Name, $vInfos[$a].baseVolume.Vserver, $vInfos[$a].baseVolume.Name, $a))
                }

                $dsVMs | ForEach-Object {

                    Write-Host ("`t{0} : {1}" -f @($_.Name, $_.PowerState))
                }
            }
            Write-Host
        }
    }




    $a++
}
