USE [StorageInformation]
GO

/****** Object:  Table [dbo].[DataCollectionRuns]    Script Date: 6/7/2021 2:23:34 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DataCollectionRuns](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CollectionDT] [datetime] NULL,
 CONSTRAINT [PK_DataCollectionRuns] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


