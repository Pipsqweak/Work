<#                 OLD                   #>


# Make a single query to ONTAP to get both CIFS servers to avoid multiple calls to Get-NcCifsServer
Write-Host -ForegroundColor Green "Retrieving CIFS servers data..."
try
{
    $involvedCIFSServers = @(Get-NcCifsServer -Controller @($cdot.Values) -ErrorAction Stop | Where-Object { $_.CifsServer -in @($SourceCIFSServerName, $DRCIFSServerName) })

    # Capture the source CIFS server which will have CIFS shares migrated from...
    $sourceCIFSServer = $involvedCIFSServers | Where-Object { $_.CifsServer -eq $SourceCIFSServerName } | Select-Object -First 1
    if($null -ne $sourceCIFSServer)
    {
        Write-Host -ForegroundColor Green ("`tSource CIFS Server: {0}:{1}" -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
        # Capture the destination CIFS server where shares will be migrated to...
        $destCIFSServer = $involvedCIFSServers | Where-Object { $_.CifsServer -eq $DRCIFSServerName } | Select-Object -First 1
        if($null -ne $destCIFSServer)
        {
            Write-Host -ForegroundColor Green ("`tDestination CIFS Server: {0}:{1}" -f @($destCIFSServer.NcController.Name, $destCIFSServer.Vserver))
            try
            {
                # If the source CIFS server is not down, make it down...
                if($sourceCIFSServer.AdministrativeStatus -ne "down")
                {
                    # Step 1: Stop CIFS services on the source VServer.  This is to ensure the snapmirror update process send all the latest changes to the destination volume.
                    <#
                        #Stop SMB service at current source
                        vserver cifs stop -vserver LAB-SMB02
                    #>
                    $good2Go = ShutdownCIFSServer -cifsServer $sourceCIFSServer
                }

                # Get all the relevant source CIFS shares...
                try
                {
                    Write-Host -ForegroundColor Green ("Collecting volumes from VServer: {0}:{1}" -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                    $sourceVolumes = @(Get-NCVol -Controller $sourceCIFSServer.NcController -Vserver $sourceCIFSServer.Vserver -ErrorAction Stop | Where-Object { $_.VolumeMirrorAttributes.IsSnapmirrorSourceSpecified -and $_.VolumeMirrorAttributes.IsSnapmirrorSource })

                    if($sourceVolumes.Length -gt 0)
                    {
                        try
                        {
                            # Get all the relevant CIFS shares hosted on the source CIFS server
                            Write-Host -ForegroundColor Green ("Collecting CIFS shares from: {0}:{1}" -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                            $sourceCIFSShares = @(Get-NcCifsShare -Controller $sourceCIFSServer.NcController -CifsServer $sourceCIFSServer.CifsServer -ErrorAction Stop | Where-Object { $_.ShareName -notin @("c$","ipc$", "admin$", "Shares$")})

                            $volumeIdx = 0

                            while($good2Go -and ($volumeIdx -lt $sourceVolumes.Length))
                            {
                                # Capture all the volumes used as snapmirror destinations for the source volume.
                                $newSnapmirrorDestionationVolumes = [System.Collections.Generic.List[System.Object]]::new()

                                Write-Host -ForegroundColor Green ("Processing {0}:{1}:{2}..." -f @($sourceVolumes[$volumeIdx].NcController.Name, $sourceVolumes[$volumeIdx].Vserver, $sourceVolumes[$volumeIdx].Name))
                                $sourceCIFSShares | Where-Object { ($_.VServer -eq $sourceVolumes[$volumeIdx].Vserver) -and ($_.Volume -eq $sourceVolumes[$volumeIdx].Name) } | ForEach-Object {
                                    Write-Host -ForegroundColor Green ("`t\\{0}\{1}" -f @($_.CifsServer, $_.ShareName))
                                }

                                try
                                {
                                    # Get the snapmirror between the source and destination volume...
                                    Write-Host -ForegroundColor Green ("`tRetrieving snapmirror between:  {0}:{1}:{2} and {3}:{4}." -f @($sourceVolumes[$volumeIdx].NcController.Name, $sourceVolumes[$volumeIdx].Vserver, $sourceVolumes[$volumeIdx].Name, $destCIFSServer.NcController.Name, $destCIFSServer.Vserver))

                                    $snapmirrors = @(Get-NCSnapmirror -Controller $destCIFSServer.NcController -DestinationVserver $destCIFSServer.Vserver -SourceVserver $sourceVolumes[$volumeIdx].Vserver -SourceVolume $sourceVolumes[$volumeIdx].Name -ErrorAction Stop)
                                    if($snapmirrors.Length -gt 0)
                                    {
                                        $snapmirrorIdx = 0
                                        while($good2Go -and ($snapmirrorIdx -lt $snapmirrors.Length))
                                        {
                                            # Add the snapmirror destination to the list of destination volumes.
                                            try
                                            {
                                                $destVolume = Get-NCVol -Controller $snapmirrors[$snapmirrorIdx].NcController -Vserver $snapmirrors[$snapmirrorIdx].Vserver -Name $snapmirrors[$snapmirrorIdx].DestinationVolume -ErrorAction Stop
                                                if($null -ne $destVolume)
                                                {
                                                    # Only need to add $destVolume once...
                                                    if($destinationVolumes.IndexOf($destVolume) -eq -1)
                                                    {
                                                        $destinationVolumes.Add($destVolume)
                                                    }
                                                    else
                                                    {
                                                        # Nothing, $destVolume is already in $destinationVolumes
                                                    }
                                                }
                                                else
                                                {
                                                    Write-Host -ForegroundColor Red ("Failed to get volume object for: {0}:{1}:{2}." -f @($snapmirrors[$snapmirrorIdx].NcController.Name, $snapmirrors[$snapmirrorIdx].Vserver, $snapmirrors[$snapmirrorIdx].DestinationVolume))
                                                    $good2Go = $false
                                                }
                                            }
                                            catch
                                            {
                                                Write-Host -ForegroundColor Red ("Exception: Failed to get volume object for: {0}:{1}:{2}." -f @($snapmirrors[$snapmirrorIdx].NcController.Name, $snapmirrors[$snapmirrorIdx].Vserver, $snapmirrors[$snapmirrorIdx].DestinationVolume))
                                                $good2Go = $false
                                            }

                                            # Step 2: Update the snapmirrors...
                                            <#
                                                #Update applicable snapmirrors
                                                snapmirror update -destination-path LABDR-SMB02:*
                                            #>
                                            $good2Go = UpdateSnapmirror -snapmirror $snapmirrors[$snapmirrorIdx]

                                            if($good2Go)
                                            {
                                                # Step 3: Now break the snapmirror...
                                                <#
                                                    #Break existing relationships
                                                    snapmirror break -destination-path LABDR-SMB02:*
                                                #>
                                                $good2Go = BreakSnapmirror -snapmirror $snapmirrors[$snapmirrorIdx]

                                                if($good2Go)
                                                {
                                                    $good2Go = CreateSnapmirror -srcVolume
                                                }
                                                else
                                                {
                                                    # Nothing, an error would have been displayed already.
                                                }
                                            }
                                            else
                                            {
                                                # Nothing, an error would have been displayed already.
                                            }

                                            $snapmirrorIdx++
                                        }
                                    }
                                    else
                                    {
                                        Write-Host -ForegroundColor Yellow ("There does not appear to be a snapmirror between {0}:{1}:{2} and {3}:{4}.`r`n`tPlease fix this manually if required." -f @($sourceVolumes[$volumeIdx].NcController.Name, $sourceVolumes[$volumeIdx].Vserver, $sourceVolumes[$volumeIdx].Name, $destCIFSServer.NcController.Name, $destCIFSServer.Vserver))
                                    }
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Red ("Exception: Unable to retrieve snapmirror between {0}:{1}:{2} and {3}:{4}." -f @($sourceVolumes[$volumeIdx].NcController.Name, $sourceVolumes[$volumeIdx].Vserver, $sourceVolumes[$volumeIdx].Name, $destCIFSServer.NcController.Name, $destCIFSServer.Vserver))
                                    $good2Go = $false
                                }

                                if($good2Go)
                                {
                                    # Step 4: Update snapshot policy on the destination volume (new source).
                                    <#
                                        #Update snapshot policy on new source
                                        vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained
                                    #>

                                    if(-not [String]::IsNullOrEmpty($sourceVolumes[$volumeIdx].VolumeSnapshotAttributes.SnapshotPolicy))
                                    {
                                        # Until we know better, assume we do not have the same snapshot policy on the destination cluster
                                        $haveDestinationSnapshotPolicy = $false

                                        # If the destination cluster is not the same as the source, we need to make sure the snapshot policy exists on the destination cluster
                                        if($sourceVolumes[$volumeIdx].NcController.Name -ne $destCIFSServer.NcController.Name)
                                        {
                                            try
                                            {
                                                $destSnapshotPolicy = Get-NcSnapshotPolicy -Controller $destCIFSServer.NcController -Name $sourceVolumes[$volumeIdx].VolumeSnapshotAttributes.SnapshotPolicy -ErrorAction Stop
                                                if($null -ne $destSnapshotPolicy)
                                                {
                                                    # The same snapshot policy exists on the destination cluster
                                                    $haveDestinationSnapshotPolicy = $true
                                                }
                                                else
                                                {
                                                    Write-Host -ForegroundColor Yellow ("`tSnapshot policy {0} does not exist on {1}." -f @($sourceVolumes[$volumeIdx].VolumeSnapshotAttributes.SnapshotPolicy, $destCIFSServer.NcController.Name))
                                                }
                                            }
                                            catch    #### LEFT OFF HERE -- Deciding how to handle snapshot policy...
                                            {
                                                Write-Host -ForegroundColor Red ("Exception: Failed to retrieve snapshot policy {0} from {1}." -f @($sourceVolumes[$volumeIdx].VolumeSnapshotAttributes.SnapshotPolicy, $destCIFSServer.NcController.Name))
                                                $good2Go = $false
                                            }
                                        }
                                        else
                                        {
                                            $haveDestinationSnapshotPolicy = $true
                                        }
                                    }
                                    else
                                    {
                                        Write-Host -ForegroundColor Yellow ("`tVolume: {0}:{1}:{2} does not have a snapshot policy set." -f @($sourceVolumes[$volumeIdx].NcController.Name, $sourceVolumes[$volumeIdx].Vserver, $sourceVolumes[$volumeIdx].Name))
                                    }
                                }
                                else
                                {
                                    # Nothing.  An error has already been displayed.
                                }
<#
        REMEMBER:  Need to "rotate" the source and destination mirrors... think triangle.
#>
                                # Now create the new snapmirror relationships using the DR volume as the source and all other volumes (including the original source volume)

                                $volumeIdx++
                            }



                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red ("Exception: Unable to retrieve CIFS shares from: {0}:{1}." -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                            $good2Go = $false
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Yellow ("There does not appear to be any volumes on {0}:{1} which are snapmirror sources." -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Exception: Unable to retrieve snapmirror source volumes from: {0}:{1}" -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                    $good2Go = $false
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Exception: Failed to stop CIFS services on {0}:{1}" -f @($sourceCIFSServer.NcController.Name, $sourceCIFSServer.Vserver))
                $good2Go = $false
            }
        }
        else
        {
            Write-Host ("Unable to locate destination CIFS server named: {0}." -f @($DRCIFSServerName))
            $good2Go = $false
        }
    }
    else
    {
        Write-Host ("Unable to locate source CIFS server named: {0}." -f @($SourceCIFSServerName))
        $good2Go = $false
    }
}
catch
{
    Write-Host -ForegroundColor Red "Exception: Failed to retrieve CIFS server data from ONTAP"
    $good2Go = $false
}
