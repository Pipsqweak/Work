function CreateTestFile
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $fileName,

        [Parameter(Mandatory=$false,Position=1)]
        [int]
        $fileSize = 1MB,

        [Parameter(Mandatory=$false,Position=2)]
        [int]
        $bufferSize = 4KB
    )

    $sw = [System.Diagnostics.Stopwatch]::new()
    $v = @(0..255)

    $buffer = [byte[]]::new($bufferSize)

    $bytesWritten = 0
    $stream = $null
    try
    {
        $stream = [System.IO.File]::Open($fileName, [System.IO.FileMode]::Create)
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to create {0} ({1})." -f @($fileName, $fileSize))
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
            Write-Host -ForegroundColor Red ("Failed to create binary stream writer for {0}." -f @($fileName))
        }

        if($null -ne $fWriter)
        {
            $bytesWritten = 0
            $bufferFillCount = 0
            do
            {
                $bPos = 0
                $sequenceCount = 0
                do
                {
                    $nxtCount = $fileSize - ($bytesWritten + $bPos)
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
                } until (($bPos -ge $buffer.Length) -or (($bytesWritten + $bPos) -eq $fileSize))

                $bufferFillCount++
                try
                {
                    # Write-Host ("Buffer fill count: {0}, size {1}." -f @($bufferFillCount, $bPos))
                    $sw.Start()
                    $fWriter.Write($buffer, 0, $bPos)
                    $sw.Stop()
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to write buffer {0} to {1}." -f @($bufferFillCount, $fileName))
                    $fWriter.Close()
                    $fWriter = $null
                }
                $bytesWritten += $bPos

            } until($bytesWritten -ge $fileSize)

            if($null -ne $fWriter)
            {
                $fWriter.Close()
            }

            # Write-Host ("`t{0} blocks" -f @($bufferFillCount))
            # Write-Host ("Elapsed: {0}ms" -f @($sw.ElapsedMilliseconds))
        }
        $stream.Close()
    }

    return @(, $sw)
}

function RunRDCTest
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $fileServer,

        [Parameter(Mandatory=$false,Position=1)]
        [int]
        $fileCount = 25,

        [Parameter(Mandatory=$false,Position=2)]
        [int]
        $fileSize = 1MB,

        [Parameter(Mandatory=$false,Position=3)]
        [int]
        $bufferSize = 4KB
    )

    $d = "" | Select-Object FileServer, ReadAverage, ReadThroughput, WriteAverage, WriteThroughput
    $d.FileServer = $fileServer

    Write-Host "Running file write test..."
    $createStats = [System.Collections.Generic.List[Int64]]::new()
    $cumulativeFileWriteSize = 0

    $a = 0
    while($a -lt $fileCount)
    {

        $testFileName = "\\{0}\Xchange\RDCTestFiles\testFile{1}.bin" -f @($fileServer, $a)
        Write-Host -NoNewline ("Creating {0}, file size: {1}, buffer size: {2} ... " -f @($testFileName, $fileSize, $bufferSize))
        $sw = CreateTestFile -fileName $testFileName -fileSize $fileSize -bufferSize $bufferSize
        $cumulativeFileWriteSize += $fileSize
        Remove-Item -Path $testFileName -Confirm:$false -Force
        $createStats.Add($sw.ElapsedMilliseconds)
        Write-Host ("{0}ms" -f @($sw.ElapsedMilliseconds))

        $a++
    }

    $totalWriteMilliseconds = ($createStats | Measure-Object -Sum).Sum

    $d.WriteThroughput = ($cumulativeFileWriteSize / $totalWriteMilliseconds) * 0.001

    $createStats.Sort()
    $createStats.RemoveAt(0)
    $createStats.RemoveAt($createStats.Count-1)

    $d.WriteAverage = ($createStats | Measure-Object -Average).Average

    Write-Host ("{0} average file write time was: {1:N}ms @ {2:N} MBps" -f @($fileServer.ToUpper(), $d.WriteAverage, $d.WriteThroughput))

    Write-Host ("Running file read test...")


    $sw = [System.Diagnostics.Stopwatch]::new()
    $readStats = [System.Collections.Generic.List[Int64]]::new()
    $cumulativeFileReadSize = 0
    $a = 1
    while($a -lt 20)
    {
        $sw.Reset()
        $testFileName = "\\{0}\Xchange\RDCTestFiles\medium-testfile-{1:D2}.bin" -f @($fileServer, $a)
        Write-Host -NoNewline ("Reading: {0}..." -f @($testFileName))

        $sw.Start()
        $junk = Get-Content -Path $testFileName -Raw
        $sw.Stop()
        $cumulativeFileReadSize += $junk.Length

        $readStats.Add($sw.ElapsedMilliseconds)
        Write-Host ("{0}ms" -f @($sw.ElapsedMilliseconds))

        $a++
    }

    $totalReadMilliseconds = ($readStats | Measure-Object -Sum).Sum

    $readStats.Sort()
    $readStats.RemoveAt(0)
    $readStats.RemoveAt($readStats.Count-1)

    $d.ReadThroughput = ($cumulativeFileReadSize / $totalReadMilliseconds) * 0.001

    $d.ReadAverage = ($readStats | Measure-Object -Average).Average

    Write-Host ("{0} average file read time was: {1:N}ms @{2:N}MBps" -f @($fileServer.ToUpper(), $d.ReadAverage, $d.ReadThroughput))

    return @( ,$d)
}

function RunAllRDCTests()
{
    $allStats = [System.Collections.Generic.List[Object]]::new()
    $fileServers = @("at4fs1","cdcfs1","ch3fs1","da11fs1","ddcfs1","las04fs1","ny7fs1","se4fs1","yyc01")
    $a = 0
    while($a -lt $fileServers.Length)
    {
        $d = RunRDCTest -fileServer $fileServers[$a] -fileCount 25 -fileSize 1048576 -bufferSize 4096
        $allStats.Add($d)

        $a++
    }

    return @(,$allStats)
}

$rdcTestStats = RunAllRDCTests
