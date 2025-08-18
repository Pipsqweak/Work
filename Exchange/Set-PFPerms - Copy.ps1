[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateRange(0,9)]
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
        $publicFoldersPath = "C:\Users\kbriney-adm\Documents\PFPerms\All-PFIdentities-{0}.txt" -f @($runID)
        $publicFolders = [System.Collections.Generic.List[System.String]]::new()
        if([System.IO.File]::Exists($publicFoldersPath))
        {
            @(Get-Content -Path $publicFoldersPath).ForEach({
                $publicFolders.Add($_)
            })
            $publicFolders.Sort()

            $successPath = "C:\Users\kbriney-adm\Documents\PFPerms\Success_{0}.txt" -f @($runID)
            # Load all the public folder identities that have successfully had their permissions updated...
            $successful = [System.Collections.Generic.List[System.String]]::new()
            if([System.IO.File]::Exists($successPath))
            {
                @(Get-Content -Path $successPath).ForEach({
                    $successful.Add($_)
                })
                $successful.Sort()
            }

            $failedPath = "C:\Users\kbriney-adm\Documents\PFPerms\Failed_{0}.txt" -f @($runID)
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
            while($a -lt $publicFolders.Count)
            {
                Write-Host -NoNewline -ForegroundColor Gray ("{0}: " -f @($publicFolders[$a]))
                # Have I already successfully set permissions on this folder?
                $i = $successful.BinarySearch($publicFolders[$a])
                if($i -lt 0)
                {
                    # Nope... let's try...
                    try
                    {
                        Add-PublicFolderClientPermission -User $mailbox.PrimarySmtpAddress -Identity $publicFolders[$a] -AccessRights Owner -ErrorAction Stop | out-Null

                        # If no exception is thrown, then I assume the permissions were updated successfully.
                        $successful.Insert(-bnot $i, $publicFolders[$a])
                        Add-Content -Path $successPath -Value $publicFolders[$a]
                        Write-Host -NoNewline -ForegroundColor Green "success"
                    }
                    catch
                    {
                        # Updating the permissions failed....track which folders failed.
                        #    Probably don't need to do this, since each time I restart the script, I only skip folders that successfully had permissions updated...
                        Add-Content -Path $failedPath -Value $publicFolders[$a]
                        $i = $failed.BinarySearch($publicFolders[$a])
                        if($i -lt 0)
                        {
                            $failed.Insert(-bnot $i, $publicFolders[$a])
                        }
                        Write-Host -NoNewline -ForegroundColor Red "failed"
                    }
                }
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