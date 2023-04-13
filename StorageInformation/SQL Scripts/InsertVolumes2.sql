INSERT INTO
	Volumes2 (RunID, UUID, Name, JunctionPath, SnaplockType, vServerUUID, AggregateUUID, Size, Used, Available, IsSnaplockProtected, IsEncrypted, SnapshotCount)
SELECT
	vd.RunID,
	v.UUID,
	v.Name,
	'' AS JunctionPath,
	v.SnaplockType,
	vd.vServerUUID,
	vd.AggregateUUID,
	vd.Size,
	vd.Used,
	vd.Available,
	vd.IsSnaplockProtected,
	vd.IsEncrypted,
	vd.SnapshotCount
FROM
	VolumeData vd
		INNER JOIN Volumes v ON vd.VolumeUUID = v.UUID
ORDER BY
	vd.RunID,vd.VolumeUUID,vd.vServerUUID,vd.AggregateUUID
