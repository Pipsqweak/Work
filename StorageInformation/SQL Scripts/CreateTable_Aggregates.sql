USE [StorageInformation]
GO

/****** Object:  Table [dbo].[Aggregates]    Script Date: 11/1/2022 1:32:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Aggregates](
	[UUID] [uniqueidentifier] NOT NULL,
	[ClusterUUID] [uniqueidentifier] NOT NULL,
	[Name] [nvarchar](100) NOT NULL,
	[SnaplockType] [nvarchar](50) NULL,
 CONSTRAINT [PK_Aggregates] PRIMARY KEY CLUSTERED 
(
	[UUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

