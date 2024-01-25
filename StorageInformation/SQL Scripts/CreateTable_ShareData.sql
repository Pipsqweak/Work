USE [StorageInformation]
GO

/****** Object:  Table [dbo].[ShareData]    Script Date: 11/1/2022 1:41:04 PM ******/
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

/****** Object:  Index [IX_RunID]    Script Date: 11/1/2022 1:41:18 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[ShareData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VolumeUUID]    Script Date: 11/1/2022 1:41:34 PM ******/
CREATE NONCLUSTERED INDEX [IX_VolumeUUID] ON [dbo].[ShareData]
(
	[VolumeUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO


