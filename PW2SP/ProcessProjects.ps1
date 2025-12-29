[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [String] $identifier = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $isProposal,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $only1,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
    [Switch] $onlyActive,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
    [Switch] $verifyOnly,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
    [Switch] $testRun,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
    [Switch] $processActive,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=7)]
    [Switch] $discover
)

<#
    $identifier =
    [Switch] $isProposal = $true


    [Switch] $only1 = $false
    [Switch] $onlyActive = $true
    [Switch] $verifyOnly = $false
    [Switch] $testRun = $false
    [Switch] $processActive = $false
    [Switch] $discover = $true

#>

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1

# . .\TestReport.ps1

$mutex = [System.Threading.Mutex]::new($false, "KLB_ListMutex")
$myProject = $null
$projectListFile = "E:\PW2SPReport\projectList.csv"
$uploadTimer = [System.Diagnostics.Stopwatch]::new()

$title = "*"
$only1Str = "no"
if($only1.IsPresent)
{
    $only1Str = "yes"
    $title = "1"
}

$onlyActiveStr = "no"
if($onlyActive.IsPresent)
{
    $onlyActiveStr = "yes"
    $title = "{0}-OA" -f @($title)

    # Force $processActive...
    [Switch] $processActive = $true
} `
else
{
    $title = "{0}-!OA" -f @($title)
}

$verifyOnlyStr = "no"
if($verifyOnly.IsPresent)
{
    $verifyOnlyStr = "yes"
    $title = "{0}-V" -f @($title)
}

$discoverStr = "no"
if($discover.IsPresent)
{
    $discoverStr = "yes"
    $title = "{0}-D" -f @($title)
}

$testRunStr = "no"
if($testRun.IsPresent)
{
    [Switch] $only1 = $true
    $testRunStr = "yes"
    $title = "{0}-T" -f @($title)
}

$processActiveStr = "no"
if($processActive.IsPresent)
{
    $processActiveStr = "yes"
    if($onlyActive.IsPresent)
    {
        $title = "{0}-A" -f @($title)
    } `
    else
    {
        $title = "{0}-AI" -f @($title)
    }
} `
else
{
    $title = "{0}-I" -f @($title)
}

do
{
    # If we have an existing project and are connected to projectwise and
    if($null -ne $myProject)
    {
        $currentPWDataSource = $myProject.pwDatasource
        $myProject = $null
    } `
    else
    {
        # Nothing keep going.
    }

    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile

        # Old, complicated way I was trying to decide which project to process...
        # $myProject = $projList.Where({ ($_.InBrookesList -eq "1") -and  ((((-not $onlyActive.IsPresent) -or ($_.pwProjectPath -match "Active")) -and (($_.pwProjectPath -notmatch "Active") -or $uploadActiveProjects)) -and (($_.uploadStatus -eq "readyToUpload") -or ($_.uploadStatus -eq "redoUpload")))}) | Sort-Object @{E={[Int64] $_.priority}} | Select-Object -First 1

        if(-not [String]::IsNullOrEmpty($identifier))
        {
            $myProject = $projList.Where({ $_.projectName -eq $identifier }) | Select-Object -First 1
        } `
        else
        {
            # First, eliminate projects that are not on Brooke's list, and sort them by priority
            $possibleProjects = $projList.Where({ $_.InBrookesList -eq "1" }) | Sort-Object @{E={[Int64] $_.priority}}

            if(-not $discover.IsPresent)
            {
                # Not discovering, so eliminate projects which have not yet be fully discovered.
                $possibleProjects = @($possibleProjects.Where({ $_.reportPhase -eq "complete" }))

                if($onlyActive.IsPresent)
                {
                    # This instance of the script should ONLY process active projects...
                    $possibleProjects = @($possibleProjects.Where({ $_.pwProjectPath -match "Active" }))
                }

                if($processActive.IsPresent)
                {
                    # Nothing, leave the active project in the possible list
                } `
                else
                {
                    $possibleProjects = @($possibleProjects.Where({ ($_.pwProjectPath -notmatch "Active") }))
                }

                if($verifyOnly.IsPresent)
                {
                    # This instance of the script should ONLY process projects which have already completed uploading, but have not been verified, and have not failed verification (.verifyCounter -lt 3)
                    $possibleProjects = @($possibleProjects.Where({ ($_.verified -ne "true") -and ($_.uploadStatus -eq "complete") -and (([int32]$_.verifyCounter) -lt 3) }))
                } `
                else
                {
                    # This instance of the script can process any project that is readyToUpload or needs to be re uploaded.
                    $possibleProjects = @($possibleProjects.Where({ $_.uploadStatus -in @("readyToUpload","redoUpload") }))
                }
            } `
            else
            {
                # Not discovering, so eliminate projects which have not yet be fully discovered.
                $possibleProjects = @($possibleProjects.Where({ [String]::IsNullOrEmpty($_.reportPhase) }))
            }

            if($possibleProjects.Length -gt 0)
            {
                $myProject = $possibleProjects[0]

                # If I'm connected to project wise....
                if(-not [pwwrapper]::aaApi_IsConnectionLost())
                {
                    if($myProject.pwDatasource -ne $currentPWDataSource)
                    {
                        # Switching to a different datasource
                        try
                        {
                            Write-Host "Disconnecting from ProjectWise..."
                            $null = Undo-PWLogin
                        }
                        catch
                        {
                            $Error.Clear()
                        }
                    }
                }

                Write-Host ("myProject Status:")
                Write-Host ("`t{0}" -f @($myProject.pwDatasource))
                Write-Host ("`t{0}" -f @($myProject.pwProjectPath))
                Write-Host ("`t{0}" -f @($myProject.projectName))
                Write-Host ("`tReport Phase: {0}" -f @($myProject.reportPhase))
                Write-Host ("`tUpload status: {0}" -f @($myProject.uploadStatus))
                Write-Host ("`tVerified: {0}" -f @($myProject.verified))
                Write-Host ("`tTest Run: {0}, Only1: {1}, ActiveOnly: {2}, Verifier: {3}, Process Active: {4}" -f @($testRunStr, $only1Str, $onlyActiveStr, $verifyOnlyStr, $processActiveStr))

                if($discover.IsPresent)
                {
                    $myProject.reportPhase = "running"
                } `
                else
                {
                    $myProject.uploadStatus = "started"
                }
            } `
            else
            {
                Write-Host ("No project left to process with the current flags.")
            }
        }
    }
    finally   # No matter what happens, make sure to release the mutex...
    {
        if(-not $testRun.IsPresent)
        {
            $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
        }
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }

    if($null -ne $myProject)
    {
        $host.UI.RawUI.WindowTitle = ("{0}-{1}-{2}" -f @($PID, $title, $myProject.projectName))
        $Error.Clear()
        $Script:HaveError = $false
        $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"
        $Script:pwDatasource = $myProject.pwDatasource
        $Script:pwPassword = "tX2NPfAK92DhM2"
        $Script:pwProjectPath = $myProject.pwProjectPath
        $Script:projectName = $myProject.projectName
        $Script:localPath = "E:\PW2SPProd"
        $Script:TraceLevel = 1

        [Switch] $Script:dbgOut = $true

        if(-not $discover.IsPresent)
        {
            # Always restarting for DoUploads.  Just means don't read anything from ProjectWise unless we need to.
            [Switch] $Script:restart = $true

            # Always exporting for DoUploads use GetReportData.ps1 otherwise...
            [Switch] $Script:DoExport = $true
            $previousUploadTime = [TimeSpan]::new(0)
            if(-not [String]::IsNullOrEmpty($myProject.uploadTime))
            {
                try
                {
                    $previousUploadTime = [TimeSpan]::Parse($myProject.uploadTime)
                }
                catch
                {
                    $Error.Clear()
                }
            }
        }

        Write-Host ("Launching {0}:{1}\{2}..." -f @($myProject.pwDatasource, $myProject.pwProjectPath, $myProject.projectName))

        if(-not $testRun.IsPresent)
        {

            $uploadTimer.Reset()
            $uploadTimer.Start()
            $verified = main
            if(-not $discover.IsPresent)
            {
                $myProject.Verified = $verified
                $myProject.checked = $myProject.verified
            }

            try
            {
                $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
                $projList = Import-csv -Delimiter "`t" -Path $projectListFile

                if($null -ne $myProject)
                {
                    $myProject2 = $projList.Where({ ($_.projectName -eq $myProject.projectName) }) | Select-Object -First 1
                    if($null -ne $myProject2)
                    {
                        if($verifyOnly.IsPresent)
                        {
                            $myProject2.verifyCounter = [int32] $myProject2.verifyCounter + 1
                        }
                        if(-not $discover.IsPresent)
                        {
                            $myProject2.uploadStatus = "complete"
                            $myProject2.uploadTime = ($previousUploadTime + $uploadTimer.Elapsed).ToString("dd\.hh\:mm\:ss")
                            $myProject2.verified = $myProject2.checked = $myProject.verified
                        } `
                        else
                        {
                            $myProject2.reportPhase = "complete"
                        }
                    } `
                    else
                    {
                        Write-Host ("Unable to update project stats for {0}." -f @($myProject.projectName))
                    }
                } `
                else
                {
                    Write-Host ("Missing myProject in update phase.")
                }
            }
            finally   # No matter what happens, make sure to release the mutex...
            {
                $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
                $null = $mutex.ReleaseMutex()  # All done, let others play...
            }
        }
    }
} while(($true) -and (-not $testRun.IsPresent) -and (-not $only1.IsPresent) -and ($null -ne $myProject))


$null = $mutex.Dispose()
$host.UI.RawUI.WindowTitle = "Idle"
