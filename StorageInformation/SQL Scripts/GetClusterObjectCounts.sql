SELECT
	c.Name as Cluster,
	COUNT(DISTINCT vs.UUID) as VServers,
	COUNT(DISTINCT a.UUID) as Aggregates,
	COUNT(DISTINCT v.UUID) as Volumes
FROM
	Clusters c
		INNER JOIN Aggregates a ON a.ClusterUUID = c.UUID
		INNER JOIN Volumes v on v.AggregateUUID = a.UUID
		INNER JOIN VServers vs ON vs.ClusterUUID = c.UUID
		INNER JOIN VolumeData vd ON vd.VolumeUUID = v.UUID
WHERE
	vd.RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID)
GROUP BY
	c.Name
ORDER BY
	c.Name