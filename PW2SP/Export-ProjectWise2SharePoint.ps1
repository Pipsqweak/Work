
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String] $projName,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $NoExport,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
    [Switch] $NoRestart,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
    [Switch] $NoDbgOut
)

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1


<#
    [Switch] $Script:dbgOut = $true
    [Switch] $Script:DoExport = $true
    [Switch] $Script:restart = $true
    $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"
    $Script:pwPassword = "tX2NPfAK92DhM2"
    $Script:localPath = "E:\PW2SPProd"

# 134945
    $Script:projectName = "134945"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Active Projects"

# 153690
    $Script:projectName = "180015"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Archive Projects"


# 180015
    $Script:projectName = "180015"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Active Projects"

# 0239208_0000
    $Script:projectName = "0239208_0000"
    $Script:pwDatasource = "pw_prod_pw02"
    $Script:pwProjectPath = "Active Projects"

# 0241892_0000
    $Script:projectName = "0239208_0000"
    $Script:pwDatasource = "pw_prod_pw02"
    $Script:pwProjectPath = "Active Projects"


# 121847
    $Script:projectName = "121847"
    $Script:pwDatasource = "pw_prod_dmsclosed"
    $Script:pwProjectPath = "Archived Projects"

# 119289
    $Script:projectName = "119289"
    $Script:pwDatasource = "pw_prod_dmsclosed"
    $Script:pwProjectPath = "Archived Projects"


# 139279
    $Script:projectName = "139279"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Archive Projects"

# 151646
    $Script:projectName = "151646"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Archive Projects"

# 157562
    $Script:projectName = "157562"
    $Script:pwDatasource = "pw_prod_pw01"
    $Script:pwProjectPath = "Archive Projects"

# zz0123456_0000
    $Script:projectName = "zz0123456_0000"
    $Script:pwDatasource = "pw_prod_pw02"
    $Script:pwProjectPath = "Active Projects"

    $Script:pwDatasource = "pw_prod_pw01"
#    $Script:pwDatasource = "pw_prod_pw02"

    $Script:pwPassword = "tX2NPfAK92DhM2"

#    $Script:pwProjectPath = "Archive Projects"
    $Script:pwProjectPath = "Active Projects"

#    $Script:projectName = "139279"
    $Script:projectName = "zz0123456_0000"
#    $Script:projectName = "161546"
    $Script:projectName = "176707"
#    $Script:projectName = "0244709_0000"



#>


$mutex = [System.Threading.Mutex]::new($false, "SPProjectListtMutex")
$myProject = $null
$projectListFile = "E:\PW2SPReport\projectList.csv"

try
{
    $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
    $projList = Import-csv -Delimiter "`t" -Path $projectListFile

    #$myProject = $projList.Where({ (((-not $onlyActive.IsPresent) -or ($_.pwProjectPath -match "Active")) -and (($_.pwProjectPath -notmatch "Active") -or $uploadActiveProjects)) -and ($_.uploadStatus -eq "readyToUpload") }) | Sort-Object priority | Select-Object -First 1
    $myProject = @($projList.Where({ $_.projectName -eq $projName }) | Select-Object -First 1)
    if($myProject.Length -eq 1)
    {
        $myProject = $myProject[0]
        $myProject.uploadStatus = "started"
        $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
    } `
    else
    {
        Write-Host -ForegroundColor Yellow ("Project '{0}' not found in project list." -f @($projName))
        $myProject = $null
    }
}
finally   # No matter what happens, make sure to release the mutex...
{
    $null = $mutex.ReleaseMutex()  # All done, let others play...
}


if($null -ne $myProject)
{
    $Error.Clear()
    $uploadTimer = [System.Diagnostics.Stopwatch]::new()
    $Script:HaveError = $false
    $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"
    $Script:pwDatasource = $myProject.pwDatasource
    $Script:pwPassword = "tX2NPfAK92DhM2"
    $Script:pwProjectPath = $myProject.pwProjectPath
    $Script:projectName = $myProject.projectName
    $Script:localPath = "E:\PW2SPProd"

    [Switch] $Script:dbgOut = -not $Script:NoDbgOut.IsPresent
    [Switch] $Script:restart = -not $Script:NoRestart.IsPresent
    [Switch] $Script:DoExport = -not $Script:NoExport.IsPresent
    $Script:TraceLevel = 1

    Write-Host ("Launching {0}:{1}\{2}..." -f @($myProject.pwDatasource, $myProject.pwProjectPath, $myProject.projectName))
    $uploadTimer.Reset()
    $uploadTimer.Start()
    $myProject.verified = main
    $myProject.checked = $myProject.verified
    $uploadTimer.Stop()
    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile

        if($null -ne $myProject)
        {
            $myProject2 = $projList.Where({ ($_.projectName -eq $myProject.projectName) }) | Select-Object -First 1
            if($null -ne $myProject2)
            {
                $myProject2.uploadStatus = "complete"
                $myProject2.uploadTime = $uploadTimer.Elapsed.ToString("dd\.hh\:mm\:ss")
                $myProject2.verified = $myProject2.checked = $myProject.verified
                $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
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
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }
} `
else
{
    # Nothing, no project to process.
}

$null = $mutex.Dispose()
