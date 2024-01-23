function ConvertTo-UNCPath
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [String] $ffPath
    )

    $retval = $ffPath
    if(-not [String]::IsNullOrEmpty($retval))
    {
        if($retval -notmatch "^\\\\\?\\unc\\")
        {
            $retval = $retval.TrimStart(@('\'))
            $retval = "\\?\UNC\{0}" -f @($retval)
        }
    }

    return $retval
}

$sharePath = "\\?\UNC\ch3fs1\Shares$"


# Queue for folders yet to be scanned...
$queueFolders = [System.Collections.Generic.Queue[System.String]]::new()

# Sorted list of folders found...
$listFolders = [System.Collections.Generic.List[System.String]]::new()
$listFailedToScan = [System.Collections.Generic.List[System.String]]::new()

$queueFolders.Enqueue($sharePath)
$queued = 1

$pass = 0

while($queueFolders.Count -gt 0)
{
    $pass++
    $nxtPath = $queueFolders.Dequeue()
    if(-not [String]::IsNullOrEmpty($nxtPath))
    {
        try
        {
            # $folders = @(Get-ChildItem -LiteralPath $nxtPath -Directory -ErrorAction Stop)
            $folders = [System.IO.Directory]::EnumerateDirectories($nxtPath)

            $folders | ForEach-Object {
                $queueFolders.Enqueue($_)
                $queued++
            }

            $i = $listFolders.BinarySearch($nxtPath)
            if($i -lt 0)
            {
                $listFolders.Insert(-bnot $i, $nxtPath)
            }
        }
        catch
        {
            $i = $listFailedToScan.BinarySearch($nxtPath)
            if($i -lt 0)
            {
                $listFailedToScan.Insert(-bnot $i, $nxtPath)
            }
        }
    }
    Write-Host ("Pass: {3}, Queued: {0}, In queue: {1}, Collected: {2}" -f @($queued, $queueFolders.Count, $listFolders.Count, $pass))
}

$ownerFound = $false
$a = 0
while(($a -lt $listFolders.Count) -and (-not $ownerFound))
{
    $scanPath = $listFolders[$a]
    try
    {
        $folderACL = Get-Acl -LiteralPath $scanPath -ErrorAction Stop
        $ownerFound = (-not [String]::IsNullOrEmpty($folderACL.Owner)) -and ($folderACL.Owner -ne "BUILTIN\Administrators")
        if(-not $ownerFound)
        {
            try
            {
                # Get the list of files in the folder...
                $files = @(Get-ChildItem -LiteralPath $scanPath -Attributes !Directory+!System+!ReparsePoint+!SparseFile)
                $b = 0
                while(($b -lt $files.Length) -and (-not $ownerFound))
                {
                    try
                    {
                        $fileACL = Get-ACL -LiteralPath $files[$b].FullName -ErrorAction Stop
                        $ownerFound = (-not [String]::IsNullOrEmpty($fileACL.Owner)) -and ($fileACL.Owner -ne "BUILTIN\Administrators")
                        if($ownerFound)
                        {
                            Write-Host ("Owner found:`r`n`tFile: {0}`r`n`tOwner: {1}" -f @($files[$b].FullName, $fileACL.Owner))
                        }
                    }
                    catch
                    {
                        Write-Host ("ERROR: Failed to get ACLs for: {0}" -f @($files[$b].FullName))
                    }

                    if(-not $ownerFound)
                    {
                        $b++
                    }
                }
            }
            catch
            {
                Write-Host ("ERROR: Failed to get files from: {0}." -f @($scanPath))
            }
        }
        else
        {
            Write-Host ("Owner found:`r`n`tFolder: {0}`r`n`tOwner: {1}" -f @($scanPath, $folderACL.Owner))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to get ACL for folder: {0}" -f @($scanPath))
    }

    if(-not $ownerFound)
    {
        $a++
    }
}


function ScanFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [String] $scanPath
    )

    try
    {
        # See if there are any explicit ACLs on the folder...
        $folderACL = Get-ACL -LiteralPath $scanPath -ErrorAction Stop
        $explicitRules = $folderACL.Access | Where-Object { -not $_.Isinherited }

        try
        {
            # Get the list of files in the folder...
            $files = @(Get-ChildItem -LiteralPath $scanPath -Attributes !Directory+!System+!ReparsePoint+!SparseFile)

            $fileACL = Get-ACL -LiteralPath $files[0].FullName -ErrorAction Stop

        }
        catch
        {
            Write-Host ("ERROR: Failed to get files from: {0}." -f @($scanPath))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to get ACLs for: {0}" -f @($scanPath))
    }
}

<#
    GENERIC_ALL: 268435456
    GENERIC_EXECUTE: 536870912
    GENERIC_WRITE: 1073741824
    GENERIC_READ: 2147483648
#>
