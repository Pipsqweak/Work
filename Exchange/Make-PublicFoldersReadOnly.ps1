[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String]
    $pfListFileName,

    [Parameter(Mandatory=$false,Position=1)]
    [Switch]
    $Simulated
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

[ExchangePermission] $Script:permissionsToRemove = [ExchangePermission]::CreateItems + [ExchangePermission]::CreateSubfolders + [ExchangePermission]::EditOwnedItems + [ExchangePermission]::EditAllItems

$Script:IgnoredPublicFolderUsers = @(
    "CVEXBackupAccount1651078337", "SRVC-PWRPubFldrBitTitan"
)

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

<#
    ProcessPublicFolder

    Parameters:
        $pFolder - Import record from public folder list.  Not an actual public folder object from calling Get-PublicFolder.
                    To avoid the extra time required to call Get-PublicFolder over and over, I just use the data available from
                    the import file.

        $Simulated - Self-explanatory
#>
function ProcessPublicFolder
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object]
        $pFolder,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch]
        $Simulated
    )

    if($null -ne $pFolder)
    {
        # Get the existing permissions on the folder...
        LogInfo ("Getting client permissions for folder: [{0} (1)]" -f @($pFolder.Identity, $pFolder.EntryId))
        $result = ReTryCatch -callee "Get-PublicFolderClientPermission" -funcParameters @{Identity = $pFolder.EntryId} -Simulated:$Simulated

        if($result.Good2Go)
        {
            $pfClientPermissions = @($result.ReturnValue)

            if($null -ne $pfClientPermissions)
            {
                $a = 0
                while($a -lt $pfClientPermissions.Length)
                {
                    if(-not $Script:IgnoredPublicFolderUsers.Contains($pfClientPermissions[$a].User.DisplayName))
                    {
                        # Role/permissions currently assigned to the user
                        $currentRole = GetPublicFolderUserPermissions -pfClientPermissionsForUser $pfClientPermissions[$a]

                        if($null -ne $currentRole)
                        {
                            # Role/permissions we need to change .AccessRights to.
                            #    Remove permissions required to make changes to public folder.
                            $newRole = $currentRole -band (-bnot $Script:permissionsToRemove)

                            # If the new role is different than the current role, we need to update client permissions...
                            if($currentRole -ne $newRole)
                            {
                                # First remove $pfClientPermissions[$a].User's current permission...
                                LogInfo ("Removing client permissions {0} for user: {1} on {2} ({3})" -f @(($currentRole -band $Script:permissionsToRemove), $pfClientPermissions[$a].User.DisplayName, $pFolder.Identity, $pFolder.EntryId))
                                $result = ReTryCatch -callee "Remove-PublicFolderClientPermission" -funcParameters @{Identity = $pFolder.EntryId; User = $pfClientPermissions[$a].User; Confirm = $false } -Simulated:$Simulated

                                if($result.Good2Go)
                                {
                                    # Convert the [ExchangePermission] to a [String[]] so I can pass it to Add-PublicFolderClientPermission
                                    $newRoleArray = $newRole.ToString() -split ", "

                                    LogInfo ("Adding client permissions: {0} for user: {1} on {2} ({3})" -f @(($newRoleArray -join ", "), $pfClientPermissions[$a].User.DisplayName, $pFolder.Identity, $pFolder.EntryId))

                                    # Now, add the new permissions to the folder...
                                    #     Add-PublicFolderClientPermission returns an array of changed users...
                                    $result = ReTryCatch -callee "Add-PublicFolderClientPermission" -funcParameters @{Identity = $pFolder.EntryId; User = $pfClientPermissions[$a].User; AccessRights = $newRoleArray } -Simulated:$Simulated
                                    if($result.Good2Go)
                                    {
                                        # In the event I am simulating the actions, make sure the verification passes.
                                        #   I might change this so I get some failures too.
                                        $newRole2 = $newRole

                                        if($Simulated.IsPresent)
                                        {
                                            # Nothing, already faked $newRole2...
                                        } `
                                        else
                                        {
                                            # Had to go all the way to .User.RecipientPrincipal.Guid to get a good comparison (other attributes might have worked, but I settled on .Guid)
                                            $changedPermissions = $result.ReturnValue | Where-Object { $_.User.RecipientPrincipal.Guid -eq $pfClientPermissions[$a].User.RecipientPrincipal.Guid }
                                            if($null -ne $changedPermissions)
                                            {
                                                $newRole2 = GetPublicFolderUserPermissions -pfClientPermissionsForUser $changedPermissions
                                            } `
                                            else
                                            {
                                                LogError ("Failed to verify changed permissions for user [{0}] on public folder [{1} ({2})] (ERR2)" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId))
                                            }
                                        }

                                        if($null -ne $newRole2)
                                        {
                                            if($newRole -eq $newRole2)
                                            {
                                                LogInfo ("Successfully changed permissions for user [{0}] on public folder [{1} ({2})] to {3}" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId, $newRole2.ToString()))
                                            } `
                                            else
                                            {
                                                LogError ("Failed to change permissions for user [{0}] on public folder [{1} ({2})]" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId))
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Failed to verify changed permissions for user [{0}] on public folder [{1} ({2})]" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId))
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("Failed to add client permission(s) [{3}] for user [{0}] on public folder [{1} ({2})]" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId, $newRole.ToString()))
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to remove client permission for user [{0}] on public folder [{1} ({2})]" -f @($pfClientPermissions[$a].User, $pFolder.Identity, $pFolder.EntryId) )
                                }
                            } `
                            else
                            {
                                # Nothing, no change in roles...
                            }
                        } `
                        else
                        {
                            LogError ("Failed to get permissions for user [{0}] on public folder [{1} ({2})], Access Rights: {3}" -f @($pfClientPermissions[$a].User.DisplayName, $pFolder.Identity, $pFolder.EntryId, ($pfClientPermissions[$a].AccessRights -join ", ")))
                        }
                    } `
                    else
                    {
                        # Nothing, skipping the ignored users...
                    }
                    $a++
                }
            } `
            else
            {
                LogError "Null client permissions retrieved for folder: {0} ({1})" -f @($pFolder.Identity. $pFolder.EntryId)
            }
        } `
        else
        {
            LogError "Failed to retrieve client permissions for folder: {0} ({1})" -f @($pFolder.Identity. $pFolder.EntryId)
        }
    } `
    else
    {
        LogError "Null public folder sent to ProcessPublicFolder."
    }
}

<#
        Main Processing...
#>

$connected = $false
try
{
    Connect-ExchangeOnline -ErrorAction Stop
    $connected = $true
}
catch
{
    Write-Host -ForegroundColor Red "Failed to connect to Exchange Online."
}

if($connected)
{
    try
    {
        $publicFolderList = @(Import-CSV -Delimiter "`t" -Path $pfListFileName -ErrorAction Stop)
        if(($null -ne $publicFolderList) -and ($publicFolderList.Length -ge 0))
        {
            $mbmrs = Get-Member -InputObject $publicFolderList[0]
            if(@($mbmrs | Where-Object { $_.Name -eq "EntryId"}).Length -eq 1)
            {
                if(@($mbmrs | Where-Object { $_.Name -eq "Identity"}).Length -eq 1)
                {
                    if($publicFolderList[0].EntryId -is [String])
                    {
                        if($publicFolderList[0].Identity -is [String])
                        {
                            $a = 0
                            while($a -lt $publicFolderList.Length)
                            {
                                ProcessPublicFolder -pFolder $publicFolderList[$a] -Simulated
                                $a++
                            }
                        } `
                        else
                        {
                            LogError ("'Identity' column does not appear to be a string.")
                        }
                    } `
                    else
                    {
                        LogError ("'EntryId' column does not appear to be a string.")
                    }
                } `
                else
                {
                    LogError ("Import data missing 'Identity' column.")
                }
            } `
            else
            {
                LogError ("Import data missing 'EntryId' column.")
            }
        } `
        else
        {
            LogWarning ("No data imported from {0}." -f @($pfListFileName))
        }
    }
    catch
    {
        LogError ("Unable to import public folder list from {0}." -f @($pfListFileName))
    }
} `
else
{
    # Nothing... already displayed an error.
}


# $pf = Get-PublicFolder -Identity "000000009598E9A20E04F041B38518182890A2D5010012225CC57BF01F4EA8CCA87A792FF35F000019E2697C0000"
# ProcessPublicFolder -pFolder $pf -Simulated:$true
