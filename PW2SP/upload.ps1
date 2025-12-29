function GetSPDocumentVersions_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $docURL
    )

    $me = $MyInvocation.MyCommand
    $retval = [System.Collections.Generic.List[System.Object]]::new()
    try
    {
        # This only works for the current version of the file....
        $spFile = Get-PnPFile -URL $docURL -AsListItem -ErrorAction Stop
        $retval.Add($spFile)
        if($null -ne $spFile)
        {
            # Now, get all the versions of the file from SharePoint.
            try
            {
                # This verison data contains the FieldValues I need to determine which version has the right "DocumentVersion", but does not
                #    include the document URL I need.  It does have .VersionLabel which I'll use to link to $referenceSPDocVersions below.
                # This works for a file with only 1 version.
                $versions = Get-PnPProperty -ClientObject $spFile -Property Versions -ErrorAction Stop
                $versions | ForEach-Object { $retval.Add($_) }
            }
            catch
            {
                LogError ("Failed to get additional versions of {0} in {1}." -f @($spFileURL, $me.Name))
            }
        } `
        else
        {
            # Nothing....
        }
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

    return @( , $retval)
}

function TempMakeDocLibField
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
        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($newDocLibName))
        {
            # Have the library...
            LogInfo ("Creating key document fields in document library '{0}'." -f @($newDocLibName))
            @($Script:connData.documentFields.Keys).ForEach({
                $df = $Script:connData.documentFields[$_]
                if($df.CreateWithNewLibrary)
                {
                    $fld = TestForSPDocumentLibraryField -libraryName $newDocLibName -fieldName $df.InternalName -displayName $df.DisplayName
                } `
                else
                {
                    # Nothing.
                }

                if($Script:HaveError)
                {
                    break
                } `
                else
                {
                    # Press on....
                }
            })
        } `


}

function getlistTest
{
    $pwDataFiles = @(Get-ChildItem -Path "E:\PW2SPReport" -Filter "*_PWDATA.json" -Recurse)
    $a = 0
    $attribsAndProps = [System.Collections.Generic.SortedDictionary[String,Int32]]::new()
    while($a -lt $pwDataFiles.Length)
    {
        Write-Host ("Processing {0}" -f @($pwDataFiles[$a].FullName))
        $pd = LoadPWDataFromJSON -filePath $pwDataFiles[$a].FullName

        @($pd.ProjectWiseObjects.Values).ForEach({
            if($_.MyType -eq "ProjectWiseFolder")
            {
                @($_.ProjectProperties.Keys).ForEach({
                    if(-not $attribsAndProps.ContainsKey($_))
                    {
                        $attribsAndProps.Add($_, 0)
                    }
                    $attribsAndProps[$_]++
                })
            } `
            else
            {
                @($_.Attributes.Keys).ForEach({
                    if(-not $attribsAndProps.ContainsKey($_))
                    {
                        $attribsAndProps.Add($_, 0)
                    }
                    $attribsAndProps[$_]++
                })
            }
        })

        $a++
    }
}

function ConvertProjectFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $projName
    )

    $myProject = $null
    $projectListFile = "E:\PW2SPReport\projectList.csv"
    $projList = Import-csv -Delimiter "`t" -Path $projectListFile
    $myProject = $projList.Where({ ($_.projectName -eq $projName) }) | Select-Object -First 1

    if($null -ne $myProject)
    {
        $Script:projectName = $myProject.projectName
        $Script:pwProjectPath = $myProject.pwProjectPath
        $Script:localPath = "E:\PW2SPProd"
        $Script:pwDatasource = $myProject.pwDatasource

        Init
        LogInfo ("PID: {0}`r`nLog file: {1}" -f @($PID, $Script:LogFileName))
        LogInfo ("{0}:{1}\{2}" -f @($myProject.pwDatasource, $myProject.pwProjectPath, $myProject.projectName))

        # Refresh the library dictionary
        BuildDocumentLibraryDictionary
        if(-not $Script:HaveError)
        {
            # Refresh the defined fields
            GetLibraryDefinedFieldsList -libraryName $myProject.pwProjectPath

            if(-not $Script:HaveError)
            {
                # Load the ProjectWise data
                $pwData = LoadLatestPWData

                if(-not $Script:HaveError)
                {
<#
                    # Build viable paths dictionary
                    $addedNewFolders,$pathDict = CreatePathDictionary -pwData $pwData

                    if(-not $Script:HaveError)
                    {
                        FixLongPaths -pathDict $pathDict

                        if(-not $Script:HaveError)
                        {
                            $viablePathsDict = BuildViablePathsDictionary -pwData $pwData -fromNode $pathDict["ROOT"].Children

                            if(-not $Script:HaveError)
                            {
                                UpdateViablePathsFromLastRun -pwData $pwData -viablePathsDict $viablePathsDict
#>
                                if(-not $Script:HaveError)
                                {
                                    BuildInitialReport -pwData $pwData
                                    LogInfo ("{0}`t{1}`t{2}`t{3}`t{4}" -f @($Script:reportData.Folders.InProject, $Script:reportData.Documents.InProject, $Script:reportData.DocumentSets.InProject, $Script:reportData.DocumentLinks.InProject, (Format-StorageNumber $Script:reportData.Size.InProjectWise)))

                                    CreateProjectDocumentLibrary -newDocLibName $Script:projectName -forExistingProject
                                    if(-not $Script:HaveError)
                                    {
                                        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($Script:projectName))
                                        {
                                            $projectDocLib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$Script:projectName]

                                            if($null -ne $projectDocLib)
                                            {
                                                $projectParams = GetProjectProperties -pwData $pwData

                                                if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($myProject.pwProjectPath))
                                                {
                                                    $destLib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$myProject.pwProjectPath]

                                                    if(-not $Script:HaveError)
                                                    {
                                                        CreateLinkInFolder -linkName ("{0}.url" -f @($Script:projectName)) -linkURL ("{0}{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $projectDocLib.DefaultViewUrl)) -folderURL $destLib.RootFolder.ServerRelativeUrl -linkParams $projectParams
                                                    }
                                                }
                                            } `
                                            else
                                            {
                                                LogError ("No document library found for {0} in {1}." -f @($Script:projectName, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Missing document library for {0} in {1}." -f @($Script:projectName, $me.Name))
                                        }
                                    }
                                }
<#
                            }
                        }
                    }
#>
                }
            }
        }
    }
}

$projectToConvert = @("163925", "164116", "166413", "166414", "173043", "177301", "0239208_0000", "0240582_0000", "0241907_0001", "0244179_0000", "0245838_0000", "0246806_0000")
$projectsToMove = @("145316", "155126", "156894", "162018")

$projectToConvert.ForEach({

    # ConvertProjectFolder -projName $_
})

function MoveProjectFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $projName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $docLibName
    )

    try
    {
        $srcLib = Get-PnPList -Identity $docLibName -ErrorAction Stop
        Write-Host ("Source: {0}" -f @($srcLib.Title))
    }
    catch
    {
        LogError ("Failed to retrieve source document library '{0}'" -f @($docLibName))
    }

    if((-not $Script:HaveError) -and ($null -ne $srcLib))
    {
        try
        {
            $destLib = Get-PnPList -Identity $projName -ErrorAction Stop
            Write-Host ("Destination: {0}..." -f @($destLib.Title))
        }
        catch
        {
            if(($Error.Count -gt 0) -and ($Error[0].Exception.Message -match "does not exists at site"))
            {
                $Error.Clear()
            } `
            else
            {
                LogError ("Failed to retrieve destination document library '{0}'" -f @($docLibName))
            }
        }
    }

    if((-not $Script:HaveError) -and ($null -ne $srcLib) -and ($null -ne $destLib))
    {
        $srcFolders = @()
        try
        {
            $srcFolders = @(Get-PnPFolderInFolder -Identity ("{0}/{1}" -f @($docLibName, $projName)) -ErrorAction Stop)
        }
        catch
        {
            LogError ("Failed to retrieve source folders for project {0}." -f @($projName))
        }

        if(-not $Script:HaveError)
        {
            Write-Host ("`tFolders in source: {0}" -f @($srcFolders.Length))
            if($srcFolders.Length -gt 0)
            {
                $srcFolders.ForEach({ Write-Host ("`t`t{0}" -f @($_.Name))})
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $srcFolders.Length))
                {
                    $pc = [float] $a / [float] $srcFolders.Length
                    Write-Progress -Id 1 -Activity ("Moving project folders | {0} of {1}" -f @(($a+1), $srcFolders.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                    $srcUrl = $srcFolders[$a].ServerRelativeUrl
                    $srcSplit = $srcUrl -split "/"
                    if($srcSplit.Length -eq 6)
                    {
                        $tarUrl = "/{0}/{1}/{2}" -f @($srcSplit[1], $srcSplit[2], $srcSplit[4])

                        try
                        {
                            Move-PnPFile -SourceUrl $srcUrl -TargetUrl $tarUrl -AllowSchemaMismatch -Force -ErrorAction Stop
                        }
                        catch
                        {
                            LogError ("Failed to move {0} to {1}." -f @($srcUrl, $tarUrl))
                        }
                    } `
                    else
                    {
                        LogError ("Too few pieces in {0}." -f @($srcUrl))
                    }

                    $a++
                }
            }
        }

        if(-not $Script:HaveError)
        {
            $srcFiles = @()
            try
            {
                $srcFiles = @(Get-PnPFileInFolder -Identity ("{0}/{1}" -f @($docLibName, $projName)) -ErrorAction Stop)
            }
            catch
            {
                LogError ("Failed to retrieve source files for project {0}." -f @($projName))
            }

            if(-not $Script:HaveError)
            {
                Write-Host ("`tFiles in source: {0}" -f @($srcFiles.Length))
                if($srcFiles.Length -gt 0)
                {
                    $srcFiles.ForEach({ Write-Host ("`t`t{0}" -f @($_.Name))})
                    $a = 0
                    while((-not $Script:HaveError) -and ($a -lt $srcFiles.Length))
                    {
                        $pc = [float] $a / [float] $srcFiles.Length
                        Write-Progress -Id 1 -Activity ("Moving project files | {0} of {1}" -f @(($a+1), $srcFiles.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                        $srcUrl = $srcFiles[$a].ServerRelativeUrl
                        $srcSplit = $srcUrl -split "/"
                        if($srcSplit.Length -eq 6)
                        {
                            $tarUrl = "/{0}/{1}/{2}/{3}" -f @($srcSplit[1], $srcSplit[2], $srcSplit[4], $srcSplit[5])

                            try
                            {
                                Move-PnPFile -SourceUrl $srcUrl -TargetUrl $tarUrl -AllowSchemaMismatch -Force -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to move {0} to {1}." -f @($srcUrl, $tarUrl))
                            }
                        } `
                        else
                        {
                            LogError ("Too few pieces in {0}." -f @($srcUrl))
                        }

                        $a++
                    }
                }
            }

            if(-not $Script:HaveError)
            {
                <#
                if(($srcFolders.Length -gt 0) -or ($srcFiles.Length -gt 0))
                {
                    Write-Host "Pausing while SharePoint catches up..."
                    Start-Sleep -Seconds 30
                }
                #>
                # One last sanity check...
                $srcFolders2 = @()
                try
                {
                    $srcFolders2 = @(Get-PnPFolderInFolder -Identity ("{0}/{1}" -f @($docLibName, $projName)) -ErrorAction Stop)
                }
                catch
                {
                    LogError ("Failed to retrieve source folders for project {0} after move." -f @($projName))
                }
                if($srcFolders2.Length -gt 0)
                {
                    Write-Host -ForegroundColor Red ("`tFolders remaining on source: {0}" -f @($srcFolders2.Length))
                } `
                else
                {
                    Write-Host -ForegroundColor Green ("`tFolders remaining on source: {0}" -f @($srcFolders2.Length))
                }
                if(-not $Script:HaveError)
                {
                    $srcFiles2 = @()
                    try
                    {
                        $srcFiles2 = @(Get-PnPFileInFolder -Identity ("{0}/{1}" -f @($docLibName, $projName)) -ErrorAction Stop)
                    }
                    catch
                    {
                        LogError ("Failed to retrieve sourve files for project {0} after move." -f @($projName))
                    }
                    if($srcFiles2.Length -gt 0)
                    {
                        Write-Host -ForegroundColor Red ("`tFiles remaining on source: {0}" -f @($srcFiles2.Length))
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Green ("`tFiles remaining on source: {0}" -f @($srcFiles2.Length))
                    }

                    if(-not $Script:HaveError)
                    {
                        # another sanity check...
                        $destFolders = @()
                        try
                        {
                            $destFolders = @(Get-PnPFolderInFolder -Identity ("{0}" -f @($projName)) -ErrorAction Stop)
                        }
                        catch
                        {
                            LogError ("Failed to retrieve folders for project {0}." -f @($projName))
                        }

                        $hasForms = $destFolders.Where({ $_.Name -eq "Forms" }).Count
                        if($srcFolders.Length -eq ($destFolders.Length - $hasForms))
                        {
                            Write-Host -ForegroundColor Green ("`tFolders in destination: {0}" -f @($destFolders.Length))
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Red ("`tFolders in destination: {0}" -f @($destFolders.Length))
                        }
                        $destFolders.ForEach({ Write-Host ("`t`t{0}" -f @($_.Name))})

                        if(-not $Script:HaveError)
                        {
                            $destFiles = @()
                            try
                            {
                                $destFiles = @(Get-PnPFileInFolder -Identity ("{0}" -f @($projName)) -ErrorAction Stop)
                            }
                            catch
                            {
                                LogError ("Failed to retrieve files for project {0}." -f @($projName))
                            }
                            if($srcFiles.Length -eq $destFiles.Length)
                            {
                                Write-Host -ForegroundColor Green ("`tFiles in destination: {0}" -f @($destFiles.Length))
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Red ("`tFiles in destination: {0}" -f @($destFiles.Length))
                            }
                            $destFiles.ForEach({ Write-Host ("`t`t{0}" -f @($_.Name))})

                            if(-not $Script:HaveError)
                            {
                                if(($srcFolders2.Length -eq 0) -and ($srcFiles2.Length -eq 0) -and ($srcFolders.Length -eq ($destFolders.Length - $hasForms)) -and ($srcFiles.Length -eq $destFiles.Length))
                                {
                                    Write-Host -ForegroundColor Yellow ("`tRemoving empty source folder {0}" -f @($projName))
                                    # Remove the project file...
                                    Remove-PnpFolder -Name $projName -Folder $docLibName -Force
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


$docLibsToCheck.ForEach({
    # CheckAndFixDocLibFields -projName $_ -existingProject
})

$projectsToMove = @(
    "142678","174296","160567","153311","161978","150800","144005","146404","175650","151372","161785",
    "161161","156954","153053","174557","142767","151646","155494","146340","149433","166342","157201",
    "142734","156009","162012","148161","144529","135785","153766","158354","147017","157668","153400",
    "155522","158876","141863","139811","140390","153436","176605","146334","149166","143111","135643",
    "153003","156555","153413","142763","154787","144994","154668","164724","153866","131820","133625",
    "132707","144246","148840","146930","135931","153414","167419","136923","156870","135977","144365",
    "154976","158741","138729","155996","155279","138166","148169","160062","144790","144172","155350",
    "168501","159137","135190","154745","140034","151697","150797","149909","154795","145553","129212",
    "147143","143506","154638","162003","144532","163380","143372","154194","158813","142201","148091",
    "142684","143504","150549","141101","144148","173043"
)

$projectsToMove.ForEach({
    # MoveProjectFolder -projName $_ -docLibName "Shared Documents"
})


$projectListFile = "E:\PW2SPReport\projectList.csv"
$projList = Import-csv -Delimiter "`t" -Path $projectListFile
$projName = "134945"
$projName = "162018"
$projName = "177301"
$projName = "145316"
$projName = "156894"
$projName = "180015"
$projName = "173793"
$projName = "0241907_0001"
$projName = "157562"
$myProject = $projList.Where({ $_.projectName -eq $projName })
if($myProject.Count -eq 1)
{
    $Script:projectName = $myProject[0].projectName
    $Script:pwDatasource = $myProject[0].pwDatasource
    $Script:pwProjectPath = $myProject[0].pwProjectPath


    <#  Proposal testing... #>
    $Script:ProjectName = "2020-01-0014"
    $Script:pwDataSource = "pw_prod_pw01"
    $Script:pwProjectPath = "Proposals - Archive"

    [Switch] $Script:dbgOut = $true
    [Switch] $Script:DoExport = $true
    [Switch] $Script:restart = $true
    $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"
    $Script:pwPassword = "tX2NPfAK92DhM2"
    $Script:localPath = "E:\PW2SPProd"

    if($null -eq $function:main)
    {
        . C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1
    }

    Init

    # Proposal testing...
    $pwData = GetProjectWiseData

    $pwData = LoadLatestPWData

    $addedNewFolders,$pathDict = CreatePathDictionary -pwData $pwData -CreateMissingLibrary:$Script:DoExport

    FixLongPaths -pathDict $pathDict

    $viablePathsDict = BuildViablePathsDictionary -pwData $pwData -fromNode $pathDict["ROOT"].Children

    UpdateViablePathsFromLastRun -pwData $pwData -viablePathsDict $viablePathsDict

    # FixUpViablePaths -pwData $pwData -viablePathsDict $viablePathsDict

    BuildInitialReport -pwData $pwData
    $reportJSON = $Script:reportData | ConvertTo-Json -Depth 10
    # LogInfo ($reportJSON)
    LogInfo ("Folders: {0}`tDocuments: {1}`tFlatSets: {2}`tFlatSet References: {3}`tSize: {4}" -f @($Script:reportData.Folders.InProject, $Script:reportData.Documents.InProject, $Script:reportData.DocumentSets.InProject, $Script:reportData.DocumentLinks.InProject, (Format-StorageNumber $Script:reportData.Size.InProjectWise)))
    $viablePathsExportPath = "{0}\{1}\{2}_{3}_ViablePaths.json" -f @($Script:localPath, $Script:pwProjectPath, $Script:projectName, $Script:exportDateTime)


}
