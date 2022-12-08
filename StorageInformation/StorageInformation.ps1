class DataObject
{
    [System.Object] $_sourceObject = $null
    hidden [System.String] $_identity

    DataObject([System.Object] $sourceObject)
    {
        if ($null -eq $sourceObject)
        {
            throw "Missing sourceObject in DataObject."
        } `
        else # NOT ($null -eq $sourceObject)
        {
            # Nothing.
        }

        $this._sourceObject = $sourceObject

        # .Identity psuedo property
        $this | Add-Member -Name Identity -MemberType ScriptProperty -Value {
            return $this._identity
        } -SecondValue {
            param($value)
            $this._identity = $value
        }

        # .Name psuedo property  (use -Force to override in inherited classes)
        $this | Add-Member -Name Name -MemberType ScriptProperty -Value {
            if (-not [String]::IsNullOrEmpty($this._sourceObject.Name))
            {
                return $this._sourceObject.Name
            } `
            else # NOT (-not [String]::IsNullOrEmpty($this._sourceObject.Name))
            {
                return [String]::Empty
            }
        }
    }
}

class NetAppObject : DataObject
{
    NetAppObject([System.Object] $sourceObject) : base($sourceObject)
    {
        if ($null -eq $sourceObject.NcController)
        {
            throw "Null NcController property in NetAppObject ctor."
        } `
        else # NOT ($null -eq $sourceObject.NcController)
        {
            # Nothing.
        }

        # .ControllerName psuedo property
        $this | Add-Member -Name ControllerName -MemberType ScriptProperty -Value {
            if (-not [String]::IsNullOrEmpty($this._sourceObject.NcController.Name))
            {
                return ($this._sourceObject.NCController.Name -split '\.')[0].ToUpper()
            } `
            else # NOT (-not [String]::IsNullOrEmpty($this._sourceObject.NcController.Name))
            {
                return [String]::Empty;
            }
        }
    }
}


class NetAppCluster : NetAppObject
{
    NetAppCluster([DataONTAP.C.Types.Cluster.ClusterIdentityInfo] $clusterInfo) : base($clusterInfo)
    {
        # .UUID psuedo property
        $this | Add-Member -Name UUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterUuid
        }

        # .Location psuedo property
        $this | Add-Member -Name Location -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterLocation
        }

        # .SerialNumber psuedo property
        $this | Add-Member -Name SerialNumber -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterSerialNumber
        }

        # .Contact psuedo property
        $this | Add-Member -Name Contact -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterContact
        }

        # .Name psuedo property
        $this | Add-Member -Force -Name Name -MemberType ScriptProperty -Value {
            return $this.ControllerName
        }
    }
}

class NetAppClusterObject : NetAppObject
{
    [NetAppCluster] $_cluster

    NetAppClusterObject([NetAppObject] $srcObject, [NetAppCluster] $cluster) : base($srcObject)
    {
        # .Cluster psuedo property
        $this | Add-Member -Name Cluster -MemberType ScriptProperty -Value {
            return $this._cluster
        } -SecondValue {
            param($value)

            if ($null -ne $value)
            {
                $this._cluster = $value
            } `
            else # NOT ($null -ne $value)
            {
                throw "Missing cluster in NetAppClusterObject ctor."
            }
        }

        $this.Cluster = $cluster
    }
}

class NetAppVServer : NetAppClusterObject
{
    NetAppVServer([NetAppCluster] $cluster, [DataONTAP.C.Types.Vserver.VserverInfo] $vServer) : base($vServer, $cluster)
    {
        # .Type psuedo property
        $this | Add-Member -Force -Name Type -MemberType ScriptProperty -Value {
            return $this._sourceObject.VserverType
        }

        if ($cluster.ControllerName -ne $this.ControllerName)
        {
            throw ("Cluster Object mismatch in NetAppVServer ctor.  Cluster controller name: {0}, VServer controller name: {1}" -f @($cluster.ControllerName, $this.ControllerName))
        } `
        else # NOT ($cluster.ControllerName -ne $this.ControllerName)
        {
            # Nothing.
        }
    }
}

class NetAppAggregate : NetAppClusterObject
{
    [Int64] $size
    [Int64] $used
    [Int64] $available

    NetAppAggregate([NetAppCluster] $cluster, [DataONTAP.C.Types.Aggr.AggrAttributes] $aggregate) : base($cluster)
    {
        if($null -ne $aggregate)
        {
            $this.uuid = [System.Guid]::new($aggregate.AggregateUuid)
            $this.name = $aggregate.Name
            $this.size = $aggregate.AggrSpaceAttributes.SizeTotal
            $this.used = $aggregate.AggrSpaceAttributes.SizeUsed
            $this.available = $aggregate.AggrSpaceAttributes.SizeAvailable
        }
        else
        {
            # Missing aggregate
        }
    }
}

class NetAppVolume : NetAppObject
{
    [NetAppVServer] $vServer
    [NetAppAggregate] $aggregate
    [Int64] $size
    [Int64] $used
    [Int64] $available

<#
    NEED TO ADD SNAPLOCKED...
#>

    NetAppVolume([NetAppVServer] $vServer, [NetAppAggregate] $aggregate, [DataONTAP.C.Types.Volume.VolumeAttributes] $volume) : base($volume)
    {
        $this | Add-Member -Name UUID -MemberType ScriptProperty -Value {
            if (($null -ne $this._sourceObject) -and ($null -ne $this._sourceObject.VolumeIdAttributes))
            {
                return $this._sourceObject.VolumeIdAttributes.UUID
            } `
            else # NOT ($null -ne $this._sourceObject)
            {
                return [String]::Empty
            }
        }

        if($null -ne $vServer)
        {
            if($null -ne $aggregate)
            {
                $this.vServer = $vServer
                $this.aggregate = $aggregate
                $this.uuid = [System.Guid]::new($volume.VolumeIdAttributes.Uuid)
                $this.name = $volume.Name
                $this.size = $volume.VolumeSpaceAttributes.Size
                $this.used = $volume.VolumeSpaceAttributes.SizeUsed
                $this.available = $volume.VolumeSpaceAttributes.SizeAvailable
            }
            else
            {
                # Missing aggregate
                throw "Missing aggregate in NetAppVolume"
            }
        }
        else
        {
            # Missing vServer
            throw "Missing vServer in NetAppVolume"
        }
    }
}

class NetAppSnapmirror : DataObject
{
    [NetAppVolume] $source
    [NetAppVolume] $destination

    NetAppSnapmirror([NetAppVolume] $source, [NetAppVolume] $destination) : base()
    {
        if($null -ne $source)
        {
            if($null -ne $destination)
            {
                $this.source = $source
                $this.destination = $destination
            }
            else
            {
                throw "Missing destination in NetAppSnapshot"
            }
        }
        else
        {
            throw "Missing source in NetAppSnapshot"
        }
    }
}

#DataONTAP.C.Types.Snapshot.SnapshotInfo

class NetAppSnapshot : DataObject
{
    [NetAppVolume] $volume
    [System.Nullable[DateTime]] $created
    [System.Nullable[DateTime]] $expiryTime
    [System.Nullable[DateTime]] $snaplockExpiryTime
    [String] $snapmirrorLabel
    [String] $name
    [Int64] $cumulativeTotal
    [Int64] $total

    NetAppSnapshot([NetAppVolume] $volume, [DataONTAP.C.Types.Snapshot.SnapshotInfo] $snapshot) : base()
    {
        if($null -ne $volume)
        {
            if($null -ne $volume)
            {
                $this.volume = $volume
                $this.created = $snapshot.Created
                if($snapshot.ExpiryTimeSpecified -and ($null -ne $snapshot.ExpiryTimeDT))
                {
                    $this.expiryTime = $snapshot.ExpiryTimeDT
                }
                if($snapshot.SnaplockExpiryTimeSpecified -and ($null -ne $snapshot.SnaplockExpiryTimeDT))
                {
                    $this.snaplockExpiryTime = $snapshot.SnaplockExpiryTimeDT
                }

                $this.snapmirrorLabel = $snapshot.SnapmirrorLabel
                $this.name = $snapshot.Name

                if($snapshot.CumulativeTotalSpecified)
                {
                    $this.cumulativeTotal = $snapshot.CumulativeTotal
                }

                if($snapshot.TotalSpecified)
                {
                    $this.total = $snapshot.Total
                }
            }
            else
            {
                throw " missing in NetAppSnapshot"
            }
            }
        else
        {
            throw " missing in NetAppSnapshot"
        }
    }



}

class NetAppShare : DataObject
{
    [NetAppVolume] $volume = $null
    [String] $path = [String]::Empty
    [String] $name = [String]::Empty

    NetAppShare([NetAppVolume] $volume, [DataONTAP.C.Types.Cifs.CifsShare] $share) : base()
    {
        if($null -ne $volume)
        {
            if($null -ne $share)
            {
                $this.volume = $volume
                $this.name = $share.ShareName
                $this.path = $share.Path
            }
            else
            {
                throw "Missing `$share in NetAppShare"
            }
        }
        else
        {
            throw "Missing `$volume in NetAppShare"
        }
    }
}

class VMWareDatastore : DataObject
{
    [NetAppVolume] $volume = $null
    [String] $path = [String]::Empty
    [String] $name = [String]::Empty

    VMWareDatastore([NetAppVolume] $volume, [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl] $datastore) : base()
    {
        if($null -ne $volume)
        {
            if($null -ne $share)
            {
                $this.volume = $volume
                $this.name = $share.ShareName
                $this.path = $share.Path
            }
            else
            {
                throw "Missing `$share in VMWareDatastore"
            }
        }
        else
        {
            throw "Missing `$volume in VMWareDatastore"
        }
    }
}

class VolumeExportRecord : IComparable
{
    [String] $Timestamp
    [String] $VolumeUUID
    [bool] $IsSourceVolume
    [bool] $IsSnaplockProtected
    [String] $SnaplockRetention
    [Int64] $Size
    [Int64] $Used
    [Int64] $Available

    VolumeExportRecord([StorageInformation] $sInfo)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.VolumeUUID = $sInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.IsSnaplockProtected = $sInfo.IsSnaplocked()
        $this.SnaplockRetention = $sInfo.snaplockRetention
        $this.Size = $sInfo.baseVolume.VolumeSpaceAttributes.Size
        $this.Used = $sInfo.baseVolume.VolumeSpaceAttributes.SizeUsed
        $this.Available = $sInfo.baseVolume.VolumeSpaceAttributes.SizeAvailable
        $this.IsSourceVolume = ($sInfo.baseVolume.VolumeMirrorAttributes.IsDataProtectionMirrorSpecified -and (-not $sInfo.baseVolume.VolumeMirrorAttributes.IsDataProtectionMirror)) -and
                               ($sInfo.baseVolume.VolumeMirrorAttributes.IsLoadSharingMirrorSpecified -and (-not $sInfo.baseVolume.VolumeMirrorAttributes.IsLoadSharingMirror)) -and
                               ($sInfo.baseVolume.VolumeMirrorAttributes.IsMoveMirrorSpecified -and (-not $sInfo.baseVolume.VolumeMirrorAttributes.IsMoveMirror)) -and
                               ($sInfo.baseVolume.VolumeMirrorAttributes.IsReplicaVolumeSpecified -and (-not $sInfo.baseVolume.VolumeMirrorAttributes.IsReplicaVolume))
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2,6} {3,10} {4,20} {5,20} {6,20}" -f @($this.Timestamp, $this.VolumeUUID, $this.IsSnaplockProtected, $this.SnaplockRetention, $this.Size, $this.Used, $this.Available)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [VolumeExportRecord] $other = [VolumeExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.VolumeUUID.CompareTo($other.VolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.IsSnaplockProtected.CompareTo($other.IsSnaplockProtected)
                    if($retval -eq 0)
                    {
                        $retval = $this.SnaplockRetention.CompareTo($other.SnaplockRetention)
                        if($retval -eq 0)
                        {
                            $retval = $this.Size.CompareTo($other.Size)
                            if($retval -eq 0)
                            {
                                $retval = $this.Used.CompareTo($other.Used)
                                if($retval -eq 0)
                                {
                                    $retval = $this.Available.CompareTo($other.Available)
                                    if($retval -eq 0)
                                    {
                                        $retval = $this.IsSourceVolume.CompareTo($other.IsSourceVolume)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return $retval
    }
}

class SnapmirrorExportRecord : IComparable
{
    [String] $Timestamp
    [String] $SourceVolumeUUID
    [String] $DestinationVolumeUUID

    SnapmirrorExportRecord([StorageInformation] $sourceVInfo, [StorageInformation] $destinationVInfo)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.SourceVolumeUUID = $sourceVInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.DestinationVolumeUUID = $destinationVInfo.baseVolume.VolumeIdAttributes.Uuid
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2,37}" -f @($this.Timestamp, $this.SourceVolumeUUID, $this.DestinationVolumeUUID)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [SnapmirrorExportRecord] $other = [SnapmirrorExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.SourceVolumeUUID.CompareTo($other.SourceVolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.DestinationVolumeUUID.CompareTo($other.DestinationVolumeUUID)
                }
            }
        }

        return $retval
    }
}

class SnapshotExportRecord : IComparable
{
    [String] $Timestamp
    [String] $VolumeUUID
    [String] $Created
    [String] $ExpiryTime
    [String] $SnaplockExpiryTime
    [String] $SnapmirrorLabel
    [String] $Name
    [Int64] $CumulativeTotal
    [Int64] $Total

    SnapshotExportRecord([StorageInformation] $sInfo, [DataONTAP.C.Types.Snapshot.SnapshotInfo] $snapshot)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.VolumeUUID = $sInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.Created = $snapshot.Created.ToString("u")
        if($snapshot.ExpiryTimeSpecified -and ($null -ne $snapshot.ExpiryTimeDT))
        {
            $this.ExpiryTime = $snapshot.ExpiryTimeDT.ToString("u")
        }
        if($snapshot.SnaplockExpiryTimeSpecified -and ($null -ne $snapshot.SnaplockExpiryTimeDT))
        {
            $this.SnaplockExpiryTime = $snapshot.SnaplockExpiryTimeDT.ToString("u")
        }

        $this.SnapmirrorLabel = $snapshot.SnapmirrorLabel
        $this.Name = $snapshot.Name

        if($snapshot.CumulativeTotalSpecified)
        {
            $this.CumulativeTotal = $snapshot.CumulativeTotal
        }

        if($snapshot.TotalSpecified)
        {
            $this.Total = $snapshot.Total
        }
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2,21} {3,21} {4,21} {5,20} {6,20} {7} {8}" -f @($this.Timestamp, $this.VolumeUUID, $this.Created, $this.ExpiryTime, $this.SnaplockExpiryTime, $this.CumulativeTotal, $this.Total, $this.Name, $this.SnapmirrorLabel)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [SnapshotExportRecord] $other = [SnapshotExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.VolumeUUID.CompareTo($other.VolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.Name.CompareTo($other.Name)
                    if($retval -eq 0)
                    {
                        $retval = $this.Created.CompareTo($other.Created)
                        if($retval -eq 0)
                        {
                            $retval = $this.SnapmirrorLabel.CompareTo($other.SnapmirrorLabel)
                            if($retval -eq 0)
                            {
                                $retval = $this.ExpiryTime.CompareTo($other.ExpiryTime)
                                if($retval -eq 0)
                                {
                                    $retval = $this.SnaplockExpiryTime.CompareTo($other.SnaplockExpiryTime)
                                    if($retval -eq 0)
                                    {
                                        $retval = $this.CumulativeTotal.CompareTo($other.CumulativeTotal)
                                        if($retval -eq 0)
                                        {
                                            $retval = $this.Total.CompareTo($other.Total)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return $retval
    }
}

class ShareExportRecord : IComparable
{
    [String] $Timestamp
    [String] $VolumeUUID
    [String] $Path
    [String] $Name

    ShareExportRecord([StorageInformation] $sInfo, [DataONTAP.C.Types.Cifs.CifsShare] $share)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.VolumeUUID = $sInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.Path = $share.Path
        $this.Name = $share.ShareName
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2} {3}" -f @($this.Timestamp, $this.VolumeUUID, $this.Name, $this.Path)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [ShareExportRecord] $other = [ShareExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.VolumeUUID.CompareTo($other.VolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.Name.CompareTo($other.Name)
                    if($retval -eq 0)
                    {
                        $retval = $this.Path.CompareTo($other.Path)
                    }
                }
            }
        }

        return $retval
    }
}

class DatastoreExportRecord : IComparable
{
    [String] $Timestamp
    [String] $VolumeUUID
    [String] $DatastoreID

    DatastoreExportRecord([StorageInformation] $sInfo, [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl] $datastore)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.VolumeUUID = $sInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.DatastoreID = $datastore.Id
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2}" -f @($this.Timestamp, $this.VolumeUUID, $this.DatastoreID)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [DatastoreExportRecord] $other = [DatastoreExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.VolumeUUID.CompareTo($other.VolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.DatastoreID.CompareTo($other.DatastoreID)
                }
            }
        }

        return $retval
    }
}

class VirtualMachineExportRecord : IComparable
{
    [String] $Timestamp
    [String] $VolumeUUID
    [String] $DatastoreID
    [String] $VMID

    VirtualMachineExportRecord([StorageInformation] $sInfo, [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl] $vm, [VMware.Vim.ManagedObjectReference] $dsReference)
    {
        $this.Timestamp = [StorageInformation]::dataCollectionTimestamp
        $this.VolumeUUID = $sInfo.baseVolume.VolumeIdAttributes.Uuid
        $this.DatastoreID = "{0}-{1}" -f @($dsReference.Type, $dsReference.Value)
        $this.VMID = $vm.Id
    }

    [String] ToString()
    {
        [String] $retval = [String]::Empty

        $retval = "{0,21} {1,37} {2} {3}" -f @($this.Timestamp, $this.VolumeUUID, $this.DatastoreID, $this.VMID)

        return $retval
    }

    [int] CompareTo([Object] $obj)
    {
        [int] $retval = 0

        if($null -eq $obj)
        {
            $retval = 1
        }
        else
        {
            [VirtualMachineExportRecord] $other = [VirtualMachineExportRecord] $obj
            $retval = $this.Timestamp.CompareTo($other.Timestamp)
            if($retval -eq 0)
            {
                $retval = $this.VolumeUUID.CompareTo($other.VolumeUUID)
                if($retval -eq 0)
                {
                    $retval = $this.DatastoreID.CompareTo($other.DatastoreID)
                    if($retval -eq 0)
                    {
                        $retval = $this.VMID.CompareTo($other.VMID)
                    }
                }
            }
        }

        return $retval
    }
}

class ExportData
{
    [System.Collections.Generic.List[VolumeExportRecord]] $volumeData = $null
    [System.Collections.Generic.List[SnapmirrorExportRecord]] $snapmirrorData = $null
    [System.Collections.Generic.List[SnapshotExportRecord]] $snapshotData = $null
    [System.Collections.Generic.List[ShareExportRecord]] $shareData = $null
    [System.Collections.Generic.List[DatastoreExportRecord]] $datastoreData = $null
    [System.Collections.Generic.List[VirtualMachineExportRecord]] $vmData = $null

    ExportData()
    {
        $this.volumeData = [System.Collections.Generic.List[VolumeExportRecord]]::new()
        $this.snapmirrorData = [System.Collections.Generic.List[SnapmirrorExportRecord]]::new()
        $this.snapshotData = [System.Collections.Generic.List[SnapshotExportRecord]]::new()
        $this.shareData = [System.Collections.Generic.List[ShareExportRecord]]::new()
        $this.datastoreData = [System.Collections.Generic.List[DatastoreExportRecord]]::new()
        $this.vmData = [System.Collections.Generic.List[VirtualMachineExportRecord]]::new()
    }
}

class StorageInformation
{
    <#
        It is my intention to track usage data with this script.  To do so, I need some way to track a "run" -- a single data collection
        event.  This is not the most accurate system though, because collecting the data is a sequencial activity, one cluster at a time.
        Even within a single cluster, collecting VServer data, aggregate data, volume data, etc... Each of these data points are collected
        in sequence.  Aggregate data is accurate when it is collected, as is volume data.  However, the clusters are ever changing, so by
        the time volume data is collected, used/available, etc may not accurately represent the numbers reported by the parent aggregate.

        However, for my purposes, it's close enough.  I just want to be able to have a way to track statistics over time.

        The script will export data in 2 phases.

        Phase 1: Export static data: long lived attributes
            Clusters:
                UUID, Name

            VServers:
                UUID, Cluster.UUID, Name

            Aggregates:
                UUID, Cluster.UUID, Name

            Volumes:
                UUID, VServer.UUID, Aggregate.UUID, Name

            Datastores:
                ID, Name

            VMs:
                ID, Name

        Phase 2: Export point in time data: short lived attributes, aggregate size, what VMs are on a datastore, etc...
            AggregateData: (Aggregate statistics at Timestamp)
                Timestamp, Aggregate.UUID, Size, Used, Available

            VolumeData: (Volume statistics at Timestamp)
                Timestamp, Volume.UUID, Snaplocked, Size, Used, Available

            SnapMirrorData: (Snapmirrors that existed at Timestamp)
                Timestamp, SourceVolume.UUID, DestinationVolume.UUID

            ShareData:  (Shares that existed at Timestamp)
                Timestamp, Volume.UUID, SharePath, ShareName

            DatastoreData: (Datastores that existed at Timestamp)
                Timestamp, Volume.UUID, Datastore.ID

            VMData: (VMs that existed at Timestamp)
                Timestamp, Datastore.ID, VM.ID

        Some static point in time data can be exported during phase 1 since it is available then and not altered by later instantiations of the
        class.  For instance, aggregate usage information is know when aggregate data is collected and is never changed, therefore, it can be
        exported in phase 1.  However, even though volume space usage information is known when all volume data is collected from the cluster
        it cannot be exported in phase 1, since later processing is used to correlate shares, datastores, etc with volumes.
    #>

    # Static members where storage information is collected from
    #   Array of NetApp Cluster Mode controller to query
    static [NetApp.Ontapi.Filer.C.NcController[]] $controllers

    #   Array of VMware vCenter servers to query
    static [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl[]] $vcenters

    # The time static data attributes are populated.  This property is used to relate all point in time data to a single "run"
    static [String] $dataCollectionTimestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")

    # Static data pertaining to NetApp filers
    static [System.Collections.Generic.List[DataONTAP.C.Types.Cluster.ClusterIdentityInfo]] $clusters = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Vserver.VserverInfo]] $vServers = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Aggr.AggrAttributes]] $aggregates = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Volume.VolumeAttributes]] $volumes = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]] $snapmirrors = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]] $shares = $null
    static [System.Collections.Generic.List[DataONTAP.C.Types.Net.NetInterfaceInfo]] $cdotLIFS = $null

    # Static data pertaining to VMware
    static [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]] $nfsDatastores = $null
    static [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]] $virtualMachines = $null

    # Static storage information...
    static [System.Collections.Generic.List[StorageInformation]] $storageInfo = $null

    [DataONTAP.C.Types.Volume.VolumeAttributes] $baseVolume = $null
    [System.Collections.Generic.List[StorageInformation]] $snapmirrorDestinationVolumes = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Snapshot.SnapshotInfo]] $snapshots = $null
    [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]] $volumeShares = $null
    [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]] $volumeDatastores = $null
    [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]] $volumeVMs = $null
    [System.String] $snaplockRetention = [String]::Empty

    static [void] Reset()
    {
        [StorageInformation]::aggregates = $null
        [StorageInformation]::clusters = $null
        [StorageInformation]::snapmirrors = $null
        [StorageInformation]::vServers = $null
        [StorageInformation]::volumes = $null
        [StorageInformation]::shares = $null
        [StorageInformation]::cdotLIFS = $null
        [StorageInformation]::nfsDatastores = $null
        [StorageInformation]::virtualMachines = $null
    }

    static [void] InitStaticMembers()
    {
        # Make sure we have values for [StorageInformation]::controllers and [StorageInformation]::vcenters...
        if(($null -ne [StorageInformation]::controllers) -and ([StorageInformation]::controllers.Length -gt 0) -and ($null -ne [StorageInformation]::vcenters) -and ([StorageInformation]::vcenters.Length -gt 0))
        {
            # Set the data collection timestamp
            [StorageInformation]::dataCollectionTimestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")

            if($null -eq [StorageInformation]::clusters)
            {
Write-Host "Getting Clusters..."
                Get-NcCluster -Controller @([StorageInformation]::controllers) | Foreach-Object {

                    # Create [StorageInformation]::clusters if it has not already been created.
                    if($null -eq [StorageInformation]::clusters)
                    {
                        [StorageInformation]::clusters = [System.Collections.Generic.List[DataONTAP.C.Types.Cluster.ClusterIdentityInfo]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::clusters
                    }
Write-Host ("`tAdding cluster {0}" -f @($_.ClusterName))
                    [StorageInformation]::clusters.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::clusters has already been initialized.
            }

            if($null -eq [StorageInformation]::aggregates)
            {
Write-Host "Getting Aggregates..."
                Get-NcAggr -Controller @([StorageInformation]::controllers) | Foreach-Object {

                    # Create [StorageInformation]::aggregates if it has not already been created.
                    if($null -eq [StorageInformation]::aggregates)
                    {
                        [StorageInformation]::aggregates = [System.Collections.Generic.List[DataONTAP.C.Types.Aggr.AggrAttributes]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::aggregates
                    }
Write-Host ("`tAdding aggregate {0}" -f @($_.Name))
                    [StorageInformation]::aggregates.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::aggregates has already been initialized.
            }

            if($null -eq [StorageInformation]::snapmirrors)
            {
Write-Host "Getting snapmirrors..."
                Get-NcSnapmirror -Controller @([StorageInformation]::controllers) | Foreach-Object {

                    # Create [StorageInformation]::snapmirrors if it has not already been created.
                    if($null -eq [StorageInformation]::snapmirrors)
                    {
                        [StorageInformation]::snapmirrors = [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::snapmirrors
                    }
Write-Host ("`tAdding snapmirror {0} ==> {1}" -f @($_.SourceLocation, $_.DestinationLocation))
                    [StorageInformation]::snapmirrors.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::snapmirrors has already been initialized.
            }

            if($null -eq [StorageInformation]::vServers)
            {
Write-Host "Getting vServers..."
                Get-NcVserver -Controller @([StorageInformation]::controllers) | ForEach-Object {

                    # Create [StorageInformation]::vServers if it has not already been created.
                    if($null -eq [StorageInformation]::vServers)
                    {
                        [StorageInformation]::vServers = [System.Collections.Generic.List[DataONTAP.C.Types.Vserver.VserverInfo]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::vServers
                    }

Write-Host ("`tAdding vServer {0}" -f @($_.VserverName))
                    [StorageInformation]::vServers.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::vServers has already been initialized.
            }

            if($null -eq [StorageInformation]::volumes)
            {
Write-Host "Getting volumes..."
                Get-NcVol -Controller @([StorageInformation]::controllers) | Foreach-Object {

                    # Create [StorageInformation]::volumes if it has not already been created.
                    if($null -eq [StorageInformation]::volumes)
                    {
                        [StorageInformation]::volumes = [System.Collections.Generic.List[DataONTAP.C.Types.Volume.VolumeAttributes]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::volumes
                    }
Write-Host ("`tAdding {0}:{1}:{2}" -f @($_.NcController.Name, $_.Vserver, $_.Name))
                    [StorageInformation]::volumes.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::volumes has already been initialized.
            }

            if($null -eq [StorageInformation]::shares)
            {
Write-Host "Getting shares..."
                Get-NcCifsShare -Controller @([StorageInformation]::controllers) | Foreach-Object {

                    # Create [StorageInformation]::shares if it has not already been created.
                    if($null -eq [StorageInformation]::shares)
                    {
                        [StorageInformation]::shares = [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::shares
                    }
                    # Ignore shares on volumes that start with ROOT_ or JP_.
                    if((-not [String]::IsNullOrEmpty($_.Volume)) -and (-not ($_.Volume.StartsWith("ROOT_") -or $_.Volume.StartsWith("JP_"))))
                    {
Write-Host ("`tAdding share \\{0}\{1} ==> {2}" -f @($_.CifsServer, $_.ShareName, $_.Path))
                        [StorageInformation]::shares.Add($_)
                    }
                }
            }
            else
            {
                # Nothing, [StorageInformation]::shares has already been initialized.
            }

            if($null -eq [StorageInformation]::cdotLIFS)
            {
Write-Host "Getting CDOT NFS LIFs..."
                Get-NcNetInterface -Controller @([StorageInformation]::controllers) -DataProtocols "nfs" | Foreach-Object {

                    # Create [StorageInformation]::cdotLIFS if it has not already been created.
                    if($null -eq [StorageInformation]::cdotLIFS)
                    {
                        [StorageInformation]::cdotLIFS = [System.Collections.Generic.List[DataONTAP.C.Types.Net.NetInterfaceInfo]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::cdotLIFS
                    }
Write-Host ("`tAdding NFS LIF {0}:{1}" -f @($_.InterfaceName, $_.Address))
                        [StorageInformation]::cdotLIFS.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::cdotLIFS has already been initialized.
            }

            if($null -eq [StorageInformation]::nfsDatastores)
            {
Write-Host "Getting VMware NFS datastores..."
                Get-Datastore -Server @([StorageInformation]::vcenters) | Where-Object {
                    $_.Type -eq "NFS"
                } | ForEach-Object {
                    # Create [StorageInformation]::nfsDatastores if it has not already been created.
                    if($null -eq [StorageInformation]::nfsDatastores)
                    {
                        [StorageInformation]::nfsDatastores = [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::nfsDatastores
                    }
Write-Host ("`tAdding NFS datastore {0}" -f @($_.Name))
                        [StorageInformation]::nfsDatastores.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::nfsDatastores has already been initialized.
            }

            if($null -eq [StorageInformation]::virtualMachines)
            {
Write-Host "Getting VMware virtual machines..."
                Get-VM -Server @([StorageInformation]::vcenters) | ForEach-Object {
                    # Create [StorageInformation]::virtualMachines if it has not already been created.
                    if($null -eq [StorageInformation]::virtualMachines)
                    {
                        [StorageInformation]::virtualMachines = [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]]::new()
                    }
                    else
                    {
                        # Nothing, already created [StorageInformation]::virtualMachines
                    }
Write-Host ("`tAdding virtual machine {0}" -f @($_.Name))
                        [StorageInformation]::virtualMachines.Add($_)
                }
            }
            else
            {
                # Nothing, [StorageInformation]::virtualMachines has already been initialized.
            }
        }
        else
        {
            $errMsg = [System.Text.StringBuilder]::new()
            if(($null -eq [StorageInformation]::controllers) -or ([StorageInformation]::controllers.Length -eq 0))
            {
                [void] $errMsg.AppendLine("No cluster controllers provided in InitStaticMembers.")
            }

            if(($null -eq [StorageInformation]::vcenters) -or ([StorageInformation]::vcenters.Length -eq 0))
            {
                [void] $errMsg.AppendLine("No vCenter servers provided in InitStaticMembers.")
            }

            Write-Error $errMsg.ToString()
        }
    }

    static [DataONTAP.C.Types.Volume.VolumeAttributes] GetSnapmirrorSourceVolume([DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $snapInfo)
    {
        [DataONTAP.C.Types.Volume.VolumeAttributes] $snapmirrorVolume = $null

        # Make sure static members are initialized.
        [StorageInformation]::InitStaticMembers()

        if($null -ne $snapInfo)
        {
            # [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] seems to provide the source/destination cluster name or
            #   the source/destination vserver UUID.  The source/destination vserver name is always available, but to
            #   handle potential duplicate vserver names, I do not want to rely on JUST the vserver name.
            #
            #   So, if there is no SourceVserverUUID, then SourceCluster and SourceVserver must match
            $snapVServer = @([StorageInformation]::vServers | Where-Object {
                ($_.Uuid -eq $snapInfo.SourceVserverUuid) -or
                (($_.VserverName -eq $snapInfo.SourceVserver) -and
                 ($_.NcController.Name -eq $snapInfo.SourceCluster)) })

            if($snapVServer.Length -eq 1)
            {
                $snapmirrorVolume = [StorageInformation]::volumes | Where-Object { ($_.NCController.Name -eq $snapVServer[0].NCController.Name) -and ($_.Vserver -eq $snapVServer[0].VServerName) -and ($_.Name -eq $snapInfo.SourceVolume) }
            }
            elseif($snapVServer.Length -eq 0)
            {
                throw "No vServer found for:`r`n`tSourceCluster: {0}`r`n`tSourceVserver: {1}`r`n`tSourceVserverUUID: {2}" -f @($snapInfo.SourceCluster, $snapInfo.SourceVserver, $snapInfo.SourceVserverUuid)
            }
            else
            {
                throw "Multiple vServers found for:`r`n`tSourceCluster: {0}`r`n`tSourceVserver: {1}`r`n`tSourceVserverUUID: {2}" -f @($snapInfo.SourceCluster, $snapInfo.SourceVserver, $snapInfo.SourceVserverUuid)
            }
        }
        else
        {
            # Nothing, no $snapInfo, no snapmirror source.
        }

        return $snapmirrorVolume
    }

    static [DataONTAP.C.Types.Volume.VolumeAttributes] GetSnapmirrorDestinationVolume([DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $snapInfo)
    {
        [DataONTAP.C.Types.Volume.VolumeAttributes] $snapmirrorVolume = $null

        # Make sure static members are initialized.
        [StorageInformation]::InitStaticMembers()

        if($null -ne $snapInfo)
        {
            # [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] seems to provide the source/destination cluster name or
            #   the source/destination vserver UUID.  The source/destination vserver name is always available, but to
            #   handle potential duplicate vserver names, I do not want to rely on JUST the vserver name.
            #
            #   So, if there is no SourceVserverUUID, then SourceCluster and SourceVserver must match
            $snapVServer = @([StorageInformation]::vServers | Where-Object {
                ($_.Uuid -eq $snapInfo.DestinationVserverUuid) -or
                (($_.VserverName -eq $snapInfo.DestinationVserver) -and
                 ($_.NcController.Name -eq $snapInfo.DestinationCluster)) })

            if($snapVServer.Length -eq 1)
            {
                $snapmirrorVolume = [StorageInformation]::volumes | Where-Object { ($_.NCController.Name -eq $snapVServer[0].NCController.Name) -and ($_.Vserver -eq $snapVServer[0].VServerName) -and ($_.Name -eq $snapInfo.DestinationVolume) }
            }
            elseif($snapVServer.Length -eq 0)
            {
                throw "No vServer found for:`r`n`tDestinationCluster: {0}`r`n`tDestinationVserver: {1}`r`n`tDestinationVserverUUID: {2}" -f @($snapInfo.DestinationCluster, $snapInfo.DestinationVserver, $snapInfo.DestinationVserverUuid)
            }
            else
            {
                throw "Multiple vServers found for:`r`n`tDestinationCluster: {0}`r`n`tDestinationVserver: {1}`r`n`tDestinationVserverUUID: {2}" -f @($snapInfo.DestinationCluster, $snapInfo.DestinationVserver, $snapInfo.DestinationVserverUuid)
            }
        }
        else
        {
            # Nothing, no $snapInfo, no snapmirror destination.
        }

        return $snapmirrorVolume
    }

    static [DataONTAP.C.Types.Cluster.ClusterIdentityInfo] GetClusterByNCController([NetApp.Ontapi.Filer.C.NcController] $ncController)
    {
        $matchingClusters = @([StorageInformation]::clusters | Where-Object {
            ($ncController.Name -eq $_.NcController.Name) -and
            ($ncController.Address -eq $_.NcController.Address) -and
            ($ncController.Ontapi -eq $_.NcController.Ontapi) -and
            ($ncController.Version -eq $_.NcController.Version)
        })

        if($matchingClusters.Length -gt 1)
        {
            $sb = [System.Text.StringBuilder]::new()
            [void] $sb.AppendLine("EXCEPTION: Multiple cluster found for NC Controller: {0}" -f @($ncController.Name))
            foreach($nc in $matchingClusters)
            {
                [void] $sb.AppendLine("`t{0}, {1}" -f @($nc.ClusterName, $nc.ClusterUuid))
            }
            Write-Host $sb.ToString()
        }

        $retval = $null
        if($matchingClusters.Length -gt 0)
        {
            $retval = $matchingClusters[0]
        }

        return $retval
    }

    static [void] ExportStaticData([String] $exportFolder)
    {
        if((-not [String]::IsNullOrEmpty($exportFolder)) -and ([System.IO.Directory]::Exists($exportFolder)))
        {
            # Make sure $exportFolder does not end with a "\"
            $exportFolder = $exportFolder.TrimEnd("\")

            $clustersCSV = "{0}\{1}_clusters.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $vServersCSV = "{0}\{1}_vServers.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $aggregatesCSV = "{0}\{1}_aggregates.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $aggregateDataCSV = "{0}\{1}_aggregateData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $volumesCSV = "{0}\{1}_volumes.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $datastoresCSV = "{0}\{1}_datastores.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)
            $virtualMachinesCSV = "{0}\{1}_virtualMachines.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)

            if($null -ne [StorageInformation]::clusters)
            {
                [StorageInformation]::clusters | Select-Object @{N="UUID";E={$_.ClusterUuid}},@{N="Name";E={$_.ClusterName}} | Export-CSV -Delimiter "," -NoTypeInformation -Path $clustersCSV -Force
            }

            if($null -ne [StorageInformation]::vServers)
            {
                [StorageInformation]::vServers | ForEach-Object {
                    $vServerCluster = [StorageInformation]::GetClusterByNCController($_.NcController)

                    if($null -ne $vServerCluster)
                    {
                        $d = "" | Select-Object UUID, ClusterUUID, Name

                        $d.UUID = $_.Uuid
                        $d.ClusterUUID = $vServerCluster.ClusterUuid
                        $d.Name = $_.VserverName

                        $d
                    }
                    else
                    {
                        Write-Error ("No cluster found for vServer: {0}" -f @($_.VserverName))
                    }
                } | Export-CSV -Delimiter "," -NoTypeInformation -Path $vServersCSV -Force
            }

            if($null -ne [StorageInformation]::aggregates)
            {
                [StorageInformation]::aggregates | ForEach-Object {
                    $aggrCluster = [StorageInformation]::GetClusterByNCController($_.NcController)
                    if($null -ne $aggrCluster)
                    {
                        $d = "" | Select-Object UUID, ClusterUUID, Name

                        $d.UUID = $_.AggregateUuid
                        $d.ClusterUUID = $aggrCluster.ClusterUuid
                        $d.Name = $_.Name

                        $d
                    }
                    else
                    {
                        Write-Host ("No cluster found for aggregate: {0}" -f @($_.Name))
                    }
                } | Export-CSV -Delimiter "," -NoTypeInformation -Path $aggregatesCSV -Force
            }

            if($null -ne [StorageInformation]::aggregates)
            {
                [StorageInformation]::aggregates | ForEach-Object {
                    $d = "" | Select-Object Timestamp, AggregateUUID, Size, Used, Available

                    $d.Timestamp = [StorageInformation]::dataCollectionTimestamp
                    $d.AggregateUUID = $_.AggregateUuid
                    $d.Size = $_.AggrSpaceAttributes.SizeTotal
                    $d.Used = $_.AggrSpaceAttributes.SizeUsed
                    $d.Available = $_.AggrSpaceAttributes.SizeAvailable

                    $d
                } | Export-CSV -Delimiter "," -NoTypeInformation -Path $aggregateDataCSV -Force
            }

            if($null -ne [StorageInformation]::volumes)
            {
                @(foreach($volume in [StorageInformation]::volumes) {
                    $volumeCluster = [StorageInformation]::GetClusterByNCController($volume.NcController)
                    if($null -ne $volumeCluster)
                    {
                        $volumeAggrs = @([StorageInformation]::aggregates | Where-Object {
                            $aggrCluster = [StorageInformation]::GetClusterByNCController($_.NcController)
                            ($null -ne $aggrCluster) -and
                            ($aggrCluster.ClusterUuid -eq $volumeCluster.ClusterUuid) -and
                            ($_.Name -eq $volume.Aggregate)
                        })

                        if($volumeAggrs.Length -eq 1)
                        {
                            $d = "" | Select-Object UUID, VServerUUID, AggregateUUID, Name
                            $d.UUID = $volume.VolumeIdAttributes.Uuid
                            $d.VServerUUID = $volume.VolumeIdAttributes.OwningVserverUuid
                            $d.AggregateUUID = $volumeAggrs[0].AggregateUuid
                            $d.Name = $volume.Name

                            $d
                        }
                        else
                        {
                            Write-Error ("{0} aggregates found for volume: {1}." -f @($volumeAggrs.Length, $volume.Name))
                        }
                    }
                }) | Export-CSV -Delimiter "," -NoTypeInformation -Path $volumesCSV -Force
            }

            if($null -ne [StorageInformation]::nfsDatastores)
            {
                [StorageInformation]::nfsDatastores | Select-Object ID,Name | Export-CSV -Delimiter "," -NoTypeInformation -Path $datastoresCSV -Force
            }

            if($null -ne [StorageInformation]::virtualMachines)
            {
                [StorageInformation]::virtualMachines | Select-Object ID,Name | Export-CSV -Delimiter "," -NoTypeInformation -Path $virtualMachinesCSV -Force
            }
        }
        else
        {
            if([String]::IsNullOrEmpty($exportFolder))
            {
                Write-Error "Export folder not specified."
            }
            else
            {
                Write-Error ("Export folder {0} not found." -f @($exportFolder))
            }
        }
    }

    static [void] Collect([NetApp.Ontapi.Filer.C.NcController[]] $controllers, [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl[]] $vcenters)
    {
        if($null -ne $controllers)
        {
            if($controllers -is [Array])
            {
                [StorageInformation]::controllers = $controllers
            }
            elseif($controllers -is [NetApp.Ontapi.Filer.C.NcController])
            {
                [StorageInformation]::controllers = @($controllers)
            }
            else
            {
                Write-Error ("Parameter `$controllers in not of type [NetApp.Ontapi.Filer.C.NcController] or [NetApp.Ontapi.Filer.C.NcController[]].")
            }
        }
        else
        {
            Write-Error ("Parameter `$controllers in missing.")
        }

        if($null -ne $vcenters)
        {
            if($controllers -is [Array])
            {
                [StorageInformation]::vcenters = $vcenters
            }
            elseif($vcenters -is [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl])
            {
                [StorageInformation]::vcenters = @($vcenters)
            }
            else
            {
                Write-Error ("Parameter `$vcenters in not of type [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] or [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl[]].")
            }
        }
        else
        {
            Write-Error ("Parameter `$vcenters in missing.")
        }

        # Make sure we have values for [StorageInformation]::controllers and [StorageInformation]::vcenters...
        if(($null -ne [StorageInformation]::controllers) -and ([StorageInformation]::controllers.Length -gt 0) -and ($null -ne [StorageInformation]::vcenters) -and ([StorageInformation]::vcenters.Length -gt 0))
        {
            # Initialize static members
            [StorageInformation]::InitStaticMembers()

            # Static property to contain all correlated storage data...
            [StorageInformation]::storageInfo = [System.Collections.Generic.List[StorageInformation]]::new()

            # Collect data for each NetApp volume considered a source, user volume
            [StorageInformation]::volumes | Where-Object {
                # Don't care about volumes used as junction paths
                (-not $_.Name.StartsWith("JP_")) -and
                # Don't care about vServer root volumes
                (-not $_.VolumeStateAttributes.IsVserverRoot) -and
                # Don't care about node root volumes
                (-not $_.VolumeStateAttributes.IsNodeRoot) -and
                # These will get picked up as snapmirror/snapvault destinations
                (-not $_.VolumeMirrorAttributes.IsDataProtectionMirror) } | ForEach-Object {
                    # Create a new [StorageInformation] instance for the source volume and add it to [StorageInformation]::storageInfo
                    $si = [StorageInformation]::new($_)
                    [StorageInformation]::storageInfo.Add($si)
                }
        }
    }

    StorageInformation([DataONTAP.C.Types.Volume.VolumeAttributes] $volume)
    {
        # Make sure static members are initialized.
        [StorageInformation]::InitStaticMembers()

        if($null -ne $volume)
        {
            $this.baseVolume = $volume
Write-Host ("`r`nProcessing: {0}:{1}:{2}..." -f @($this.baseVolume.NcController.Name, $this.baseVolume.Vserver, $this.baseVolume.Name))

            # Populate snapmirror destinations
            $this.InitializeSnapmirrorDestinations()

            # Populate snapshots
            $this.InitializeSnapshots()

            # Populate shares
            $this.InitializeShares()

            # Populate volumeDatastores first so we can use it to initialize volumeVMs
            $this.InitiailizeDatastores()

            # Populate VM Data
            $this.InitializeVirtualMachines()

            if(($null -ne $this.baseVolume.VolumeSnaplockAttributes) -and ($this.baseVolume.VolumeSnaplockAttributes.SnaplockType -ne "non_snaplock"))
            {
                $snaplockAttr = Get-NcSnaplockVolAttr -Controller $this.baseVolume.NcController -VserverContext $this.baseVolume.Vserver -Volume $this.baseVolume.Name
                switch($snaplockAttr.DefaultRetentionPeriod)
                {
                    "min" { $this.snaplockRetention = $snaplockAttr.MinimumRetentionPeriod }
                    "max" { $this.snaplockRetention = $snaplockAttr.MaximumRetentionPeriod }
                    default { $this.snaplockRetention = $snaplockAttr.DefaultRetentionPeriod }
                }
            }
            else
            {
                # Nothing, the base volume is not a snaplock volume.
            }

        }
        else
        {
            throw "Null volume specified in StorageInformation"
        }
    }

    [void] InitializeSnapmirrorDestinations()
    {
        # Populate $this.snapmirrorDestinationVolumes
        $this.snapmirrorDestinationVolumes = [System.Collections.Generic.List[StorageInformation]]::new()

        [StorageInformation]::snapMirrors | Where-Object {
            ((($_.SourceCluster -eq $this.baseVolume.NcController.Name) -and ($_.SourceVserver -eq $this.baseVolume.Vserver)) -or ($_.SourceVserverUUID -eq $this.baseVolume.VolumeIdAttributes.OwningVserverUuid)) -and
                ($_.SourceVolume -eq $this.baseVolume.Name)
        } | ForEach-Object {
            $smdv = [StorageInformation]::GetSnapmirrorDestinationVolume($_)
Write-Host ("`t+snapmirror destination volume: {0}:{1}:{2}" -f @($smdv.NcController.Name, $smdv.Vserver, $smdv.Name))
            $smdvVI = [StorageInformation]::new($smdv)
            $this.snapmirrorDestinationVolumes.Add($smdvVI)
        }
    }

    [void] InitializeSnapshots()
    {
        # Get all the snapshots for the volume
        $this.snapshots = [System.Collections.Generic.List[DataONTAP.C.Types.Snapshot.SnapshotInfo]]::new()
        Get-NcSnapshot -Controller $this.baseVolume.NcController -Volume $this.baseVolume | ForEach-Object {
            $this.snapshots.Add($_)
        }
Write-Host ("`t+{0} snapshots" -f @($this.snapshots.Count))
    }

    [void] InitializeShares()
    {
        # Get all the shares that are hosted on this volume
        $this.volumeShares = [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsShare]]::new()
        [StorageInformation]::shares | Where-Object {
            ($this.baseVolume.Name -eq $_.Volume) -and ($this.baseVolume.NcController.Name -eq $_.NcController.Name) -and ($this.baseVolume.Vserver -eq $_.Vserver)
        } | ForEach-Object {
Write-Host ("`t+Share: \\{0}\{1}  [{2}]" -f @($_.CifsServer, $_.ShareName, $_.Path))
            $this.volumeShares.Add($_)
        }
    }

    [void] InitiailizeDatastores()
    {
        $this.volumeDatastores = [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]::new()

        # Get a list of NFS LIFs for this volume's VServer.
        $nfsLIFs = @([StorageInformation]::cdotLIFS | Where-Object { ($_.DataProtocols -contains "nfs") -and ($_.Vserver -eq $this.baseVolume.Vserver) -and ($_.NcController.Name -eq $this.baseVolume.NcController.Name) })

        $a = 0
        while($a -lt [StorageInformation]::nfsDatastores.Count)
        {
            $b = 0
            while($b -lt $nfsLIFs.Length)
            {
                if(([StorageInformation]::nfsDatastores[$a].RemoteHost -contains $nfsLIFs[$b].Address) -and ([StorageInformation]::nfsDatastores[$a].RemotePath -eq $this.baseVolume.JunctionPath))
                {
                    $this.volumeDatastores.Add([StorageInformation]::nfsDatastores[$a])
Write-Host ("`t+ VM Datastore: {0}" -f @([StorageInformation]::nfsDatastores[$a].Name))
                }
                $b++
            }
            $a++
        }
    }

    [void] InitializeVirtualMachines()
    {
        $this.volumeVMs = [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]]::new()

        $a = 0
        while($a -lt $this.volumeDatastores.Count)
        {
            $b = 0
            while($b -lt $this.volumeDatastores[$a].ExtensionData.VM.Count)
            {
                $vmID = "{0}-{1}" -f @($this.volumeDatastores[$a].ExtensionData.VM[$b].Type, $this.volumeDatastores[$a].ExtensionData.VM[$b].Value)
                if(@($this.volumeVMs | Where-Object { $_.id -eq $vmID }).Length -eq 0)
                {
                    $vms = @([StorageInformation]::virtualMachines | Where-Object { $_.id -eq $vmID })
                    $c = 0
                    while($c -lt $vms.Length)
                    {
                        $this.volumeVMs.Add($vms[$c])
Write-Host ("`t+ VM: {0} [{1}]" -f @($vms[$c].Name, $vms[$c].PowerState))
                        $c++
                    }
                }

                $b++
            }
            $a++
        }
    }
<#
    Get a list of volumes including this volume or any of its snapmirror destinations that are snaplock volumes.
#>
    [System.Collections.Generic.List[StorageInformation]] GetSnaplockVolumes()
    {
        $snaplockVolumes = [System.Collections.Generic.List[StorageInformation]]::new()

        if($null -ne $this.baseVolume)
        {
            # See if the base volume is a snaplocked volume.  Remember, this function recursively calls itself to determine
            #   if snapmirror destinations are snaplocked volumes, so the destination will, themselves be the base volume.
            if(($null -ne $this.baseVolume.VolumeSnaplockAttributes) -and ($this.baseVolume.VolumeSnaplockAttributes.SnaplockType -ne "non_snaplock"))
            {
                $snaplockVolumes.Add($this)
            }
            else
            {
                # Nothing, the base volume is not a snaplock volume.
            }
            # Enumerate snapmirror destinations until a snaplock volumes is found or all destinations have been checked.
            $a = 0
            while($a -lt $this.snapmirrorDestinationVolumes.Count)
            {
                # Get all the snaplock volumes for this snapmirror destination
                $slvs = $this.snapmirrorDestinationVolumes[$a].GetSnaplockVolumes()
                if($null -ne $slvs)
                {
                    $slvs | Foreach-Object {
                        $tVol = $_

                        # Make sure we only add unique snaplock volumes to the list
                        if(@($snaplockVolumes | Where-Object { $_.baseVolume.VolumeIdAttributes.UUID -eq $tVol.VolumeIdAttributes.UUID }).Length -eq 0)
                        {
                            $snaplockVolumes.Add($tVol)
                        }
                        else
                        {
                            # Nothing, duplicate volume
                        }
                    }
                }
                else
                {
                    # Nothing, no snaplock volumes for this snapmirror destination volume
                }

                $a++
            }
        }
        else
        {
            # Nothing, there is no base volume, so there can be no snapmirror destination or snaplock attributes to check.
        }

        return $snaplockVolumes
    }

    [bool] IsSnaplocked()
    {
        $slVols = $this.GetSnaplockVolumes()

        return ($null -ne $slVols) -and ($slVols.Count -gt 0)
    }

    [ExportData] ExportToCSV()
    {
        $exportData = [ExportData]::new()

        if($null -ne $this.baseVolume)
        {
            $d = [VolumeExportRecord]::new($this)

            $i = $exportData.volumeData.BinarySearch($d)
            if($i -lt 0)
            {
                $exportData.volumeData.Insert(-bnot $i, $d)
            }
        }

        if($null -ne $this.snapshots)
        {
            $a = 0
            while($a -lt $this.snapshots.Count)
            {
                $d = [SnapshotExportRecord]::new($this, $this.snapshots[$a])

                $i = $exportData.snapshotData.BinarySearch($d)
                if($i -lt 0)
                {
                    $exportData.snapshotData.Insert(-bnot $i, $d)
                }

                $a++
            }
        }

        if($null -ne $this.volumeShares)
        {
            $a = 0
            while($a -lt $this.volumeShares.Count)
            {
                $d = [ShareExportRecord]::new($this, $this.volumeShares[$a])

                $i = $exportData.shareData.BinarySearch($d)
                if($i -lt 0)
                {
                    $exportData.shareData.Insert(-bnot $i, $d)
                }
                $a++
            }
        }

        if($null -ne $this.volumeDatastores)
        {
            $a = 0
            while($a -lt $this.volumeDatastores.Count)
            {
                $d = [DatastoreExportRecord]::new($this, $this.volumeDatastores[$a])

                $i = $exportData.datastoreData.BinarySearch($d)
                if($i -lt 0)
                {
                    $exportData.datastoreData.Insert(-bnot $i, $d)
                }
                $a++
            }
        }

        if($null -ne $this.volumeVMs)
        {
            $a = 0
            while($a -lt $this.volumeVMs.Count)
            {
                $b = 0
                while($b -lt $this.volumeVMs[$a].ExtensionData.Datastore.Count)
                {
                    $d = [VirtualMachineExportRecord]::new($this, $this.volumeVMs[$a], $this.volumeVMs[$a].ExtensionData.Datastore[$b])

                    $i = $exportData.vmData.BinarySearch($d)
                    if($i -lt 0)
                    {
                        $exportData.vmData.Insert(-bnot $i, $d)
                    }

                    $b++
                }

                $a++
            }
        }

        if($null -ne $this.snapmirrorDestinationVolumes)
        {
            $a = 0
            while($a -lt $this.snapmirrorDestinationVolumes.Count)
            {
                $d = [SnapmirrorExportRecord]::new($this, $this.snapmirrorDestinationVolumes[$a])

                $i = $exportData.snapmirrorData.BinarySearch($d)
                if($i -lt 0)
                {
                    $exportData.snapmirrorData.Insert(-bnot $i, $d)
                }

                # Get the child export data
                $childExportData = $this.snapmirrorDestinationVolumes[$a].ExportToCSV()

                # VolumeData, SnapmirrorData, SnapshotData, ShareData, DatastoreData, VMData
                # Merge child export data to parent export data

                # Merge volume export data
                $childExportData.volumeData | ForEach-Object {
                    $i = $exportData.volumeData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.volumeData.Insert(-bnot $i, $_)
                    }
                }

                # Merge snapmirror export data
                $childExportData.snapmirrorData | ForEach-Object {
                    $i = $exportData.snapmirrorData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.snapmirrorData.Insert(-bnot $i, $_)
                    }
                }

                # Merge snapshot export data
                $childExportData.snapshotData | ForEach-Object {
                    $i = $exportData.snapshotData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.snapshotData.Insert(-bnot $i, $_)
                    }
                }

                # Merge share export data
                $childExportData.shareData | ForEach-Object {
                    $i = $exportData.shareData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.shareData.Insert(-bnot $i, $_)
                    }
                }

                # Merge datastore export data
                $childExportData.datastoreData | ForEach-Object {
                    $i = $exportData.datastoreData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.datastoreData.Insert(-bnot $i, $_)
                    }
                }

                # Merge virual machine export data
                $childExportData.vmData | ForEach-Object {
                    $i = $exportData.vmData.BinarySearch($_)
                    if($i -lt 0)
                    {
                        $exportData.vmData.Insert(-bnot $i, $_)
                    }
                }

                $a++
            }
        }

        return $exportData
    }
}
