
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String] $connDataJSONFile,

    [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String] $pwDatasource
)


function t1
{
    Write-Host ("1: {0}" -f @($Script:connDataJSONFile))
    Write-Host ("2: {0}" -f @($Script:pwDatasource))
}


t1
