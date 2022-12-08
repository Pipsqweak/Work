/****** Script for SelectTopNRows command from SSMS  ******/
SELECT
	  SourceClusters.Name AS SourceCluster
	, SourceVServers.Name AS SourceVServer
	, SourceVolumes.Name AS SourceVolume
	, svd.Size AS SourceVolumeSize
	, svd.Used AS SourceVolumeUsed
	, svd.Available AS SourceVolumeAvailable
	, svd.IsSnaplockProtected AS SourceVolumeIsSnaplockProtected
	, SourceDatastores.Name AS SourceDatastore
	, DestinationClusters.Name AS DestinationCluster
	, DestinationVServers.Name AS DestinationVServer
	, DestinationVolumes.Name AS DestinationVolume
	, dvd.Size AS DestinationVolumeSize
	, dvd.Used AS DestinationVolumeUsed
	, dvd.Available AS DestinationVolumeAvailable
	, dvd.IsSnaplockProtected AS DestinationVolumeIsSnaplockProtected
	, DestinationDatastores.Name AS DestinationDatastore
FROM
	SnapMirrorData smd
		INNER JOIN VolumeData svd ON (smd.SourceVolumeUUID = svd.VolumeUUID) AND (smd.RunID = svd.RunID)
		INNER JOIN VolumeData dvd ON (smd.DestinationVolumeUUID = dvd.VolumeUUID) AND (smd.RunID = dvd.RunID)
		INNER JOIN Volumes SourceVolumes ON svd.VolumeUUID = SourceVolumes.UUID
		INNER JOIN Volumes DestinationVolumes ON dvd.VolumeUUID = DestinationVolumes.UUID
		INNER JOIN VServers SourceVServers ON svd.vServerUUID = SourceVServers.UUID
		INNER JOIN VServers DestinationVServers ON dvd.vServerUUID = DestinationVServers.UUID
		INNER JOIN Clusters SourceClusters ON SourceVServers.ClusterUUID = SourceClusters.UUID
		INNER JOIN Clusters DestinationClusters ON DestinationVServers.ClusterUUID = DestinationClusters.UUID
		INNER JOIN DatastoreData SourceDatastoreData ON (smd.RunID = SourceDatastoreData.RunID) AND (smd.SourceVolumeUUID = SourceDatastoreData.VolumeUUID)
		LEFT  JOIN DatastoreData DestinationDatastoreData ON (smd.RunID = DestinationDatastoreData.RunID) AND (smd.DestinationVolumeUUID = DestinationDatastoreData.VolumeUUID)
		INNER JOIN Datastores SourceDatastores ON SourceDatastoreData.DatastoreID = SourceDatastores.ID
		LEFT  JOIN Datastores DestinationDatastores ON DestinationDatastoreData.DatastoreID = DestinationDatastores.ID
WHERE
	smd.RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID)
	-- AND
	-- (SourceDatastoreData.DatastoreID IS NOT NULL)	
ORDER BY
	  SourceDatastore
    , SourceCluster
	, SourceVServer
	, SourceVolume
	, DestinationCluster
	, DestinationVServer
	, DestinationVolume