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
	SnapmirrorData
		INNER JOIN VolumeData AS SourceVolumeData ON (SnapmirrorData.SourceVolumeUUID = SourceVolumeData.VolumeUUID) AND (SourceVolumeData.RunID = SnapmirrorData.RunID)
		INNER JOIN VolumeData AS DestinationVolumeData ON (SnapmirrorData.DestinationVolumeUUID = DestinationVolumeData.VolumeUUID) AND (DestinationVolumeData.RunID = SnapmirrorData.RunID)
		INNER JOIN Volumes AS SourceVolumes ON SourceVolumeData.VolumeUUID = SourceVolumes.UUID
		INNER JOIN Volumes AS DestinationVolumes ON DestinationVolumeData.VolumeUUID = DestinationVolumes.UUID
		INNER JOIN VServers AS SourceVServers ON SourceVolumeData.vServerUUID = SourceVServers.UUID
		INNER JOIN VServers AS DestinationVServers ON DestinationVolumeData.vServerUUID = DestinationVServers.UUID
		INNER JOIN Clusters AS SourceClusters ON SourceVServers.ClusterUUID = SourceClusters.UUID
		INNER JOIN Clusters AS DestinationClusters ON DestinationVServers.ClusterUUID = DestinationClusters.UUID

WHERE
	SnapmirrorData.RunID = dbo.MaxRunID()
ORDER BY
	  SnapmirrorData.RunID
    , SourceCluster
	, SourceVServer
	, SourceVolume
	, DestinationCluster
	, DestinationVServer
	, DestinationVolume