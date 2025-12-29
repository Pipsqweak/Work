function main
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $connDataJSONFile,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $pwDatasource,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $pwPassword,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNullOrEmpty()]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [ValidateNotNullOrEmpty()]
        [String] $localPath,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $DoExport,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=7)]
        [Switch] $restart,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=8)]
        [Switch] $dbgOut
    )
    @($PSBoundParameters.Keys).ForEach({
        Write-Host ("{0}: {1}" -f @($_, $PSBoundParameters[$_]))
    })
    Start-Sleep -Seconds 60
}
