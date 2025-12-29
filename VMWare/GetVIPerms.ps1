
function GetObjectChildren($obj,$pathStr,$parentObj)
{
    $idx = 0
    if(($null -ne $obj) -and ($obj.Name -notmatch "^vCLS-"))
    {
        $idx = $Global:checkedObjects.BinarySearch($obj.Id)
        if($idx -lt 0)
        {
            try
            {
                $perms = @(Get-VIPermission -Server $viServer -Entity $obj -ErrorAction Stop)
            }
            catch
            {
                Write-Host -ForegroundColor Yellow ("Unable to retrieve permissions on {0}/{1}" -f @($obj.Name, $obj.ID))
                $perms = @()
            }

            $pathStr2 = "{0}\{1}`t{2}" -f @($pathStr, $obj.Name, $obj.Id)
            $pathStr2 = $pathStr2.TrimStart(@('\'))
            $parentID = ""
            if($null -ne $parentObj)
            {
                $parentID = $parentObj.ID
            }
            Write-Host ("{0} -> {1}" -f @($parentID, $pathStr2))

            $d = "" | Select-Object Path,Name,ID,PersistentId,Principal,Role,Propagate,Parent,Permissions
            $d.Path = $pathStr
            $d.Name = $obj.Name
            $d.ID = $obj.Id
            $d.PersistentId = $obj.PersistentId
            $d.Permissions = $perms
            $d.Parent = $parentObj
            $exportData.Add($d)
            $parentObj = $d

            $Global:checkedObjects.Insert(-bnot $idx, $obj.Id)
        }
    }
    try
    {
        if(($idx -lt 0) -or ($null -eq $obj))
        {
            $children = @(Get-Inventory -Server $viServer -Location $obj -NoRecursion )# -ErrorAction Stop)
            $a = 0
            while($a -lt $children.Length)
            {
                $pathStr2 = ""
                if(($null -ne $obj) -and ($obj.Name -ne "Datacenters"))
                {
                    $pathStr2 = "{0}\{1}" -f @($pathStr, $obj.Name)
                }
                $pathStr2 = $pathStr2.TrimStart(@('\'))

                GetObjectChildren $children[$a] $pathStr2 $parentObj
                $a++
            }
        }
    }
    catch
    {

    }
}

$viServer = $vCenter
$viServer = $vc01
$rootObjects = @(Get-Inventory -Server $viServer -Location $null -NoRecursion)

function GetPerms
{
    $checkedObjects = [System.Collections.Generic.List[System.String]]::new()
    $exportData = [System.Collections.Generic.List[System.Object]]::new()

    GetObjectChildren $rootObjects[0] "" $null

    $uniqueObjPerms = [System.Collections.Generic.List[System.Object]]::new()
    $b = 0
    while($b -lt $exportData.Count)
    {
        Write-Host ("Checking {0}: {1} {2} {3}" -f @($b, $exportData[$b].Path, $exportData[$b].Name, $exportData[$b].ID))

        $objPerms = $exportData[$b].Permissions
        if($objPerms.Length -gt 0)
        {
            # $objPerms = @($objPerms | Sort-Object PermNum)
            $parentObjPerms = @()
            if($null -ne $exportData[$b].Parent)
            {
                $parentObjPerms = $exportData[$b].Parent.Permissions
            }

            $a = 0
            while($a -lt $objPerms.Length)
            {
                if($objPerms[$a].Principal.StartsWith("POWERENG") -or $objPerms[$a].Principal.StartsWith("CORP"))
                {
                    $matchingPerms = $parentObjPerms | Where-Object { ($_.Principal -eq $objPerms[$a].Principal) -and ($_.Role -eq $objPerms[$a].Role) -and ($_.Propagate) }

                    if($null -eq $matchingPerms)
                    {
                        # Did not find a permission on the parent which matches this permission.  It must be a new permission.

                        $d = "" | Select-Object Path,Name,ID,PersistentId,Principal,Role,Propagate
                        $d.Path = $exportData[$b].Path
                        $d.Name = $exportData[$b].Name
                        $d.ID = $exportData[$b].ID
                        $d.PersistentId = $exportData[$b].PersistentId
                        $d.Principal = $objPerms[$a].Principal
                        $d.Role = $objPerms[$a].Role
                        $d.Propagate = $objPerms[$a].Propagate

                        Write-Host ("`tUnique permission: {0} {1} {2} {3} {4} {5}" -f @($exportData[$b].Path, $exportData[$b].Name, $exportData[$b].ID, $exportData[$b].PersistentId, $objPerms[$a].Principal, $objPerms[$a].Role))
                        $uniqueObjPerms.Add($d)
                    } `
                    else
                    {
                        # Found a permission on the parent which matches this permission and it is propagated to this object
                    }
                }
                $a++
            }
        }

        $b++
    }
}
