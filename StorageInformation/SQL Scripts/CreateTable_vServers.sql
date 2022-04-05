USE [StorageInformation]
GO

/****** Object:  Table [dbo].[VServers]    Script Date: 6/7/2021 2:16:22 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[VServers](
	[UUID] [uniqueidentifier] NOT NULL,
	[ClusterUUID] [uniqueidentifier] NOT NULL,
	[Name] [nvarchar](100) NOT NULL,
	[Type] [nvarchar](50) NOT NULL,
 CONSTRAINT [PK_VServers] PRIMARY KEY CLUSTERED 
(
	[UUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


