
function DownloadGoogleDriveFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $url,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $outFileName
    )

    $downloadSuccessful = $false
    Remove-Item -Path $outFileName -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    try
    {
        Invoke-WebRequest -Uri $url -OutFile $outFileName -ErrorAction Stop
        $downloadSuccessful = [System.IO.File]::Exists($outFileName)
    }
    catch { }

    return $downloadSuccessful
}

function TestGoogleDrive
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Object[]] $fileIDs,

        [Parameter(Mandatory=$true)]
        [ValidateSet("small","medium","large")]
        [String] $fileSize,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $TrackOverallElapsed
    )

    $sw = [System.Diagnostics.Stopwatch]::new()
    $baseURL = "https://drive.google.com/uc?export=download&id="
    $tempFileName = [System.IO.Path]::GetTempFileName()
    # If the file to be downloaded is a large file, Google will require confirmation before downloading the file, so I have to extract the confirmation URL out of the downloaded file.
    $requiresConfirmation = $fileSize -eq "large"
    $results = [System.Collections.Generic.List[Object]]::new()

    # Suppress progress bar...
    $ProgressPreference = "SilentlyContinue"
    $a = 0
    while(((-not $TrackOverallElapsed) -or ($Script:overAllSW.Elapsed.TotalMinutes -lt $Script:MaximumRuntime)) -and ($a -lt $fileIDs.Length))
    {
        $sw.Reset()
        $url = "{0}{1}" -f @($baseURL, $fileIDs[$a])
        Write-Host $url

        if(-not $requiresConfirmation)
        {
            $sw.Start()
        }

        $downloadSuccessful = DownloadGoogleDriveFile -url $url -outFileName $tempFileName

        # No matter if we started the stopwatch or not, stop it here...
        $sw.Stop()

        if($downloadSuccessful)
        {
            if($requiresConfirmation)
            {
                $content = [String]::Empty
                try
                {
                    $content = Get-Content -ReadCount 64kb -Path $tempFileName -ErrorAction Stop
                }
                catch
                {
                    Write-Host -ForegroundColor Red "Failed to read content of downloaded virus confirmation file from Google drive for file ID: [{0}]" -f @($fileIDs[$a])
                }

                if(-not [String]::IsNullOrEmpty($content))
                {
                    if($content[0] -match "<\s*form[^>]*\s+action=([`"'])(.*?)\1")
                    {
                        if($Matches.Count -gt 2)
                        {
                            $url = $Matches[2]
                            $url = $url.Replace("&amp;","&")
                            $sw.Start()
                            $downloadSuccessful = DownloadGoogleDriveFile -url $url -outFileName $tempFileName
                            $sw.Stop()
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Red ("Failed to extract confirmation URL for file ID: [{0}]." -f @($fileIDs[$a]))
                        }
                    }
                }
            }
        }

        if($downloadSuccessful)
        {
            $fcMetric = "" | Select-Object BytesRead,ReadTimeMS,MBPS
            $fcMetric.BytesRead = (Get-ChildItem -Path $tempFileName -ErrorAction SilentlyContinue).Length
            $fcMetric.ReadTimeMS = $sw.Elapsed.TotalMilliseconds
            $fcMetric.MBPS = (($fcMetric.BytesRead / $fcMetric.ReadTimeMS) * 1000) / 1MB
            $ts = [TimeSpan]::new(0,0,0,0,$fcMetric.ReadTimeMS).ToString().TrimEnd("0")
            Write-Host -ForegroundColor Green ("`tRead time: {0:N2}ms ({1}) @ {2:N2}MB/s" -f @($fcMetric.ReadTimeMS, $ts, $fcMetric.MBPS))
            $results.Add($fcMetric)
        }

        $a++
    }
    # Restore progress bar...
    $ProgressPreference = "Continue"

    return $results
}

function TestInternetConnection
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [Object]
        $googleDriveFileIDs
    )

    $alive, $tr = TestLatency "www.google.com" -count 25

    if($alive -and ($null -ne $tr))
    {
        $avgMS = ($tr | Measure-Object -Average -Property ResponseTime).Average
        Write-Host -ForegroundColor Green ("`t{0}ms" -f @($avgMS))

        $testResults = "" | Select-Object DCName, DateTime, ServerName, ShareName, Latency, FileCopy, FileTestSummary
        $testResults.FileTestSummary = "" | Select-Object Small,Medium,Large

        $testResults.DCName = "Google"
        $testResults.ShareName = "N/A"
        $testResults.ServerName = "Drive"
        $testResults.DateTime = [DateTime]::now.ToString("yyyyMMdd-HHmm")
        $testResults.Latency = $tr

        TestGoogleDrive -fileIDs $googleDriveFileIDs.small -fileSize small | ForEach-Object { $testResults.FileCopy += $_ }
    }
}
