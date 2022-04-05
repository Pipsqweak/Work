USE [StorageInformation]
GO

/****** Object:  Table [dbo].[VirtualMachineData]    Script Date: 6/7/2021 3:08:40 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[VirtualMachineData](
	[RunID] [int] NOT NULL,
	[VirtualMachineID] [nvarchar](100) NOT NULL,
	[PowerState] [nvarchar](50) NOT NULL
) ON [PRIMARY]
GO

/****** Object:  Index [IX_RunID]    Script Date: 6/7/2021 3:08:47 PM ******/
CREATE NONCLUSTERED INDEX [IX_RunID] ON [dbo].[VirtualMachineData]
(
	[RunID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Index [IX_VirtualMachineID]    Script Date: 6/7/2021 3:08:57 PM ******/
CREATE NONCLUSTERED INDEX [IX_VirtualMachineID] ON [dbo].[VirtualMachineData]
(
	[VirtualMachineID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
