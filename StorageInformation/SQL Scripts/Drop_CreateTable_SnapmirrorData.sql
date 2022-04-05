USE [StorageInformation]
GO

/****** Object:  Table [dbo].[SnapmirrorData]    Script Date: 6/7/2021 2:38:55 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SnapmirrorData]') AND type in (N'U'))
DROP TABLE [dbo].[SnapmirrorData]
GO

/****** Object:  Table [dbo].[SnapmirrorData]    Script Date: 6/7/2021 2:38:55 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[SnapmirrorData](
	[RunID] [int] NOT NULL,
	[SourceVolumeUUID] [uniqueidentifier] NOT NULL,
	[DestinationVolumeUUID] [uniqueidentifier] NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_DestinationVolumeUUID]    Script Date: 6/7/2021 2:38:05 PM ******/
CREATE NONCLUSTERED INDEX [IX_DestinationVolumeUUID] ON [dbo].[SnapmirrorData]
(
	[DestinationVolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 2:38:17 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[SnapmirrorData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_SourceVolumeUUID]    Script Date: 6/7/2021 2:38:28 PM ******/
CREATE NONCLUSTERED INDEX [IX_SourceVolumeUUID] ON [dbo].[SnapmirrorData]
(
	[SourceVolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
