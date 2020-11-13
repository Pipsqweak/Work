$Global:objectsCheckedCount = 0
$Global:aclsRecords = 0

<#
    NOTES:
        Need CIFS Server Name to get $serverID  ($cifsServerName)
        Need to keep part of the "SaveJobResults process in the Scanner, like updating CIFS Server data.
#>

function SaveResult
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cifsServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [Object]
        $aclData
    )

    if($null -ne $aclData)
    {
        # Add or update the server name record in the database and get the server ID
        $serverID = [DataAccess]::AddUpdateServer($cifsServerName)

        if($serverID -ne -1)
        {
            # Save the ACL data to the database

            # Add or update the path record in the database and get a path ID
            $pathID = [DataAccess]::AddUpdatePath($serverID, $aclData.Path, $aclData.IsInheritanceBroken)

            if($pathID -ne -1)
            {
                $Global:aclsRecords++
                # Save each of the explicit rules found for the path to the database
                for($p = 0; $p -lt $aclData.ExplicitRules.Count; $p++)
                {
                    # Add or update the identity associated with this rule in the database and get an identity ID
                    $identityID = [DataAccess]::AddUpdateIdentity($aclData.ExplicitRules[$p].Identity)

                    if($identityID -ne -1)
                    {
                        # Save the file right to the database.  Rights [in the database] do not have a unique ID, so instead, make sure at least 1 row was updated/inserted.
                        $rowCount = [DataAccess]::AddUpdateRight($pathID, $identityID, $aclData.ExplicitRules[$p].ACLType, $aclData.ExplicitRules[$p].Rights)
                        if($rowCount -lt 1)
                        {
                            [Log]::Warning("Failed to save rights for {0} {1} {2} {3} {4}." -f @($cifsServerName, $aclData.Path, $aclData.ExplicitRules[$p].Identity, $aclData.ExplicitRules[$p].ACLType, $aclData.ExplicitRules[$p].Rights))
                        }
                        else
                        {
                            # Nothing
                        }
                    }
                    else
                    {
                        [Log]::Warning("Unable to save result for {0} {1} {2}.  Could not add/update identity." -f @($cifsServerName, $aclData.Path, $aclData.ExplicitRules[$p].Identity))
                    }
                }
            }
            else
            {
                [Log]::Warning("Unable to save result for {0} {1}.  Could not add/update path." -f @($cifsServerName, $aclData.Path))
            }
        }
        else
        {
            [Log]::Warning("Unable to save results for {0}.  Failed to update server name in database." -f @($cifsServerName))
        }
    }
    else
    {
        [Log]::Warning("Unable to save ACL data to DB, null aclData.")
    }
}

function ProcessPath
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cifsServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $pathToCheck
    )

    $aclData = "" | Select-Object Path,IsInheritanceBroken,ExplicitRules
    $aclData.Path = [String]::Empty
    $aclData.IsInheritanceBroken = $false
    $aclData.ExplicitRules = @()

    if(Test-Path -LiteralPath $pathToCheck)
    {
        $aclData.Path = $pathToCheck.Replace("\\?\UNC\","\\")
        $acl = Get-ACL -LiteralPath $pathToCheck
        $Global:objectsCheckedCount++

        if($null -ne $acl)
        {
            $aclData.IsInheritanceBroken = $acl.AreAccessRulesProtected

            if($null -ne $acl.Access)
            {
                $explicitRules = @($acl.Access | Where-Object { -not $_.IsInherited })
                for($y = 0; $y -lt $explicitRules.Length; $y++)
                {
                    $d = "" | Select-Object ACLType, Identity, Rights
                    $d.ACLType = $explicitRules[$y].AccessControlType.ToString()

                    if($d.ACLType -eq "Deny")
                    {
                        [Log]::Warning("Deny ACL on path {0}" -f @($pathToCheck))
                    }

                    $d.Identity = $explicitRules[$y].IdentityReference.ToString()
                    $rights = $explicitRules[$y].FileSystemRights.ToString()

                    if(-not [String]::IsNullOrEmpty($rights))
                    {
                        $rights = $rights.Replace(", Synchronize","")
                        $rights = $rights.Replace("268435456", "Generic All")
                        $rights = $rights.Replace("FullControl","Full Control")
                        $rights = $rights.Replace("ReadAndExecute", "Read and Execute")
                        $d.Rights = $rights
                        $aclData.ExplicitRules += $d
                    }
                    else
                    {
                        # Nothing, no rights to save...
                    }
                }
            }
            else
            {
                [Log]::Info("Unable to get ACL rules for {0}" -f @($ff[$a].FullName))
            }
        }
        else
        {
            [Log]::Info("Unable to get ACL for {0}" -f @($ff[$a].FullName))
        }
    }

    if((-not [String]::IsNullOrEmpty($aclData.Path)) -and ($aclData.IsInheritanceBroken -or ($aclData.ExplicitRules.Length -gt 0)))
    {
        [Log]::Info("ACL Path: {0}" -f @($aclData.Path))
        [Log]::Info("`tInheritance broken: {0}" -f @($aclData.IsInheritanceBroken))
        foreach($er in $aclData.ExplicitRules)
        {
            [Log]::Info("`t{0}: {1}" -f @($er.Identity, $er.Rights))
        }

        SaveResult $cifsServerName $aclData
    }
    else
    {
        # Nothing to log.
    }
}

function Get-ACLs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cifsServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $pathToCheck,

        [Parameter(Position=2)]
        [System.String[]]
        $pathsToAvoid=@(),

        [Parameter(Position=3)]
        [System.String[]]
        $partialPathsToAvoid=@(),

        [Parameter(Position=4)]
        [System.Int32]
        $depth=0,

        [Parameter(Position=5)]
        [System.Int32]
        $maxDepth=-1,

        [Parameter(Position=6)]
        [Boolean]
        $directoriesOnly=$true
    )

    $depth++
    if($pathsToAvoid -notcontains $pathToCheck)
    {
        $p2Chk = $pathToCheck.ToLower()
        # Do not enumerate a path that contains any of the $partialPathsToAvoid...
        $containsPartialPathToAvoid = $false
        for($a = 0; (-not $containsPartialPathToAvoid) -and ($a -lt $partialPathsToAvoid.Length); $a++)
        {
            $containsPartialPathToAvoid = $p2Chk.Contains($partialPathsToAvoid[$a])
        }

        if(-not $containsPartialPathToAvoid)
        {
            if(Test-Path -LiteralPath $pathToCheck)
            {
                [Log]::Info("Processing: {0}" -f @($pathToCheck))

                # First, process the $pathToCheck
                ProcessPath $cifsServerName $pathToCheck

                # If we need to go deeper...
                if(($maxDepth -eq -1) -or ($depth -lt $maxDepth))
                {
                    $fileInfo = [System.IO.FileInfo]::new($pathToCheck)

                    if(($fileInfo.Attributes -band [System.IO.FileAttributes]::Directory) -eq [System.IO.FileAttributes]::Directory)
                    {
                        # An enumerator to enumerate files and/or folders...
                        $enumerator = $null

                        try
                        {
                            $error.Clear()
                            # Next get the folders and/or files under $pathToCheck
                            #   Get an enumerator based on the type of enumeration we are doing...
                            if($directoriesOnly)
                            {
                                $enumerator = [System.IO.Directory]::EnumerateDirectories($pathToCheck, "*", [System.IO.SearchOption]::TopDirectoryOnly).GetEnumerator()
                            }
                            else
                            {
                                $enumerator = [System.IO.Directory]::EnumerateFileSystemEntries($pathToCheck, "*", [System.IO.SearchOption]::TopDirectoryOnly).GetEnumerator()
                            }
                        }
                        catch
                        {
                            [Log]::Warning("Failed to get enumerator object to enumerate: {0}" -f @($pathToCheck))
                            [Log]::Warning("{0}" -f @($error.Exception))
                        }

                        if($null -ne $enumerator)
                        {
                            while($enumerator.MoveNext())
                            {
                                $nxtPathToCheck = $enumerator.Current

                                Get-ACLs -cifsServerName $cifsServerName -pathToCheck $nxtPathToCheck -pathsToAvoid $pathsToAvoid -partialPathsToAvoid $partialPathsToAvoid -depth $depth -maxDepth $maxDepth -directoriesOnly $directoriesOnly
                            }
                        }
                        else
                        {
                            [Log]::Warning("Unable to enumerate files and/or folder at {0}." -f @($pathToCheck))
                        }
                    }
                    else
                    {
                        # Nothing, $pathToCheck is not a directory, do don't dig deeper...
                    }
                }
                else
                {
                    # Nothing, no need to enumerate any deeper...
                }
            }
            else
            {
                [Log]::Warning("Test-Path {0} failed." -f @($pathToCheck))
            }
        }
        else
        {
            [Log]::Info("Partial path to avoid found. Not enumerating path: {0}" -f @($nxtPathToCheck))
        }
    }
    else
    {
        [Log]::Info("Avoiding: {0}" -f @($pathToCheck))
    }
}

function Main
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cifsServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $pathToCheck,

        [Parameter(Position=2)]
        [System.String[]]
        $pathsToAvoid=@(),

        [Parameter(Position=3)]
        [System.String[]]
        $partialPathsToAvoid=@(),

        [Parameter(Position=4)]
        [System.Int32]
        $depth=0,

        [Parameter(Position=5)]
        [System.Int32]
        $maxDepth=-1,

        [Parameter(Position=6)]
        [Boolean]
        $directoriesOnly=$true,

        [Parameter(Mandatory=$false,Position=7)]
        [String]
        $databaseServer,

        [Parameter(Mandatory=$false,Position=8)]
        [String]
        $databaseName
    )

    [Log]::Info("Scanner host: [{0}]" -f @($env:COMPUTERNAME))
    [Log]::Info("CIFS Server Name: [{0}]" -f @($cifsServerName))
    [Log]::Info("Path: [{0}]" -f @($pathToCheck))
    [Log]::Info("MaxDepth: [{0}]" -f @($maxDepth))
    [Log]::Info("Directories Only: [{0}]" -f @($directoriesOnly))

    <#
        To deal with potentially long paths, I'm just going to "fix" all the paths to force the system to use
        the unicode API calls.   https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file
    #>

    $fixed_pathsToAvoid = @()
    if($null -ne $pathsToAvoid)
    {
        foreach($pathToAvoid in $pathsToAvoid)
        {
            # Fix the path to use unicode API calls.
            $fixedPathToAvoid = $pathToAvoid -replace '^(\\\\([^\\]+))','\\?\UNC\$2'
            $fixed_pathsToAvoid += $fixedPathToAvoid

            [Log]::Info("Path to avoid: {0}" -f @($fixedPathToAvoid))
        }
    }
    else
    {
        # Nothing.
    }

    $connectionString = "Data Source={0};Initial Catalog={1};Integrated Security=True" -f @($databaseServer, $databaseName)
    # Initialize the connection to the database
    [DataAccess]::Init($connectionString)

    # Paths stored in the DB do not use the unicode path...
    $markedDeleted = [DataAccess]::MarkSharePathsDeleted($pathToCheck)

    [Log]::Info("Marked {0} paths as deleted" -f @($markedDeleted))

    $fixed_pathToCheck = $pathToCheck -replace '^(\\\\([^\\]+))','\\?\UNC\$2'
    for($a = 0; $a -lt $partialPathsToAvoid.Length; $a++)
    {
        $partialPathsToAvoid[$a] = $partialPathsToAvoid[$a].ToLower()
    }
    Get-ACLs -cifsServerName $cifsServerName -pathToCheck $fixed_pathToCheck -pathsToAvoid $fixed_pathsToAvoid -partialPathsToAvoid $partialPathsToAvoid -maxDepth $maxDepth -directoriesOnly $directoriesOnly

    [Log]::Must("Complete.  Checked {0} objects, recorded {1} ACLs" -f @($Global:objectsCheckedCount, $Global:aclsRecords))
}
