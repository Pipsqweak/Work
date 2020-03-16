class DataAccess
{
    hidden [DBConnection] $db = $null

    hidden [System.Data.DataTable] $aliases = $null
    hidden [System.Data.DataTable] $groupMembers = $null
    hidden [System.Data.DataTable] $identities = $null
    hidden [System.Data.DataTable] $paths = $null
    hidden [System.Data.DataTable] $rights = $null
    hidden [System.Data.DataTable] $servers = $null

    static [DataAccess] $instance = $null

    static [DataAccess] Me()
    {
        if($null -eq [DataAccess]::instance)
        {
            [DataAccess]::instance = [DataAccess]::new()
        }
        else
        {
            # Nothing...singleton, there can be only one!
        }

        return [DataAccess]::instance
    }

    static [Boolean] IsInitialized()
    {
        return ($null -ne [DataAccess]::Me().db)
    }

    static [void] Init([String] $dbConnectionString)
    {
        if(-not [String]::IsNullOrEmpty($dbConnectionString))
        {
            if(-not [DataAccess]::IsInitialized())
            {
                [DataAccess]::Me().db = [DBConnection]::new($dbConnectionString)

                [DataAccess]::Me().aliases = [DataAccess]::Me().db.GetDataTable("SELECT * FROM Aliases")
                [DataAccess]::Me().identities = [DataAccess]::Me().db.GetDataTable("SELECT * FROM Identities")
                [DataAccess]::Me().groupMembers = [DataAccess]::Me().db.GetDataTable("SELECT * FROM GroupMembers")
                [DataAccess]::Me().paths = [DataAccess]::Me().db.GetDataTable("SELECT * FROM Paths")
                [DataAccess]::Me().rights = [DataAccess]::Me().db.GetDataTable("SELECT * FROM Rights")
                [DataAccess]::Me().servers = [DataAccess]::Me().db.GetDataTable("SELECT * FROM Servers")
            }
            else
            {
                [Log]::Warning("DataAccess has already been initialized.")
            }
        }
        else
        {
            [Log]::Error("Missing connection string in {0}" -f $MyInvocation.MyCommand)
        }
    }

    static [System.Data.DataRow[]] GetRows_ByColumn([System.Data.DataTable] $dt, [String] $colName, [System.Object] $val)
    {
        if($val -is [String])
        {
            $select = "{0} = '{1}'" -f @($colName, $val)
        }
        else
        {
            $select = "{0} = {1}" -f @($colName, $val)
        }
        [System.Data.DataRow[]] $rows = $dt.Select($select)

        return $rows
    }

    static [System.Data.DataRow[]] GetIdentityRow_ByName([String] $name)
    {
        return [DataAccess]::GetRows_ByColumn([DataAccess]::Me().identities, "Name", $name)
    }

    static [System.Int32] MarkAllDeleted()
    {
        $markedDeletedCount = 0
        if([DataAccess]::IsInitialized())
        {
            $tablesToUpdate = @("Servers","Aliases","Identities","Paths")
            $lastUpdated = [DateTime]::Now

            foreach($table in $tablesToUpdate)
            {
                $query = "UPDATE {0} SET IsDeleted=1, LastUpdated='{1}' WHERE IsDeleted=0" -f $table, $lastUpdated.ToString("yyyy-MM-dd HH:mm:ss.fff")
                $markedDeletedCount += [DataAccess]::Me().db.ExecuteNonQuery($query)
            }
        }
        else
        {
            [Log]::Warning("DataAccess must be initialized prior to use.")
        }

        return $markedDeletedCount
    }

    static [System.Int32] MarkSharePathsDeleted([String] $pathToCheck)
    {
        $markedDeletedCount = 0
        if([DataAccess]::IsInitialized())
        {
            $lastUpdated = [DateTime]::Now

            $query = "UPDATE Paths SET IsDeleted=1, LastUpdated='{0}' WHERE (IsDeleted=0) AND ((Path = '{1}') OR (Path LIKE '{1}\%'))" -f @($lastUpdated.ToString("yyyy-MM-dd HH:mm:ss.fff"), $pathToCheck)
            $markedDeletedCount = [DataAccess]::Me().db.ExecuteNonQuery($query)
        }
        else
        {
            [Log]::Warning("DataAccess must be initialized prior to use.")
        }

        return $markedDeletedCount
    }

    static [String] GetServerName_ByServerID([Int64] $serverID)
    {
        [String] $serverName = [String]::Empty

        if($serverID -ge 0)
        {
            $serverNames = [DataAccess]::Me().db.GetDataTable("SELECT Name FROM Servers WHERE ID = '{0}'" -f $serverID)
            if($serverNames.Rows.Count -eq 1)
            {
                $serverName = $serverNames.Rows[0].Name
            }
            elseif($serverNames.Rows.Count -gt 1)
            {
                [Log]::Warning("Multiple servers ({0}) detected with name: {1}" -f @($serverNames.Rows.Count, $serverName))
            }
            else
            {
                # Nothing, server not found, return [String]::Empty
            }
        }
        else
        {
            [Log]::Warning("Attempt to retrieve server name with invalid ServerID {0}." -f @($serverID))
        }

        return $serverName
    }

    static [Int64] GetServerID_ByServerName([String] $serverName)
    {
        [Int64] $serverID = -1

        if(-not [String]::IsNullOrEmpty($serverName))
        {
            $serverIDs = [DataAccess]::Me().db.GetDataTable("SELECT ID FROM Servers WHERE Name = '{0}'" -f $serverName)
            if($serverIDs.Rows.Count -eq 1)
            {
                $serverID = $serverIDs.Rows[0].ID
            }
            elseif($serverIDs.Rows.Count -gt 1)
            {
                [Log]::Warning("Multiple servers ({0}) detected with name: {1}" -f @($serverIDs.Rows.Count, $serverName))
            }
            else
            {
                # Nothing, server not found, return -1
            }
        }
        else
        {
            [Log]::Warning("Attempt to retrieve server ID with null/empty server name.")
        }

        return $serverID
    }

    static [String] GetPath_ByPathID([Int64] $pathID)
    {
        [String] $path = [String]::Empty

        if($pathID -ge 0)
        {
            $tPaths = [DataAccess]::Me().db.DataTable("SELECT Path FROM Paths WHERE ID = '{0}'" -f $pathID)
            if($tPaths.Rows.Count -eq 1)
            {
                $path = $tPaths.Rows[0].Path
            }
            elseif($tPaths.Rows.Count -gt 1)
            {
                [Log]::Warning("Multiple paths ({0}) detected for PathID: {1}" -f @($tPaths.Rows.Count, $pathID))
            }
            else
            {
                # Nothing, path not found, [String]::Empty
            }
        }
        else
        {
            [Log]::Warning("Attempt to retrieve path with invalid PathID: {0}." -f @($pathID))
        }

        return $path
    }

    static [Int64] GetPathID_ByServerIDAndPathName([Int64] $serverID, [String] $path)
    {
        [Int64] $pathID = -1

        if($serverID -ge 0)
        {
            if(-not [String]::IsNullOrEmpty($path))
            {
                $pathIDs = [DataAccess]::Me().db.GetDataTable("SELECT ID FROM Paths WHERE (Path = '{0}') AND (ServerID = {1})" -f $path, $serverID)
                if($pathIDs.Rows.Count -eq 1)
                {
                    $pathID = $pathIDs.Rows[0].ID
                }
                elseif($pathIDs.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple paths ({0}) detected for ServerID: {1}, Path: {2}" -f @($pathIDs.Rows.Count, $serverID, $path))
                }
                else
                {
                    # Nothing, path not found, return -1
                }
            }
            else
            {
                [Log]::Warning("Attempt to retrieve path ID with null/empty path.")
            }
        }
        else
        {
            [Log]::Warning("Attempt to retrieve path ID with invalid ServerID: {0}" -f @($serverID))
        }

        return $pathID
    }

    static [Int64] GetPathID_ByServerNameAndPathName([String] $serverName, [String] $path)
    {
        [Int64] $pathID = -1

        if(-not [String]::IsNullOrEmpty($serverName))
        {
            if(-not [String]::IsNullOrEmpty($path))
            {
                $pathIDs = [DataAccess]::Me().db.GetDataTable("SELECT Paths.ID FROM Paths INNER JOIN Servers ON Paths.ServerID = Servers.ID WHERE (Paths.Path = '{0}') AND (Servers.Name = '{1}')" -f @($path, $serverName))
                if($pathIDs.Rows.Count -eq 1)
                {
                    $pathID = $pathIDs.Rows[0].ID
                }
                elseif($pathIDs.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple paths ({0}) detected for server: {1}, path: {2}" -f @($pathIDs.Rows.Count, $serverName, $path))
                }
                else
                {
                    # Nothing, path not found, return -1
                }
            }
            else
            {
                [Log]::Warning("Attempt to retrieve path ID with null/empty path.")
            }
        }
        else
        {
            [Log]::Warning("Attempt to retrieve path ID with null/empty server name.")
        }

        return $pathID
    }

    static [Int64] AddUpdateServer([String] $serverName)
    {
        [Int64] $serverID = -1

        if(-not [String]::IsNullOrEmpty($serverName))
        {
            $params = @( [DBConnection]::CreateParam("serverName", $serverName))
            $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdateServer", $params)
            if($null -ne $tmpDT)
            {
                if($tmpDT.Rows.Count -eq 1)
                {
                    if($tmpDT.Columns.Contains("ID"))
                    {
                        $serverID = $tmpDT.Rows[0].ID
                    }
                    else
                    {
                        # Must have been an error (ExecuteStoredProcedure already logged it.)
                        # return -1
                    }
                }
                elseif($tmpDT.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple servers found in database with name: {0}" -f @($serverName))
                }
                else
                {
                    # Nothing, return -1
                }
            }
            else
            {
                # Nothing, return -1
            }
        }
        else
        {
            [Log]::Warning("Attempt to add server with no name.")
        }

        return $serverID
    }

    static [Int64] AddUpdateIdentity([String] $identityName)
    {
        [Int64] $identityID = -1

        if(-not [String]::IsNullOrEmpty($identityName))
        {
            $params = @( [DBConnection]::CreateParam("identityName", $identityName))
            $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdateIdentity", $params)
            if($null -ne $tmpDT)
            {
                if($tmpDT.Rows.Count -eq 1)
                {
                    if($tmpDT.Columns.Contains("ID"))
                    {
                        $identityID = $tmpDT.Rows[0].ID
                    }
                    else
                    {
                        # Must have been an error (ExecuteStoredProcedure already logged it.)
                        # return -1
                    }
                }
                elseif($tmpDT.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple identities found in database with name: {0}" -f @($identityName))
                }
                else
                {
                    # Nothing, return -1
                }
            }
            else
            {
                # Nothing, return -1
            }
        }
        else
        {
            [Log]::Warning("Attempt to add identity with no name.")
        }

        return $identityID
    }

    static [Int64] AddUpdatePath([Int64] $serverID, [String] $path, [Boolean] $inheritanceBroken)
    {
        [Int64] $pathID = -1

        if(-not [String]::IsNullOrEmpty($path))
        {
            $params = @(
                [DBConnection]::CreateParam("serverID", $serverID),
                [DBConnection]::CreateParam("path", $path),
                [DBConnection]::CreateParam("inheritanceBroken", $inheritanceBroken)
            )
            $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdatePath", $params)
            if($null -ne $tmpDT)
            {
                if($tmpDT.Rows.Count -eq 1)
                {
                    if($tmpDT.Columns.Contains("ID"))
                    {
                        $pathID = $tmpDT.Rows[0].ID
                    }
                    else
                    {
                        # Must have been an error (ExecuteStoredProcedure already logged it.)
                        # return -1
                    }
                }
                elseif($tmpDT.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple paths found in database with server ID: {0} path: {1}" -f @($serverID, $path))
                }
                else
                {
                    # Nothing, return -1
                }
            }
            else
            {
                # Nothing, return -1
            }
        }
        else
        {
            [Log]::Warning("Attempt to add/update path with no path.")
        }

        return $pathID
    }

    static [Int64] AddUpdateServerAlias([Int64] $serverID, [String] $alias)
    {
        [Int64] $aliasID = -1

        if(-not [String]::IsNullOrEmpty($alias))
        {
            $params = @(
                [DBConnection]::CreateParam("serverID", $serverID),
                [DBConnection]::CreateParam("alias", $alias)
            )
            $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdateAlias", $params)
            if($null -ne $tmpDT)
            {
                if($tmpDT.Rows.Count -eq 1)
                {
                    if($tmpDT.Columns.Contains("ID"))
                    {
                        $aliasID = $tmpDT.Rows[0].ID
                    }
                    else
                    {
                        # Must have been an error (ExecuteStoredProcedure already logged it.)
                        # return -1
                    }
                }
                elseif($tmpDT.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple aliases found in database with server ID: {0} alias: {1}" -f @($serverID, $alias))
                }
                else
                {
                    # Nothing, return -1
                }
            }
            else
            {
                # Nothing, return -1
            }
        }
        else
        {
            [Log]::Warning("Attempt to add/update blank alias.")
        }

        return $aliasID
    }

    static [Int64] AddUpdateRight([Int64] $pathID, [Int64] $identityID, [String] $aclType, [String] $right)
    {
        [Int64] $rowCount = 0

        if(-not [String]::IsNullOrEmpty($right))
        {
            $params = @(
                [DBConnection]::CreateParam("pathID", $pathID),
                [DBConnection]::CreateParam("identityID", $identityID),
                [DBConnection]::CreateParam("aclType", $aclType)
                [DBConnection]::CreateParam("right", $right)
            )
            $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdateRight", $params)
            if($null -ne $tmpDT)
            {
                if($tmpDT.Rows.Count -eq 1)
                {
                    if($tmpDT.Columns.Contains("RowCount"))
                    {
                        $rowCount = $tmpDT.Rows[0].RowCount
                    }
                    else
                    {
                        # Must have been an error (ExecuteStoredProcedure already logged it.)
                        # return -1
                    }
                }
                elseif($tmpDT.Rows.Count -gt 1)
                {
                    [Log]::Warning("Multiple 'RowCount' values return in AddUpdateRights for path ID: {0}, identity ID: {1}, aclType: {2}, right: {3}" -f @($pathID, $identityID, $aclType, $right))
                }
                else
                {
                    # Nothing, return 0
                }
            }
            else
            {
                # Nothing, return 0
            }
        }
        else
        {
            [Log]::Warning("Attempt to add/update empty right.")
        }

        return $rowCount
    }

    static [Int64] AddUpdateGroupMember([String] $groupName, [String] $identityName)
    {
        [Int64] $rowCount = 0
        [Int64] $groupID = -1
        [Int64] $identityID = -1

        if(-not [String]::IsNullOrEmpty($groupName))
        {
            if(-not [String]::IsNullOrEmpty($identityName))
            {
                $groupID = [DataAccess]::AddUpdateIdentity($groupName)
                if($groupID -gt 0)
                {
                    $identityID = [DataAccess]::AddUpdateIdentity($identityName)
                    if($identityID -gt 0)
                    {
                        $rowCount = [DataAccess]::AddUpdateGroupMember($groupID, $identityID)
                    }
                    else
                    {
                        # Nothing warning already logged
                    }
                }
                else
                {
                    # Nothing warning already logged
                }
            }
            else
            {
                [Log]::Warning("Attempt to add/update group member with blank identity name")
            }
        }
        else
        {
            [Log]::Warning("Attempt to add/update group member with blank group name")
        }
        return $rowCount
    }

    static [Int64] AddUpdateGroupMember([Int64] $groupID, [Int64] $identityID)
    {
        [Int64] $rowCount = 0

        $params = @(
            [DBConnection]::CreateParam("groupID", $groupID),
            [DBConnection]::CreateParam("identityID", $identityID)
        )
        $tmpDT = [DataAccess]::Me().db.ExecuteStoredProcedure("AddUpdateGroupMember", $params)
        if($null -ne $tmpDT)
        {
            if($tmpDT.Rows.Count -eq 1)
            {
                if($tmpDT.Columns.Contains("RowCount"))
                {
                    $rowCount = $tmpDT.Rows[0].RowCount
                }
                else
                {
                    # Must have been an error (ExecuteStoredProcedure already logged it.)
                    # return -1
                }
            }
            elseif($tmpDT.Rows.Count -gt 1)
            {
                [Log]::Warning("Multiple 'RowCount' values returned in AddUpdateGroupMember for group ID: {0}, identity ID: {1}" -f @($groupID, $identityID))
            }
            else
            {
                # Nothing, return 0
            }
        }
        else
        {
            # Nothing, return 0
        }

        return $rowCount
    }
}
