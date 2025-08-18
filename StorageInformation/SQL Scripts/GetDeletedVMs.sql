DECLARE @d int
SET @d = 9

SELECT Q1.* FROM (
	SELECT
	dcr.ID AS RunID
	, vm.ID AS VirtualMachineID
	, vm.Name AS VirtualMachine
	, vmd.PowerState AS PowerState
	, vmd.Host AS VMHost
	, vmd.vCPU AS NumCPU
	, vmd.MemoryMB AS MemoryMB
	, vmd.UsedSpaceGB AS UsedSpaceGB
	, vmd.GPUProfile AS GPUProfile
	, vmdd.Used AS DSUsed
	, ds.ID AS DatastoreID
	, ds.Name AS Datastore
	, dsd.Capacity AS DSCapacity
	, dsd.FreeSpace AS DSFreeSpace
	, dsd.Uncommitted AS DSUncommitted
	, v.UUID AS VolumeUUID
	, v.Name AS Volume
	, v.SnaplockType AS SnaplockType
	, vd.Available AS VolumeAvailable
	, vd.Size AS VolumeSize
	, vd.Used AS VolumeUsed
	, vd.IsEncrypted AS VolumeIsEncrypted
	, vd.IsSnaplockProtected AS VolumeIsSnaplockProtected
FROM
	DataCollectionRuns dcr
		INNER JOIN VirtualMachineData vmd ON (dcr.ID = vmd.RunID)
		INNER JOIN VirtualMachines vm ON (vmd.VirtualMachineID = vm.ID)
		INNER JOIN VirtualMachine_DatastoreData vmdd ON (vm.ID = vmdd.VirtualMachineID) AND (vmdd.RunID = dcr.ID)
		INNER JOIN DatastoreData dsd ON (vmdd.DatastoreID = dsd.DatastoreID) AND (dsd.RunID = dcr.ID)
		INNER JOIN Datastores ds ON (dsd.DatastoreID = ds.ID)
		INNER JOIN VolumeData vd ON (dsd.VolumeUUID = vd.VolumeUUID) AND (vd.RunID = dcr.ID)
		INNER JOIN Volumes v ON (vd.VolumeUUID = v.UUID)
	WHERE
		dcr.ID = (dbo.MaxRunID() - (@d + 1))
) Q1

WHERE VirtualMachineID NOT IN (
	SELECT
		vm.ID AS VirtualMachineID
	FROM
		DataCollectionRuns dcr
			INNER JOIN VirtualMachineData vmd ON (dcr.ID = vmd.RunID)
			INNER JOIN VirtualMachines vm ON (vmd.VirtualMachineID = vm.ID)
	WHERE
		dcr.ID = (dbo.MaxRunID() - @d)
)