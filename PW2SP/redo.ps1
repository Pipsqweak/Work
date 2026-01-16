function BuildVerificationLookupDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $rebuild
    )

    $viablePathsDictValues = @($viablePathsDict.Values)

    if(($null -eq $Script:viablePathsLookupDict) -or ($rebuild.IsPresent))
    {
        $Script:viablePathsLookupDict = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]]::new()

        # First add unverified objects...
        $b = 0
        $viablePathKeys = @($viablePathsDict.Keys)
        while((-not $Script:HaveError) -and ($b -lt $viablePathKeys.Length))
        {
            $vp = $viablePathsDict[$viablePathKeys[$b]]
            ShowProgress -progressID 1 -activity "Building verification lookup dictionary" -counter $b -counterMax $viablePathKeys.Length

            if(-not $vp.SPData.Verified)
            {
                $vp.SPData.Processed = $false
                # Ignore the pwProjectPath and project folder...
                if($vp.Paths.Length -ge 1)
                {
                    $pathToCheck = $vp.Paths -join "/"
                    if(-not [String]::IsNullOrEmpty($pathToCheck))
                    {
                        if(-not $Script:viablePathsLookupDict.ContainsKey($pathToCheck))
                        {
                            $Script:viablePathsLookupDict.Add($pathToCheck, [System.Collections.Generic.List[Object]]::new())
                        } `
                        else
                        {
                            # Nothing, don't want dups...
                        }
                        $Script:viablePathsLookupDict[$pathToCheck].Add($vp)

                        # Now add all parent folders for the object to the dictionary
                        $p = $vp.Paths.Length - 2
                        while($p -gt 0)
                        {
                            # Get a smaller list of folder objects to look at.
                            $folderVPs = @($viablePathsDictValues | Where-Object { ($_.Paths.Length -eq ($p + 1)) -and ($_.SourceObject.MyType -eq "ProjectWiseFolder") })
                            $folderPathToMatch = $vp.Paths[0..$p] -join "/"

                            # Narrow the list even more.
                            $folderVPs = @($folderVPs | Where-Object { ($_.Paths[0..$p] -join "/") -eq $folderPathToMatch })

                            $folderVPs.ForEach({
                                if(-not $Script:viablePathsLookupDict.ContainsKey($folderPathToMatch))
                                {
                                    $Script:viablePathsLookupDict.Add($folderPathToMatch, [System.Collections.Generic.List[Object]]::new())
                                    $Script:viablePathsLookupDict[$folderPathToMatch].Add($_)
                                } `
                                else
                                {
                                    # Nothing, don't want dups...
                                }
                            })
                            $p--
                        }
                    } `
                    else
                    {
                        LogError("Empty paths for {0} in {1}." -f @((SourceObjectIdentity -srcObj $vp), $me.Name))
                        break
                    }
                } `
                else
                {
                    # Nothing, ignoring the pwProjectPath folder.
                }
            } `
            else
            {
                # Already verified... skip it.
            }

            $b++
        }

        ShowProgress -progressID 1 -complete
    } `
    else
    {
        # Nothing, already built it.
    }
}
