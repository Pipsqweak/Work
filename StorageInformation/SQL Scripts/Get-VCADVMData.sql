SELECT 
	dcr.CollectionDT,
	COUNT(vmd.VirtualMachineID)
FROM
	DataCollectionRuns dcr 
		INNER JOIN VirtualMachineData vmd ON dcr.ID = vmd.RunID
		INNER JOIN VirtualMachines vm ON vmd.VirtualMachineID = vm.ID
WHERE
	((vm.Name LIKE '%-VCAD%') OR (vm.Name LIKE '%vGIS-MCS%')  OR (vm.Name LIKE '%vDW11-MIT%'))
GROUP BY
	dcr.CollectionDT


