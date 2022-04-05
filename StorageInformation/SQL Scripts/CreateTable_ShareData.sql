USE [StorageInformation]
GO

/****** Object:  Table [dbo].[ShareData]    Script Date: 6/7/2021 2:57:35 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[ShareData](
	[RunID] [int] NOT NULL,
	[VolumeUUID] [uniqueidentifier] NOT NULL,
	[Path] [nvarchar](400) NOT NULL,
	[Name] [nvarchar](100) NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 2:57:49 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[ShareData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 6/7/2021 2:57:55 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[ShareData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

