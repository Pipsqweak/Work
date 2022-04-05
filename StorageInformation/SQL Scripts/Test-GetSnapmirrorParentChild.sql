WITH EXPL (RunID, SourceVolumeUUID, DestinationVolumeUUID) AS
(
	SELECT
		ROOT.RunID,
		ROOT.SourceVolumeUUID,
		ROOT.DestinationVolumeUUID
	FROM
		SnapmirrorData AS ROOT
			INNER JOIN Volumes
				ON ROOT.DestinationVolumeUUID = Volumes.UUID
	WHERE
		(Volumes.SnaplockType IS NOT NULL) AND (Volumes.SnaplockType <> 'non_snaplock')

	UNION ALL

	SELECT
		CHILD.RunID,
		CHILD.SourceVolumeUUID,
		CHILD.DestinationVolumeUUID
	FROM
		SnapmirrorData as CHILD
			INNER JOIN EXPL as PARENT
				ON PARENT.DestinationVolumeUUID = CHILD.SourceVolumeUUID
)

 

     SELECT DISTINCT
		EXPL.RunID,
		EXPL.SourceVolumeUUID as SourceVolumeUUID,
		SourceClusters.Name as SourceClusterName,
		SourceVServers.Name as SourceVServerName,
		SourceVolumes.Name as SourceVolumeName,
		EXPL.DestinationVolumeUUID as DestinationVolumeUUID,
		DestinationClusters.Name as DestinationClusterName,
		DestinationVServers.Name as DestinationVServerName,
		DestinationVolumes.Name as DestinationVolumeName
     FROM
		EXPL
			INNER JOIN Volumes as SourceVolumes
				ON SourceVolumeUUID = SourceVolumes.UUID
			INNER JOIN VServers as SourceVServers
				ON SourceVolumes.VServerUUID = SourceVServers.UUID
			INNER JOIN Clusters as SourceClusters
				ON SourceVServers.ClusterUUID = SourceClusters.UUID
			INNER JOIN Volumes as DestinationVolumes
				ON DestinationVolumeUUID = DestinationVolumes.UUID
			INNER JOIN VServers as DestinationVServers
				ON DestinationVolumes.VServerUUID = DestinationVServers.UUID
			INNER JOIN Clusters as DestinationClusters
				ON DestinationVServers.ClusterUUID = DestinationClusters.UUID
     ORDER BY SourceVolumeUUID, DestinationVolumeUUID;


