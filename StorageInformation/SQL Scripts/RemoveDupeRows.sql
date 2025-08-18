
SELECT
	*
FROM (
	SELECT
		StorageInfoTest.dbo.VirtualMachineData.RunID
		, StorageInfoTest.dbo.VirtualMachineData.VirtualMachineID
		, COUNT(StorageInfoTest.dbo.VirtualMachineData.RunID) AS DupeCount
	FROM
		StorageInfoTest.dbo.VirtualMachineData
	GROUP BY
		StorageInfoTest.dbo.VirtualMachineData.RunID, StorageInfoTest.dbo.VirtualMachineData.VirtualMachineID
) AS DD
WHERE
	DupeCount > 1
ORDER BY
	RunID

BEGIN TRANSACTION;


DECLARE @RunID INT;
SET @RunID = 630;
DECLARE @VMID NVARCHAR(100);
SET @VMID = 'VirtualMachine-vm-28842';
DELETE FROM vmd FROM (SELECT TOP 1 StorageInfoTest.dbo.VirtualMachineData.* FROM StorageInfoTest.dbo.VirtualMachineData WHERE (StorageInfoTest.dbo.VirtualMachineData.VirtualMachineId = @VMID) AND (StorageInfoTest.dbo.VirtualMachineData.RunID = @RunID)) vmd;
SELECT * FROM StorageInfoTest.dbo.VirtualMachineData WHERE (StorageInfoTest.dbo.VirtualMachineData.VirtualMachineId = @VMID) AND (StorageInfoTest.dbo.VirtualMachineData.RunID = @RunID);


ROLLBACK



