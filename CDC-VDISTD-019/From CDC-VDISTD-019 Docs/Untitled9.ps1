function ImportFilesToProjectWise
{
    if($Script:ReturnObject.Good2Go)
    {
        if($Script:ReturnObject.ExportedItems.Count -gt 0)
        {
            $exportedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            if($Script:ExportedAsICS)
            {
                try
                {
                    @(Get-ChildItem -Path $Script:WorkingFolder -Filter "*.ics" -ErrorAction Stop).ForEach({
                        $exportedFiles.Add($_)
                    })
                }
                catch
                {
                    LogException "Failed to generate list of exported files."
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else # NOT ($Script:ExportedAsICS)
            {
                if($null -ne $Script:PublicFolderItems)
                {
                    if($Script:PublicFolderItems.Count -gt 0)
                    {
                        $a = 0
                        while($a -lt $Script:PublicFolderItems.Count)
                        {
                            $pfObj = $Script:PublicFolderItems[$a]
                            if($pfObj.Good2Go)
                            {
                                if($pfObj.Saved2Temp)
                                {
                                    if($pfObj.Renamed)
                                    {
                                        try
                                        {
                                            $fi = [System.IO.FileInfo]::new($pfObj.FileName)
                                        }
                                        catch
                                        {
                                            LogError ("{0} not found." -f @($pfObj.FileName))
                                            $pfObj.Good2Go = $false
                                            UpdatePublicFolderObjectStatus -pfObj $pfObj "File not found during import"
                                            $fi = $null
                                        }

                                        if($null -ne $fi)
                                        {
                                            $exportedFiles.Add($fi)
                                        } `
                                        else # NOT ($null -ne $fi)
                                        {
                                            # Nothing.
                                        }
                                    } `
                                    else # NOT ($pfObj.Renamed)
                                    {
                                        # Nothing.
                                    }
                                } `
                                else # NOT ($pfObj.Saved2Temp)
                                {
                                    # Nothing.
                                }
                            } `
                            else # NOT ($pfObj.Good2Go)
                            {
                                # Nothing.
                            }

                            $a++
                        }
                    } `
                    else # NOT ($Script:PublicFolderItems.Count -gt 0)
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($null -ne $Script:PublicFolderItems)
                {
                    # Nothing.
                }
            }

            if($Script:ReturnObject.Good2Go)
            {
                if($exportedFiles.Count -gt 0)
                {
                    LogInfo ("Found {0} items to import into ProjectWise." -f @($exportedFiles.Count))

                    $pwFolderPath = $Script:ExportedPublicFolderPath

                    # Verify the existence of the corresponding folder structure in ProjectWise, creating any missing folders.
                    $pwFolderExists, $pwFolder = VerifyCreatePWPath -path $pwFolderPath -Create
                    if($pwFolderExists)
                    {
                        if($Script:ReturnObject.Good2Go)
                        {
                            LogInfo ("Importing items into ProjectWise folder: {0}" -f @($pwFolderPath))

                            $importFolderName = CreateIntermediateTempFolder
                            if($Script:ReturnObject.Good2Go)
                            {
                                $a = 0
                                while($Script:ReturnObject.Good2Go -and ($a -lt $exportedFiles.Count))
                                {
                                    $newFileName = "{0}\{1}" -f @($importFolderName, $exportedFiles[$a].Name)
                                    try
                                    {
                                        [System.IO.File]::Move($exportedFiles[$a].FullName, $newFileName)
                                    }
                                    catch
                                    {
                                        LogError ("Failed to move {0} to {1}." -f @($exportedFiles[$a].FullName, $newFileName))
                                        $Script:ReturnObject.Good2Go = $false
                                    }

                                    $a++

                                    # After moving $Script:MaxFilesPerImport files (or the last file) into the ImportToPW folder:
                                    #    1. Import the files in ImportToPW into ProjectWise
                                    #    2. Delete all the files in ImportToPW
                                    if($Script:ReturnObject.Good2Go -and (($a % $Script:MaxFilesPerImport) -eq 0) -or ($a -eq $exportedFiles.Count))
                                    {
                                        ImportFolderToProjectWise -importFolder $importFolderName

                                        if($a -lt $exportedFiles.Count)
                                        {
                                            # After importing the folder, if there are more files to import, create another temporary folder
                                            $importFolderName = CreateIntermediateTempFolder    # while loop will check $Script:ReturnObject.Good2Go
                                        } `
                                        else # NOT ($a -lt $exportedFiles.Count)
                                        {
                                            # Nothing.
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, keep going until an error occured, we put 1000 items in the import folder, or we get to the end...
                                    }
                                }
                            } `
                            else # NOT ($Script:ReturnObject.Good2Go)
                            {
                                # Nothing.
                            }

                            if($Script:ReturnObject.Good2Go)
                            {
                                LogInfo ("Imported {0} items totalling {1}" -f @($Script:ReturnObject.ImportedItems.Count, (Format-StorageNumber $Script:ReturnObject.ImportedItems.Size)))
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed a message.
                        }
                    } `
                    else # NOT (VerifyCreatePWPath -path $pwFolderPath -Create)
                    {
                        # Nothing.
                    }
                } `
                else
                {
                    LogError ("No files found in {0} to import into ProjectWise." -f @($Script:WorkingFolder))
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, already displayed an error
            }
        } `
        else # NOT ($Script:ReturnObject.ExportedItems.Count -gt 0)
        {
            LogInfo "No files exported from public folder.  Skipping import to ProjectWise."
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}
