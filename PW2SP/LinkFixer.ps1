LoadConnectionDataFromFile
ConnectToSPOL

function CollectURLLinks
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Microsoft.SharePoint.Client.Folder] $folder,

        [Parameter(Mandatory=$true, Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[Object]] $projectLinks
    )

    try
    {
        $Error.Clear()
        Write-Host ("`r`nChecking [{0}]..." -f @($folder.ServerRelativeURL))
        $filesAndFolders = @(Get-PnPFolderItem -Identity $folder.ServerRelativeURL -ErrorAction Stop).Where({ $_.Name -ne "Forms" })
        $b = 0
        while($b -lt $filesAndFolders.Count)
        {
            if($filesAndFolders[$b] -is [Microsoft.SharePoint.Client.Folder])
            {
                CollectURLLinks -folder $filesAndFolders[$b] -projectLinks $projectLinks
            } `
            else
            {
                if(($filesAndFolders[$b] -is [Microsoft.SharePoint.Client.File]) -and ($filesAndFolders[$b].Name -match "\.url$"))
                {
                    $d = [PSCustomObject]@{
                        FolderURL = $folder.ServerRelativeURL
                        LinkName = $filesAndFolders[$b].Name
                        LinkURL = [String]::Empty
                        LinkParams = [String]::Empty
                        Status = [String]::Empty
                    }

                    Write-Host -ForegroundColor Green ("`treading [{0}]" -f @($filesAndFolders[$b].ServerRelativeURL))
                    try
                    {
                        $Error.Clear()
                        $fileAsListItem = Get-PnPFile -AsListItem -URL $filesAndFolders[$b].ServerRelativeURL -ErrorAction Stop
                        if($null -ne $fileAsListItem)
                        {
                            if($fileAsListItem.FieldValues.ContainsKey("FileRef"))
                            {
                                Write-Host -ForegroundColor Green ("`t`tgetting reference to linked document from: [{0}]" -f @($fileAsListItem.FieldValues["FileRef"]))
                                try
                                {
                                    $Error.Clear()
                                    $fileAsString = Get-PnPFile -Url $fileAsListItem.FieldValues["FileRef"] -AsString -ErrorAction Stop

                                    if(-not [String]::IsNullOrEmpty($fileAsString))
                                    {
                                        $urlMatch = [String]::Empty
                                        $urlMatch = $fileAsString.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) -match "^URL=(.*)$" | Select-Object -First 1

                                        if($urlMatch -match "^URL=(.*)$")
                                        {
                                            try
                                            {
                                                $urlObject = [System.Uri] $Matches[1]
                                                $segStart = $urlObject.Segments.IndexOf("sites/")
                                                $newURL = [System.Web.HttpUtility]::UrlDecode($urlObject.Segments[$segStart..($urlObject.Segments.Length-1)] -join "")
                                                $newURL = "/" + $newURL.Replace("SP-GovernmentServices-Projects","WSPFED-SP-GVSProjects0241907_0001and0250215_0000/Shared Documents").Replace("0250215_0000","0250215")
                                            }
                                            catch
                                            {

                                            }


                                            $d.LinkURL = $Matches[1]
                                            Write-Host -ForegroundColor Green ("`t`t`tgetting document properties from: [{0}]" -f @($d.LinkURL))
                                            try
                                            {
                                                $Error.Clear()
                                                $refFileAsListItem = Get-PnPFile -Url $d.LinkURL -AsListItem -ErrorAction Stop
                                                $linkParams = @{}
                                                $fvKeys = @($refFileAsListItem.FieldValues.Keys)
                                                $c = 0
                                                while($c -lt $fvKeys.Length)
                                                {
                                                    if(($connData.documentFields.ContainsKey($fvKeys[$c])) -and (-not [String]::IsNullOrEmpty($refFileAsListItem.FieldValues[$fvKeys[$c]])))
                                                    {
                                                        $val = $refFileAsListItem.FieldValues[$fvKeys[$c]]
                                                        if($fvKeys[$c] -eq "_ShortcutUrl")
                                                        {
                                                            $val = $val.Url
                                                        }

                                                        $linkParams.Add($fvKeys[$c], $val)
                                                    }
                                                    $c++
                                                }

                                                $d.LinkParams = @($linkParams.Keys).ForEach({ "`"{0}`"=`"{1}`"" -f @($_, $linkParams[$_]) }) -join "`t"
                                                $d.Status = "Ok"
                                            }
                                            catch
                                            {
                                                Write-Host -ForegroundColor Red ("`t`t`tFailed to get document properties for [{0}].  Exception:`r`n`t`t`t{1}" -f @($Matches[1], $Error[0].Exception.Message))
                                                $d.Status = $Error[0].Exception.Message
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, not a .URL file.
                                        }
                                    } `
                                    else
                                    {
                                        Write-Host -ForegroundColor Red ("`t`tFailed to read [{0}].  Null String returned" -f @($fileAsListItem.FieldValues["FileRef"]))
                                        $d.Status = "Null string return from reading {0}" -f @($fileAsListItem.FieldValues["FileRef"])
                                    }
                                }
                                catch
                                {
                                    Write-Host -ForegroundColor Red ("`t`tFailed to read [{0}].  Exception:`r`n`t`t{1}" -f @($fileAsListItem.FieldValues["FileRef"], $Error[0].Exception.Message))
                                    $d.Status = $Error[0].Exception.Message
                                }
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Red ("`t`tFile is missing the FileRef field value. [{0}]" -f @($filesAndFolders[$b].ServerRelativeURL))
                                $d.Status = "No FileRef field value."
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Red ("`tFailed to read file [{0}].  Null value returned." -f @($filesAndFolders[$b].ServerRelativeURL))
                            $d.Status = "No file contents.  Null value returned"
                        }
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("`tFailed to read file [{0}].  Exception:`r`n`t" -f @($filesAndFolders[$b].ServerRelativeURL, $Error[0].Exception.Message))
                        $d.Status = $Error[0].Exception.Message
                    }


                    $projectLinks.Add($d)
                } `
                else
                {
                    # Nothing, not a file, and certainly not a .url file.
                }
            }
            $b++
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("`tFailed to get subfolders and files for {0}" -f @($folder.ServerRelativeURL))
    }
}

function CheckSite
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String] $topFolder,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $saveFile
    )

    try
    {
        $folderItems = @(Get-PnPFolderItem -Identity $topFolder -ErrorAction Stop).Where({ $_.Name -ne "Forms" })
        <#
        if($topFolder -eq "Proposal Archives")
        {
            $folderItems = @(Get-PnPFolderItem -Identity $topFolder -ErrorAction Stop).Where({ 1 -eq 1})
        } `
        else
        {
            $folderItems = @(Get-PnPFolderItem -Identity $topFolder -ErrorAction Stop).Where({ $_.Name -match "\.url$" })
        }
        #>
        $projectLinks = [System.Collections.Generic.List[Object]]::new()
        $a = 0
        while($a -lt $folderItems.Count)
        {
            if($topFolder -ne "Proposal Archives")
            {
                try
                {
                    $Error.Clear()
                    $fileAsString = [String]::Empty
                    $fileAsString = Get-PnPFile -AsString -URL $folderItems[$a].ServerRelativeURL -ErrorAction Stop

                    if(-not [String]::IsNullOrEmpty($fileAsString))
                    {
                        $urlMatch = [String]::Empty
                        $urlMatch = $fileAsString.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) -match "^URL=(.*)$" | Select-Object -First 1

                        if($urlMatch -match "^URL=(.*)$")
                        {
                            $folderURL = $Matches[1].Replace("/Forms/AllItems.aspx","")
                            try
                            {
                                $Error.Clear()
                                $projectFilesAndFolders = @(Get-PnPFolderItem -Identity $folderURL -ErrorAction Stop).Where({ $_.Name -ne "Forms" })
                                $b = 0
                                while($b -lt $projectFilesAndFolders.Count)
                                {
                                    if($projectFilesAndFolders[$b] -is [Microsoft.SharePoint.Client.Folder])
                                    {
                                        CollectURLLinks -folder $projectFilesAndFolders[$b] -projectLinks $projectLinks
                                    }
                                    $b++
                                }
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("Failed to get files and folder for [{0}]" -f @($folderURL))
                            }
                        } `
                        else
                        {
                            # Nothing, not a .url file.
                        }
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Red ("Failed to read as string file: [{0}] (null string)" -f @(folderItems[$a].ServerRelativeURL))
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to read as string file: [{0}]" -f @(folderItems[$a].ServerRelativeURL))
                }
            } `
            else
            {
                $folderURL = $folderItems[$a].ServerRelativeUrl
                try
                {
                    $Error.Clear()
                    Write-Host -ForegroundColor Green ("Getting files and folders for {0}" -f @($folderURL))
                    $projectFilesAndFolders = @(Get-PnPFolderItem -Identity $folderURL -ErrorAction Stop).Where({ $_.Name -ne "Forms" })
                    $b = 0
                    while($b -lt $projectFilesAndFolders.Count)
                    {
                        if($projectFilesAndFolders[$b] -is [Microsoft.SharePoint.Client.Folder])
                        {
                            # $folder = $projectFilesAndFolders[$b]
                            CollectURLLinks -folder $projectFilesAndFolders[$b] -projectLinks $projectLinks
                        }
                        $b++
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to get files and folder for [{0}]" -f @($folderURL))
                }
            }
            $projectLinks | ConvertTo-Json -Depth 10 | Set-Content -Path $saveFile -Force
            $a++
        }
    }
    catch
    {
        Write-Host ("Failed to get {0} folder items." -f @($topFolder))
    }
}

CheckSite -topFolder "Shared Documents" -saveFile "E:\PW2SP\templinkdata1.json"

CheckSite -topFolder "Closed Projects" -saveFile "E:\PW2SP\linkdata2.json"

CheckSite -topFolder "Proposal Archives" -saveFile "E:\PW2SP\linkdata3.json"


Connect-PnPOnline -Url $siteURL -ClientId "5bd66128-adff-40e5-b9cf-5ed139ccf821" -Thumbprint "8CA9FD2F2B6F57C288E3665CE2BF729A68EF8973" -Tenant "0f3cfa5e-1c7a-46dc-b39c-fbe2e805c797" -AzureEnvironment USGovernmentHigh

# Fed Projects
$siteURL = "https://wspusa.sharepoint.us/sites/WSPFED-SP-GVS-Projects"

# Fed Proposals..
$siteURL = "https://wspusa.sharepoint.us/sites/WSPFED-SP-GVS-PursuitCollaboration"

# Temp Fed Projects
$siteURL = "https://wspusa.sharepoint.us/sites/WSPFED-SP-GVSProjects0241907_0001and0250215_0000"

$topFolder = "Shared Documents"
$saveFile = "E:\PW2SP\templinkdata1.json"
