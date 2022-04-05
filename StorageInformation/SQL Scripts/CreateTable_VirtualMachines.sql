USE [StorageInformation]
GO

/****** Object:  Table [dbo].[VirtualMachines]    Script Date: 6/7/2021 2:20:26 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[VirtualMachines](
	[ID] [nvarchar](100) NOT NULL,
	[Name] [nvarchar](100) NOT NULL,
 CONSTRAINT [PK_VirtualMachines] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


