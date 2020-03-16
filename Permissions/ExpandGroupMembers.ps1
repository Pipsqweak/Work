function ExtractDomainAndIdentity($nameToCheck)
{
    $domainAndID = "" | Select-Object DomainName, IdentityName

    if($nameToCheck.Contains("\"))
    {
        $nameSplit = $nameToCheck.Split('\')

        if($nameSplit.Length -ne 2)
        {
            throw ("Unable to split [{0}] on '\'" -f @($nameToCheck))
        }
        else
        {
            $domainAndID.DomainName = $nameSplit[0]
            $domainAndID.IdentityName = $nameSplit[1]
        }
    }
    else
    {
        # If there is no "\" in $nameToCheck, substitute the NetBIOSName of the domain the script is running under now...
        if($null -eq $Global:adDomain)
        {
            $Global:adDomain = Get-ADDomain
            if($null -eq $Global:adDomain)
            {
                throw "Unable to continue without the current AD domain object."
            }
        }
        else
        {
            # Nothing already acquired the current AD domain...
        }

        $domainAndID.DomainName = $Global:adDomain.NetBIOSName
        $domainAndID.IdentityName = $nameToCheck
    }

    return $domainAndID
}

function ExpandGroupMembers($nameToCheck)
{
    if(-not [String]::IsNullOrEmpty($nameToCheck))
    {
        if($nameToCheck.Contains("\"))
        {
            $nameSplit = $nameToCheck.Split('\')

            if($nameSplit.Length -ne 2)
            {
                [Log]::Warning("Unable to split [{0}] on '\'" -f @($nameToCheck))
                $nameToCheck = [String]::Empty
            }
            else
            {
                $nameToCheck = $nameSplit[1]
            }
        }
        else
        {
            # Nothing, leave it as is...
        }

        if(-not [String]::IsNullOrEmpty($nameToCheck))
        {
            $adObj = Get-ADObject -LDAPFilter ("(sAMAccountName={0})" -f @($nameToCheck)) -Properties objectClass,objectCategory,msDS-PrincipalName -ErrorAction SilentlyContinue
            if($null -ne $adObj)
            {
                if($adObj.objectCategory.StartsWith("CN=Group,"))
                {
                    # It's a group...
                }
                else
                {
                    # Nothing, only concerned with groups...
                }
            }
            else
            {
                [Log]::Warning("Unable to retrieve AD object for [{0}]" -f @($nameToCheck))
            }
        }
        else
        {
            # Nothing...
        }
    }
    else
    {
        [Log]::Warning("Blank name set sent to {0}" -f @($MyInvocation.MyCommand))
    }
}

function ExpandGroupMembers_old($groupName)
{
    if($null -eq $Global:expandedGroups)
    {
        $Global:expandedGroups = [System.Collections.Generic.List[String]]::new()
    }
    else
    {
        # Nothing ... already created $Global:expandedGroups...
    }

    if($null -eq $Global:groupToMembers)
    {
        $Global:groupToMembers = [System.Collections.Generic.SortedDictionary[[String],[System.Collections.Generic.List[String]]]]::new()
    }
    else
    {
        # Nothing ... already created $Global:groupToMembers
    }

    if(-not [String]::IsNullOrEmpty($groupName))
    {
        $eIdx = $Global:expandedGroups.BinarySearch($groupName)

        if($eIdx -lt 0)
        {
            $groupMembers = $null
            if(-not $Global:groupToMembers.ContainsKey($groupName))
            {
                $groupMembers = [System.Collections.Generic.List[String]]::new()
                $Global:groupToMembers.Add($groupName, $groupMembers)
            }
            else
            {
                # Nothing
            }
            $groupMembers = $Global:groupToMembers[$groupName]

            if($null -ne $groupMembers)
            {
                $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain)

                if($null -ne $context)
                {
                    $grpPrincipal = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($context, $groupName)
                    if($null -ne $grpPrincipal)
                    {
                        if($null -ne $grpPrincipal.Members)
                        {
                            <#
                                Iterating the group members is funky.  There might be abandoned Foreign Security Principles in the group.
                                If there are, then MoveNext() throws an exception because it can't resolve the FSP.  To avoid this,
                                I wrapped the MoveNext() in a try-catch and continue to MoveNext() until an exception is not thrown.
                            #>

                            $iter = $grpPrincipal.Members.GetEnumerator()
                            $iter.Reset()

                            $movedNext = $false
                            do
                            {
                                $moved = $false
                                do
                                {
                                    try
                                    {
                                        $movedNext = $iter.MoveNext()
                                        $moved = $true
                                    }
                                    catch
                                    {
                                        Write-Host ("Failed to MoveNext on group: {0}" -f $grpPrincipal.Name)
                                    }
                                } while(-not $moved)

                                if($movedNext)
                                {
                                    $grpMbr = $iter.Current
                                    $idx = $groupMembers.BinarySearch($grpMbr.Name)
                                    if($idx -lt 0)
                                    {
                                        $groupMembers.Insert(-bnot $idx, $grpMbr.Name)
                                    }
                                    else
                                    {
                                        # Nothing, user is already a group member
                                    }

                                    if ($grpMbr -is [System.DirectoryServices.AccountManagement.GroupPrincipal])
                                    {
                                        # See if we've already expanded the next group...
                                        $fIdx = $Global:expandedGroups.BinarySearch($grpMbr.Name)

                                        # If not, then expand it...
                                        if($fIdx -lt 0)
                                        {
                                            ExpandGroupMembers $grpMbr.Name
                                        }
                                        else
                                        {
                                            # Nothing...
                                        }

                                        # Now, if $Global:groupToMember contains an entry for $grpMbr.Name, add its members to the
                                        #    current groupMembers list...
                                        if($Global:groupToMembers.ContainsKey($grpMbr.Name))
                                        {
                                            if($false)
                                            {
                                                foreach($l in $Global:groupToMembers[$grpMbr.Name])
                                                {
                                                    $idx = $groupMembers.BinarySearch($l)
                                                    if($idx -lt 0)
                                                    {
                                                        $groupMembers.Insert(-bnot $idx, $l)
                                                    }
                                                    else
                                                    {
                                                        # Nothing, user is already a group member
                                                    }
                                                }
                                            }
                                        }
                                        else
                                        {
                                            Write-Host ("WTH!!  We should have just expanded {0}, but groupToMembers does not contain it" -f $grpMbr.Name)
                                        }
                                    }
                                }
                                else
                                {
                                    # Nothing to do
                                }
                            } while($movedNext)
                        }
                        else
                        {
                            # Nothing, guess there are no members of this group...
                        }
                        $grpPrincipal.Dispose()
                    }
                    else
                    {
                        # Group was not found...
                    }
                    $context.Dispose()
                }
                else
                {
                    # TODO: Cannot create context
                }
            }
            else
            {
                # Nothing, can't continue without $groupMembers
            }

            # Insert $groupName into $expandedGroups so we don't try to expand it again.
            $Global:expandedGroups.Insert(-bnot $eIdx, $groupName)
        }
        else
        {
            # Nothing, we've already expanded this group.
        }
    }
    else
    {
        # Nothing, can't continue without $groupName
    }
}
