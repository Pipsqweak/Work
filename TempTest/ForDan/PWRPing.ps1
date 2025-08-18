[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $jsonFilePath = "\\10.236.3.37\Xchange\ForDG\PWRPingCfg.json"
)

$maxFileStreamRetryPeriodMS = 1000

# Get configuration data from the JSON file.
$configText = [String]::Empty
try
{
    $configText = Get-Content -Path $jsonFilePath -ErrorAction Stop
}
catch
{
    Write-Host -ForegroundColor Red ("Failed to read configuration data from {0}" -f @($jsonFilePath))
}

$config = $null
if (-not [String]::IsNullOrEmpty($configText))
{
    try
    {
        $config = $configText | ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to parse JSON data from config file.  Check for valid format.")
    }
} `
else # NOT (-not [String]::IsNullOrEmpty($configText))
{
    # Nothing.
}

if ($null -ne $config)
{
    if (($null -ne $config.IPList) -and ($config.IPList -is [Array]))
    {
        if (($null -ne $config.PingCount) -and ($config.PingCount -is [Int32]))
        {
            if (-not [String]::IsNullOrEmpty($config.ResultsFile))
            {
                $resultsDirectory = [System.IO.Path]::GetDirectoryName($config.ResultsFile)
                if ([System.IO.Directory]::Exists($resultsDirectory))
                {
                    $localHostIP = $env:COMPUTERNAME

                    # Get the IPv4 address of the host running this script.
                    try
                    {
                        $localTest = Test-Connection -ComputerName $localHostIP -Count 1 -ErrorAction Stop

                        $localHostIP = $localTest.IPV4Address.ToString()
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red "Failed to determine local host IP address.  Using local host name instead."
                    }

                    # Array to hold results
                    $results = @()

                    # Loop through each IP and collect statistics
                    $a = 0
                    while($a -lt $config.IPList.Length)
                    {
                        $ipToPing = $config.IPList[$a]
                        $d = [PSCustomObject]@{
                            SourceIP = $localHostIP
                            SourceComputer = $env:COMPUTERNAME
                            SourceUserName = $env:USERNAME

                            Destination = $ipToPing
                            MinResponseTime = "Unreachable"
                            MaxResponseTime = "Unreachable"
                            AvgResponseTime = "Unreachable"
                        }
                        Write-Host ("Pinging {0} {1} times..." -f @($ipToPing, $config.PingCount))

                        $responses = Test-Connection -ComputerName $ipToPing -Count $config.PingCount -ErrorAction SilentlyContinue
                        if ($responses)
                        {
                            $times = $responses | Select-Object -ExpandProperty ResponseTime
                            $measurements = $times | Measure-Object -Minimum -Maximum -Average

                            $d.MinResponseTime = $measurements.Minimum
                            $d.MaxResponseTime = $measurements.Maximum
                            $d.AvgResponseTime = [math]::Round($measurements.Average, 2)
                        } `
                        else  # NOT ($responses)
                        {
                            # Nothing, leave $d set to unavailable
                        }

                        $resultsStr = $d | Format-Table -AutoSize | Out-String
                        Write-Host ($resultsStr.Replace("`r`n","`r`n`t"))

                        $results += $d
                        $a++
                    }

                    if ($results.Length -gt 0)
                    {
                        $resultsSaved = $false

                        # Try to acquire a file lock so no more than 1 user at a time attempts to append results to the results file.
                        $sw = [System.Diagnostics.Stopwatch]::new()
                        $sw.Start()
                        $haveLock = $false
                        $lockFileName = "{0}\PWRPing.lck" -f @($resultsDirectory)
                        $fLock = $null
                        do
                        {
                            try
                            {
                                # Create a lock file so no other process tries to verify/create this path while I am.
                                $fLock = [System.IO.File]::Open($lockFileName, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                                $haveLock = $true
                            }
                            catch
                            {
                                # Failed to acquire the lock.  Assume another process has the lock file
                                # Sleep a bit to allow the other process to complete its work.
                                Start-Sleep -Milliseconds 10
                            }
                        } while((-not $haveLock) -and ($sw.ElapsedMilliseconds -lt $maxFileStreamRetryPeriodMS))
                        $sw.Stop()

                        if ($haveLock)
                        {
                            try
                            {
                                # Export results to CSV
                                $results | Export-Csv -Path $config.ResultsFile -NoTypeInformation -Append -ErrorAction Stop
                                Write-Host ("Results appended to {0}." -f @($config.ResultsFile))
                                $resultsSaved = $true
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("Failed to append results to {0}." -f @($config.ResultsFile))
                            }
                            $fLock.Close()
                            [System.IO.File]::Delete($lockFileName)
                        } `
                        else # NOT ($haveLock)
                        {
                            Write-Host -ForegroundColor "Failed to acquire file lock prior to saving results."
                        }

                        if (-not $resultsSaved)
                        {
                            # Dump the results to the screen...
                            Write-Host "Results:"
                            $resultsStr = $results | Format-Table -AutoSize | Out-String
                            Write-Host ($resultsStr.Replace("`r`n","`r`n`t"))
                        } `
                        else # NOT (-not $resultsSaved)
                        {
                            # Nothing.
                        }
                    } `
                    else
                    {
                        # Nothing, no results to save.
                    }
                } `
                else # NOT ([System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($config.ResultsFile)))
                {
                    Write-Host -ForegroundColor Red ("Results directory {0} does not exist." -f @($resultsDirectory))
                }
            } `
            else # NOT (-not [String]::IsNullOrEmpty($config.ResultsFile))
            {
                Write-Host -ForegroundColor "ResultsFile is missing or incorrect.  Should be a string value."
            }
        } `
        else # NOT (($null -ne $config.PingCount) -and ($config.PingCount -is [Int32]))
        {
            Write-Host -ForegroundColor "PingCount is missing or incorrect.  Should be an Int32 value."
        }
    } `
    else # NOT ((($null -ne $config.IPList) -and ($config.IPList -is [Array]))
    {
        Write-Host -ForegroundColor "IPList is missing or incorrect.  Should be an array of IP addresses."
    }
} `
else # NOT ($null -ne $config)
{
    # Nothing.
}
