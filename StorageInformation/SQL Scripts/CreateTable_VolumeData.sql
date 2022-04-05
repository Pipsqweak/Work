USE [StorageInformation]
GO

/****** Object:  Table [dbo].[VolumeData]    Script Date: 6/7/2021 2:34:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[VolumeData](
	[RunID] [int] NOT NULL,
	[VolumeUUID] [uniqueidentifier] NOT NULL,
	[Size] [bigint] NOT NULL,
	[Used] [bigint] NOT NULL,
	[Available] [bigint] NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 6/7/2021 2:34:18 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[VolumeData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 2:34:39 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[VolumeData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO


