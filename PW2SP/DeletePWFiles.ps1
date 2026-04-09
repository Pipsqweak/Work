[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [String] $projectName = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [String] $pwDatasource = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
    [Switch] $testRun
)

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1


if($null -ne $projectName)
{
    $title = "Deleting {0}" -f @($projectName)

    if($testRun.IsPresent)
    {
        $title = "{0}-T" -f @($title)
    }

    $host.UI.RawUI.WindowTitle = ("{0}-{1}" -f @($PID, $title))
    $Error.Clear()
    $Script:HaveError = $false
    $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"

    $Script:pwProjectPath = "GovtServices projects for deletion"

    #$Script:pwDatasource = "pw_prod_pw01"

    $Script:pwPassword = "tX2NPfAK92DhM2"
    $Script:localPath = "E:\PWDelete"
    $Script:TraceLevel = 1

    [Switch] $Script:dbgOut = $true

    Write-Host ("Deleting {0}\{1}\{2}..." -f @($Script:pwDatasource, $Script:pwProjectPath, $Script:projectName))

    if(-not $testRun.IsPresent)
    {
        main4Delete2
    }
}


$host.UI.RawUI.WindowTitle = "Idle"
