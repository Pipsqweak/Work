/****** Script for SelectTopNRows command from SSMS  ******/
SELECT
	  SnapmirrorData.RunID
	, SourceClusters.Name AS SourceCluster
	, SourceVServers.Name AS SourceVServer
	, SourceVolumes.Name AS SourceVolume
	, SourceVolumeData.Size AS SourceVolumeSize
	, SourceVolumeData.Used AS SourceVolumeUsed
	, SourceVolumeData.Available AS SourceVolumeAvailable
	, SourceVolumeData.IsSnaplockProtected AS SourceVolumeIsSnaplockProtected
	, DestinationClusters.Name AS DestinationCluster
	, DestinationVServers.Name AS DestinationVServer
	, DestinationVolumes.Name AS DestinationVolume
	, DestinationVolumeData.Size AS DestinationVolumeSize
	, DestinationVolumeData.Used AS DestinationVolumeUsed
	, DestinationVolumeData.Available AS DestinationVolumeAvailable
	, DestinationVolumeData.IsSnaplockProtected AS DestinationVolumeIsSnaplockProtected
FROM
	Volumes AS SourceVolumes
		INNER JOIN SnapmirrorData ON SourceVolumes.UUID = SnapmirrorData.SourceVolumeUUID
		INNER JOIN VServers AS SourceVServers ON SourceVolumes.VServerUUID = SourceVServers.UUID
		INNER JOIN Clusters AS SourceClusters ON SourceVServers.ClusterUUID = SourceClusters.UUID
		INNER JOIN VolumeData AS SourceVolumeData ON (SnapmirrorData.RunID = SourceVolumeData.RunID) AND (SourceVolumes.UUID = SourceVolumeData.VolumeUUID)
		INNER JOIN Volumes AS DestinationVolumes ON DestinationVolumes.UUID = SnapmirrorData.DestinationVolumeUUID
		INNER JOIN VServers AS DestinationVServers ON DestinationVolumes.VServerUUID = DestinationVServers.UUID
		INNER JOIN Clusters AS DestinationClusters ON DestinationVServers.ClusterUUID = DestinationClusters.UUID
		INNER JOIN VolumeData AS DestinationVolumeData ON (SnapmirrorData.RunID = DestinationVolumeData.RunID) AND (DestinationVolumes.UUID = DestinationVolumeData.VolumeUUID)
WHERE
--    SnapmirrorData.RunID = 11)
	(SnapmirrorData.RunID = (
		SELECT 
			TOP 1 ID AS MaxRunID
		FROM
			DataCollectionRuns
		ORDER BY ID DESC
	))
	-- AND
	-- (SourceDatastoreData.DatastoreID IS NOT NULL)	
ORDER BY
	  SnapmirrorData.RunID
    , SourceCluster
	, SourceVServer
	, SourceVolume
	, DestinationCluster
	, DestinationVServer
	, DestinationVolume