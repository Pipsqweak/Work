USE [StorageInformation]
GO

/****** Object:  Table [dbo].[DatastoreData]    Script Date: 11/1/2022 1:35:28 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DatastoreData](
	[RunID] [int] NOT NULL,
	[VolumeUUID] [uniqueidentifier] NOT NULL,
	[DatastoreID] [nvarchar](100) NOT NULL,
	[Capacity] [bigint] NOT NULL,
	[FreeSpace] [bigint] NOT NULL,
	[Uncommitted] [bigint] NOT NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[DatastoreData] ADD  CONSTRAINT [DF_DatastoreData_Capacity]  DEFAULT ((0)) FOR [Capacity]
GO

ALTER TABLE [dbo].[DatastoreData] ADD  CONSTRAINT [DF_DatastoreData_FreeSpace]  DEFAULT ((0)) FOR [FreeSpace]
GO

ALTER TABLE [dbo].[DatastoreData] ADD  CONSTRAINT [DF_DatastoreData_Uncommitted]  DEFAULT ((0)) FOR [Uncommitted]
GO

SET ANSI_PADDING ON
GO

/****** Object:  Index [IX_ID]    Script Date: 11/1/2022 1:36:28 PM ******/
CREATE NONCLUSTERED INDEX [IX_ID] ON [dbo].[DatastoreData]
(
	[DatastoreID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 11/1/2022 1:36:52 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[DatastoreData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 11/1/2022 1:37:08 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[DatastoreData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

