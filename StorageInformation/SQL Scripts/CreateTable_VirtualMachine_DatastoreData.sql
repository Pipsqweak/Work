USE [StorageInformation]
GO

/****** Object:  Table [dbo].[VirtualMachine_DatastoreData]    Script Date: 6/7/2021 3:13:41 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[VirtualMachine_DatastoreData](
	[RunID] [int] NOT NULL,
	[VirtualMachineID] [nvarchar](100) NOT NULL,
	[VolumeUUID] [uniqueidentifier] NOT NULL,
	[DatastoreID] [nvarchar](100) NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_DatastoreID]    Script Date: 6/7/2021 3:13:49 PM ******/
CREATE NONCLUSTERED INDEX [IX_DatastoreID] ON [dbo].[VirtualMachine_DatastoreData]
(
	[DatastoreID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 3:13:59 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[VirtualMachine_DatastoreData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VirtualMachineID]    Script Date: 6/7/2021 3:14:11 PM ******/
CREATE NONCLUSTERED INDEX [IX_VirtualMachineID] ON [dbo].[VirtualMachine_DatastoreData]
(
	[VirtualMachineID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 6/7/2021 3:14:20 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[VirtualMachine_DatastoreData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

