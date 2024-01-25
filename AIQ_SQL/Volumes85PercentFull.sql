SELECT
	netapp_model_view.cluster.name AS Cluster,
	netapp_model_view.vserver.name AS VServer,
	NMVV.name AS Volume,
    OVV.daysUntilFull AS DaysTillFull,
    CASE
         WHEN NMVV.size < 1024 THEN CONCAT(FORMAT(NMVV.size, 0), ' B')
         WHEN ((NMVV.size >= 1024) AND (NMVV.size < 1048576)) THEN CONCAT(FORMAT((NMVV.size / 1024), 2), ' KB')
         WHEN ((NMVV.size >= 1048576) AND (NMVV.size < 1073741824)) THEN CONCAT(FORMAT((NMVV.size / 1048576), 2), ' MB')
         WHEN ((NMVV.size >= 1073741824) AND (NMVV.size < 1099511627776)) THEN CONCAT(FORMAT((NMVV.size / 1073741824), 2), ' GB')
         ELSE CONCAT(FORMAT((NMVV.size / 1099511627776), 2), ' TB')
	END AS VolumeSize,
    NMVV.autoSizeMode AS AutoSizeMode,
    CASE
		WHEN lower(NMVV.autoSizeMode) LIKE '%grow%' THEN
			CASE
				 WHEN NMVV.autoSizeMaximumSize < 1024 THEN CONCAT(FORMAT(NMVV.autoSizeMaximumSize, 0), ' B')
				 WHEN ((NMVV.autoSizeMaximumSize >= 1024) AND (NMVV.autoSizeMaximumSize < 1048576)) THEN CONCAT(FORMAT((NMVV.autoSizeMaximumSize / 1024), 2), ' KB')
				 WHEN ((NMVV.autoSizeMaximumSize >= 1048576) AND (NMVV.autoSizeMaximumSize < 1073741824)) THEN CONCAT(FORMAT((NMVV.autoSizeMaximumSize / 1048576), 2), ' MB')
				 WHEN ((NMVV.autoSizeMaximumSize >= 1073741824) AND (NMVV.autoSizeMaximumSize < 1099511627776)) THEN CONCAT(FORMAT((NMVV.autoSizeMaximumSize / 1073741824), 2), ' GB')
				 ELSE CONCAT(FORMAT((NMVV.autoSizeMaximumSize / 1099511627776), 2), ' TB')
			END
		ELSE
			'N/A'
	END AS AutoSizeMax,
    CASE
		WHEN lower(NMVV.autoSizeMode) LIKE '%grow%'
			THEN FORMAT (((NMVV.size / NMVV.autoSizeMaximumSize) * 100.0), 2)
            ELSE 'N/A'
	END AS PercentAutoSizeMax
FROM
	ocum_view.volume AS OVV
		INNER JOIN netapp_model_view.volume AS NMVV
			ON (OVV.id = NMVV.objid)
		INNER JOIN netapp_model_view.vserver
			ON (NMVV.vserverId = netapp_model_view.vserver.objid)
		INNER JOIN netapp_model_view.cluster
			ON (netapp_model_view.vserver.clusterId = netapp_model_view.cluster.objid)
WHERE
	(OVV.daysUntilFull < 30) AND
    (NMVV.name NOT LIKE 'SMD_%') AND
    (NMVV.name NOT LIKE 'SL_%') AND
    (
		(lower(NMVV.autoSizeMode) NOT LIKE '%grow%') OR
        (
			(lower(NMVV.autoSizeMode) LIKE '%grow%') AND
            (NMVV.size > (NMVV.autoSizeMaximumSize * 0.85))
		)
	)
ORDER BY
	OVV.daysUntilFull