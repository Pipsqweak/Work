USE [StorageInformation]
GO

/****** Object:  Table [dbo].[Aggregates]    Script Date: 6/7/2021 2:19:04 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Aggregates]') AND type in (N'U'))
DROP TABLE [dbo].[Aggregates]
GO

/****** Object:  Table [dbo].[Aggregates]    Script Date: 6/7/2021 2:19:04 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Aggregates](
	[UUID] [uniqueidentifier] NOT NULL,
	[ClusterUUID] [uniqueidentifier] NOT NULL,
	[Name] [nvarchar](100) NOT NULL,
 CONSTRAINT [PK_Aggregates] PRIMARY KEY CLUSTERED 
(
	[UUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


