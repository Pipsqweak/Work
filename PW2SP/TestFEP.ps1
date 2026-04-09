[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
    [String] $projectName = [String]::Empty,

    [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
    [Switch] $testRun
)


Write-Host $projectName
Start-Sleep -Seconds 10
