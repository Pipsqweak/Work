[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $cifsServerName,

    [Parameter(Mandatory=$true,Position=1)]
    [String]
    $pathToCheck,

    [Parameter(Mandatory=$true,Position=2)]
    [System.String[]]
    $pathsToAvoid,

    [Parameter(Mandatory=$true,Position=3)]
    [System.Int32]
    $maxDepth,

    [Parameter(Mandatory=$true,Position=4)]
    [Boolean]
    $directoriesOnly,

    [Parameter(Mandatory=$true,Position=5)]
    [Boolean]
    $doDebug,

    [Parameter(Mandatory=$true,Position=6)]
    [String]
    $logPath,

    [Parameter(Mandatory=$true,Position=7)]
    [String]
    $databaseServer,

    [Parameter(Mandatory=$true,Position=8)]
    [String]
    $databaseName
)

Write-Host ("cifsServerName: {0}" -f @($cifsServerName))
Write-Host ("pathToCheck: {0}" -f @($pathToCheck))
Write-Host ("pathsToAvoid: {0}" -f @([String]::Join(",", $pathsToAvoid)))
Write-Host ("maxDepth: {0}" -f @($maxDepth))
Write-Host ("directoriesOnly: {0}" -f @($directoriesOnly))
Write-Host ("doDebug: {0}" -f @($doDebug))
Write-Host ("logPath: {0}" -f @($logPath))
Write-Host ("databaseServer: {0}" -f @($databaseServer))
Write-Host ("databaseName: {0}" -f @($databaseName))

Sleep 10
