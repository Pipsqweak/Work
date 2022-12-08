Maintain a database of storage and virtual machine data.

There are 3 "types" of tables in the StorageInformation database:

    Identity table: Storage information about objects which rarely change.  Names, serial numbers, etc.  When a new object is discovered, an entry will be created in its object type table.  For instance,
       when a new datastore is discovered, identity data for the datastore will be recorded in the Datastores table.

    Point in time table: Stored object attributes as they existed when the data was collected.  For instance, the size of a datastore, or the UUID of the aggregate a volume hosted from.

    Link Table: DataCollectionRuns stores a list of RunIDs and CollectsDTs representing when point in time data was collected.

    When querying the data, care must be taken to ensure accurate information is retrieved.  For instance:

        When a volume is moved from one aggregate to another, the volume is assigned a new UUID.  As a result, a new entry in the Volumes table will be created since the new UUID assigned to the volume
            will not exist in the Volumes table.  This also has the side effect of leaving the "old" volume information still in the Volumes table.  This is needed for historical purposes.  Supposed I
            wanted to create a report of volumes on an aggregate on day X.  Therefore, if you query for current volumes by simply using "SELECT * FROM VOLUMES", you could retrieve data about volumes
            which are no longer active.  To alleviate this issue, always JOIN the Identity table to the Point in Time table, this will limit the data retrieved to only what existed at the time the data
            was stored.

            Example: To retrieve the current list of NetApp volumes (max RunID) use something like:

                SELECT
                    v.Name as Volume,
                    vd.Size as Size,
                    vd.Available as Available,
                    vd.Used as Used,
                    vd.IsEncrypted as IsEncrypted,
                    vd.IsSnaplockProtected as IsSnaplockProtected,
                    vd.SnapshotCount as SnapshotCount
                FROM
                    Volumes v
                        INNER JOIN VolumeData vd ON vd.VolumeUUID = v.UUID  -- Incorporating the VolumeData table will ensure only data which existed at the time it was collected is retrieved.
                WHERE
                    vd.RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID)
                ORDER BY
                    Volume




Link Tables:

    DataCollectionRuns: Link Table
        ID - int representing a unique collection of data
        CollectionDT - A timestamp representing when the data was collected.
            NOTE: This is not a 100% accurate representation since data for various objects is collected at different points in the script.  However, it is accurate enough for our purposes.

Identity Tables:

    Clusters:
        UUID: (Get-NcCluster).ClusterUuid
        Name: (Get-NcCluster).ClusterName
        Location: (Get-NcCluster).ClusterLocation
        SerialNumber: (Get-NcCluster).ClusterSerialNumber
        Contact: (Get-NcCluster).ClusterContact

    VServers:
        UUID: (Get-NcVserver).UUID
        ClusterUUID: the Vserver's parent cluster (--> Clusters.UUID)
        Name: (Get-NcVserver).VserverName
        Type: (Get-NcVserver).VserverType
        CIFSServerName: (Get-NCCifsServer -VserverContext $this).CifsServer

    Aggregates:
        UUID: (Get-NcAggr).UUID
        ClusterUUID: the aggregate's parent cluster (--> Clusters.UUID)
        Name: (Get-NcAggr).Name
        SnaplockType: (Get-NcAggr).AggrSnaplockAttributes.SnaplockType

    Volumes:
        UUID: (Get-NcVol).UUID
        Name: (Get-NcVol).Name
        SnaplockType: (Get-NcVol).VolumeSnaplockAttributes.SnaplockType

    Datastores: (Only NFS datastores are tracked, and currently, only datastores hosted on NetApp clustered ONTAP clusters)
        ID: (Get-Datastore).ID
        Name: (Get-Datastore).Name

    VirtualMachines:
        ID: (Get-Vm).ID
        Name: (Get-Vm).Name

Point in Time Tables:

    AggregateData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        AggregateUUID: the aggregate this data is associated with (--> Aggregates.UUID)
        Size: (Get-NcAggr).AggrSpaceAttributes.SizeTotal
        Used: (Get-NcAggr).AggrSpaceAttributes.SizeUsed
        Available: (Get-NcAggr).AggrSpaceAttributes.SizeAvailable

    VolumeData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        VServerUUID: the volume's parent Vserver (--> VServers.UUID)
        AggregateUUID: the volume's parent aggregate (--> Aggregates.UUID)
        VolumeUUID: the volume this data is associated with (--> Volumes.UUID)
        Size: (Get-NcVol).VolumeSpaceAttributes.SizeTotal
        Used: (Get-NcVol).VolumeSpaceAttributes.SizeUsed
        Available: (Get-NcVol).VolumeSpaceAttributes.SizeAvailable
        IsSnaplockProtected:
            1 if (Get-NcVol).VolumeSnaplockAttributes.SnaplockType is not NULL and != "non_snaplock" OR any of the volume's snapmirror destinations are Snaplock volumes.
            0 otherwise
        IsEncrypted: (Get-NcVol).Encrypted
        SnapshotCount: (Get-NcVol).VolumeSnapshotAttributes.SnapshotCount

    SnapmirrorData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        SourceVolumeUUID: the volume representing the source volume (--> Volumes.UUID)
        DestinationVolumeUUID: the volume representing the destination volume (--> Volumes.UUID)

    ShareData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        VolumeUUID: the volume associated with this data (--> Volumes.UUID)
        Path: (Get-NcCifsShare).Path
        Name: (Get-NcCifsShare).ShareName

    DatastoreData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        VolumeUUID: the volume associated with this data (--> Volumes.UUID)
        DatastoreID: the datastore associated with this data (--> Datastores.ID)
        Capacity: (Get-Datastore).ExtensionData.Summary.Capacity
        FreeSpace: (Get-Datastore).ExtensionData.Summary.FreeSpace
        Uncommitted: (Get-Datastore).ExtensionData.Summary.Uncommitted

    VirtualMachineData:
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        VirtualMachineID: the virtual machine associated with this data (--> VirtualMachines.ID)
        PowerState: (Get-VM).PowerState

    VirtualMachine_DatastoreData: (*NOTE* -- If a VM has files stored on multiple datastores, there will be a row for each datastore)
        RunID: the data collection run this data belongs to (--> DataCollectionRuns.ID)
        VirtualMachineID: the virtual machine associated with this data (--> VirtualMachines.ID)
        DatastoreID: the datastore associated with this data (--> Datastores.ID)
        Used: amount of space consumed on the datastore as calculated per unique datastore represented in (Get-VM).ExtensionData.LayoutEx.File
