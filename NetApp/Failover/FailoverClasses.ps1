class FailOverObject
{
    [bool] $Good2Go = $true
}

class FailOverVServer : FailOverObject
{
    [bool] $IsNFSHost = $false
    [DataONTAP.C.Types.Vserver.VserverInfo] $VServer = $null
    [DataONTAP.C.Types.Cifs.CifsServerConfig] $CIFSServer = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]] $CIFSShares = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Net.NetInterfaceInfo]] $NetworkInterfaces = $null
    static [System.String[]] $SharesToIgnore = @("c`$","ipc`$", "Shares`$", "admin`$")

    [void] Initialize()
    {
        # Get the CIFS server associated with the VServer, if there is one.
        LogInfo ("Collecting CIFS data from {0}..." -f @($this.VServer.Identity))
        $funcParams = @{
            Controller = $this.VServer.NcController
            VserverContext = $this.VServer.VserverName
        }
        $result = ReTryCatch -callee "Get-NCCifsServer" -funcParameters $funcParams
        if($result.Good2Go)
        {
            $this.CIFSServer = $result.ReturnValue[0]

            if($null -ne $this.CIFSServer)
            {
                # Get the CIFS shares this CIFS Server hosts.
                $funcParams = @{
                    Controller = $this.VServer.NcController
                    VserverContext = $this.VServer.VserverName
                }
                $result = ReTryCatch -callee "Get-NcCifsShare" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $this.CIFSShares = [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]]::new()
                    @($result.ReturnValue | Where-Object { ($_.ShareName -notin [FailOverVServer]::SharesToIgnore) }).ForEach({ $this.CIFSShares.Add($_) })
                    LogInfo ("Shares: {0}" -f @($this.CIFSShares.Count)) 1
                } `
                else
                {
                    LogError ("Failed to retrieve CIFS shares from {0}." -f @($this.VServer.Identity))
                    $this.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, this VServer must not be a CIFS server.
            }
        } `
        else
        {
            LogError ("Unable to get CIFS server data from {0}." -f @($this.VServer.Identity))
            $this.Good2Go = $false
        }
    }

    FailOverVServer([DataONTAP.C.Types.Vserver.VserverInfo] $vServer)
    {
        $this.VServer = $vServer

        if($null -ne $this.VServer)
        {
            $this.Initialize()
        } `
        else
        {
            # Nothing.
        }

    }
}

class FailOverSourceVServer : FailOverVServer
{
    # The source VServer will have SnapmirrorDestinations.
    [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorDestinationInfo]] $SnapmirrorDestinations = $null

    FailOverSourceVServer([DataONTAP.C.Types.Vserver.VserverInfo] $vServer) : base($vServer)
    {

    }
}

class FailOverDestinationVServer : FailOverVServer
{
    # The destination VServer will have Snapmirrors.
    [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]] $Snapmirrors = $null

    FailOverDestinationVServer([DataONTAP.C.Types.Vserver.VserverInfo] $vServer) : base($vServer)
    {

    }
}

class FailOverSnapmirrorRelationship : FailOverObject
{
    [DataONTAP.C.Types.Volume.VolumeAttributes] $DestinationVolume = $null
    [DataONTAP.C.Types.Volume.VolumeAttributes] $SourceVolume = $null
    [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $Snapmirror = $null
    [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]] $Datastores = $null
}
class FailOverSnapmirror : FailOverObject
{
    [DataONTAP.C.Types.Volume.VolumeAttributes] $OriginalSourceVolume = $null
    [DataONTAP.C.Types.Volume.VolumeAttributes] $SourceVolume = $null
    [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]] $Datastores = $null
    [System.Collections.Generic.List[FailOverSnapmirrorRelationship]] $Relationships = $null
}

class FailOverData : FailOverObject
{
    [bool] $FirstPass = $false
    [bool] $MigratedAllVolumes = $true
    [System.Collections.Generic.List[NetApp.Ontapi.Filer.C.NcController]] $RelatedControllers = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Volume.VolumeAttributes]] $AllVolumes = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Vserver.VserverInfo]] $AllVServers = $null
    [FailOverSourceVServer] $Source = $null
    [FailOverDestinationVServer] $Destination = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]] $Snapmirrors = $null
    [System.Collections.Generic.List[System.Object]] $ActionSequence = $null
    [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]] $NFSDatastores = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorDestinationInfo]] $SnapmirrorDestinations = $null
    [System.Collections.Generic.SortedDictionary[System.String,System.Collections.Generic.List[System.Object]]] $DatastoreToVMHosts
    [System.Collections.Generic.List[System.String]] $ServicePrincipalNames = $null
    [System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]] $CNAMERecords = $null
    [System.Collections.Generic.List[FailOverSnapmirror]] $NewSnapmirrors = $null
    [System.Collections.Generic.List[System.String]] $VolumesToInclude = $null

    [void] GetVServerData([System.String] $sourceVServerName, [System.String] $drVServerName)
    {
        if($this.Good2Go)
        {
            LogInfo "Collecting VServers..."
            # Get all VServer objects ...

            $funcParams = @{
                Controller = @($Global:cDot.Values)
            }

            $result = ReTryCatch -callee "Get-NCVserver" -funcParameters $funcParams

            if($result.Good2Go)
            {
                $this.AllVServers = [System.Collections.Generic.List[DataONTAP.C.Types.Vserver.VserverInfo]]::new()
                $result.ReturnValue.ForEach({ $this.AllVServers.Add($_) })

                # Get enough VServers?
                if($this.AllVServers.Count -ge 2)
                {
                    LogInfo ("Located {0} VServer(s)." -f @($this.AllVServers.Count)) 1
                    $sourceVServers = @($this.AllVServers | Where-Object { $_.VServerName -eq $sourceVServerName })
                    if($sourceVServers.Length -eq 1)
                    {
                        # Unique source VServer was found...
                        $this.Source = [FailOverSourceVServer]::new($sourceVServers[0])

                        LogInfo ("Source VServer: {0}" -f @($this.Source.VServer.Identity)) 1

                        $destinationVServers = @($this.AllVServers | Where-Object { $_.VServerName -eq $drVServerName })
                        if($destinationVServers.Length -eq 1)
                        {
                            # Unique destination VServer was found...
                            $this.Destination = [FailOverDestinationVServer]::new($destinationVServers[0])
                            LogInfo ("Destination VServer: {0}" -f @($this.Destination.VServer.Identity)) 1
                        } `
                        elseif($destinationVServers.Length -eq 0)
                        {
                            # No VServer was found...
                            LogError  ("Failed to retrieve vServer object for {0}." -f @($drVServerName))
                            $this.Good2Go = $false
                        } `
                        else
                        {
                            # Multiple VSerers were found.
                            LogError ("Multiple VServers found for {0}." -f @($drVServerName))
                            $destinationVServers.ForEach({
                                LogError ("{0}" -f @($_.Identity)) 1
                            })
                            $this.Good2Go = $false
                        }
                    } `
                    elseif($sourceVServers.Length -eq 0)
                    {
                        # No VServer was found...
                        LogError  ("Failed to retrieve vServer object for {0}." -f @($sourceVServerName))
                        $this.Good2Go = $false
                    } `
                    else
                    {
                        # Multiple VServers were found.
                        LogError ("Multiple VServers found for {0}." -f @($sourceVServerName))
                        $sourceVServers.ForEach({
                            LogError ("{0}" -f @($_.Identity)) 1
                        })
                        $this.Good2Go = $false
                    }
                } `
                else
                {
                    LogError "Failed to retrieve VServer data from ONTAP clusters."
                    $this.Good2Go = $false
                }
            } `
            else
            {
                LogError "Failed to retrieve VServer data from ONTAP clusters."
                $this.Good2Go = $false
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }
    }

    [void] Initialize([System.String] $sourceVServerName, [System.String] $drVServerName, [bool] $firstPass, [System.String[]] $VolumesToInclude)
    {
        $this.Good2Go = $true

        LogInfo "Collecting data..."

        $this.ActionSequence = [System.Collections.Generic.List[System.Object]]::new()

        if(($null -eq $Global:cDot) -or ($Global:cDot.Count -eq 0))
        {
            LogInfo "Connecting to ONTAP clusters..."
            ConnectTo cdot
        } `
        else
        {
            # Nothing, already connected to ONTAP clusters
        }
        LogInfo ("Connected to {0} ONTAP cluster(s)." -f @($Global:cDot.Count))

        try
        {
            $this.Good2Go = ($null -ne $Global:cDot) -and ($Global:cDot -is [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]]) -and ($Global:cDot.Count -gt 0)
        }
        catch
        {
            LogException "Failed to determine connectivity to ONTAP clusters."
            $this.Good2Go = $false
        }

        $this.GetVServerData($sourceVServerName, $drVServerName)

        $this.FixVolumesToInclude($volumesToInclude)

        $this.GetVolumesData()

        $this.GetSnapmirrorDestinations()

        # After this, we will not need to issue queries to all ONTAP controllers since we now have a list of all controllers involved in the fail over.
        $this.GetRelatedControllers()

        $this.GetSnapmirrors()

        $this.GetCIFSData()

        $this.GetADData()

        # NFS/VMware functionality isn't complete yet...
        $this.GetNFSData()

        $this.BuildNewSnapmirrorRelationships()

        $this.FixupNewSnapmirrors()

        $this.CheckSnapmirrorPolicies()

        $this.CheckSnapshotPolicies()

        $this.CheckVServerPeers()
    }

    # ctor to only process certain volumes
    FailOverData([System.String] $sourceVServerName, [System.String] $drVServerName, [bool] $firstPass, [System.String[]] $volumesToInclude)
    {
        $this.Initialize($sourceVServerName, $drVServerName, $firstPass, $volumesToInclude)
    }

    # ctor for including all volumes
    FailOverData([System.String] $sourceVServerName, [System.String] $drVServerName, [bool] $firstPass)
    {
        $this.Initialize($sourceVServerName, $drVServerName, $firstPass, $null)
    }
}
