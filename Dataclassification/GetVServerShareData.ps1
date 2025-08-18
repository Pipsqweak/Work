[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNull()]
    [String]
    $TranslationCSV,

    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNull()]
    [String]
    $VServerName,

    [Parameter(Mandatory=$true,Position=2)]
    [ValidateNotNull()]
    [String]
    $FolderToSaveTo
)

class ShareAgeStat
{
    [UInt64] $Count = 0
    [UInt64] $Size = 0
}

class ShareStats
{
    static [DateTime] $dNow
    static [System.Collections.Generic.List[DateTime]] $FileAgeKeys = $null
    [UInt64] $Directories = 0
    [UInt64] $Files = 0
    [UInt64] $TotalSize = 0
    [System.Collections.Generic.Dictionary[[DateTime],[Object]]] $FilesByAge = [System.Collections.Generic.Dictionary[[DateTime],[ShareAgeStat]]]::new()
    [System.Collections.Generic.List[System.Object]] $Owners = [System.Collections.Generic.List[System.Object]]::new()

    static [void] InitFileAgeKeys()
    {
        if($null -eq [ShareStats]::FileAgeKeys)
        {
            [ShareStats]::dNow = [DateTime]::Parse([DateTime]::Now.ToString("MM/dd/yyyy"))
            [ShareStats]::FileAgeKeys = [System.Collections.Generic.List[DateTime]]::new()
            @(-10..-1) | ForEach-Object { [ShareStats]::FileAgeKeys.Add([ShareStats]::dNow.AddYears($_)) }
        }
    }

    ShareStats([System.Collections.Generic.List[System.String]] $pathOwners)
    {
        if($null -ne [ShareStats]::FileAgeKeys)
        {
            [ShareStats]::InitFileAgeKeys()
        }
        foreach($key in [ShareStats]::FileAgeKeys)
        {
            $this.FilesByAge.Add($key, [ShareAgeStat]::new())
        }
        if($null -ne $pathOwners)
        {
            $pathOwners | Foreach-Object { $this.Owners.Add($_) }
        }
    }
}

function AddLongUNCPath($str) { $retval = $str; if($str -notmatch "^\\\\\?\\unc\\") { $retval = $str -replace "^\\\\","\\?\UNC\" } return $retval }

function RemoveLongUNCPath($str) { return ($str -replace "^\\\\\?\\UNC\\","\\") }

function LD
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $translationCSVPath,

        [Parameter(Mandatory=$true,Position=2)]
        [String]
        $folderToSaveTo,

        [Parameter(Mandatory=$true,Position=3)]
        [String]
        $di
    )

    [ShareStats]::InitFileAgeKeys()
    $Global:sizeByAgeDict = [System.Collections.Generic.SortedDictionary[[String], [ShareStats]]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $Global:directoryExceptions = [System.Collections.Generic.List[System.String]]::new()
    $Global:fileExceptions = [System.Collections.Generic.List[System.String]]::new()

    $Global:translationSW = [System.Diagnostics.Stopwatch]::new()
    $Global:translationsAttempted = 0
    $Global:translationsFailed = [System.Collections.Generic.List[String]]::new()

    $Global:explicitACLRules = [System.Collections.Generic.List[System.Object]]::new()

    $tDI = RemoveLongUNCPath $di
    $diParts = $tDI.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $serverName = $diParts[0]
    $shareName = $diParts[1]

    # "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\Data"
    CreateSavePath -folderToSaveTo $folderToSaveTo -cifsServer $serverName

    $oldTitle = $host.UI.RawUI.WindowTitle
    BuildTranslationDictionaryFromCSV -translationCSVPath $translationCSVPath -forServer $serverName
        # "\\cdc-ntapmgmt01\c$\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\AllCifsShares-20231213.csv" $serverName

    $host.ui.RawUI.WindowTitle = $di.ToLower()
    ListDirectory -di $di -folderToSaveTo $folderToSaveTo -serverName $serverName
    if($Global:directoryExceptions.Count -gt 0)
    {
        Write-Host ("`r`nDirectory Exceptions:")
        Write-Host ("`t{0}" -f @(($Global:directoryExceptions -join "`r`n`t")))
    }

    if($Global:fileExceptions.Count -gt 0)
    {
        Write-Host ("`r`nFile Exceptions:")
        Write-Host ("`t{0}" -f @(($Global:fileExceptions -join "`r`n`t")))
    }
    ShowStats
    $host.UI.RawUI.WindowTitle = $oldTitle
    SaveData -folderToSaveTo $folderToSaveTo -cifsServer $serverName
}


. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\testStuff2.ps1
LD -translationCSVPath $TranslationCSV -folderToSaveTo $FolderToSaveTo -di $PathToScan
