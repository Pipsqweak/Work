function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KB","MB","GB","TB","PB","EB","ZB","YB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}


function ExecuteNonQuery
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DBConnection]
        $dbConn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlCommand]
        $cmd
    )

    $result = $null
    if($this.Open())
    {
        $completed = $false
        $tries = 0
        do
        {
            try
            {
                $result = $cmd.ExecuteNonQuery()
                $completed = $true
            }
            catch
            {
                $tries++

                # Sleep a random period of time to let other transactions complete...
                $sleepMS = Get-Random -Minimum 3 -Maximum 10
                Start-Sleep -Milliseconds $sleepMS
            }
        }
        while((-not $completed) -and ($tries -lt [DBConnection]::maxRetries))
        $cmd.Dispose()
        $this.Close()
    }
    else
    {
        [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
    }

    return $result
}

function UpdatePrincipalsFromAD
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DBConnection]
        $dbConn
    )

    $added = 0
    $updated = 0
    $deleted = 0
    try
    {
        $adDomainName = (Get-ADDomain -ErrorAction Stop).NetBIOSName

        if(-not [String]::IsNullOrEmpty($adDomainName))
        {
            $adObjects = [System.Collections.Generic.List[Microsoft.ActiveDirectory.Management.ADObject]]::new()
            $adObjects = [System.Collections.Generic.SortedDictionary[[System.String],[Microsoft.ActiveDirectory.Management.ADObject]]]::new()
            try
            {
                $adUsers = @(Get-ADUser -Filter * -ErrorAction Stop)
                [Log]::Info("AD Users: {0}" -f @($adUsers.Length))
                $adUsers | Foreach-Object { $adObjects.Add($_.SID.Value, $_) }

                try
                {
                    $adGroups = @(Get-ADGroup -Filter * -ErrorAction Stop)
                    [Log]::Info("AD Groups: {0}" -f @($adGroups.Length))
                    $adGroups | Foreach-Object { $adObjects.Add($_.SID.Value, $_) }

                    $sidKeys = @($adObjects.Keys)

                    $principals = $dbConn.GetDataTable("SELECT * FROM Principal")
                    [Log]::Info("Principals: {0}" -f @($principals.Rows.Count))

                    $insertCmd = $dbConn.connection.CreateCommand()
                    $insertCmd.CommandType = [System.Data.CommandType]::Text
                    $insertCmd.CommandText = "INSERT INTO Principal (Name, Domain, SamAccountName, SID) OUTPUT INSERTED.ID VALUES (@Name, @Domain, @SamAccountName, @SID)"

                    $updateCmd = $dbConn.connection.CreateCommand()
                    $updateCmd.CommandType = [System.Data.CommandType]::Text
                    $updateCmd.CommandText = "UPDATE Principal SET Name = @Name, Domain = @Domain, SamAccountName = @SamAccountName WHERE (ID = @ID) AND (SID = @SID) OUTPUT "

                    $deleteCmd = $dbConn.connection.CreateCommand()
                    $deleteCmd.CommandType = [System.Data.CommandType]::Text
                    $deleteCmd.CommandText = "UPDATE Principal SET IsDeleted = 1 WHERE (ID={@ID})"

                    # First, add new users/groups and update existing users/groups from AD
                    $a = 0
                    while($a -lt $sidKeys.Length)
                    {
                        $adObj = $adObjects[$sidKeys[$a]]
                        $rows = $principals.Select("SID = '{0}'" -f @($adObj.SID.Value))
                        if($rows.Length -eq 0)
                        {
                            $insertCmd.Parameters.Clear()
                            [void] $insertCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $adObj.Name))
                            [void] $insertCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Domain", $adDomainName))
                            [void] $insertCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@SamAccountName", $adObj.SamAccountName))
                            [void] $insertCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@SID", $adObj.SID.Value))
                            if($null -ne $dbConn.ExecuteScalar($insertCmd))
                            {
                                $added++
                            }
                            else
                            {
                                [Log]::Warning("Failed to add new principal to database")
                                [Log]::Warning(("INSERT INTO Principal (Name, Domain, SamAccountName, SID) VALUES ('{0}', '{1}', '{2}', '{3}')" -f @($adObj.Name, $adDomainName, $adObj.SamAccountName, $adObj.SID.Value)))
                            }
                        }
                        elseif ($rows.Length -eq 1)
                        {
                            # Check row for accuracy...
                            if(($adObj.Name -ne $rows[0].Name) -or ($adDomainName -ne $rows[0].Domain) -or ($adObj.SamAccountName) -ne ($rows[0].SamAccountName))
                            {
                                $updateCmd.Parameters.Clear()
                                [void] $updateCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $adObj.Name))
                                [void] $updateCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Domain", $adDomainName))
                                [void] $updateCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@SamAccountName", $adObj.SamAccountName))
                                [void] $updateCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@ID", $rows[0].ID))
                                [void] $updateCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@SID", $adObj.SID.Value))

                                if($null -ne $dbConn.ExecuteScalar($updateCmd))
                                {
                                    $updated++
                                }
                                else
                                {
                                    [Log]::Warning("Failed to update principal table.")
                                    [Log]::Warning("UPDATE Principal SET Name = '{0}', Domain = '{1}', SamAccountName = '{2}' WHERE (ID={3}) AND (SID = '{4}')" -f @($adObj.Name, $adDomainName, $adObj.SamAccountName, $rows[0].ID, $adObj.SID.Value))
                                }
                            }
                        }
                        $a++
                    }

                    # Get all the principals from the database that are not already marked as deleted.
                    $principals = $dbConn.GetDataTable("SELECT * FROM Principal WHERE (Domain = '{0}') AND (IsDeleted = 0)" -f @($adDomainName))

                    $a = 0
                    while($a -lt $principals.Rows.Count)
                    {
                        if(-not $adObjects.ContainsKey($principals.Rows[$a].SID))
                        {
                            $deleteCmd.Parameters.Clear()
                            [void] $deleteCmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@ID", $principals.Rows[$a].ID))
                            if($null -ne $dbConn.ExecuteScalar($deleteCmd))
                            {
                                $deleted++
                            }
                            else
                            {
                                [Log]::Warning("Failed to mark principal as deleted.")
                                [Log]::Warning(("UPDATE Principal SET IsDeleted = 1 WHERE (ID={0})" -f @($principals.Rows[$a].ID)))
                            }
                        }
                        $a++
                    }

                    [Log]::Info("Updated principals.  Added: {0}, Updated: {1}, Deleted: {2}" -f @($added, $updated, $deleted))
                }
                catch
                {
                    [Log]::Warning("Failed to get groups from active directory.")
                }
            }
            catch
            {
                [Log]::Warning("Failed to get users from active directory.")
            }
        }
        else
        {
            [Log]::Warning("Blank active directory NetBIOSName.")
        }
    }
    catch
    {
        [Log]::Warning("Failed to get active directory domain.")
    }
}

function Get-SecurityIdentifierFromString($acctStr)
{
    $sid = $null

    try
    {
        $ntAcct = [System.Security.Principal.NTAccount]::new($acctStr)
        if($null -ne $ntAcct)
        {
            try
            {
                $sid = $ntAcct.Translate([System.Security.Principal.SecurityIdentifier])
            }
            catch
            {
                # Failed to translate $ntAcct into a SecurityIdentifier
            }
        }
    }
    catch
    {
        # Failed to get NTAccount for $acctStr
    }

    return $sid
}

function TestDBConnectionObject
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [DBConnection]
        $conn
    )

    return (($null -ne $conn) -and ($conn -is [DBConnection]))
}

# Changing \\?\UNC\server\share to \\server\share solves the long path issue...
function RemoveLongUNCPath($str) { return ($str -replace "^\\\\\?\\UNC\\","\\") }

# Changing \\server\share to \\?\UNC\server\share solves the long path issue...
function AddLongUNCPath($str) { $retval = $str; if($str -notmatch "^\\\\\?\\unc\\") { $retval = $str -replace "^\\\\","\\?\UNC\" } return $retval }

function IsRootFSI
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.IO.FileSystemInfo]
        $fsi
    )

    $isRoot = (($fsi -is [System.IO.DirectoryInfo]) -and ($null -ne ([System.IO.DirectoryInfo] $fsi).Root) -and (([System.IO.DirectoryInfo] $fsi).Root.FullName -eq $fsi.FullName))

    return $isRoot
}


function AddFSIToDB
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DBConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.IO.FileSystemInfo]
        $fsi
    )

    $isRoot = IsRootFSI $fsi
    $fsiID = -1  # Signal an error
    $cmd = $conn.connection.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = "INSERT INTO [dbo].[FileSystemInfo] ([Name], [Extension], [CreationTime], [LastWriteTime], [Attributes]) OUTPUT INSERTED.ID VALUES (@Name, @Extension, @CreationTime, @LastWriteTime, @Attributes)"

    try
    {
        if($isRoot)
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $fsi.FullName))
        }
        else
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $fsi.BaseName))
        }

        try
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@CreationTime", $fsi.CreationTime))

            try
            {
                [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@LastWriteTime", $fsi.LastWriteTime))

                try
                {
                    [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Attributes", $fsi.Attributes.value__))
                }
                catch
                {
                    # Failed to add @Attributes parameter
                }
            }
            catch
            {
                # Failed to add @LastWriteTime parameter
            }
        }
        catch
        {
            # Failed to add @CreationTime parameter
        }

        if($isRoot -or ([String]::IsNullOrEmpty($fsi.Extension)))
        {
            $cmd.CommandText = $cmd.CommandText.Replace(", [Extension]","").Replace(", @Extension", "")
        } `
        else
        {
            try
            {
                [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Extension", $fsi.Extension))
            }
            catch
            {
                # Failed to add @Extension parameter
            }
        }

        # May need to use this later for associating ACLs
        #    [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@ACLID", 0))

        $fsiID = $conn.ExecuteScalar($cmd)
        if($null -eq $fsiID)
        {
            # Failed to add FileSystemInfo to database
            $fsiID = -1
        }
    }
    catch
    {
        # Failed to add @Name parameter
    }

    return $fsiID
}

<#
    AddDIToDB:
        1. Check for the existence of a FileSystemInfo row matching DI.
            1a. If no FileSystemInfo row is found,
#>
function AddDIToDB
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [DBConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [System.IO.DirectoryInfo]
        $di
    )

    # The FileSystemInfo ID for the directory.
    $fsiID = -1
    if(TestDBConnectionObject $conn)
    {
        if($null -ne $di)
        {
            # If this is a root DI, then we'll use $di.FullName for the Name column and forgo using the Extension column.
            $isRoot = IsRootFSI $di
            if($isRoot)
            {
                # There needs to be a single FileSystemInfo row for this directory, or we need to add a new one...
                $dt = $conn.GetDataTable("SELECT * FROM FileSystemInfo WHERE (Name = '{0}')" -f @($di.FullName))
                if($dt.Rows.Count -eq 0)
                {
                    # Need to add a new root to the database
                    $fsiID = AddDIToDB $conn $di
                    if($fsiID -eq -1)
                    {
                        # Failed to add DI to database...
                    }
                } `
                elseif ($dt.Rows.Count -eq 1)
                {
                    # See if the FileSystemInfo columns need to be updated

                    if(-not (UpdateFileSystemInfoRowByID $conn $dt.Rows[0] $di))
                    {
                        # Failed to update the FileSystemInfo row for this directory
                        $fsiID = -1
                    }
                } `
                else
                {
                    Write-Host ("EXCEPTION: Multiple FSIs for root directory: {0}." -f @($di.FullName))
                }
            } `
            else
            {
                # This is not a root DI...

                # Get the root DI for this DI
                $dt = $conn.GetDataTable("SELECT * FROM FileSystemInfo WHERE (Name = '{0}')" -f @($di.Root.FullName))
            }
        } `
        else
        {
            Write-Host ("Null DI in {0}." -f @($MyInvocation.MyCommand))
        }
    } `
    else
    {
        Write-Host ("DB connection object is null or not a [DBConnection] in {0}." -f @($MyInvocation.MyCommand))
    }
}

function UpdateFileSystemInfoRowByID
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DBConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataRow]
        $fsiRow,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [System.IO.FileSystemInfo]
        $fsi
    )

    $result = $false
    $isRoot = IsRootFSI $fsi
    $fsiID = -1  # Signal an error
    $cmd = $conn.connection.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = "UPDATE [dbo].[FileSystemInfo] SET [Name] = @Name, [Extension] = @Extension, [CreationTime] = @CreationTime, [LastWriteTime] = @LastWriteTime, [Attributes] = @Attributes) OUTPUT INSERTED.ID WHERE (ID = @ID);"

    try
    {
        if($isRoot)
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $fsi.FullName))
        }
        else
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Name", $fsi.BaseName))
        }

        try
        {
            [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@CreationTime", $fsi.CreationTime))

            try
            {
                [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@LastWriteTime", $fsi.LastWriteTime))

                try
                {
                    [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Attributes", $fsi.Attributes.value__))
                }
                catch
                {
                    # Failed to add @Attributes parameter
                }
            }
            catch
            {
                # Failed to add @LastWriteTime parameter
            }
        }
        catch
        {
            # Failed to add @CreationTime parameter
        }

        if($isRoot -or ([String]::IsNullOrEmpty($fsi.Extension)))
        {
            $cmd.CommandText = $cmd.CommandText.Replace(", [Extension]","").Replace(", @Extension", "")
        } `
        else
        {
            try
            {
                [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@Extension", $fsi.Extension))
            }
            catch
            {
                # Failed to add @Extension parameter
            }
        }

        # May need to use this later for associating ACLs
        #    [void] $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new("@ACLID", 0))

        $fsiID = $conn.ExecuteScalar($cmd)
        if($null -eq $fsiID)
        {
            # Failed to add FileSystemInfo to database
            $fsiID = -1
        }
    }
    catch
    {
        # Failed to add @Name parameter
    }

    return $fsiID
}


<#
    Ideas for translating a file path to a more direct share on the NetApp.  This was added so I'd have a history of what I considered so I don't "reinvent" ideas later.  Or anyone else...

    For instance:
        \\fmc-smb01\shares$\REPLICATE\SAS\Projects\FMC Training Lab\FMC Training Lab.lnk

        can be translated to:
            \\fmc-smb01\SAS\Projects\FMC Training Lab\FMC Training Lab.lnk

            Since SAS -> /Shares/REPLICATE/SAS ...

    I could build a simple [SortedDictionary[String][String]] where:
        key = original path i.e. \\fmc-smb01\shares$\REPLICATE\SAS
        value = translated path i.e. \\fmc-smb01\SAS

        Pros:
            Simple to construct the structure and re-use it.

        Cons:
            Each translation would require comparing each "subpath" to the keys until a match is found or all the keys are checked with no matches.
            At first this seems like a fair plan.  However, if a complete path is several folders deep, there could be lots of comparison per key, and with 200m paths to translate, that's a lot...
                Consider: \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1\To\Person 2\Etc1\Etc2 ...
                    This would result in the following:
                        Compare all keys to each of the following to find a match:
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1\To\Person 2\Etc1\Etc2
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1\To\Person 2\Etc1
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1\To\Person 2
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1\To
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From\Person 1
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages\From
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a\Messages
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1\Sub Folder 1a
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1\Folder 1
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1\Subproject 1
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects\Project 1
                            \\fmc-smb01\shares$\REPLICATE\SAS\Projects
                            \\fmc-smb01\shares$\REPLICATE\SAS

                        Remember, to find the most direct share, we have to eliminate the nested folders from the end.  What if there was a translation of \\fmc-smb01\shares$\REPLICATE -> \\fmc-smb01\REPLICATE?  This would not be as direct as
                            \\fmc-smb01\shares$\REPLICATE\SAS -> \\fmc-smb01\SAS

    I could build a [SortedDictionary[String][Object]] where:
        key = a piece of the original path  i.e. fmc-smb01 from :\\fmc-smb01\shares$\REPLICATE\SAS
        value = either a string representing the value to translate to or another [SortedDictionary[String][Object]] where:
            key = a piece of the original path  i.e. shares$ from :\\fmc-smb01\shares$\REPLICATE\SAS
            value = either a string representing the value to translate to or another [SortedDictionary[String][Object]] where: etc...etc...etc...

    Pros:
        I believe this would result in much faster translations since I could start at the beginning of the path and continue until a complete match is found.  This should limit the search per path to 3-4 levels.

    Cons:
        Much more complicated to code.
#>

function NewDictionaryLeaf($dict, $key, $translation = [String]::Empty)
{
    if(-not $dict.ContainsKey($key))
    {
            #Write-Host ("{0}" -f @($key))
        $dict.Add($key, [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
            <#
            if(-not [String]::IsNullOrEmpty($translation))
            {
                Write-Host ("->{0}" -f @($translation))
            }
            #>
        $dict[$key].Add("Translation", $translation)
        $dict[$key].Add("Children", [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
    }

    return @( , $dict[$key]["Children"])
}

function ExportNCCIFSSharesToCSV($csvPath)
{
    $dnsServer = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "loopback" } | Select-Object -ExpandProperty ServerAddresses)[0]
    $cifsServerAliases = Get-DnsServerResourceRecord -RRType CName -ZoneName "powereng.com" -ComputerName $dnsServer | Where-Object { $_.HostName -match "fs1$" } | Select-Object @{N='Alias';E={$_.HostName.ToLower()}},@{N='AliasFor';E={$_.RecordData.HostNameAlias.ToLower().Replace(".powereng.com.","")}}

    $allCifsShares = [System.Collections.Generic.List[Object]]::new()

    # Get all volumes that do not match:
    #   1. CifsServer contains "DR-"
    #   2. ShareName is: c$, ipc$, or admin$
    # @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object { $allCifsShares.Add($_) }
    @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object { $allCifsShares.Add($_) }
    #@(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") } | Foreach-Object { $x = "" | Select-Object CifsServer,ShareName,Path; $x.CifsServer = $_.CifsServer; $x.ShareName = $_.ShareName; $x.Path = $_.Path; $x } | Sort-Object CifsServer,Path,ShareName)
    # $allCifsShares | Export-Csv -Path $csvPath -Delimiter "`t" -NoTypeInformation


    # Now, filter out all the shares that are hosted on data protection destination volumes...
    $cifsShareVolumes = [System.Collections.Generic.List[Object]]::new()
    $indexesToRemove = [System.Collections.Generic.List[int]]::new()
    foreach($cifsShare in $allCifsShares)
    {
        if(-not [String]::IsNullOrEmpty($cifsShare.Volume))
        {
            try
            {
                $vol = $cifsShareVolumes | Where-Object { ($_.NCController.name -eq $cifsShare.NcController.Name) -and ($_.VServer -eq $cifsShare.Vserver) -and ($_.Name -eq $cifsShare.Volume) }
                if($null -eq $vol)
                {
                    Write-Host ("Getting {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
                    $vol = Get-NCVol -Controller $cifsShare.NcController -Vserver $cifsShare.Vserver -Name $cifsShare.Volume -ErrorAction Stop
                    $cifsShareVolumes.Add($vol)
                }

                if($null -ne $vol)
                {
                    if($vol.VolumeMirrorAttributes.IsDataProtectionMirror)
                    {
                        $idx = $allCifsShares.IndexOf($cifsShare)
                        if($idx -gt -1)
                        {
                            $i = $indexesToRemove.BinarySearch($idx)
                            if($i -lt 0)
                            {
                                $indexesToRemove.Insert(-bnot $i, $idx)
                            }
                        }
                    }
                }
                else
                {
                    Write-Host ("No volume found for: {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
                }
            }
            catch
            {
                Write-Host ("Failed to get {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
            }
        }
    }

    $a = $indexesToRemove.Count - 1
    while($a -ge 0)
    {
        $idx = $indexesToRemove[$a]
        if(($idx -ge 0) -and ($idx -lt $allCifsShares.Count))
        {
            $cifsShare = $allCifsShares[$idx]
            Write-Host ("Removing CIFS share on DP volume: \\{0}\{1} ==> {2}://{3}/{4}" -f @($cifsShare.CifsServer, $cifsShare.ShareName, $cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
            [void] $allCifsShares.RemoveAt($idx)
        }
        $a--
    }

    @(foreach($cifsShare in $allCifsShares)
    {
        $fs1Alias = $cifsServerAliases | where-object { $_.AliasFor -match $cifsShare.CifsServer } | Select-Object -First 1 -ExpandProperty Alias
        if($null -ne $fs1Alias)
        {
            $cifsShare | Select-Object @{N='Cluster'; E={$_.NCController.Name}}, VServer, CifsServer, @{N='FS1Alias';E={ $fs1Alias }}, ShareName, Path, @{N='UNCPath';E={"\\?\UNC\{0}\{1}" -f @($fs1Alias, $_.ShareName) }}
        }
        else
        {
            Write-Host ("No FS1 alias for {0}:{1}:{2}" -f @($cifsShare.CifsServer, $cifsShare.ShareName, $cifsShare.Path))
        }
    }) | Export-CSV -Force -Delimiter "`t" -NoTypeInformation -Path $csvPath
}


function BuildTranslationDictionaryFromCSV
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $csvPath,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $forServer = [String]::Empty
    )

    try
    {
        $allCifsShares = Import-CSV -Delimiter "`t" -Path $csvPath

        $byAlias = ($forServer -match "fs1$")
        $propName = "CifsServer"
        if($byAlias)
        {
            $propName = "FS1Alias"
        }
        $sharesForServer = $allCifsShares | Where-Object { ([String]::IsNullOrEmpty($forServer)) -or ((-not $byAlias) -and ($_.CifsServer -eq $forServer)) -or ($byAlias -and ($_.FS1Alias -eq $forServer)) }

        $Global:pathTranslationDictionary = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $uniqueCifsServers = @($sharesForServer | Select-Object -Unique -ExpandProperty $propName)

        $a = 0
        while($a -lt $uniqueCifsServers.Length)
        {
            $translationDictionary = $Global:pathTranslationDictionary

            $translationDictionary = NewDictionaryLeaf $translationDictionary $uniqueCifsServers[$a]
            $cifsServerShares = [System.Collections.Generic.List[Object]]::new()
            @($sharesForServer | Where-Object { ($_.$($propName) -eq $uniqueCifsServers[$a]) } | Sort-Object Path) | ForEach-Object { $cifsServerShares.Add($_) }

            $shareNum = 0
            while($shareNum -lt $cifsServerShares.Count)
            {
                $parentCifsShare = $cifsServerShares[$shareNum]
                $childShares = @($cifsServerShares | Where-Object { ($_.Path -ne $parentCifsShare.Path) -and $_.Path.StartsWith($parentCifsShare.Path) })
                if($childShares.Length -gt 0)
                {
                    $translationDictionary = NewDictionaryLeaf $translationDictionary $parentCifsShare.ShareName
                    $parentTranslationDictionary = $translationDictionary
                    [void] $cifsServerShares.Remove($parentCifsShare)
                    $b = 0
                    while($b -lt $childShares.Length)
                    {
                        $translationDictionary = $parentTranslationDictionary
                        $subFolders = ($childShares[$b].Path -replace $parentCifsShare.Path, "").Split(@('/'), [System.StringSplitOptions]::RemoveEmptyEntries)
                        $c = 0
                        while($c -lt $subFolders.Length)
                        {
                            if(-not $translationDictionary.ContainsKey($subFolders[$c]))
                            {
                                if($c -eq ($subFolders.Length - 1))
                                {
                                    # Write-Host ("`t`t[{0}] -> {1}" -f @($subFolders[$c], ("{0}\{1}" -f @($childShares[$b].CifsServer, $childShares[$b].ShareName))))
                                    $translationDictionary = NewDictionaryLeaf $translationDictionary $subFolders[$c] ("{0}\{1}" -f @($childShares[$b].$($propName), $childShares[$b].ShareName))
                                }
                                else
                                {
                                    # Write-Host ("`t`tadding child key: {0}" -f @($subFolders[$c]))
                                    $translationDictionary = NewDictionaryLeaf $translationDictionary $subFolders[$c]
                                }
                            }
                            else
                            {
                                $translationDictionary = $translationDictionary[$subFolders[$c]]["Children"]
                            }

                            $c++
                        }
                        [void] $cifsServerShares.Remove($childShares[$b])

                        $b++
                    }
                }
                $shareNum++
            }
            $a++
        }
    }
    catch
    {
        # [Log]::Error("CIFS server shares file {0} not found." -f @($csvPath))
    }
}


$translations = 0
function DisplayTranslationDictionary($dict, $indent=0)
{
    foreach($key in @($dict.Keys))
    {
        $translation = [String]::Empty
        if(-not [String]::IsNullOrEmpty($dict[$key]["Translation"]))
        {
            $translation = " -> {0}" -f @($dict[$key]["Translation"])
            $Global:translations++
        }

        Write-Host (("{{0,{0}}}{{1}}{{2}}" -f @($indent)) -f @(" ",$key, $translation))
        DisplayTranslationDictionary $dict[$key]["Children"] ($indent + 3)
    }
}

<#
    TranslatePath returns an object:
        .TranslatedPath : String - $pathToTranslate translated to a more direct share for the same path
        .DirectShare : String - share path .TranslatedPath is a part of.
#>
function TranslatePath($pathToTranslate)
{
    $tPath = RemoveLongUNCPath $pathToTranslate
    $d = "" | Select-Object TranslatedPath, DirectShare

    $d.TranslatedPath = $pathToTranslate

    $pathParts = $tPath.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $d.DirectShare = "\\{0}" -f @(($pathParts[0..1] -join "\\"))
    $tDict = $Global:pathTranslationDictionary
    $eDict = $Global:pathTranslationDictionary
    $mDict = $null
    $a = 0
    while(($a -lt $pathParts.Length) -and $tDict.ContainsKey($pathParts[$a]) -and ($tDict[$pathParts[$a]]["Children"].Keys.Count -gt 0))
    {
        # If there is a translation at this point, let's capture it...
        if(-not [String]::IsNullOrEmpty($tDict[$pathParts[$a]]["Translation"]))
        {
            $mDict = $tDict[$pathParts[$a]]
            $d.DirectShare = "\\{0}" -f @($mDict["Translation"])
            $d.TranslatedPath = $pathToTranslate -replace (($pathParts[0..$a] -join "\\") -replace "\$","\$"), $mDict["Translation"]
        }
        #Write-Host ("{0}) {1} : [{2}]" -f @($a, $pathParts[$a], $tDict[$pathParts[$a]]["Translation"]))
        $eDict = $tDict[$pathParts[$a]]
        $tDict = $tDict[$pathParts[$a]]["Children"]
        $a++
    }

    if(($a -lt $pathParts.Length) -and ($tDict.ContainsKey($pathParts[$a])) -and (-not [String]::IsNullOrEmpty($tDict[$pathParts[$a]]["Translation"])))
    {
        $d.DirectShare = "\\{0}" -f @($tDict[$pathParts[$a]]["Translation"])
        $d.TranslatedPath = $pathToTranslate -replace (($pathParts[0..$a] -join "\\") -replace "\$","\$"), $tDict[$pathParts[$a]]["Translation"]
    }

    if($pathToTranslate -match "^\\\\\?\\unc\\")
    {
        $d.DirectShare = AddLongUNCPath $d.DirectShare
    }

    return $d
}

function AddUpdateDirectoryInfoInDB
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [DBConnection]
        $dbConn,

        [Parameter(Mandatory=$true,Position=1)]
        [System.Object]
        $di
    )


    $dt = $db.GetDataTable("SELECT fsi.ID AS fsiID, fsi.Name AS fsiName, fsi.Extension AS fsiExtension, fsi.CreationTime AS fsiCreationTime, fsi.LastWriteTime AS fsiLastWriteTime, fsi.Attributes AS fsiAttributes, di.ID AS diID, di.FileSystemInfoID AS diFileSystemInfoID, di.ParentDirectoryInfoID AS diParentDirectoryInfoID, di.RootDirectoryInfoID AS diRootDirectoryInfoID FROM FileSystemInfo fsi INNER JOIN DirectoryInfo di ON di.FileSystemInfoID = fsi.ID WHERE (di.ParentDirectoryInfoID IS NULL) AND (di.RootDirectoryInfoID = di.ID)")


}

function InitShareAgeDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $shareName
    )

    if(-not $Global:sizeByAgeDict.ContainsKey($shareName))
    {
        $Global:sizeByAgeDict.Add($shareName, [System.Collections.Generic.Dictionary[[DateTime],[UInt64]]]::new() )
        $Global:sizeByAgeDict[$shareName]
        $Global:fileAgeKeys | ForEach-Object { $Global:sizeByAgeDict[$shareName].Add($_, 0) }
    }
}

function ListDirectory
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=1)]
        [System.Object]
        $di
    )

    if($null -ne $di)
    {
        if($di -is [System.IO.DirectoryInfo])
        {
            $pathTranslation = TranslationPath $di.FullName

            if(-not $Global:sizeByAgeDict.ContainsKey($pathTranslation.DirectShare))
            {
                $Global:sizeByAgeDict.Add($pathTranslation.DirectShare, [ShareStats5]::new())
            }
            $Global:sizeByAgeDict[$pathTranslation.DirectShare].Directories++

            try
            {
                $diDirectories = @($di.GetDirectories() | Where-Object { $_.Name -notmatch "~snapshot" })
                $diDirectories | ForEach-Object {
                    ListDirectory $_
                }

                try
                {
                    $diFiles = $di.GetFiles()
                    $Global:sizeByAgeDict[$pathTranslation.DirectShare].Files += $diFiles.Length
                    $diFiles | ForEach-Object {
                        $fi = $_
                        $Global:sizeByAgeDict[$pathTranslation.DirectShare].TotalSize += $fi.Length
                        foreach($ageKey in [ShareStats5]::FileAgeKeys)
                        {
                            if($fi.LastWriteTime -le $ageKey)
                            {
                                $Global:sizeByAgeDict[$pathTranslation.DirectShare].FilesByAge[$ageKey].Count++
                                $Global:sizeByAgeDict[$pathTranslation.DirectShare].FilesByAge[$ageKey].Size += $fi.Length
                            }
                        }

                        # [void] (AddFSIToDB $db $_ $false)
                        if([Console]::KeyAvailable)
                        {
                            $fileTranslation = TranslatePath $fi.FullName
                            [void] [Console]::ReadKey($false)
                            Write-Host ("`r`n{0}`r`nTranslated: {1}`t{2}`t{3}" -f @($_.FullName, $fileTranslation.TranslatedPath, (Format-StorageNumber $_.Length), $_.CreationTime.ToString("yyyyMMdd hh:mm:ss")))
                            ShowStats
                        }
                    }
                }
                catch
                {
                    $formatstring = "{5}`r`n{0} : {1}`n{2}`n" +
                    "    + CategoryInfo          : {3}`n" +
                    "    + FullyQualifiedErrorId : {4}`n"
                    $fields = $_.InvocationInfo.MyCommand.Name,
                            $_.ErrorDetails.Message,
                            $_.InvocationInfo.PositionMessage,
                            $_.CategoryInfo.ToString(),
                            $_.FullyQualifiedErrorId,
                            $di.FullName

                    $formatstring -f $fields
                    Write-Host -Foreground Red -Background Black ($formatstring -f $fields)
                    $Global:fileExceptions.Add($di.FullName)
                }
            }
            catch
            {
                $formatstring = "{5}`r`n{0} : {1}`n{2}`n" +
                "    + CategoryInfo          : {3}`n" +
                "    + FullyQualifiedErrorId : {4}`n"
                $fields = $_.InvocationInfo.MyCommand.Name,
                        $_.ErrorDetails.Message,
                        $_.InvocationInfo.PositionMessage,
                        $_.CategoryInfo.ToString(),
                        $_.FullyQualifiedErrorId,
                        $di.FullName

                $formatstring -f $fields
                Write-Host -Foreground Red -Background Black ($formatstring -f $fields)

                $Global:directoryExceptions.Add($di.FullName)
            }
        } `
        elseif($di -is [String])
        {
            $di = [System.IO.DirectoryInfo]::new($di)
            if($di.Exists)
            {
                ListDirectory $di
            }
        }
    } `
    else
    {
        return
    }
}
