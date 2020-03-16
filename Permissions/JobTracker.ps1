
class JobTracker
{
    static [Int32] $maxSubProcesses = 5
    [System.Int32] $maxDepth = 3
    [Boolean] $directoriesOnly = $true
    [Boolean] $doDebug = $true
    hidden [Boolean] $resultsSaved = $false
    hidden [Boolean] $launchingLocal = $false
    hidden [Boolean] $okToLaunch = $false

    [String] $mgmtServer = [String]::Empty
    [String] $cifsServerName = [String]::Empty
    [String] $databaseServer = [String]::Empty
    [String] $databaseName = [String]::Empty
    [String] $scriptPath = [String]::Empty
    hidden [System.Management.Automation.Job] $job = $null
    [String] $pathToCheck = [String]::Empty
    [System.String[]] $pathsToAvoid = @()
    [System.String[]] $partialPathsToAvoid = @()
    [String] $logPath = [String]::Empty
    hidden [String] $psRemoteConfName = [String]::Empty
    hidden [System.Object] $results = $null
    hidden [LogLevel] $logLevel

    JobTracker(
        [String] $psRemoteConfName,
        [String] $mgmtServer,
        [String] $cifsServerName,
        [String] $scriptPath,
        [String] $pathToCheck,
        [System.String[]] $pathsToAvoid,
        [String] $logPath,
        [LogLevel] $logLevel,
        [System.Int32] $maxDepth,
        [Boolean] $directoriesOnly,
        [Boolean] $doDebug,
        [String] $databaseServer,
        [String] $databaseName,
        [System.String[]] $partialPathsToAvoid)
    {
        $this.psRemoteConfName = $psRemoteConfName
        $this.mgmtServer = $mgmtServer
        $this.cifsServerName = $cifsServerName
        $this.databaseServer = $databaseServer
        $this.databaseName = $databaseName
        $this.scriptPath = $scriptPath
        $this.pathToCheck = $pathToCheck
        $this.pathsToAvoid = $pathsToAvoid
        $this.partialPathsToAvoid = $partialPathsToAvoid
        $this.logPath = $logPath
        $this.logLevel = $logLevel
        $this.maxDepth = $maxDepth
        $this.directoriesOnly = $directoriesOnly
        $this.doDebug = $doDebug
        $this.okToLaunch = $false

        # Validate $mgmtServer
        if(-not [String]::IsNullOrEmpty($mgmtServer))
        {
            $this.launchingLocal = ($env:COMPUTERNAME.ToUpper() -eq $mgmtServer.ToUpper())

            if(($this.launchingLocal) -or (Test-Connection -ComputerName $mgmtServer -Quiet))
            {
                # Validate $psRemoteConfName
                if(($this.launchingLocal) -or (-not [String]::IsNullOrEmpty($psRemoteConfName)))
                {
                    $remotePSConf = @()
                    if(-not $this.launchingLocal)
                    {
                        $remotePSConf = @(Invoke-Command -ComputerName $mgmtServer -ScriptBlock { Get-PSSessionConfiguration } -ErrorAction SilentlyContinue)
                    }
                    else
                    {
                        # Nothing, no need to check for a remote PS Session Configuration if we are launching locally
                    }

                    if(($this.launchingLocal) -or (@($remotePSConf | Where-Object { $_.Name -eq $psRemoteConfName}).Length -eq 1))
                    {
                        # Validate $scriptPath
                        if(-not [String]::IsNullOrEmpty($scriptPath))
                        {
                            if(Test-Path -Path $scriptPath)
                            {
                                # Validate $pathToCheck
                                if(-not [String]::IsNullOrEmpty($pathToCheck))
                                {
                                    if(Test-Path -Path $pathToCheck)
                                    {
                                        $this.okToLaunch = $true
                                    }
                                    else
                                    {
                                        [Log]::Warning("Test-Path {0} failed" -f @($pathToCheck))
                                    }
                                }
                                else
                                {
                                    [Log]::Warning("Missing path to check")
                                }
                            }
                            else
                            {
                                [Log]::Warning("Script to launch [{0}] does not exist." -f @($scriptPath))
                            }
                        }
                        else
                        {
                            [Log]::Warning("Missing path to launch script")
                        }
                    }
                    else
                    {
                        [Log]::Warning("Missing remote powershell session configuration [{0}] on management server [{1}]." -f @($psRemoteConfName, $mgmtServer))

                        # The following need to be ran to build the remote session on the management server.  However, right now, the credentials are not
                        #   passed into this function.
                        # Invoke-Command -ComputerName $mgmtServer -ScriptBlock { Register-PSSessionConfiguration -Name $psRemoteConfName -RunAsCredential $creds -Force }
                    }
                }
                else
                {
                    [Log]::Warning("Remote powershell session configuration name not provided.")
                }
            }
            else
            {
                [Log]::Warning("Test connection to {0} failed." -f @($mgmtServer))
            }
        }
        else
        {
            [Log]::Warning("Missing management server name in {0}." -f @($MyInvocation.MyCommand))
        }
    }

    [void] Launch()
    {
        <#
            NOTE:  Need to take into consideration different domains.  i.e. segafs.segainc.com
        #>
        if($this.okToLaunch)
        {
            # Get the arguments to build a JSON object
            $jsonArgs = $this | Select-Object cifsServerName, pathToCheck, maxDepth, directoriesOnly, doDebug, logPath, logLevel, databaseServer, databaseName, pathsToAvoid, partialPathsToAvoid

            # Encode $jsonArgs to text
            $rawJson = $jsonArgs | ConvertTo-Json

            # Create a .json file to hold the arguments
            $parts = $this.pathToCheck.Split("\", [System.StringSplitOptions]::RemoveEmptyEntries)
            $jsonArgsFileName = "{0}\{1}-args.json" -f @($this.logPath, [String]::Join("-", $parts))

            # Save the JSON arguments to the file
            $rawJson | Out-File -FilePath $jsonArgsFileName

            # WQL to find all processes where $this.scriptPath exists in the command-line.
            $processQuery = "SELECT * FROM Win32_Process WHERE (CommandLine LIKE '%{0}%')" -f @($this.scriptPath.Replace("\","\\"))

            # Arguments used to launch the script locally
            $scriptArgs = @()

            # If $this.scriptPath is running locally, then setup $scriptArgs...
            if($this.launchingLocal)
            {
                # If debugging, don't let the local powershell window close so we can verify
                if($this.doDebug)
                {
                    $scriptArgs += "-NoExit"
                }

                foreach($a in @("-command", $this.scriptPath, "-jsonArgsFile", $jsonArgsFileName))
                {
                    $scriptArgs += $a
                }
            }
            else
            {
                # Nothing...
            }

            # Check to make sure I haven't launched [JobTracker]::maxSubProcesses already...
            $childProcs = @()
            do
            {
                $childProcs = @(Get-WmiObject -ComputerName $this.mgmtServer -Query $processQuery)
                if($childProcs.Length -ge [JobTracker]::maxSubProcesses)
                {
                    Start-Sleep -Milliseconds 250
                }
            }
            while($childProcs.Length -ge [JobTracker]::maxSubProcesses)

            # If running locally...
            if($this.launchingLocal)
            {
                # ...then start a new powershell process..
                Start-Process "powershell.exe" -WindowStyle Minimized -ArgumentList $scriptArgs
            }
            else
            {
                # ...otherwise launch $this.scriptPath on the remote management server.
                $this.job = Invoke-Command -ComputerName $this.mgmtServer -scriptblock { & $Using:this.scriptPath -jsonArgsFile $Using:jsonArgsFileName } -ConfigurationName $this.psRemoteConfName -AsJob
            }
        }
        else
        {
            [Log]::Warning("Attempt to launch remote script when job is not ok to launch.  Check logs.")
        }
    }

    [System.Management.Automation.JobState] GetState()
    {
        $retval = [System.Management.Automation.JobState]::NotStarted

        if($null -ne $this.job)
        {
            $retval = $this.job.JobStateInfo.State
        }

        return $retval
    }

    [System.Object] GetResults()
    {
        if($null -eq $this.results)
        {
            if($this.GetState() -eq [System.Management.Automation.JobState]::Completed)
            {
                $this.results = @($this.job| Receive-Job)
            }
            else
            {
                # Nothing, can't get results if the job isn't complete.
            }
        }

        return $this.results
    }
}
