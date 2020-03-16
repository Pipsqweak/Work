# Main function for Permissions Scanner.
#   NOT going to retest all the parameter here, Scanner.ps1 already checked them.  If Main gets called by something
#      other than Scanner, the caller better do their own checks.

function Main
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0)]
        [String]
        $logPath,

        [Parameter(Mandatory=$false,Position=1)]
        [Object[]]
        $nasList,

        [Parameter(Mandatory=$false,Position=2)]
        [String]
        $pathToGetACLs,

        [Parameter(Mandatory=$false,Position=3)]
        [String]
        $remotePSConfigName,

        [Parameter(Mandatory=$false,Position=4)]
        [String]
        $databaseServer,

        [Parameter(Mandatory=$false,Position=5)]
        [String]
        $databaseName,

        [Parameter(Mandatory=$false,Position=6)]
        [String[]]
        $partialPathsToAvoid,

        [Parameter(Mandatory=$false,Position=7)]
        [Int32]
        $maxSubProcesses,

        [Parameter(Mandatory=$false,Position=8)]
        [Int32]
        $maxScanDepth,

        [Parameter(Mandatory=$false,Position=9)]
        [Int32]
        $maxSharesToCheck,

        [Parameter(Mandatory=$false,Position=10)]
        [Boolean]
        $doDebug,

        [Parameter(Mandatory=$false,Position=11)]
        [Boolean]
        $directoriesOnly,

        [Parameter(Mandatory=$false,Position=12)]
        [LogLevel]
        $logLevel,

        [Parameter(Mandatory=$false,Position=13)]
        [Boolean]
        $testRun,

        [Parameter(Mandatory=$false,Position=14)]
        [Boolean]
        $launchRemote
    )
    # Collection of all the CIFS servers/shares discovered on all the clusters/filers
    [NetAppCIFSServerCollection] $Global:naCIFSServers = [NetAppCIFSServerCollection]::new()

    # Set the maximum number of subprocesses the JobTracker should let launch
    [JobTracker]::maxSubProcesses = $maxSubProcesses

    if (-not $testRun)
    {
        Connect-NetAppFromList $nasList
    }
    else # NOT (-not $testRun)
    {
        $Global:cdot = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]'

 #       $c = Connect-NetApp -name "CDC-CDOTCLST01" -mode "CLUSTER"
 #       $Global:cdot.Add($c.Name, $c)

        $Global:smNodes = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]'
        foreach($nas in @("ORLPRDNAS1")) #, "ARBPRDNAS1", "EDPPRDNAS1"))
        {
           $s = Connect-NetApp -name $nas -mode "7-MODE"
           $Global:smNodes.Add($s.Name, $s)
        }
    }

    # Discover all the shares on the clusters
    $Global:naCIFSServers.Add($Global:cdot, $true)

    # Discover all the shares on the 7-mode filers
    $Global:naCIFSServers.Add($Global:smNodes, $true)

    # Update the database with CIFS servers...
    $Global:naCIFSServers.UpdateDB($databaseServer, $databaseName)

    # Get an array of all the shares to check
    $sharesToCheck = $Global:naCIFSServers.GetSharesToCheck($maxSharesToCheck)

    # Build all the remote jobs and launch them...
    for($a = 0; $a -lt $sharesToCheck.Length; $a++)
    {
        $shareToCheck = $sharesToCheck[$a]

        # Get the NAS definition for the share's filer...
        $filer = @($nasList | Where-Object { $_.name -eq $shareToCheck.Filer })

        if($filer.Length -eq 1)
        {
            # Get the management server associated with the filer.
            $mgmtServer = $filer[0].mgmtServer

            if(-not [String]::IsNullOrEmpty($mgmtServer))
            {
                # Create the path Get-ACLs should check
                $sharePath = "\\{0}\{1}" -f $shareToCheck.CIFSShare.CIFSServer, $shareToCheck.CIFSShare.Name

                $getACLsRemoteJob = [JobTracker]::new($remotePSConfigName, $mgmtServer, $shareToCheck.CIFSShare.CIFSServer, $pathToGetACLs, $sharePath, $shareToCheck.CIFSShare.pathsToAvoid, $logPath, $logLevel, $maxScanDepth, $directoriesOnly, $doDebug, $databaseServer, $databaseName, $partialPathsToAvoid)

                if($getACLsRemoteJob.okToLaunch)
                {
                    if($launchRemote)
                    {
                        [Log]::Info("Launching remote job for {0} on {1}" -f @($sharePath, $mgmtServer))
                        $getACLsRemoteJob.Launch()
                    }
                    else
                    {
                        [Log]::Info("Not launching remote job for {0} on {1}" -f @($sharePath, $mgmtServer))
                    }
                }
                else
                {
                    # Nothing JobTracker would have logged an error
                }
            }
            else
            {
                [Log]::Warning("No management server defined for CIFS server: {0}." -f @($shareToCheck.CIFSShare.CIFServer))
            }
        }
        else
        {
            [Log]::Warning("No management server defined for filer: {0}." -f @($shareToCheck.Filer))
        }
    }
}
