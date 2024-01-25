SELECT
	vm.Name as VM,
	ds.Name as Datastore
FROM
	VirtualMachines vm 
		INNER JOIN VirtualMachine_DatastoreData vdd ON vm.ID = vdd.VirtualMachineID
		INNER JOIN Datastores ds ON ds.ID = vdd.DatastoreID
WHERE
	(RunID = (SELECT MAX(ID) as RunID FROM DataCollectionRuns as MaxRunID))
	AND (vdd.DatastoreID = 'Datastore-datastore-9104')
	AND (vdd.VirtualMachineID = 'VirtualMachine-vm-27571')