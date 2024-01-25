$speedTestArgs = @{
    configFileName = "\\cdcfs1\Reference\PerfTest\config.json"
    Description = "Standard Presidio Test"
    TrackOverallElapsed = $true
}

& \\cdcfs1\Reference\PerfTest\Speedtest.ps1 @speedTestArgs
