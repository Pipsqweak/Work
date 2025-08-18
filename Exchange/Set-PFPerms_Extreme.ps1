[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0)]
    [Int32]
    $runID,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $userAccount,

    [Parameter(Mandatory=$true, Position=2)]
    [String[]]
    $accessRights
)


[Flags()] enum ExchangePermission
{
    NoPermission = 0
    CreateItems = 1
    ReadItems = 2
    CreateSubfolders = 4
    FolderOwner = 8
    FolderContact = 16
    FolderVisible = 32
    EditOwnedItems = 64
    EditAllItems = 128
    DeleteOwnedItems = 256
    DeleteAllItems = 512
    AvailabilityOnly = 1024
}

enum ExchangeRole
{
    Special = [ExchangePermission]::NoPermission
    None = [ExchangePermission]::FolderVisible
    Owner = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::CreateSubfolders + [ExchangePermission]::FolderOwner + [ExchangePermission]::FolderContact + [ExchangePermission]::FolderVisible + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::EditAllItems + [ExchangePermission]::DeleteOwnedItems + [ExchangePermission]::DeleteAllItems
    PublishingEditor = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::CreateSubfolders + [ExchangePermission]::FolderVisible + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::EditAllItems + [ExchangePermission]::DeleteOwnedItems + [ExchangePermission]::DeleteAllItems
    Editor = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::FolderVisible + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::EditAllItems + [ExchangePermission]::DeleteOwnedItems + [ExchangePermission]::DeleteAllItems
    PublishingAuthor = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::CreateSubfolders + [ExchangePermission]::FolderVisible + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::DeleteOwnedItems
    Author = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::FolderVisible + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::DeleteOwnedItems
    NonEditingAuthor = [ExchangePermission]::CreateItems + [ExchangePermission]::ReadItems + [ExchangePermission]::FolderVisible + [ExchangePermission]::DeleteOwnedItems
    Reviewer = [ExchangePermission]::ReadItems + [ExchangePermission]::FolderVisible
    Contributor = [ExchangePermission]::CreateItems + [ExchangePermission]::FolderVisible
}


# Create an array of [ExchangePermission] for easy/reuseable enumeration...
$Script:ExchangePermissionArray = [Enum]::GetValues([ExchangePermission])

$Script:validFunctions = [System.Collections.Generic.List[System.String]]::new()
$Script:maxOperationRetries = 3
$Script:actionRetriesWaitSeconds = 5

function LogOutput
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Int32]
        $IndentLevel,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.ConsoleColor]
        $Color,

        [Parameter(Mandatory = $false, Position = 2)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 4)]
        [Switch]
        $NewLine
    )

    if([String]::IsNullOrEmpty($Script:LogFileName))
    {
        $Script:LogFileName = "{0}PFPerms-{1}.log" -f @([System.IO.Path]::GetTempPath(), [DateTime]::Now.ToString("yyyyMMdd-HHmmss"))
        Write-Host ("Log file: {0}" -f @($Script:LogFileName))
    }
    else `
    {
        # Nothing
    }

    if($NewLine)
    {
        $leadingCRLFs = "`r`n"
    } `
    else
    {
        $leadingCRLFs = [String]::Empty
    }

    $Message = $Message.Replace("~SIMULATED~", $Script:simulatedMsg)
    while(-not [String]::IsNullOrEmpty($Message) -and $Message.StartsWith("`r`n"))
    {
        $leadingCRLFs += "`r`n"
        $Message = $Message.Substring(2, $Message.Length - 2)
    }
    $indent = [String]::new(' ', ($IndentLevel * 3))
    if([Console]::CursorLeft -eq 0)
    {
        $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff: ")
    } `
    else
    {
        $ts = [String]::Empty
    }
    $logMsg = "{0}{1}{2}{3}" -f @($leadingCRLFs, $ts, $indent, $Message)
    $logParams = @{
        Path = $Script:LogFileName
        Value = $logMsg
    }

    if($NoNewLine)
    {
        Write-Host -ForegroundColor $Color -NoNewline ("{0}{1}{2}" -f @($leadingCRLFs, $indent, $Message))
        $logParams.Add("NoNewLine", $true)
    } `
    else
    {
        Write-Host -ForegroundColor $Color ("{0}{1}{2}" -f @($leadingCRLFs, $indent, $Message))
    }

    if(-not [String]::IsNullOrEmpty($Script:LogFileName))
    {
        Add-Content @logParams -ErrorAction SilentlyContinue
    } `
    else
    {
        # Nothing
    }
}

function LogInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Green -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogWarning
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Yellow -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function LogError
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Red -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogException
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Red -Message ("Exception: {0}" -f @($Message)) -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function CatchActionException
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false, Position=0)]
        [Int32]
        $tries = 1,

        [Parameter(Mandatory=$false, Position=1)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $IgnoreException = $false
    )

    $good2Go = $true
    if($tries -lt $maxTries)
    {
        if(($tries -eq 1) -and (-not $IgnoreException))
        {
            LogWarning "Operation failed."
            if($maxTries -gt 1)
            {
                LogWarning ("Pausing {0} seconds before retrying (max {1} attempts)" -f @($secondsToPause, $maxTries))
            } `
            else
            {
                # Nothing only show the message if we are going to retry.
            }
        } `
        else
        {
            # Nothing, only want to display a message once.
        }
        Start-Sleep -Seconds $secondsToPause
    } `
    else
    {
        $good2Go = $false

        if(-not $IgnoreException)
        {
            LogError "Operation failed" -NewLine -NoNewLine
            if($tries -gt 1)
            {
                LogError (" after {0} tries." -f @($tries)) -NoNewLine
            } `
            else
            {
                # Nothing
            }
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr)) -NewLine
        } `
        else
        {
            # Nothing, do as we are told...ignore the error.
        }
    }

    return $good2Go
}

function ReTryCatch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $callee,

        [Parameter(Mandatory=$false, Position=1)]
        [HashTable]
        $funcParameters,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch]
        $IgnoreException,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch]
        $Simulated
    )

    if($null -eq $funcParameters)
    {
        $funcParameters = @{
            ErrorAction = [System.Management.Automation.ActionPreference]::Stop
        }
    } `
    else
    {
        # Nothing, we were provided function parameters for $callee
    }

    if(-not $funcParameters.ContainsKey("ErrorAction"))
    {
        $funcParameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop)
    } `
    else
    {
        # Nothing, ErrorAction already specified.
    }

    # Capture vital information in $result which is returned to the caller.
    $result = "" | Select-Object ActionComplete, Good2Go, ReturnValue, Tries, Error
    $result.Good2Go = $true              # .Good2Go does NOT imply the result of & $callee was successful, just that & $callee did not throw an exception or the call was simulated.  It's up to the caller to check .ReturnValue
    $result.ReturnValue = $null          # ALWAYS an array of the results of calling $callee
    $result.ActionComplete = $false      # Did $callee complete without an exception?
    $result.Error = $null                # $Error[0].ErrorRecord if the call failed
    $result.Tries = 0                    # How many times was $callee called?


    $idx = $Script:validFunctions.BinarySearch($callee)
    $calleeIsValid = ($idx -ge 0)

    $Error.Clear()
    if(-not $calleeIsValid)
    {
        try
        {
            $calleeIsValid = ($null -ne (Get-Command -Name $callee -ErrorAction Stop)) -or ($null -ne (Get-Item -Path ("Function:\{0}" -f @($callee)) -ErrorAction Stop))
            if($calleeIsValid)
            {
                $Script:validFunctions.Insert(-bnot $idx, $callee)
            } `
            else
            {
                # Nothing, no need to record an invalid callee.
            }
        }
        catch
        {
            # Nothing, a message will be displayed later
        }
    } `
    else
    {
        # Nothing....
    }

    if($calleeIsValid)
    {
        do
        {
            $result.Tries++
            $Error.Clear()

            if(-not $Simulated.IsPresent)
            {
                try
                {
                    # To ensure consistency, I'll always return an array...
                    $result.ReturnValue = @(& $callee @funcParameters)
                    $result.ActionComplete = $true
                }
                catch
                {
                    $result.Error = $Error[0]
                    $result.Good2Go = CatchActionException -tries $result.Tries -maxTries $maxTries -secondsToPause $secondsToPause -IgnoreException:$IgnoreException.IsPresent
                }
            } `
            else
            {
                # Nothing, just simulating...
            }
        } while((-not $Simulated.IsPresent) -and $result.Good2Go -and (-not $result.ActionComplete) -and ($result.Tries -lt $maxTries))
    } `
    else
    {
        LogError ("No cmdlet or function named {0} found." -f @($callee))
        $result.Good2Go = $false
    }

    return $result
}

function GetPublicFolderUserPermissions
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object]
        $pfClientPermissionsForUser
    )

    $userPermissions = $null

    if($null -ne $pfClientPermissionsForUser)
    {
        if($null -ne $pfClientPermissionsForUser.AccessRights)
        {
            # Role/permissions currently assigned to the user
            $currentRole = [ExchangeRole]::Special

            $b = 0
            while($b -lt $pfClientPermissionsForUser.AccessRights.Count)
            {
                # Most of the time, .AccessRights will be a single [ExchangeRole], so...
                #    first, try to translate .AccessRights[$b] into an [ExchangeRole]
                #    This avoids most of the exceptions which would happen if I tried to
                #    translate .AccessRights[$b] into an [ExchangePermission] first (i.e. increased performance)...
                try
                {
                    $currentRole = [ExchangeRole] $pfClientPermissionsForUser.AccessRights[$b]
                }
                catch
                {
                    # Translation to [ExchangeRole] failed...
                    #   Now try to translate .AccessRights[$b] into an [ExchangePermission]...
                    try
                    {
                        $perm = [ExchangePermission] $pfClientPermissionsForUser.AccessRights[$b]

                        # Add the permission to $currentRole...
                        [ExchangePermission] $currentRole += $perm
                    }
                    catch
                    {
                        LogException ("Failed to translate access right [{0}] for user [{1}] on public folder [{2} ({3})]" -f @($pfClientPermissionsForUser.AccessRights[$b], $pfClientPermissionsForUser.User, $pfClientPermissionsForUser.FolderName, $pfClientPermissionsForUser.Identity) )
                    }
                }
                $b++
            }

            # Convert [ExchangeRole] to an [ExchangePermission]
            try
            {
                $userPermissions = [ExchangePermission] $currentRole
            }
            catch
            {
                $userPermissions = $null
                LogError ("Failed to convert current role to user permissions in GetPublicFolderUserPermissions for user [{0}] on public folder [{1} ({2})], Access Rights: {3}" -f @($pfClientPermissionsForUser.User, $pfClientPermissionsForUser.FolderName, $pfClientPermissionsForUser.Identity, $pfClientPermissionsForUser.AccessRights.ToString()))
            }
        } `
        else
        {
            LogError ("Access rights missing for user [{0}] on public folder [{1} ({2})]" -f @($pfClientPermissionsForUser.User, $pfClientPermissionsForUser.FolderName, $pfClientPermissionsForUser.Identity) )
        }
    } `
    else
    {
        LogException "Null client permissions sent to GetPublicFolderUserPermissions."
    }

    return $userPermissions
}

function GetExchangePermissionsFromStringArray
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String[]]
        $accessRights
    )

    $success = $true
    $perms = [ExchangePermission]::NoPermission

    $b = 0
    while($b -lt $accessRights.Length)
    {
        try
        {
            $role = [ExchangeRole] $accessRights[$b]
            $perms = $perms -bor [ExchangePermission] $role
        }
        catch
        {
            # Translation to [ExchangeRole] failed...
            #   Now try to translate accessRights[$b] into an [ExchangePermission]...
            try
            {
                $perm = [ExchangePermission] $accessRights[$b]

                # Add the permission to $currentRole...
                $perms = $perms -bor $perm
            }
            catch
            {
                LogException ("Failed to translate access right [{0}] for user [{1}] on public folder [{2} ({3})]" -f @($pfClientPermissionsForUser.AccessRights[$b], $pfClientPermissionsForUser.User, $pfClientPermissionsForUser.FolderName, $pfClientPermissionsForUser.Identity) )
                $success = $false
            }
        }
        $b++
    }

    # Shorten the permissions to a role if possible.
    try
    {
        $role = [ExchangeRole] $perms
        $perms = $role
    }
    catch
    {
        # Nothing, just trapping the exception
    }

    return @($success, $perms)
}

$success, $exchangeAccessRights = GetExchangePermissionsFromStringArray -accessRights $accessRights

if ($success)
{
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
            $publicFolders = $null
            if([System.IO.File]::Exists($publicFoldersPath))
            {
                try
                {
                    $publicFolders = @(Import-CSV -Path $publicFoldersPath -Delimiter "`t" -ErrorAction Stop)
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Exception importing CSV: {0}" -f @($publicFoldersPath))
                }

                if ($null -ne $publicFolders)
                {
                    try
                    {
                        $publicFoldersSorted = $publicFolders | Sort-Object -Property Identity -ErrorAction Stop
                        $publicFolders = $publicFoldersSorted
                    }
                    catch
                    {
                        # Nothing, just trapping the sort exception.
                    }

                    # Load all the public folder identities that have successfully had their permissions updated...
                    $successPath = "E:\tmp\PFWork\20250212\Success_{0}.txt" -f @($runID)
                    $successful = [System.Collections.Generic.List[System.String]]::new()
                    if([System.IO.File]::Exists($successPath))
                    {
                        @(Get-Content -Path $successPath).ForEach({
                            $successful.Add($_)
                        })
                        $successful.Sort()
                    }

                    # Load all the public folder identities that failed to have their permissions updated...
                    $failedPath = "E:\tmp\PFWork\20250212\Failed_{0}.txt" -f @($runID)
                    $failed = [System.Collections.Generic.List[System.String]]::new()
                    if([System.IO.File]::Exists($failedPath))
                    {
                        @(Get-Content -Path $failedPath).ForEach({
                            $failed.Add($_)
                        })
                        $failed.Sort()
                    }

                    # Update the permissions on all the public folders in the list
                    $a = 0
                    while($a -lt $publicFolders.Length)
                    {

                        $onlinePF = $null
                        try
                        {
                            $onlinePF = Get-PublicFolder -Identity $publicFolders[$a].EntryId
                        }
                        catch
                        {
                            LogError ("Exception retrieving public folder: {0} ({1})" -f @($publicFolders[$a].Identity, $publicFolders[$a].EntryId))
                        }

                        if ($null -ne $onlinePF)
                        {
                            $existingClientPermissions = $null
                            try
                            {
                                $existingClientPermissions = Get-PublicFolderClientPermission -Identity $onlinePF.EntryId -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to retrieve client permissions for {0} ({1})" -f @($onlinePF.Identity, $onlinePF.EntryId))
                            }

                            if ($null -ne $existingClientPermissions)
                            {
                                $userPermissions = @($existingClientPermissions | Where-Object { $_.User.RecipientPrincipal.Guid -eq $mailbox.Guid })
                                if ($userPermissions.Length -gt 0)
                                {
                                    $permissionsRemovedSuccessfully = $true
                                    $b = 0
                                    while($permissionsRemovedSuccessfully -and ($b -lt $userPermissions.Length))
                                    {
                                        $currentRole = GetPublicFolderUserPermissions -pfClientPermissionsForUser $userPermissions[$b]

                                        LogInfo ("Removing client permissions {0} for user: {1} on {2} ({3})" -f @($currentRole, $userPermissions[$b].User.DisplayName, $onlinePF.Identity, $onlinePF.EntryId))
                                        $result = ReTryCatch -callee "Remove-PublicFolderClientPermission" -funcParameters @{Identity = $onlinePF.EntryId; User = $userPermissions[$b].User; Confirm = $false } -Simulated:$Simulated

                                        if($result.Good2Go)
                                        {
                                        } `
                                        else
                                        {
                                            $permissionsRemovedSuccessfully = $false
                                        }
                                        $b++
                                    }
                                } `
                                else # NOT ($userPermissions.Length -gt 0)
                                {
                                    # Nothing.
                                }

                                if ($userPermissions.Length -eq 0)
                                {
                                    $result = ReTryCatch -callee "Add-PublicFolderClientPermission" -funcParameters @{Identity = $onlinePF.EntryId; User = $mailbox.PrimarySmtpAddress; AccessRights = $newRoleArray } -Simulated:$Simulated
                                    if($result.Good2Go)
                                    { }
                                    try
                                    {
                                        Add-PublicFolderClientPermission -User $mailbox.PrimarySmtpAddress -Identity $onlinePF.EntryId -AccessRights $accessRightsStr -ErrorAction Stop | out-Null
                                    }
                                    catch
                                    {

                                    }
                                } `
                                else # NOT ($userPermissions.Length -eq 0)
                                {
                                    # Nothing.
                                }
                            } `
                            else # NOT ($null -ne $existingClientPermissions)
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else # NOT ($null -ne $onlinePF)
                        {
                            # Nothing.
                        }

                        Write-Host -NoNewline -ForegroundColor Gray ("{0} ({1}): " -f @($publicFolders[$a].Identity, $publicFolders[$a].EntryId))

                        # Have I already successfully set permissions on this folder?
                        $i = $successful.BinarySearch($publicFolders[$a].EntryId)
                        if($i -lt 0)
                        {
                            # Nope... let's try...
                            try
                            {
                                Add-PublicFolderClientPermission -User $mailbox.PrimarySmtpAddress -Identity $publicFolders[$a].EntryId -AccessRights $accessRightsStr -ErrorAction Stop | out-Null

                                # If no exception is thrown, then I assume the permissions were updated successfully.
                                $successful.Insert(-bnot $i, $publicFolders[$a].EntryId)
                                Add-Content -Path $successPath -Value $publicFolders[$a]
                                Write-Host -NoNewline -ForegroundColor Green "success"
                            }
                            catch
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
                        }
                        else
                        {
                            Write-Host -NoNewline -ForegroundColor Blue "skipped"
                        }
                        Write-Host
                        $a++
                    }
                } `
                else # NOT ($null -ne $publicFolders)
                {
                    # Nothing.
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
} `
else # NOT ($success)
{
    Write-Host -ForegroundColor Red ("Unable to parse access rights: {0}" -f @($accessRights -join ", "))
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
