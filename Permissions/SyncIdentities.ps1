<#
    Synchronize AD groups and users to the Permissions database so the scanner does not have to worry about expanding groups, etc.
       It will only have to save the identities and rights it finds along its way.  This module/script will deal with making sure
       groups/identity/group members are up to snuff.

        Keep in mind, Get-ADGroup, Get-ADGroupMember, etc will return distribution lists groups/group members, so filter these out since
        they don't work for permissions.

            if(($adGroup.groupType -band 0x80000000) -eq 0x80000000)
            {
                # Then group is security enabled.
            }
#>

function ShowProgress($str)
{
    $x = [Console]::CursorLeft
    $y = [Console]::CursorTop
    [Console]::Write($str)
    [Console]::SetCursorPosition($x,$y)
}

$domainData = @()

foreach($adServerName in @("powereng.com","segainc.com"))
{
    $o = "" | Select-Object DomainName, ADDomain, SecurityGroups, NonSecurityGroups, ADUsers
    $o.DomainName = $adServerName
    [Log]::Info("Getting AD domain for {0}" -f @($o.DomainName))
    $o.ADDomain = Get-ADDomain -Server $o.DomainName
    if($null -ne $o.ADDomain)
    {
        $o.SecurityGroups = New-Object 'System.Collections.Generic.SortedDictionary[[String],[Microsoft.ActiveDirectory.Management.ADGroup]]'([System.StringComparer]::InvariantCultureIgnoreCase)
        $o.NonSecurityGroups = New-Object 'System.Collections.Generic.SortedDictionary[[String],[Microsoft.ActiveDirectory.Management.ADGroup]]'([System.StringComparer]::InvariantCultureIgnoreCase)
        $o.ADUsers = New-Object 'System.Collections.Generic.SortedDictionary[[String],[Microsoft.ActiveDirectory.Management.ADUser]]'([System.StringComparer]::InvariantCultureIgnoreCase)

        [Log]::Info("    Getting users...")
        $allADUsers = Get-ADUser -Filter * -Server $o.ADDomain.PDCEmulator
        [Log]::Info("        found {0} users" -f @($allADUsers.Length))

        for($a = 0; $a -lt $allADUsers.Length; $a++)
        {
            ShowProgress ("Processing Users: {0,7:P3} Complete" -f @($a/$allADUsers.Length))
            try
            {
                $o.ADUsers.Add($allADUsers[$a].DistinguishedName, $allADUsers[$a])
            }
            catch
            {
                [Log]::Warning("        Failed to add: {0}" -f @($allADUsers[$a].DistinguishedName))
            }
        }

        [Log]::Info("    Getting groups...")
        $allADGroups = Get-ADGroup -Filter * -Properties Members -Server $o.ADDomain.PDCEmulator
        [Log]::Info("        found {0} groups" -f @($allADGroups.Length))
        for($a = 0; $a -lt $allADGroups.Length; $a++)
        {
            $adGroup = $allADGroups[$a]
            ShowProgress ("Processing Groups: {0,7:P3} Complete" -f @($a/$allADGroups.Length))
            $dictToAddTo = $o.SecurityGroups
            #if(($adGroup.groupType -band 0x80000000) -ne 0x80000000)
            if($adGroup.GroupCategory -ne [Microsoft.ActiveDirectory.Management.ADGroupCategory]::Security)
            {
                $dictToAddTo = $o.NonSecurityGroups
            }
            else
            {
                # Nothing
            }

            try
            {
                $dictToAddTo.Add($adGroup.DistinguishedName, $adGroup)
            }
            catch
            {
                [Log]::Warning("            Failed to add: {0}" -f @($adGroup.DistinguishedName))
            }
        }

        [Log]::Info("            {0} security groups" -f @($o.SecurityGroups.Count))
        [Log]::Info("            {0} non-security groups" -f @($o.NonSecurityGroups.Count))

        $domainData += $o
    }
    else
    {
        # Nothing, no domain found...
    }
}

[DateTime] $lastUpdated = [DataAccess]::Me().db.ExecuteScalar("SELECT MAX(LastUpdated) FROM Identities")

for($d = 0; $d -lt $domainData.Length; $d++)
{
    $domainData[$d].SecurityGroups.GetEnumerator() | ForEach-Object {
        $groupIdentity = "{0}\{1}" -f @($domainData[$d].ADDomain.NetBIOSName, $_.Value.name)
        $groupID = [DataAccess]::AddUpdateIdentity($groupIdentity)
        if($groupID -gt 0)
        {
            [Log]::Info("Added/Updated group {0}({1})" -f @($groupIdentity, $groupID))
            if($null -ne $_.Value.Members)
            {
                $_.Value.Members.GetEnumerator() | ForEach-Object {
                    $member = $null
                    for($a = 0; ($null -eq $member) -and ($a -lt $domainData.Length); $a++)
                    {
                        if($domainData[$a].SecurityGroups.ContainsKey($_))
                        {
                            $member = $domainData[$a].SecurityGroups[$_]
                        }
                        elseif($domainData[$a].ADUsers.ContainsKey($_))
                        {
                            $member = $domainData[$a].ADUsers[$_]
                        }
                        else
                        {
                            # Keep Looking...
                        }
                    }

                    if($null -ne $member)
                    {
                        $memberIdentity = "{0}\{1}" -f @($domainData[$d].ADDomain.NetBIOSName, $member.SamAccountName)
                        $memberID = [DataAccess]::AddUpdateIdentity($memberIdentity)
                        if($memberID -gt 0)
                        {
                            [Log]::Info("    Added/Updated member identity {0}({1})" -f @($memberIdentity, $memberID))
                            $rowCount = [DataAccess]::AddUpdateGroupMember($groupID, $memberID)
                            if($rowCount -ne -1)
                            {
                                [Log]::Info("        Added/Updated group membership for {0}({1}) / {2}({3})" -f @($groupIdentity, $groupID, $memberIdentity, $memberID))
                            }
                            else
                            {
                                [Log]::Warning("        Failed to add/update group membership for {0}({1}) / {2}({3})" -f @($groupIdentity, $groupID, $memberIdentity, $memberID))
                            }
                        }
                        else
                        {
                            [Log]::Warning("    Failed to add/update identity {0}" -f $memberIdentity)
                        }
                    }
                    else
                    {
                        [Log]::Warning("    Unable to determine identity of {0}" -f @($_))
                    }
                }
            }
            else
            {
                # Nothing, no members
            }
        }
        else
        {
            [Log]::Warning("Failed to add/update group {0}" -f @($groupIdentity))
        }
    }
}

$q = "SELECT * FROM Identities WHERE (LastUpdated < '{0}')" -f $lastUpdated.ToString("yyyy-MM-dd hh:mm:ss.fff")
$t = [DataAccess]::Me().db.GetDataTable($q)
