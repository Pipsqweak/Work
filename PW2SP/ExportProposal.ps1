[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [String] $propName = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $only1,

    [Parameter(Mandatory=$false, ParameterSetName='Discover', ValueFromPipeline=$false, Position=2)]
    [Switch] $discover,

    [Parameter(Mandatory=$false, ParameterSetName='Export', ValueFromPipeline=$false, Position=2)]
    [Switch] $export,

    [Parameter(Mandatory=$false, ParameterSetName='MakeFlatSets', ValueFromPipeline=$false, Position=2)]
    [Switch] $makeFlatSets,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
    [Switch] $testRun
)

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1

[Switch] $isProposal = $true
$proposalListFile = "E:\PW2SPProd\proposalList.csv"
$Script:localPath = "E:\PWProposals"
$Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProposals.json"
$Script:pwDatasource = "pw_prod_pw01"
$Script:pwPassword = "tX2NPfAK92DhM2"
$Script:TraceLevel = 1
[Switch] $Script:dbgOut = $true

$mutex = [System.Threading.Mutex]::new($false, "SPProposalListtMutex")

do
{
    # Safely get the next proposal to export.
    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $updateList = $false
        $proposalList = Import-csv -Delimiter "`t" -Path $proposalListFile

        if(-not [String]::IsNullOrEmpty($propName))
        {
            $myProposal = $proposalList.Where({ ($_.Name -eq $propName) -and ([String]::IsNullOrEmpty($_.Status)) }) | Select-Object -First 1
            if($null -ne $myProposal)
            {
                if(-not $myProposal.Discovered)
                {
                    $myProposal.Status = "discovering"
                    $myProposal.Discovered = "processing"
                    $updateList = $true
                } `
                elseif (-not $myProposal.Exported)
                {
                    $myProposal.Status = "exporting"
                    $myProposal.Exported = "processing"
                    $updateList = $true
                } `
                elseif (($myProposal.Uploaded) -and (-not $myProposal.FlatSetProcessed))
                {
                    $myProposal.Status = "processingFS"
                    $myProposal.FlatSetProcessed = "processing"
                    $updateList = $true
                } `
                else
                {
                    LogWarning ("Nothing to do for proposal {0}" -f @($myProposal.Name))
                }
            } `
            else
            {
                LogError ("Proposal {0} not found." -f @($propName))
            }
        } `
        else
        {
            if($discover.IsPresent)
            {
                $myProposal = $proposalList.Where({ $_.Discovered -eq "FALSE" }) | Select-Object -First 1
                if($null -ne $myProposal)
                {
                    $myProposal.Status = "discovering"
                    $myProposal.Discovered = "processing"
                    $updateList = $true
                }
            } `
            elseif($export.IsPresent)
            {
                $myProposal = $proposalList.Where({ ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "FALSE") }) | Select-Object -First 1
                if($null -ne $myProposal)
                {
                    $myProposal.Status = "exporting"
                    $myProposal.Exported = "processing"
                    $updateList = $true
                }
            } `
            elseif($makeFlatSets.IsPresent)
            {
                $myProposal = $proposalList.Where({ ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "TRUE") -and ($_.Uploaded -eq "TRUE") -and ($_.FlatSetProcessed -eq "FALSE")}) | Select-Object -First 1
                if($null -ne $myProposal)
                {
                    $myProposal.Status = "processingFS"
                    $myProposal.FlatSetProcessed = "processing"
                    $updateList = $true
                }
            }
        }

        if($null -ne $myProposal)
        {
            if($updateList -and (-not $testRun.IsPresent))
            {
                $proposalList | Export-CSV -Delimiter "`t" -Path $proposalListFile -Force
            }
        } `
        else
        {
            Write-Host ("No proposal available to process.")
        }
    }
    finally   # No matter what happens, make sure to release the mutex...
    {
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }


    if($null -ne $myProposal)
    {
        $Script:HaveError = $false
        $Script:projectName = $myProposal.Name
        $Script:proposalName = $myProposal.Name
        $Script:pwProjectPath = $myProposal.pwProjectPath
        $Script:pwDataSource = "pw_prod_pw01"
        [Switch] $Script:dbgOut = $true
        [Switch] $Script:DoExport = $false
        [Switch] $Script:restart = $false

        InitProposals
        $host.UI.RawUI.WindowTitle = ("{0}-{1}" -f @($PID, $myProposal.Name))

        if(-not $Script:HaveError)
        {
            if(ConnectToPW)
            {
                try
                {
                    if(-not $testRun.IsPresent)
                    {
                        $pwFolder = Get-PWFoldersByGUIDs -FolderGUIDs $myProposal.FolderGUID -ErrorAction Stop
                    }
                }
                catch
                {
                    LogError ("Failed to get ProjectWise folder [{0}] for GUID: {1}" -f @($myProposal.Name, $myProposal.FolderGUID))
                }

                if($null -ne $pwFolder)
                {
                    if(-not $Script:HaveError)
                    {
                        LogInfo ("Getting {0} properties..." -f @($pwFolder.Name))
                        try
                        {
                            if(-not $testRun.IsPresent)
                            {
                                $null = $pwFolder.GetFolderProperties()
                            }
                        }
                        catch
                        {
                            LogError ("Failed to get folder properties for {0}." -f @($pwFolder.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }

                    if(-not $Script:HaveError)
                    {
                        if($discover.IsPresent)
                        {
                            if(-not [String]::IsNullOrEmpty($pwFolder.FullPath))
                            {
                                $Script:ProjectName = $pwFolder.Name
                                $Script:pwProjectPath = @($pwFolder.FullPath -split "\\")[0]

                                if(-not [String]::IsNullOrEmpty($Script:pwProjectPath))
                                {
                                    # Get relevant information from ProjectWise
                                    Init
                                    $pwData = GetProjectWiseData
                                    if(-not $Script:HaveError)
                                    {
                                        if($null -ne $pwData)
                                        {
                                            $myProposal.Folders = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseFolder" }).Count
                                            $myProposal.Documents = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }).Count
                                            $myProposal.FlatSets = @($pwData.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseDocument") -and ($_.IsSet) }).Count
                                            $myProposal.Size = (@($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }) | Measure-Object -Sum -Property FileSize).Sum
                                            ExportPWDataToJSON
                                            $myProposal.Status = ""
                                            $myProposal.Discovered = "TRUE"
                                        } `
                                        else
                                        {
                                            LogError ("Failed to get ProjectWise data for project {0}\{1} in {2}." -f @($Script:pwProjectPath, $Script:projectName, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, already logged an error.
                                    }
                                } `
                                else
                                {
                                    LogError ("Missing `$Script:pwProjectPath for {0}." -f @($myProposal.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Missing full path for {0}." -f @($myProposal.Name))
                            }
                        } `
                        else
                        {
                            LogInfo ("Getting {0} subfolders..." -f @($pwFolder.Name))
                            try
                            {
                                if(-not $testRun.IsPresent)
                                {
                                    $null = $pwFolder.GetSubFolders()
                                }
                            }
                            catch
                            {
                                LogError ("Failed to get subfolders for {0}." -f @($pwFolder.Name))
                            }

                            if(-not $Script:HaveError)
                            {
                                LogInfo ("Getting {0} tree documents..." -f @($pwFolder.Name))
                                try
                                {
                                    if(-not $testRun.IsPresent)
                                    {
                                        $null = $pwFolder.GetTreeDocuments()
                                    }
                                }
                                catch
                                {
                                    LogError ("Failed to get tree documents for {0}." -f @($pwFolder.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }

                            if(-not $Script:HaveError)
                            {
                                LogInfo ("Building proposal folder structure...")
                                try
                                {
                                    if(-not $testRun.IsPresent)
                                    {
                                        $localFolders = [System.Collections.Generic.List[System.Object]]::new()
                                        @($pwFolder.Subfolders).ForEach({
                                            $nf = New-Item -ItemType Directory -Path $Script:localPath -Name $_.FullPath -Force -ErrorAction Stop
                                            $localFolders.Add($nf)
                                        })
                                    }
                                }
                                catch
                                {
                                    LogError ("Failed to create local folder structure for {0}." -f @($myProposal.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }

                            if(-not $Script:HaveError)
                            {
                                LogInfo ("Exporting proposal documents...")
                                try
                                {
                                    if(-not $testRun.IsPresent)
                                    {
                                        $exportedDocs = Export-PWDocuments -OutputFolder $Script:localPath -inputDocuments $pwFolder.TreeDocuments -exportversions -ErrorAction Stop
                                    }
                                }
                                catch
                                {
                                    LogError ("Failed to export proposal documents for {0}." -f @($myProposal.Name))
                                    $myProposal.Status = "failed"
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }

                            if(-not $Script:HaveError)
                            {
                                if($localFolders.Count -ne $pwFolder.SubFolders.Count)
                                {
                                    LogWarning ("Subfolder count mismatch.  ProjectWise: {0}, Exported: {1}." -f @($pwFolder.SubFolders.Count, $localFolders.Count))
                                }

                                if($exportedDocs.Length -ne $pwFolder.TreeDocuments.Count)
                                {
                                    LogWarning ("Document count mismatch.  ProjectWise: {0}, Exported: {1}." -f @($pwFolder.TreeDocuments.Count, $exportedDocs.Length))
                                }

                                if(($localFolders.Count -eq$pwFolder.SubFolders.Count) -and ($exportedDocs.Length -eq $pwFolder.TreeDocuments.Count))
                                {
                                    $myProposal.Status = "exported"
                                    LogInfo ("{0} successfully exported" -f @($myProposal.Name))
                                } `
                                else
                                {
                                    $myProposal.Status = "error"
                                    LogWarning ("{0} not successfully exported" -f @($myProposal.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    $myProposal.Status = "Error"
                }

                try
                {
                    $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
                    $proposalList2 = Import-csv -Delimiter "`t" -Path $proposalListFile

                    $myProposal2 = $proposalList2.Where({ $_.Name -eq $myProposal.Name }) | Select-Object -First 1

                    if($null -ne $myProposal2)
                    {
                        if((-not $testRun.IsPresent) -and (($myProposal2.Status -ne $myProposal.Status) -or ($myProposal2.Notes -ne $myProposal.Notes)))
                        {
                            $myProposal2.Status = $myProposal.Status
                            $myProposal2.Notes = $myProposal.Notes
                            $myProposal2.Folders = $myProposal.Folders
                            $myProposal2.Documents = $myProposal.Documents
                            $myProposal2.Size = $myProposal.Size
                            $myProposal2.FlatSets = $myProposal.FlatSets

                            try
                            {
                                $proposalList2 | Export-CSV -Delimiter "`t" -Path $proposalListFile -Force -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to save proposal list.")
                            }
                        }
                    } `
                    else
                    {
                        Write-Host ("Failed to reload proposal list from {0}." -f @($proposalListFile))
                    }
                }
                finally   # No matter what happens, make sure to release the mutex...
                {
                    $null = $mutex.ReleaseMutex()  # All done, let others play...
                }
            } `
            else
            {
                # Nothing, already loogged an error.
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }
    } `
    else
    {
        # Nothing, already displayed a message, or I reset $myProposal to $null to indicate nothing to do.
    }
}
while((-not $only1.IsPresent) -and (-not $Script:HaveError) -and ($null -ne $myProposal))
$host.UI.RawUI.WindowTitle = "Idle"
