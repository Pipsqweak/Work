[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $pathToCheck,

    [Parameter(Position=1)]
    [System.String[]]
    $pathsToAvoid=@(),

    [Parameter(Position=2)]
    [System.Int32]
    $maxDepth=-1,

    [Parameter(Position=3)]
    [Boolean]
    $directoriesOnly=$true,

    [Parameter(Position=4)]
    [Boolean]
    $doDebug=$true,

    [Parameter(Position=5)]
    [String]
    $logPath=[String]::Empty
)

$Global:doDebug = $doDebug
$Global:logPath = $logPath
$Global:objectsCheckedCount = 0

# Include logger...
. \\47888L\c$\users\kbriney\klb\scripts\Util\LogMessage.ps1

LogMessage ("Script root: {0}" -f @($PSScriptRoot))

function Get-ACLData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $pathToCheck
    )

    $aclData = "" | Select-Object Path,IsInheritanceBroken,ExplicitRules
    $aclData.Path = [String]::Empty
    $aclData.IsInheritanceBroken = $false
    $aclData.ExplicitRules = @()

    if(Test-Path -Path $pathToCheck)
    {
        $aclData.Path = $pathToCheck
        $acl = Get-ACL -LiteralPath $pathToCheck
        $Global:objectsCheckedCount++

        if($null -ne $acl)
        {
            $aclData.IsInheritanceBroken = $acl.AreAccessRulesProtected

            if($null -ne $acl.Access)
            {
                $explicitRules = @($acl.Access | Where-Object { -not $_.IsInherited })
                for($y = 0; $y -lt $explicitRules.Length; $y++)
                {
                    $d = "" | Select-Object Identity, Rights
                    $d.Identity = $explicitRules[$y].IdentityReference.ToString()
                    $d.Rights = $explicitRules[$y].FileSystemRights.ToString()

                    $aclData.ExplicitRules += $d
                }
            }
            else
            {
                LogMessage ("Unable to get ACL rules for {0}" -f $ff[$a].FullName)
            }
        }
        else
        {
            LogMessage ("Unable to get ACL for {0}" -f $ff[$a].FullName)
        }
    }

    if((-not [String]::IsNullOrEmpty($aclData.Path)) -and ($aclData.IsInheritanceBroken -or ($aclData.ExplicitRules.Length -gt 0)))
    {
        LogMessage ($aclData.Path)
        LogMessage ("`tInheritance broken: {0}" -f @($aclData.IsInheritanceBroken))
        foreach($er in $aclData.ExplicitRules)
        {
            LogMessage ("`t{0}: {1}" -f @($er.Identity, $er.Rights))
        }
    }
    else
    {
        # Nothing to log.
    }
    return $aclData
}

function Get-ACLs
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $pathToCheck,

        [Parameter(Position=1)]
        [System.String[]]
        $pathsToAvoid=@(),

        [Parameter(Position=2)]
        [System.Int32]
        $depth=0,

        [Parameter(Position=3)]
        [System.Int32]
        $maxDepth=-1,

        [Parameter(Position=4)]
        [Boolean]
        $directoriesOnly=$true
    )

    $pathACLs = @()
    $depth++
    if($pathsToAvoid -notcontains $pathToCheck)
    {
        LogMessage ("Processing: {0}" -f $pathToCheck)
        if(Test-Path -Path $pathToCheck)
        {
            # First, get the ACLs for this path...
            $acls = Get-ACLData $pathToCheck
            if($acls.IsInheritanceBroken -or ($acls.ExplicitRules.Length -gt 0))
            {
                $pathACLs += $acls
            }

            # Next process the folders and files under $pathToCheck

            if($directoriesOnly)
            {
                $ff = @(Get-ChildItem -LiteralPath $pathToCheck -Directory)
            }
            else
            {
                $ff = @(Get-ChildItem -LiteralPath $pathToCheck)
            }
            for($a = 0; $a -lt $ff.Length; $a++)
            {
                $acls = @()
                # If the current object is a folder, follow it...
                if($ff[$a].PSIsContainer)
                {
                    if(($maxDepth -eq -1) -or ($depth -le $maxDepth))
                    {
                        $acls = Get-ACLs -pathToCheck $ff[$a].FullName -pathsToAvoid $pathsToAvoid -depth $depth -maxDepth $maxDepth -directoriesOnly $directoriesOnly
                    }
                    else
                    {
                        # Don't go any deeper
                    }
                }

                # ... otherwise, get the file ACLs...
                else
                {
                    $acls = Get-ACLData $ff[$a].FullName
                }

                if($acls.IsInheritanceBroken -or ($acls.ExplicitRules.Length -gt 0))
                {
                    $pathACLs += $acls
                }
            }
        }
        else
        {
        }
    }
    else
    {
        LogMessage ("Avoiding: {0}" -f $pathToCheck)
    }

    return @(, $pathACLs)
}

LogMessage ("Path: [{0}]" -f $pathToCheck)
LogMessage ("MaxDepth: [{0}]" -f $maxDepth)
LogMessage ("Directories Only: [{0}]" -f $directoriesOnly)
LogMessage ("LogPath: [{0}]" -f $logPath)
LogMessage ("DoDebug: [{0}]" -f $doDebug)
if($null -ne $pathsToAvoid)
{
    $pathsToAvoid | ForEach-Object { LogMessage ("Path to avoid: {0}" -f $_) }
}
else
{
    $pathsToAvoid = @()
}

$allACLs = Get-ACLs -pathToCheck $pathToCheck -pathsToAvoid $pathsToAvoid -maxDepth $maxDepth -directoriesOnly $directoriesOnly

LogMessage ("Complete.  Checked {0} objects" -f $Global:objectsCheckedCount)

$allACLs
