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

function Get-StandardDeviation { #Begin function Get-StandardDeviation
    [cmdletbinding()]
    param(
    [Parameter(Mandatory=$true)]
    [decimal[]]$value
    )

    [decimal]$stdDev      = $null

    #Simple if to see if the value matches digits, and also that there is more than one number.
    if ($value -match '\d+' -and $value.Count -gt 1) {

        #Variables used later
        [decimal]$newNumbers  = $Null

        #Get the average and count via Measure-Object
        $avgCount             = $value | Measure-Object -Average | Select Average, Count

        #Iterate through each of the numbers and get part of the variance via some PowerShell math.
        ForEach($number in $value) {

            $newNumbers += [Math]::Pow(($number - $avgCount.Average), 2)

        }

        #Finish the variance calculation, and get the square root to finally get the standard deviation.
        $stdDev = [math]::Sqrt($($newNumbers / ($avgCount.Count - 1)))
    }

    return $stdDev

} #End function Get-StandardDeviation

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

    $d = "" | Select-Object TotalBytes, TotalMS, AverageMS, AverageMBPS, OverallMBPS, MSStdDev

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
        $d.MSStdDev = Get-StandardDeviation @($fileCopyStats | Select-Object -ExpandProperty ReadTimeMS)
    }

    return $d
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

    $largeFileLimit = 20
    if($LimitLargeFiles)
    {
        $largeFileLimit = 5
    }
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
            $testResults.FileCopy = [System.Collections.Generic.List[Object]]::new()

            $testFileLocation = "\\{0}\{1}\RDCTestFiles" -f @($serverName, $shareName)
            $tmpTestFiles = $null
            $tries = 0
            do
            {
                try
                {
                    $tries++
                    $tmpTestFiles = Get-ChildItem -Path $testFileLocation -Filter "*.bin" -ErrorAction Stop | Sort-Object Length,Name
                }
                catch { }
            } until(($null -ne $tmpTestFiles) -or ($tries -ge $Global:maxRetries))

            if($null -eq $tmpTestFiles)
            {
                Write-Host -ForegroundColor Red ("Failed to acquire test files from {0}." -f @($testFileLocation))
            } `
            else
            {
                $testFiles = [System.Collections.Generic.List[System.Object]]::new()

                $tmpTestFiles | Where-Object { ($_.Name -match "small|medium") } | Foreach-Object { $testFiles.Add($_) }
                $tmpTestFiles | Where-Object { $_.Name -match "large"} | Select-Object -First $largeFileLimit | Foreach-Object { $testFiles.Add($_) }

                $b = 0
                $largeFileCount = 0
                # I think testing the elapsed time was skewing the test, so I'll only test elapsed time before starting to read another file.
                while( ($b -lt $testFiles.Count) -and ((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)))
                {
                    if($testFiles[$b].Name -match "large")
                    {
                        $largeFileCount++
                    }

                    if((-not $LimitLargeFiles) -or ($largeFileCount -le $largeFileLimit))
                    {
                        Write-Host -NoNewline ("`t{0}: Test file {1,3} of {2} length: {3,11:N0} bytes" -f @([DateTime]::now.ToString("HH:mm:ss.fff"), ($b + 1), $testFiles.Count, $testFiles[$b].Length))

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
                            Write-Host -ForegroundColor Green ("`tRead time: {0,12:N2}ms ({1:D2}:{2:D2}.{3:D3}) @ {4,5:N2}MB/s -- {5}" -f @($fcMetric.ReadTimeMS, [int]($sw.Elapsed.TotalMinutes), $sw.Elapsed.Seconds, $sw.Elapsed.Milliseconds, $fcMetric.MBPS, [DateTime]::now.ToString("HH:mm:ss.fff")))
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
                Write-Host ("Small file read time average: {0:N2}, standard deviation: {1:N2}, Variance: {2:N2}%" -f @($testResults.FileTestSummary.Small.AverageMS, $testResults.FileTestSummary.Small.MSStdDev, (($testResults.FileTestSummary.Small.MSStdDev / $testResults.FileTestSummary.Small.AverageMS) * 100.0)))
                $testResults.FileTestSummary.Medium = SummarizeTestResults -fileResults $testResults.FileCopy -MediumFiles
                Write-Host ("Medium file read time average: {0:N2}, standard deviation: {1:N2}, Variance: {2:N2}%" -f @($testResults.FileTestSummary.Medium.AverageMS, $testResults.FileTestSummary.Medium.MSStdDev, (($testResults.FileTestSummary.Medium.MSStdDev / $testResults.FileTestSummary.Medium.AverageMS) * 100.0)))
                $testResults.FileTestSummary.Large = SummarizeTestResults -fileResults $testResults.FileCopy -LargeFiles
                Write-Host ("Large file read time average: {0:N2}, standard deviation: {1:N2}, Variance: {2:N2}%" -f @($testResults.FileTestSummary.Large.AverageMS, $testResults.FileTestSummary.Large.MSStdDev, (($testResults.FileTestSummary.Large.MSStdDev / $testResults.FileTestSummary.Large.AverageMS) * 100.0)))
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

function Set-AlternatingRows
{
    <#
    .SYNOPSIS
        Simple function to alternate the row colors in an HTML table
    .DESCRIPTION
        This function accepts pipeline input from ConvertTo-HTML or any
        string with HTML in it.  It will then search for <tr> and replace
        it with <tr class=(something)>.  With the combination of CSS it
        can set alternating colors on table rows.

        CSS requirements:
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }

        Classnames can be anything and are configurable when executing the
        function.  Colors can, of course, be set to your preference.

        This function does not add CSS to your report, so you must provide
        the style sheet, typically part of the ConvertTo-HTML cmdlet using
        the -Head parameter.
    .PARAMETER Line
        String containing the HTML line, typically piped in through the
        pipeline.
    .PARAMETER CSSEvenClass
        Define which CSS class is your "even" row and color.
    .PARAMETER CSSOddClass
        Define which CSS class is your "odd" row and color.
    .EXAMPLE $Report | ConvertTo-HTML -Head $Header | Set-AlternateRows -CSSEvenClass even -CSSOddClass odd | Out-File HTMLReport.html

        $Header can be defined with a here-string as:
        $Header = @"
        <style>
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        </style>
        "@

        This will produce a table with alternating white and grey rows.  Custom CSS
        is defined in the $Header string and included with the table thanks to the -Head
        parameter in ConvertTo-HTML.
    .NOTES
        Author:         Martin Pugh
        Twitter:        @thesurlyadm1n
        Spiceworks:     Martin9700
        Blog:           www.thesurlyadmin.com

        Changelog:
            1.1         Modified replace to include the <td> tag, as it was changing the class
                        for the TH row as well.
            1.0         Initial function release
    .LINK
        http://community.spiceworks.com/scripts/show/1745-set-alternatingrows-function-modify-your-html-table-to-have-alternating-row-colors
    .LINK
        http://thesurlyadmin.com/2013/01/21/how-to-create-html-reports/
    #>
    [CmdletBinding()]
        Param(
            [Parameter(Mandatory,ValueFromPipeline)]
            [string]$Line,

            [Parameter(Mandatory)]
            [string]$CSSEvenClass,

            [Parameter(Mandatory)]
            [string]$CSSOddClass
        )

    Begin
    {
        $ClassName = $CSSEvenClass
    }

    Process
    {
        if ($Line.Contains("<tr><td>"))
        {
            $Line = $Line.Replace("<tr>","<tr class=""$ClassName"">")
            if ($ClassName -eq $CSSEvenClass)
            {
                $ClassName = $CSSOddClass
            }
            else
            {
                $ClassName = $CSSEvenClass
            }
        }

        return $Line
    }
}

function SendResultsSummary
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [System.Collections.Generic.List[Object]]
        $allTestResults,

        [Parameter(Mandatory=$true, Position=1)]
        [String]
        $officeName,

        [Parameter(Mandatory=$true, Position=2)]
        [String]
        $description
    )

    $htmlHeader =
@"
<head>
    <title>{0} Perf Testing</title>
    <style>
        body {{ font-family: Consolas,monaco,monospace; font-size: 9pt; }}
        th {{ background-color:#0083FF; padding: 2px; font-size: 10pt; }}
        td {{ text-align: center; padding: 2px; }}
        .odd  {{ background-color:#ffffff; }}
        .even {{ background-color:#dddddd; }}
        table, th, td {{ border: 1px solid black; border-collapse: collapse; }}
        .notice {{ font-size: 12pt; }}
        .red {{ color: red; }}
    </style>
</head>
"@ -f @($officeName)

    $htmlPre = "<span class='notice'>Values in <span class='red'>red</span> indicate a large variance in file read times.  This may indicate an anomaly especially for medium and large files.</span><br /><br />"

    $html = @($allTestResults |
        Select-Object `
            @{N = 'Datacenter';  E = { $_.DCName }},
            @{N = 'Test host';   E = { hostname }},
            @{N = 'File server'; E = { $_.ServerName }},
            @{N = 'Description'; E = { $description }},

            @{N = 'Small file average<br />read time (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Small.AverageMS) }},
            @{N = 'Small file standard<br/>deviation (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Small.MSStdDev) }},
            @{N = 'Small file<br />variance'; E={ if((($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0) -gt 25) { ("<div class='red'>{0:N2}%</div>" -f @([decimal](($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0))) } else { ("{0:N2}%" -f @([decimal](($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0))) }}},

            @{N = 'Medium file average<br />read time (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Medium.AverageMS) }},
            @{N = 'Medium file standard<br/>deviation (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Medium.MSStdDev) }},
            @{N = 'Medium file<br />variance'; E={ if((($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0) -gt 25) { ("<div class='red'>{0:N2}%</div>" -f @([decimal](($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0))) } else { ("{0:N2}%" -f @([decimal](($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0))) }}},

            @{N = 'Large file average<br />read time (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Large.AverageMS) }},
            @{N = 'Large file standard<br/>deviation (MS)';E={ "{0:N2}" -f ([decimal] $_.FileTestSummary.Large.MSStdDev) }},
            @{N = 'Large file<br />variance'; E={ if((($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0) -gt 25) { ("<div class='red'>{0:N2}%</div>" -f @([decimal](($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0))) } else { ("{0:N2}%" -f @([decimal](($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0))) }}} |

        ConvertTo-Html -Head $htmlHeader -PreContent $htmlPre |
        Set-AlternatingRows -CSSEvenClass "even" -CSSOddClass "odd" |
        ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }) -join "`r`n"

    try
    {
        $recipients = @("IT Network <itnetwork@powereng.com>", "Ken Briney <ken.briney@powereng.com>")
        $smtp = [System.Net.Mail.SmtpClient]::new("smtp.powereng.com")
        $subject = "{0} Performance Test Results" -f @($officeName)
        $emailMessage = [System.Net.Mail.MailMessage]::new("Performance Tester <perftest@powereng.com>", $recipients, $subject, $html)
        $emailMessage.IsBodyHtml = $true
        $smtp.send($emailMessage)
    }
    catch
    {
        Write-Error ("Failed to email results to: {0}." -f @($recipients -join ", "))
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

                    # If time allows, test the remaining RDCs...
                    $a = 0
                    while(((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)) -and ($a -lt $off2RDCMetricsConfig.RDCs.Length))
                    {
                        # Don't retest a datacenter ...
                        if($a -ne $off2RDCMetricsConfig.RDCs.IndexOf($hostRDC) -and (@($allTestResults | Where-Object { $_.DCName -eq $off2RDCMetricsConfig.RDCs[$a].Name }).Length -eq 0))
                        {
                            if($off2RDCMetricsConfig.RDCs[$a].Active)
                            {
                                $tr = TestDatacenter -dcName $off2RDCMetricsConfig.RDCs[$a].Name -serverName $off2RDCMetricsConfig.RDCs[$a].ServerName -shareName $off2RDCMetricsConfig.RDCs[$a].ShareName -TrackOverallElapsed:$TrackOverallElapsed -LimitLargeFiles:$LimitLargeFiles
                                if($null -ne $tr)
                                {
                                    $allTestResults.Add($tr)
                                }
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Yellow ("Skipping inactive RDC: {0}." -f @($off2RDCMetricsConfig.RDCs[$a].Name))
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Yellow ("Already tested: \\{0}\{1}." -f @($off2RDCMetricsConfig.RDCs[$a].ServerName, $off2RDCMetricsConfig.RDCs[$a].ShareName))
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

                    @{N='SmallFileAverageMS';E={$_.FileTestSummary.Small.AverageMS}},
                    @{N='SmallFileMSStdDev';E={$_.FileTestSummary.Small.MSStdDev}},
                    @{N='SmallFileMSVariance';E={($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0}},

                    @{N='MediumFileBytesRead';E={$_.FileTestSummary.Medium.TotalBytes}},
                    @{N='MediumFileReadTime';E={$_.FileTestSummary.Medium.TotalMS}},
                    @{N='MediumFileMBPS';E={$_.FileTestSummary.Medium.OverallMBPS}},

                    @{N='MediumFileAverageMS';E={$_.FileTestSummary.Medium.AverageMS}},
                    @{N='MediumFileMSStdDev';E={$_.FileTestSummary.Medium.MSStdDev}},
                    @{N='MediumFileMSVariance';E={($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0}},

                    @{N='LargeFileBytesRead';E={$_.FileTestSummary.Large.TotalBytes}},
                    @{N='LargeFileReadTime';E={$_.FileTestSummary.Large.TotalMS}},
                    @{N='LargeFileMBPS';E={$_.FileTestSummary.Large.OverallMBPS}},

                    @{N='LargeFileAverageMS';E={$_.FileTestSummary.Large.AverageMS}},
                    @{N='LargeFileMSStdDev';E={$_.FileTestSummary.Large.MSStdDev}},
                    @{N='LargeFileMSVariance';E={($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0}}  | Export-CSV -Delimiter "`t" -NoTypeInformation -Path $resultFileName -Force

                Write-Host -ForegroundColor Green ("Test Results saved to: {0}." -f @($resultFileName))

                SendResultsSummary -allTestResults $allTestResults -officeName $hostOffice.Name
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
        Write-Host -ForegroundColor Red ("No results repository was specified in the configuration file.  Tests will not be ran.")
    }
}
else
{
    # Unable to determine office location.
}

# SIG # Begin signature block
# MIIPMgYJKoZIhvcNAQcCoIIPIzCCDx8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUxhPJspfQkXgBI6JEH85Ucvj7
# 2kGgggyXMIIF3zCCBMegAwIBAgITFQAAAALU9Lz04Hi9mwAAAAAAAjANBgkqhkiG
# 9w0BAQ0FADBGMRMwEQYKCZImiZPyLGQBGRYDY29tMRgwFgYKCZImiZPyLGQBGRYI
# cG93ZXJlbmcxFTATBgNVBAMTDFBFSSBSb290IENBMjAeFw0xNTA4MTIyMDQ2MDVa
# Fw0zNTA4MTIyMDA4MDVaME0xEzARBgoJkiaJk/IsZAEZFgNjb20xGDAWBgoJkiaJ
# k/IsZAEZFghwb3dlcmVuZzEcMBoGA1UEAxMTUEVJIFN1Ym9yZGluYXRlIENBMjCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKVLzra7Ww5Nmy+NM14MdRZW
# wEhw09fhAIC6jDl90IGt1D0zvB9xrM1XTrSfEWgCNnveOnNSvXBSHjfWYd7KAs8N
# EDLyIjWluCB66bdi/xY2fascuYJvy2ZmA6Voh005/nRS7lPGq6yfZEjc6LXfiaHS
# Wo+kbrFw/ICoq79kEIympaHeO7TYFOcHoP7T/nfWvD0OrJZLrou9m53qQzZXduBV
# pYwfI91CsGR1DpXKwcgC4yPqLdaP9GmWjYYddT6jQTGD/aCIfYo/29z2vXVafaHx
# 90i8OIF7frlhOL39P3GhxIlDk7espdSKxHWF6772N0XXc7NVaq+Jdw7vtpG02yMC
# AwEAAaOCAr0wggK5MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBQFk+663K25
# Xljs+Tik5+qrsUUojTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8E
# BAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBSwdElPGrGwpa46Uu+0
# SWDcXSTY9TCCAQ8GA1UdHwSCAQYwggECMIH/oIH8oIH5hoG6bGRhcDovLy9DTj1Q
# RUklMjBSb290JTIwQ0EyLENOPUJPSS1SQ0EwMixDTj1DRFAsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1w
# b3dlcmVuZyxEQz1jb20/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29i
# amVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50hjpodHRwOi8vY2VydHMyLnBv
# d2VyZW5nLmNvbS9DZXJ0RW5yb2xsL1BFSSUyMFJvb3QlMjBDQTIuY3JsMIIBFwYI
# KwYBBQUHAQEEggEJMIIBBTCBsAYIKwYBBQUHMAKGgaNsZGFwOi8vL0NOPVBFSSUy
# MFJvb3QlMjBDQTIsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENO
# PVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9cG93ZXJlbmcsREM9Y29tP2NB
# Q2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9y
# aXR5MFAGCCsGAQUFBzAChkRodHRwOi8vY2VydHMyLnBvd2VyZW5nLmNvbS9DZXJ0
# RW5yb2xsL0JPSS1SQ0EwMl9QRUklMjBSb290JTIwQ0EyLmNydDANBgkqhkiG9w0B
# AQ0FAAOCAQEAcpv1ZhjtPnt9puHEI7ex1y8Y5l9KFw9/H0d05h104MDMGuD07HDG
# lQfgvSrmghZP86z2WsssNFbUisjr+aQlCtK8kTdfO/lf3agg/GJBPnzqxiJxIlb9
# Y1v0JT4gJf9sZMsXNiiYwatYGecK8DR2UbWDFUMjcIF7MaECWNedh/aWMb4cah2i
# sNP7FbCftZmP4LJ5VynBGTHb3P6DxYG2YzRxpSFeIlDP1aAABoFuKDGIK72izBG2
# QyeB1W2e7/sjFRiSLbyw2GuSuzHm0o4w3PkHQ0H1yiv50jiX02Sl30J/uP4bNAQF
# kC2U3Ov3RefYTwqj4uLKMmkNEqmpxLoySDCCBrAwggWYoAMCAQICE2YAABLaelh+
# 7dzdJlYAAAAAEtowDQYJKoZIhvcNAQENBQAwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyMB4XDTE2MDMyNDEzNTQzOVoXDTI2MDMyMjEzNTQzOVowgbAxCzAJ
# BgNVBAYTAlVTMQ4wDAYDVQQIEwVJZGFobzEPMA0GA1UEBxMGSGFpbGV5MR0wGwYD
# VQQKExRQT1dFUiBFbmdpbmVlcnMgSW5jLjEWMBQGA1UECxMNT3BlcmF0aW9ucyBJ
# VDFJMEcGA1UEAxNAUE9XRVIgRW5naW5lZXJzIEluZm9ybWF0aW9uIFRlY2hub2xv
# Z3kgSW5mcmFzdHJ1Y3R1cmUgRGVwYXJ0bWVudDCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBANo3WBVO5y8uBMYMzLPqdqDkyMcQoJVQR7yPHPKOh/0DeNoZ
# yVM0qXwdV6sZGaotW0+UR2DzyyMvmwxl5zqIIBEvIwjtHFLU/tAEOWamTf9vMwn+
# LxbUVysZ/RCKkv+V56dOnhtYE3vg+NxRBfEZKViQMXHq6FbmpL1LZcDKlYq1t3RO
# gYhbEHYjG5tEJftg11rznA379+K9yWkybUYEEVCavYNQGp/WHlroK9jMg8RtXIaQ
# pI7O/5CLFondPga3eqEU6fjbE3uDsY2ex7Q1+YnjFhvKt7GkosZo+1yWPeykOPra
# TGxqnig+7c8hKHO+ibV9/xfX8q/iWzlLAPQhMZUCAwEAAaOCAyMwggMfMD4GCSsG
# AQQBgjcVBwQxMC8GJysGAQQBgjcVCIHNilODqvxmhZmNOoHT7HuB1rU5gSGC5vp+
# hMywSwIBZAIBCjATBgNVHSUEDDAKBggrBgEFBQcDAzALBgNVHQ8EBAMCB4AwGwYJ
# KwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUY/0hsMlcQdPeIB7Z
# eh3nuq3RuZ8wHwYDVR0jBBgwFoAUBZPuutytuV5Y7Pk4pOfqq7FFKI0wggEjBgNV
# HR8EggEaMIIBFjCCARKgggEOoIIBCoaBwWxkYXA6Ly8vQ049UEVJJTIwU3Vib3Jk
# aW5hdGUlMjBDQTIsQ049Qk9JLVNDQTAyLENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0
# Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGRGh0dHA6Ly9CT0ktU0NBMDIucG93
# ZXJlbmcuY29tL0NlcnRFbnJvbGwvUEVJJTIwU3Vib3JkaW5hdGUlMjBDQTIuY3Js
# MIIBNQYIKwYBBQUHAQEEggEnMIIBIzCBtwYIKwYBBQUHMAKGgapsZGFwOi8vL0NO
# PVBFSSUyMFN1Ym9yZGluYXRlJTIwQ0EyLENOPUFJQSxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jQUNlcnRpZmljYXRlP2Jhc2U/b2JqZWN0Q2xhc3M9Y2VydGlm
# aWNhdGlvbkF1dGhvcml0eTBnBggrBgEFBQcwAoZbaHR0cDovL0JPSS1TQ0EwMi5w
# b3dlcmVuZy5jb20vQ2VydEVucm9sbC9CT0ktU0NBMDIucG93ZXJlbmcuY29tX1BF
# SSUyMFN1Ym9yZGluYXRlJTIwQ0EyLmNydDANBgkqhkiG9w0BAQ0FAAOCAQEAcMQQ
# HArQMPorMDdTv0PIeU80NpxlZm6ZjMLHJIWtyKWNRmuG1Oc+Ti762snW05yq5aEY
# kwmmWtm/00ukV4z/DhYrlCuxbmKeQP4kIZoVo4/7K7HrdG0u6QN4SmG9rTJGCuXz
# EXlKZIeHiwgD2EsNa7varVK3jX8CEik1jJh8II0VIbBzvetAMm1QGUCk9/WtllYG
# 76CLyPasgcfFsOlMeRWoHKNw/oV4AvMab0yuQCDJ9uNG3dU+6jGoxDz+ksAKl9OO
# u+zBNs+EOR/TWBD0JfE9hdChCzrbyG6JPIQdOsBoqo822QoIGc8emp4MTeDnCTTh
# ojIQLkYA7bMGDxIxHjGCAgUwggIBAgEBMGQwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyAhNmAAAS2npYfu3c3SZWAAAAABLaMAkGBSsOAwIaBQCgeDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBSI
# tcmrsX+HcBoe3tGzOBfuFqXAqjANBgkqhkiG9w0BAQEFAASCAQBoBHTp2q9SmA4O
# +SZhUUjFgivYOeox5YHIrq5ugNQHc3gF6txHxJWR/j9qMoAeee43OyXS8JvEIW3n
# /9WhXlRtnEcZ8edPe1vk9ByrB9Vk8rXyzufLZMqDfsZqTrN0y2rQGn1gvc97g0F/
# YK5QjUSuMxvvG5WYJKl7jOZlStUThHTxnF2gst8PiQB+/Z4oIHfmMkF/C9PhNac9
# ckIl1ZC/fyVsYVO0m3oD4VTBTBt2i0F/tgkZN+kbXdmyDqof8SsKYYOEmQQmKPO8
# i1cKJ4OQsbsvbJRxJys0lQDuhZSUGPXXkMMVW32FEy1UpqGKHJyIoC5s7s8uvBnf
# Qy2AP2uD
# SIG # End signature block
