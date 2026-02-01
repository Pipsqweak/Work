[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [String] $propName = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $only1,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
    [Switch] $discover,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
    [Switch] $export,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
    [Switch] $verify,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
    [Switch] $testRun
)

<#
    $propName = "0231326"
    [Switch] $export = $true

    [Switch] $verify = $true
#>

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1

[Switch] $isProposal = $true
$proposalListFile = "E:\PW2SPProd\proposalList.csv"
$Script:localPath = "E:\PWProposals"
$Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProposals.json"
#$Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProposalsKLB.json"
$Script:pwDatasource = "pw_prod_pw01"
$Script:pwPassword = "tX2NPfAK92DhM2"
$Script:TraceLevel = 1
[Switch] $Script:dbgOut = $true
$myProposal = $null

$mutex = [System.Threading.Mutex]::new($false, "SPProposalListtMutex")

Write-Host "Processing proposals..."
do
{
    if(-not [System.IO.File]::Exists("E:\PW2SPProd\STOPPROCESSING.TXT"))
    {
        # Safely get the next proposal to export.
        try
        {
            $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
            $updateList = $false
            $proposalList = Import-csv -Delimiter "`t" -Path $proposalListFile

            if(-not [String]::IsNullOrEmpty($propName))
            {
                Write-Host ("Selecting proposal by name: [{0}]" -f @($propName))
                $myProposal = $proposalList.Where({ ($_.Name -eq $propName) }) | Select-Object -First 1
                if($null -ne $myProposal)
                {
                    if($myProposal.Discovered -eq "false")
                    {
                        $myProposal.Status = "Discovering"
                        $myProposal.Discovered =  "Processing"
                        $updateList = $true

                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $false

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    } `
                    elseif($myProposal.Exported -eq "false")
                    {
                        $myProposal.Status = "Exporting"
                        $myProposal.Exported =  "Processing"
                        $updateList = $true

                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $true

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    } `
                    elseif(($myProposal.Uploaded -eq "true") -and ($myProposal.FlatSetProcessed -eq "false"))
                    {
                        $myProposal.Status = "ProcessingFS"
                        $myProposal.FlatSetProcessed =  "Processing"
                        $updateList = $true

                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $true

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    } `
                    elseif($myProposal.Verified -eq "false")
                    {
                        $myProposal.Status = "Verifying"
                        $myProposal.Verified =  "Processing"
                        $updateList = $true

                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $true

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    } `
                    else
                    {
                        Write-Host ("Nothing to do for proposal {0}" -f @($myProposal.Name))
                        $myProposal = $null
                    }
                } `
                else
                {
                    LogError ("Proposal {0} not found." -f @($propName))
                }
            } `
            else
            {
                Write-Host "No proposal name given"
                if($discover.IsPresent)
                {
                    Write-Host "Discovering..."
                    $myProposal = $proposalList.Where({ ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "FALSE") }) | Select-Object -First 1
                    if($null -ne $myProposal)
                    {
                        $myProposal.Status = "Discovering"
                        $myProposal.Discovered =  "Processing"
                        $updateList = $true
                    }
                } `
                elseif($export.IsPresent)
                {
                    Write-Host "Exporting..."
                    $myProposal = $proposalList.Where({ ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "FALSE") }) | Select-Object -First 1
                    if($null -ne $myProposal)
                    {
                        $myProposal.Status = "Exporting"
                        $myProposal.Exported =  "Processing"
                        $updateList = $true
                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $true

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    }
                } `
                elseif($verify.IsPresent)
                {
                    Write-Host "Verifying..."
                    $myProposal = $proposalList.Where({ (([int] $_.VerifyCount) -lt 3) -and ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "TRUE") -and ($_.Uploaded -eq "TRUE") -and ($_.FlatSetProcessed -eq "TRUE") -and ($_.Verified -eq "FALSE")}) | Select-Object -First 1
                    if($null -ne $myProposal)
                    {
                        $myProposal.Status = "Verifying"
                        $myProposal.Verified =  "Processing"
                        Write-Host ("VC: {0}/Type: {1}" -f @($myProposal.VerifyCount, $myProposal.VerifyCount.GetType().Name))
                        $myProposal.VerifyCount = [int] $myProposal.VerifyCount
                        $myProposal.VerifyCount++
                        Write-Host ("VC: {0}/Type: {1}" -f @($myProposal.VerifyCount, $myProposal.VerifyCount.GetType().Name))
                        $updateList = $true
                        # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                        [Switch] $Script:restart = $true

                        # $Script:DoExport also needs to be set to do any work...
                        [Switch] $Script:DoExport = $true
                    }
                } `
                else
                {
                    # Just find the next thing that needs to be processed.
                    Write-Host "Looking for next proposal to process"
                    # Does anything need to be discovered?
                    $myProposal = $proposalList.Where({ ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "FALSE") }) | Select-Object -First 1
                    if($null -ne $myProposal)
                    {
                        $myProposal.Status = "Discovering"
                        $myProposal.Discovered =  "Processing"
                        $updateList = $true
                    } `
                    else
                    {
                        Write-Host "Everything is discovered"
                        # Anything need to be verified?
                        $myProposal = $proposalList.Where({ (([int] $_.VerifyCount) -lt 3) -and  ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "TRUE") -and ($_.Uploaded -eq "TRUE") -and ($_.FlatSetProcessed -eq "TRUE") -and ($_.Verified -eq "FALSE")}) | Select-Object -First 1
                        if($null -ne $myProposal)
                        {
                            Write-Host "Verifying..."
                            $myProposal.Status = "Verifying"
                            $myProposal.Verified =  "Processing"
                            $updateList = $true

                            Write-Host ("VC: {0}/Type: {1}" -f @($myProposal.VerifyCount, $myProposal.VerifyCount.GetType().Name))
                            $myProposal.VerifyCount = [int] $myProposal.VerifyCount
                            $myProposal.VerifyCount++
                            Write-Host ("VC: {0}/Type: {1}" -f @($myProposal.VerifyCount, $myProposal.VerifyCount.GetType().Name))

                            # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                            [Switch] $Script:restart = $true

                            # $Script:DoExport also needs to be set to do any work...
                            [Switch] $Script:DoExport = $true
                        } `
                        else
                        {
                            Write-Host "No proposals to verify"
                            # Anything need to be exported?
                            $myProposal = $proposalList.Where({ ($_.Status -notin @("Complete","Errored")) -and ($_.Discovered -eq "TRUE") -and ($_.Exported -eq "FALSE") }) | Select-Object -First 1
                            if($null -ne $myProposal)
                            {
                                Write-Host "Exporting..."
                                $myProposal.Status = "Exporting"
                                $myProposal.Exported =  "Processing"
                                $updateList = $true
                                # $Script:restart needs to be set if the proposal has already been discovered.  Not having $restart set sparks the discovery process.
                                [Switch] $Script:restart = $true

                                # $Script:DoExport also needs to be set to do any work...
                                [Switch] $Script:DoExport = $true
                            } `
                            else
                            {
                                Write-Host "All done."
                            }
                        }
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
            # $myProposal
            @("FolderGUID","pwProjectPath","Name","Description","Status","Discovered","Exported","Uploaded","FlatSetProcessed","Verified","VerifyCount","Folders","Documents","Size","FlatSets","Notes").ForEach({
                Write-Host ("{0}: {1}" -f @($_, $myProposal.$_))
            })
            $Script:HaveError = $false
            $Script:projectName = $myProposal.Name
            $Script:proposalName = $myProposal.Name
            $Script:pwProjectPath = $myProposal.pwProjectPath
            $Script:pwDataSource = "pw_prod_pw01"
            [Switch] $Script:dbgOut = $true

            $host.UI.RawUI.WindowTitle = ("{0}-{1}" -f @($PID, $myProposal.Name))

            $projectData = main

            $updateList = $true
            if(-not $projectData.HaveError)
            {
                $myProposal.Folders = $projectData.Folders
                $myProposal.Documents = $projectData.Documents
                $myProposal.FlatSets = $projectData.FlatSets
                $myProposal.Size = $projectData.Size
                $myProposal.Discovered = $projectData.Discovered.ToString()
                $myProposal.Exported = $projectData.Exported.ToString()
                $myProposal.Uploaded = $projectData.Uploaded.ToString()
                $myProposal.FlatSetProcessed = $projectData.FlatSetProcessed.ToString()
                $myProposal.Verified = $projectData.Verified.ToString()
                if($projectData.Verified)
                {
                    $myProposal.Status = "Complete"
                } `
                elseif($projectData.Exported)
                {
                    $myProposal.Status = "Exported"
                } `
                elseif($projectData.Discovered)
                {
                    $myProposal.Status = "Discovered"
                }
                else
                {
                    $myProposal.Status = ""
                }
            } `
            else
            {
                $myProposal.Status = "Errored"
            }

            if($updateList)
            {
                try
                {
                    $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
                    $proposalList = Import-csv -Delimiter "`t" -Path $proposalListFile

                    $myProposal2 = $proposalList.Where({ ($_.Name -eq $myProposal.Name) }) | Select-Object -First 1
                    if($null -ne $myProposal2)
                    {
                        $myProposal2.Folders = $myProposal.Folders
                        $myProposal2.Documents = $myProposal.Documents
                        $myProposal2.FlatSets = $myProposal.FlatSets
                        $myProposal2.Size = $myProposal.Size
                        $myProposal2.Discovered = $myProposal.Discovered
                        $myProposal2.Exported = $myProposal.Exported
                        $myProposal2.Uploaded = $myProposal.Uploaded
                        $myProposal2.FlatSetProcessed = $myProposal.FlatSetProcessed
                        $myProposal2.Verified = $myProposal.Verified
                        $myProposal2.VerifyCount = $myProposal.VerifyCount
                        $myProposal2.Status = $myProposal.Status

                        $proposalList | Export-CSV -Delimiter "`t" -Path $proposalListFile -Force
                    } `
                    else
                    {
                        LogError ("Proposal {0} not found after main processing." -f @($myProposal.Name))
                    }
                }
                finally   # No matter what happens, make sure to release the mutex...
                {
                    $null = $mutex.ReleaseMutex()  # All done, let others play...
                }
            } `
            else
            {
                # Nothing
            }
        } `
        else
        {
            # Nothing.
        }
    }
}
while((-not [System.IO.File]::Exists("E:\PW2SPProd\STOPPROCESSING.TXT")) -and (-not $only1.IsPresent) -and (-not $Script:HaveError) -and ($null -ne $myProposal))
$host.UI.RawUI.WindowTitle = "Idle"

if([System.IO.File]::Exists("E:\PW2SPProd\STOPPROCESSING.TXT"))
{
    Write-Host -ForegroundColor Yellow "Stop processing requested."
}
