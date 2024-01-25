[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [AllowNull()]
    [String]
    $configFileName="\\cdcfs1\Reference\PerfTest\config.json",

    [Parameter(Mandatory=$false)]
    [String]
    $Description,

    [Parameter(Mandatory=$false)]
    [Switch]
    $TrackOverallElapsed,

    [Parameter(Mandatory=$false)]
    [Switch]
    $Riverbed,

    [Parameter(Mandatory=$false)]
    [Switch]
    $TestLocal,

    [Parameter(Mandatory=$false)]
    [Switch]
    $LimitLargeFiles
)

$Global:maxRetries = 3

<#
    -Riverbed: Only test to EDCs
        To complete a "Riverbed" test, the script will be ran manually from a computer where Riverbed appliances are utilized between the test computer and the EDCs.
          Typically, there would be 3 variations of the test:

            1) Riverbed active w/ optimization (normal)
            2) Riverbed active w/o optimization
            3) Riverbed inactive

        Therefore, if -Riverbed is set, testing will be conducted between whichever computer is running the script and all EDCs.

#>

function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # TRUE

        # Using -match to parse out the octets.
        if($ipStr -match "^((\d+)\.(\d+)\.(\d+)\.(\d+))$")
        {
            $a = 0
            while($a -lt 4)
            {
                $octet = [Convert]::ToUInt32($Matches[$a + 2], 10)
                $ipAddr += ($octet -shl (24 - (8 * $a)))
                $a++
            }
        }
    }
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # FALSE

        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

function SummarizeTestResults
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [System.Collections.Generic.List[Object]]
        $fileResults,

        [Parameter(Mandatory=$false, Position=1)]
        [Switch]
        $SmallFiles,

        [Parameter(Mandatory=$false, Position=1)]
        [Switch]
        $MediumFiles,

        [Parameter(Mandatory=$false, Position=1)]
        [Switch]
        $LargeFiles
    )

    $d = "" | Select-Object TotalBytes, TotalMS, AverageMS, AverageMBPS, OverallMBPS

    if($SmallFiles)
    {
        $fileCopyStats = $fileResults | Where-Object { $_.BytesRead -lt 4823450 }
    } `
    elseif($MediumFiles)
    {
        $fileCopyStats = $fileResults | Where-Object { ($_.BytesRead -ge 4823450) -and ($_.BytesRead -lt 154350387) }
    } `
    else
    {
        $fileCopyStats = $fileResults | Where-Object { ($_.BytesRead -ge 154350387) }
    }

    $bytesRead = $fileCopyStats | Measure-Object -Average -Sum -Property BytesRead
    $readTimeMS = $fileCopyStats | Measure-Object -Average -Sum -Property ReadTimeMS
    $MBPS = $fileCopyStats | Measure-Object -Average -Sum -Property MBPS

    $d.TotalBytes = $bytesRead.Sum
    $d.TotalMS = $readTimeMS.Sum
    $d.AverageMS = $readTimeMS.Average
    $d.AverageMBPS = $MBPS.Average
    $d.OverallMBPS = 0
    if($readTimeMS.Sum -gt 0)
    {
        $d.OverallMBPS = (($bytesRead.Sum / $readTimeMS.Sum) * 1000) / 1MB
    }

    return $d
}

function TestLatency
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $serverName,

        [Parameter(Mandatory=$false)]
        [Int]
        $count=25
    )

    $tr = $null
    $alive = $false
    $tries = 0
    do
    {
        try
        {
            $tries++
            $tr = Test-Connection -Destination $serverName -Count $count -ErrorAction Stop | Select-Object @{N='SourceName';E={$_.PSComputerName}}, @{N='SourceIP';E={$_.IPV4Address.IPAddressToString}}, @{N='DestinationName';E={$_.Address}}, @{N='DestinationIP';E={$_.ProtocolAddress}}, ReplySize, @{N='ResponseTTL';E={$_.ResponseTimeToLive}}, ResponseTime
            $alive = $true
        }
        catch
        {
            if($count -gt 5)
            {
                $count -= 5
            }
        }
    }
    while((-not $alive) -and ($tries -lt $Global:maxRetries))

    return @($alive, $tr)
}

function TestDatacenter
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $dcName,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $serverName,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $shareName,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $TrackOverallElapsed,

        [Parameter(Mandatory=$false)]
        [Switch]
        $LimitLargeFiles
    )

    $largeFileLimit = 5
    $testResults = $null

    Write-Host -NoNewline -ForegroundColor Green ("Testing {0}..." -f @($dcName))
    # Prime the pump so to speak.  Wake up the connection...
    $alive, $null = TestLatency -serverName $serverName -count 3

    if($alive)
    {
        # Now, really test the connection...
        $alive, $tr = TestLatency $serverName -count 25

        if($alive -and ($null -ne $tr))
        {
            $avgMS = ($tr | Measure-Object -Average -Property ResponseTime).Average
            Write-Host -ForegroundColor Green ("`t{0}ms" -f @($avgMS))

            $testResults = "" | Select-Object DCName, DateTime, ServerName, ShareName, Latency, FileCopy, FileTestSummary
            $testResults.FileTestSummary = "" | Select-Object Small,Medium,Large

            $testResults.DCName = $dcName
            $testResults.ShareName = $shareName
            $testResults.ServerName = $serverName
            $testResults.DateTime = [DateTime]::now.ToString("yyyyMMdd-HHmm")
            $testResults.Latency = $tr

            $sw = [System.Diagnostics.Stopwatch]::new()
            $bufferSize = 4096
            $buffer = [byte[]]::new($bufferSize)
            $b = 0
            $testResults.FileCopy = [System.Collections.Generic.List[Object]]::new()

            $testFileLocation = "\\{0}\{1}\RDCTestFiles" -f @($serverName, $shareName)
            $testFiles = $null
            $tries = 0
            do
            {
                try
                {
                    $tries++
                    $testFiles = Get-ChildItem -Path $testFileLocation -Filter "*.bin" -ErrorAction Stop | Sort-Object Length
                }
                catch { }
            } until(($null -ne $testFiles) -or ($tries -ge $Global:maxRetries))

            if($null -eq $testFiles)
            {
                Write-Host -ForegroundColor Red ("Failed to acquire test files from {0}." -f @($testFileLocation))
            } `
            else
            {
                $largeFileCount = 0
                # I think testing the elapsed time was skewing the test, so I'll only test elapsed time before starting to read another file.
                while(($null -ne $testFiles) -and ($b -lt $testFiles.Length) -and ((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)))
                {
                    if($testFiles[$b].Name -match "large")
                    {
                        $largeFileCount++
                    }

                    if((-not $LimitLargeFiles) -or ($largeFileCount -le $largeFileLimit))
                    {
                        Write-Host -NoNewline ("`tTest file {0,2} of {1} length: {2,11:N0} bytes" -f @(($b + 1), $testFiles.Length, $testFiles[$b].Length))

                        $tries = 0
                        do
                        {
                            $sw.Reset()
                            $sw.Start()
                            $bytesRead = 0

                            try
                            {
                                $tries++
                                $stream = [System.IO.File]::Open($testFiles[$b].FullName, [System.IO.FileMode]::Open)
                                $reader = [System.IO.BinaryReader]::new($stream)
                                do
                                {
                                    $len = $reader.Read($buffer, 0, $bufferSize)
                                    $bytesRead += $len
                                } until($len -lt $bufferSize) # -or ($TrackOverallElapsed -and ($Script:overAllSW.Elapsed.TotalMinutes -ge $Script:MaximumRuntime)))
                                # I think testing the elapsed time was skewing the test, so I'll only test elapsed time before starting to read another file.
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("`r`n`tFailed to read {0}.`r`n" -f @($testFiles[$b].FullName))
                            }
                            finally
                            {
                                if($null -ne $reader)
                                {
                                    $reader.Close()
                                    $reader.Dispose()
                                }

                                if($null -ne $stream)
                                {
                                    $stream.Close()
                                    $stream.Dispose()
                                }
                            }

                            $sw.Stop()
                        } until(($tries -ge $Global:maxRetries) -or ($bytesRead -ge $testFiles[$b].Length))

                        if($bytesRead -ge $testFiles[$b].Length)
                        {
                            $fcMetric = "" | Select-Object BytesRead,ReadTimeMS,MBPS
                            $fcMetric.BytesRead = $bytesRead
                            $fcMetric.ReadTimeMS = $sw.Elapsed.TotalMilliseconds
                            $fcMetric.MBPS = (($fcMetric.BytesRead / $fcMetric.ReadTimeMS) * 1000) / 1MB
                            $ts = [TimeSpan]::new(0,0,0,0,$fcMetric.ReadTimeMS).ToString().TrimEnd("0")
                            Write-Host -ForegroundColor Green ("`tRead time: {0,12:N2}ms ({1,12}) @ {2,5:N2}MB/s" -f @($fcMetric.ReadTimeMS, $ts, $fcMetric.MBPS))
                            $testResults.FileCopy.Add($fcMetric)

                            if((-not $LimitLargeFiles) -and ($fcMetric.ReadTimeMS -gt 60000))
                            {
                                $LimitLargeFiles = $true
                                if($largeFileCount -lt 5)
                                {
                                    Write-Host -ForegroundColor Yellow ("Due to excessive read time, large files will be limited to {0}." -f @($largeFileLimit))
                                } `
                                else
                                {
                                    Write-Host -ForegroundColor Yellow ("Large file test aborted after {0} files due to excessive read time." -f @($largeFileCount))
                                }
                            }
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red ("Failed to completely read file after {0} retries." -f @($tries + 1))
                        }
                    }
                    $b++
                }

                $testResults.FileTestSummary.Small = SummarizeTestResults -fileResults $testResults.FileCopy -SmallFiles
                $testResults.FileTestSummary.Medium = SummarizeTestResults -fileResults $testResults.FileCopy -MediumFiles
                $testResults.FileTestSummary.Large = SummarizeTestResults -fileResults $testResults.FileCopy -LargeFiles
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "`tFailed to test latency..."
        }
    }
    else
    {
        Write-Host -ForegroundColor Yellow ("{0} does not respond." -f @($serverName))
    }

    return $testResults
}

function SendAlert
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $alertMessage
    )

    $smtpClient = [System.Net.Mail.SmtpClient]::new("smtp.powereng.com")
    $mailMessage = [System.Net.Mail.MailMessage]::new()
    $mailMessage.Subject = "{0}: PerfTest Alert" -f @([DateTime]::Now.ToString("yyyyMMdd"))
    $mailMessage.From = "Performance Tester Script <donotreply@powereng.com>"
    $Global:off2RDCMetricsConfig.AlertEmailAddresses | ForEach-Object { $mailMessage.To.Add($_) }
    $mailMessage.Body = $alertMessage
    $mailMessage.ReplyTo = [mailaddress]::new("DoNotReply <donotreply@powereng.com>")

    try
    {
        $Error.Clear()
        $smtpClient.Send($mailMessage)
    }
    catch
    {
        Write-Error "Failed to send alert email."
    }
}

# For Debugging/Development...
#$configFileName = ".\RDC\Metrics\config.json"
#$TrackOverallElapsed = $false

$off2RDCMetricsConfig = $null
$ipv4s = $null
$hostOffice = $null
$hostRDC = $null
$allTestResults = [System.Collections.Generic.List[Object]]::new()
$sbAlertEmail = [System.Text.StringBuilder]::new()

if([String]::IsNullOrEmpty($configFileName))
{
    $configFileName = "{0}\config.json" -f @($PSScriptRoot)
}

try
{
    $off2RDCMetricsConfig = Get-Content -Path $configFileName -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch
{
    Write-Host -ForegroundColor Red ("ERROR: Unable to load configuration file from: {0}." -f @($configFileName))
}

if($null -ne $off2RDCMetricsConfig)
{
    try
    {
        $ipv4s = @(Get-NetIPAddress -ErrorAction Stop | Where-Object { ($_.AddressFamily -eq "IPv4") -and ($_.InterfaceAlias -notmatch "Loopback") -and ($_.IPAddress.StartsWith("10.") -and ($_.InterfaceAlias -notmatch "Device Tunnel"))})
    }
    catch
    {
        Write-Host -ForegroundColor Red "ERROR: Unable to determine computer's location based on IP address.  Could not determine a usable IPv4 address."
    }
}

if($null -ne $ipv4s)
{
    $i = 0
    do
    {
        $hostOffice = $off2RDCMetricsConfig.Offices | Where-object { ((INET_ATON $_.StartIP) -lt (INET_ATON $ipv4s[$i].IPAddress)) -and ((INET_ATON $ipv4s[$i].IPAddress) -lt (INET_ATON $_.EndIP)) }
        if($null -eq $hostOffice)
        {
            $i++
        }
    } until (($null -ne $hostOffice) -or ($i -ge $ipv4s.Length))
}

if($null -ne $hostOffice)
{
    Write-Host -ForegroundColor Green ("Determined computer's location to be: {0} based on IP Address: {1}." -f @($hostOffice.Name, $ipv4s[$i].IPAddress))
    $hostRDC = $off2RDCMetricsConfig.RDCs | Where-Object { $_.Name -eq $hostOffice.RDC }

    if($null -ne $off2RDCMetricsConfig.ResultsRepository)
    {
        if([System.IO.Directory]::Exists($off2RDCMetricsConfig.ResultsRepository))
        {
            $Script:MaximumRuntime = 30
            if($null -ne $off2RDCMetricsConfig.MaximumRuntime)
            {
                $Script:MaximumRuntime = $off2RDCMetricsConfig.MaximumRuntime
            }
            $Script:overAllSW = [System.Diagnostics.Stopwatch]::new()

            if ($Riverbed)
            {
                Write-Host -ForegroundColor Green "Performing 'Riverbed' test..."
                # Test Office to EDCs
                $a = 0
                while($a -lt $off2RDCMetricsConfig.EDCs.Length)
                {
                    if(@($allTestResults | Where-Object { $_.DCName -eq $off2RDCMetricsConfig.EDCs[$a].Name }).Length -eq 0)
                    {
                        $tr = TestDatacenter -dcName $off2RDCMetricsConfig.EDCs[$a].Name -serverName $off2RDCMetricsConfig.EDCs[$a].ServerName -shareName $off2RDCMetricsConfig.EDCs[$a].ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                        if($null -ne $tr)
                        {
                            $allTestResults.Add($tr)
                        }
                    }
                    $a++
                }
            } `
            else # NOT ($Riverbed)
            {
                # Remove any EDC that are tagged RiverbedOnly ... BOI
                $off2RDCMetricsConfig.EDCs = $off2RDCMetricsConfig.EDCs | Where-Object { -not $_.RiverbedOnly }

                if($null -ne $hostRDC)
                {
                    Write-Host -ForegroundColor Green ("Office: {0} is associated with RDC: {1}" -f @($hostOffice.Name, $hostRDC.Name))

                    if($TrackOverallElapsed)
                    {
                        Write-Host ("Testing started.  Testing will terminate after approximately {0} minutes.`r`n" -f @($Script:MaximumRuntime))
                    } `
                    else
                    {
                        Write-Host ("Testing started.  Unlimited test time.")
                    }

                    $Script:overAllSW.Start()

                    if($TestLocal -and (-not [String]::IsNullOrEmpty($hostOffice.LocalStorage.ServerName)) -and (-not [String]::IsNullOrEmpty($hostOffice.LocalStorage.ShareName)))
                    {
                        $tr = TestDatacenter -dcName $hostOffice.Name -serverName $hostOffice.LocalStorage.ServerName -shareName $hostOffice.LocalStorage.ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                        $allTestResults.Add($tr)
                    }

                    # Always test the office's associated RDC first so we at least get it...
                    if($hostRDC.Active)
                    {
                        if(@($allTestResults | Where-Object { ($_.ServerName -eq $hostRDC.ServerName) -and ($_.ShareName -eq $hostRDC.ShareName) }).Length -eq 0)
                        {
                            $tr = TestDatacenter -dcName $hostRDC.Name -serverName $hostRDC.ServerName -shareName $hostRDC.ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                            $allTestResults.Add($tr)
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Yellow ("Already tested: \\{0}\{1}." -f @($hostRDC.ServerName, $hostRDC.ShareName))
                        }
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Yellow ("Skipping inactive RDC: {0}." -f @($hostRDC.Name))
                    }

                    # If time allows, test the enterprise datacenters...
                    $a = 0
                    while(((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)) -and ($a -lt $off2RDCMetricsConfig.EDCs.Length))
                    {
                        if(@($allTestResults | Where-Object { ($_.ServerName -eq $off2RDCMetricsConfig.EDCs[$a].ServerName) -and ($_.ShareName -eq $off2RDCMetricsConfig.EDCs[$a].ShareName) }).Length -eq 0)
                        {
                            $tr = TestDatacenter -dcName $off2RDCMetricsConfig.EDCs[$a].Name -serverName $off2RDCMetricsConfig.EDCs[$a].ServerName -shareName $off2RDCMetricsConfig.EDCs[$a].ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                            if($null -ne $tr)
                            {
                                $allTestResults.Add($tr)
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Yellow ("Already tested: \\{0}\{1}." -f @($off2RDCMetricsConfig.EDCs[$a].ServerName, $off2RDCMetricsConfig.EDCs[$a].ShareName))
                        }
                        $a++
                    }

                    # If time allows, test the remaining RDCs...
                    $a = 0
                    while(((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)) -and ($a -lt $off2RDCMetricsConfig.RDCs.Length))
                    {
                        if($off2RDCMetricsConfig.RDCs[$a].Active)
                        {
                            # Don't retest a server\share ...
                            if(@($allTestResults | Where-Object { ($_.ServerName -eq $off2RDCMetricsConfig.RDCs[$a].ServerName) -and ($_.ShareName -eq $off2RDCMetricsConfig.RDCs[$a].ShareName) }).Length -eq 0)
                            {
                                $tr = TestDatacenter -dcName $off2RDCMetricsConfig.RDCs[$a].Name -serverName $off2RDCMetricsConfig.RDCs[$a].ServerName -shareName $off2RDCMetricsConfig.RDCs[$a].ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                                if($null -ne $tr)
                                {
                                    $allTestResults.Add($tr)
                                }
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Yellow ("Already tested: \\{0}\{1}." -f @($off2RDCMetricsConfig.RDCs[$a].ServerName, $off2RDCMetricsConfig.RDCs[$a].ShareName))
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Yellow ("Skipping inactive RDC: {0}." -f @($off2RDCMetricsConfig.RDCs[$a].Name))
                        }

                        $a++
                    }
                }

                $Script:overAllSW.Stop()
                Write-Host ("Overall test took: {0}" -f @($Script:overAllSW.Elapsed.ToString()))
            }

            if($allTestResults.Count -gt 0)
            {
                $resultFileName = "{0}\{1}-{2}-{3}.csv" -f @($off2RDCMetricsConfig.ResultsRepository, [DateTime]::Now.ToString("yyyyMMddHHmm"), $hostOffice.Name, $env:COMPUTERNAME)

                $allTestResults | Select-Object DCName,
                    @{N='TestHost';E={hostname}},
                    ServerName, DateTime, @{N='Description';E={$Description}},
                    @{N='Latency';E={ ($_.Latency | Measure-Object -Average -Property ResponseTime).Average}},
                    @{N='SmallFileBytesRead';E={$_.FileTestSummary.Small.TotalBytes}},
                    @{N='SmallFileReadTime';E={$_.FileTestSummary.Small.TotalMS}},
                    @{N='SmallFileMBPS';E={$_.FileTestSummary.Small.OverallMBPS}},
                    @{N='MediumFileBytesRead';E={$_.FileTestSummary.Medium.TotalBytes}},
                    @{N='MediumFileReadTime';E={$_.FileTestSummary.Medium.TotalMS}},
                    @{N='MediumFileMBPS';E={$_.FileTestSummary.Medium.OverallMBPS}},
                    @{N='LargeFileBytesRead';E={$_.FileTestSummary.Large.TotalBytes}},
                    @{N='LargeFileReadTime';E={$_.FileTestSummary.Large.TotalMS}},
                    @{N='LargeFileMBPS';E={$_.FileTestSummary.Large.OverallMBPS}} | Export-CSV -Delimiter "`t" -NoTypeInformation -Path $resultFileName -Force

                Write-Host -ForegroundColor Green ("Test Results saved to: {0}." -f @($resultFileName))
            } `
            else
            {
                Write-Host -ForegroundColor Yellow "No test results to save."
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red ("The results repository specified in the configuration file ({0}) does not exist.  Tests will not be ran." -f @($off2RDCMetricsConfig.ResultsRepository))
        }
    } `
    else
    {
        [void] $sbAlertEmail.AppendLine(("No results repository was specified in the configuration file.  Tests will not be ran."))
    }
}
else
{
    # Unable to determine office location based on IP address.
    [void] $sbAlertEmail.AppendLine(("Unable to determine office based on IP Address(es): {0}" -f @(($ipv4s | Select-Object -ExpandProperty IPAddress) -join ", ")))
}

if($sbAlertEmail.Length -gt 0)
{
    SendAlert -alertMessage $sbAlertEmail.ToString()
}
