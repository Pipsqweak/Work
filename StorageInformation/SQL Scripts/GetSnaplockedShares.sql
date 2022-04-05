SELECT        
	Clusters.Name AS ClusterName,
	VServers.Name AS VServerName,
	VServers.CIFSServerName as CIFSServerName,
	Aggregates.Name AS AggregateName,
	Volumes.Name AS VolumeName,
	ShareData.Name AS ShareName,
	ShareData.Path AS SharePath,
	CONCAT('\\', VServers.CIFSServerName, '\', ShareData.Name) as CIFSShare
FROM
	Clusters INNER JOIN Aggregates
		ON Clusters.UUID = Aggregates.ClusterUUID INNER JOIN Volumes
			ON Aggregates.UUID = Volumes.AggregateUUID INNER JOIN VolumeData
				ON VolumeData.VolumeUUID = Volumes.UUID INNER JOIN ShareData
					ON ShareData.VolumeUUID = VolumeData.VolumeUUID INNER JOIN VServers
                        ON Volumes.VServerUUID = VServers.UUID  
WHERE        
	(ShareData.RunID = 7) AND 
	(ShareData.RunID = VolumeData.RunID) AND
	(VolumeData.IsSnaplockProtected = 1)
ORDER BY
	ClusterName,VServerName,AggregateName,VolumeName,ShareName,SharePath