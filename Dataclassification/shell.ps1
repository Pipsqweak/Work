[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNull()]
    [String]
    $TranslationCSV,

    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNull()]
    [String]
    $PathToScan,

    [Parameter(Mandatory=$true,Position=2)]
    [ValidateNotNull()]
    [String]
    $FolderToSaveTo
)

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\testStuff2b4.ps1
LD -translationCSVPath $TranslationCSV -folderToSaveTo $FolderToSaveTo -di $PathToScan
