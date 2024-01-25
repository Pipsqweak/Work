SELECT
	*
FROM 
	ShareData sd
		INNER JOIN Volumes2 v ON (sd.RunID = v.RunID) AND (sd.VolumeUUID = v.UUID)
WHERE
	(sd.RunID,sd.VolumeUUID IN (SELECT DISTINCT RunID,VolumeUUID FROM ShareData))


UPDATE
	Volumes2 v2
SET
	v2.JunctionPath = (
		SELECT TOP 1
			sd.Path AS JunctionPath
		FROM
			ShareData sd
				INNER JOIN Volumes2 v ON (sd.RunID = v.RunID) AND (sd.VolumeUUID = v.UUID)
		WHERE
			(sd.VolumeUUID = v2.UUID) AND (sd.RunID = 1)
		)



WHILE @cnt < 2
BEGIN
 DECLARE @cnt INT = 1; 
 
	SELECT
		sd.Path AS JunctionPath
	FROM 
		ShareData sd
			INNER JOIN Volumes2 v ON (sd.RunID = v.RunID) AND (sd.VolumeUUID = v.UUID)
	WHERE
		(sd.VolumeUUID IN (SELECT DISTINCT VolumeUUID FROM ShareData WHERE RunID = @cnt))
		AND (sd.RunID = @cnt)


   SET @cnt = @cnt + 1;
END;
