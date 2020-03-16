function NASListChecker
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [Object[]]
        $nasList
    )

    $retval = $true
    if($null -ne $nasList)
    {
        if($nasList -is [Object[]])
        {
            for($a = 0; $a -lt $nasList.Length; $a++)
            {
                $objProps = @(Get-Member -InputObject $nasList[$a] -MemberType NoteProperty | Select-Object -ExpandProperty Name)
                foreach($propName in @("name","mode","mgmtServer"))
                {
                    if($objProps -contains $propName)
                    {
                        if([String]::IsNullOrEmpty($nasList[$a].$($propName)))
                        {
                            $retval = $false
                            [Log]::Warning("NAS list entry {0} missing value for {1}" -f @($a, $propName))
                        }
                        else
                        {
                            # Nothing all good
                        }
                    }
                    else
                    {
                        $retval = $false
                        [Log]::Warning("NAS list entry {0} missing {1} property" -f @($a, $propName))
                    }
                }

                if(@("CLUSTER","7-MODE") -notcontains $nasList[$a].mode)
                {
                    [Log]::Warning("Invalid NetApp filer mode: {0}.  Use CLUSTER OR 7-MODE only." -f @($nasList[$a].mode))
                    $retval = $false
                }
                else
                {
                    # Nothing...
                }
            }
        }
        else
        {
            [Log]::Warning("NAS list is not an array")
        }
    }
    else
    {
        [Log]::Warning("NAS list is null")
    }

    return $retval
}
