# Source in DBConnection...
. "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Utilities\DBConnection.ps1"
[Log]::Init("C:\Users\kbriney-adm\Tmp", "Scratch", 30, 1, [LogLevel]::INFO, $null)

$db = [DBConnection]::new("Server=.\SQLEXPRESS;Database=FoldersAndFiles2;Trusted_Connection=True;")

ConnectTo cdot,prod
$cdotShares = @(Get-NcCifsShare -Controller @($cdot.Values) | Where-Object {
    ($_.VServer -notmatch "DR\-") `
    -and ($_.ShareName -eq "Shares$")
} )

$cdotShares | Select-Object @{N='MyPath'; E = { "{0}:{1}:{2}:{3}:{4}" -f @($_.NcController.Name, $_.Vserver, $_.Volume, $_.Name, $_.Path)}} | Sort-Object MyPath
ConnectTo cdot,prod


function CheckFolder($folderToCheck, $pathsQueue, $foldersQueue, $oFile, $lock)
{
    $di = [System.IO.DirectoryInfo]::new($folderToCheck)
    if($di.Exists)
    {
        try
        {
            $lock.EnterWriteLock()
            $folderToCheck | Out-File -Append -FilePath $oFile
        }
        finally
        {
            if($lock.IsWriteLockHeld)
            {
                $lock.ExitWriteLock()
            }
        }

        $foldersQueue.Enqueue($folderToCheck)
        Write-Host ("Checking folder: {0}" -f @($folderToCheck))
        try
        {
            $Error.Clear()
            $subFoldersToCheck = [System.IO.Directory]::GetDirectories($folderToCheck, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)
            Write-Host ("`tFound {0} sub folders" -f @($subFoldersToCheck.Length))
            $foldersAdded = 0
            $foldersToSkip = 0
            $a = 0
            while($a -lt $subFoldersToCheck.Length)
            {
                if($subFoldersToCheck[$a] -notmatch "~snapshot")
                {
                    $pathsQueue.Enqueue($subFoldersToCheck[$a])
                    $foldersAdded++
                } `
                else
                {
                    $foldersToSkip++
                }
                $a++
            }
            Write-Host ("`tAdd {0} new folders to check.  {1} skipped" -f @($foldersAdded, $foldersToSkip))
            Write-Host ("Paths to check: {0}`r`nFolders to check: {1}" -f @($pathsQueue.Count, $foldersQueue.Count))
        }
        catch
        {
            Write-Host ("ERROR: Failed to get directories for: {0}" -f @($folderToCheck))
            Write-Host $Error
        }
    } `
    else
    {
        Write-Host ("WARNING: {0} does not exist" -f @($folderToCheck))
    }
}



# First get all the share paths to check...
# $pathsToCheck = [System.Collections.Generic.List[System.String]]::new()
$pathsToCheck = [System.Collections.Concurrent.ConcurrentQueue[System.String]]::new()

$a = 0
while($a -lt $cdotShares.Length)
{
    try
    {
        $cifsServer = Get-NcCifsServer -Controller $cdotShares[$a].NcController -VserverContext $cdotShares[$a].VServer -ErrorAction Stop

        try
        {
            $adComp = Get-ADComputer -Identity $cifsServer.CifsServer -Properties servicePrincipalName -ErrorAction Stop
            $haveCIFSAlias = $false
            $b = 0
            while((-not $haveCIFSalias) -and ($null -ne $adComp.servicePrincipalName) -and ($b -lt $adComp.servicePrincipalName.Count))
            {
                $haveCIFSAlias = $adComp.servicePrincipalName[$b] -match "^HOST/([^\.]*)$"
                $b++
            }

            if($haveCIFSAlias)
            {
                $cifsAlias = $Matches[1].ToLower()
                $sharePath = "\\?\UNC\{0}\{1}" -f @($cifsAlias, $cdotShares[$a].ShareName)

                try
                {
                    $di = [System.IO.DirectoryInfo]::new($sharePath)
                    if($di.Exists)
                    {
                        $pathsToCheck.Enqueue($sharePath)
                    }
                }
                catch
                {
                    Write-Host ("ERROR: Failed to retrieve directory information for: {0}" -f @($sharePath))
                }
            } `
            else
            {
                Write-Host ("ERROR: Failed to find CIFS alias (servicePrincipalName) for: {0}" -f @($cifsServer.CifsServer))
            }
        }
        catch
        {
            Write-Host ("ERROR: Failed to get AD computer object for: {0}" -f @($cifsServer.CifsServer))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to get CIFS server for: {0}/{1}" -f @($cdotShares[$a].NcController.Name, $cdotShares[$a].VServer))
    }

    $a++
}

# This will be the complete list of folders to check.
$foldersToCheck = [System.Collections.Concurrent.ConcurrentQueue[System.String]]::new()

$fileLock = [System.Threading.ReaderWriterLockSlim]::new()
$outputFile = "E:\Tmp\folderstocheck.txt"
[Int64] $oldFileCount = 0
[Int64] $oldFileSize = 0
[DateTime] $oldFileDate = [DateTime]::Now.AddYears(-6)


while($pathsToCheck.Count -gt 0)
{
    $maxThreads = 20
    if($pathsToCheck.Count -lt $maxThreads)
    {
        $maxThreads = $pathsToCheck.Count
    }
    @(1..$maxThreads) | Foreach-Object -ThrottleLimit $maxThreads -Parallel {
        $lock = $using:fileLock
        $oFile = $using:outputFile
        $foldersQueue = $using:foldersToCheck
        $pathsQueue = $using:pathsToCheck
        $oFileSize = $using:oldFileSize
        $oFileDate = $using:oldFileDate
        $oFileCount = $using:oldFileCount

        function CheckFolder($folderToCheck, $pathsQueue, $foldersQueue, $oFile, $lock, $oFileSize, $oFileDate, $oFileCount)
        {
            $di = [System.IO.DirectoryInfo]::new($folderToCheck)
            if($di.Exists)
            {
                try
                {
                    $lock.EnterWriteLock()
                    $folderToCheck | Out-File -Append -FilePath $oFile
                }
                finally
                {
                    if($lock.IsWriteLockHeld)
                    {
                        $lock.ExitWriteLock()
                    }
                }

                $foldersQueue.Enqueue($folderToCheck)
                Write-Host ("Checking folder: {0}" -f @($folderToCheck))
                try
                {
                    $Error.Clear()
                    $subFoldersToCheck = [System.IO.Directory]::GetDirectories($folderToCheck, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)
                    Write-Host ("`tFound {0} sub folders" -f @($subFoldersToCheck.Length))
                    $foldersAdded = 0
                    $foldersToSkip = 0
                    $a = 0
                    while($a -lt $subFoldersToCheck.Length)
                    {
                        if($subFoldersToCheck[$a] -notmatch "~snapshot")
                        {
                            $pathsQueue.Enqueue($subFoldersToCheck[$a])
                            $foldersAdded++
                        } `
                        else
                        {
                            $foldersToSkip++
                        }
                        $a++
                    }
                    Write-Host ("`tAdd {0} new folders to check.  {1} skipped" -f @($foldersAdded, $foldersToSkip))
                    Write-Host ("Paths to check: {0}`r`nFolders to check: {1}" -f @($pathsQueue.Count, $foldersQueue.Count))
                }
                catch
                {
                    Write-Host ("ERROR: Failed to get directories for: {0}" -f @($folderToCheck))
                    Write-Host $Error
                }
            } `
            else
            {
                Write-Host ("WARNING: {0} does not exist" -f @($folderToCheck))
            }
        }


        $folderToCheck = ""
        if($pathsQueue.TryDequeue([ref] $folderToCheck))
        {
            CheckFolder $folderToCheck $pathsQueue $foldersQueue $oFile $lock $oFileSize $oFileDate $oFileCount
        }
    }
}




while($pathsToCheck.Count -gt 0)
{
    $folderToCheck = $pathsToCheck[0]
    $pathsToCheck.RemoveAt(0)
    $i = $foldersToCheck.BinarySearch($folderToCheck)
    if($i -lt 0)
    {
        $foldersToCheck.Insert(-bnot $i, $folderToCheck)
    }
    $di = [System.IO.DirectoryInfo]::new($folderToCheck)
    if($di.Exists)
    {
        #if(-not $di.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
        #{
            Write-Host ("Checking folder: {0}" -f @($folderToCheck))
            $subFoldersToCheck = [System.IO.Directory]::GetDirectories($folderToCheck, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)
            Write-Host ("`tFound {0} sub folders" -f @($subFoldersToCheck.Length))
            $foldersAdded = 0
            $foldersToSkip = 0
            $a = 0
            while($a -lt $subFoldersToCheck.Length)
            {
                if($subFoldersToCheck[$a] -notmatch "~snapshot")
                {
                    $i = $pathsToCheck.BinarySearch($subFoldersToCheck[$a])
                    if($i -lt 0)
                    {
                        $pathsToCheck.Insert(-bnot $i, $subFoldersToCheck[$a])
                        $foldersAdded++
                    }
                }
                else
                {
                    $foldersToSkip++
                }
                $a++
            }
            Write-Host ("`tAdd {0} new folders to check.  {1} skipped" -f @($foldersAdded, $foldersToSkip))
            Write-Host ("Paths to check: {0}`r`nFolders to check: {1}" -f @($pathsToCheck.Count, $foldersToCheck.Count))
        #}
        #else
        #{
        #    Write-Host ("INFO: Skipping reparse point: {0}" -f @($folderToCheck))
        #}
    }
    else
    {
        Write-Host ("WARNING: {0} does not exist" -f @($folderToCheck))
    }
}



# Single thread....


# First get all the share paths to check...
$pathsToCheck = [System.Collections.Generic.List[System.String]]::new()

$a = 0
while($a -lt $cdotShares.Length)
{
    try
    {
        $cifsServer = Get-NcCifsServer -Controller $cdotShares[$a].NcController -VserverContext $cdotShares[$a].VServer -ErrorAction Stop

        try
        {
            $adComp = Get-ADComputer -Identity $cifsServer.CifsServer -Properties servicePrincipalName -ErrorAction Stop
            $haveCIFSAlias = $false
            $b = 0
            while((-not $haveCIFSalias) -and ($null -ne $adComp.servicePrincipalName) -and ($b -lt $adComp.servicePrincipalName.Count))
            {
                $haveCIFSAlias = $adComp.servicePrincipalName[$b] -match "^CIFS/([^\.]*)$"
                $b++
            }

            if($haveCIFSAlias)
            {
                $cifsAlias = $Matches[1].ToLower()
                $sharePath = "\\?\UNC\{0}\{1}" -f @($cifsAlias, $cdotShares[$a].ShareName)

                try
                {
                    $di = [System.IO.DirectoryInfo]::new($sharePath)
                    if($di.Exists)
                    {
                        $i = $pathsToCheck.BinarySearch($sharePath)
                        if($i -lt 0)
                        {
                            $pathsToCheck.Insert(-bnot $i, $sharePath)
                        }
                    }
                }
                catch
                {
                    Write-Host ("ERROR: Failed to retrieve directory information for: {0}" -f @($sharePath))
                }
            } `
            else
            {
                Write-Host ("WARNING: Failed to find CIFS alias (servicePrincipalName) for: {0}" -f @($cifsServer.CifsServer))
            }
        }
        catch
        {
            Write-Host ("ERROR: Failed to get AD computer object for: {0}" -f @($cifsServer.CifsServer))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to get CIFS server for: {0}/{1}" -f @($cdotShares[$a].NcController.Name, $cdotShares[$a].VServer))
    }

    $a++
}




# Insert Well known SID...
# $db.ExecuteNonQuery("INSERT INTO Principals (Name, Domain, SamAccountName, SID) VALUES ('Administrators', 'BUILTIN', 'Administrators', 'S-1-5-32-544')")



<#
    Root FileSystemInfo will have Name = [System.IO.DirectoryInfo]::FullName, Extension will be empty even if [System.IO.DirectoryInfo]::Extension has a value

    To create a new "root" FileSystemInfo/DirectoryInfo:
        1. Get System.IO.DirectoryInfo $di for $rootPath
        2. Make sure there is no FileSystemInfo in the database with a matching
        2. Create new row in FileSystemInfo for
#>

function Get-RootDirectoriesFromDB($db)
{
    $dt = $db.GetDataTable("SELECT fsi.ID AS fsiID, fsi.Name AS fsiName, fsi.Extension AS fsiExtension, fsi.CreationTime AS fsiCreationTime, fsi.LastWriteTime AS fsiLastWriteTime, fsi.Attributes AS fsiAttributes, di.ID AS diID, di.FileSystemInfoID AS diFileSystemInfoID, di.ParentDirectoryInfoID AS diParentDirectoryInfoID, di.RootDirectoryInfoID AS diRootDirectoryInfoID FROM FileSystemInfo fsi INNER JOIN DirectoryInfo di ON di.FileSystemInfoID = fsi.ID WHERE (di.ParentDirectoryInfoID IS NULL) AND (di.RootDirectoryInfoID = di.ID)")


}

function Get-DirectoryRootFromDB($db, $rootStr)
{
    $dt = $db.GetDataTable("SELECT di.* FROM DirectoryInfo di INNER JOIN FileSystemInfo fsi ON (di.FileSystemInfoID = fsi.ID) AND (di.ParentDirectoryID IS NULL))")

}





<#
    To check a file/folder:

    1. Get FileInfo or DirectoryInfo
    2. Get ACL
#>

function CheckNextPath($pathsToCheck)
{
    if($pathsToCheck.Count -gt 0)
    {
        $pathToCheck = $pathsToCheck[0]
        $pathsToCheck.RemoveAt(0)

        # First, get all the subfolders of $pathToCheck...
        try
        {
            $di = [System.IO.DirectoryInfo]::new($pathToCheck)
            if($di.Exists)
            {
                try
                {
                    $dSec = $di.GetAccessControl()

                    if($null -ne $dSec)
                    {
                        if(-not [String]::IsNullOrEmpty($dSec.Owner))
                        {
                            $sid = Get-SecurityIdentifierFromString $dSec.Owner

                            if($null -ne $sid)
                            {
                                $i = $principals.Select("SID = '{0}'" -f @($sid.ToString()))
                                if($i.Length -eq 0)
                                {
                                    $userName = $dSec.Owner
                                    if($userName.Contains("\"))
                                    {
                                        $split = $userName.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
                                        $domainName = $split[0]
                                        $userName = $split[1]
                                    }

                                    # No row in Principals for $sid...

                                    $db.ExecuteNonQuery("INSERT INTO Principals (Domain, Name, SamAccountName, SID) VALUES ('{0}', '{1}', '{1}', '{}')")
                                }
                            }
                            else
                            {
                                # Log No SID for $dSec.Owner
                            }
                        }
                    }
                }
                catch
                {
                    # Log Failed to get ACL for $di
                }

            }
            $pathFolders = [System.IO.Directory]::GetDirectories($pathToCheck, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)
            $a = 0
            while($a -lt $pathFolders.Length)
            {

                $a++
            }
        }
        catch
        {
            Write-Host ("ERROR: Unable to check share: {0}." -f @($shareToCheck))
        }
    }
}

# Next, check each path until we check them all...
#   However, when a path is checked, we may, and likely will, add more paths to check to the list...
while($pathsToCheck.Count -gt 0)
{
    CheckNextPath $pathsToCheck
}

<#
    if(($null -ne [DirectoryInfo].Root) -and ([DirectoryInfo].FullName -eq [DirectoryInfo].Root.FullName))
    {
        then [DirectoryInfo] is a root directory.
    }
#>


class DILink
{
    [System.Data.DataRow] $parentDIRow
    [System.Data.DataRow] $rootDIRow
    [System.Data.DataRow] $fsiRow
    [System.IO.DirectoryInfo] $di
}

function CheckDirectory
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [DBConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [System.IO.DirectoryInfo]
        $di
    )


}



function EscapeNonAsciiCharacters($value)
{
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in $value.ToCharArray())
    {
        if ([int]$c -gt 255)
        {
            # This character is too big for ASCII
            $encodedValue = "\\u" + ([int]$c).ToString("x4")
            Write-Host $encodedValue
            [void] $sb.Append($encodedValue);
        } `
        else
        {
            [void] $sb.Append([char] $c)
        }
    }
    return $sb.ToString()
}


$jj = "" | Select-Object @{N='Share';E={$shareName}}, @{N='Directories'; E={$Global:totalDirectories}}, @{N='Files';E={$Global:totalFiles}}, @{N='TotalSize';E={$Global:totalSize}},
    @{N='yr1size';E={$Global:sizeByAge[$Global:fileAgeKeys[9]]}},
    @{N='yr2size';E={$Global:sizeByAge[$Global:fileAgeKeys[8]]}},
    @{N='yr3size';E={$Global:sizeByAge[$Global:fileAgeKeys[7]]}},
    @{N='yr4size';E={$Global:sizeByAge[$Global:fileAgeKeys[6]]}},
    @{N='yr5size';E={$Global:sizeByAge[$Global:fileAgeKeys[5]]}},
    @{N='yr6size';E={$Global:sizeByAge[$Global:fileAgeKeys[4]]}},
    @{N='yr7size';E={$Global:sizeByAge[$Global:fileAgeKeys[3]]}},
    @{N='yr8size';E={$Global:sizeByAge[$Global:fileAgeKeys[2]]}},
    @{N='yr9size';E={$Global:sizeByAge[$Global:fileAgeKeys[1]]}},
    @{N='yr10size';E={$Global:sizeByAge[$Global:fileAgeKeys[0]]}}
$jj | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
