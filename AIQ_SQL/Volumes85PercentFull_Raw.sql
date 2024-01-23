SELECT
	netapp_model_view.cluster.name AS Cluster,
	netapp_model_view.vserver.name AS VServer,
	netapp_model_view.volume.name AS Volume,
    ocum_view.volume.daysUntilFull AS DaysTillFull,
	netapp_model_view.volume.size AS VolumeSize,
	netapp_model_view.volume.autoSizeMode AS AutoSize,
    CASE
		WHEN lower(netapp_model_view.volume.autoSizeMode) LIKE '%grow%' THEN netapp_model_view.volume.autoSizeMaximumSize
		ELSE FORMAT(-1,0)
	END AS AutoSizeMax,
    CASE
		WHEN lower(netapp_model_view.volume.autoSizeMode) LIKE '%grow%' THEN ((netapp_model_view.volume.size / netapp_model_view.volume.autoSizeMaximumSize) * 100.0)
		ELSE FORMAT(-1,0)
	END AS PercentAutoSizeMax
FROM
	ocum_view.volume
		INNER JOIN netapp_model_view.volume
			ON (ocum_view.volume.id = netapp_model_view.volume.objid)
		INNER JOIN netapp_model_view.vserver
			ON (netapp_model_view.volume.vserverId = netapp_model_view.vserver.objid)
		INNER JOIN netapp_model_view.cluster
			ON (netapp_model_view.vserver.clusterId = netapp_model_view.cluster.objid)
WHERE
	(ocum_view.volume.daysUntilFull < 30) AND
    (netapp_model_view.volume.name NOT LIKE 'SMD_%') AND
    (netapp_model_view.volume.name NOT LIKE 'SL_%') AND
    (
		(lower(netapp_model_view.volume.autoSizeMode) NOT LIKE '%grow%') OR
        (
			(lower(netapp_model_view.volume.autoSizeMode) LIKE '%grow%') AND
            (netapp_model_view.volume.size > (netapp_model_view.volume.autoSizeMaximumSize * 0.85))
		)
	)
ORDER BY
	ocum_view.volume.daysUntilFull