USE [StorageInformation]
GO

/****** Object:  Table [dbo].[Clusters]    Script Date: 11/1/2022 1:34:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Clusters](
	[UUID] [uniqueidentifier] NOT NULL,
	[Location] [nvarchar](100) NULL,
	[SerialNumber] [nvarchar](100) NOT NULL,
	[Contact] [nvarchar](100) NULL,
	[Name] [nvarchar](100) NOT NULL,
 CONSTRAINT [PK_Clusters] PRIMARY KEY CLUSTERED 
(
	[UUID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


