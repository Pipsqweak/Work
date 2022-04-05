USE [StorageInformation]
GO

/****** Object:  Table [dbo].[SnapshotData]    Script Date: 6/7/2021 2:55:14 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SnapshotData]') AND type in (N'U'))
DROP TABLE [dbo].[SnapshotData]
GO

/****** Object:  Table [dbo].[SnapshotData]    Script Date: 6/7/2021 2:55:14 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[SnapshotData](
	[RunID] [int] NOT NULL,
	[UUID] [uniqueidentifier] NOT NULL,
	[VolumeUUID] [uniqueidentifier] NOT NULL,
	[Created] [datetime] NULL,
	[ExpiryTime] [datetime] NULL,
	[SnaplockExpiryTime] [datetime] NULL,
	[SnapmirrorLabel] [nvarchar](100) NULL,
	[Name] [nvarchar](100) NULL,
	[Size] [bigint] NOT NULL,
	[CumulativeSize] [bigint] NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 2:54:17 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[SnapshotData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 6/7/2021 2:54:27 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[SnapshotData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_UUID_VolumeUUID]    Script Date: 6/7/2021 2:54:34 PM ******/
CREATE UNIQUE NONCLUSTERED INDEX [IX_UUID_VolumeUUID] ON [dbo].[SnapshotData]
(
	[UUID] ASC,
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
