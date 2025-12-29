
function ConnectPW
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $pwDatasource,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $pwUserName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [SecureString] $pwPassword
    )

    $pwEnvironment = "{0}:{1}" -f @($pwServer, $pwDatasource)
    $connected = $false
    try
    {
        $connected = New-PWLogin -DatasourceName $pwEnvironment -UserName $pwUserName -Password $pwPassword -ErrorAction Stop *> $null
    }
    catch
    {

    }

    return $connected
}


ConnectTo vCenter,prod
$pwCreds = (Get-ConnectCredentials "projectwise").Credential
Import-Module pwps_dab

$pwServer = "cdc-pwdint02.powereng.com"
$pwDatasource = "pw_prod_pw01"
#$pwDatasource = "pw_prod_pw02"
#$pwDatasource = "pw_prod_dmsclosed"
#$pwDatasource = "pw_prod_acq_archive"
$pwUserName = $pwCreds.UserName
$pwPassword = $pwCreds.Password

ConnectPW -pwServer $pwServer -pwDatasource $pwDatasource -pwUserName $pwUserName -pwPassword $pwPassword

function CaptureProjectWiseDataToJSON
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $localPath
    )

    $retval = [PSCustomObject]@{
        JSONData = $null
        JSONFile = $null
        PWFolder = $null
    }

    $Error.Clear()

    if([System.IO.Directory]::Exists($localPath))
    {
        try
        {
            # Get the associated ProjectWise folder along with all the relevant data "-Slow" ...
            Write-Host ("Getting PW Folder for {0}..." -f @($pwProjectPath))
            $retval.PWFolder = Get-PWFolders -FolderPath $pwProjectPath -JustOne -Slow 3> $null
        }
        catch
        {
            Write-Error ("Failed to locate ProjectWise Folder using path: {0}" -f @($pwProjectPath))
            $retval.PWFolder = $null
        }

        if($null -ne $retval.PWFolder)
        {
            $Global:flatSets = [System.Collections.Generic.SortedDictionary[String, Object]]::new()

            # The code below looks odd, we are getting data, but returning it to $null.  The reason is,
            #    the code behind actaully populates $retval.PWFolder with the returned data.

            try
            {
                # Get a list of all the subfolders in the project
                Write-Host "Getting project subfolders..."
                $null = $retval.PWFolder.GetSubFolders()
            }
            catch
            {
                Write-Error ("Failed to get project subfolders.")
                $retval.PWFolder = $null
            }

            if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    Write-Host "Getting project document tree..."
                    $null = $retval.PWFolder.GetTreeDocuments()
                }
                catch
                {
                    Write-Error ("Failed to get project documents.")
                    $retval.PWFolder = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
            {
                #  NOTE:  Check for IsSet before GetGeneralProperties and GetCustomAttributes ....
                #     Need to know if they need to be successful before evaluting .IsSet...

                Write-Host "Getting project document properties and custom attributes..."
                # Now, populate all the attributes for the documents.
                $totalDocuments = $retval.PWFolder.TreeDocuments.Count
                $i = 0
                while(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder) -and ($i -lt $retval.PWFolder.TreeDocuments.Count))
                {
                    $pc = [float] $i / [float] $totalDocuments
                    Write-Progress -Id 1 -Activity ("Processing Document {0} of {1}" -f @(($i+1), $totalDocuments)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)
                    try
                    {
                        $null = $retval.PWFolder.TreeDocuments[$i].GetGeneralProperties()
                    }
                    catch
                    {
                        Write-Error ("Failed to retrieve general properties for {0}" -f @($retval.PWFolder.TreeDocuments[$i].FullPath))
                        $retval.PWFolder = $null
                        break
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        try
                        {
                            $null = $retval.PWFolder.TreeDocuments[$i].GetCustomAttributes()
                        }
                        catch
                        {
                            Write-Error ("Failed to retrieve custom attributes for {0}" -f @($retval.PWFolder.TreeDocuments[$i].FullPath))
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        if($retval.PWFolder.TreeDocuments[$i].IsSet)
                        {
                            try
                            {
                                $fs =  Get-PWDocumentFlatSetMembers -FolderPath $retval.PWFolder.TreeDocuments[$i].FolderPath -SetName $retval.PWFolder.TreeDocuments[$i].Name -ErrorAction Stop
                                $Global:flatSets.Add($retval.PWFolder.TreeDocuments[$i].FullPath, $fs)
                            }
                            catch
                            {
                                Write-Error ("Failed to acquire flat set: {0} from {1}." -f @($retval.PWFolder.TreeDocuments[$i].Name, $retval.PWFolder.TreeDocuments[$i].FolderPath))
                            }
                        } `
                        else
                        {
                            # Not a flatset, so nothing to do here.
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }

                    $i++
                }

                Write-Progress -Id 1 "Finished" -Completed
                if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                {
                    # Dump a copy of the project data to the local folder.
                    $retval.JSONFile = "{0}\{1}.pwdata.json" -f @($localPath, $retval.PWFolder.Name)
                    try
                    {
                        Write-Host "Converting project data to json format..."
                        $retval.JSONData = $retval.PWFolder | ConvertTo-Json -Depth 10 -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Error "Failed to convert project data structure to JSON format."
                        $retval.JSONData = $null
                        $retval.JSONFile = $null
                        $retval.PWFolder = $null
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        if(-not [String]::IsNullOrEmpty($retval.JSONData))
                        {
                            try
                            {
                                Write-Host ("Saving project data to {0}..." -f @($retval.JSONFile))
                                $retval.JSONData | Set-Content -Path $retval.JSONFile -ErrorAction Stop
                            }
                            catch
                            {
                                Write-Error ("Failed to save project data to {0}." -f @($retval.JSONFile))
                                $retval.JSONData = $null
                                $retval.JSONFile = $null
                                $retval.PWFolder = $null
                            }
                        } `
                        else
                        {
                            Write-Warning "No project 'JSON' data to save."
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }
                } `
                else
                {
                    # Should have already displayed an error
                }
            } `
            else
            {
                # Should have already displayed an error
            }
        } `
        else
        {
            # Should have already displayed an error.
        }
    } `
    else
    {
        Write-Error ("{0} not found.  Please provide an existing path." -f @($localPath))
    }

    return $retval
}

$localPath = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest"
$pwProjectPath = "Archive Projects\136723"

# Get relevant information from ProjectWise
$pwData = CaptureProjectWiseDataToJSON -pwProjectPath $pwProjectPath -localPath $localPath
