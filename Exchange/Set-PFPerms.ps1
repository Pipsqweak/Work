[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0)]
    [Int32]
    $runID,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $userAccount
)

$host.ui.RawUI.WindowTitle = "Set-PFPerms -runID {0} -userAccount {1}" -f @($runID, $userAccount)
Connect-ExchangeOnline

try
{
    $mailboxes = @(Get-Mailbox -anr $userAccount -ErrorAction Stop)
    if($mailboxes.Length -eq 1)
    {
        $mailbox = $mailboxes[0]
        # $runID = 0    # 0 - 9

        # Load the list of all public folders for this runID...
        $publicFoldersPath = "E:\tmp\PFWork\20250212\PFList_{0:D2}.csv" -f @($runID)
        if([System.IO.File]::Exists($publicFoldersPath))
        {
            $publicFolders = Import-CSV -Delimiter "`t" -Path $publicFoldersPath -ErrorAction Stop

            $publicFolders = @($publicFolders | Sort-Object -Property Identity)

            $successPath = "E:\tmp\PFWork\20250212\Success_{0:D2}.txt" -f @($runID)
            # Load all the public folder identities that have successfully had their permissions updated...
            $successful = [System.Collections.Generic.List[System.String]]::new()
            if([System.IO.File]::Exists($successPath))
            {
                @(Get-Content -Path $successPath).ForEach({
                    $successful.Add($_)
                })
                $successful.Sort()
            }

            $failedPath = "E:\tmp\PFWork\20250212\Failed_{0:D2}.txt" -f @($runID)
            # Load all the public folder identities that failed to have their permissions updated...
            $failed = [System.Collections.Generic.List[System.String]]::new()
            if([System.IO.File]::Exists($failedPath))
            {
                @(Get-Content -Path $failedPath).ForEach({
                    $failed.Add($_)
                })
                $failed.Sort()
            }

            # Update the permissions on all the public folders.
            $a = 0
            while($a -lt $publicFolders.Length)
            {
                Write-Host -NoNewline -ForegroundColor Gray ("{0} ({1}): " -f @($publicFolders[$a].Identity, $publicFolders[$a].EntryId))
                # Have I already successfully set permissions on this folder?
                $i = $successful.BinarySearch($publicFolders[$a].EntryId)
                if($i -lt 0)
                {
                    $addedSuccessfully = $true
                    # Nope... let's try...
                    try
                    {
                        $Error.Clear()
                        Add-PublicFolderClientPermission -User $mailbox.PrimarySmtpAddress -Identity $publicFolders[$a].EntryId -AccessRights Reviewer -ErrorAction Stop | out-Null
                    }
                    catch
                    {
                        # While not exactly successful, the user does already have some permission if the error message contains the following string
                        $addedSuccessfully = ($Error[0].ToString() -match "An existing permission entry was found for user")
                    }

                    if ($addedSuccessfully)
                    {
                        $successful.Insert(-bnot $i, $publicFolders[$a].EntryId)
                        Add-Content -Path $successPath -Value $publicFolders[$a].EntryId
                        Write-Host -NoNewline -ForegroundColor Green "success"
                    } `
                    else # NOT ($addedSuccessfully)
                    {
                        # Updating the permissions failed....track which folders failed.
                        #    Probably don't need to do this, since each time I restart the script, I only skip folders that successfully had permissions updated...
                        Add-Content -Path $failedPath -Value $publicFolders[$a].EntryId
                        $i = $failed.BinarySearch($publicFolders[$a].EntryId)
                        if($i -lt 0)
                        {
                            $failed.Insert(-bnot $i, $publicFolders[$a].EntryId)
                        }
                        Write-Host -NoNewline -ForegroundColor Red "failed"
                    }
                } `
                else
                {
                    Write-Host -NoNewline -ForegroundColor Blue "skipped"
                }
                Write-Host
                $a++
            }
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("Multiple mailboxes ({0}) match {1}." -f @($mailboxes.Length, $userAccount))
        $mailboxes | Foreach-Object {
            Write-Host -ForegroundColor Gray ("`t{0}" -f @($_.DisplayName))
        }
    }
}
catch
{
    Write-Host -ForegroundColor Red ("Failed to retrieve mailbox for: {0}" -f @($userAccount))
}

<#
    Utility code:

    # Build the AllPublicFolders.txt file...
    $allPublicFolders = Get-PublicFolder -Identity "\" -Recurse -ResultSize Unlimited
    $allPublicFolders.ForEach({ Add-Content -Path "C:\Users\kbriney-adm\Documents\PFPerms\AllPublicFolders.txt" -Value $_.Identity })

    # Test to make sure Add-PublicFolderClientPermission throws an exception on failure...
    try
    {
        Add-PublicFolderClientPermission -Identity "\Test" -User "XCVEXBackupAccount16510783371@powereng0.onmicrosoft.com" -AccessRights Owner -ErrorAction Stop
        Write-Host "Success"
    }
    catch
    {
        Write-Host "Failed"
    }


    #
    Get-PublicFolderClientPermission -Identity $publicFolders[$a]
#>
