-- Snaplock

SELECT
	U.RunID as RunID,
	CONCAT('\\', ParentVServers.CIFSServerName, '\', ShareData.Name) as CIFSShare, 
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
	U.SnapLockCount
FROM
(
	-- Add the number of snapshots for each RunID, VolumeUUID from the inner select (T)
	SELECT
		T.RunID,
		T.VolumeUUID,
		COUNT(SnapshotData.UUID) AS SnapLockCount
	FROM
	(
		-- Get the latest RunID and VolumeUUID for each unique VolumeUUID in SnapshotData where the snapshot has a snaplock expiration date
		SELECT
			MAX(SnapShotData.RunID) as RunID,
			SnapshotData.VolumeUUID
		FROM
			SnapshotData
		WHERE        
			(SnapshotData.SnaplockExpiryTime IS NOT NULL)
		GROUP BY
			SnapshotData.VolumeUUID
	) AS T
		INNER JOIN SnapshotData
			ON (T.RunID = SnapshotData.RunID) AND (T.VolumeUUID = SnapshotData.VolumeUUID)
	GROUP BY
		T.RunID,
		T.VolumeUUID
) AS U
		INNER JOIN Volumes as SnaplockVolumes
			ON (U.VolumeUUID = SnaplockVolumes.UUID)
		INNER JOIN SnapmirrorData
			ON (SnaplockVolumes.UUID = SnapmirrorData.DestinationVolumeUUID) AND (SnapmirrorData.RunID = U.RunID)
		INNER JOIN SnapMirrorData as ParentSnapMirror
			ON (SnapmirrorData.SourceVolumeUUID = ParentSnapMirror.DestinationVolumeUUID) AND (ParentSnapMirror.RunID = U.RunID)
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
		INNER JOIN ShareData
			ON (ShareData.VolumeUUID = ParentVolumes.UUID) AND (ShareData.RunID = U.RunID)
		INNER JOIN DataCollectionRuns
			ON U.RunID = DataCollectionRuns.ID