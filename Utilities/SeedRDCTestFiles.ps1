$off2RDCMetrics = Get-Content .\RDC\Metrics\config.json | ConvertFrom-Json

function TestWithRetry
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [System.Management.Automation.ScriptBlock]
        $testScript,

        [Parameter(Mandatory=$true,Position=1)]
        [int]
        $maxRetries,

        [Parameter(Mandatory=$true, Position=2, ValueFromRemainingArguments)]
        $testScriptParams
    )

    $testPassed = $false
    $c = 0
    do
    {
        if($c -gt 0)
        {
            Write-Host -NoNewline -ForegroundColor Yellow ("`r`n`tRetry #{0}..." -f @($c))
        }
        try
        {
            $testPassed = & $testScript $testScriptParams
        }
        catch { }
        $c++
    } until($testPassed -or ($c -ge $maxRetries))

    return $testPassed
}

$testForServerScriptBlock =  { Param($serverName) Test-Connection -ComputerName $serverName -Quiet -ErrorAction Stop }
$testForPathScriptBlock = { Param($pathToTest) Test-Path -Path $pathToTest -ErrorAction Stop }

$testFiles = @(Get-ChildItem -Path C:\Temp\RDCTestFiles -Filter "*.bin" | Sort-Object -Property Length)

$a = 0
$foldersChecked = [System.Collections.Generic.List[String]]::new()
while($a -lt $off2RDCMetrics.Offices.Length)
{
    $destinationShare = "\\{0}\{1}" -f @($off2RDCMetrics.Offices[$a].LocalStorage.ServerName, $off2RDCMetrics.Offices[$a].LocalStorage.ShareName)
    $destinationFolder = "{0}\RDCTestFiles" -f @($destinationShare)

    $i = $foldersChecked.BinarySearch($destinationFolder)
    if($i -lt 0)
    {
        $foldersChecked.Insert(-bnot $i, $destinationFolder)
        Write-Host -NoNewline ("Testing for server: {0}..." -f @($off2RDCMetrics.Offices[$a].LocalStorage.ServerName))

        if((TestWithRetry -testScript $testForServerScriptBlock -maxRetries 3 $off2RDCMetrics.Offices[$a].LocalStorage.ServerName))
        {
            Write-Host -ForegroundColor Green "good"
            Write-Host -NoNewline ("Testing for share: {0}..." -f @($destinationShare))
            if((TestWithRetry -testScript $testForPathScriptBlock -maxRetries 3 $destinationShare))
            {
                Write-Host -ForegroundColor Green "good"
                Write-Host -NoNewline ("Testing for {0}..." -f @($destinationFolder))

                try
                {
                    if(-not (TestWithRetry -testScript $testForPathScriptBlock -maxRetries 3 $destinationFolder))
                    {
                        Write-Host -ForegroundColor Yellow "creating"
                        [System.IO.Directory]::CreateDirectory($destinationFolder) | Out-Null
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Green "good"
                    }

                    # Remove the older test files...
                    Get-Childitem -Path $destinationFolder | Where-Object { -not ($_.Name.StartsWith("small") -or $_.Name.StartsWith("medium") -or $_.Name.StartsWith("large")) } | Remove-Item -Force -Confirm:$false

                    $b = 0
                    while($b -lt $testFiles.Length)
                    {
                        $destinationFileName = "{0}\{1}" -f @($destinationFolder, $testFiles[$b].Name)
                        #Write-Host ("Processing {0}..." -f @($testFiles[$b].Name))
                        #Write-Host -NoNewline ("`tTesting for {0} with length {1}..." -f @($destinationFileName, $testFiles[$b].Length))

                        $doFileCopy = $false
                        try
                        {
                            $f = Get-ChildItem -Path $destinationFileName -ErrorAction Stop
                            if($f.Length -ne $testFiles[$b].Length)
                            {
                                #Write-Host -NoNewline -ForegroundColor Yellow "exists, wrong size, deleting..."
                                try
                                {
                                    [System.IO.File]::Delete($destinationFileName)
                                    #Write-Host -ForegroundColor Green "success"
                                    $doFileCopy = $true
                                }
                                catch
                                {
                                    #Write-Host -ForegroundColor Red "failed, skipping"
                                }
                            } `
                            else
                            {
                                # Nothing, file is good, do not replace.
                                #Write-Host -ForegroundColor Green "exists, same size, skipping"
                            }
                        }
                        catch
                        {
                            #Write-Host -ForegroundColor Green "does not exist, copying"
                            # File does not exist, need to copy...
                            $doFileCopy = $true
                        }

                        if($doFileCopy)
                        {
                            Write-Host -NoNewline ("`tCopying {0} to {1}..." -f @($testFiles[$b].Name, $destinationFileName))
                            $success = $false
                            $c = 0
                            $copyTime = (Measure-Command -Expression {
                                do
                                {
                                    if($c -gt 0)
                                    {
                                        Write-Host -NoNewline -ForegroundColor Yellow ("`r`n`t`tRetry #{0}..." -f @($c))
                                    }
                                    try
                                    {
                                        [System.IO.File]::Copy($testFiles[$b].FullName, $destinationFileName)
                                        $success = $true
                                    }
                                    catch { }

                                    $c++
                                } until($success -or ($c -ge 3))
                            })

                            if($success)
                            {
                                $mbps = (($testFiles[$b].Length / $copyTime.TotalMilliseconds) * 1000) / 1MB
                                Write-Host -ForegroundColor Green ("success - {0} copy time ({1:N2}MB/s)." -f @($copyTime.ToString(), $mbps))
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Red "failed"
                            }
                        }
                        else
                        {
                            # Nothing, skipped copying a good file
                        }

                        $b++
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red "`r`nUncaught error occurred."
                    throw
                }
            } `
            else
            {
                Write-Host -ForegroundColor Red "unable to verify"
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red "does not respond"
        }
    }
    $a++
}

function CreateTestFiles()
{
    $v = @(0..255)

    $numFilesPerSize = 20
    $prefixes = @("small", "medium", "large")
    $fileSizeStart = @(16KB, 4MB, 128MB)
    $fileSizeIncrements = @(0, 0, 0)
    $buffer = [byte[]]::new(4096)

    $a = 0
    while($a -lt $fileSizeStart.Length)
    {
        $size = [int] ($fileSizeStart[$a] * 1.15)
        $b = 0
        $bytesWritten = 0
        while($b -lt $numFilesPerSize)
        {
            $fn = "C:\temp\RDCTestFiles\{0}-testfile-{1:D2}.bin" -f @($prefixes[$a], ($b + 1))
            $stream = $null
            try
            {
                $stream = [System.IO.File]::Open($fn, [System.IO.FileMode]::Create)
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to create {0} ({1})." -f @($fn, $size))
            }

            if($null -ne $stream)
            {
                $fWriter = $null
                try
                {
                    $fWriter = [System.IO.BinaryWriter]::new($stream)
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to create binary stream writer for {0}." -f @($fn))
                }

                if($null -ne $fWriter)
                {
                    Write-Host -NoNewline ("Creating {0}, size {1}..." -f @($fn, $size))
                    $bytesWritten = 0
                    $bufferFillCount = 0
                    do
                    {
                        $bPos = 0
                        $sequenceCount = 0
                        do
                        {
                            $nxtCount = $size - ($bytesWritten + $bPos)
                            if($nxtCount -gt $v.Length)
                            {
                                $nxtCount = $v.Length
                            }

                            if(($nxtCount + $bPos) -gt $buffer.Length)
                            {
                                $nxtCount = $buffer.Length - $bPos
                            }

                            $nxtSequence = $v | Get-Random -Count $nxtCount
                            $sequenceCount++

                            # Write-Host ("Sequence count: {0}, length: {1}" -f @($sequenceCount, $nxtSequence.Length))
                            $c = 0
                            while(($c -lt $nxtSequence.Length) -and ($bPos -lt $buffer.Length))
                            {
                                $buffer[$bPos] = $nxtSequence[$c]
                                $bPos++
                                $c++
                            }
                        } until (($bPos -ge 4096) -or (($bytesWritten + $bPos) -eq $size))

                        $bufferFillCount++
                        try
                        {
                            # Write-Host ("Buffer fill count: {0}, size {1}." -f @($bufferFillCount, $bPos))
                            $fWriter.Write($buffer, 0, $bPos)
                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red ("Failed to write buffer {0} to {1}." -f @($bufferFillCount, $fn))
                            $fWriter.Close()
                            $fWriter = $null
                        }
                        $bytesWritten += $bPos

                    } until($bytesWritten -ge $size)

                    if($null -ne $fWriter)
                    {
                        $fWriter.Close()
                    }

                    Write-Host ("`t{0} blocks" -f @($bufferFillCount))
                }
                $stream.Close()
            }


            # Write-Host ("{0} - {1} - {2} - {3}" -f @($a, $b, $size, $bytesWritten))
            $size += $fileSizeIncrements[$a]
            $b++
        }
        $a++
    }
}
