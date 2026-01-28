$srcFolder = "E:\BOIFS1"
$dstFolder = "\\BOIFS1\Shares`$\Projects"
$maxRobocopyThreads = 8
$folders = $null
try
{
    $folders = @(Get-ChildItem -Path $srcFolder -Directory -ErrorAction Stop)
}
catch
{
    Write-Host -ForegroundColor Red ("Failed to retrieve folders from {0}." -f @($srcFolder))
}

if($null -ne $folders)
{
    $logFiles = [System.Collections.Generic.List[String]]::new()
    $listOnly = $false
    $a = 0
    $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    while($a -lt $folders.Length)
    {
        $copySrc = "{0}\FromPW" -f @($folders[$a].FullName)
        $copyDst = "{0}\{1}\FromPW" -f @($dstFolder, $folders[$a].Name)

        # Name of log file for the next ROBOCOPY process
        $logFile = "{0}\{1}-{2}.log" -f @($srcFolder, $ts, $folders[$a].Name)

        # Array of command-line parameters for ROBOCOPY
        $cmdArgs = @(
            ("`"{0}`"" -f @($copySrc)),        # Source Directory (drive:\path or \\server\share\path).
            ("`"{0}`"" -f @($copyDst)),        # Destination Dir  (drive:\path or \\server\share\path).
            "/MIR",                                   # Mirror source to destination
            "/ZB",                                    # use restartable mode; if access denied use Backup mode.
            "/COPY:DAT",                              # COPY ALL file info (equivalent to /COPY:DATSOU).
            "/R:1",                                   # Number of Retries on failed copies: default 1 million.
            "/W:1",                                   # Wait time between retries: default is 30 seconds.
            "/NP",                                    # No Progress - don't display percentage copied.
            ("/MT:{0}" -f @($maxRobocopyThreads)),    # Do multi-threaded copies with n threads (default 8).
            ("/LOG:{0}" -f @($logFile))               # output status to LOG file (overwrite existing log).
        )

        if($listOnly)
        {
            $cmdArgs += "/L"                          # List only - don't copy, timestamp or delete any files.
        }

        # Keep track of all log files so they can be merged.
        $logFiles.Add($logFile)

        # Spawn a new ROBOCOPY process to copy this $sourceLocation
        Start-Process -WindowStyle Normal robocopy $cmdArgs | Out-Null


        Write-Host ("Source: {0}`tDestination: {1}" -f @($copySrc, $copyDst))
        $a++
    }
} `
else
{
    # Nothing, already displayed an error.
}
