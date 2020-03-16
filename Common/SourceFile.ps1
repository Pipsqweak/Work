<#
.SYNOPSIS

Sources a .ps1 file into a session.


.PARAMETER SourceFile
Specifies the path to the .ps1 file to source into the session

.PARAMETER Reload
Specifies whether the .ps1 file should be sourced into the session even if it was previously sourced.

.INPUTS

None. You cannot pipe objects to SourceFile.ps1.

.OUTPUTS

None. SourceFile.ps1 does not generate any output.

.NOTES

Keep scope in mind when calling SourceFile.ps1.  Without a leading . in front of the call to SourceFile.ps1, the source file will be
sourced into the local scope of SourceFile.ps1, not the global scope.

.EXAMPLE

PS> . .\SourceFile.ps1 C:\Scripts\MySourceFile.ps1

.EXAMPLE

PS> . .\SourceFile.ps1 -SourceFile C:\Scripts\MySourceFile.ps1 -Reload

#>

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $SourceFile,

    [Parameter(Mandatory=$false,Position=1)]
    [switch]
    $Reload
)

if($null -eq $Global:sourcedFiles)
{
    $Global:sourcedFiles = [System.Collections.Generic.List[String]]::new()
}
else
{
    # Nothing, already created the list of sourced files.
}

if(-not [String]::IsNullOrEmpty($SourceFile))
{
    $idx = $Global:sourcedFiles.BinarySearch($SourceFile.ToLower())
    if(($idx -lt 0) -or ($Reload.IsPresent))
    {
        if(Test-Path -Path $SourceFile)
        {
            . $SourceFile

            # Only add the source file to the list of sourced files if it's not in the list...  (-Reload(ing))
            if($idx -lt 0)
            {
                $Global:sourcedFiles.Insert(-bnot $idx, $SourceFile)
            }
            else
            {
                # Nothing file is already in the list ... we must have been instructed to re-source the file
            }
        }
        else
        {
            Write-Error ("Unable to source file {0}.  It does not exist." -f @($SourceFile))
        }
    }
    else
    {
        # Nothing, already sourced the file
    }
}
else
{
    Write-Error ("Missing source file name in {0}." -f @($MyInvocation.MyCommand))
}
