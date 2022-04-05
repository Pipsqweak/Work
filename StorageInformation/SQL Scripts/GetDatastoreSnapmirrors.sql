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
	, SourceDatastores.Name AS SourceDatastore
	, DestinationClusters.Name AS DestinationCluster
	, DestinationVServers.Name AS DestinationVServer
	, DestinationVolumes.Name AS DestinationVolume
	, DestinationVolumeData.Size AS DestinationVolumeSize
	, DestinationVolumeData.Used AS DestinationVolumeUsed
	, DestinationVolumeData.Available AS DestinationVolumeAvailable
	, DestinationVolumeData.IsSnaplockProtected AS DestinationVolumeIsSnaplockProtected
	, DestinationDatastores.Name AS DestinationDatastore
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
		LEFT  JOIN DatastoreData AS SourceDatastoreData ON (SnapmirrorData.RunID = SourceDatastoreData.RunID) AND (SourceVolumeUUID = SourceDatastoreData.VolumeUUID)
		INNER JOIN Datastores AS SourceDatastores ON SourceDatastoreData.DatastoreID = SourceDatastores.ID
		LEFT  JOIN DatastoreData AS DestinationDatastoreData ON (SnapmirrorData.RunID = DestinationDatastoreData.RunID) AND (DestinationVolumeUUID = DestinationDatastoreData.VolumeUUID)
		LEFT  JOIN Datastores AS DestinationDatastores ON DestinationDatastoreData.DatastoreID = DestinationDatastores.ID
WHERE
--    (SnapmirrorData.RunID = 15)
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