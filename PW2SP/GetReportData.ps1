[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [Switch] $only1,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $onlyActive,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
    [Switch] $verifyOnly,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
    [Switch] $testRun,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
    [Switch] $processActive
)


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
    $title = "{0}-AI" -f @($title)
} `
else
{
    $title = "{0}-I" -f @($title)
}


. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1

# . .\TestReport.ps1

$mutex = [System.Threading.Mutex]::new($false, "SPProjectListtMutex")
$myProject = $null
$projectListFile = "E:\PW2SPReport\projectList.csv"

if($testRun.IsPresent)
{
    [Switch] $only1 = $true
}

do
{
    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile

        if($null -ne $myProject)
        {
            $currentPWDataSource = $myProject.pwDatasource
            Write-Host ("Getting next project in {0}..." -f @($myProject.pwDatasource))
            # Grab the next project that is not complete which is in the same datasource as the last project
            $myProject = $null
            $myProject = $projList.Where({ [String]::IsNullOrEmpty($_.reportPhase) -and ($_.pwDatasource -eq $currentPWDataSource) }) | Select-Object -First 1
            if($null -eq $myProject)
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
            } `
            else
            {
                # Nothing keep going.
            }
        } `
        else
        {
            # Nothing...we'll get the project below
        }

        if($null -eq $myProject)
        {
            # Just grab the next project that is not complete.
            $myProject = $projList.Where({ [String]::IsNullOrEmpty($_.reportPhase) }) | Select-Object -First 1
        } `
        else
        {
            # Nothing, already selected a project
        }

        if($null -ne $myProject)
        {
            Write-Host ("myProject Status:")
            Write-Host ("`t{0}" -f @($myProject.pwDatasource))
            Write-Host ("`t{0}" -f @($myProject.pwProjectPath))
            Write-Host ("`t{0}" -f @($myProject.projectName))
            Write-Host ("`tReport Phase: {0}" -f @($myProject.reportPhase))
            Write-Host ("`tUpload status: {0}" -f @($myProject.uploadStatus))
            Write-Host ("`tVerified: {0}" -f @($myProject.verified))
            Write-Host ("`tTest Run: {0}, Only1: {1}, ActiveOnly: {2}, Verifier: {3}, Process Active: {4}" -f @($testRunStr, $only1Str, $onlyActiveStr, $verifyOnlyStr, $processActive))


            $myProject.reportPhase = "running"
            $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
        } `
        else
        {
            # Nothing more to process.
        }
    }
    finally   # No matter what happens, make sure to release the mutex...
    {
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }

    if($null -ne $myProject)
    {
        $Error.Clear()
        $Script:HaveError = $false
        $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connData.json"
        $Script:pwDatasource = $myProject.pwDatasource
        $Script:pwPassword = "tX2NPfAK92DhM2"
        $Script:pwProjectPath = $myProject.pwProjectPath
        $Script:projectName = $myProject.projectName
        $Script:localPath = "E:\PW2SPReport"
        [Switch] $Script:dbgOut = $true

        Write-Host ("Launching {0}:{1}\{2}..." -f @($myProject.pwDatasource, $myProject.pwProjectPath, $myProject.projectName))
        if(-not $testRun.IsPresent)
        {
            $null = main

            try
            {
                $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
                $projList = Import-csv -Delimiter "`t" -Path $projectListFile

                if($null -ne $myProject)
                {
                    $myProject2 = $projList.Where({ $_.projectName -eq $myProject.projectName }) | Select-Object -First 1
                    if($null -ne $myProject2)
                    {
                        $myProject2.reportPhase = "complete"
                        $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
                    } `
                    else
                    {
                        Write-Host ("Unable to update project report phase for {0}." -f @($myProject.projectName))
                    }
                } `
                else
                {
                    Write-Host ("Missing myProject in report phase update.")
                }
            }
            finally   # No matter what happens, make sure to release the mutex...
            {
                $null = $mutex.ReleaseMutex()  # All done, let others play...
            }
        }
    }
} while((-not $only1.IsPresent) -and ($null -ne $myProject))
$null = $mutex.Dispose()
