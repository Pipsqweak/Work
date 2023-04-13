SELECT 
	c.Name AS Cluster,
	vs.Name AS VServer,
	a.Name AS Aggregate,
	v.Name AS Volume,
	sd.Path,
	sd.Name
FROM
	ShareData sd
		INNER JOIN Volumes v ON sd.VolumeUUID = v.UUID
		INNER JOIN VolumeData vd ON (v.UUID = vd.VolumeUUID) AND (sd.RunID = vd.RunID)
		INNER JOIN VServers vs ON (vd.vServerUUID = vs.UUID)
		INNER JOIN Aggregates a ON (vd.AggregateUUID = a.UUID)
		INNER JOIN Clusters c ON (vs.ClusterUUID = c.UUID)
WHERE
	(sd.RunID = dbo.MaxRunID()) AND
	(sd.Name NOT IN ('c$','d$','e$','f$','g$','admin$','ipc$','Shares$'))
