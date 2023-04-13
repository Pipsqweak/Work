SELECT
	  dcr.CollectionDT AS DataCollected
	, c.Name AS ClusterName
	, vs.Name AS VServerName
	, v.Name AS VolumeName
	, vd.Size AS VolumeSize
	, vd.Available AS VolumeAvailable
	, vd.Used AS VolumeUsed
	, vd.IsEncrypted as VolumeIsEncrypted
	, vd.IsSnaplockProtected as VolumeIsSnaplockProtected
FROM
	Clusters c
		INNER JOIN VServers vs ON c.UUID = vs.ClusterUUID
		INNER JOIN VolumeData vd ON vs.UUID = vd.vServerUUID
		INNER JOIN Volumes v ON vd.VolumeUUID = v.UUID
		INNER JOIN DataCollectionRuns dcr ON vd.RunID = dcr.ID
WHERE
	-- dcr.ID = dbo.MaxRunID() AND
	(v.Name NOT LIKE 'JP_%') AND
	(v.Name NOT LIKE 'vol0') AND
	(v.Name NOT LIKE 'LSM_%') AND
	(v.Name NOT LIKE 'ROOT_%') AND
	(v.Name NOT LIKE 'SMD_%') AND
	(v.Name NOT LIKE 'SMDV_%') AND
	(v.Name NOT LIKE 'SL_%')
ORDER BY
	c.Name,
	vs.Name,
	v.Name,
    dcr.CollectionDT

