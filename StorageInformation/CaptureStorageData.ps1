[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

<#
    SPECIAL NOTE:

        I have opted to use Invoke-Expression in parts of the code below.  Take care in changing variable names as there may be
        unforeseen issues where variables are assigned values via Invoke-Expression.

        $customStatements.DataSourceSearchStatement
            Variables:
                $row
                $dataElements
                $dataMap
            Used in functions:
                BuildDatamapExpressionStatements, UpdateDBFirstPass

        $customStatements.RowSearchStatement
            Variables:
                $rows
                $dt
                $dataElement
            Used in functions:
                BuildDatamapExpressionStatements, UpdateDBSecondPass
#>

function CollectvServerNFSLIFs([NetAppVServer] $vServer)
{
    <#
        Add all NFS LIFs to the $vServer.
    #>
    if(-not $Global:ErrorLogged)
    {
        # Only collect NFS LIF information for data vServers.
        if($vServer.Source.VserverType -eq "data")
        {
            $ncLIFS = @()
            try
            {
                $ncLIFS = @(Get-NcNetInterface -Controller $vServer.Source.NcController -Vserver $vServer.Name -DataProtocols "NFS" -ErrorAction Stop)
            }
            catch
            {
                LogWarning ($_)
            }

            $a = 0
            while(($a -lt $ncLIFS.Length) -and (-not $Global:ErrorLogged))
            {
                try
                {
                    $lif = $vServer.AddLIF($ncLIFS[$a])
                    LogInfo("        +NFS LIF: {0} ({1})" -f @($lif.Identity, $lif.Address))
                }
                catch
                {
                    LogError ($_)
                }
                $a++
            }
        }
    }
}

function CollectClusterVServerInformation([NetAppCluster] $cluster)
{
    <#
        Add all vServers to $cluster
    #>
    if(-not $Global:ErrorLogged)
    {
        $ncVServers = @()
        $ncCIFSServers = @()
        try
        {
            # Get all the VServers and CIFS servers for the cluster.
            $ncVServers = @(Get-NcVserver -Controller $cluster.Source.NcController -ErrorAction Stop)
            $ncCIFSServers = @(Get-NCCifsServer -Controller $cluster.Source.NcController -ErrorAction Stop)
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $ncVServers.Length) -and (-not $Global:ErrorLogged))
        {
            $ncCIFSServer = $ncCIFSServers | Where-Object { $_.VServer -eq $ncVServers[$a].VServer }
            $cifsServerName = [string]::Empty
            if($null -ne $ncCIFSServer)
            {
                $cifsServerName = $ncCIFSServer.CifsServer
            }

            try
            {
                $vServer = $cluster.AddVServer($ncVServers[$a], $cifsServerName)
                LogInfo ("    +vServer: {0}" -f @($vServer.Identity))

                # Collect all NFS LIFs for the vServer.  This is done so I can later relate VMware datastores to the cluster/vServer that hosts the datastore.
                CollectvServerNFSLIFs $vServer
            }
            catch
            {
                LogError ($_)
            }

            $a++
        }
    }
}

function CollectVolumeShareInformation([NetAppVolume] $vol)
{
    <#
        Get CIFS shares hosted on $vol
    #>
    if ((-not $Global:ErrorLogged))
    {
        # Node root volumes do not have shares, so don't even try.
        if($vol.Source.VolumeStateAttributes.IsNodeRootSpecified -and (-not $vol.Source.VolumeStateAttributes.IsNodeRoot))
        {
            try
            {
                # Create a query template to get a list of shares for this volume
                $query = Get-NcCifsShare -Controller $vol.Source.NcController -Template -ErrorAction Stop
                $query.NcController = $vol.Source.NcController
                $query.Vserver = $vol.VServer.Name
                $query.Volume = $vol.Name

                $volShares = @(Get-NcCifsShare -Controller $query.NcController -Query $query -ErrorAction Stop)
                $a = 0
                while($a -lt $volShares.Length)
                {
                    $newShare = $vol.AddShare($volShares[$a])
                    LogInfo ("            +Share: {0}    ({1})" -f @($newShare.Name, $newShare.Path))
                    $a++
                }
            }
            catch
            {
                LogError($_)
            }
        }
        else #
        {
            # Nothing...
        }
    }
    else # NOT ((-not $Global:ErrorLogged))
    {
        # FALSE

        # Nothing.
    }
}

function CollectVolumeSnapshotInformation([NetAppVolume] $vol)
{
    <#
        Add all snapshots to $vol
    #>
    if ((-not $Global:ErrorLogged))
    {
        # Define $ncSnapshots outside the try/catch so it exists outside the try/catch... seems obvious right...
        $ncSnapshots = @()

        # Node root volumes do not have snapshots, so don't even try.
        if($vol.Source.VolumeStateAttributes.IsNodeRootSpecified -and (-not $vol.Source.VolumeStateAttributes.IsNodeRoot))
        {
            try
            {
                # Since we want $ncSnapshots to exist outside the try/catch, it was defined above, which means we can't just set it equal to something, instead,
                #   add each snapshot to it.
                @(Get-NCSnapshot -Controller $vol.Source.NcController -Vserver $vol.VServer.Name -Volume $vol.Name -ErrorAction Stop) | ForEach-Object { $ncSnapshots += $_ }
            }
            catch
            {
                LogWarning ($_)
            }
        }
        else #
        {
            # Nothing...
        }
        if (-not $Global:ErrorLogged)
        {
            try
            {
                $ncSnapshots | ForEach-Object {
                    $vol.AddSnapshot($_)
                }
            }
            catch
            {
                LogError ($_)
            }
            if((-not $Global:ErrorLogged) -and ($ncSnapshots.Length -gt 0))
            {
                LogInfo ("            +{0} snapshots" -f @($ncSnapshots.Length))
            }
        }
        else # NOT (-not $Global:ErrorLogged)
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ((-not $Global:ErrorLogged))
    {
        # FALSE

        # Nothing.
    }
}

function CollectAggregateVolumeInformation([NetAppAggregate] $aggr)
{
    if (-not $Global:ErrorLogged)
    {
        try
        {
            $ncVols = @(Get-NcVol -Controller $aggr.Source.NcController -Aggregate $aggr.Name -ErrorAction Stop)
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $ncVols.Length) -and (-not $Global:ErrorLogged))
        {
            $vServers = $aggr.Cluster.FindVServerByUUID($ncVols[$a].VolumeIdAttributes.OwningVserverUuid)
            if($vServers.Count -eq 1)
            {
                $vServer = $vServers[0] # This is [0] because I should only ever find 0 or 1 vServer

                try
                {
                    $vol = $aggr.AddVolume($ncVols[$a], $vServer)
                    $vServers[0].Volumes.Add($vol)
                    LogInfo ("        +Volume: {0}:{1}" -f @($vServer.Identity, $vol.Identity))

                    CollectVolumeShareInformation $vol
                    CollectVolumeSnapshotInformation $vol
                }
                catch
                {
                    LogError ($_)
                }
            }
            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

function CollectClusterAggregateInformation([NetAppCluster] $cluster)
{
    <#
        Add all aggregates to $cluster
    #>
    if (-not $Global:ErrorLogged)
    {
        try
        {
            $ncAggrs = @(Get-NcAggr -Controller $cluster.Source.NcController -ErrorAction Stop)
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $ncAggrs.Length) -and (-not $Global:ErrorLogged))
        {
            try
            {
                $aggr = $cluster.AddAggregate($ncAggrs[$a])
                LogInfo ("    +Aggregate: {0}" -f @($aggr.Identity))

                CollectAggregateVolumeInformation $aggr
            }
            catch
            {
                LogError ($_)
            }

            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

function CollectClusterInformation()
{
    # Create collection to hold collected storage information
    $clusters = [NetAppClusterCollection]::new()

    if (-not $Global:ErrorLogged)
    {
        <#
            Loop through all the cluster controllers collecting cluster, vServer, NFS LIF, aggregate, and volume information.
        #>
        $a = 0
        while(($a -lt @($Global:cDot.Values).Length) -and (-not $Global:ErrorLogged))
        {
            $cntrlr = @($Global:cDot.Values)[$a]

            # Get information about the cluster from the cluster controller
            $clusterInfo = $null
            try
            {
                $clusterInfo = Get-NCCluster -Controller $cntrlr -ErrorAction Stop
            }
            catch
            {
                LogError ($_)
            }

            if (-not $Global:ErrorLogged)
            {
                try
                {
                    # Create a new [NetAppCluster] object for the controller
                    $cluster = $clusters.AddCluster($clusterInfo)
                    LogInfo ("Cluster: {0}" -f @($cluster.Identity))

                    # Collect other cluster level information
                    CollectClusterVServerInformation $cluster
                    CollectClusterAggregateInformation $cluster
                }
                catch
                {
                    LogError ($_)
                }
            }
            else # NOT (-not $Global:ErrorLogged)
            {
                # FALSE

                # Nothing.
            }

            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }

    return @( ,$clusters)   # PS is stupid on the way it returns objects.  It really likes to return arrays.  This way, PS gets to return
                            #   an array, but I get my object intact.
}

function CollectSnapmirrorInformation([NetAppClusterCollection] $clusters)
{
    <#
        Populate snapmirror data after volumes have been collected, otherwise the script can't "FindVolumeBySnapmirrorSource" or "FindVolumeBySnapmirrorDestination".

        Get all snapmirrors from all controllers, then link them to the appropriate source and destination [NetAppVolume] objects.
    #>
    if (-not $Global:ErrorLogged)
    {
        $ncSnapmirrors = @()

        try
        {
            # Collect all snapmirrors from all cluster controllers
            $ncSnapmirrors = @(Get-NCSnapmirror -Controller @($Global:cDot.Values))
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $ncSnapmirrors.Length) -and (-not $Global:ErrorLogged))
        {
            # Shortcut for the snapmirror object we are processing
            $snapmirror = $ncSnapmirrors[$a]

            # Find all [NetAppVolume] objects associated with the snapmirror destination.
            $destinationVolumes = $clusters.FindVolumeBySnapmirrorDestination($snapmirror)

            # Make sure a single [NetAppVolume] was located for the snapmirror destination
            if($destinationVolumes.Count -eq 1)
            {
                # Shortcut for the destination snapmirror [NetAppVolume] object we are processing
                $destinationVolume = $destinationVolumes[0]

                # Find all [NetAppVolume] objects associated with the snapmirror source.
                $sourceVolumes = $clusters.FindVolumeBySnapmirrorSource($snapmirror)

                # Make sure a single [NetAppVolume] was located for the snapmirror source
                if($sourceVolumes.Count -eq 1)
                {
                    # Shortcut for the source snapmirror [NetAppVolume] object we are processing
                    $sourceVolume = $sourceVolumes[0]

                    try
                    {
                        # Add the destination [NetAppVolume] to $sourceVolume's list of snapmirrors
                        $sourceVolume.AddSnapmirror($destinationVolume)
                        LogInfo ("+Snapmirror: {0}:{1}:{2} --> {3}:{4}:{5}" -f @($sourceVolume.VServer.Cluster.Name, $sourceVolume.VServer.Name, $sourceVolume.Name, $destinationVolume.VServer.Cluster.Name, $destinationVolume.Vserver.Name, $destinationVolume.Name))
                    }
                    catch
                    {
                        LogError ($_)
                    }
                }
                else
                {
                    if($sourceVolumes.Count -eq 0)
                    {
                        LogInfo ("No source volume found for {0}:{1}:{2}:{3}:{4}" -f @($a, $snapmirror.SourceCluster, $snapmirror.SourceVserver, $snapmirror.SourceVserverUuid, $snapmirror.SourceVolume))
                    }
                    else
                    {
                        LogError ("Multiple source volumes found for {0}:{1}:{2}:{3}:{4}" -f @($a, $snapmirror.SourceCluster, $snapmirror.SourceVserver, $snapmirror.SourceVserverUuid, $snapmirror.SourceVolume))
                        $sourceVolumes | ForEach-Object {
                            LogError ("`t{0}:{0}" -f @($_.VServer.Identity, $_.Identity))
                        }
                    }
                }
            }
            else
            {
                if($destinationVolumes.Count -eq 0)
                {
                    LogError ("No destination volume found for {0}:{1}:{2}:{3}:{4}" -f @($a, $snapmirror.DestinationCluster, $snapmirror.DestinationVserver, $snapmirror.DestinationVserverUuid, $snapmirror.DestinationVolume))
                }
                else
                {
                    LogError ("Multiple destination volumes found for {0}:{1}:{2}:{3}:{4}" -f @($a, $snapmirror.DestinationCluster, $snapmirror.DestinationVserver, $snapmirror.DestinationVserverUuid, $snapmirror.DestinationVolume))
                    $destinationVolumes | ForEach-Object {
                        LogError ("`t{0}:{0}" -f @($_.VServer.Identity, $_.Identity))
                    }
                }
            }

            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

function CollectShareInformation([NetAppClusterCollection] $clusters)
{
    <#
        Populate share data after volumes have been collected, otherwise the script can't successfully call "FindVolumeByShare" for the share volume.

        Get a list of all CIFS shares from all cluster controllers, then link the shares to the appropriate source [NetAppVolume] object.
    #>
    if (-not $Global:ErrorLogged)
    {
        $ncShares = @()
        try
        {
            # Get all CIFS shares from all cluster controllers.
            $ncShares = @(Get-NcCifsShare -Controller @($Global:cDot.Values) -ErrorAction Stop)
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $ncShares.Length) -and (-not $Global:ErrorLogged))
        {
            # Shortcut for the share we are processing
            $share = $ncShares[$a]

            $volumes = @()
            if(-not [String]::IsNullOrEmpty($share.Volume))
            {
                # Find all [NetAppVolume] objects associated with the share.
                $volumes = $clusters.FindVolumeByShare($share)

                # Make sure a single [NetAppVolume] was located for the share
                if($volumes.Length -eq 1)
                {
                    # Shortcut for the [NetAppVolume] we are processing
                    $volume = $volumes[0]

                    try
                    {
                        # Add the share to the [NetAppVolume]
                        $ns = $volume.AddShare($share)
                        LogInfo("Added share: {0} to {1}" -f @($ns.Identity, $volume.Identity))
                    }
                    catch
                    {
                        LogError ($_)
                    }
                }
                elseif ($shareVolumes.Length -eq 0)
                {
                    LogWarning ("No volume found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                }
                else
                {
                    LogError ("Multiple volumes found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                    $volumes | ForEach-Object {
                        LogError ("`t{0}:{0}" -f @($_.VServer.Identity, $_.Identity))
                    }
                }
            }
            else
            {
                LogWarning ("No volume name for {0}:{1}:{2}:{3}:{4}" -f @($a, $share.NCController.Name, $share.Vserver, $share.ShareName, $share.Path))
            }

<#
            $shareClusters = @($clusters | Where-Object { $_.Source.NcController.Name -eq $share.NCController.Name })

            if($shareClusters.Length -eq 1)
            {
                $sharevServers = @($shareClusters[0].VServers | Where-Object { $_.Name -eq $share.Vserver })

                if($sharevServers.Length -eq 1)
                {
                    $sharevServers = @($shareClusters[0].VServers | Where-Object { $_.Name -eq $share.Vserver } )

                    $shareVolumes = @($sharevServers[0].Volumes | Where-Object { $_.Name -eq $share.Volume} )

                    # Make sure a single [NetAppVolume] was located for the share
                    if($shareVolumes.Length -eq 1)
                    {
                        # Shortcut for the [NetAppVolume] we are processing
                        $volume = $shareVolumes[0]

                        try
                        {
                            # Add the share to the [NetAppVolume]
                            $ns = $volume.AddShare($share)
                            LogInfo("Added share: {0} to {1}" -f @($ns.Identity, $volume.Identity))
                        }
                        catch
                        {
                            LogError ($_)
                        }
                    }
                    elseif ($shareVolumes.Length -eq 0)
                    {
                        LogWarning ("No volume found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                    }
                    else
                    {
                        LogError ("Multiple volumes found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                        $shareVolumes | ForEach-Object {
                            LogError ("`t{0}:{0}" -f @($_.VServer.Identity, $_.Identity))
                        }
                    }
                }
                elseif ($sharevServers.Length -eq 0)
                {
                    LogWarning ("No vServer found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                }
                else
                {
                    LogError ("Multiple vServers found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                    $sharevServers | ForEach-Object {
                        LogError ("`t{0}" -f @($_.Identity))
                    }
                }
            }
            elseif ($shareClusters.Length -eq 0)
            {
                LogWarning ("No cluster found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
            }
            else
            {
                LogError ("Multiple clusters found for {0}:{1}:{2}:{3}" -f @($a, $share.NCController.Name, $share.Vserver, $share.Volume))
                $shareClusters | ForEach-Object {
                    LogError ("`t{0}" -f @($_.Identity))
                }
            }
#>
            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

function CollectDatastoreVirtualMachineInformation([VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter, [VMWareDatastore] $datastore, [NetAppClusterCollection] $clusters)
{
    <#
        Get all virtual machines using $datastore.

        Add $datastore to the appropriate [VMWareVirtual] objects
        Add appropriate [VMWareVirtualMachine] objects to $datastore
    #>
    if (-not $Global:ErrorLogged)
    {
        $dsVirtualMachines = @()
        try
        {
            # Get all virtual machines associated with $datastore from $vCenter
            $dsVirtualMachines = @(Get-VM -Server $vCenter -Datastore $datastore.Source -ErrorAction Stop)
        }
        catch
        {
            LogError ($_)
        }

        <#
            Loop through all the datastore virtual machines.

            1. Add $datastore to the [VMWareVirtualMachine] ($vm) object associated with each virtual machine
            2. Add $vm to $datastore's list of [VMWareVirtualMachine]
        #>
        $a = 0
        while(($a -lt $dsVirtualMachines.Length) -and (-not $Global:ErrorLogged))
        {
Write-Host ("Processing VM: {0}:{1} from datastore: {2}:{3}" -f @($dsVirtualMachines[$a].Name, $dsVirtualMachines[$a].Id, $datastore.Name, $datastore.Id))
            # Get a list of unique [VMWareVirtualMachine] objects matching $dsVirtualMachines[$a].Name/ID  (so should be 0 or 1 objects)
            $vms = $clusters.FindVirtualMachineByNameAndId($dsVirtualMachines[$a].Name, $dsVirtualMachines[$a].ID)
                # $virtualMachines | Where-Object { ($_.Name -eq $dsVirtualMachines[$a].Name) -and ($_.Id -eq $dsVirtualMachines[$a].ID) }

            # Set this here so it exists outside the if() scope.
            $vm = $null

            # Only create a new [VMWareVirtualMachine] if one does not already exist.
            if($vms.Count -eq 0)
            {
                $vm = [VMWareVirtualMachine]::new($dsVirtualMachines[$a])
            }
            elseif ($vms.Count -eq 1)
            {
                # Shortcut to the single [VMWareVirtualMachine] object we need to add $datastore to.
                $vm = $vms[0]
            }

            # If we have an appropriate [VMWareVirtualMachine] object, add it to $datastore and add $datastore to it.
            if($null -ne $vm)
            {
                try
                {
                    $vm.AddDatastore($datastore)
                    LogInfo ("Adding datastore {0} to VM {1}" -f @($ds.Identity, $vm.Identity))
                }
                catch
                {
                    LogError ($_)
                }

                if(-not $Global:ErrorLogged)
                {
                    try
                    {
                        $datastore.AddVirtualMachine($vm)
                        LogInfo ("Adding virtual machine {0} to datastore {1}" -f @($vm.Identity, $ds.Identity))
                    }
                    catch
                    {
                        LogError ($_)
                    }
                }
            }
            else
            {

            }

            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

function CollectVMwareInformation([VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter, [NetAppClusterCollection] $clusters)
{
    <#
        Collect all NFS datastore and virtual machine information.

        Associate NFS datastores with the [NetAppVServer]/[NetAppVolume] they are hosted on.
        Associate virtual machines with all [VMWareDatastore] they use
    #>
    if (-not $Global:ErrorLogged)
    {
        $vmDatastores = @()
        try
        {
            $vmDatastores = @(Get-Datastore -Server $vCenter -ErrorAction Stop | Where-Object { $_.Type -eq "NFS" })
Write-Host ("Found {0} NFS datastores" -f @($vmDatastores.Length))
        }
        catch
        {
            LogError ($_)
        }

        $a = 0
        while(($a -lt $vmDatastores.Length) -and (-not $Global:ErrorLogged))
        {
Write-Host ("Processing datastore: {0}) {1}:{2}" -f @($a, $vmDatastores[$a].Name, $vmDatastores[$a].Id))
            $dsVolumes = $clusters.FindVolumeByDatastore($vmDatastores[$a])

            if($dsVolumes.Count -eq 1)
            {
                $dsVolume = $dsVolumes[0]
                $ds = $dsVolume.AddDatastore($vmDatastores[$a])

                if($null -ne $ds)
                {
                    LogInfo ("Adding datastore {0} to volume {1}" -f @($ds.Identity, $dsVolume.Identity))
Write-Host ("Adding datastore {0} to volume {1}" -f @($ds.Name, $dsVolume.Name))
                    CollectDatastoreVirtualMachineInformation $vCenter $ds $clusters
                }
                else
                {
Write-Host ("Unable to add datastore: {0}:{1} to volume:{2}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name, $dsVolume.Name))
                    LogError ("Unable to add datastore: {0}:{1} to volume:{2}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name, $dsVolume.Identity))
                }
            }
            else
            {
                if($dsVolumes.Count -gt 1)
                {
Write-Host ("Multiple volumes found for {0}:{1}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name))
foreach($v in $dsVolumes)
{
    Write-Host ("`t{0}" -f @($v.Name))
}

                    LogError ("Multiple volumes found for {0}:{1}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name))
                    foreach($v in $dsVolumes)
                    {
                        LogError ("`t{0}" -f @($v.Identity))
                    }
                }
                else
                {
Write-Host ("No volumes found for {0}:{1}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name))
                    LogWarning ("No volumes found for {0}:{1}" -f @($vmDatastores[$a].ID, $vmDatastores[$a].Name))
                }
            }
            $a++
        }
    }
    else # NOT (-not $Global:ErrorLogged)
    {
        # FALSE

        # Nothing.
    }
}

<#
Write-Host ("Processing datastore: {0}) {1}:{2}" -f @($a, $vmDatastores[$a].Name, $vmDatastores[$a].Id))
$dsVolumes = $clusters.FindVolumeByDatastore($vmDatastores[$a])
$dsVolumes.Count


$dsVolume = $dsVolumes[0]
$ds = $dsVolume.AddDatastore($vmDatastores[$a])
$ds


LogInfo ("Adding datastore {0} to volume {1}" -f @($ds.Identity, $dsVolume.Identity))
Write-Host ("Adding datastore {0} to volume {1}" -f @($ds.Name, $dsVolume.Name))
CollectDatastoreVirtualMachineInformation $vCenter $ds $clusters
$a++
#>

function CollectStorageInformation()
{
    # Just a diagnostic timer to see how long data collection takes.
    $timer1 = [System.Diagnostics.Stopwatch]::new()
    $timer1.Start()

    # Start by collecting as much information as we can about all the clusters.  VServer, Aggregates, Volumes, Shares, Snapshots, etc...
    $clusters = CollectClusterInformation

    <#
        NOTE: I would have liked to have collected/correlated snapmirror information while populating $clusters, but the problem is, to associate the destination volume to the source volume, both volumes have
              to have been discovered. There is no guarantee a particular destination volume has already been discovered when collecting information about its source.  So I'll wait until I have all the volume
              information prior to matching up source to destination mirror.
    #>
    CollectSnapmirrorInformation $clusters

    # I changed the code to add share information to the volume as the volume is processed.
    # CollectShareInformation $clusters

    CollectVMwareInformation $vCenter $clusters

    [void] $timer1.Stop()
    LogInfo ("Took {0} to populate clusters." -f @($timer1.Elapsed.ToString()))

    return @(,$clusters)
}

<#
    $dataMap layout:

        .DataSource = Array of row data used to update the database
        .TableName = Name of database table for data
        .Columns = Dictionary of tables columns by column name
        .KeyColumns = Array of column names serving as key columns.  The order of names determines sort order.
        .NewRows = Placeholder for new table rows that need to be added to the database.
        .ModifiedRows = Placeholder for modified table rows that need to be updated in the database.
        .DeletedRows = Placeholder for table rows that need to be deleted from the database.



#>
function AddDataMap
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $tableName,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [ValidateCount(1, [Int32]::MaxValue)]
        [string[]]
        $keyColumns,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNull()]
        [ValidateCount(1, [Int32]::MaxValue)]
        [System.Object[]]
        $dataSource,

        [Parameter(Mandatory=$true,Position=4)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $dataMaps
    )

    $dataMap = $null

    # Get a list of property names in the datasource (convert them to all uppercase)
    $propertyNames = @(@($dataSource | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name).ForEach("ToUpper"))

    if($propertyNames.Length -gt 0)
    {
        # Create the datamap object
        $dataMap = "" | Select-Object DataSource,TableName,Columns,KeyColumns,NewRows,ModifiedRows,DeletedRows

        $dataMap.DataSource = $dataSource
        $dataMap.TableName = $tableName
        $dataMap.Columns = [System.Collections.Generic.Dictionary[[System.String],[System.Data.DataRow]]]::new()
        $dataMap.KeyColumns = @($keyColumns.Foreach("ToUpper"))
        $dataMap.NewRows = $null
        $dataMap.ModifiedRows = $null
        $dataMap.DeletedRows = $null

        # Open the connection if it's closed
        $connectionWasClosed = $conn.State -eq [System.Data.ConnectionState]::Closed
        if($connectionWasClosed)
        {
            $conn.Open()
        }

        # Get the table schema
        $cmd = $conn.CreateCommand()
        $cmd.CommandType = [System.Data.CommandType]::Text
        $cmd.CommandText = "SELECT * FROM [{0}] WHERE (1=0);" -f @($tableName)
        $tableSchemaReader = $cmd.ExecuteReader()
        $dtTableSchema = $tableSchemaReader.GetSchemaTable()
        $tableSchemaReader.Close()

        # If the connection was opened in the function, then close it.  (Leave it like it was when the function started)
        if($connectionWasClosed-and ($conn.State -ne [System.Data.ConnectionState]::Closed))
        {
            $conn.Close()
        }

        if($dtTableSchema.Rows.Count -gt 0)
        {
            # Make sure every column is represented in the datasource.
            #   And populate $dataMap.Columns
            $a = 0
            while($a -lt $dtTableSchema.Rows.Count)
            {
                $columnName = $dtTableSchema.Rows[$a].ColumnName.ToUpper()
                $dataMap.Columns.Add($columnName, $dtTableSchema.Rows[$a])

                if(-not $propertyNames.Contains($columnName))
                {
                    LogError ("Missing property {0} in {1} datasource." -f @($columnName, $tableName))
                }
                $a++
            }

            # If $propertyNames has a different number of elements than $dataMap.Columns, then there are missing or extra properties... tell the caller about them.
            #    However, we checked for missing properties in the loop above, so here, there must be extra properties.
            if($propertyNames.Length -ne $dataMap.Columns.Count)
            {
                $a = 0
                while($a -lt $propertyNames.Length)
                {
                    if(-not $dataMap.Columns.ContainsKey($propertyNames[$a]))
                    {
                        LogError ("Extra datasource property {0} in {1}." -f @($propertyNames[$a], $tableName))
                    }
                    $a++
                }
            }
            else
            {
                # Nothing, if $propertyNames.Length -eq $dataMap.Columns.Count then all columns/properties were checked in the previous loop.
            }

            # Make sure all the key columns exist.
            $a = 0
            while($a -lt $dataMap.KeyColumns.Length)
            {
                if(-not $dataMap.Columns.ContainsKey($dataMap.KeyColumns[$a]))
                {
                    LogError ("Unknown key column {0} to table {1}." -f @($dataMap.KeyColumns[$a], $dataMap.TableName))
                }
                $a++
            }
        }
        else
        {
            LogError ("Unable to determine schema for {0}." -f @($tableName))
        }
    }
    else
    {
        LogError ("Unable to determine property names from datasource for {0}." -f @($tableName))
    }

    $dataMaps.Add($dataMap)
    LogInfo ("{0}: {1}" -f @($dataMap.TableName, $dataMap.DataSource.Length))
}

function CreateDataMaps
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [NetAppClusterCollection]
        $storageInformation,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]
        $runID
    )
<#
    SPECIAL NOTE:

    Some of the statements below look like they are repeating "Select-Object", and they are...sort of.  However, when Select-Object is embedded in a Foreach-Object to
    select data from multiple parent containers, both Select-Objects need to be executed.  For example:

    @($storageInformation | ForEach-Object { $_.Aggregates | Foreach-Object { $_.Volumes | ForEach-Object { $_.Datastores | ForEach-Object { $_.VirtualMachines | Select-Object ID, Name } } } } | Select-Object -Unique ID, Name | Sort-Object Name,ID)
        Select-Object #1: Selects virtual machine ID and Name from each datastore on each volume on each aggregate on each cluster.
        Select-Object #2: Selects the UNIQUE virtual machine ID and Names across all virtual machine.

    This is needed, especially for virtual machines, because they can (and do) have VMDKs stored on different datastores.  This means the same virtual machine could be selected from the first
    Select-Object because it exists on multiple datastores.  The second Select-Object then filters out all the duplicates.

    Data that is inherently unique does not use the same technique.  There is no reason to use the second Select-Object to get only unique records since it's already unique.

#>
    $dataMaps = [System.Collections.Generic.List[System.Object]]::new()

    # Data map for DataCollectionData
    AddDataMap $conn "DataCollectionRuns" @("ID") `
        @("" | Select-Object `
            @{N="ID";E={$runID}},
            @{N="CollectionDT";E={$storageInformation.WhenCollected}}) $dataMaps

    # Data map for Clusters
    AddDataMap $conn "Clusters" @("UUID") `
        @($storageInformation | Select-Object -Unique `
            UUID,
            Location,
            SerialNumber,
            Contact,
            Name `
        | Sort-Object Name) $dataMaps

    # Data map for VServers
    AddDataMap $conn "VServers" @("UUID") `
        @($storageInformation | ForEach-Object {
            $_.VServers | Select-Object `
                UUID,
                @{N="ClusterUUID";E={$_.Cluster.UUID}},
                Name,
                CIFSServerName,
                Type
        } | Select-Object -Unique `
            UUID,
            ClusterUUID,
            Name,
            CIFSServerName,
            Type `
        | Sort-Object Name) $dataMaps

    # Data map for Aggregates:
    AddDataMap $conn "Aggregates" @("UUID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Select-Object `
                UUID,
                @{N="ClusterUUID";E={$_.Cluster.UUID}},
                Name,
                SnaplockType
        } | Select-Object -Unique `
            UUID,
            ClusterUUID,
            Name,
            SnaplockType `
        | Sort-Object Name) $dataMaps

    # Data map for Volumes:
    AddDataMap $conn "Volumes" @("UUID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | Select-Object `
                    UUID,
                    @{N="VServerUUID";E={$_.VServer.UUID}},
                    @{N="AggregateUUID";E={$_.Aggregate.UUID}},
                    Name,
                    SnaplockType
            }
        } | Select-Object -Unique `
            UUID,
            VServerUUID,
            AggregateUUID,
            Name,
            SnaplockType `
        | Sort-Object Name) $dataMaps

    # Data map for Datastores:
    AddDataMap $conn "Datastores" @("ID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores `
                    | Select-Object `
                        ID,
                        Name
                }
            }
        } | Select-Object -Unique `
            ID,
            Name `
        | Sort-Object Name) $dataMaps

    # Data map for VirtualMachines:
    AddDataMap $conn "VirtualMachines" @("ID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores | ForEach-Object {
                        $_.VirtualMachines `
                        | Select-Object `
                            ID,
                            Name
                    }
                }
            }
        } | Select-Object -Unique `
            ID,
            Name `
        | Sort-Object Name,ID) $dataMaps

    # Data map for AggregateData:
    AddDataMap $conn "AggregateData" @("RunID","AggregateUUID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Select-Object `
                @{N="RunID";E={$runID}},
                @{N="AggregateUUID";E={$_.UUID}},
                Size,
                Used,
                Available
            } `
        | Sort-Object AggregateUUID) $dataMaps

    # Data map for VolumeData:
    AddDataMap $conn "VolumeData" @("RunID","VolumeUUID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | Select-Object `
                    @{N="RunID";E={$runID}},
                    @{N="VolumeUUID";E={$_.UUID}},
                    IsSnaplockProtected,
                    IsEncrypted,
                    Size,
                    Used,
                    Available
            }
        } `
        | Sort-Object VolumeUUID) $dataMaps

    # Data map for SnapshotData:
    AddDataMap $conn "SnapshotData" @("UUID","VolumeUUID","RunID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Snapshots | Select-Object `
                        @{N="RunID";E={$runID}},
                        UUID,
                        @{N="VolumeUUID";E={$_.Volume.UUID}},
                        Created,
                        ExpiryTime,
                        SnaplockExpiryTime,
                        SnapmirrorLabel,
                        Name,
                        @{N="Size";E={$_.Total}},
                        @{N="CumulativeSize";E={$_.CumulativeTotal}}
                }
            }
        } `
        | Sort-Object VolumeUUID,Created) $dataMaps

    # Data map for SnapmirrorData:
    AddDataMap $conn "SnapmirrorData" @("SourceVolumeUUID","DestinationVolumeUUID","RunID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $sourceVolumeUUID = $_.UUID  # Need this here since $_.UUID will mean something different in the next Select-Object...
                    $_.SnapmirrorDestinations | Select-Object `
                        @{N="RunID";E={$runID}},
                        @{N="SourceVolumeUUID";E={$sourceVolumeUUID}},
                        @{N="DestinationVolumeUUID";E={$_.UUID}}
                }
            }
        } `
        | Sort-Object SourceVolumeUUID,DestinationVolumeUUID) $dataMaps

    # Data map for ShareData:
    AddDataMap $conn "ShareData" @("VolumeUUID","RunID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Shares | Select-Object `
                        @{N="RunID";E={$runID}},
                        @{N="VolumeUUID";E={$_.Volume.UUID}},
                        Path,
                        Name
                }
            }
        } `
        | Sort-Object VolumeUUID,Name) $dataMaps

    # Data map for DatastoreData:
        # 25 Oct 2022:
        #   Added Capacity, FreeSpace, and Uncommitted
    AddDataMap $conn "DatastoreData" @("VolumeUUID","DatastoreID","RunID", "Capacity", "FreeSpace", "Uncommitted") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores | Select-Object `
                        @{N="RunID";E={$runID}},
                        @{N="VolumeUUID";E={$_.Volume.UUID}},
                        @{N="DatastoreID";E={$_.ID}},
                        # Sometimes, Uncommitted will be $null, to be uniform, I handled all the Summary data the same way.
                        @{N="Capacity";E={$_v = $_.Source.ExtensionData.Summary.Capacity; if($null -eq $_v) { $_v = 0 }; $_v }},
                        @{N="FreeSpace";E={$_v = $_.Source.ExtensionData.Summary.FreeSpace; if($null -eq $_v) { $_v = 0 }; $_v }},
                        @{N="Uncommitted";E={$_v = $_.Source.ExtensionData.Summary.Uncommitted; if($null -eq $_v) { $_v = 0 }; $_v }}
                }
            }
        } `
        | Sort-Object VolumeUUID,DatastoreID) $dataMaps

    # Data map for VirtualMachineData:
    AddDataMap $conn "VirtualMachineData" @("VirtualMachineID","RunID") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores | ForEach-Object {
                        $_.VirtualMachines | Select-Object `
                            @{N="RunID";E={$runID}},
                            @{N="VirtualMachineID";E={$_.ID}},
                            @{N="PowerState";E={$_.PowerState}}
                    }
                }
            }
        } `
        | Sort-Object VirtualMachineID) $dataMaps

    # Data map for VirtualMachine_DatastoreData:
    AddDataMap $conn "VirtualMachine_DatastoreData" @("VirtualMachineID","DatastoreID","RunID","Used") `
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores | ForEach-Object {
                        $datastores = $_  # Capture $datastores for later use
                        $_.VirtualMachines | Foreach-Object {
                            $vm = $_      # Capture $vm for later use
                            $dsFileSizes = [System.Collections.Generic.SortedDictionary[[System.String],[Int64]]]::new()  # Dictionary to collect datastore usage
                            $_.Source.ExtensionData.LayoutEx.File | Foreach-Object {
                                if($_.Name -match "^\[(.*?)\]")  # Use a regular expression to get the datastore name
                                {
                                    $fileDSName = $Matches[1]
                                    if(-not $dsFileSizes.ContainsKey($fileDSName))
                                    {
                                        $dsFileSizes.Add($fileDSName, 0)
                                    }
                                    $dsFileSizes[$fileDSName] += $_.Size
                                }
                            }
                            @($dsFileSizes.Keys) | Foreach-Object {
                                $dsName = $_
                                $datastore = @($datastores | Where-Object { ($_.Name -eq $dsName) -and ($_.VirtualMachines -contains $vm) })
                                if($datastore.Length -eq 1)
                                {
                                    $d = "" | Select-Object RunID,VirtualMachineID,DatastoreID,Used
                                    $d.RunID = $runID
                                    $d.DatastoreID = $datastore[0].ID
                                    $d.VirtualMachineID = $vm.ID
                                    $d.Used = $dsFileSizes[$dsName]
                                    $d
                                }
                            }
                        }
                    }
                }
            }
        } | Select-Object -Unique `
            RunID,
            VirtualMachineID,
            DatastoreID,
            Used `
        | Sort-Object VirtualMachineID, DatastoreID) $dataMaps
<#
        @($storageInformation | ForEach-Object {
            $_.Aggregates | Foreach-Object {
                $_.Volumes | ForEach-Object {
                    $_.Datastores | ForEach-Object {
                        $datastoreID = $_.ID
                        $_.VirtualMachines | Select-Object `
                            @{N="RunID";E={$runID}},
                            @{N="VirtualMachineID";E={$_.ID}},
                            @{N="DatastoreID";E={$datastoreID}}
                    }
                }
            }
        } `
        | Sort-Object VirtualMachineID,DatastoreID) $dataMaps
#>
    return $dataMaps.ToArray()
}

function GetNewRunID($conn)
{
    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = "SELECT MAX(ID)+1 FROM DataCollectionRuns;"
    $newRunID = $cmd.ExecuteScalar()

    return $newRunID
}

function BuildDatamapExpressionStatements($datamap)
{

    $orderByClause = [System.Text.StringBuilder]::new()
    $dataSourceWhereClause = [System.Text.StringBuilder]::new()
    $rowWhereClause = [System.Text.StringBuilder]::new()

    $a = 0
    while($a -lt $dataMap.KeyColumns.Length)
    {
        if($orderByClause.Length -eq 0)
        {
            [void] $orderByClause.Append(" ORDER BY")
        }
        if($a -gt 0)
        {
            [void] $orderByClause.Append(",")
            [void] $dataSourceWhereClause.Append(" -and ")
            [void] $rowWhereClause.Append(" -and ")
        }
        [void] $orderByClause.Append(" [{0}]" -f @($dataMap.KeyColumns[$a]))

        [void] $dataSourceWhereClause.Append("(`$_.{0} -eq `$row.{0})" -f @($dataMap.KeyColumns[$a]))
        [void] $rowWhereClause.Append("(`$_.{0} -eq `$dataElement.{0})" -f @($dataMap.KeyColumns[$a]))
        $a++
    }

    $d = "" | Select-Object SelectStatement, DataSourceSearchStatement, RowSearchStatement

    <#
        Because the number of key columns can be different, I'll just build custom expressions for each datamap.

        .DataSourceSearchStatement: The 'Where-Object' statement to find matching $datamap.DataSource elements
        .RowSearchStatement: The 'Where-Object' statement to find matching $dt.Rows
    #>
    $d.DataSourceSearchStatement = "`$dataElements = @(`$dataMap.DataSource | Where-Object {{ {0} }})" -f @($dataSourceWhereClause.ToString())
    $d.RowSearchStatement = "`$rows = @(`$dt.Rows | Where-Object {{ {0} }})" -f @($rowWhereClause.ToString())

    # Create the SQL SELECT statement                     Join all .ColumnNames in .PropertyMap with "," to select all columns in the table.
    $d.SelectStatement = "SELECT {0} FROM [{1}]{2};" -f @((@(@($dataMap.Columns.Keys) | ForEach-Object { "[{0}]" -f @($_) }) -join ", "), $dataMap.TableName, $orderByClause.ToString())


    return @(, $d)
}

function UpdateRowFromDataMapSource($tableName, $row, $dataMapColumnNames, $dataElement)
{
    $b = 0
    while($b -lt $dataMapColumnNames.Length)
    {
        $columnName = $dataMapColumnNames[$b]
        $oldValue = $row.$($columnName)
        $newValue = $dataElement.$($columnName)

        # If $row is new or the column value is changing...
        if(($row.RowState -eq [System.Data.DataRowState]::Detached) -or ($newValue -ne $oldValue))
        {
            <#
                Had some weirdness here.  Trying to do the assignment directly was throwing exceptions assigning GUID to GUID, so I had to get creative.
                The script was throwing a type mismatch exception.

                Originally I had the following:

                    $row.$($columnName) = $dataElement.$($columnName)

                Finally, I came up with the following to "dynamically" cast the source element...
            #>

            # Create a powershell statement to assign the source data element with casting to the new row's column, then invoke the statement...
            $castType = $null

            if($null -ne $newValue)
            {
                $castType = "[{0}]" -f @($newValue.GetType().FullName)
            }
            else
            {
                # The following handles converting null to DBNull so the DB server doesn't reject the statements.
                $newValue = [System.DBNull]::Value
            }

            $stmt = "`$row.{0} = {1}`$newValue" -f @($columnName, $castType)
            try
            {
                Invoke-Expression $stmt -ErrorAction Stop
                # Write-Host ("{0}:{1} changed: {2} -> {3}" -f @($tableName, $columnName, $oldValue, $newValue))
            }
            catch
            {
                Write-Host -ForegroundColor Red ("FAILED: {0}" -f @($stmt))
            }
        }
        $b++
    }
}

<#
    PASS 1: Enumerate existing DB data comparing to collected data.
#>
function UpdateDBFirstPass($datamap, $dt, $customStatements)
{
    # Create an array of column names to make enumerating the .Columns collection easier.
    $dataMapColumnNames = @($dataMap.Columns.Keys)

    $a = 0
    while($a -lt $dt.Rows.Count)
    {
        $row = $dt.Rows[$a]

        # Invoke $customStatements.DataSourceSearchStatement to find all $datamap.Datasource array element that match all of the $row KeyColumns...
        #  Populates $dataElements
        Invoke-Expression $customStatements.DataSourceSearchStatement
        switch($dataElements.Length)
        {
            0 {
                # Old data element -- Consider DELETE FROM [{$dataMap.TableName}] WHERE [{$dataMap.PropertyMap[$dataMap.KeyColumn].ColumnName}] = $row.$($($dataMap.PropertyMap[$dataMap.KeyColumn].ColumnName))
                #  UPDATE: Do not delete the data element, there is likely point-in-time data in the database that requires it.
                #  FUTURE: Potentially do a "scrub" of the database to see if there is any point-in-time data for the row and if not, clean it up across all tables.
                break
            }

            1 { # Existing data element : Update row
                UpdateRowFromDataMapSource $dataMap.TableName $row $dataMapColumnNames $dataElements[0]
                <#
                $b = 0
                while($b -lt $dataMapColumnNames.Length)
                {
                    $rowValue = $row.$($dataMapColumnNames[$b])
                    if($rowValue -is [System.DBNull])
                    {
                        $rowValue = $null
                    }
                    if($rowValue -ne $dataElements[0].$($dataMapColumnNames[$b]))
                    {
                        # Trying to set a UNIQUEIDENTIFIER (Guid) column equal to the dataelement value directly was throwing an exception:
                        #   Exception setting "VSERVERUUID": "Type of value has a mismatch with column typeCouldn't store <3593eca7-5be6-11e5-9609-00a098666986> in VSERVERUUID Column.  Expected type is Guid."
                        # So I adjusted the code as follows, which appears to work.
                        if($row.$($dataMapColumnNames[$b]) -is [Guid])
                        {
                            $row.$($dataMapColumnNames[$b]) = $dataElements[0].$($dataMapColumnNames[$b]).Guid.ToString()
                        }
                        else #
                        {
                            $row.$($dataMapColumnNames[$b]) = $dataElements[0].$($dataMapColumnNames[$b])
                        }
                        Write-Host ("{0}:{4} value changed: {1}:{2}:{3}" -f @($dataMap.TableName, $b, $dataMapColumnNames[$b], $dataElements[0].$($dataMapColumnNames[$b]), $a))
                    }
                    $b++
                }
                #>
                break
            }

            default { # WTH?  More than 1
                Write-Host -ForegroundColor Red ("Multiple {0} data found with:" -f @($dataMap.TableName))
                $b = 0
                while($b -lt $dataMap.KeyColumns.Length)
                {
                    Write-Host -ForegroundColor Red ("`t{0} = {1}" -f @($dataMap.KeyColumns[$b], $row.$($dataMap.KeyColumns[$b])))
                    $b++
                }
                break
            }
        }

        $a++
        if(($a % 1000) -eq 0)
        {
            Write-Host ("Pass 1: Processed {0} records for {1}..." -f @($a, $dataMap.TableName))
        }
    }
    if(($a % 1000) -ne 0)
    {
        Write-Host ("Pass 1: Processed {0} total records for {1}..." -f @($a, $dataMap.TableName))
    }
}

<#
    PASS 2: Enumerate collected data to existing DB data
#>
function UpdateDBSecondPass($dataMap, $dt, $customStatements, $isAllNewData)
{
    # Create an array of column names to make enumerating the .Columns collection easier.
    $dataMapColumnNames = @($dataMap.Columns.Keys)

    # If $isAllNewData then initialize $rows to an array of 0 length to avoid excess comparisons later
    #   The value of $isAllNewData is not changed in the following while loop, so I don't have to worry about re-initializing $rows for every execution of the loop.
    $rows = @()

    $a = 0
    while($a -lt $dataMap.DataSource.Length)
    {
        $dataElement = $dataMap.DataSource[$a]

        # Only invoke $customStatements.RowSearchStatement if we are processing non-point-in-time data.
        if(-not $isAllNewData)
        {
            # Invoke $customStatements.RowSearchStatement to find all rows that match all of the $datamap.DataSource KeyColumns...
            Invoke-Expression $customStatements.RowSearchStatement
        }

        # Even if $customStatements.RowSearchStatement was not invoked, $rows was initialized to an empty array.
        switch($rows.Length)
        {
            0 { # New data row : INSERT
                $newRow = $dt.NewRow()
                UpdateRowFromDataMapSource $dataMap.TableName $newRow $dataMapColumnNames $dataElement

                <#
                $b = 0
                while($b -lt $dataMapColumnNames.Length)
                {
                    <#
                        Had some weirdness here.  Trying to do the assignment directly was throwing exceptions assigning GUID to GUID, so I had to get creative.
                        The script was throwing a type mismatch exception.

                        Originally I had the following:

                            $newRow.$($dataMap.PropertyMap[$b].ColumnName) = $dataElement.$($dataMap.PropertyMap[$b].ColumnName)

                        Finally, I came up with the following to "dynamically" cast the source element...

THERE WAS A COMMENT BLOCK END HERE

                    # Create a powershell statement to assign the source data element with casting to the new row's column, then invoke the statement...
                    $castType = $null
                    $newValue = $dataElement.$($dataMapColumnNames[$b])

                    if($null -ne $newValue)
                    {
                        $castType = "[{0}]" -f @($newValue.GetType().FullName)
                    }
                    else
                    {
                        # The following handles converting null to DBNull so the DB server doesn't reject the statements.
                        $newValue = [System.DBNull]::Value
                    }

                    $stmt = "`$newRow.{0} = {1}`$newValue" -f @($dataMapColumnNames[$b], $castType)
                    try
                    {
                        Invoke-Expression $stmt -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("FAILED: {0}" -f @($stmt))
                    }

                    $b++
                }
                #>
                $dt.Rows.Add($newRow)
                break
            }

            1 { # Existing row : UPDATE -- Always use $rows[0] since there is only 1 element in the array.
                UpdateRowFromDataMapSource $rows[0] $dataMapColumnNames $dataElement
<#
                $b = 0
                while($b -lt $dataMapColumnNames.Length)
                {
                    $rowValue = $rows[0].$($dataMapColumnNames[$b])
                    if($rowValue -is [System.DBNull])
                    {
                        $rowValue = $null
                    }
                    if($rowValue -ne $dataElement.$($dataMapColumnNames[$b]))
                    {
                        $rows[0].$($dataMapColumnNames[$b]) = $dataElement.$($dataMapColumnNames[$b])
                        Write-Host ("{0} value changed: {1}:{2}:{3}" -f @($dataMap.TableName, $b, $dataMapColumnNames[$b], $dataElement.$($dataMapColumnNames[$b])))
                    }
                    $b++
                }
#>
                break
            }

            default { # WTH?  More than 1
                Write-Host -ForegroundColor Red ("{0} rows found with:" -f @($rows.Length))
                $b = 0
                while($a -lt $dataMap.KeyColumns.Length)
                {
                    Write-Host -ForegroundColor Red ("`t{0} = {1}" -f @($dataMap.KeyColumns[$b], $dataElement.$($dataMap.KeyColumns[$b])))
                    $b++
                }
                break
            }
        }

        $a++
        if(($a % 1000) -eq 0)
        {
            Write-Host ("Pass 2: Processed {0} records for {1}..." -f @($a, $dataMap.TableName))
        }
    }
    if(($a % 1000) -ne 0)
    {
        Write-Host ("Pass 2: Processed {0} total records for {1}..." -f @($a, $dataMap.TableName))
    }
}

function UpdateDBFromDataMap($conn, $dataMap)
{
    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text

    # If the table/data contains a 'RunID' column, then the data represents all new "point-in-time" data.
    #  Meaning the data represents things like volume size, volume used, etc.  "point-in-time data."
    $isAllNewData = $dataMap.Columns.ContainsKey("RUNID")



    # Change this to not load all data when -not $isAllNewData


    # Build custom statements for the datamap
    $customStatements = BuildDatamapExpressionStatements $dataMap

    # Create the SQL SELECT statement                     Join all .ColumnNames in .PropertyMap with "," to select all columns in the table.
    $cmd.CommandText = $customStatements.SelectStatement

    # Create a DataReader object to read all the data from the SQL database table
    $rdr = $cmd.ExecuteReader()

    # Create and load a datatable to hold the results of the select
    $dt = [System.Data.DataTable]::new()
    $dt.Load($rdr)

    # If the datamap represents only point-in-time data, then no need to bother trying to update existing database data...
    if(-not $isAllNewData)
    {
        UpdateDBFirstPass $datamap $dt $customStatements
    }

    UpdateDBSecondPass $datamap $dt $customStatements $isAllNewData

    $dataMap.NewRows = $dt.GetChanges([System.Data.DataRowState]::Added)
    $dataMap.ModifiedRows = $dt.GetChanges([System.Data.DataRowState]::Modified)

    if($null -ne $dataMap.NewRows)
    {
        Write-Host ("New: {0}" -f @($dataMap.NewRows.Rows.Count))

        # See Insertsql.ps1 to add new rows...
    }

    if($null -ne $dataMap.ModifiedRows)
    {
        Write-Host ("Modified: {0}" -f @($dataMap.ModifiedRows.Rows.Count))

        # TODO: Create ModifySQL.ps1
    }
}

function MakeParameter($dataMap, $columnName, $row, $rowNumber)
{
    <#
        MakeParameter created a simple object representing a parameter name and value.
          It's primary purpose to to check if a column is a string type, and if so, return a .Value
          that is database/table/column safe.
    #>
    $d = "" | Select-Object Name, Value
    $d.Name = "@{0}{1}" -f @($columnName, $rowNumber)
    $d.Value = $row.$($columnName)

    if(($dataMap.Columns[$columnName].ProviderSpecificDataType -match "string") -and ([string]::IsNullOrEmpty($d.Value)))
    {
        if($dataMap.Columns[$columnName].AllowDBNull)
        {
            # If the string is null or empty, and the column allows null, then send DBNull vs null.
            #    At the time I wrote this comment, I cannot remember the exact situation, but suffice it to say,
            #    I did run into some weirdness sending $null vs [System.DBNull]::Value.
            $d.Value = [System.DBNull]::Value
        }
        else
        {
            # If the column does not allow nulls, then send an empty string vs null
            $d.Value = [string]::Empty
        }
    }

    return (, $d)
}

<#
    UpdateDBInsertNewRows dynamically builds SQL INSERT statements shown below.

    INSERT INTO [dbo].[AggregateData] ([RUNID], [AGGREGATEUUID], [SIZE], [USED], [AVAILABLE]) VALUES
        (@RUNID0,@AGGREGATEUUID0,@SIZE0,@USED0,@AVAILABLE0),
        (@RUNID1,@AGGREGATEUUID1,@SIZE1,@USED1,@AVAILABLE1),
        (@RUNID2,@AGGREGATEUUID2,@SIZE2,@USED2,@AVAILABLE2),
        (@RUNID3,@AGGREGATEUUID3,@SIZE3,@USED3,@AVAILABLE3),
        (@RUNID4,@AGGREGATEUUID4,@SIZE4,@USED4,@AVAILABLE4),
        (@RUNID5,@AGGREGATEUUID5,@SIZE5,@USED5,@AVAILABLE5),
        (@RUNID6,@AGGREGATEUUID6,@SIZE6,@USED6,@AVAILABLE6),
        (@RUNID7,@AGGREGATEUUID7,@SIZE7,@USED7,@AVAILABLE7)

        SQL parameters are used to feed the data to the SQL Command object
            SqlCommand: https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlcommand?view=dotnet-plat-ext-5.0
            SqlParameter: https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlparameter?view=dotnet-plat-ext-5.0

        The maximum number of parameters is hard capped at 2100 (https://docs.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?redirectedfrom=MSDN&view=sql-server-ver15).
           To deal with this, I make sure the current number of parameters + the number of parameters the next row will add does not exceed 2000.  If it does, the SQL statement is completed and
           sent to the SQL server, and I start the process over.
#>

function UpdateDBInsertNewRows($conn, $dataMap)
{
    # Create an array of column names to make enumerating the .Columns collection easier.
    $dataMapColumnNames = @($dataMap.Columns.Keys)

    # Base INSERT Query for the $dataMap
    $insertQuery = "INSERT INTO [dbo].[{0}] ({1}) VALUES" -f @($dataMap.TableName, (@($dataMapColumnNames | ForEach-Object { "[{0}]" -f @($_) }) -join ", "))

    # $querySB is used to construct a complete SQL Statement
    $querySB = [System.Text.StringBuilder]::new()

    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text

    $rowNumber = 0
    $totalInserts = 0
    while(($null -ne $dataMap.NewRows) -and ($rowNumber -lt $dataMap.NewRows.Rows.Count))
    {
        $row = $dataMap.NewRows.Rows[$rowNumber]

        # If the query string builder is empty, then start it out with $insertQuery
        if($querySB.Length -eq 0)
        {
            [void] $querySB.AppendLine($insertQuery)

            # If I'm just now adding $insertQuery to $querySB, then I can also clear $cmd.Parameters for good measure.
            $cmd.Parameters.Clear()
        }

        # temporary array for this row's parameter set
        $parameterSet = @()
        $p = 0
        while($p -lt $dataMapColumnNames.Length)
        {
            # $param.Name = @COLUMNNAMEX
            # $param.Value = $row.COLUMNNAME (or DBNull if needed)
            $param = MakeParameter $dataMap $dataMapColumnNames[$p] $row $rowNumber

            $sqlParam = $cmd.Parameters.Add($param.Name, $dataMap.Columns[$dataMapColumnNames[$p]].ProviderSpecificDataType)
            $sqlParam.Value = $param.Value

            $parameterSet += $param.Name
            $p++
        }

        # Parameters to $querySB
        [void] $querySB.Append(("({0})" -f @(($parameterSet -join ","))))

        # Increment to the next row.  Must be completed prior to the if statements below for them to be evaluated accurately
        $rowNumber++

        # If this is not the last row, append a ,<cr-lf> otherwise, just <cr-lf> to $querySB
        if($rowNumber -ne $dataMap.NewRows.Rows.Count)
        {
            [void] $querySB.AppendLine(",")
        }
        else
        {
            [void] $querySB.AppendLine("")
        }

        <#
            Reference:
                https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?redirectedfrom=MSDN&view=sql-server-ver15
                    Parameters per user-defined function: 2100

                I chose to stop adding parameters closer to 2000 just to be safe.

            If
                1) adding the next row of parameters to $cmd.Parameters will exceed 2000 parameters, OR
                2) we are at the end of rows to insert
            then execute the INSERT and reset to start again if we need to.
        #>
        if((($cmd.Parameters.Count + $dataMap.Columns.Count) -gt 2000) -or ($rowNumber -eq $dataMap.NewRows.Rows.Count))
        {
            # Trim extraneous characters off the end of the query.  I think I fixed the issue, but doesn't hurt to leave this as is.
            $cmd.CommandText = $querySB.ToString().TrimEnd(@("`r","`n",","))

            $r = $cmd.ExecuteNonQuery()
            $totalInserts += $r
            Write-Host ("Added {0} rows [{1} total]" -f @($r, $totalInserts))

            # Clear $querySB and reseed it with $insertQuery so it's read for any remaining rows (if the query got to large)...
            [void] $querySB.Clear()
            [void] $querySB.AppendLine($insertQuery)
            $cmd.Parameters.Clear()
        }
    }
}

function UpdateDBUpdateModifiedRows($conn, $dataMap)
{
    <#
        Since I'm an SQL hack and I couldn't find a wait I liked or understood to send multiple updates per query, I will
        just create a single SQL command object and reuse it to send an update query to the server for each modified row.
    #>
    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text

    # Track the number of updates completed.
    $totalUpdates = 0
    $rowNumber = 0
    while(($rowNumber -lt $dataMap.ModifiedRows.Rows.Count) -and (-not $Global:ErrorLogged))
    {
        # Reuse the SQLCommand object, but reset the parameters each time.
        $cmd.Parameters.Clear()

        # Get a list of all column names that need to be updated, excluding key columns as these should never change.
        #  NOTE: Ensure the result is an array of string.  Without the enclosing @(), if a single column has to be updated, then the single column name gets treated
        #        like an array of characters and the update statement ends up looking like: UPDATE [TABLE] SET [N] = @N0, [A] = @A, [M] = @M0, [E] = @E0 WHERE ([ID] = @ID0);
        $updateColumns = @(($dataMap.ModifiedRows.Columns | Select-Object -ExpandProperty COLUMNNAME) | Where-Object { $_ -notin $dataMap.KeyColumns })

        # Array of strings used to create the SET clause in the UPDATE query using SQL parameter values:
        #    ex: "[CLUSTERUUID] = @CLUSTERUUID0", "[UUID] = @UUID0", "[NAME] = @NAME0"
        #      The number following the parameter name is the row number within $dataMap.ModifiedRows, this was used to reuse the function MakeParameter
        #      The strings are joined with " ," to create the complete SET clause.
        $setPieces = @()

        # Array of strings used to create the WHERE clause in the UPDATE query using SQL parameter values:
        #    ex: "([UUID] = @UUID0)"
        #      The number following the parameter name is the row number within $dataMap.ModifiedRows, this was done so I could reuse the function MakeParameter
        #      The strings are joined with " AND " to create the complete WHERE clause.
        $wherePieces = @()

        # Process each column to update, creating a SET sub-statement and SQL Parameter for each column.
        $columnIndex = 0
        while(($columnIndex -lt $updateColumns.Length) -and (-not $Global:ErrorLogged))
        {
            # Create the SET sub-statement for this column and add it to $setPieces
            $piece = "[{0}] = @{0}{1}" -f @($updateColumns[$columnIndex], $rowNumber)
            $setPieces += $piece

            # Call MakeParameter to create a param object that can be used to create an SQL Parameter, then add it to the SQL Command object parameters.
            $param = MakeParameter $dataMap $updateColumns[$columnIndex] $dataMap.ModifiedRows.Rows[$rowNumber] $rowNumber
            $sqlParam = $cmd.Parameters.Add($param.Name, $dataMap.Columns[$updateColumns[$columnIndex]].ProviderSpecificDataType)
            $sqlParam.Value = $param.Value

            $columnIndex++
        }

        # Process each key column, creating a WHERE condition string and SQL Parameter for each column.
        $columnIndex = 0
        while(($columnIndex -lt $dataMap.KeyColumns.Length) -and (-not $Global:ErrorLogged))
        {
            # Create the WHERE condition string for this key column and add it to $wherePieces
            $piece = "([{0}] = @{0}{1})" -f @($dataMap.KeyColumns[$columnIndex], $rowNumber)
            $wherePieces += $piece

            # Call MakeParameter to create a param object that can be used to create an SQL Parameter, then add it to the SQL Command object parameters.
            $param = MakeParameter $dataMap $dataMap.KeyColumns[$columnIndex] $dataMap.ModifiedRows.Rows[$rowNumber] $rowNumber
            $sqlParam = $cmd.Parameters.Add($param.Name, $dataMap.Columns[$updateColumns[$columnIndex]].ProviderSpecificDataType)
            $sqlParam.Value = $param.Value

            $columnIndex++
        }

        # Construct the UPDATE query using the string arrays we created above.
        $cmd.CommandText = "UPDATE [{0}] SET {1} WHERE {2};" -f @($dataMap.TableName, ($setPieces -join ", "), ($wherePieces -join " AND "))
        Write-Host ($cmd.CommandText)

        # Send it!
        $r = $cmd.ExecuteNonQuery()
        $totalUpdates += $r

        $rowNumber++
    }
}


<# Main Function below #>


$JSONArgsFile = "SnaplockReporter-kbriney-adm.json"

Import-Module DataONTAP
Import-Module VMware.VimAutomation.Core

$requiredFilesAvailable = $true
$requiredFiles = @(
    $JSONArgsFile,                               # Contains information used in the operation of the script.
    "CMTraceLog.ps1",                            # PS script to provide CMTrace formatted logging
    "LoadConfigurationData.ps1",                 # Loads and verifies the contents of $JSONArgsFile
    "StorageInfoClasses.ps1",                    # Loads C# classes
    "StorageInfoClasses\StorageInfoClasses.cs",  # C# source code to define classes used in this script
    "LocalDB.ps1",                               # Defines a class providing SQL connectivity via LocalDB (https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/sql-server-express-localdb?view=sql-server-ver15)
    "Connect-NetApp.ps1"                         # Script to connect to NetApp Clusters and 7-mode filers
)

# For debugging purposes:  If the script is not ran from the command line (loaded by the powershell interpreter), then artificially set it.
$scriptRoot = $PSScriptRoot
if([String]::IsNullOrEmpty($scriptRoot))
{
    $scriptRoot = (Get-Location).Path
}

# Make sure all the files required to make this script functional are available.
foreach($requiredFile in $requiredFiles)
{
    $testFile = "{0}\{1}" -f @($scriptRoot, $requiredFile)
    if(-not (Test-Path -Path $testFile))
    {
        Write-Error ("Missing required file: {0}." -f @($testFile))
        $requiredFilesAvailable = $false
    }
}

# If we are missing any of the required files, terminate the script.
if(-not $requiredFilesAvailable) { return }

# Source in the logging functions.
. .\CMTraceLog.ps1
if(-not $Global:CMLoggingAvailable)
{
    Write-Error "CM Logging capabilities not available"
    return
}

# Source in LoadConfigurationData function.  This function is stored externally since it is used in other scripts.
. .\LoadConfigurationData.ps1

# Verify LoadConfigurationData was source into the script.
try
{
    Get-ChildItem -Path Function:\LoadConfigurationData -ErrorAction Stop | Out-Null
}
catch
{
    LogError "Unable to locate Function:\LoadConfigurationData, terminating script."
    return
}

# Load script initialization information.
$Global:scriptConfig = LoadConfigurationData $JSONArgsFile

# If errors were logged terminate the script
if($Global:ErrorLogged) { return }

# Get all but the most recent $scriptConfig.LogsToKeep log files so we can delete them
$oldLogs = @(Get-ChildItem -Path $Global:scriptConfig.LogPath | Sort-Object -Descending LastWriteTime | Select-Object -Skip $Global:scriptConfig.LogsToKeep)
if($oldLogs.Length -gt 0)
{
    $oldLogs | Remove-Item -Confirm:$false
}

# Load C# classes for the script
. .\StorageInfoClasses.ps1 $requiredFiles[4]

# If errors were logged terminate the script
if($Global:ErrorLogged) { return }

# Load the LocalDB class...
. .\LocalDB.ps1

# If errors were logged terminate the script
if($Global:ErrorLogged) { return }

# Source in Connect-NetApp.ps1 to connect to all the NetApp clusters/7-mode filers as required.
. .\Connect-NetApp.ps1

# If errors were logged terminate the script
if($Global:ErrorLogged) { return }

try
{
    $vCenterCredential = [System.Management.Automation.PsCredential]::new($Global:scriptConfig.vCenter.UserName, ($Global:scriptConfig.vCenter.Password | ConvertTo-SecureString))
    $Global:vCenter = Connect-VIServer -Server $Global:scriptConfig.vCenter.Server -Credential $vCenterCredential -ErrorAction Stop
}
catch
{
    LogError ("Failed to connect to vCenter server {0}." -f @($Global:scriptConfig.vCenter.Server))
}

<#
    NOTE: Still need to clean up the following code...
#>

$myConn = [LocalDB]::GetLocalDB("StorageInformation", $false)
$runID = GetNewRunID $myConn
Write-Host ("Run ID: {0}" -f @($runID))
$storageInformationCollection = CollectStorageInformation
$dataMaps = CreateDataMaps $myConn $storageInformationCollection $runID

$j = 0
while($j -lt $dataMaps.Length)
{
    Write-Host ("{0}" -f @($dataMaps[$j].TableName))
    UpdateDBFromDataMap $myConn $datamaps[$j]

    if(($null -ne $dataMaps[$j].NewRows) -and ($dataMaps[$j].NewRows.Rows.Count -gt 0))
    {
        UpdateDBInsertNewRows $myConn $dataMaps[$j]
    }

    if(($null -ne $dataMaps[$j].ModifiedRows) -and ($dataMaps[$j].ModifiedRows.Rows.Count -gt 0))
    {
        UpdateDBUpdateModifiedRows $myConn $dataMaps[$j]
    }
    $j++
}
