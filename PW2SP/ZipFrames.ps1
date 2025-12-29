function ShowProgress
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="Complete", ValueFromPipeline=$false, Position=0)]
        [Int32] $progressID,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=1)]
        [String] $activity,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=2)]
        [Int32] $counter,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=3)]
        [Int32] $counterMax,

        [Parameter(Mandatory=$false, ParameterSetName="Running", ValueFromPipeline=$false, Position=4)]
        [String] $statusSuffix = [String]::Empty,

        [Parameter(Mandatory=$false, ParameterSetName="Complete", ValueFromPipeline=$false, Position=1)]
        [Switch] $complete
    )

    if(-not $complete.IsPresent)
    {
        $pc = [float] ($counter + 1) / [float] $counterMax
        if($pc -gt 1)
        {
            $pc = [Float] 0.99
        }
        $counterMaxStrLen = $counterMax.ToString("N0").Length
        $activityStr = ("{0} {{0,{1}:N0}} of {{1,{1}:N0}}" -f ($activity, $counterMaxStrLen)) -f @(($counter + 1), $counterMax)
        $statusStr = "{0,7:P} Complete" -f @($pc)
        if(-not [String]::IsNullOrEmpty($statusSuffix))
        {
            $statusStr = @($statusStr, $statusSuffix) -join " | "
        }
        Write-Progress -Id $progressID -Activity $activityStr -Status $statusStr -PercentComplete ($pc * 100)
    } `
    else
    {
        Write-Progress -Id $progressID -Completed
    }
}

function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KB","MB","GB","TB","PB","EB","ZB","YB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}


$framesFiles = @(Get-ChildItem -Path "E:\tmp\157562\Frames" -File -Recurse)
$zipArchiveFMT = "Video2.2Frames{0,3:D3}.zip"
$sb = [System.Text.StringBuilder]::new()


$a = 0
$z = 0
$zipArchive = $zipArchiveFMT -f @($z)
while($a -lt $framesFiles.Length)
{
    $relPath = $framesFiles[$a].FullName.Replace("E:\tmp\157562\","")

    $null = 7z a $zipArchive $relPath
    $zipFI = [System.IO.FileInfo]::new(("E:\tmp\157562\{0}" -f @($zipArchive)))
    if($zipFI.Length -gt 249MB)
    {
        $z++
        $zipArchive = $zipArchiveFMT -f @($z)
    }

    [void] $sb.AppendLine(("{0}, {1}" -f @($zipArchive, $relPath)))
    ShowProgress -progressID 1 -activity "Adding file" -counter $a -counterMax $framesFiles.Length -statusSuffix ("{0} ({1}) | {2} ({3})" -f @($relPath, (Format-StorageNumber $framesFiles[$a].Length), $zipArchive, (Format-StorageNumber $zipFI.Length)))
    $a++
}
Set-Content -Path "E:\tmp\157562\FileList.txt" -Value @($sb.ToString())
ShowProgress -progressID 1 -complete



$framesObjects = @($pwData.ProjectWiseObjects.Values).Where({ $_.FullPath.StartsWith("Archive Projects\157562\BOI Vis\Video\Video2.2\Frames\") })
$framesObjects.ForEach({ $null = $pwData.ProjectWiseObjects.Remove($_.DocumentGUID) })
