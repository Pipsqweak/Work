\\cdcfs1\Reference\PerfTest\SpeedTest.ps1 -configFileName \\cdcfs1\Reference\PerfTest\config.json -Riverbed -LimitLargeFiles -Description "Riverbed Cold"
\\cdcfs1\Reference\PerfTest\SpeedTest.ps1 -configFileName \\cdcfs1\Reference\PerfTest\config.json -Riverbed -LimitLargeFiles -Description "Riverbed Optimized"


$riverBedResults = [System.Collections.Generic.List[Object]]::new()
$resultsFiles = Get-ChildItem -Path "\\cdcfs1\Reference\PerfTest\Results\Riverbed\*.csv"

$a = 0
while($a -lt $resultsFiles.Length)
{
    $contents = Get-Content -Path $resultsFiles[$a].FullName
    $b = 0
    while($b -lt $contents.Length)
    {
        while($contents[$b].Contains("`""))
        {
            $contents[$b] = $contents[$b].Replace("`"","")
        }
        $b++
    }

    $results = $contents | ConvertFrom-Csv -Delimiter "`t"
    $results | Foreach-Object {
        $riverBedResults.Add($_)
    }
    $a++
}

$riverBedResults | Sort-Object DCName,TestHost,ServerName,DateTime | Export-CSV -Path "\\cdcfs1\Reference\PerfTest\Results\RiverbedTests.csv" -Delimiter "`t" -NoTypeInformation -Force -Confirm:$false

$riverBedResults | Sort-Object DCName,TestHost,ServerName,DateTime |
    Select-Object `
        DCName,
        TestHost,
        ServerName,
        DateTime,
        Description,
        Latency,
        SmallFileBytesRead,
        @{N='SmallFileRead'; E={ Format-StorageNumber $_.SmallFileBytesRead }},
        SmallFileReadTime,
        @{N='SmallFileReadTime2'; E={ [Timespan]::new(0,0,0,0,$_.SmallFileReadTime).ToString("mm\:ss\.fff") }},
        SmallFileMBPS,
        MediumFileBytesRead,
        @{N='MediumFileRead'; E={ Format-StorageNumber $_.MediumFileBytesRead }},
        MediumFileReadTime,
        @{N='MediumFileReadTime2'; E={ [Timespan]::new(0,0,0,0,$_.MediumFileReadTime).ToString("mm\:ss\.fff") }},
        MediumFileMBPS,
        LargeFileBytesRead,
        @{N='LargeFileRead'; E={ Format-StorageNumber $_.LargeFileBytesRead }},
        LargeFileReadTime,
        @{N='LargeFileReadTime2'; E={ [Timespan]::new(0,0,0,0,$_.LargeFileReadTime).ToString("mm\:ss\.fff") }},
        LargeFileMBPS | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard


function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KiB","MiB","GiB","TiB","PiB","EiB","ZiB","YiB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}
