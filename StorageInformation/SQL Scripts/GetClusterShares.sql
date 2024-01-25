/****** Script for SelectTopNRows command from SSMS  ******/
SELECT
	c.Name as Cluster,
	vs.Name as VServer,
	vs.CIFSServerName as CIFSName,
    sd.Path,
    sd.Name
FROM
	ShareData sd
		INNER JOIN Volumes v ON sd.VolumeUUID = v.UUID
		INNER JOIN VServers vs ON vs.UUID = v.VServerUUID
		INNER JOIN Clusters c ON c.UUID = vs.ClusterUUID
WHERE
	RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID) AND 
	sd.Name NOT IN ('admin$','c$','ipc$','Shares$')

