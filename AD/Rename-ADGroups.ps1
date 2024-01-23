$adGroupsToRename = Get-ADGroup -Filter * -SearchBase "OU=File Shares,OU=Groups,OU=IT,OU=PEI,DC=powereng,DC=com" -SearchScope OneLevel | Where-Object { $_.Name -match "\-SVMAFS01" }

$doRenameOperation = $true
$renames = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $adGroupsToRename.Length)
{
    if($adGroupsToRename[$a].Name -match "(\-SVMAFS01)")
    {
        $d = "" | Select-Object Before, After
        $d.Before = $adGroupsToRename[$a].Name
        $d.After = $adGroupsToRename[$a].Name.Replace($Matches[1], "FS1")

        if($doRenameOperation)
        {
            $newSAMAccountName = $adGroupsToRename[$a].Name.Replace($Matches[1], "FS1")
            try
            {
                # Make sure there isn't already a group with the new name...
                $existingGroup = Get-ADGroup -Identity $newSAMAccountName -ErrorAction Stop
                Write-Host -ForegroundColor Yellow ("Unable to rename {0} to {1}, a group with the same name already exists." -f @($adGroupsToRename[$a].Name, $newSAMAccountName))
            }
            catch
            {
                # Safe to rename the group...
                Write-Host -ForegroundColor Green ("Renaming {0} to {1}." -f @($adGroupsToRename[$a].Name, $newSAMAccountName))
                Set-ADGroup -Identity:$adGroupsToRename[$a].DistinguishedName -SamAccountName:$newSAMAccountName
                Rename-ADObject -Identity:$adGroupsToRename[$a].DistinguishedName -NewName:$newSAMAccountName
            }
        }

        $renames.Add($d)
    }
    $a++
}
