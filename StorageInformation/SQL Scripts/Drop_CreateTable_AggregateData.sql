USE [StorageInformation]
GO

/****** Object:  Table [dbo].[AggregateData]    Script Date: 6/7/2021 2:29:43 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AggregateData]') AND type in (N'U'))
DROP TABLE [dbo].[AggregateData]
GO

/****** Object:  Table [dbo].[AggregateData]    Script Date: 6/7/2021 2:29:43 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[AggregateData](
	[RunID] [int] NOT NULL,
	[AggregateUUID] [uniqueidentifier] NOT NULL,
	[Size] [bigint] NOT NULL,
	[Used] [bigint] NOT NULL,
	[Available] [bigint] NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_AggregateUUID]    Script Date: 6/7/2021 2:33:25 PM ******/
CREATE NONCLUSTERED INDEX [IX_AggregateUUID] ON [dbo].[AggregateData]
(
	[AggregateUUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 2:28:42 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[AggregateData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
