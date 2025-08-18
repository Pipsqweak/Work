
function SetSubjectForPWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $prefix,

        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [String]
        $senderName,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]
        $subject,

        [Parameter(Mandatory = $true, Position = 3)]
        [String]
        $extension,

        [Parameter(Mandatory = $false, Position = 4)]
        [Int32]
        $idxNum = -1
    )

    if(-not [String]::IsNullOrEmpty($subject))
    {
        $subject = ($subject -replace "\s+"," ").Trim()
    }
    $subjLength = $subject.Length

    if([String]::IsNullOrEmpty($senderName))
    {
        # This deals with $senderName -eq $null
        $senderName = [String]::Empty
    } `
    else # NOT ([String]::IsNullOrEmpty($senderName))
    {
        # Nothing.
    }

    if([String]::IsNullOrEmpty($prefix))
    {
        # This deals with $senderName -eq $null
        $prefix = [String]::Empty
    } `
    else # NOT ([String]::IsNullOrEmpty($senderName))
    {
        # Nothing.
    }

    if($idxNum -gt -1)
    {
        $pwPath = "{0}{1}{2} ({3}).{4}" -f @($prefix, $senderName, $subject, $idxNum, $extension)
    } `
    else # NOT ($idxNum -gt -1)
    {
        $pwPath = "{0}{1}{2}.{3}" -f @($prefix, $senderName, $subject, $extension)
    }

#    if($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    if($pwPath.Length -gt 120)
    {
        $subjCharactersToRemove = $pwPath.Length - 120
        if($subjCharactersToRemove -gt 0)
        {
            $subjLength -= $subjCharactersToRemove
            if($subjLength -lt 0)
            {
                $subjLength = 0
            } `
            else # NOT ($subjLength -lt 0)
            {
                # Nothing.
            }
        } `
        else # NOT ($subjCharactersToRemove -gt 0)
        {
            LogError ("Unable to create a viable ProjectWise path for {0}." -f @($pwPath))
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    {
        # Nothing.
    }

    return $subject.Substring(0, $subjLength)
}