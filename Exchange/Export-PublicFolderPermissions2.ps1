[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String]
    $pfListExportFolder,   # This is the folder Make-PublicFolderProcessLists.ps1 exported public folder to.

    [Parameter(Mandatory=$true, Position=1)]
    [String]
    $pfPermsWorkFolder,    # This is the working folder for the script.  Saved information will be placed here.

    [Parameter(Mandatory=$false,Position=2)]
    [Switch]
    $Simulated
)
<#

    This script will typically timeout before it can complete.  As a result, progress is tracked via a file containing the public folder EntryIDs which we failed to export permissions for.
    Each time the script is ran, it reads in all the public folder identity information from a folder where Make-PublicFolderProcessLists.ps1 saved it to.
    Next, the failed list is read.  $pfPermsWorkFolder\Failed.txt
    Next, the permissions which have so far been exported are read.  $pfPermsWorkFolder\PFPermissions.CSV
    From the permissions data, a list of public folder which have already had their permissions exported is created.

#>
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

$ProgressPreference = "Continue"

# These are the public folders we were unable to export permissions for.
$Script:failedToCheckPublicFolderEntryIDs = [System.Collections.Generic.List[System.String]]::new()

# Dictionary of exported public folder permissions ... so far
$Script:publicFolderAccessRights = [System.Collections.Generic.SortedDictionary[System.String, [System.Collections.Generic.List[System.Object]]]]::new()

# List to contain EntryIDs for new public folder permissions added to $Script:publicFolderAccessRights since the data was last saved.
$Script:newPublicFolderPermissionEntryIDs = [System.Collections.Generic.List[System.String]]::new()
$Script:publicFolderPermissionFile = "{0}\PFPermissions.CSV" -f @($pfPermsWorkFolder)
$Script:failedToCheckPublicFoldersFile = "{0}\Failed.TXT" -f @($pfPermsWorkFolder)

function AddFailedPublicFolderEntryID
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $entryID
    )

    $idx = $Script:failedToCheckPublicFolderEntryIDs.BinarySearch($entryID)
    if($idx -lt 0)
    {
        $Script:failedToCheckPublicFolderEntryIDs.Insert(-bnot $idx, $entryID)
    } `
    else
    {
        # Nothing, only need to record .EntryID once.
    }
}

function AddNewPublicFolderPermission
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Object]
        $permObject,

        [Parameter(Mandatory=$false, Position=1)]
        [Switch]
        $PreExisting
    )

    if(-not $Script:publicFolderAccessRights.ContainsKey($permObject.EntryID))
    {
        $newPermList = [System.Collections.Generic.List[System.Object]]::new()
        $Script:publicFolderAccessRights.Add($permObject.EntryID, $newPermList)

        if(-not $PreExisting.IsPresent)
        {
            $idx = $Script:newPublicFolderPermissionEntryIDs.BinarySearch($permObject.EntryID)
            if($idx -lt 0)
            {
                $Script:newPublicFolderPermissionEntryIDs.Insert(-bnot $idx, $permObject.EntryID)
            } `
            else
            {
                # Nothing.
            }
        } `
        else
        {
            # Nothing, pre-existing items are not new...
        }
    } `
    else
    {
        # Nothing, don't need to add another dictionary entry...
    }

    $Script:publicFolderAccessRights[$permObject.EntryID].Add($permObject)
}

function SavePublicFolderPermissionsData
{
    try
    {
        $Script:failedToCheckPublicFolderEntryIDs | Set-Content -Path $Script:failedToCheckPublicFoldersFile -Force -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Yellow ("Warning failed to save entry IDs for public folders I was unable to get permissions for to: {0}" -f @($Script:failedToCheckPublicFoldersFile))
    }

    # To be able to remove saved entryIDs from the list, we'll have to reverse enumerate it, or we'll mess up the order of things.
    $b = $Script:newPublicFolderPermissionEntryIDs.Count - 1
    while($b -ge 0)
    {
        $entryID = $Script:newPublicFolderPermissionEntryIDs[$b]
        try
        {
            # Remove the next entryID to save from the list of new permission entryIDs...
            $Script:newPublicFolderPermissionEntryIDs.RemoveAt($b)

            # If we removed entryID successfully, proceed to save it's permissions to the file...
            try
            {
                $Script:publicFolderAccessRights[$entryID] | Export-CSV -Append -Delimiter "`t" -NoTypeInformation -Path $Script:publicFolderPermissionFile -Force -ErrorAction Stop
            }
            catch
            {
                Write-Host -ForegroundColor Yellow ("Failed to export permissions for public folder: {0}/{1}" -f @($Script:publicFolderAccessRights[$entryID].EntryID, $Script:publicFolderAccessRights[$entryID].Identity))

                # If we failed to save entryID's permissions to the file, then put the entryID back in the list of new entry permissions so we can try again.
                $Script:newPublicFolderPermissionEntryIDs.Insert($b, $entryID)
            }
        }
        catch
        {
            Write-Host -ForegroundColor Yellow ("Failed to remove {0} from the list of new permissions." -f @($entryID))
        }

        # Remember, we are reverse enumerating the list...
        $b--
    }
}

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
    if([System.IO.Directory]::Exists($pfListExportFolder))
    {
        if([System.IO.Directory]::Exists($pfPermsWorkFolder))
        {
            <#

                First read in all the exported public folders from the folder where Make-PublicFolderProcessLists.ps1 saved them and merge them into a single array.


                *** TODO: REPLACE THIS WITH ACTUAL PUBLIC FOLDER INFORMATION FROM EXCHANGE ONLINE.  ***
                    $publicFolders = @(Get-PublicFolder -Identity "\" -Recurse -ResultSize "Unlimited" | Sort-Object -Property EntryID)
            #>
            $pfListFiles = @()
            $publicFolders = [System.Collections.Generic.List[Object]]::new()
            try
            {
                $pfListFiles = @(Get-ChildItem -Path $pfListExportFolder -ErrorAction Stop)
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to get public folder export files from: {0}" -f @($pfListExportFolder))
            }

            $good2Go = $true
            $a = 0
            while($good2Go -and ($a -lt $pfListFiles.Length))
            {
                $pfListData = @()
                try
                {
                    $pfListData = Import-CSV -Path $pfListFiles[$a].FullName -Delimiter "`t" -ErrorAction Stop
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to read contents of: {0}" -f @($pfListFiles[$a].FullName))
                    $good2Go = $false
                }

                $b = 0
                while($good2Go -and ($b -lt $pfListData.Length))
                {
                    $publicFolders.Add($pfListData[$b])
                    $b++
                }

                $a++
            }

            if($good2Go)
            {
                if([System.IO.File]::Exists($Script:failedToCheckPublicFoldersFile))
                {
                    try
                    {
                        $failedData = @(Get-Content -path $Script:failedToCheckPublicFoldersFile -ErrorAction Stop)
                        $failedData.ForEach({
                            AddFailedPublicFolderEntryID -entryID $_
                        })
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Yellow ("Warning, unable to read contents of: {0}" -f @($Script:failedToCheckPublicFoldersFile))
                        Write-Host -ForegroundColor Yellow "Consider deleting."
                        # Don't set $good2Go to false ... we'll rebuild the list when we check for permissions...
                    }
                } `
                else
                {
                    # Nothing, nothing to read...
                }
            } `
            else
            {
                # Nothing, already displayed an error
            }
            <#

                Read the list of public folder EntryIDs we failed to get permissions for.

            #>
            if($good2Go)
            {
                # TODO: Remove the following line once the script is ready
                $publicFolders = $publicFolders | Sort-Object EntryID

                if([System.IO.File]::Exists($publicFolderPermissionFile))
                {
                    try
                    {
                        $importedPermissions = Import-CSV -Path $publicFolderPermissionFile -Delimiter "`t" -ErrorAction Stop
                        $importedPermissions.Foreach({ AddNewPublicFolderPermission -permObject $_ -PreExisting })
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("Failed to read public folder permissions file: {0}" -f @($publicFolderPermissionFile))
                        $good2Go = $false
                    }
                } `
                else
                {
                    # Nothing, just haven't exported any permissions yet...
                }

                if($good2Go)
                {
                    $a = 0
                    while($a -lt $publicFolders.Length)
                    {
                        # Progress bar stuff...
                        $percentComplete = ($a / $publicFolders.Length)
                        $status = "{1,7:P2} Complete | {0}" -f @($publicFolders[$a].Identity, $percentComplete)
                        Write-Progress -Activity "Exporting Public Folder Permissions" -Status $status -PercentComplete ($percentComplete * 100.0)

                        # If we've already exported permissions for $publicFolders[$a], then skip it.
                        if(-not $Script:publicFolderAccessRights.ContainsKey($publicFolders[$a].EntryId))
                        {
                            # Reset these to null so they don't have old values if an exception occurs
                            $pfOnline = $null
                            $publicFolderClientPermissions = $null

                            try
                            {
                                $pfOnline = Get-PublicFolder -Identity $publicFolders[$a].EntryId -ErrorAction Stop
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Yellow ("Failed to get online public folder: {0}/{1}" -f @($publicFolders[$a].EntryId, $publicFolders[$a].Identity))
                                AddFailedPublicFolderEntryID -entryID $publicFolders[$a].EntryId
                            }

                            if($null -ne $pfOnline)
                            {
                                try
                                {
                                    $publicFolderClientPermissions = Get-PublicFolderClientPermission -Identity $publicFolders[$a].EntryID -ErrorAction Stop
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Yellow ("Failed to get permissions on public folder: {0}/{1}" -f @($publicFolders[$a].EntryId, $publicFolders[$a].Identity))
                                    AddFailedPublicFolderEntryID -entryID $publicFolders[$a].EntryId
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error
                            }

                            if($null -ne $publicFolderClientPermissions)
                            {
                                $b = 0
                                while($b -lt $publicFolderClientPermissions.Length)
                                {
                                    $d = "" | Select-Object EntryID, PublicFolder,User,Role,CreateItems,ReadItems,CreateSubfolders,FolderOwner,FolderContact,FolderVisible,EditOwnedItems,EditAllItems,DeleteOwnedItems,DeleteAllItems,AvailabilityOnly
                                    $d.EntryID = $pfOnline.EntryID
                                    $d.PublicFolder = $pfOnline.Identity
                                    $d.User = $publicFolderClientPermissions[$b].User.ToString()
                                    $d.Role = [ExchangeRole]::Special.ToString()

                                    $c = 0
                                    while($c -lt $publicFolderClientPermissions[$b].AccessRights.Count)
                                    {
                                        try
                                        {
                                            $role = [ExchangeRole] $publicFolderClientPermissions[$b].AccessRights[$c]
                                            $d.Role = $role.ToString()

                                            [ExchangePermission].GetEnumNames() | Foreach-Object {
                                                $v = [ExchangePermission]::$_
                                                if($role -band $v)
                                                {
                                                    $d.$($_) = (($role -band $v) -ne 0)
                                                }
                                            }
                                        }
                                        catch
                                        {
                                            try
                                            {
                                                $permission = [ExchangePermission] $publicFolderClientPermissions[$b].AccessRights[$c]
                                                $d.$($permission) = $true
                                            }
                                            catch
                                            {
                                                $problemPublicFolderAccessRights.Add($d)
                                                Write-Host ("`r`nA: {0}, B:{1}, C:{2}" -f @($a, $b, $c))
                                            }
                                        }

                                        $c++
                                    }

                                    AddNewPublicFolderPermission $d

                                    $b++
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        } `
                        else
                        {
                            # Nothing, skip the public folders we've already checked.
                        }

                        if($Script:newPublicFolderPermissionEntryIDs.Count -gt 10)
                        {
                            SavePublicFolderPermissionsData
                        } `
                        else
                        {
                            # Nothing, only export the data after adding 10+ new permissions.
                        }
                        $a++
                    }

                    # If there are any unsaved permissions, save them...
                    SavePublicFolderPermissionsData
                } `
                else
                {
                    # Nothing, already displayed an error.
                }
            } `
            else
            {
                # Nothing already displayed an error
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red ("Work folder: {0} does not exist." -f @($pfPermsWorkFolder))
        }
    } `
    else
    {
        Write-Host -ForegroundColor Red ("Export folder: {0} does not exist." -f @($pfListExportFolder))
    }
} `
else
{
    # Nothing, already displayed an error.
}
