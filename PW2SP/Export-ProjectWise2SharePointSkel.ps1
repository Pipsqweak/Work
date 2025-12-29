function CheckDocumentProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object] $libInfo,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload
    )

    $me = $MyInvocation.MyCommand
    if(-not [String]::IsNullOrEmpty($libInfo.FileURL))
    {
        try
        {
            $spFile = Get-PnPFile -Url $libInfo.FileURL -AsListItem -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to retrieve {0} from SharePoint in {1}." -f @($libInfo.FileURL, $me.Name))
        }

        if($null -ne $spFile)
        {
            $docProps = BuildDocumentProperties -obj2Upload $obj2Upload -libInfo $libInfo
            $newFileProps = @{}

            if(-not $Script:HaveError)
            {
                if($null -ne $docProps)
                {
                    if($null -ne $spFile.FieldValues)
                    {
                        $docPropKeys = @($docProps.Keys)
                        $a = 0
                        while((-not $Script:HaveError) -and ($a -lt $docPropKeys.Length))
                        {
                            if($spFile.FieldValues.ContainsKey($docPropKeys[$a]))
                            {
                                if($spFile.FieldValues[$docPropKeys[$a]] -ne $docProps[$docPropKeys[$a]])
                                {
                                    $newFileProps.Add($docPropKeys[$a], $docProps[$docPropKeys[$a]])
                                } `
                                else
                                {
                                    # Nothing, this field is fine.
                                }
                            } `
                            else
                            {
                                $newFileProps.Add($docPropKeys[$a], $docProps[$docPropKeys[$a]])
                            }
                            $a++
                        }
                    } `
                    else
                    {
                        $newFileProps = $docProps
                    }

                    if($newFileProps.Count -gt 0)
                    {
                        # Sucks, but this is the only way I know of to get an updatable version of $spFile...
                        try
                        {
                            $spFile = Get-PnPFile -Url $libInfo.FileURL -ErrorAction Stop
                        }
                        catch
                        {
                            LogError ("Failed to retrieve {0} from SharePoint in {1}." -f @($libInfo.FileURL, $me.Name))
                        }

                        if(-not $Script:HaveError)
                        {
                            if($null -ne $spFile)
                            {
                                $a = 0
                                $filePropKeys = @($newFileProps.Keys)
                                while((-not $Script:HaveError) -and ($a -lt $filePropKeys.Length))
                                {
                                    $spFile.ListItemAllFields[$filePropKeys[$a]] = $newFileProps[$filePropKeys[$a]]
                                    $a++
                                }

                                # Send the changes to the file...
                                LogInfo ("Sending file property changes for {0}." -f @($libInfo.FileURL))
                                try
                                {
                                    $spFile.ListItemAllFields.Update()
                                    Invoke-PnpQuery -ErrorAction Stop
                                }
                                catch
                                {
                                    LogError ("Failed to update file document fields for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Failed to get updatable version of {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error
                        }
                    } `
                    else
                    {
                        # TODO: Or is there???  Might think about a reverse check... if there are no document properties from PW, then remove them from SP....hrm...
                        # Nothing, nothing to change.
                    }
                } `
                else
                {
                    LogError ("Null doc properties returned from BuildDocumentProperties in {0}." -f @($me.Name))
                }
            } `
            else
            {
                # Nothing, already logged an error
            }
        } `
        else
        {
            # TODO: Do I want to make sure a file exists before calling this function?  If so, then this needs to be an error.
            # Nothing, file doesn't exist
        }
    } `
    else
    {
        LogError ("Missing file URL in {0}." -f @($me.Name))
    }
}

function CheckFolderProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object] $libInfo,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload
    )
<#   For now, until I know better, I don't think any folders have properties I'm concerned with
            $spFolder = $null
            try
            {
                $spFolder = Get-PnPFolder -Url $libInfo.FolderURL -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to retrieve folder from {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
            }

            if(-not $Script:HaveError)
            {
                if($null -ne $spFolder)
                {
                    try
                    {
                        $folderProps = Get-PnPProperty -ClientObject $spFolder -ErrorAction Stop
                    }
                    catch
                    {
                        LogError ("Failed to retrieve folder properties for {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                    }

                    if(-not $Script:HaveError)
                    {
                        if($null -ne $folderProps)
                        {
                            try
                            {
                                $folderProps = Get-PnPProperty -ClientObject $spFolder -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to retrieve folder properties for {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing??? no folder there...
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }


                } `
                else
                {
                    # Nothing??? no folder there...
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
#>
}

function CheckItemProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload
    )

    # TODO:  Might consider making this work with folders too...

    $me = $MyInvocation.MyCommand

    $libInfo = ($null -ne $obj2Upload.LibInfo) ? $obj2Upload.LibInfo : (GetLibraryDataFromObj -obj2Upload $obj2Upload)
    if($null -ne $libInfo)
    {
        if($obj2Upload.SourceObject.MyType -eq "ProjectWiseDocument")
        {
            CheckDocumentProperties -libInfo $libInfo -obj2Upload $obj2Upload
        } `
        elseif($obj2Upload.SourceObject.MyType -eq "ProjectWiseFolder")
        {
            CheckFolderProperties -libInfo $libInfo -obj2Upload $obj2Upload
        } `
        else
        {
            LogError ("Unknown source object type: '{0}' for {1}:{2} in {3}." -f @($obj2Upload.SourceObject.MyType, $obj2Upload.SourceObject.DocumentGUID, $obj2Upload.SourceObject.FullPath, $me.Name))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function LoadLatestViablePaths
{
    $ovp = $null
    try
    {
        $latestViablePathsExportFile = Get-ChildItem -File -Filter ("{0}_*_ViablePaths.json" -f @($Script:projectName)) -Path ("{0}\{1}" -f @($Script:localPath, $Script:pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        if($null -ne $latestViablePathsExportFile)
        {
            $ovp = LoadViablePaths -savePath $latestViablePathsExportFile.FullName
        } `
        else
        {
            # Nothing, no viable path export to load.
        }
    }
    catch
    {
        $Error.Clear()
        # Not viable path export to load.
    }

    return @( ,$ovp)
}

function CreateSharePointProjectFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $fo
    )

    $me = $MyInvocation.MyCommand
    $libInfo = ($null -ne $fo.LibInfo) ? $fo.LibInfo : (GetLibraryDataFromObj -obj2Upload $fo -CreateMissingLibrary)
    if($null -ne $libInfo)
    {
        if($libInfo.SPFolderPathPieces.Length -ge 2)
        {
            $projName = $libInfo.SPFolderPathPieces[1]
            if(-not [String]::IsNullOrEmpty($projName))
            {
                # Add the project folder to the sharepoint document library.
                $pFolder = $null
                $folderListItem = $null
                try
                {
                    # See if the folder already exists...
                    $pFolder = Get-PnPFolder -Url $libInfo.FolderURL -Includes ListItemAllFields -ErrorAction Stop
                }
                catch
                {
                    if(($Error.Count -gt 0) -and ($Error[0].Exception.Message -match "File Not Found."))
                    {
                        # No big deal, need to create the folder.
                        $Error.Clear()
                    } `
                    else
                    {
                        LogError ("Failed to retrieve folder {0} from SharePoint in {1}." -f @($libInfo.FolderURL, $me.Name))
                    }
                }

                # If the folder exists, then get it's properties...
                if($null -ne $pFolder)
                {
                    try
                    {
                        $folderListItem = Get-PnPListItem -List $libInfo.Library -Id $pFolder.ListItemAllFields.Id

                        if($null -ne $folderListItem)
                        {
                            $Script:reportData.Folders.PreExisting++
                            if($null -ne $folderListItem.FieldValues)
                            {
                                # Nothing, all good.
                            } `
                            else
                            {
                                LogError ("Unable to retrieve folder list item for {0} in {1}.  Null value returned" -f @($libInfo.FolderURL, $me.Name))
                            }
                        } `
                        else
                        {
                            LogError ("Unable to retrieve folder list item for {0} in {1}.  Null value returned" -f @($libInfo.FolderURL, $me.Name))
                        }
                    }
                    catch
                    {
                        LogError ("Unable to retrieve folder list item for {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                    }
                } `
                else
                {
                    # Nothing, can't get properties for a non-existent folder.
                }

                if(-not $Script:HaveError)
                {
                    # If there isn't a pre-existing folder, then try to create it.
                    if($null -eq $pFolder)
                    {
                        try
                        {
                            LogInfo ("Creating project folder: {0}" -f @($Script:projectName))
                            # Create the new top level project folder
                            $pFolder = Add-PnpFolder -Folder $libInfo.LibURL -Name $Script:projectName -ErrorAction Stop

                            # Reset $pFolder to null so we reget it below.
                            $pFolder = $null

                            $Script:reportData.Folders.Created++
                        }
                        catch
                        {
                            LogError ("Failed to create new Sharepoint Online project folder: {0} in {1}." -f @($libInfo.FolderURL, $me.Name))

                        }
                    } `
                    else
                    {
                        # No need to create a new folder when it already exists.
                    }

                    # Set/Update the properties on the folder.
                    if(-not $Script:HaveError)
                    {
                        # Create a hashtable with all the project properties from ProjectWise
                        $projectParams = @{  }

                        $a = 0
                        $projectPropKeys = @($fo.SourceObject.ProjectProperties.Keys)
                        while((-not $Script:HaveError) -and ($a -lt $projectPropKeys.Length))
                        {
                            if(-not [String]::IsNullOrEmpty($fo.SourceObject.ProjectProperties[$projectPropKeys[$a]]))
                            {
                                if($Script:connData.documentFields.ContainsKey($projectPropKeys[$a]))
                                {
                                    $spDocField = $Script:connData.documentFields[$projectPropKeys[$a]]
                                } `
                                else
                                {
                                    $spDocField = $null
                                }

                                <#
                                    If...
                                        There was no existing folder  OR
                                        There was a folder and either
                                            there is no existing value for this property  OR
                                            the existing value of the property is different
                                    Then proceed to set the property value if we aren't ignoring it.
                                #>
                                if(($null -eq $folderListItem) -or (($null -ne $folderListItem) -and ((-not $folderListItem.FieldValues.ContainsKey($projectPropKeys[$a])) -or ($folderListItem.FieldValues.ContainsKey($projectPropKeys[$a])) -and ($folderListItem.FieldValues[$projectPropKeys[$a]] -ne $fo.SourceObject.ProjectProperties[$projectPropKeys[$a]]))))
                                {
                                    if(($null -eq $spDocField) -or (($null -ne $spDocField) -and (-not $spDocField.Ignore)))
                                    {
                                        $fld = TestForSPDocumentLibraryField -libraryName $libInfo.LibraryName -fieldName $projectPropKeys[$a]

                                        if(-not $Script:HaveError)
                                        {
                                            if(($null -ne $fld) -and (-not $fld.Ignore))
                                            {
                                                $projectParams.Add($fld.InternalName, $fo.SourceObject.ProjectProperties[$projectPropKeys[$a]])
                                            } `
                                            else
                                            {
                                                # Nothing, ignore the property
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, already displayed an error.
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, not a field we care about...
                                    }
                                } `
                                else
                                {
                                    # Nothing, can't check the pre-existing value when it doesn't exist.
                                }
                            }
                            $a++
                        }

                        if(-not $Script:HaveError)
                        {
                            # Did we set any folder properties?
                            if($projectParams.Count -gt 0)
                            {
                                # Yes...

                                # Then we need to set the property values on the folder...

                                # Was there a pre-existing folder?
                                if($null -eq $pFolder)
                                {
                                    # No, need to get the folder...
                                    try
                                    {
                                        # Now get the new folder with its fields
                                        $pFolder = Get-PnPFolder -Url $libInfo.FolderURL -Includes ListItemAllFields -ErrorAction Stop
                                    }
                                    catch
                                    {
                                        LogError ("Failed to retrieve newly created project folder: {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                                    }
                                } `
                                else
                                {
                                    # Yes... then use it to set the properties...
                                }

                                if($null -ne $pFolder)
                                {
                                    $fileListItem = $null
                                    try
                                    {
                                        $fileListItem = Set-PnpListItem -List $libInfo.Library -Identity $pFolder.ListItemAllFields.Id -Values $projectParams -ErrorAction Stop
                                    }
                                    catch
                                    {
                                        LogError ("Failed to set document properties on project folder {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                                    }

                                    if($null -ne $fileListItem)
                                    {
                                        $projectPropKeys = @($projectParams.Keys)
                                        $a = 0
                                        while($a -lt $projectPropKeys.Length)
                                        {
                                            if($fileListItem.FieldValues.ContainsKey($projectPropKeys[$a]))
                                            {
                                                if($fileListItem.FieldValues[$projectPropKeys[$a]] -ne $projectParams[$projectPropKeys[$a]])
                                                {
                                                    LogError ("Project property value mismatch for {0}:{1}:{2}.  Should be: {3}, returned {4} in {5}." -f @($libInfo.LibraryName, $Script:projectName, $projectPropKeys[$a], $projectParams[$projectPropKeys[$a]], $fileListItem.FieldValues[$projectPropKeys[$a]], $me.Name))
                                                } `
                                                else
                                                {
                                                    # Nothing, all is well.
                                                }
                                            } `
                                            else
                                            {
                                                LogError ("Failed to verify project property: {0} in {1}." -f @($projectPropKeys[$a], $me.Name))
                                            }
                                            $a++
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("Failed to set document properties on project folder {0} in {1}.  NUll object returned." -f @($libInfo.FolderURL, $me.Name))
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to retrieve newly created project folder: {0} in {1}.  Null folder returned." -f @($libInfo.FolderURL, $me.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, no project properties to set...
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }
                } `
                else
                {
                    # Nothing, already displayed an error.
                }
            } `
            else
            {
                LogError ("Malformed Sharepoint folder name [{0}], missing project name in {1}." -f @($fo.SPData.FolderName, $me.Name))
            }

            if(-not $Script:HaveError)
            {
                # Mark the project folder's viable path node as processed.
                $fo.SPData.Processed = $true
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            LogError ("Unable to determine SharePoint Project Folder from {0} in {1}." -f @($pwFolder.FullPath, $me.Name))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    if($Script:HaveError)
    {
        $pFolder = $null
    } `
    else
    {
        # Nothing, let it fly
    }

    return @(, $pFolder)
}

function GetSPDocumentVersionLinks
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $currentVersionOfDocument
    )

    $me = $MyInvocation.MyCommand

    if($Script:DoDebugging)
    {
        # LogInfo ("Getting version data for {0}" -f @(($currentVersionOfDocument.Paths -join "/")))
    }

    $libInfo = ($null -ne $currentVersionOfDocument.LibInfo) ? $currentVersionOfDocument.LibInfo : (GetLibraryDataFromObj -obj2Upload $currentVersionOfDocument -CreateMissingLibrary)
    if($null -ne $libInfo)
    {
        try
        {
            # This only works for the current version of the file....
            $spFile = Get-PnPFile -URL $libInfo.FileURL -AsListItem -ErrorAction Stop

            # Leave $uploadDocument set to false so we don't upload it again.
        }
        catch
        {
            if($Error[0].Exception.Message -match "The object does not belong to a list.")
            {
                # File doesn't exist...
                $Error.Clear()
                $spFile = $null
            } `
            else
            {
                LogError ("Failed to retrieve file [{0}] from SharePoint in {1}." -f @($libInfo.FileURL, $me.Name))
            }
        }

        if(-not $Script:HaveError)
        {
            if($null -ne $spFile)
            {
                # Now, get all the versions of the file from SharePoint.
                try
                {
                    # This verison data contains the FieldValues I need to determine which version has the right "DocumentVersion", but does not
                    #    include the document URL I need.  It does have .VersionLabel which I'll use to link to $referenceSPDocVersions below.
                    # This works for a file with only 1 version.
                    $versions = Get-PnPProperty -ClientObject $spFile -Property Versions -ErrorAction Stop
                }
                catch
                {
                    LogError ("Failed to get field value versions for {0} in {1}." -f @($spFileURL, $me.Name))
                }

                if(-Not $Script:HaveError)
                {
                    if($null -ne $versions)
                    {
                        # Always attach the verion information to the current version of the document, it's where it comes from after all.

                        # Now, get all the version references of the file from SharePoint.
                        try
                        {
                            # This 'version' data contains the URL and VersionLabel
                            $referenceSPDocVersions = Get-PnpFileVersion -URL $libInfo.FileURL -ErrorAction Stop
                        }
                        catch
                        {
                            LogError ("Failed to get reference versions for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                        }

                        if(-not $Script:HaveError)
                        {
                            $docVerToLink = [System.Collections.Generic.SortedDictionary[String, String]]::new()

                            # Add the current document's version and link to the dictionary.
                            $docVerToLink.Add($currentVersionOfDocument.SourceObject.Version, $libInfo.FileURL)

                            if($Script:DoDebugging)
                            {
                                # LogInfo ("`tadded: {0}, {1}" -f @($currentVersionOfDocument.SourceObject.Version, $libInfo.FileURL))
                            }

                            if($null -ne $referenceSPDocVersions)
                            {
                                $f = 0
                                while($f -lt $versions.Count)
                                {
                                    $refSPDocVer = $referenceSPDocVersions.Where({ $_.VersionLabel -eq $versions[$f].VersionLabel })
                                    if($null -ne $refSPDocVer)
                                    {
                                        if($versions[$f].FieldValues.ContainsKey("DocumentVersion"))
                                        {
                                            if(-not $docVerToLink.ContainsKey($versions[$f].FieldValues["DocumentVersion"]))
                                            {
                                                $docVerToLink.Add($versions[$f].FieldValues["DocumentVersion"], $refSPDocVer.Url)
                                                if($Script:DoDebugging)
                                                {
                                                    LogInfo ("`tadded: {0}, {1}" -f @($versions[$f].FieldValues["DocumentVersion"], $refSPDocVer.Url))
                                                }
                                            } `
                                            else
                                            {
                                                if($versions[$f].FieldValues["DocumentVersion"] -ne $currentVersionOfDocument.SourceObject.Version)
                                                {
                                                    LogError ("Duplicate document version {0} for {1} in {2}." -f @($versions[$f].FieldValues["DocumentVersion"], $libInfo.FileURL, $me.Name))
                                                } `
                                                else
                                                {
                                                    # Nothing, since I added the original version above, ignore it here...
                                                }
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Document {0} missing DocumentVersion field in {1}." -f @($libInfo.FileURL, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # This is the current version and there is no "version history" for it...
                                    }
                                    $f++
                                }
                            } `
                            else
                            {
                                # LogError ("Failed to get field reference versions for {0} in {1}.  Null value returned" -f @($libInfo.FileURL, $me.Name))
                                # Nothing, no old versions of the file...
                            }

                            if(-not $Script:HaveError)
                            {
                                $currentVersionOfDocument.SPData.DocVersionToLink = $docVerToLink
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        LogError ("Failed to get field value versions for {0} in {1}.  Null value returned" -f @($libInfo.FileURL, $me.Name))
                    }
                } `
                else
                {
                    # Nothing, already displayed an error.
                }
            } `
            else
            {
                # Nothing, file not found...
            }
        } `
        else
        {
            # Nothing, either displayed an error, or no file was found.
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function FindProjectFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object[]] $pwRootFolders,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName
    )

    $me = $MyInvocation.MyCommand
    $pwFolders = [System.Collections.Generic.List[System.Object]]::new()
    $pn = $projectName

    if($null -ne $pwRootFolders)
    {
        $b = 0
        while((-not $Script:HaveError) -and ($b -lt $pwRootFolders.Length) -and (-not [String]::IsNullOrEmpty($pn)))
        {
            $pwPath = "{0}\{1}" -f @($pwRootFolders[$b].Name, $pn)

            if($Script:DoDebugging)
            {
                Write-Host ("`tlooking for {0} in {1}..." -f @($pn, $pwRootFolders[$b].Name))
            }

            try
            {
                $pwFolder = Get-PWFolders -FolderPath $pwPath -JustOne -Slow -ErrorAction Stop 3> $null
            }
            catch
            {
                LogError ("Unable to get ProjectWise folders in {0}." -f @($me.Name))
            }

            if($null -ne $pwFolder)
            {
                if($Script:DoDebugging)
                {
                    Write-Host ("`t`t...located")
                }
                $j = [PSCustomObject]@{
                    RequestedProjectName = $projectName
                    LocatedProjectName = $pn
                    Description = $pwFolder.Description
                    FullPath = $pwFolder.FullPath
                    DataSource = $pwDatasource
                }
                $pwFolders.Add($j)
            } `
            else
            {
                # Nothing, already displayed an error
            }

            if(-not $Script:HaveError)
            {
                # Nope....

                # Are there more root folders?
                if($b -lt ($pwRootFolders.Length - 1))
                {
                    # Yes, check the next root folder...
                    $b++
                } `
                else
                {
                    # No...

                    # Does the project name start with a 0?
                    if($pn -match "^0(.*)$")
                    {
                        # Yes...

                        # Remove a 0 and try again...
                        $pn = $Matches[1]

                        # Start back at the first root folder
                        $b = 0
                    } `
                    else
                    {
                        # Nope, set $pn = $null to escape the loop...
                        $pn = $null
                    }
                }
            } `
            else
            {
                # Nothing, found the project folder, or an error occurred.
            }
        }
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    if($Error.Count -gt 0)
    {
        $pwFolder = $null
    } `
    else
    {
        # Nothing, send the folder back to the caller.
    }

    return @( ,$pwFolders)
}

function FindManyProjectFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String[]] $projectNames
    )

    $projectData = [System.Collections.Generic.List[System.Object]]::new()

    $me = $MyInvocation.MyCommand
    $a = 0
    $pwFolder = $null
    while((-not $Script:HaveError) -and ($null -eq $pwFolder) -and ($a -lt $Script:connData.ConnectionInformation.ProjectWiseDatasources.Length))
    {
        $Script:pwDatasource = $Script:connData.ConnectionInformation.ProjectWiseDatasources[$a]

        if($Script:DoDebugging)
        {
            Write-Host ("Connecting to {0}:{1}..." -f @($Script:connData.ConnectionInformation.ProjectWiseServer, $Script:pwDatasource))
        }

        try
        {
            $null = Undo-PWLogin -ErrorAction Stop
        }
        catch
        {
            $Error.Clear()
        }

        if(ConnectToPW)
        {
            if($Script:DoDebugging)
            {
                Write-Host ("...getting root folders...")
            }

            $pwRootFolders = $null
            try
            {
                $pwRootFolders = @(Get-PWFoldersImmediateChildren -Root -ErrorAction Stop)
            }
            catch
            {
                LogError ("Failed to get root folder from {0}:{1} in {2}." -f @($Script:connData.ConnectionInformation.ProjectWiseServer, $Script:pwDatasource, $me.Name))
            }

            if($null -ne $pwRootFolders)
            {
                $c = 0
                while($c -lt $projectNames.Length)
                {
                    $pwFolders = FindProjectFolders -projectName $projectNames[$c] -pwRootFolders $pwRootFolders

                    if($pwFolders.Count -gt 0)
                    {
                        @($pwFolders).ForEach({
                            $projectData.Add($_)
                        })
                    } `
                    else
                    {
                        $j = [PSCustomObject]@{
                            RequestedProjectName = $projectNames[$c]
                            LocatedProjectName = "Not found"
                            Description = [String]::Empty
                            DataSource = $Script:pwDatasource
                            FullPath = [String]::Empty
                        }
                        $projectData.Add($j)
                    }
                    $c++
                }
            } `
            else
            {

            }
        } `
        else
        {
            LogError ("Failed to connect to ProjectWise server {0}:{1} in {2}." -f @($Script:connData.ConnectionInformation.ProjectWiseServer, $Script:pwDatasource, $me.Name))
        }
        $a++
    }

    return @(,$projectData)
}

function FixUpViablePaths
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $me = $MyInvocation.MyCommand
    if($viablePathsDict.ContainsKey($pwData.PWFolder.DocumentGUID))
    {
        if(-not [String]::IsNullOrEmpty($viablePathsDict[$pwData.PWFolder.DocumentGUID].SPData.FolderName))
        {
            # Have we already fixed this viable paths dictionary up?  Or perhaps created it correctly??
            if($viablePathsDict[$pwData.PWFolder.DocumentGUID].SPData.FolderName -match "^Active|Inactive Projects")
            {
                # Nope, still need to fix it up.

                $vpKeys = @($viablePathsDict.Keys)
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $vpKeys.Length))
                {
                    $vp = $viablePathsDict[$vpKeys[$a]]

                    if(-not [String]::IsNullOrEmpty($vp.SPData.FolderName))
                    {
                        $pathPieces = $vp.SPData.FolderName -split "/"
                        if($pathPieces[0] -match "Active|Inactive Projects")
                        {
                            # Drop off the ProjectWise project parent folder (pwProjectPath) and the project folder...
                            $vp.Paths = $vp.Paths | Select-Object -Skip 2

                            if($vp.SourceObject.MyType -eq "ProjectWiseFolder")
                            {
                                $vp.SPData.FolderName = $vp.Paths -join "/"
                                $vp.SPData.FileName = [String]::Empty
                            } `
                            elseif($vp.SourceObject.MyType -eq "ProjectWiseDocument")
                            {
                                $vp.SPData.FolderName = $vp.Paths[0..($vp.Paths.Length - 2)] -join "/"
                                $vp.SPData.FileName = $vp.Paths[-1]
                            }
                        } `
                        else
                        {
                            LogError ("Unknown path for {0}:{1} in {2}." -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Empty SPData folder name for {0}:{1}")
                    }
                    $a++
                }
            } `
            else
            {
                # Nothing, already fixed up this viable paths dictionary.
            }
        } `
        else
        {
            LogError ("Missing SPData.FolderName for {0}:{1} in {2}." -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
        }

    } `
    else
    {
        LogError ("Viable paths data and PW Data are out of sync in {0}." -f @($me.Name))
    }
}
