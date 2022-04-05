SELECT DISTINCT
	VirtualMachines.Name AS VMName,
	Datastores.Name AS DatastoreName,
	Volumes.Name AS VolName,
	VServers.Name AS vServerName,
	Aggregates.Name AS AggrName,
	Clusters.Name AS ClusterName
FROM
	VirtualMachine_DatastoreData INNER JOIN VirtualMachines
		ON VirtualMachine_DatastoreData.VirtualMachineID = VirtualMachines.ID INNER JOIN DatastoreData
			ON VirtualMachine_DatastoreData.DatastoreID = DatastoreData.ID INNER JOIN VolumeData
				ON DatastoreData.VolumeUUID = VolumeData.VolumeUUID INNER JOIN Volumes
					ON VolumeData.VolumeUUID = Volumes.UUID INNER JOIN Aggregates
						ON Volumes.AggregateUUID = Aggregates.UUID INNER JOIN Clusters
							ON Aggregates.ClusterUUID = Clusters.UUID INNER JOIN VServers
								ON Volumes.VServerUUID = VServers.UUID INNER JOIN Datastores
									ON VirtualMachine_DatastoreData.DatastoreID = Datastores.ID
WHERE
	(VolumeData.RunID = 7) AND
	(VirtualMachine_DatastoreData.RunID = VolumeData.RunID) AND
	(DatastoreData.RunID = VolumeData.RunID) AND
	(VirtualMachine_DatastoreData.RunID = VolumeData.RunID) AND

	(VolumeData.IsSnaplockProtected = 1) AND
	(VirtualMachines.Name NOT LIKE 'vCLS%')
ORDER BY
	VMName
