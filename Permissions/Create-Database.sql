USE [master]
GO
/****** Object:  Database [PEI-FF-Permissions]    Script Date: 9/27/2019 4:20:38 PM ******/
CREATE DATABASE [PEI-FF-Permissions]
 CONTAINMENT = NONE
 ON  PRIMARY
( NAME = N'PEI-FF-Permissions', FILENAME = N'D:\SQL Data\PEI-FF-Permissions.mdf' , SIZE = 12288KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
 LOG ON
( NAME = N'PEI-FF-Permissions_log', FILENAME = N'L:\SQL Logs\PEI-FF-Permissions_log.ldf' , SIZE = 267456KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
GO
ALTER DATABASE [PEI-FF-Permissions] SET COMPATIBILITY_LEVEL = 120
GO
IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [PEI-FF-Permissions].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO
ALTER DATABASE [PEI-FF-Permissions] SET ANSI_NULL_DEFAULT OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET ANSI_NULLS OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET ANSI_PADDING OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET ANSI_WARNINGS OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET ARITHABORT OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET AUTO_CLOSE OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET AUTO_SHRINK OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET AUTO_UPDATE_STATISTICS ON
GO
ALTER DATABASE [PEI-FF-Permissions] SET CURSOR_CLOSE_ON_COMMIT OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET CURSOR_DEFAULT  GLOBAL
GO
ALTER DATABASE [PEI-FF-Permissions] SET CONCAT_NULL_YIELDS_NULL OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET NUMERIC_ROUNDABORT OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET QUOTED_IDENTIFIER OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET RECURSIVE_TRIGGERS OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET  DISABLE_BROKER
GO
ALTER DATABASE [PEI-FF-Permissions] SET AUTO_UPDATE_STATISTICS_ASYNC OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET DATE_CORRELATION_OPTIMIZATION OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET TRUSTWORTHY OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET ALLOW_SNAPSHOT_ISOLATION OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET PARAMETERIZATION SIMPLE
GO
ALTER DATABASE [PEI-FF-Permissions] SET READ_COMMITTED_SNAPSHOT OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET HONOR_BROKER_PRIORITY OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET RECOVERY FULL
GO
ALTER DATABASE [PEI-FF-Permissions] SET  MULTI_USER
GO
ALTER DATABASE [PEI-FF-Permissions] SET PAGE_VERIFY CHECKSUM
GO
ALTER DATABASE [PEI-FF-Permissions] SET DB_CHAINING OFF
GO
ALTER DATABASE [PEI-FF-Permissions] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF )
GO
ALTER DATABASE [PEI-FF-Permissions] SET TARGET_RECOVERY_TIME = 0 SECONDS
GO
ALTER DATABASE [PEI-FF-Permissions] SET DELAYED_DURABILITY = DISABLED
GO
USE [PEI-FF-Permissions]
GO
/****** Object:  UserDefinedTableType [dbo].[BigIntList]    Script Date: 9/27/2019 4:20:39 PM ******/
CREATE TYPE [dbo].[BigIntList] AS TABLE(
	[bi] [bigint] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[GroupMemberList]    Script Date: 9/27/2019 4:20:39 PM ******/
CREATE TYPE [dbo].[GroupMemberList] AS TABLE(
	[GroupID] [bigint] NULL,
	[IdentityID] [bigint] NULL
)
GO
/****** Object:  Table [dbo].[Aliases]    Script Date: 9/27/2019 4:20:40 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Aliases](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[Alias] [nvarchar](max) NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[ServerID] [bigint] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_Aliases] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[GroupMembers]    Script Date: 9/27/2019 4:20:40 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[GroupMembers](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[GroupID] [bigint] NOT NULL,
	[IdentityID] [bigint] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_GroupMembers] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Identities]    Script Date: 9/27/2019 4:20:40 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Identities](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](max) NOT NULL,
	[DisplayName] [nvarchar](max) NULL,
	[IsDeleted] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_Identities] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Paths]    Script Date: 9/27/2019 4:20:40 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Paths](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[Path] [nvarchar](max) NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[ServerID] [bigint] NOT NULL,
	[InheritanceBroken] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_Paths_1] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Rights]    Script Date: 9/27/2019 4:20:40 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Rights](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[PathID] [bigint] NOT NULL,
	[IdentityID] [bigint] NOT NULL,
	[Right] [nvarchar](max) NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_Rights] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[Servers]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Servers](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](max) NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[LastUpdated] [datetime] NOT NULL,
 CONSTRAINT [PK_Servers] PRIMARY KEY CLUSTERED
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
ALTER TABLE [dbo].[Aliases] ADD  CONSTRAINT [DF_Aliases_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[Aliases] ADD  CONSTRAINT [DF_Aliases_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
ALTER TABLE [dbo].[GroupMembers] ADD  CONSTRAINT [DF_GroupMembers_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[GroupMembers] ADD  CONSTRAINT [DF_GroupMembers_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
ALTER TABLE [dbo].[Identities] ADD  CONSTRAINT [DF_Identities_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[Identities] ADD  CONSTRAINT [DF_Identities_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
ALTER TABLE [dbo].[Paths] ADD  CONSTRAINT [DF_Paths_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[Paths] ADD  CONSTRAINT [DF_Paths_InheritanceBroken]  DEFAULT ((1)) FOR [InheritanceBroken]
GO
ALTER TABLE [dbo].[Paths] ADD  CONSTRAINT [DF_Paths_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
ALTER TABLE [dbo].[Rights] ADD  CONSTRAINT [DF_Rights_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[Rights] ADD  CONSTRAINT [DF_Rights_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
ALTER TABLE [dbo].[Servers] ADD  CONSTRAINT [DF_Servers_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[Servers] ADD  CONSTRAINT [DF_Servers_LastUpdated]  DEFAULT (getdate()) FOR [LastUpdated]
GO
/****** Object:  StoredProcedure [dbo].[AddUpdateAlias]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sept 4
-- Description:	Add or update a server alias record
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdateAlias]
	@serverID bigint,
	@alias nvarchar(max)
AS
BEGIN
    DECLARE @serverCount int
	SET NOCOUNT ON;

    SELECT @serverCount = COUNT(ID) FROM Servers WHERE (ID = @serverID)

	BEGIN TRAN
		IF (@serverCount > 0)
			BEGIN
				-- First try to update the identity's row ...
				UPDATE [Aliases] SET [IsDeleted] = 0, [LastUpdated] = GETDATE() WHERE (Alias = @alias) AND ([ServerID] = @serverID);

				-- If the update failed, then create a new record
				IF @@ROWCOUNT = 0
					BEGIN
						INSERT INTO [Aliases] ([Alias] ,[ServerID]) VALUES (@alias ,@serverID)
					END

                SELECT ID FROM Aliases WHERE (Alias = @alias) AND (ServerID = @serverID)
			END;
        ELSE
            BEGIN
                SELECT 'Server ID ' + CAST(@serverID as varchar) + ' not found' as [ERROR]
            END;
	COMMIT TRAN
END
GO
/****** Object:  StoredProcedure [dbo].[AddUpdateGroupMember]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sep 12
-- Description:	Add/Update Group member
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdateGroupMember]
	@groupID bigint,
	@identityID bigint
AS
BEGIN
	DECLARE @groupCount int
	DECLARE @identityCount int
    SET NOCOUNT ON;

    SELECT @groupCount = COUNT(ID) FROM Identities WHERE (ID = @groupID)
    SELECT @identityCount = COUNT(ID) FROM Identities WHERE (ID = @identityID)

    BEGIN TRAN
        IF (@groupCount > 0)
            BEGIN
                IF (@identityCount > 0)
                    BEGIN
				        -- First try to update the identity's row ...
				        UPDATE [GroupMembers] SET [LastUpdated] = GETDATE(), [IsDeleted] = 0 WHERE ([GroupID] = @groupID) AND ([IdentityID] = @identityID)

				        -- If the update failed, then create a new record
				        IF @@ROWCOUNT = 0
					        BEGIN
						        INSERT INTO [GroupMembers] ([GroupID] ,[IdentityID]) VALUES (@groupID, @identityID)
        			        END;
                    END
                ELSE
                    BEGIN
                        SELECT 'Identity ID ' + CAST(@identityID as varchar) + ' not found' as [ERROR]
                    END;
            END
        ELSE
            BEGIN
                SELECT 'Group ID ' + CAST(@groupID as varchar) + ' not found' as [ERROR]
            END;
    COMMIT
    SELECT COUNT(GroupID) as [RowCount] FROM GroupMembers WHERE (GroupID = @groupID) AND (IdentityID = @identityID)
END

GO
/****** Object:  StoredProcedure [dbo].[AddUpdateIdentity]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sept 4
-- Description:	Add or update an identity record
--     Does not use or update DisplayName.
--     This SP is mostly intended to be called from the powershell scanner script.
--        This is to avoid the overhead of having the powershell script query AD
--
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdateIdentity]
	@identityName nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRAN
		-- First try to update the identity's row ...
		UPDATE [Identities] SET [IsDeleted] = 0, [LastUpdated] = GETDATE() WHERE [Name] = @identityName

		-- If the update failed, then create a new record
		IF @@ROWCOUNT = 0
			BEGIN
				INSERT INTO [Identities] ([Name]) VALUES (@identityName)
			END;

        SELECT ID FROM Identities WHERE (Name = @identityName)
	COMMIT TRAN
END


GO
/****** Object:  StoredProcedure [dbo].[AddUpdatePath]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sept 4
-- Description:	Add or update a path record
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdatePath]
	@serverID bigint,
	@path nvarchar(max),
    @inheritanceBroken bit
AS
BEGIN
	DECLARE @serverCount int
	SET NOCOUNT ON;

    SELECT @serverCount = COUNT(ID) FROM Servers WHERE (ID = @serverID)

	BEGIN TRAN
        IF (@serverCount > 0)
            BEGIN
				-- First try to update the identity's row ...
				UPDATE [Paths] SET [IsDeleted] = 0, [LastUpdated] = GETDATE(), [InheritanceBroken] = @inheritanceBroken WHERE ([Path] = @path) AND ([ServerID] = @serverID);

				-- If the update failed, then create a new record
				IF @@ROWCOUNT = 0
					BEGIN
						INSERT INTO [Paths] ([Path] ,[ServerID], [InheritanceBroken]) VALUES (@path ,@serverID, @inheritanceBroken)
					END;

            	SELECT p.ID From Paths p INNER JOIN Servers s ON p.ServerID = s.ID WHERE (p.Path = @path) AND (p.ServerID = @serverID)
            END;
        ELSE
            BEGIN
                SELECT 'Server ID ' + CAST(@serverID as varchar) + ' not found' as [ERROR]
            END;
	COMMIT TRAN
END
GO
/****** Object:  StoredProcedure [dbo].[AddUpdateRight]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sept 4
-- Description:	Add or update a path record
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdateRight]
	@pathID bigint,
    @identityID bigint,
    @right nvarchar(max)
AS
BEGIN
	DECLARE @identityCount int
    DECLARE @pathCount int
    SET NOCOUNT ON;

    SELECT @identityCount = COUNT(ID) FROM Identities WHERE (ID = @identityID)
    SELECT @pathCount = COUNT(ID) FROM Paths WHERE (ID = @pathID)

	BEGIN TRAN
		IF (@identityCount > 0)
			BEGIN
                IF (@pathCount > 0)
                    BEGIN
				        -- First try to update the identity's row ...
				        UPDATE [Rights] SET [LastUpdated] = GETDATE() WHERE ([PathID] = @pathID) AND ([IdentityID] = @identityID) AND ([Right] = @right)

				        -- If the update failed, then create a new record
				        IF @@ROWCOUNT = 0
					        BEGIN
						        INSERT INTO [Rights] ([PathID] ,[IdentityID], [Right]) VALUES (@pathID ,@identityID, @right)
					        END;

	                    SELECT
                            Count(r.[Right]) as [RowCount]
                        FROM
                            Rights r
                        WHERE
                                (r.[Right] = @right)
                            AND (r.PathID = @pathID)
                            AND (r.IdentityID = @identityID)

			        END;
                ELSE
                    BEGIN
                        SELECT 'Path ID ' + CAST(@pathID as varchar) + ' not found' as [ERROR]
                    END;
            END;
        ELSE
            BEGIN
                SELECT 'Identity ID ' + CAST(@identityID as varchar) + ' not found' as [ERROR]
            END;
	COMMIT TRAN
END
GO
/****** Object:  StoredProcedure [dbo].[AddUpdateServer]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sept 4
-- Description:	Add or update a server record
-- =============================================
CREATE PROCEDURE [dbo].[AddUpdateServer]
	@serverName nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRAN
		-- First try to update the server's row ...
		UPDATE [Servers] SET [IsDeleted] = 0, [LastUpdated] = GETDATE() WHERE [Name] = @serverName

		-- If the update failed, then create a new record
		IF @@ROWCOUNT = 0
			BEGIN
				INSERT INTO [Servers] ([Name]) VALUES (@serverName)
			END;
	COMMIT TRAN
    SELECT ID FROM Servers WHERE (Name = @serverName)
END

GO
/****** Object:  StoredProcedure [dbo].[GetGroupMember_ByGroupID]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sep 12
-- Description:	Get group members by group ID
-- =============================================
CREATE PROCEDURE [dbo].[GetGroupMember_ByGroupID]
	@groupID bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.* FROM Identities i INNER JOIN GroupMembers gm ON (gm.IdentityID = i.ID) INNER JOIN Identities g ON (g.ID = gm.GroupID) WHERE (g.ID = @groupID)
END

GO
/****** Object:  StoredProcedure [dbo].[GetGroupMember_ByGroupName]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 2019 Sep 12
-- Description:	Get group members by group name
-- =============================================
CREATE PROCEDURE [dbo].[GetGroupMember_ByGroupName]
	@groupName nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.* FROM Identities i INNER JOIN GroupMembers gm ON (gm.IdentityID = i.ID) INNER JOIN Identities g ON (g.ID = gm.GroupID) WHERE (g.Name = @groupName)
END

GO
/****** Object:  StoredProcedure [dbo].[MarkAllDeleted]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[MarkAllDeleted]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	UPDATE [Servers] SET [IsDeleted] = 1 WHERE [IsDeleted] = 0;
    -- Trigger on Servers will set all paths for server as IsDeleted
        -- Trigger on Paths will delete all Rights for Paths
    -- Trigger on Servers will set all aliases for server as IsDeleted

	UPDATE [Identities] SET [IsDeleted] = 1 WHERE [IsDeleted] = 0;
    -- Trigger on Identities will delete all GroupMembers where Identity.ID is GroupID or IdentityID
END

GO
/****** Object:  StoredProcedure [dbo].[Reset_All]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 16 Sept 2019
-- Description:	Reset database
-- =============================================
CREATE PROCEDURE [dbo].[Reset_All]
AS
BEGIN
	SET NOCOUNT ON;
    TRUNCATE TABLE Servers;
    DBCC CHECKIDENT ('Servers', RESEED, 1)
    TRUNCATE TABLE Identities;
    DBCC CHECKIDENT ('Identities', RESEED, 1)
    TRUNCATE TABLE Rights;
    DBCC CHECKIDENT ('Rights', RESEED, 1)
    TRUNCATE TABLE Paths;
    DBCC CHECKIDENT ('Paths', RESEED, 1)
    TRUNCATE TABLE GroupMembers;
    DBCC CHECKIDENT ('GroupMembers', RESEED, 1)
    TRUNCATE TABLE Aliases;
    DBCC CHECKIDENT ('Aliases', RESEED, 1)
END

GO
/****** Object:  StoredProcedure [dbo].[TouchGroupMembers]    Script Date: 9/27/2019 4:20:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Briney, Ken
-- Create date: 18 Sept 2019
-- Description:
--        UPDATE Identites SET IsDeleted = 0, LastUpdated = @lastUpdated for each GroupID and IdentityID in @groupMemberList
--        UPDATE GroupMembers SET IsDeleted = 0, LastUpdated = @lastUpdated for each row with ID in @groupMemberList
-- =============================================
CREATE PROCEDURE [dbo].[TouchGroupMembers]
    @lastUpdated as DateTime,
    @groupMemberList AS dbo.GroupMemberList READONLY
AS
BEGIN
	SET NOCOUNT ON;
    DECLARE @gID bigint
    DECLARE @mID bigint
    DECLARE gmCursor CURSOR LOCAL FAST_FORWARD FOR SELECT [GroupID], [IdentityID] FROM @groupMemberList;

    OPEN gmCursor;
    WHILE 1=1
        BEGIN
            FETCH NEXT FROM gmCursor INTO @gID,@mID;
            IF @@FETCH_STATUS = -1 BREAK
            UPDATE Identities SET IsDeleted = 0, LastUpdated = @lastUpdated WHERE (ID = @gID) OR (ID = @mID);
            UPDATE GroupMembers SET IsDeleted = 0, LastUpdated =@lastUpdated WHERE (GroupID = @gID) AND (IdentityID = @mID);
        END;
    CLOSE gmCursor;
    DEALLOCATE gmCursor;
END

GO
USE [master]
GO
ALTER DATABASE [PEI-FF-Permissions] SET  READ_WRITE
GO
