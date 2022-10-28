SELECT
	c.Name as Cluster,
	vs.Name as VServer,
	v.Name as Volume,
	a.Name as Aggregate
FROM
	Clusters c
		INNER JOIN Aggregates a ON a.ClusterUUID = c.UUID
		INNER JOIN Volumes v on v.AggregateUUID = a.UUID
		INNER JOIN VServers vs ON vs.UUID = v.VServerUUID
		INNER JOIN VolumeData vd ON vd.VolumeUUID = v.UUID
WHERE
	vd.RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID)
ORDER BY
	Cluster,
	VServer,
	Volume