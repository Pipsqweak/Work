enum ExchangePermissions
{
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

enum ExchangeRoles
{
    None = [ExchangePermissions]::FolderVisible
    Owner = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::CreateSubfolders -bor [ExchangePermissions]::FolderOwner -bor [ExchangePermissions]::FolderContact -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::EditOwnedItems -bor [ExchangePermissions]::EditAllItems -bor [ExchangePermissions]::DeleteOwnedItems -bor [ExchangePermissions]::DeleteAllItems
    PublishingEditor = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::CreateSubfolders -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::EditOwnedItems -bor [ExchangePermissions]::EditAllItems -bor [ExchangePermissions]::DeleteOwnedItems -bor [ExchangePermissions]::DeleteAllItems
    Editor = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::EditOwnedItems -bor [ExchangePermissions]::EditAllItems -bor [ExchangePermissions]::DeleteOwnedItems -bor [ExchangePermissions]::DeleteAllItems
    PublishingAuthor = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::CreateSubfolders -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::EditOwnedItems -bor [ExchangePermissions]::DeleteOwnedItems
    Author = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::EditOwnedItems -bor [ExchangePermissions]::DeleteOwnedItems
    NonEditingAuthor = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::FolderVisible -bor [ExchangePermissions]::DeleteOwnedItems
    Reviewer = [ExchangePermissions]::ReadItems -bor [ExchangePermissions]::FolderVisible
    Contributor = [ExchangePermissions]::CreateItems -bor [ExchangePermissions]::FolderVisible
    Special
}



Connect-ExchangeOnline
$checkedPublicFolders = [System.Collections.Generic.List[System.String]]::new()
@(Get-Content -Path "C:\Users\kbriney-adm\Documents\PFChecked.txt").ForEach({ $checkedPublicFolders.Add($_) })
$checkedPublicFolders.Sort()


$publicFolderAccessRights = [System.Collections.Generic.List[System.Object]]::new()
$problemPublicFolderAccessRights = [System.Collections.Generic.List[System.Object]]::new()
# $publicFolders = Get-PublicFolder -Identity "\" -Recurse -ResultSize "Unlimited" 
# $publicFoldersSorted = $publicFolders | Sort-Object -Property Identity
$a = 0
while($a -lt $publicFoldersSorted.Length)
{
    $idx = $checkedPublicFolders.BinarySearch($publicFoldersSorted[$a].Identity)
    if($idx -lt 0)
    {
        $checkedPublicFolders.Insert(-bnot $idx, $publicFoldersSorted[$a].Identity)
        $publicFolderClientPermissions = Get-PublicFolderClientPermission -Identity $publicFoldersSorted[$a].Identity
        $b = 0
        while($b -lt $publicFolderClientPermissions.Length)
        {
            $c = 0
            while($c -lt $publicFolderClientPermissions[$b].AccessRights.Count)
            {
                $d = "" | Select-Object PublicFolder,User,AccessRight,CreateItems,ReadItems,CreateSubfolders,FolderOwner,FolderContact,FolderVisible,EditOwnedItems,EditAllItems,DeleteOwnedItems,DeleteAllItems
                $d.PublicFolder = $publicFolderClientPermissions[$b].Identity
                $d.User = $publicFolderClientPermissions[$b].User.ToString()
                $d.AccessRight = $publicFolderClientPermissions[$b].AccessRights[$c].ToString()

                try
                {
                    $role = [ExchangeRoles] $publicFolderClientPermissions[$b].AccessRights[$c]

                    [ExchangePermissions].GetEnumNames() | Foreach-Object {
                        $v = [ExchangePermissions]::$_
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
                        $permission = [ExchangePermissions] $publicFolderClientPermissions[$b].AccessRights[$c]
                        $d.$($permission) = $true
                    }
                    catch
                    {
                        $problemPublicFolderAccessRights.Add($d)
                        Write-Host ("`r`nA: {0}, B:{1}, C:{2}" -f @($a, $b, $c))
                    }
                }

                $publicFolderAccessRights.Add($d)

                $c++
            }
            $b++
        }

        if(($a % 10) -eq 0)
        {
            $publicFolderAccessRights | Export-CSV -Delimiter "`t" -NoTypeInformation -Path "C:\Users\kbriney-adm\Documents\PFPermissions.CSV" -Force
            $problemPublicFolderAccessRights | Export-CSV -Delimiter "`t" -NoTypeInformation -Path "C:\Users\kbriney-adm\Documents\ProblemPFPermissions.CSV" -Force
            Write-Host -NoNewline "."
        }
    }
    $a++
}
$publicFolderAccessRights | Export-CSV -Delimiter "`t" -NoTypeInformation -Path "C:\Users\kbriney-adm\Documents\PFPermissions.CSV" -Force
$problemPublicFolderAccessRights | Export-CSV -Delimiter "`t" -NoTypeInformation -Path "C:\Users\kbriney-adm\Documents\ProblemPFPermissions.CSV" -Force
