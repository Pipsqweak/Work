DECLARE @RunID INT;
SET @RunID = 15;

DELETE FROM VolumeData WHERE RunID = @RunID;
DELETE FROM VirtualMachineData WHERE RunID = @RunID;
DELETE FROM VirtualMachine_DatastoreData WHERE RunID = @RunID;
DELETE FROM SnapshotData WHERE RunID = @RunID;
DELETE FROM SnapmirrorData WHERE RunID = @RunID;
DELETE FROM ShareData WHERE RunID = @RunID;
DELETE FROM DatastoreData WHERE RunID = @RunID;
DELETE FROM AggregateData WHERE RunID = @RunID;
DELETE FROM DataCollectionRuns WHERE ID = @RunID;
