With T AS 
(
	SELECT
		SnapShotData.RunID as RunID,
		SnapshotData.VolumeUUID as VolumeUUID,
		COUNT(SnapshotData.UUID) AS SnapLockCount
	FROM
		SnapshotData
			INNER JOIN SnapmirrorData
				ON (SnapshotData.VolumeUUID = SnapmirrorData.DestinationVolumeUUID) AND (SnapshotData.RunID = SnapmirrorData.RunID)
			INNER JOIN Volumes as DestinationVolumes
				ON SnapmirrorData.DestinationVolumeUUID = DestinationVolumes.UUID
			INNER JOIN Volumes as SourceVolumes
				ON SnapmirrorData.SourceVolumeUUID = SourceVolumes.UUID
			INNER JOIN VolumeData
				ON (SourceVolumes.UUID = VolumeData.VolumeUUID) AND (SnapmirrorData.RunID = VolumeData.RunID)
	WHERE        
		(VolumeData.IsSnaplockProtected = 1)
	GROUP BY
		SnapshotData.RunID, SnapshotData.VolumeUUID
)
SELECT
	T.RunID,
	DataCollectionRuns.CollectionDT as RunDate,
	ParentClusters.Name as ParentClusterName,
	ParentVServers.Name as ParentVServerName,
	ParentVolumes.Name as ParentVolumeName,
	IntermediateClusters.Name as IntermediateClusterName,
	IntermediateVServers.Name as IntermediateVServerName,
	IntermediateVolumes.Name as IntermediateVolumeName,
	SnaplockClusters.Name as SnaplockClusterName,
	SnaplockVServers.Name as SnaplockVServerName,
	SnaplockVolumes.Name as SnaplockVolumeName,
	T.SnapLockCount
FROM
	T INNER JOIN Volumes as SnaplockVolumes
		ON (T.VolumeUUID = SnaplockVolumes.UUID) AND (SnaplockVolumes.SnaplockType <> 'non_snaplock')
	  INNER JOIN SnapmirrorData
		ON (SnaplockVolumes.UUID = SnapmirrorData.DestinationVolumeUUID) AND (SnapmirrorData.RunID = T.RunID)

	  INNER JOIN SnapMirrorData as ParentSnapMirror
	    ON (SnapmirrorData.SourceVolumeUUID = ParentSnapMirror.DestinationVolumeUUID) AND (ParentSnapMirror.RunID = T.RunID)
	  INNER JOIN Volumes as ParentVolumes
	    ON (ParentSnapMirror.SourceVolumeUUID = ParentVolumes.UUID)
	  INNER JOIN VServers as ParentVServers
	    ON ParentVServers.UUID = ParentVolumes.VServerUUID
	  INNER JOIN Clusters as ParentClusters
	    ON (ParentClusters.UUID = ParentVServers.ClusterUUID)
	  INNER JOIN Volumes AS IntermediateVolumes
	    ON SnapmirrorData.SourceVolumeUUID = IntermediateVolumes.UUID
	  INNER JOIN VServers as IntermediateVServers
	    ON IntermediateVServers.UUID = IntermediateVolumes.VServerUUID
	  INNER JOIN VServers as SnaplockVServers
	    ON SnaplockVServers.UUID = SnaplockVolumes.VServerUUID
	  INNER JOIN Clusters as IntermediateClusters
	    ON IntermediateClusters.UUID = IntermediateVServers.ClusterUUID
	  INNER JOIN Clusters as SnaplockClusters
	    ON SnaplockClusters.UUID = SnaplockVServers.ClusterUUID
	  INNER JOIN DataCollectionRuns
	    ON T.RunID = DataCollectionRuns.ID
ORDER BY
	ParentClusterName,
	ParentVServerName,
	ParentVolumeName,
	SnaplockClusterName,
	RunID