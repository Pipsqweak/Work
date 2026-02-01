ConnectTo vCenter,prod

function test11
{
    Measure-Command {   # 9.9219
        $projectMatch = "^{0}" -f @([Regex]::Escape($pwData.PWFolder.FullPath))
        for ($i = 0; $i -lt 1000; $i++)
        {
            if($documentsToUpload[0].SourceObject.FullPath -match $projectMatch)
            {
                $kl++
            }
            #$documentsToUpload[0].SourceObject.FullPath.StartsWith($pwData.PWFolder.FullPath)
        }
    }

    Measure-Command { # 20.1232
        for ($i = 0; $i -lt 1000; $i++)
        {
            if($documentsToUpload[0].SourceObject.FullPath.StartsWith($pwData.PWFolder.FullPath))
            {
                $kl++
            }
        }
    }
}

$PWServerFQDN = "cdc-pwdint02.powereng.com"

$PWDatasourceName = "pw_prod_pw01"
#$PWDatasourceName = "pw_prod_pw02"
#$PWDatasourceName = "pw_prod_dmsclosed"
#$PWDatasourceName = "pw_prod_acq_archive"

$pwEnvironment = "{0}:{1}" -f @($PWServerFQDN, $PWDatasourceName)

$pwCreds = (Get-ConnectCredentials "projectwise").Credential

Import-Module pwps_dab
New-PWLogin -DatasourceName $pwEnvironment -UserName $pwCreds.UserName -Password $pwCreds.Password -ErrorAction Stop




$pwRootNodes = [System.Collections.Generic.List[System.Object]]::new()

$d = "" | Select-Object Server, DataSourceName, RootPath
$d.Server = "cdc-pwdint02.powereng.com"
$d.DataSourceName = "pw_prod_pw01"
$d.RootPath = ""

$pwRootNodes.Add($d)

$d = "" | Select-Object Server, DataSourceName, RootPath
$d.Server = "cdc-pwdint02.powereng.com"
$d.DataSourceName = "pw_prod_dmsclosed"
$d.RootPath = ""

$pwRootNodes.Add($d)


function ConnectToSPOL
{
    $siteURL = "https://powereng0.sharepoint.com/sites/SP-GVS-ProjectWise-MigrationTest"

    $spSiteLoginDataJSON =
@"
{
    "Pfxfile": "C:\\Users\\kbriney-adm\\PSScripts\\Repos\\PEI-IT-OPS\\PW2SP\\PnP.PowerShell.PW2SP.pfx",
    "Cerfile": "C:\\Users\\kbriney-adm\\PSScripts\\Repos\\PEI-IT-OPS\\PW2SP\\PnP.PowerShell.PW2SP.cer",
    "AzureAppId": "5c5d34c2-375f-43e6-a534-b2cf942e2812",
    "CertificateThumbprint": "EA671D41B5B422D0A764D8D982CFB05456E97DA6",
    "Base64Encoded": "MIIKHwIBAzCCCdsGCSqGSIb3DQEHAaCCCcwEggnIMIIJxDCCBf0GCSqGSIb3DQEHAaCCBe4EggXqMIIF5jCCBeIGCyqGSIb3DQEMCgECoIIE7jCCBOowHAYKKoZIhvcNAQwBAzAOBAi6AQ0NUGWDsQICB9AEggTIxXF5X71ojqwYWh5GxAzeR8sEP9LQL5rD/hOhWKmvJ7Liy6rmxV3rjbWr4pbUC92wYe/CuVqRHkJ6jqTPUBfsAGIVPgfzySXTfTCoJpmuAon+rBCHtTWZiKeFQuDMtH8UUUpPCoVe7yIQnX5FXLGPDZ3SRGAtpOEJb/3DVGkx4KjS2nJOtjFLaPwrWgPlJ3aIZzoNx40XoH6l/1rGMThjs6MhSLpNZN5XDyHH3QBcO/MWTb+Dl7lhptNQvROIwST0VoZ3AvrUORdqx/LhUzsXnInUuOzAS3Lsgxj+tSUI2rt6iLojUsDbotliL0+VdBTROJUlnZgJUwH8IKP46ZxhDSJlqYxQL4b9/lO/8U3Wu2uBmz9k4XRw+WNIzazTKd0+F/U5nP2oyrGsqEbKvF8bjwN7T6ko83GyE15MnxLZKu9GkAyd5Vo0KksqnY/cwAo0r11sk8YP9awzjo+zLJscefh64+MkUZCd73pA9I+6Pzf2xJ+RLeQxr2P2n0QlrN9l6wRix33bgCqheMHIyxr92nLPqgdFYg5i2axNnGRwfnuwu+wbFkPNupuyr8ZwIY+2McqbhvA1OHIiiMtZf7XsjZy3wW4FvPKBAxeh62HiCvXXE/RC12Vu5EopeiuYX3Tdrc1mOWX2mKP7xn18txy70Z6CErutfOzNg6j6SXAqCsMhKuUHpwlwsNE0Vhy1zi4EwDQX+KexhFI+MQOTGE+JMOxfyxPYu1x2nEVEskD8xnrZPyuoEn+zS1y4Uiy3/+E5Nv9/2hvDpd3lHchw8W9WSULe2K9TraOk+3tuSuUimnzi+QLY+TgvYLfMPtFHK6gU+Jtxuh0feQyJEPr4B3c6T42rbgJDe5gFn/RaqKuoJS4Qq6LDaJ/3qRO+67rITmFLAGom4sM9JTlkQ0BsoqGPmAYBimr9Y2plY4iSK8DwdaAj7zQ7vhSoDHyJs9KplEOfcoInv8VGKF/tbZ8b8rdbbUXaZIkRTHP2o2FjD5ct2lp49m5U8u3yWvLX34Ohi6ii+tq05zsolIDbO/82TAd58yYNmVIcQT71NPkd97ppuiZp7w2r9frTvq2QCn23c0rKbCIMfICHdjniuAkJs1R0nWKbzGwfdSQLesD9SHfrGaYbrIAWmucxpQLC9K4+yo5xI4QfKK6raqiy2ABukD/G0xr0Io76wxnu1OgMYcTGpfFqK+h9Ja158Uw3Wq81JgJTZjUto+gsXQLWQjO6YQw1tjpOgjE9dQwMDVPNxN4A+1uirNRvl0ekKpSqh9xd9GuHqFXMrVr62+lJxOpObYQMpOw+K0FtNfkhu23kHPzw0WjMGQ9los0aBg3r29mqEFI1NJfzD1dzl3CMSGZGyaSO8V+O0YFoidlguKeaU78SL96PYa+t5bwxzcYWM6Vf1p35X7w4hnoldh9Ej2e36l3ckcCe4YkKX92Ot0Rl5AMtzkV18mvWWB3oUYL3iJure7Q1gfkYNBo63xcHiI7k5U9zPJWDnRkhr9EYnAQwTKMCvoRPxmY/f2x377ozRYcz1OwOl+cdK8z39tqHnUpizYHgn6KUmyzvjgKrjGHn1gAVrGk1cQ6xJgxkLnvCGffI4yQnHGy82R2ZrC09pYaLE8uto/IOt5r17MpgMYHgMA0GCSsGAQQBgjcRAjEAMBMGCSqGSIb3DQEJFTEGBAQBAAAAMFsGCSqGSIb3DQEJFDFOHkwAewBEADMAQwBBAEMAQwA2ADMALQAyAEUAQgA0AC0ANABDADMAMgAtADkAQQAxADAALQAxADkAMAA2ADQANAAwAEIAQwBGADQAOQB9MF0GCSsGAQQBgjcRATFQHk4ATQBpAGMAcgBvAHMAbwBmAHQAIABTAG8AZgB0AHcAYQByAGUAIABLAGUAeQAgAFMAdABvAHIAYQBnAGUAIABQAHIAbwB2AGkAZABlAHIwggO/BgkqhkiG9w0BBwagggOwMIIDrAIBADCCA6UGCSqGSIb3DQEHATAcBgoqhkiG9w0BDAEDMA4ECNMEHAMR9K/9AgIH0ICCA3jFa85BmwNhXj5WHsDaYI5Sj7g6U6FnIHiiQNk8GlRiRonDGMS5voI0EotBJhMw24fx/TuJPwhqzWsVhiGacKReg07Qf0cGzP8PQOv/d/JpXu1FlW7xxBV3wbKEZ6tg4uT4sVdcet5odrq/9jmIE3MjZ9tcE14U6uDDlYDFnvsQl53dmbtHqO4w+smzpYaJCQM51HSspmX55AZ0VNUh2I25sIsHsScUE82q3h0zWzBrsMYKppVJucFf6O7CfYPDLaJw/BHdGhQy5wV83RXKFbbHz7RS3QfvXDkEdWIPJ/H2XyiK3msm1IVnL5Yto9eppzbcRjwxMgogCYTecRFCNlo/sy1e7WBn8ePWZpOvCi/knYb/tSxEVp6n0aBAlcadLqVGb8eleioRiF1N9uB4tBqdb+g5RzhWJhD1snUGcl5+3Rz8ESM3KIRlsmCk4Tsh5IQPv0VLTk32cu4fTfC9bLGdxdi/53qXHCJ4s3Hq0O2So9NQLANzPqQt7JhL75Lo033Av1A+aqzN06zuDZkL0sp3BQy84bjGYgKl713yaVhwNYPy5Spk16NBxMqNDOTGClK8/XLCifFJISmBFInaU+dCCgVnk3PgHgmCivoIXAeCdVwibEpuB0um8SEGJsqBTwRiG64QMMX5wPY2rWcouaJ9xu6wHNpaYC+EtorhOwE3IeJML80pFi9S57I8BR8KhaoJtYe2nN9Oukb6akBd/5XZQxgx1hYt8Dp1mrTvJowjHTv5up53NvySGPXqOR7610NtSUdREBbenItfwVhiUybL02Rkem/VBrfc5wt4wjNeT3FoFTquAtinDVhlB5zr2xRuxuNa4ocXuDKNS46TSIz19lPjPAFnIA/RDN9cERR1TdlwJI6tWP+5Eca+i7TkmGBYaxB5+wAMGiN0zhPutw47aW48YBRhClk+5SwGqKOuZgOtB+XFs3P1P/dKFT77iobM4TcAiqKPdJuF3+muTH0JSmdX+CW1/1l1x/c/FrBhb12rjO5GD8K67HO6k9VfgPvP47wmukwbYReLtokFPgiWNgVcbnprzx3mHuDQtcLrNnNQ6mv5LS790IrUb0Q7uOsCpnZSTqixr+Ee4XuacsWEPQMTYRtWMHnZeqPyHdhu4iFrPHS9dgfUtnLLuEtJzsVC1sJkwx9e5u7gH/F5IZkSvUqwrUFxXPMwOzAfMAcGBSsOAwIaBBTbOY5E4gIoClVXMMrJXk3gjyxQrQQU5sImp0DwWm+2eCEN6gC0blpDE3gCAgfQ"
}
"@

    $spSiteLoginData = $spSiteLoginDataJSON | ConvertFrom-Json
    Connect-PnPOnline $siteURL -ClientId $spSiteLoginData.AzureAppId -Tenant powereng0.onmicrosoft.com -CertificateBase64Encoded $spSiteLoginData.Base64Encoded
}

    $libraryName = "Documents"
    $fieldName = "KLBTestColumn"
    $fieldType = "Text" # Example: Text, Number, DateTime, Choice, Boolean, etc.

    # Add the field to the specific list (document library)
    Add-PnPField -List $libraryName -DisplayName $fieldName -InternalName $fieldName -Type $fieldType



$pwFolderName = "Active Projects\zz0123456_0000\Design\Lists"
$pwFolder = Get-PWFolders -FolderPath $pwFolderName
$pwFolderFullPath = $pwFolder.GetFullPath()

# PW Folder with documents...
$pwFolderWithDocuments = "Active Projects\zz0123456_0000\Design\Lists"
$pwFolder = Get-PWFolders -FolderPath $pwFolderWithDocuments

$pwFolder = Get-PWFolders -FolderName "Active Projects"
$customAttributeNames = [System.Collections.Generic.SortedDictionary[String,String]]::new()


$pwFolder = Get-PWFolders -FolderPath "Archive Projects\136723" -JustOne
$null = $pwFolder.GetFullPath()
$rp = Get-PWRichProjects -FolderPath $pwFolder.FullPath -JustOne -PopulateProjectProperties






$Global:FolderCount = 0
$Global:DocumentCount = 0
$Global:saveFileName = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\attribs.csv"

function WalkPWFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $pwFolder,

        [Parameter(Mandatory=$false, Position=1)]
        [Int32] $folderDepth = 0
    )

    if($null -ne $pwFolder)
    {
        $pwFolderFullPath = $pwFolder.GetFullPath()

        if(-not [String]::IsNullOrEmpty($pwFolderFullPath))
        {
            $Global:FolderCount++
            [Console]::WriteLine(("{0}{1}/{2}: {3}" -f @([String]::new(' ', $folderDepth), $Global:FolderCount, $Global:DocumentCount, $pwFolderFullPath)))
            $pwSubFolders = @()
            $result = Get-PWFoldersImmediateChildren -FolderPath $pwFolderFullPath
            if($result)
            {
                $pwSubFolders = $result
            }

            $a = 0
            while($a -lt $pwSubFolders.Length)
            {
                WalkPWFolder -pwFolder $pwSubFolders[$a] -folderDepth ($folderDepth + 1)
                $a++
            }

            $result = $pwFolder.GetFolderDocuments()
            $pwFolderDocs = @()
            if($result)
            {
                $pwFolderDocs = $result
                $Global:DocumentCount += $pwFolderDocs.Count
            }

            $a = 0
            while($a -lt $pwFolderDocs.Count)
            {
                $customAttribs = $pwFolderDocs[$a].GetCustomAttributes()
                if($null -ne $customAttribs)
                {
                    $b = 0
                    while($b -lt $customAttribs.Count)
                    {
                        $customAttribDict = $customAttribs[$b]

                        if($null -ne $customAttribDict)
                        {
                            $attribKeys = @($customAttribDict.Keys)
                            $c = 0
                            while($c -lt $attribKeys.Length)
                            {

                                if(-not $customAttributeNames.ContainsKey($attribKeys[$c]))
                                {
                                    $newType = ($customAttribDict[$attribKeys[$c]].GetType()).Name
                                    $customAttributeNames.Add($attribKeys[$c], $newType)
                                    [Console]::WriteLine(("{0}{1}: {2}/{3}" -f @([String]::new(' ', ($folderDepth + 1)),$pwFolderDocs[$a].Name,$attribKeys[$c], $newType)))
                                    $d = "" | Select-Object PWPath,AttribName,TypeName
                                    $d.PWPath = "{0}\{1}" -f @($pwFolderFullPath, $pwFolderDocs[$a].Name)
                                    $d.AttribName = $attribKeys[$c]
                                    $d.TypeName = $newType

                                    $d | Export-CSV -Append -Path $Global:saveFileName -Delimiter "`t" -NoTypeInformation
                                }
                                $c++
                            }
                        }
                        $b++
                    }
                }

                $a++
            }
        }
    }
}

# WalkPWFolder -pwFolder $pwFolder



# This is either very slow, or does not work....
# $pwDocs = Get-PWDocumentsBySearch -FolderPath $pwFolderFullPath -GetVersionsToo -GetAttributes -Verbose



$pwRootFolders = @(Get-PWFoldersImmediateChildren -Root)
$pwRootFolders.ForEach({ $_.GetFullPath() })
$pwRootFolders | ogv


$a = 0
while($a -lt $pwRootFolders.Length)
{
    if($pwRootFolders[$a].Name -ne "PW Admin Standards")
    {
        $pwFolder = Get-PWFolders -FolderID $pwRootFolders[$a].ProjectID -JustOne
        $pwFolderSubFolders = $pwFolder.GetSubFolders()
        $pwFolderDocs = $pwFolder.GetFolderDocuments() | Out-Null

    }
    $a++
}

# Get Document versions and attributes...
$pwDocs = Get-PWDocumentsBySearch -FolderID 1270073  -Verbose -GetVersionsToo -GetAttributes

$children = Get-PWFoldersImmediateChildren -FolderPath $pwFolderFullPath


$localFolder = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest"


$pwFolder = Get-PWFolders -FolderPath "Active Projects\zz0123456_0000" -JustOne -Slow
$pwFolder = Get-PWFolders -FolderPath "Active Projects\zz0123456_0000\Design\Lists" -JustOne

function GetPWDatasource
{
    $currentDS = [String]::Empty
    try
    {
        $currentDS = Get-PWCurrentDatasource -ErrorAction Stop
    }
    catch
    {

    }

    return $currentDS
}

function ConnectPW
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $pwDatasource,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $pwUserName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [SecureString] $pwPassword
    )

    $pwEnvironment = "{0}:{1}" -f @($pwServer, $pwDatasource)
    $connected = $false
    try
    {
        $connected = New-PWLogin -DatasourceName $pwEnvironment -UserName $pwUserName -Password $pwPassword -ErrorAction Stop *> $null
    }
    catch
    {

    }

    return $connected
}


ConnectTo vCenter,prod
$pwCreds = (Get-ConnectCredentials "projectwise").Credential
Import-Module pwps_dab

$pwServer = "cdc-pwdint02.powereng.com"
$pwDatasource = "pw_prod_pw01"
#$pwDatasource = "pw_prod_pw02"
#$pwDatasource = "pw_prod_dmsclosed"
#$pwDatasource = "pw_prod_acq_archive"
$pwUserName = $pwCreds.UserName
$pwPassword = $pwCreds.Password

ConnectPW -pwServer $pwServer -pwDatasource $pwDatasource -pwUserName $pwUserName -pwPassword $pwPassword


function DisconnectPW
{
    try
    {
        $null = Undo-PWLogin -ErrorAction Stop *> $null
    }
    catch
    {

    }
}

function GetPWSecurity
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $pwFolder
    )

    $me = $MyInvocation.MyCommand

    if($null -ne $pwFolder)
    {
        $sec = $pwFolder | Get-PWFolderSecurity | Where-Object { ($_.SecurityType -eq "Document") -and ($_.Workflow -eq [System.DBNull]::Value) }
    } `
    else
    {
        Write-Error ("Missing ProjectWise folder in {0}." -f @($me.Name))
    }
}

function PWGroupOrUserListToUsers
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $name,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $objType

    )

    $userList = [System.Collections.Generic.List[System.String]]::new()
    $me = $MyInvocation.MyCommand
    try
    {
        #Write-Host ("Getting members for: {0}" -f @($name))
        $members = Get-PWMembers -Name $name -Type $objType -ErrorAction Stop  3> $null
        #$members.Rows.ForEach({ Write-Host ("M: {0}`tT: {1}" -f @($_.MemberName, $_.MemberType))})


        $a = 0
        while($a -lt $members.Rows.Count)
        {
            if($members.Rows[$a].MemberType -eq "User")
            {
                $i = $userList.BinarySearch($members.Rows[$a].MemberName)
                if($i -lt 0)
                {
                    $userList.Insert(-bnot $i, $members.Rows[$a].MemberName)
                } `
                else
                {
                    # Nothing, duplicate user
                }
            } `
            elseif ($members.Rows[$a].MemberType -in @("UserList","Group"))
            {
                $userList2 = PWGroupOrUserListToUsers -name $members.Rows[$a].MemberName -objType $members.Rows[$a].MemberType
                $b = 0
                while($b -lt $userList2.Count)
                {
                    $i = $userList.BinarySearch($userList2[$b])
                    if($i -lt 0)
                    {
                        $userList.Insert(-bnot $i, $userList2[$b])
                    } `
                    else
                    {
                        # Nothing, duplicate user
                    }
                    $b++
                }
            } `
            else
            {
                Write-Warning ("Unknown member type [{0}] in {1}." -f @($members.Rows[$a].MemberType, $me.Name))
            }
            $a++
        }
    }
    catch
    {
        Write-Error ("Unable to retrieve group or user list members for {0} in {1}." -f @($name, $me.Name))
    }

    return @(, $userList)
}

function CaptureProjectWiseDataToJSON
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $localPath
    )

    $retval = [PSCustomObject]@{
        JSONData = $null
        JSONFile = $null
        PWFolder = $null
    }

    $Error.Clear()

    if([System.IO.Directory]::Exists($localPath))
    {
        $pwPath = "{0}\{1}" -f @($pwProjectPath, $projectName)
        try
        {
            # Get the associated ProjectWise folder along with all the relevant data "-Slow" ...
            Write-Host ("Getting PW Folder for {0}..." -f @($pwPath))
            $retval.PWFolder = Get-PWFolders -FolderPath $pwPath -JustOne -Slow 3> $null
        }
        catch
        {
            Write-Error ("Failed to locate ProjectWise Folder using path: {0}" -f @($pwPath))
            $retval.PWFolder = $null
        }

        if($null -ne $retval.PWFolder)
        {
            $Global:flatSets = [System.Collections.Generic.SortedDictionary[String, Object]]::new()

            # The code below looks odd, we are getting data, but returning it to $null.  The reason is,
            #    the code behind actaully populates $retval.PWFolder with the returned data.

            try
            {
                # Get a list of all the subfolders in the project
                Write-Host "Getting project subfolders..."
                $null = $retval.PWFolder.GetSubFolders()
            }
            catch
            {
                Write-Error ("Failed to get project subfolders.")
                $retval.PWFolder = $null
            }

            if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    Write-Host "Getting project document tree..."
                    $null = $retval.PWFolder.GetTreeDocuments()
                }
                catch
                {
                    Write-Error ("Failed to get project documents.")
                    $retval.PWFolder = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
            {
                #  NOTE:  Check for IsSet before GetGeneralProperties and GetCustomAttributes ....
                #     Need to know if they need to be successful before evaluting .IsSet...

                Write-Host "Getting project document properties and custom attributes..."
                # Now, populate all the attributes for the documents.
                $totalDocuments = $retval.PWFolder.TreeDocuments.Count
                $i = 0
                while(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder) -and ($i -lt $retval.PWFolder.TreeDocuments.Count))
                {
                    $pc = [float] $i / [float] $totalDocuments
                    Write-Progress -Id 1 -Activity ("Processing Document {0} of {1}" -f @(($i+1), $totalDocuments)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)
                    try
                    {
                        $null = $retval.PWFolder.TreeDocuments[$i].GetGeneralProperties()
                    }
                    catch
                    {
                        Write-Error ("Failed to retrieve general properties for {0}" -f @($retval.PWFolder.TreeDocuments[$i].FullPath))
                        $retval.PWFolder = $null
                        break
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        try
                        {
                            $null = $retval.PWFolder.TreeDocuments[$i].GetCustomAttributes()
                        }
                        catch
                        {
                            Write-Error ("Failed to retrieve custom attributes for {0}" -f @($retval.PWFolder.TreeDocuments[$i].FullPath))
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        if($retval.PWFolder.TreeDocuments[$i].IsSet)
                        {
                            try
                            {
                                $fs =  Get-PWDocumentFlatSetMembers -FolderPath $retval.PWFolder.TreeDocuments[$i].FolderPath -SetName $retval.PWFolder.TreeDocuments[$i].Name -ErrorAction Stop
                                $Global:flatSets.Add($retval.PWFolder.TreeDocuments[$i].FullPath, $fs)
                            }
                            catch
                            {
                                Write-Error ("Failed to acquire flat set: {0} from {1}." -f @($retval.PWFolder.TreeDocuments[$i].Name, $retval.PWFolder.TreeDocuments[$i].FolderPath))
                            }
                        } `
                        else
                        {
                            # Not a flatset, so nothing to do here.
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }

                    $i++
                }

                Write-Progress -Id 1 "Finished" -Completed
                if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                {
                    # Dump a copy of the project data to the local folder.
                    $retval.JSONFile = "{0}\{1}.pwdata.json" -f @($localPath, $retval.PWFolder.Name)
                    try
                    {
                        Write-Host "Converting project data to json format..."
                        $retval.JSONData = $retval.PWFolder | ConvertTo-Json -Depth 10 -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Error "Failed to convert project data structure to JSON format."
                        $retval.JSONData = $null
                        $retval.JSONFile = $null
                        $retval.PWFolder = $null
                    }

                    if(($Error.Count -eq 0) -and ($null -ne $retval.PWFolder))
                    {
                        if(-not [String]::IsNullOrEmpty($retval.JSONData))
                        {
                            try
                            {
                                Write-Host ("Saving project data to {0}..." -f @($retval.JSONFile))
                                $retval.JSONData | Set-Content -Path $retval.JSONFile -ErrorAction Stop
                            }
                            catch
                            {
                                Write-Error ("Failed to save project data to {0}." -f @($retval.JSONFile))
                                $retval.JSONData = $null
                                $retval.JSONFile = $null
                                $retval.PWFolder = $null
                            }
                        } `
                        else
                        {
                            Write-Warning "No project 'JSON' data to save."
                        }
                    } `
                    else
                    {
                        # Should have already displayed an error
                    }
                } `
                else
                {
                    # Should have already displayed an error
                }
            } `
            else
            {
                # Should have already displayed an error
            }
        } `
        else
        {
            # Should have already displayed an error.
        }
    } `
    else
    {
        Write-Error ("{0} not found.  Please provide an existing path." -f @($localPath))
    }

    return $retval
}

$localPath = "E:\PW2SP"
$projectName = "136723"
$pwProjectPath = "Archive Projects"
$sharePointRootURL = "https://powereng0.sharepoint.com"
$sharePointSiteName = "SP-GVS-ProjectWise-MigrationTest"
$documentLibraryName = "Shared Documents"
$documentLibraryFolderName = "Inactive Projects"

function NewTranslation
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $localPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $sharePointSiteName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $documentLibrayName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [String] $topFolderName
    )
}

function CalculatePathTranslations
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $localPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $sharePointSiteName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $documentLibrayName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [String] $topFolderName
    )

    <#
        If a path is too long, then any file with a path which contains the folder which was shortened needs to have a translation entry.

            For example, if "Archive Projects\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf" results in
                "ADF-C Outage Analysis" being shortened to "ADF-C Outage Anal" then any subfolder or file where "\ADF-C Outage Analysis\" exists needs to be translates to "\ADF-C Outage Anal\", not just the offending file.

        "FullPath": "Archive Projects\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf"


        C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf

        Thought process, I'll start by looping through all the TreeDocuments creating the local path and sharepoint path for each document.  This process will use any existing translations.
        If a new "path too long" is detected, then either
            1) An existing translation will be further shortened in an attempt to make it viable, or
            2) a new translation will be constructed

            Example:
                existing translations:
                    From: "DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports"
                      To: "DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysi\Blackstart Preparation\Reports"

                We discover the path C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf is too long.

                1) Any existing translations?

                2) Yes, apply existing translations:
                    from: C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf is too long.
                      to: C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysi\Blackstart Preparation\Reports\322-131.pdf is too long.

                    2a) Still to long?

                    2b) Yes, modify existing translations: Same process as creating a new translation except I start with the translation to determine which subfolder to shorten.
                        From: "DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports"
                          To: "DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analys\Blackstart Preparation\Reports"

TODO: Verify translated path will not result in a duplicate folder.

                    2c) No, jump to end

                3) No, create a new translation
                    Select the longest subfolder which does not have an existing translation

    #>
}

<#
    $pwServer = The FQDN for the ProjectWise server where the project will be exported from.
        ex: "cdc-pwdint02.powereng.com"

    $pwDataSource = The name of the ProjectWise datasource where the project is stored.
        ex: "pw_prod_pw01"

    $projectName = The name of the project to export from ProjectWise.
        ex: "136723"

    $pwProjectPath = ProjectWise path where $projectName [folder] resides.
        ex: "Archive Projects"

    $localPath = Path to local folder where the project will be exported to.
        ex: "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest"

    $sharePointRootURL = The root SharePoint Online URL where the project will be migrated to.
        ex: https://powereng0.sharepoint.com

    $sharePointSiteName = The name of the SharePoint Online site where the project will ultimate be uploaded to.
        ex: "SP-GVS-ProjectWise-MigrationTest"

    $documentLibrayName = The name of the document library on the SharePoint online site where the project will be uploaded to.
        ex: "Shared Documents"

    $documentLibraryFolderName = The name of the folder directly under $documentLibrayName where the project will be uploaded to.
        ex: "Inactive Projects"

    Example:
    t1
        -pwServer "cdc-pwdint02.powereng.com"
        -pwDatasource "pw_prod_pw01"
        -projectName "136723"
        -pwProjectPath "Archive Projects"
        -localPath "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest"
        -sharePointRootURL "https://powereng0.sharepoint.com"
        -sharePointSiteName "SP-GVS-ProjectWise-MigrationTest"
        -documentLibrayName "Shared Documents"
        -documentLibraryFolderName "Inactive Projects"

    This will result in all files and folders under CDC-PWDINT02.powereng.com:pw_prod_pw01\Documents\Archive Projects\136723 being exported to the local folder C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723, then
    the local files and folders being uploaded to https://powereng0.sharepoint.com/sites/SP-GVS-ProjectWise-MigrationTest/Shared Documents/Inactive Projects/136723

    NOTES:
        There are file path limitations imposed by both the local file system and Sharepoint Online.
        For Sharepoint Online, the following pattern is limited to 400 characters.
            sites/[SHAREPOINT_SITE_NAME]/[DOCUMENT_LIBRARY_NAME]/[TOP_FOLDER_NAME]/[DOCUMENT_NAME].[DOCUMENT_EXTENSION]
#>
function t1
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $pwDatasource,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $localPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [String] $sharePointRootURL,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=6)]
        [String] $sharePointSiteName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=7)]
        [String] $documentLibraryName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=8)]
        [String] $documentLibraryFolderName
    )

    # Not sure if I need the follow....
    $sharePointSiteName = [URI]::EscapeDataString($sharePointSiteName)
    $documentLibrayName = [URI]::EscapeDataString($documentLibrayName)
    $documentLibraryFolderName = [URI]::EscapeDataString($documentLibraryFolderName)


    <#
        $localPath = "E:\PW2SP"
        $projectName = "136723"
        $pwProjectPath = "Archive Projects"
    #>
    # Get relevant information from ProjectWise
    $pwData = CaptureProjectWiseDataToJSON -pwProjectPath $pwProjectPath -projectName $projectName -localPath $localPath
    <#
        $localPath = "E:\PW2SP"
        $projectName = "136725"
        $pwProjectPath = "Archive Projects"
        $pwData2 = CaptureProjectWiseDataToJSON -pwProjectPath $pwProjectPath -projectName $projectName -localPath $localPath
    #>


    # Build the local folder structure.
    if(($null -ne $pwData) -and ($null -ne $pwData.PWFolder) -and ($null -ne $pwData.JSONFile) -and ($null -ne $pwData.JSONData))
    {
        $translations = CalculatePathTranslations -pwData $pwData
        $Error.Clear()
        $newSubFolders = @($pwData.PWFolder.SubFolders | Sort-Object FolderDepth,FullPath | Select-Object -Unique -ExpandProperty FullPath)
        $a = 0
        while(($Error.Count -eq 0) -and ($a -lt $newSubFolders.Length))
        {
            $newPath = "{0}\{1}" -f @($localPath, $newSubFolders[$a])
            try
            {
                $null = New-Item -ItemType Directory -Path $newPath -ErrorAction Stop
            }
            catch
            {
                Write-Error ("Failed to create folder: {0}." -f @($newPath))
            }
            $a++
        }

        # Export all the files from ProjectWise to the local folder
        $totalDocuments = $retval.PWFolder.TreeDocuments.Count
        $a = 0
        while(($Error.Count -eq 0) -and ($a -lt $pwData.PWFolder.TreeDocuments.Count))
        {
            # Strip the file name and extension off the path.
            $newDocPath = [System.IO.Path]::GetDirectoryName(("{0}\{1}" -f @($localPath, $pwData.PWFolder.TreeDocuments[$a].FullPath)))

            try
            {
                $null = $pwData.PWFolder.TreeDocuments[$a].CopyOut($newDocPath)
            }
            catch
            {
                Write-Error ("Failed to export {0} to {1}." -f @($pwData.PWFolder.TreeDocuments[$a].Name, $newDocPath))
            }

            $a++
            $pc = [float] $a / [float] $totalDocuments
            Write-Progress -Id 1 -Activity ("Exporting Document {0} of {1}" -f @($a, $totalDocuments)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)
        }

        Write-Progress -Id 1 "Finished" -Completed
    } `
    else
    {
        # Already displayed an error.
    }
}


# Add the project properties to sharepoint...
$a = 0
while($a -lt $projectProps.Length)
{
    if(-not $projectProps[$a].Ignore)
    {
        $newPropValues = @{
            List="Documents"
            DisplayName = $projectProps[$a].DisplayName
            InternalName = $projectProps[$a].InternalName
            Type = $projectProps[$a].Type
        }
        if($projectProps[$a].Type -eq "Choice")
        {
            $newPropValues.Add("Choices", $projectProps[$a].Choices)
        }

        Add-PnpField @newPropValues
    }
    $a++
}

while($a -lt $spData.documentFields.Length)
{
    $field = $spDocumentFields | Where-Object { $_.InternalName -eq $spData.documentFields[$a].InternalName }
    if($null -ne $field)
    {
        Write-Host ("Removing: {0}" -f @($field.Title))
        $null = Remove-PnPField -Identity $field -Force
    }
    $a++
}

function WalkPathsDict
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [System.Object] $fromNode
    )
    $totalDocs = 0

    $keys = @($fromNode.Keys)
    $a = 0
    while($a -lt $keys.Length)
    {
        $totalDocs += $fromNode[$keys[$a]].Documents.Count

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            @($fromNode[$keys[$a]].Children).ForEach({
                $totalDocs += (WalkPathsDict -fromNode $_)
            })
        }

        $a++
    }

    return $totalDocs
}

function FindDocGUIDInPathsDict
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [System.Object] $fromNode,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [System.Guid] $docGuid

    )

    $keys = @($fromNode.Keys)
    $a = 0
    $foundDoc = $null
    while(($null -eq $foundDoc) -and ($a -lt $keys.Length))
    {
        $foundDoc = $fromNode[$keys[$a]].Documents | Where-Object { $_.DocumentGUID -eq $docGuid }

        if($null -eq $foundDoc)
        {
            if($null -ne $fromNode[$keys[$a]].Children)
            {
                $foundDoc = FindDocGUIDInPathsDict -fromNode $fromNode[$keys[$a]].Children -docGuid $docGuid
            }
        }

        $a++
    }

    return  $foundDoc
}


function GetAllPathsFromDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $parentPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[String]] $allTestPaths
    )

    <#
    $fromNode = $testPaths
    $allTestPaths = [System.Collections.Generic.List[String]]::new()
    $parentPath = "" # "sites/{0}/{1}/{2}/{3}" -f @($spData.ConnectionInformation.SharePointSiteName, $spData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    GetAllPathsFromDictionary -fromNode $testPaths -parentPath $parentPath -allTestPaths $allTestPaths
    $allTestPaths = @($allTestPaths | Sort-Object Length -Descending)
    $allTestPaths | Set-Clipboard
    #>
    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + "/" + $keys[$a]
        $allTestPaths.Add($pathToTest)

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            @($fromNode[$keys[$a]].Children).ForEach({
                GetAllPathsFromDictionary -fromNode $_ -parentPath $pathToTest -allTestPaths $allTestPaths
            })
        }
        $a++
    }
}

function BuildPathsDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $parentPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $allTestPaths
    )

    <#
    $fromNode = $testPaths

    $allTestPaths = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()
    $parentPath = "" # "sites/{0}/{1}/{2}/{3}" -f @($spData.ConnectionInformation.SharePointSiteName, $spData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    BuildPathsDictionary -fromNode $testPaths -parentPath $parentPath -allTestPaths $allTestPaths

    $allTestPaths = @($allTestPaths | Sort-Object Length -Descending)
    $allTestPaths | Set-Clipboard
    #>
    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $keys[$a]

        if($null -ne $fromNode[$keys[$a]].DocumentGUID)
        {
            $pp = @($pathToTest -split "/")
            $allTestPaths.Add($fromNode[$keys[$a]].DocumentGUID.Guid, $pp)
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            @($fromNode[$keys[$a]].Children).ForEach({
                BuildPathsDictionary -fromNode $_ -parentPath ($pathToTest + "/") -allTestPaths $allTestPaths
            })
        }
        $a++
    }
}

function GetPathsTooLongFromDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $parentPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[String]] $pathsTooLong,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [int] $maxLength

    )

    <#
    $fromNode = $testPaths
    $pathsTooLong = [System.Collections.Generic.List[String]]::new()
    $parentPath = "sites/{0}/{1}/{2}/{3}" -f @($spData.ConnectionInformation.SharePointSiteName, $spData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    GetPathsTooLongFromDictionary -fromNode $testPaths -parentPath $parentPath -pathsTooLong $pathsTooLong -maxLength 200
    #>
    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $keys[$a]

        if($pathToTest.Length -gt $maxLength)
        {
            $pathsTooLong.Add($pathToTest)
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            @($fromNode[$keys[$a]].Children).ForEach({
                GetPathsTooLongFromDictionary -fromNode $_ -parentPath ($pathToTest + "/") -pathsTooLong $pathsTooLong -maxLength $maxLength
            })
        }
        $a++
    }
}

function t2
{
    <#
        In the URL: https://powereng0.sharepoint.com/sites/SP-GVS-ProjectWise-MigrationTest/Shared Documents/Inactive Projects/139279/Cin Dr/Site Plan/Manhole Numbering sequence - Potomac Testing 4-17-15.pdf
        SharePoint imposes a 400 character length limit to the following part of the URL: sites/SP-GVS-ProjectWise-MigrationTest/Shared Documents/Inactive Projects/139279/Cin Dr/Site Plan/Manhole Numbering sequence - Potomac Testing 4-17-15.pdf

        To avoid these issues, I'm going to build a sorted dictionary as follows:
            Each node will have the following properties:
                DocumentGuid
                ParentNode
                OriginalName
                Children
            If a node has a populated DocumentGuid then it references a DocumentGuid from ProjectWise.

            Given the following document path: DocFolder1/SubFolder1/LongFolder2/SubFolder3/DocumentName.Ext I'll construct the following dictionary:

            [DocFolder1]
                [SubFolder1]
                    [LongFolder2]
                        [SubFolder3]
                            [DocumentName.Ext]
                                [DocumentGuid]

        After the dictionary is constructed, assuming I have found paths which are too long, then I'll use the dictionary and list of paths which are too long to determine what to shorten and by how much.

        Let's say we have the following document path which is artificially too long: DocFolder1/SubFolder1/LongFolder2/SubFolder3/DocumentName.Ext

        First, I'll determine how many characters have to be dropped from the path to make the path viable.  For this example, let's say I need to remove 3 characters.

        Next, split the document path on "/"

            path pieces:
                DocFolder1
                SubFolder1
                LongFolder2
                SubFolder3
                DocumentName.Ext

            create another "original" version:
                DocFolder1
                SubFolder1
                LongFolder2
                SubFolder3
                DocumentName.Ext

        I'll preform the following loop however many times are required to viably shorten the path (3 for this example)

            Find the piece of the split path which is the longest (using only the document name without its extension).

                DocumentName   (* have to track this)

            Reduce the name by 1 and check for uniqueness at this level.

                DocumentNam

            While there exists a node with a matching name:
                Remove X character(s) and add a counter: X starts at 2 and increments if no unique names can be found after trying all 0..9, A-Z as a counter.
                    ex:
                        DocumentNa0.ext
                        DocumentNa1.ext
                        DocumentNa2.ext
                        .
                        .
                        .
                        DocumentNaZ.ext

            *** If a new name cannot be found, throw an exception.

            path pieces:
                DocFolder1
                SubFolder1
                LongFolder2
                SubFolder3
                DocumentNam.ext

        Repeat...

            Find the piece of the split path which is the longest (using only the document name without its extension).

                LongFolder2

            Reduce the name by 1 and check for uniqueness at this level.

                LongFolder

            While there exists a node with a matching name:
                Remove X character(s) and add a counter: X starts at 2 and increments if no unique names can be found after trying all 0..9, A-Z as a counter.
                    ex:
                        LongFolde0.ext
                        LongFolde1.ext
                        LongFolde2.ext
                        .
                        .
                        .
                        LongFoldeZ.ext

            *** If a new name cannot be found, throw an exception.

            path pieces:
                DocFolder1
                SubFolder1
                LongFolder
                SubFolder3
                DocumentNam.ext

            Repeat...

            Find the piece of the split path which is the longest (using only the document name without its extension).

                DocumentNam

            Reduce the name by 1 and check for uniqueness at this level.

                DocumentNa

            While there exists a node with a matching name:
                Remove X character(s) and add a counter: X starts at 2 and increments if no unique names can be found after trying all 0..9, A-Z as a counter.
                    ex:
                        DocumentN0.ext
                        DocumentN1.ext
                        DocumentN2.ext
                        .
                        .
                        .
                        DocumentNZ.ext

            *** If a new name cannot be found, throw an exception.

            path pieces:
                DocFolder1
                SubFolder1
                LongFolder
                SubFolder3
                DocumentNa.ext

            Path is 3 characters shorter.

            Apply the changes to the dictionary:

            $a = 0
            $i = $testPaths
            while($a -lt $pathPieces.Length)
            {
                if($originalPieces[$a] -ne $pathPieces[$a])
                {
                    $i.Add($pathPieces[$a], $i[$originalPieces[$a]])    # Copy the children of the original node to the new node
                    $i.Remove($originalPieces[$a])                      # Remove the old node
                }

                # Now point to the new child dictionary
                $i = $i[$pathPieces[$a]]
                $a++
            }



    #>
    $treeDocGUIDToPaths = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()
    $spSiteURI = "{0}/sites/{1}/" -f @($spData.ConnectionInformation.SharePointRootURL, $spData.ConnectionInformation.SharePointSiteName)
    $fixedSPPath = "{0}{1}/{2}/{3}/" -f @($spSiteURI, $spData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    $spLimitPrefix = "sites/{0}/{1}/{2}/{3}/" -f @($spData.ConnectionInformation.SharePointSiteName, $spData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    $spLimitPrefixLength = $spLimitPrefix.Length

    # Keep track of any document paths which are too long.
    $pathsTooLong = [System.Collections.Generic.List[String]]::new()

    $testPaths = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()

    $Error.Clear()
    $a = 0
    while(($Error.Count -eq 0) -and ($a -lt $pwData.PWFolder.TreeDocuments.Count))
    {
        $td = $pwData.PWFolder.TreeDocuments[$a]
        $d = "" | Select-Object SPPath, SPFolder, LPath, LocalFolder, Exported, Uploaded
        $d.SPPath = SharePointPathFromPWTreeDocument -pwTreeDocument $td -projectName $projectName -pwProjectPath $pwProjectPath -sharePointRootURL $spData.ConnectionInformation.SharePointRootURL -sharePointSiteName $spData.ConnectionInformation.SharePointSiteName -documentLibrayName $spData.ConnectionInformation.DocumentLibraryName -documentLibraryFolderName $documentLibraryFolderName
        $d.LPath = LocalPathFromPWTreeDocument -pwTreeDocument $td -projectName $projectName -pwProjectPath $pwProjectPath -localPath $localPath
        $docNameURI = "/{0}" -f @($td.FileName)
        if($false)
        {
            $docNameURI = "/{0}" -f @([URI]::EscapeDataString($td.FileName))
        }

        if($d.SPPath -match ("^({0})(.*)({1})$" -f @([Regex]::Escape($spSiteURI), [Regex]::Escape($docNameURI))))
        {
            $d.SPFolder = $Matches[2]
            if($d.LPath -match ("^(.*)\\{0}$" -f @([Regex]::Escape($td.FileName))))
            {
                $d.LocalFolder = $Matches[1]

                $d.Exported = $false
                $d.Uploaded = $false

                $docPath = $d.SPPath.Replace($fixedSPPath, "")

                <#
                if(($spLimitPrefixLength + $docPath.Length + 1) -gt $MAX_SP_DOC_PATH_LEN)
                {
                    $pathsTooLong.Add($docPath)
                }
                #>
                $docPathParts = $docPath -split "/"

                $i = $testPaths
                $b = 0
                while($b -lt $docPathParts.Length)
                {
                    if(-not $i.ContainsKey($docPathParts[$b]))
                    {
                        $j = "" | Select-Object OriginalName, ParentNode, Children, DocumentGUID
                        $j.Children = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
                        $j.ParentNode = $i
                        $j.OriginalName = $docPathParts[$b]
                        if($b -eq ($docPathParts.Length - 1))
                        {
                            $j.DocumentGUID = $td.DocumentGUID
                        }
                        $i.Add($docPathParts[$b], $j)
                    } `
                    else
                    {
                        # Nothing, already have a branch for $docPathParts[$b]
                    }

                    $i = $i[$docPathParts[$b]].Children

                    $b++
                }
            } `
            else
            {
                Write-Error ("Faulty local path for {0}" -f @($td.DocumentGUID))
            }
        } `
        else
        {
            Write-Error ("Faulty Sharepoint path for {0}" -f @($td.DocumentGUID))
        }

        $treeDocGUIDToPaths.Add($td.DocumentGUID, $d)
        $a++
    }




    $COUNTER_CHARACTERS = @("0".."9") + @("A".."Z")
    $pathsTooLong = [System.Collections.Generic.List[String]]::new()
    # $pathsTooLong | Set-Clipboard
    GetPathsTooLongFromDictionary -fromNode $testPaths -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
    $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending)
    # $pathsTooLong is now an array....


    $Error.Clear()
    $pass = 0
    while(($Error.Count -eq 0) -and ($pathsTooLong.Length -gt 0))
    {
        $pass++
        $originalPathPieces = $pathsTooLong[0] -split "/"

        if(($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength))
        {
            $pathPieces = $pathsTooLong[0] -split "/"
            $longestPiece = $pathPieces | Sort-Object Length -Descending | Select-Object -First 1
            $longestPieceIdx = $pathPieces.IndexOf($longestPiece)
            $lpMinLength = 2

            $node = $testPaths
            $c = 0
            while(($Error.Count -eq 0) -and ($c -lt $longestPieceIdx))
            {
                if($node.ContainsKey($originalPathPieces[$c]))
                {
                    $node = $node[$originalPathPieces[$c]].Children
                } `
                else
                {
                    Write-Error ("Missing node for {0}" -f @($originalPathPieces[$c]))
                }
                $c++
            }

            $fi = $null

            # Is the longest piece the file name??
            if($longestPieceIdx -eq ($pathPieces.Length - 1))
            {
                # This is the file name...
                $fi = [System.IO.FileInfo]::new($longestPiece)
                $longestPiece = $fi.BaseName
                $lpMinLength += $fi.Extension.Length
            } `
            else
            {
                # Nothing....
            }

            $originalLP = $longestPiece

            # When $x -eq 0 the script first removes leading and trailing spaces from the name and replaces all double spaces with single spaces.
            $x = 0

            # Start at the first counter character if we need it...
            $i = 0

            do {
                if($x -eq 0)
                {
                    $longestPiece = $longestPiece.Trim()
                    while($longestPiece -match "  ")
                    {
                        $longestPiece = $longestPiece.Replace("  ", " ")
                    }
                    $x++
                } `
                elseif($x -gt 0)
                {
                    $longestPiece = $originalLP.SubString(0, $originalLP.Length - $x)
                    if($x -gt 1)
                    {
                        $longestPiece += $COUNTER_CHARACTERS[$i]
                        $i++
                        if($i -eq $COUNTER_CHARACTERS.Length)
                        {
                            $i = 0
                            $x++
                        }
                    } `
                    else
                    {
                        $x++
                    }
                }

                if($x -ge ($originalLP.Length - 3))
                {
                    Write-Error ("Unable to shorten {0} enough.`r`n`tOffending piece: {1}" -f @($pathsTooLong[0], $originalLP))
                } `
                else
                {
                    if($null -ne $fi)
                    {
                        $longestPiece += $fi.Extension
                    } `
                    else
                    {
                        # Nothing, don't add a non-existant extension...
                    }
                }
            } while(($Error.Count -eq 0) -and ($x -lt ($originalLP.Length - 3)) -and ($i -lt $COUNTER_CHARACTERS.Length) -and ($longestPiece.Length -gt $lpMinLength) -and ($node.ContainsKey($longestPiece)))

            # Found a substitute name...
            if($Error.Count -eq 0)
            {
                $pathPieces[$longestPieceIdx] = $longestPiece
                $pathsTooLong[0] = $pathPieces -join "/"

                if($node.ContainsKey($originalPathPieces[$longestPieceIdx]))
                {
                    Write-Host ("Adding modified node: {0}..." -f @($longestPiece))
                    try
                    {
                        $node.Add($longestPiece, $node[$originalPathPieces[$longestPieceIdx]])
                    }
                    catch
                    {
                        Write-Error ("Failed to add modified node: {0}..." -f @($longestPiece))
                    }

                    Write-Host ("Removing 'old' node: {0}..." -f @($originalPathPieces[$longestPieceIdx]))

                    try
                    {
                        $null = $node.Remove($originalPathPieces[$longestPieceIdx])
                    }
                    catch
                    {
                        Write-Error ("Failed to remove 'old' node: {0}..." -f @($originalPathPieces[$longestPieceIdx]))
                    }

                    if($null -eq $fi)
                    {
                        # If this was not a file node, then rebuild the list of paths which are too long...
                        $pathsTooLong = [System.Collections.Generic.List[String]]::new()
                        GetPathsTooLongFromDictionary -fromNode $testPaths -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
                    }
                    # $node = $node[$originalPathPieces[$c]].Children
                } `
                else
                {
                    Write-Error ("Missing node for {0}" -f @($originalPathPieces[$c]))
                }
                # Sort $pathsTooLong, putting the longest one on top and removing any paths which are now viable....
                $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending | Where-Object { ($_.Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)})

                # ($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)
            } `
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            Write-Error ("Why is {0} in the list of paths too long? Length={1}" -f @($pathsTooLong[0], $pathsTooLong[0].Length))
        }
<#
        $pathsTooLong | Set-Clipboard
#>
Write-Host ("After pass: {0}, Too long: {1}" -f @($pass, $pathsTooLong.Length))
    }



<#
    Add project top level folder "136723" here along with project properties.


#>



function ExportPW2SP
{
    $PSStyle.Progress.View = 'Minimal'
    $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
    $Error.Clear()
    $totalDocuments = $pwData.PWFolder.TreeDocuments.Count
    $sw = [System.Diagnostics.Stopwatch]::new()
    $sw.Start()
    $a = 0
    while(($Error.Count -eq 0) -and ($a -lt $pwData.PWFolder.TreeDocuments.Count))
    {
        $pc = [float] $a / [float] $totalDocuments
        $status = "{0} of {1} | {2,7:P2} Complete" -f @($a, $totalDocuments, $pc)
        if($a -gt 0)
        {
            $elapsedTicks = $sw.ElapsedTicks
            $ticksPerItem = $elapsedTicks / ($a + 1)
            $totalETATicks = $ticksPerItem * $totalDocuments
            $remainingETATicks = $totalETATicks - $elapsedTicks
            $etaTS = [TimeSpan]::new($remainingETATicks)
            $etaDT = [DateTime]::Now.Add($etaTS)

            $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @($a, $totalDocuments, $pc, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))
        }
        Write-Progress -Id 1 -Activity "Exporting/Uploading..." -Status $status -PercentComplete ($pc * 100)
        $td = $pwData.PWFolder.TreeDocuments[$a]

        if($treeDocGUIDToPaths.ContainsKey($td.DocumentGUID))
        {
            if(-not $treeDocGUIDToPaths[$td.DocumentGUID].Exported)
            {
                Write-Progress -Id 2 -Activity "Exporting..." -Status ("{0} [{1:N0}]..." -f @($td.FileName, $td.FileSize)) -PercentComplete 0
                try
                {
                    $localFile = $td.CopyOut($treeDocGUIDToPaths[$td.DocumentGUID].LocalFolder)
                    if($localFile -eq $treeDocGUIDToPaths[$td.DocumentGUID].LPath)
                    {
                        $treeDocGUIDToPaths[$td.DocumentGUID].Exported = $true
                    } `
                    else
                    {
                        Write-Error ("ProjectWise file {0} was copied out to {1}.  Was expecting {2}." -f @($td.FullPath, $localFile, $treeDocGUIDToPaths[$td.DocumentGUID].LPath))
                    }
                }
                catch
                {
                    Write-Error ("Failed to export {0} to {1}." -f @($td.FullPath, $treeDocGUIDToPaths[$td.DocumentGUID].LPath))
                }
                Write-Progress -Id 2 -Activity "Exporting..." -Status ("{0} [{1:N0}]..." -f @($td.FileName, $td.FileSize)) -PercentComplete 100
            } `
            else
            {
                # Nothing, already exported the file from projectwise...
            }


            if($Error.Count -eq 0)
            {
                if($treeDocGUIDToPaths[$td.DocumentGUID].Exported)
                {
                    if(-not $treeDocGUIDToPaths[$td.DocumentGUID].Uploaded)
                    {

                        <#
                            Check for and add any missing document properties here.
                        #>
                        $spdocValues = @{
                            Created = $td.CreateDate
                            Modified = $td.FileUpdateDate
                        }

                        Write-Progress -Id 3 -Activity "Uploading..." -Status ("{0} [{1:N0}]..." -f @($td.FullPath, $td.FileSize)) -PercentComplete 0
                        try
                        {
                            $spFile = Add-PnPFile -Path $treeDocGUIDToPaths[$td.DocumentGUID].LPath -Folder $treeDocGUIDToPaths[$td.DocumentGUID].SPFolder -Values $spdocValues -ErrorAction Stop
                            $treeDocGUIDToPaths[$td.DocumentGUID].Uploaded = $true
                        }
                        catch
                        {
                            Write-Error ("Failed to upload {0} to {1}." -f @($treeDocGUIDToPaths[$td.DocumentGUID].LPath, $treeDocGUIDToPaths[$td.DocumentGUID].SPFolder))
                        }
                        Write-Progress -Id 3 -Activity "Uploading..." -Status ("{0} [{1:N0}]..." -f @($td.FullPath, $td.FileSize)) -PercentComplete 100
                    } `
                    else
                    {
                        # Nothing, already uploaded...
                    }
                } `
                else
                {
                    # Nothing already displayed an error...
                }
            } `
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            Write-Error ("Missing tree document paths for {0}." -f @($td.DocumentGUID))
        }

        $a++
    }
    Write-Progress -Id 2 -Completed
    Write-Progress -Id 1 -Completed
}

function t3
{
    $pathParts = $viablePathsDict[$pwData.PWFolder.TreeDocuments[1000].DocumentGUID]

    $viablePath = $pathParts -join "/"
    $originalPathParts = [System.Collections.Generic.List[String]]::new()
    $a = 0
    $i = $pathDict
    while($a -lt $pathParts.Length)
    {
        if($i.ContainsKey($pathParts[$a]))
        {
            $originalPathParts.Add($i[$pathParts[$a]].OriginalName)
            $i = $i[$pathParts[$a]].Children
        } `
        else
        {
            Write-Error ("Missing path dictionary node for {0} in {1}." -f @($pathParts[$a], $viablePath))
        }
        $a++
    }

    $originalPath = $originalPathParts -join "/"

}

function RevertToOriginal
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode
    )

    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $originalName = $fromNode[$keys[$a]].OriginalName
        if($originalName -ne $keys[$a])
        {
            # Write-Host ("Reverting [{0}] to [{1}]" -f @($keys[$a], $originalName))
            # Re-add the the node with the original name...
            $fromNode.Add($originalName, $fromNode[$keys[$a]])

            # Remove the node with the old name.
            $null = $fromNode.Remove($keys[$a])
        } `
        else
        {
            # Nothing, no need to revert an unchanged node.
        }

        # Now revert all of the children's children...
        @($fromNode[$originalName].Children).ForEach({
            RevertToOriginal -fromNode $_
        })

        $a++
    }
}

function ExportPWFoldersToLocal
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $pwFolder,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $localFolder,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32] $depth = 0
    )

    $haveError = $false
    $me = $MyInvocation.MyCommand

    if([System.IO.Directory]::Exists($localFolder))
    {
        $existingFFs = @()
        try
        {
            $existingFFs = @(Get-ChildItem -Path $localFolder -ErrorAction Stop)
            if($existingFFs.Length -eq 0)
            {
                if($null -ne $pwFolder)
                {
                    $pwFolderFullPath = $pwFolder.GetFullPath()

                    if(-not [String]::IsNullOrEmpty($pwFolderFullPath))
                    {
                        $pwSubFolders = @()
                        $result = Get-PWFoldersImmediateChildren -FolderPath $pwFolderFullPath
                        if($result)
                        {
                            $pwSubFolders = $result

                            $a = 0
                            while((-not $haveError) -and ($a -lt $pwSubFolders.Length))
                            {
                                try
                                {
                                    $newFolder = New-item -ItemType Directory -Path $localFolder -Name $pwSubFolders[$a].Name -ErrorAction Stop
                                    ExportPWFoldersToLocal -pwFolder $pwSubFolders[$a] -localFolder $newFolder.FullName -depth ($depth+1)
                                }
                                catch
                                {
                                    Write-Error ("Failed to create folder {0} under {1} in {2}." -f @($pwSubFolders[$a].Name, $localFolder, $me.Name))
                                    $haveError = $true
                                }

                                $a++
                            }
                        } `
                        else
                        {
                            # Nothing, no subfolders...
                        }

                        if(-not $haveError)
                        {
                            $exportData = ExportPWFolder2Local -pwFolder $pwFolder -localFolder $localFolder
                            $haveError = $exportData.Status -eq "Error"
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        Write-Error ("Unable to determine full ProjectWise path for folder {0} in {1}." -f @($pwFolder.Name, $me.Name))
                    }
                } `
                else
                {
                    Write-Error ("Missing ProjectWise folder in {0}." -f @($me.Name))
                }
            } `
            else
            {
                Write-Error ("Local folder {0} is not empty in {1}." -f @($localFolder, $me.Name))
            }
        }
        catch
        {
            Write-Error ("Unable to get child items from {0} in {1}." -f @($localFolder, $me.Name))
        }
    } `
    else
    {
        Write-Error ("{0} does not exist in {1}." -f @($localFolder, $me.Name))
    }
}

$pwFolder = Get-PWFolders -FolderPath "Active Projects\zz0123456_0000" -JustOne
$pwFolder = Get-PWFolders -FolderPath "Active Projects\zz0123456_0000\Transmittals" -JustOne

ExportPWFoldersToLocal -pwFolder $pwFolder -localFolder "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest2"

<#
    ExportPWFolder2LocalFolder exports documents from a ProjectWise folder to a local folder.
        It does not export nested folders and documents.
#>
function ExportPWFolder2Local
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $pwFolder,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $localFolder
    )

    $me = $MyInvocation.MyCommand
    $exportData = [PSCustomObject]@{
        Status = "NotStarted"
        ProjectWiseFullPath = $pwFolderFullPath
        ExportedFiles = [System.Collections.Generic.List[System.Object]]::new()
    }

    if([System.IO.Directory]::Exists($localFolder))
    {
        $existingFFs = @()
#        try
#        {
            # $existingFFs = @(Get-ChildItem -Path $localFolder -ErrorAction Stop)
            $existingFFs = @()
            if($existingFFs.Length -eq 0)
            {
                if($null -ne $pwFolder)
                {
                    $pwFolderFullPath = $pwFolder.GetFullPath()

                    if(-not [String]::IsNullOrEmpty($pwFolderFullPath))
                    {
                        Write-Host ("Exporting {0} to {1}..." -f @($pwFolderFullPath, $localFolder))
                        $exportedFiles = Export-PWDocuments -OutputFolder $localFolder -ProjectWiseFolder $pwFolderFullPath -ExportVersions -JustOneFolder

                        if($null -ne $exportedFiles)
                        {
                            $a = 0
                            while($a -lt $exportedFiles.Length)
                            {
                                if($exportedFiles[$a].IsSet)
                                {
                                    #  Need to flesh this out...
                                    #  Talk to Austin about Document Sets in SharePoint....
                                } `
                                else
                                {
                                    # Create a new object to track this exported file.
                                    $d = [PSCustomObject]@{
                                        LocalFile = $exportedFiles[$a].CopiedOutLocalFileName
                                        FileName = $exportedFiles[$a].FileName
                                        VersionSequence = $exportedFiles[$a].VersionSequence
                                        CustomAttributes = [System.Collections.Generic.List[System.Object]]::new()
                                    }
                                    if($d.LocalFile.StartsWith("\\?\"))
                                    {
                                        $d.LocalFile = $d.LocalFile.Replace("\\?\","")
                                    } `
                                    else
                                    {
                                        # Nothing, leave $d.LocalFile as is...
                                    }

                                    # Get the custom attributes for this document...
                                    $customAttribs = $exportedFiles[$a].GetCustomAttributes()
                                    if($null -ne $customAttribs)
                                    {
                                        $b = 0
                                        while($b -lt $customAttribs.Count)
                                        {
                                            $customAttribDict = $customAttribs[$b]

                                            if($null -ne $customAttribDict)
                                            {
                                                $attribKeys = @($customAttribDict.Keys)
                                                $c = 0
                                                while($c -lt $attribKeys.Length)
                                                {
                                                    if(-not [String]::IsNullOrEmpty($customAttribDict[$attribKeys[$c]]))
                                                    {
                                                        $o = [PSCustomObject]@{
                                                            Attribute = $attribKeys[$c]
                                                            Value = $customAttribDict[$attribKeys[$c]]
                                                        }
                                                        $d.CustomAttributes.Add($o)
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, not tracking empty attributes.
                                                    }

                                                    $c++
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, no custom attributes.
                                            }
                                            $b++
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, no custom attributes for the file
                                    }
                                    $exportData.ExportedFiles.Add($d)
                                }

                                $a++
                            }
                            $exportData.Status = "Exported"
                        } `
                        else
                        {
                            Write-Warning ("No files exported for {0} in {1}." -f @($pwFolderFullPath, $me.Name))
                            $exportData.Status = "ZeroFiles"
                        }
                        $exportFileResultsFile = "{0}\exportResults.json" -f @($localFolder)

                        try
                        {
                            $exportJSON = $exportData | ConvertTo-Json -Depth 10 -ErrorAction Stop

                            try
                            {
                                $exportJSON | Set-Content -Path $exportFileResultsFile -ErrorAction Stop
                            }
                            catch
                            {
                                Write-Error ("Failed to save export data to {0} in {1}." -f @($exportFileResultsFile, $me.Name))
                            }
                        }
                        catch
                        {
                            Write-Error ("Failed to convert export data to JSON format in {0}." -f @($me.Name))
                        }
                    } `
                    else
                    {
                        Write-Error ("Unable to determine full ProjectWise path for folder {0} in {1}." -f @($pwFolder.Name, $me.Name))
                    }
                } `
                else
                {
                    Write-Error ("Missing ProjectWise folder in {0}." -f @($me.Name))
                }
            } `
            else
            {
                Write-Error ("Local folder {0} is not empty in {1}." -f @($localFolder, $me.Name))
            }
#        }
#        catch
#        {
#            Write-Error ("Unable to get child items from {0} in {1}." -f @($localFolder, $me.Name))
#        }

    } `
    else
    {
        Write-Error ("{0} does not exist in {1}." -f @($localFolder, $me.Name))
    }
}


$exportFileResultsFile = "{0}\exportResults.json"
$result = Export-PWDocuments -OutputFolder $localFolder -ProjectWiseFolder $pwFolderFullPath -ExportVersions -JustOneFolder




$result2 = Export-PWAccessControlToExcel -InputFolder $pwFolderFullPath -ExportFolder $localFolder -ExportFileName 'MyProjectAccessControl' -ExportFileExtension 'csv'


$tooManyPaths = [System.Collections.Generic.List[System.Object]]::new()

$projects = Import-CSV -Delimiter "`t" -Path .\PW2SP\projects.csv

$a = 0
while($a -lt $projects.Length)
{
    if([String]::IsNullOrEmpty($projects[$a].PWPath))
    {
        $projectName = $projects[$a].ProjectId
        $Error.Clear()
        $isError = $false
        try
        {
            Write-Host ("Checking for {0}..." -f @($projectName))
            $pwFolders = @(Get-PWFolders -FolderName $projectName -ErrorAction Stop)
        }
        catch
        {
            $isError = $true
        }

        if(-not $isError)
        {
            if($pwFolders.Length -eq 0)
            {
                if($projects[$a].ProjectId.TrimStart("0") -ne $projectName)
                {
                    $projectName = $projects[$a].ProjectId.TrimStart("0")
                    $Error.Clear()
                    $isError = $false
                    try
                    {
                        Write-Host ("Checking for {0}..." -f @($projectName))
                        $pwFolders = @(Get-PWFolders -FolderName $projectName -ErrorAction Stop)
                    }
                    catch
                    {
                        $isError = $true
                    }
                }
            }
        }

        if(-not $isError)
        {
            if($pwFolders.Length -eq 1)
            {
                $projects[$a].PWDataSource = $PWDatasourceName
                $projects[$a].PWPath = $pwFolders[0].GetFullPath()

                Write-Host ("Found: {0} at {1}:{2}" -f @($projectName, $projects[$a].PWDataSource, $projects[$a].PWPath))
            } `
            elseif ($pwFolders.Length -gt 1)
            {
                $pwFolders.ForEach({
                    $null = $_.GetFullPath()
                })

                $b = 0
                $found = $false
                while((-not $found) -and ($b -lt $pwFolders.Length))
                {
                    $pwPath = $pwFolders[$b].FullPath
                    $pathSplit = $pwPath.Split([System.IO.Path]::DirectorySeparatorChar)
                    if($pathSplit.Length -ge 2)
                    {
                        if($pathSplit[0] -eq $projectName)
                        {
                            $found = $true
                        } `
                        elseif($pathSplit[1] -eq $projectName)
                        {
                            $found = $true
                        }

                        if($found)
                        {
                            $projects[$a].PWDataSource = $PWDatasourceName
                            $projects[$a].PWPath = $pwPath
                            Write-Host -ForegroundColor Green ("Found: {0} at {1}:{2}" -f @($projectName, $projects[$a].PWDataSource, $projects[$a].PWPath))

                            break
                        }
                    }

                    $b++
                }

                if(-not $found)
                {
                    Write-Host -ForegroundColor Red ("Too many PW folders ({0}) for {1}." -f @($pwFolders.Length, $projectName))
                    $pwFolders.ForEach({
                        $d = "" | Select-Object ProjectName, PWDataSource, PWPath
                        $d.ProjectName = $projectName
                        $d.PWDataSource = $PWDatasourceName
                        $d.PWPath = $_.FullPath
                        $tooManyPaths.Add($d)
                        Write-Host -ForegroundColor Red ("Found: {0} at {1}:{2}" -f @($projectName, $d.PWDataSource, $d.PWPath))
                    })
                }
            } `
            elseif($pwFolders.Length -eq 0)
            {

            }
        }
    }
    $a++
}


# $projects | ConvertTo-CSV -Delimiter "`t" | Set-Clipboard
# $tooManyPaths | ConvertTo-CSV -Delimiter "`t" | Set-Clipboard


function t4
{
    $list = Get-PnPList -Identity $spData.ConnectionInformation.DocumentLibraryName
    $docSetType = Get-PnPContentType -List $list -Identity "Document Set"
    $ds = Add-PnPDocumentSet -List $list -Folder "Documents" -Name "Test1" -ContentType $docSetType

    $folder = Get-PnPFolder -
    Add-PnPDocumentSet -List $list -ContentType "Document Set" -Name "Test" -Folder "Shared Documents/Inactive Projects"


}


$fedProjectNames = @(
    "119289",
    "119422",
    "119888",
    "120216",
    "120334",
    "120837",
    "121760",
    "121844",
    "121847",
    "121894",
    "121896",
    "122599",
    "124198",
    "124582",
    "124612",
    "124669",
    "125987",
    "126134",
    "126210",
    "127327",
    "128473",
    "129050",
    "129140",
    "129212",
    "131820",
    "131962",
    "132707",
    "133625",
    "134637",
    "134945",
    "135190",
    "135633",
    "135643",
    "135785",
    "135837",
    "135931",
    "135943",
    "135977",
    "135983",
    "136048",
    "136061",
    "136723",
    "136749",
    "136923",
    "137700",
    "137993",
    "138093",
    "138166",
    "138729",
    "138877",
    "139279",
    "139811",
    "140034",
    "140185",
    "140186",
    "140390",
    "140776",
    "141101",
    "141610",
    "141863",
    "141933",
    "142201",
    "142678",
    "142684",
    "142734",
    "142763",
    "142767",
    "142880",
    "143111",
    "143136",
    "143372",
    "143504",
    "143506",
    "144005",
    "144147",
    "144148",
    "144162",
    "144172",
    "144246",
    "144365",
    "144411",
    "144529",
    "144532",
    "144790",
    "144968",
    "144994",
    "145164",
    "145316",
    "145493",
    "145553",
    "145725",
    "146308",
    "146334",
    "146340",
    "146930",
    "147017",
    "147143",
    "148027",
    "148091",
    "148161",
    "148169",
    "148169.001",
    "148169.002",
    "148169.003",
    "148279",
    "148840",
    "148860",
    "149166",
    "149386",
    "149433",
    "149466",
    "149909",
    "150549",
    "150797",
    "150823",
    "151176",
    "151372",
    "151646",
    "151697",
    "152376",
    "153002",
    "153003",
    "153053",
    "153296",
    "153311",
    "153400",
    "153413",
    "153414",
    "153436",
    "153690",
    "153766",
    "153866",
    "153940",
    "153984",
    "154178",
    "154194",
    "154342",
    "154574",
    "154638",
    "154668",
    "154745",
    "154787",
    "154795",
    "154947",
    "154959",
    "154976",
    "155126",
    "155160",
    "155279",
    "155350",
    "155368",
    "155494",
    "155522",
    "155534",
    "155666",
    "155677",
    "155938",
    "155996",
    "156009",
    "156278",
    "156555",
    "156870",
    "156894",
    "156954",
    "157076",
    "157201",
    "157243",
    "157552",
    "157562",
    "157668",
    "157826",
    "158349",
    "158354",
    "158380",
    "158419",
    "158652",
    "158741",
    "158813",
    "158853",
    "158876",
    "158884",
    "159137",
    "159171",
    "159275",
    "159361",
    "159366",
    "159627",
    "159630",
    "159674",
    "159867",
    "160062",
    "160075",
    "160088",
    "160378",
    "160533",
    "160567",
    "160609",
    "160714",
    "160808",
    "160842",
    "160862",
    "160863",
    "160868",
    "161007",
    "161161",
    "161504",
    "161546",
    "161785",
    "161978",
    "162003",
    "162012",
    "162018",
    "162365",
    "162459",
    "162467",
    "163122",
    "163183",
    "163380",
    "163779",
    "163784",
    "163925",
    "163937",
    "164108",
    "164116",
    "164200",
    "164212",
    "164710",
    "164724",
    "165363",
    "165412",
    "165931",
    "166342",
    "166413",
    "166414",
    "166424",
    "166434",
    "166533",
    "166634",
    "166661",
    "166963",
    "167062",
    "167069",
    "167323",
    "167402",
    "167410",
    "167419",
    "167426",
    "167497",
    "167697",
    "167770",
    "168345",
    "168501",
    "169008",
    "169508",
    "169508.001",
    "169606",
    "169842",
    "169849",
    "170144",
    "170443",
    "170599",
    "171437",
    "172242",
    "172495",
    "172657",
    "172699",
    "173043",
    "173052",
    "173221",
    "173227",
    "173359",
    "173754",
    "173760",
    "173773",
    "173793",
    "173889",
    "173942",
    "174010",
    "174137",
    "174253",
    "174254",
    "174254.001",
    "174296",
    "174391",
    "174417",
    "174465",
    "174557",
    "174994",
    "175190",
    "175210",
    "175650",
    "175925",
    "176174",
    "176605",
    "176707",
    "177128",
    "177217",
    "177301",
    "177331",
    "177797",
    "177830",
    "177875",
    "178327",
    "179139",
    "179243",
    "179469",
    "179690",
    "179849",
    "179956",
    "180015",
    "180052",
    "180494",
    "181177",
    "181674",
    "0188265_0001",
    "0188803_00",
    "0190057_00",
    "0226781_00",
    "0227774_00",
    "0231064_00",
    "0233676_00",
    "0234427_00",
    "0234943_00",
    "0234949_00",
    "0235215_00",
    "0235437_00",
    "0235440_00",
    "0235565_0002",
    "0235574_00",
    "0235744_00",
    "0238423_0000",
    "0238813_0001",
    "0239007_0000",
    "0239157_0000",
    "0239208_0000",
    "0240142_0000",
    "0240327_0000",
    "0240535_0000",
    "0240582_0000",
    "0240800_0000",
    "0240821_0000",
    "0241426_0000",
    "0241892_0000",
    "0241907_0001",
    "0242182_0001",
    "0242706_0000",
    "0242738_0000",
    "0242994_0000",
    "0243077_0000",
    "0243627_0000",
    "0243748_0000",
    "0243952_0000",
    "0243974_0000",
    "0244179_0000",
    "0244182_0000",
    "0244266_0000",
    "0244461_0000",
    "0244588_0000",
    "0244709_0000",
    "0244896_0000",
    "0245025_0000",
    "0245137_0000",
    "0245337_0000",
    "0245414_0000",
    "0245666_0000",
    "0245838_0000",
    "0246304_0000",
    "0246381_0000",
    "0246381_0001",
    "0246795_0000",
    "0246806_0000",
    "0246807_0000",
    "0247030_0000",
    "0247511_0000",
    "0248017_0000",
    "0248121_0000",
    "0248128_0000",
    "0248420_0000",
    "0248721_0000",
    "0248823_0000",
    "0248844_0000",
    "0249372_0000",
    "0249380_0000",
    "0249386_0000",
    "0249423_0000",
    "0249675_0000",
    "0249733_0000",
    "0250215_0000",
    "0250605_0000",
    "0250639_0000",
    "0250641_0000",
    "0251078_0000",
    "0251270_0000",
    "0251869_0000",
    "0251994_0000",
    "0252230_0000",
    "0252242_0000",
    "0252559_0000",
    "0252562_0000",
    "0253099_0000",
    "0253191_0000",
    "0253269_0000",
    "0253290_0000",
    "0253384_0000",
    "0253397_0000",
    "0253785_0000",
    "0253948_0000",
    "0254063_0000",
    "0254307_0000",
    "0254819_0000",
    "0255372_0000",
    "0255376_0000",
    "0255544_0000",
    "0256018_0000",
    "0256023_0000",
    "0256346_0000",
    "0256525_0000",
    "0256805_0000",
    "0256903_0000",
    "0257073_0000",
    "0257387_0000",
    "0257443_0000",
    "0257518_0000",
    "0257670_0000",
    "0257862_0000",
    "0257925_0000",
    "0257998_0000",
    "0258338_0000",
    "0258794_0000",
    "0258794_0001",
    "0259198_0000",
    "0259420_0000",
    "0259602_0000",
    "0261227_0000",
    "0261262_0000",
    "0261410_0000",
    "0261492_0000",
    "0261674_0000",
    "0261744_0000",
    "0262057_0000",
    "0262135_0000",
    "0262136_0000",
    "0262137_0000",
    "0262155_0000",
    "0262394_0000",
    "0262470_0000",
    "0262671_0000"
)

$Error.Clear()
$Script:HaveError = $false
$pf = FindManyProjectFolders -connData $connData -pwPassword "tX2NPfAK92DhM2" -projectNames $fedProjectNames -dbgOut

$pf | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
<#  DUMP PATHS

    $p = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $pwData.PWFolder.TreeDocuments.Count)
    {
        $o = GetDocumentPathsFromDictionary -viablePathsDict $viablePathsDict -documentGUID $pwData.PWFolder.TreeDocuments[$a].DocumentGUID
        if($o.OriginalPath -ne $o.ViablePath)
        {
            $p.Add($o)
        }
        $a++
    }

    $p | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
#>


function t5
{
    $permRows = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $pwData.PWFolder.SubFolders.Count)
    {
        $pc = [float] $a / [float] $pwData.PWFolder.SubFolders.Count
        Write-Progress -Id 1 -Activity ("Processing Subfolder {0} of {1}" -f @(($a + 1), $pwData.PWFolder.SubFolders.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

        $ppp = Export-PWProjectAccessControl -FolderPath $pwData.PWFolder.SubFolders[$a].FullPath
        $b = 0
        while($b -lt $ppp.Rows.Count)
        {
            $permRows.Add($ppp.Rows[$b])
            $b++
        }
        $a++
    }
    Write-Progress -Id 1 -Completed
}

function t6
{
    # $pwData = Get-Content -Path "e:\pw2sp\0244709_0000.pwdata.json" | ConvertFrom-Json

    $saDict = GetStorageDictionary
    $srcObjects = @($topPaths["ROOT"].Children["Active Projects"].Children["0244709_0000"].Children["Drawings"].Children["Drawing PDF"].Children["0244709-ES101.pdf"].SourceObjects | Sort-Object VersionSequence)

    $a = 0
    while($a -lt $srcObjects.Length)
    {
        $td = $srcObjects[$a]
        if($td.ProjectID -le 99999)
        {
            $srcFolder = "{0}\dms{1:D5}" -f @($pwData.StorageAreas[$td.StorageName], $td.ProjectID)
        } `
        else
        {
            $srcFolder = "{0}\d{1:D7}" -f @($pwData.StorageAreas[$td.StorageName], $td.ProjectID)
        }
        if([System.IO.Directory]::Exists($srcFolder))
        {
            # Is this the latest version of the file?
            if($a -eq ($srcObjects.Length - 1))
            {
                $srcPath = "{0}\{1}" -f @($srcFolder, $td.Name)
            } `
            else
            {
                $srcPath = "{0}\ver{1:D5}\{2}" -f @($srcFolder, $td.VersionSequence, $td.Name)
            }

            if([System.IO.File]::Exists($srcPath))
            {
                $fi = [System.IO.FileInfo]::new($srcPath)
                if($fi.Length -ne $td.FileSize)
                {
                    Write-Host ("{0} file size different.  TD.FileSize: {1}, FI.Length: {2}" -f @($srcPath, $td.FileSize, $fi.Length))
                }
            } `
            else
            {
                LogError ("Source file {0} not found for {1}:{2} in {3}." -f @($srcPath, $td.DocumentGUID, $td.FullPath, $me.Name))
            }
        } `
        else
        {
            LogError ("Source folder {0} not found for {1}:{2} in {3}." -f @($srcFolder, $td.DocumentGUID, $td.FullPath, $me.Name))
        }
        $a++
    }


}


function x1
{

    <#
        Playing with document sets and file versions...
    #>



                                        $referenceSPDoc = Get-PnpFile -URL ("/sites/{0}/{1}/{2}" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName, ($vp.Paths -join "/"))) -AsListItem

                                        $referenceSPDocVersions = Get-PnpFileVersion -URL  ("/sites/{0}/{1}/{2}" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName, ($vp.Paths -join "/")))
# "sites/SP-GVS-ProjectWise-MigrationTest/_vti_history/3072/Shared%20Documents/Active%20Projects/0244709_0000/Drawings/Drawing%20PDF/0244709-ES101.pdf"
                                        $spDoc = Get-PnPFile -URL ("sites/{0}/{1}" -f @($connData.ConnectionInformation.SharePointSiteName, $referenceSPDocVersions[20].Url)) -AsListItem

                                        $spDoc = Get-PnPFile -URL $referenceSPDocVersions[20].Url -AsListItem

                                        $spDoc = Get-PnPFile -URL "https://powereng0.sharepoint.com/sites/SP-GVS-ProjectWise-MigrationTest/_vti_history/3072/Shared Documents/Active Projects/0244709_0000/Drawings/Drawing PDF/0244709-ES101.pdf"


                                        $docLink = "{0}/sites/{1}/{2}" -f @($connData.ConnectionInformation.SharePointRootURL, $connData.ConnectionInformation.SharePointSiteName, $referenceSPDocVersions[20].Url)
                                        $linkContent = "[InternetShortcut]`nURL={0}" -f @($docLink)
                                        $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))
                                        $targetFolder = "{0}/{1}" -f @($fsFolder, $fsName)
                                        $linkName = "{0}.url" -f @($pwFS.References[$b].Name)

                                        try
                                        {
                                            $fsDocLink = Add-PnPFile -FileName $linkName -Folder $targetFolder -Stream $stream -Values @{ _ShortcutUrl=$docLink }
                                        }
                                        catch
                                        {
                                            LogError ("Failed to create document link {0} for document set {1} in {2}." -f @($docLink, $fsName, $me.Name))
                                        }
}


<#
    Not using this function.  I'll just add document fields as I find them in projects/documents
#>
function CheckSPDocumentFields
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData
    )

    $me = $MyInvocation.MyCommand
    try
    {
        $spDocumentFields = Get-PnpField -List $connData.ConnectionInformation.DocumentLibraryName -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to get document fields for {0} in {1}." -f @($connData.ConnectionInformation.DocumentLibraryName, $me.Name))
    }

    if(-not $Script:HaveError)
    {
        $a = 0
        while($a -lt $connData.documentFields.Length)
        {
            if(-not $connData.documentFields[$a].Ignore)
            {
                $field = $spDocumentFields | Where-Object { $_.InternalName -eq $connData.documentFields[$a].InternalName }

                if($null -ne $field)
                {
                    if($field.Title -eq $connData.documentFields[$a].DisplayName)
                    {
                        if($field.FieldTypeKind -eq $connData.documentFields[$a].Type)
                        {
                            if($field.FieldTypeKind -eq "Choice")
                            {
                                if($field.Choices.Length -eq $connData.documentFields[$a].Choices.Length)
                                {
                                    $b = 0
                                    while($b -lt $field.Choices.Length)
                                    {
                                        if($connData.documentFields[$a].Choices -contains $field.Choices[$b])
                                        {
                                            # Nothing, both choices contain the value..
                                        } `
                                        else
                                        {
                                            LogError ("Field {0} contains choice {1} not specified in sharepoint data file in {2}." -f @($field.Title, $field.Choices[$b], $me.Name))
                                        }
                                        $b++
                                    }

                                    $b = 0
                                    while($b -lt $connData.documentFields[$a].Choices.Length)
                                    {
                                        if($field.Choices -contains $connData.documentFields[$a].Choices[$b])
                                        {
                                            # Nothing, both choices contain the value..
                                        } `
                                        else
                                        {
                                            LogError ("Document field definition {0} contains choice {1} not present in sharepoint field in {2}." -f @($connData.documentFields[$a].DisplayName, $connData.documentFields[$a].Choices[$b], $me.Name))
                                        }
                                        $b++
                                    }
                                } `
                                else
                                {
                                    LogError ("Field {0} has a different amount of choices [{1}] than specified [{2}] in {3}." -f @($field.Title, $field.Choices.Length, $connData.documentFields[$a].Choices.Length, $me.Name))
                                }
                            } `
                            else
                            {
                                # Only worried about checking "Choice" fields...
                            }
                        } `
                        else
                        {
                            LogError ("Field {0} Title: [{1}] does not match DisplayName: {2} in {3}." -f @($field.InternalName, $field.Title, $connData.documentFields[$a].DisplayName, $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Field {0} Title: [{1}] does not match DisplayName: {2} in {3}." -f @($field.InternalName, $field.Title, $connData.documentFields[$a].DisplayName, $me.Name))
                    }
                } `
                else
                {
                    # Did not find a definition for this document field in Sharepoint Online...
                    $newPropValues = @{
                        List="Documents"
                        DisplayName = $connData.documentFields[$a].DisplayName
                        InternalName = $connData.documentFields[$a].InternalName
                        Type = $connData.documentFields[$a].Type
                    }
                    if($connData.documentFields[$a].Type -eq "Choice")
                    {
                        $newPropValues.Add("Choices", $connData.documentFields[$a].Choices)
                    }
                    try
                    {
                        $null = Add-PnpField @newPropValues -ErrorAction Stop
                    }
                    catch
                    {
                        LogError ("Failed to add document field {0} in {1}." -f @($connData.documentFields[$a].DisplayName, $me.Name))
                    }
                }
            } `
            else
            {
                # Field which are ignored are only present so when parsing documents from ProjectWise, we know about the property.  They are not migrated to SP
            }

            $a++
        }
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    return (-not $Script:HaveError)
}

<#  Old function versions #>

function BuildViablePathsDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $parentPath = "",

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $allTestPaths = $null
    )

    $me = $MyInvocation.MyCommand
    if($null -eq $parentPath)
    {
        $parentPath = ""
    } `
    else
    {
        # Nothing
    }

    if($null -eq $allTestPaths)
    {
        $allTestPaths = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()
    } `
    else
    {
        # Nothing
    }

    <#
    $fromNode = $pathDict

    $allTestPaths = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()
    $parentPath = "" # "sites/{0}/{1}/{2}/{3}" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName, $documentLibraryFolderName, $projectName)
    BuildViablePathsDictionary -fromNode $testPaths -parentPath $parentPath -allTestPaths $allTestPaths

    $allTestPaths = @($allTestPaths | Sort-Object Length -Descending)
    $allTestPaths | Set-Clipboard
    #>
    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $keys[$a]

        if($fromNode[$keys[$a]].Documents.Count -gt 0)
        {
            $b = 0
            while($b -lt $fromNode[$keys[$a]].Documents.Count)
            {
                $d = "" | Select-Object Paths, CopyOutPath, SPUploadPath
                $d.Paths = @($pathToTest -split "/")
                $d.CopyOutPath = $null
                $d.SPUploadPath = $null
                $allTestPaths.Add($fromNode[$keys[$a]].Documents[$b].DocumentGUID, $d)

                $b++
            }
        } `
        else
        {
            if($null -ne $fromNode[$keys[$a]].DocumentGUID)
            {
                $d = "" | Select-Object Paths, CopyOutPath, SPUploadPath
                $d.Paths = @($pathToTest -split "/")
                $d.CopyOutPath = $null
                $d.SPUploadPath = $null
                $allTestPaths.Add($fromNode[$keys[$a]].DocumentGUID, $d)
            } `
            else
            {
                $folderDepth = $parentPath -split "/"
                if($folderDepth.Length -gt 2)
                {
                    LogError ("Missing Document GUID for folder {0} in {1} FD: {2}, P: {3}." -f @($pathToTest, $me.Name, $folderDepth.Length, $parentPath))
                } `
                else
                {
                    # Nothing, not concerned about the top 2 folders...
                }
            }
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            $null = BuildViablePathsDictionary -fromNode $fromNode[$keys[$a]].Children -parentPath ($pathToTest + "/") -allTestPaths $allTestPaths
            <#
            @($fromNode[$keys[$a]].Children).ForEach({
                $null = BuildViablePathsDictionary -fromNode $_ -parentPath ($pathToTest + "/") -allTestPaths $allTestPaths
            })
            #>
        } `
        else
        {
            # Nothing, no child nodes to follow...
        }
        $a++
    }

    return @( , $allTestPaths)
}


function CreateSharePointProjectSubFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $me = $MyInvocation.MyCommand
    $a = 0
    $subFolderGUIDs = @($pwData.SubFolderGuidToPWSubFolder.Keys)
    $newFolders = [System.Collections.Generic.List[Object]]::new()
    while((-not $Script:HaveError) -and ($a -lt $subFolderGUIDs.Length))
    {
        if($viablePathsDict.ContainsKey($subFolderGUIDs[$a]))
        {
            $d = [PSCustomObject]@{
                ParentFolder = "{0}/{1}" -f @($connData.ConnectionInformation.DocumentLibraryName, ($viablePathsDict[$subFolderGUIDs[$a]].Paths[0..($viablePathsDict[$subFolderGUIDs[$a]].Paths.Length -2)] -join "/"))
                FolderName = $viablePathsDict[$subFolderGUIDs[$a]].Paths[-1]
                Description = $pwData.SubFolderGuidToPWSubFolder[$subFolderGUIDs[$a]].Description
            }

            $newFolders.Add($d)
        } `
        else
        {
            LogError ("No viable path for subfolder {0}:{1} in {2}" -f @($subFolderGUIDs[$a], $pwData.SubFolderGuidToPWSubFolder[$subFolderGUIDs[$a]].FullPath, $me.Name))
        }

        $a++
    }

    $newFolders = @($newFolders | Sort-Object ParentFolder, Foldername)
    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $newFolders.Length))
    {
        $pc = [float] $i / [float] $newFolders.Length
        Write-Progress -Id 1 -Activity ("Creating SharePoint folder {0} : {1} of {2}" -f @($newFolders[$a].FolderName, ($a + 1), $newFolders.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

        AddSharePointFolder -parentFolder $newFolders[$a].ParentFolder -newFolderName $newFolders[$a].FolderName -description $newFolders[$a].Description

        $a++
    }
    Write-Progress -Id 1 -Completed
}


function FixLongPaths
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pathDict
    )

    $spLimitPrefix = "sites/{0}/{1}/" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName)
    $spLimitPrefixLength = $spLimitPrefix.Length

    $pathsTooLong = [System.Collections.Generic.List[String]]::new()
    # $pathsTooLong | Set-Clipboard

    GetPathsTooLongFromDictionaryNew -fromNode $pathDict["ROOT"].Children -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)

    # GetPathsTooLongFromDictionary -fromNode $pathDict -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
    $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending)
    # $pathsTooLong is now an array....

    $maxLongPaths = $pathsTooLong.Length
    while((-not $Script:HaveError) -and ($pathsTooLong.Length -gt 0))
    {
        $pc = [float] ($maxLongPaths - $pathsTooLong.Length) / [float] $maxLongPaths
        Write-Progress -Id 1 -Activity ("Processing {0}" -f @($pathsTooLong[0])) -Status ("{0} of {1} ({2,7:P}) Complete" -f @(($maxLongPaths - $pathsTooLong.Length), $maxLongPaths, $pc)) -PercentComplete ($pc * 100)

        $originalPathPieces = @($pathsTooLong[0] -split "/")

        if(($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength))
        {
            $pathPieces = @($pathsTooLong[0] -split "/")

            if($pathPieces.Length -gt 2)
            {
                # The first 2 placeholders in the path are always fixed....
                $longestPiece = ($pathPieces | Select-Object -Skip 2) | Sort-Object Length -Descending | Select-Object -First 1
                $longestPieceIdx = $pathPieces.IndexOf($longestPiece)
                $lpMinLength = 2

                # $node = $pathDict
                $node = $pathDict["ROOT"].Children
                $c = 0
                while((-not $Script:HaveError) -and ($c -lt $longestPieceIdx))
                {
                    if($node.ContainsKey($originalPathPieces[$c]))
                    {
                        $node = $node[$originalPathPieces[$c]].Children
                    } `
                    else
                    {
                        LogError ("Missing node for {0}" -f @($originalPathPieces[$c]))
                    }
                    $c++
                }

                $fi = $null

                # Is the longest piece the file name??
                if($longestPieceIdx -eq ($pathPieces.Length - 1))
                {
                    # This is the file name...
                    $fi = [System.IO.FileInfo]::new($longestPiece)
                    $longestPiece = $fi.BaseName
                    $lpMinLength += $fi.Extension.Length
                } `
                else
                {
                    # Nothing....
                }

                $originalLP = $longestPiece

                # When $x -eq 0 the script first removes leading and trailing spaces from the name and replaces all double spaces with single spaces.
                $x = 0

                # Start at the first counter character if we need it...
                $i = 0

                do {
                    if($x -eq 0)
                    {
                        $longestPiece = $longestPiece.Trim()
                        while($longestPiece -match "  ")
                        {
                            $longestPiece = $longestPiece.Replace("  ", " ")
                        }
                        $x++
                    } `
                    elseif($x -gt 0)
                    {
                        do
                        {
                            $longestPiece = $originalLP.SubString(0, $originalLP.Length - $x)
                            if($longestPiece.EndsWith(" "))
                            {
                                $x++
                            }
                        } while(($longestPiece.Length -gt $lpMinLength) -and ($longestPiece.EndsWith(" ")))

                        if($x -gt 1)
                        {
                            $longestPiece += $COUNTER_CHARACTERS[$i]
                            $i++
                            if($i -eq $COUNTER_CHARACTERS.Length)
                            {
                                $i = 0
                                $x++
                            }
                        } `
                        else
                        {
                            $x++
                        }
                    }

                    if($x -ge ($originalLP.Length - 3))
                    {
                        LogError ("Unable to shorten {0} enough.`r`n`tOffending piece: {1}" -f @($pathsTooLong[0], $originalLP))
                    } `
                    else
                    {
                        if($null -ne $fi)
                        {
                            $longestPiece += $fi.Extension
                        } `
                        else
                        {
                            # Nothing, don't add a non-existant extension...
                        }
                    }
                } while((-not $Script:HaveError) -and ($x -lt ($originalLP.Length - 3)) -and ($i -lt $COUNTER_CHARACTERS.Length) -and ($longestPiece.Length -gt $lpMinLength) -and ($node.ContainsKey($longestPiece)))

                # Found a substitute name...
                if(-not $Script:HaveError)
                {
                    $pathPieces[$longestPieceIdx] = $longestPiece
                    $pathsTooLong[0] = $pathPieces -join "/"

                    if($node.ContainsKey($originalPathPieces[$longestPieceIdx]))
                    {
                        try
                        {
                            $node.Add($longestPiece, $node[$originalPathPieces[$longestPieceIdx]])
                        }
                        catch
                        {
                            LogError ("Failed to add modified node: {0}..." -f @($longestPiece))
                        }

                        try
                        {
                            $null = $node.Remove($originalPathPieces[$longestPieceIdx])
                        }
                        catch
                        {
                            LogError ("Failed to remove 'old' node: {0}..." -f @($originalPathPieces[$longestPieceIdx]))
                        }

                        if($null -eq $fi)
                        {
                            if($null -ne $node[$longestPiece].Children)
                            {
                                @($node[$longestPiece].Children).ForEach({ RevertToOriginal -fromNode $_ })
                            } `
                            else
                            {
                                # Nothing, no children to revert.
                            }

                            # If this was not a file node, then rebuild the list of paths which are too long...
                            $pathsTooLong = [System.Collections.Generic.List[String]]::new()
                            GetPathsTooLongFromDictionary -fromNode $pathDict -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
                        }
                        # $node = $node[$originalPathPieces[$c]].Children
                    } `
                    else
                    {
                        LogError ("Missing node for {0}" -f @($originalPathPieces[$c]))
                    }
                    # Sort $pathsTooLong, putting the longest one on top and removing any paths which are now viable....
                    $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending | Where-Object { ($_.Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)})

                    # ($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)
                } `
                else
                {
                    # Nothing, already displayed an error.
                }
            } `
            else
            {
                LogError ("Path too short [{0}], cannot shorten in {1}." -f @($pathsTooLong[0], $me.Name))
            }
        } `
        else
        {
            LogError ("Why is {0} in the list of paths too long? Length={1}" -f @($pathsTooLong[0], $pathsTooLong[0].Length))
        }
    }

    if($maxLongPaths -gt 0)
    {
        Write-Progress -Id 1 -Completed
    } `
    else
    {
        # Nothing, didn't have any paths to fix...
    }
}

function RevertToOriginal
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode
    )

    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $originalName = $fromNode[$keys[$a]].OriginalName
        if($originalName -ne $keys[$a])
        {
            # Re-add the the node with the original name...
            $fromNode.Add($originalName, $fromNode[$keys[$a]])

            # Remove the node with the old name.
            $null = $fromNode.Remove($keys[$a])
        } `
        else
        {
            # Nothing, no need to revert an unchanged node.
        }

        # Now revert all of the children's children...
        @($fromNode[$originalName].Children).ForEach({
            RevertToOriginal -fromNode $_
        })

        $a++
    }
}


function GetPathsTooLongFromDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $fromNode,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $parentPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[String]] $pathsTooLong,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [int] $maxLength
    )

    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $keys[$a]
        if($pathToTest.Length -gt $maxLength)
        {
            $pathsTooLong.Add($pathToTest)
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            @($fromNode[$keys[$a]].Children).ForEach({
                GetPathsTooLongFromDictionary -fromNode $_ -parentPath ($pathToTest + "/") -pathsTooLong $pathsTooLong -maxLength $maxLength
            })
        }
        $a++
    }
}

function AddPWDocumentToPathDict
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[String],[Object]]] $testPaths,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $td,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]] $notAdded,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [System.Collections.Generic.SortedDictionary[Guid, PWPS_DAB.CommonTypes+ProjectWiseFolder]] $subFolderDict
    )

    $added = $false

    # Replace all "*:<>?/| characters with ""   (nothing)
    $docPath = $td.FullPath -replace "[\`"\*\:\<\>\?\/\|]",""

    $docPathParts = $docPath -split "\\"

    $i = $testPaths
    $b = 0
    while($b -lt $docPathParts.Length)
    {
        # Trim leading and trailing spaces...
        $docPathParts[$b] = $docPathParts[$b].Trim()

        # Replace multiple whitespace characters with a single space.
        $docPathParts[$b] = $docPathParts[$b] -replace "\s+", " "

        # The first part of the path is what I call the "ProjectWise Document Folder..." i.e. "Archive Projects" or "Active Projects".
        if(($b -eq 0) -and ($docPathParts[$b] -match "Archive[d]* Projects"))
        {
            $docPathParts[$b] = "Inactive Projects"
        } `
        elseif($b -eq ($docPathParts.Length - 1))    # If this is the file name part of the document path...
        {
            # Remove spaces for and aft of the period.  Remember, we trimmed leading and trailing spaces above.
            if($docPathParts[$b] -match "^\s*(.*?)\s*\.\s*(\w+)\s*$")
            {
                $docPathParts[$b] = $matches[1..2] -join "."
            } `
            else
            {
                # Nothing, leave as is.
            }
        } `
        else
        {
            # Nothing, leave it alone.
        }

        if(-not $i.ContainsKey($docPathParts[$b]))
        {
            $j = "" | Select-Object IsFixed, OriginalName, ParentNode, Children, DocumentGUID, CopyOutPath, SPUploadPath, Documents
            #  Original name represents the pre-shortened name, not necessarily the original from .TreeDocument[].FullPath

            $j.IsFixed = ($b -eq 0) -or ($b -eq 1)    # These parts of the path cannot change...
            $j.Children = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
            $j.ParentNode = $i
            $j.OriginalName = $docPathParts[$b]
            $j.CopyOutPath = [String]::Empty
            $j.SPUploadPath = [String]::Empty

            $j.Documents = [System.Collections.Generic.List[Object]]::new()

            # If this is the file name part of the document path...
            if($b -eq ($docPathParts.Length - 1))
            {
                # Create a list of documents (yes, with versions, there can be multiples.)
                $k = "" | Select-Object DocumentGUID, CopyOutPath, SPUploadPath

                $k.DocumentGUID = $td.DocumentGUID
                $j.Documents.Add($k)
                # $j.DocumentGUID = $td.DocumentGUID
            } `
            else
            {
                # Add a subfolder marker
            }

            $added = $true
            $i.Add($docPathParts[$b], $j)
        } `
        else
        {
            # If this is the file name part ofthe document path...
            if($b -eq ($docPathParts.Length - 1))
            {
                # Make sure there isn't a document with DocumentGUID already in the list -- yes, versions have the same name, but a different DocumentGUID.
                $existingDocs = @($i[$docPathParts[$b]].Documents | Where-Object { $_.DocumentGUID -eq $td.DocumentGUID })

                if($existingDocs.Length -eq 0)
                {
                    # Add the document to the list.
                    $k = "" | Select-Object DocumentGUID, CopyOutPath, SPUploadPath
                    $k.DocumentGUID = $td.DocumentGUID
                    $i[$docPathParts[$b]].Documents.Add($k)
                    $added = $true
                } `
                else
                {
                    # Nothing, if we already know about the document, don't add it again.
                    #   This might happen if a flatset references a document in .TreeDocuments...
                }
            }
        }

        $i = $i[$docPathParts[$b]].Children

        $b++
    }

    if(-not $added)
    {
        $notAdded.Add($td.DocumentGUID)
    }
}


function ExportPW2SP
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $viablePathsExportPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $localPath,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $uriEncode
    )

    $me = $MyInvocation.MyCommand
    $PSStyle.Progress.View = 'Minimal'
    $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
    $Error.Clear()
    $totalDocuments = $pwData.PWFolder.TreeDocuments.Count
    $sw = [System.Diagnostics.Stopwatch]::new()
    $sw.Start()

    $null = CreateSharePointProjectFolder -connData $connData -pwData $pwData

    if(-not $Script:HaveError)
    {
        CreateSharePointProjectSubFoldersNew -connData $connData -pwData $pwData -viablePathsDict $viablePathsDict
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    # Where we export $viablePathsDict to, to track progress.
    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath

    $sw = [System.Diagnostics.Stopwatch]::new()
    if(-not $Script:HaveError)
    {
        <#

                Export/Upload $pwData.PWFolder.TreeDocuments...

        #>
        # Exclude FlatSets here...
        $pathVersionSequenceOrderTreeDocuments = $pwData.PWFolder.TreeDocuments | Where-Object { -not $_.IsSet } | Sort-Object FullPath, VersionSequence

        $fpToDocumentsDict = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
        $a = 0
        while((-not $Script:HaveError) -and ($a -lt $pathVersionSequenceOrderTreeDocuments.Length))
        {
            if(-not $fpToDocumentsDict.ContainsKey($pathVersionSequenceOrderTreeDocuments[$a].FullPath))
            {
                $docList = [System.Collections.Generic.List[Object]]::new()
                $fpToDocumentsDict.Add($pathVersionSequenceOrderTreeDocuments[$a].FullPath, $docList)
            } `
            else
            {
                # Nothing, already have a node for this .FullPath
            }

            $existingDoc = $fpToDocumentsDict[$pathVersionSequenceOrderTreeDocuments[$a].FullPath] | Where-Object { $_.DocumentGUID -eq $pathVersionSequenceOrderTreeDocuments[$a].DocumentGUID}
            if($null -eq $existingDoc)
            {
                $fpToDocumentsDict[$pathVersionSequenceOrderTreeDocuments[$a].FullPath].Add($pathVersionSequenceOrderTreeDocuments[$a])
            } `
            else
            {
                LogError ("Attempt to add duplicate document {0}:{1} (idx:{2}) to fullpath dictionary in {3}." -f @($pathVersionSequenceOrderTreeDocuments[$a].DocumentGUID, $pathVersionSequenceOrderTreeDocuments[$a].FullPath, $a, $me.Name))
            }
            $a++
        }

        # Don't need to sort the lists, I sorted the complete list above, so the TreeDocuments will be added in the correct order.


        $totalDocuments = $pathVersionSequenceOrderTreeDocuments.Length

        $retryList = [System.Collections.Generic.List[System.Object]]::new()
        $totalRetries = 0    # In total, how many items have we added to $retryList
        $totalRetried = 0    # How many items from $retryList have we processed?
        $sw.Start()
        $a = 0

        while((-not $Script:HaveError) -and (($a -lt $pathVersionSequenceOrderTreeDocuments.Length) -or ($retryList.Count -gt 0)))
        {
            $retrying = $false
            # The "oldest" item to retry will always be at the top of the list...
            if(($retryList.Count -gt 0) -and ($retryList[0].When -ge [DateTime]::Now))
            {
                $td = $pathVersionSequenceOrderTreeDocuments[$retryList[0].Idx]
                $retryCount = $retryList[0].RetryCount + 1
                $retryList.RemoveAt(0)
                $totalRetried++
                $retrying = $true
            } `
            else
            {
                $retryCount = 0
                $td = $pathVersionSequenceOrderTreeDocuments[$a]
            }

            if($fpToDocumentsDict.ContainsKey($td.FullPath))
            {
                $docList = $fpToDocumentsDict[$td.FullPath]
                $fileExportUploadParams = @{
                    connData = $connData
                    td = $td
                    viablePathsDict = $viablePathsDict
                    localPath = $localPath
                    viablePathsExportPath = $viablePathsExportPath
                    retryList = $retryList
                    sw = $sw
                    a = $a
                    totalDocuments = $totalDocuments
                    totalRetries = $totalRetries
                    totalRetried = $totalRetried
                    retryCount = $retryCount
                    docList = $docList
                }
                ExportDocumentFromPW_UploadToSP @fileExportUploadParams

                # If we didn't just process a retry, then move to the next document...
                if(-not $retrying)
                {
                    $a++
                    if($a % 10 -eq 0)
                    {
                        ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                    }
                } `
                else
                {
                    # Nothing,
                }
            } `
            else
            {
                Write-Error ("Missing full path to document list for {0} in {1}." -f @($td.FullPath, $me.Name))
            }
        }
        Write-Progress -Id 2 -Completed
        Write-Progress -Id 1 -Completed
        $sw.Stop()
        ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath

        <#

                Export/Upload $pwData.FlatSets...

        #>

        # Need to create an array of documents we need to upload so we can sort them and keep try of which ones we need to retry.
        $fsDocumentsToExportUpload = @(@($pwData.FlatSets).ForEach({ $_.References.ForEach({ $_ }) }) | Sort-Object FullPath, VersionSequence)

        # Reset some admin stuff..
        $retryList.Clear()
        $sw.Restart()
        $a = 0
        $totalRetries = 0    # In total, how many items have we added to $retryList
        $totalRetried = 0    # How many items from $retryList have we processed?
        $totalDocuments = $fsDocumentsToExportUpload.Length

        # First, make sure all the referenced documents have been uploaded...
        while((-not $Script:HaveError) -and ($a -lt $fsDocumentsToExportUpload.Length))
        {
            $fileExportUploadParams = @{
                connData = $connData
                td = $fsDocumentsToExportUpload[$a]
                viablePathsDict = $viablePathsDict
                localPath = $localPath
                viablePathsExportPath = $viablePathsExportPath
                retryList = $retryList
                sw = $sw
                a = $a
                totalDocuments = $totalDocuments
                totalRetries = $totalRetries
                totalRetried = $totalRetried
                retryCount = $retryCount
            }
            ExportDocumentFromPW_UploadToSP @fileExportUploadParams

            $a++
        }

        try
        {
            # Get the list corresponding to the document library
            $list = Get-PnPList -Identity $connData.ConnectionInformation.DocumentLibraryName -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to get document library list for {0} in {1}." -f @($connData.ConnectionInformation.DocumentLibraryName, $me.Name))
        }

        <# TODO: Add progress output. #>
        if($null -ne $list)
        {
            # Next need to create all the document sets and add the document links.
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $pwData.FlatSets.Count))
            {
                $pc = [float] $a / [float] $pwData.FlatSets.Count
                Write-Progress -Id 1 -Activity ("Processing FlatSet {0} of {1}" -f @(($a + 1), $pwData.FlatSets.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                if($viablePathsDict.ContainsKey($pwData.FlatSets[$a].TreeDocument.DocumentGUID))
                {
                    $vp = $viablePathsDict[$pwData.FlatSets[$a].TreeDocument.DocumentGUID]

                    # The folder where the document set will live
                    $fsFolder = "{0}/{1}" -f @($connData.ConnectionInformation.DocumentLibraryName, (($vp.Paths[0..($vp.Paths.Length - 2)]) -join "/"))

                    # [-1] is the last item in the array...
                    $fsName = $vp.Paths[-1]

                    try
                    {
                        $ds = Add-PnPDocumentSet -List $list -ContentType "Document Set" -Name $fsName -Folder $fsFolder -ErrorAction Stop
                    }
                    catch
                    {
                        LogError ("Failed to add document set: {0:1} at {2} in {3}." -f @($fsName, $flatsetTreeDocuments[$a].DocumentGUID, $fsFolder, $me.Name))
                    }

                    if(-not $Script:HaveError)
                    {
                        if(-not [String]::IsNullOrEmpty($ds))
                        {
                            # Now, create all the document links in the document set.

                            $b = 0
                            while((-not $Script:HaveError) -and ($b -lt $pwData.FlatSets[$a].References.Length))
                            {
                                $pc = [float] $b / [float] $pwData.FlatSets[$a].References.Length
                                Write-Progress -Id 2 -Activity ("Adding links to FlatSet {0} of {1}" -f @(($b + 1), $pwData.FlatSets[$a].References.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                                if($viablePathsDict.ContainsKey($pwData.FlatSets[$a].References[$b].DocumentGUID))
                                {
                                    $vp = $viablePathsDict[$pwData.FlatSets[$a].References[$b].DocumentGUID]
                                    $docLink = "{0}{1}" -f @($connData.ConnectionInformation.SharePointRootURL, $vp.SPUploadPath)
                                    $linkContent = "[InternetShortcut]`nURL={0}" -f @($docLink)
                                    $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))
                                    $targetFolder = "{0}/{1}" -f @($fsFolder, $fsName)
                                    $linkName = "{0}.url" -f @($pwData.FlatSets[$a].References[$b].Name)

                                    try
                                    {
                                        $fsDocLink = Add-PnPFile -FileName $linkName -Folder $targetFolder -Stream $stream -Values @{ _ShortcutUrl=$docLink }
                                    }
                                    catch
                                    {
                                        LogError ("Failed to create document link {0} for document set {1} in {2}." -f @($docLink, $fsName, $me.Name))
                                    }
                                } `
                                else
                                {
                                    LogError ("Missing flat set reference viable path for {0}:{1} in {2}." -f @($pwData.FlatSets[$a].References[$b].DocumentGUID, $pwData.FlatSets[$a].References[$b].FullPath, $me.Name))
                                }

                                $b++
                            }
                        } `
                        else
                        {
                            LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0}:{1}/{2} in {3}." -f @($flatsetTreeDocuments[$a].DocumentGUID, $fsFolder, $fsName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }
                } `
                else
                {
                    LogError ("Missing flat set viable path for {0}:{1} in {2}." -f @($pwData.FlatSets[$a].TreeDocument.DocumentGUID, $pwData.FlatSets[$a].TreeDocument.FullPath, $me.Name))
                }
                $a++
            }
        } `
        else
        {
            # Nothing, already displayed an error.
        }
    } `
    else
    {
        # Nothing, already displayed an error.
    }
}


function AddPWFolderToPathDict
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[String],[Object]]] $testPaths,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Guid] $fldrGuid,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $fldr,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]] $notAdded
    )

    $added = $false

    # Replace all "*:<>?/| characters with ""   (nothing)
    $folderPath = $fldr.FullPath -replace "[\`"\*\:\<\>\?\/\|]",""

    $pathParts = $folderPath -split "\\"

    $i = $testPaths
    $b = 0
    while($b -lt $pathParts.Length)
    {
        # Trim leading and trailing spaces...
        $pathParts[$b] = $pathParts[$b].Trim()

        # Replace multiple whitespace characters with a single space.
        $pathParts[$b] = $pathParts[$b] -replace "\s+", " "

        # The first part of the path is what I call the "ProjectWise Document Folder..." i.e. "Archive Projects" or "Active Projects".
        if(($b -eq 0) -and ($pathParts[$b] -match "Archive[d]* Projects"))
        {
            $pathParts[$b] = "Inactive Projects"
        } `
        else
        {
            # Nothing, leave it alone.
        }

        if(-not $i.ContainsKey($pathParts[$b]))
        {
            # Create a new pathDict node...
            $j = "" | Select-Object IsFixed, OriginalName, ParentNode, Children, DocumentGUID, CopyOutPath, SPUploadPath, Documents
            #  Original name represents the pre-shortened name, not necessarily the original from .TreeDocument[].FullPath

            $j.IsFixed = ($b -eq 0) -or ($b -eq 1)    # These parts of the path cannot change...
            $j.Children = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
            $j.ParentNode = $i
            $j.OriginalName = $pathParts[$b]
            $j.CopyOutPath = [String]::Empty
            $j.SPUploadPath = [String]::Empty

            $j.Documents = [System.Collections.Generic.List[Object]]::new()

            $added = $true
            $i.Add($pathParts[$b], $j)
        } `
        else
        {
            $j = $i[$pathParts[$b]]
            $added = $true    # Sort of, it's already there, so we don't want to add it again, but we also don't want to add it to $notAdded.
        }

        # If this is the deepest folder in the path...
        if($b -eq ($pathParts.Length - 1))
        {
            $existingDocOrFolder = $j.Documents | Where-Object { $_.DocumentGUID -eq $fldrGuid }

            if($null -eq $existingDocOrFolder)
            {
                # Create a document entry for this folder
                $k = "" | Select-Object DocumentGUID, CopyOutPath, SPUploadPath

                $k.DocumentGUID = $fldrGuid
                $j.Documents.Add($k)
            } `
            else
            {
                # Nothing...
            }
        } `
        else
        {
            # Nothing...
        }

        $i = $i[$pathParts[$b]].Children

        $b++
    }

    if(-not $added)
    {
        $notAdded.Add($fldrGUID)
    }
}


function GetDocumentPathsFromDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Guid] $documentGUID
    )

    $me = $MyInvocation.MyCommand
    if($viablePathsDict.ContainsKey($documentGUID))
    {
        $d = "" | Select-Object DocumentGUID, ViablePath, OriginalPath

        $pathParts = $viablePathsDict[$documentGUID].Paths

        $d.DocumentGUID = $documentGUID
        $d.ViablePath = $pathParts -join "/"
        $d.OriginalPath = [String]::Empty

        $originalPathParts = [System.Collections.Generic.List[String]]::new()
        $a = 0
        $i = $pathDict
        while($a -lt $pathParts.Length)
        {
            if($i.ContainsKey($pathParts[$a]))
            {
                $originalPathParts.Add($i[$pathParts[$a]].OriginalName)
                $i = $i[$pathParts[$a]].Children
            } `
            else
            {
                LogError ("Missing path dictionary node for {0} of path {1} in {2}." -f @($pathParts[$a], $d.ViablePath, $me.Name))
            }

            $a++
        }

        if(-not $Script:HaveError)
        {
            $d.OriginalPath = $originalPathParts -join "/"
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if([String]::IsNullOrEmpty($d.ViablePath))
        {
            LogError ("Failed to create a viable path for document {0} in {1}." -f @($documentGUID, $me.Name))
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if([String]::IsNullOrEmpty($d.OriginalPath))
        {
            LogError ("Failed to create original path for document {0} in {1}." -f @($documentGUID, $me.Name))
        } `
        else
        {
            # Nothing, already displayed an error
        }
    } `
    else
    {
        LogError ("No viable path entry for GUID: {0} in {1}." -f @($documentGUID, $me.Name))
    }

    return @(, $d)
}

function StuffForSecurity
{

    $security = [PSCustomObject]@{
        UserLists = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
        Groups = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
        Users = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
    }

    $userLists = Get-PWUserLists
    $userGroups = Get-PWGroups
    $userLists.ForEach({
        $userListID = $_.ID.ToString()
        $members = Get-PWUsersInUserList -UserList $_.Name

        $node = [PSCustomObject]@{
            UserList = $_
            Members = [System.Collections.Generic.List[Object]]::new()
        }

        $members.ForEach({
            if(-not $security.Users.ContainsKey($_.ID))
            {
                $security.Users.Add($_.ID.ToString(), $_)
            }

            $node.Members.Add($_)
        })

        $security.UserLists.Add($userListID, $node)
    })

    $userGroups.ForEach({
        $groupID = $_.ID.ToString()
        $members = Get-PWUsersInGroup -GroupName $_.Name

        $node = [PSCustomObject]@{
            Group = $_
            Members = [System.Collections.Generic.List[Object]]::new()
        }

        $members.ForEach({
            if(-not $security.Users.ContainsKey($_.ID))
            {
                $security.Users.Add($_.ID.ToString(), $_)
            }

            $node.Members.Add($_)
        })

        $security.Groups.Add($groupID, $node)
    })


    All this can be dropped.  I can get all the users and groups, all at once...

                    $secCollectionsToResolve = [System.Collections.Generic.List[System.Object]]::new()
                    @($retval.Security | Where-Object { $_.Type -in @("Group","UserList") }).ForEach({
                        $m = [PSCustomObject]@{
                            Name = $_.Name
                            Type = $_.Type
                        }
                        if(@($secCollectionsToResolve | Where-Object { ($_.Name -eq $m.Name) -and ($_.Type -eq $m.Type) }).Length -eq 0)
                        {
                            LogInfo ("New {0} {1} to resolve" -f @($m.Type, $m.Name))
                            $secCollectionsToResolve.Add($m)
                        }
                    })


                    $security.Groups = [System.Collections.Generic.List[System.Object]]::new()
                    $security.UserLists = [System.Collections.Generic.List[System.Object]]::new()
                    $a = 0
                    while((-not $Script:HaveError) -and ($secCollectionsToResolve.Count -gt 0))
                    {
                        LogInfo ("Yet to resolve: {0}" -f @($secCollectionsToResolve.Count))

                        $n = $secCollectionsToResolve[0]
                        $secCollectionsToResolve.RemoveAt(0)

                        $collectionToCheck = $retval.Groups
                        $existingCollection = $null

                        if($n.Type -eq "UserList")
                        {
                            $collectionToCheck = $retval.UserLists
                        } `
                        else
                        {
                            # Nothing.
                        }
                        $existingCollection = $collectionToCheck | Where-Object { $_.Name -eq $n.Name }
                        if($null -eq $existingCollection)
                        {
                            try
                            {
                                LogInfo ("   Getting {0} {1} members..." -f @($n.Type, $n.Name))
                                $m = Get-PWMembers -Type $n.Type -Name $n.Name -ErrorAction Stop

                                if(($null -ne $m) -and ($null -ne $m.Rows))
                                {
                                    # New group or user list...
                                    $z = [PSCustomObject]@{
                                        Name = $n.Name
                                        Members = [System.Collections.Generic.List[System.Object]]::new()
                                    }
                                    $r = 0
                                    while((-not $Script:HaveError) -and ($r -lt $m.Rows.Count))
                                    {
                                        $y = [PSCustomObject]@{
                                            ID = $m.Rows[$r].ID
                                            MemberType = $m.Rows[$r].MemberType
                                            MemberName = $m.Rows[$r].MemberName
                                        }

                                        # Add the new member to the userlist/group members...
                                        $z.Members.Add($y)

                                        # Now check to see if this is a new userlist or group...
                                        $isNewGroup = $false
                                        $isNewUserList = $false
                                        $alreadyQueuedToCheck = @($secCollectionsToResolve | Where-Object { ($_.Name -eq $y.MemberName) -and ($_.Type -eq $y.MemberType) }).Length -gt 0
                                        if(-not $alreadyQueuedToCheck)
                                        {
                                            if($y.MemberType -eq "Group")
                                            {
                                                $isNewGroup = @($retval.Groups | Where-Object { $_.Name -eq $y.MemberName }).Length -eq 0
                                            } `
                                            elseif($y.MemberType -eq "UserList")
                                            {
                                                $isNewUserList = @($retval.UserLists | Where-Object { $_.Name -eq $y.MemberName }).Length -eq 0
                                            } `
                                            else
                                            {
                                                # Nothing, not a group or user list
                                            }

                                            # New group or user list?
                                            if($isNewGroup -or $isNewUserList)
                                            {
                                                LogInfo ("New {0} {1} to resolve" -f @($y.MemberType, $y.MemberName))
                                                $secCollectionsToResolve.Add([PSCustomObject]@{
                                                    Name = $y.MemberName
                                                    Type = $y.MemberType
                                                })
                                            } `
                                            else
                                            {
                                                # Nothing, not a new group or user list...
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, already know about this group/userlist
                                        }

                                        $r++
                                    }

                                    if(-not $Script:HaveError)
                                    {
                                        $collectionToCheck.Add($z)
                                    } `
                                    else
                                    {
                                        # Nothing, already logged an error
                                    }
                                } `
                                else
                                {
                                    LogWarning ("No members returned for {0} {1} in {2}." -f @($n.Type, $n.Name, $me.Name))
                                }
                            }
                            catch
                            {
                                LogError ("Unable to resolve {0} {1} in {2}." -f @($n.Type, $n.Name, $me.Name))
                            }
                        }
                        else
                        {
                            # Nothing, don't add a duplicate Group.
                        }
                        $a++
                    }
#>
}
function ExportDocumentFromPW_UploadToSP
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $td,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $localPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $viablePathsExportPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]] $retryList,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=6)]
        [System.Diagnostics.Stopwatch] $sw,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=7)]
        [Int32] $a,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=8)]
        [Int32] $totalDocuments,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=9)]
        [Int32] $totalRetries,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=10)]
        [Int32] $totalRetried,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=11)]
        [Int32] $retryCount,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=11)]
        [System.Collections.Generic.List[Object]] $docList
    )

    $me = $MyInvocation.MyCommand
    ShowExportUploadProgress -activityID 1 -a $a -sw $sw -totalDocuments $totalDocuments -totalRetries $totalRetries -totalRetried $totalRetried
    if($viablePathsDict.ContainsKey($td.DocumentGUID))
    {
        if(-not $td.IsSet)
        {
            # Has this document already been copied to the local drive?
            if([String]::IsNullOrEmpty($viablePathsDict[$td.DocumentGUID].CopyOutPath))
            {
                # No... need to .CopyOut

                # Create part of the file path to make sure its not blank.
                $filePath = $viablePathsDict[$td.DocumentGUID].Paths -join [System.IO.Path]::DirectorySeparatorChar
                if(-not [String]::IsNullOrEmpty($filePath))
                {
                    $localFilePath = "{0}\{1}" -f @($localPath, $filePath)
                    Write-Progress -Id 2 -Activity "Exporting..." -Status ("{0} [{1:N0}]..." -f @($td.Name, $td.FileSize)) -PercentComplete 0

                    try
                    {
                        # Create a FileInfo from the path to get just the directory for .CopyOut.
                        $fi = [System.IO.FileInfo]::new($localFilePath)

                        # Populate .CopyOutPath once the document has been exported.
                        $copyOutPath = $td.CopyOut($fi.DirectoryName)

                        if([System.IO.File]::Exists($copyOutPath))
                        {
                            $fi2 = [System.IO.FileInfo]::new($copyOutPath)
                            if($fi2.Name -ne $fi.Name)
                            {
                                [System.IO.File]::Move($fi2.FullName, $fi.FullName)
                            } `
                            else
                            {
                                # Nothing.
                            }

                            $viablePathsDict[$td.DocumentGUID].CopyOutPath = $fi.FullName
                        } `
                        else
                        {
                            LogError ("Failed to copy out {0}:{1} in {2}.`r`n`t{3}" -f @($td.DocumentGUID, $localFilePath, $me.Name, $copyOutPath))

                            # I want to log this as an error, but I don't want to stop the script....
                            $Script:HaveError = $false
                        }
                    }
                    catch
                    {
                        LogError ("Failed to export {0} to {1} in {2}." -f @($td.Name, $localFilePath, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Failed to create local file path for document {0} in {1}." -f @($td.DocumentGUID, $me.Name))
                }

                Write-Progress -Id 2 -Activity "Exporting..." -Status ("{0} [{1:N0}]..." -f @($td.Name, $td.FileSize)) -PercentComplete 100
            } `
            else
            {
                # Nothing, already exported the file from projectwise...
            }

            if(-not $Script:HaveError)
            {
                # Make sure we haven't already uploaded the file to sharepoint...
                if([String]::IsNullOrEmpty($viablePathsDict[$td.DocumentGUID].SPUploadPath))
                {
                    # Make sure the file was exported from ProjectWise...
                    if(-not [String]::IsNullOrEmpty($viablePathsDict[$td.DocumentGUID].CopyOutPath))
                    {
                        # Make sure the file exists on disk...
                        if([System.IO.File]::Exists($viablePathsDict[$td.DocumentGUID].CopyOutPath))
                        {
                            if($viablePathsDict[$td.DocumentGUID].Paths.Length -gt 1)
                            {
                                $spFolder = "{0}/{1}" -f @($connData.ConnectionInformation.DocumentLibraryName, ($viablePathsDict[$td.DocumentGUID].Paths[0..($viablePathsDict[$td.DocumentGUID].Paths.Length - 2)] -join "/"))

                                # Build the document properties...
                                $spdocValues = @{
                                    Created = $td.CreateDate
                                    Modified = $td.FileUpdateDate
                                    FileDescription = if($td.Description -ne $td.Name) { $td.Description } else { [String]::Empty }
                                    # revision = $td.Version
                                }
                                if($null -ne $td.Attributes)
                                {
                                    $b = 0
                                    while($b -lt $td.Attributes.Count)
                                    {
                                        $listKeys = @($td.Attributes[$b].Keys)

                                        $c = 0
                                        while($c -lt $listKeys.Length)
                                        {
                                            if(-not [String]::IsNullOrEmpty($td.Attributes[$b][$listKeys[$c]]))
                                            {
                                                $fld = TestForSPDocumentLibraryField -connData $connData -fieldName $listKeys[$c]

                                                if(-not $Script:HaveError)
                                                {
                                                    if(($null -ne $fld) -and (-not $fld.Ignore))
                                                    {
                                                        $spdocValues.Add($fld.InternalName, $td.Attributes[$b][$listKeys[$c]])
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, ignore the property
                                                    }
                                                } `
                                                else
                                                {
                                                    # Nothing, already displayed an error.
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, the attribute value is empty
                                            }
                                            $c++
                                        }

                                        $b++
                                    }
                                } `
                                else
                                {
                                    # Nothing, no attributes to add...
                                }

                                # If the document properties where successfully built, then proceed to upload the document to SharePoint.
                                if(-not $Script:HaveError)
                                {
                                    Write-Progress -Id 3 -Activity "Uploading..." -Status ("{0} [{1:N0}]..." -f @($td.FullPath, $td.FileSize)) -PercentComplete 0

                                    try
                                    {
                                        $spFile = Add-PnPFile -Path $viablePathsDict[$td.DocumentGUID].CopyOutPath -Folder $spFolder -Values $spdocValues -ErrorAction Stop
                                    }
                                    catch
                                    {
                                        if($Error[0].Exception.Message -match "Save Conflict")
                                        {
                                            $r = "" | Select-Object When, Idx, RetryCount
                                            $r.When = [DateTime]::Now.AddSeconds(10)
                                            $r.Idx = $a
                                            $r.RetryCount = $retryCount
                                            $retryList.Add($r)
                                            $totalRetries++
                                            $Error.Clear()
                                        } `
                                        else
                                        {
                                            $Error
                                            LogError ("Failed to upload {0}:{1} to {2} in {3}." -f @($td.DocumentGUID, $viablePathsDict[$td.DocumentGUID].CopyOutPath, $spFolder, $me.Name))
                                            @($spdocValues.Keys).ForEach({
                                                LogInfo ("`t{0} = {1}" -f @($_, $spdocValues[$_]))
                                            })
                                        }
                                    }

                                    if(-not $Script:HaveError)
                                    {
                                        if($null -ne $spFile)
                                        {
                                            $viablePathsDict[$td.DocumentGUID].SPUploadPath = $spFile.ServerRelativeURL

                                            try
                                            {
                                                Remove-Item -Path $viablePathsDict[$td.DocumentGUID].CopyOutPath -Force -ErrorAction Stop
                                            }
                                            catch
                                            {
                                                LogError ("Failed to remove {0} in {1}." -f @($viablePathsDict[$td.DocumentGUID].CopyOutPath, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("No Sharepoint file returned from Add-PnPFile for {0} in {1}." -f @($td.DocumentGUID, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, already displayed an error.
                                    }

                                    Write-Progress -Id 3 -Activity "Uploading..." -Status ("{0} [{1:N0}]..." -f @($td.FullPath, $td.FileSize)) -PercentComplete 100
                                } `
                                else
                                {
                                    # Nothing already displayed an error...
                                }
                            } `
                            else
                            {
                                LogError ("Inviable path for document {0} in {1}." -f @($td.DocumentGUID, $me.Name))
                            }
                        } `
                        else
                        {  <#  TODO:  Need to change this... #>
                            LogError ("File not found in {0}. [{1}:{2}]" -f @($me.Name, $td.DocumentGUID, $viablePathsDict[$td.DocumentGUID].CopyOutPath))

                            # I want to log this as an error, but I don't want to stop the script....
                            $Script:HaveError = $false
                        }
                    } `
                    else
                    { <#   NOTE:  Need to change this...#>
                        LogError ("Attempt to upload file [{0}] to SharePoint without copy out path in {1}." -f @($td.FullPath, $me.Name))

                        # I want to log this as an error, but I don't want to stop the script....
                        $Script:HaveError = $false
                    }
                } `
                else
                {
                    # Nothing, skip upload since we already uploaded it.
                }
            } `
            else
            {
                # Nothing, already displayed an error
            }
        } `
        else
        {
            # Nothing, skip flat set document...
        }
    } `
    else
    {
        LogError ("Missing viable path for document {0} in {1}." -f @($td.DocumentGUID, $me.Name))
    }
}


function BuildVersionProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [Microsoft.SharePoint.Client.ListItemVersionCollection] $versions,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyCollection()]
        [Object] $connData
    )

    $SPVersionProperties = [System.Collections.Generic.List[System.Object]]::new()
    $b = 0
    while($b -lt $versions.Count)
    {
        $versionInfo = [PSCustomObject]@{
            VersionLabel = $versions[$b].VersionLabel
            FieldValues = [System.Collections.Generic.List[System.Object]]::new()
        }

        $fldKeys = @($versions[$b].FieldValues.Keys)
        $fldKeys.Foreach({
            if($connData.documentFields.ContainsKey($_) -and (-not [String]::IsNullOrEmpty($versions[$b].FieldValues[$_])))
            {
                $fv = [PSCustomObject]@{
                    FieldName = $_
                    FieldValue = $versions[$b].FieldValues[$_]
                }
                $versionInfo.FieldValues.Add($fv)
            } `
            else
            {
                # Nothing, ignore this field.
            }
        })
        $SPVersionProperties.Add($versionInfo)

        $b++
    }

    return @(, $SPVersionProperties)
}

function SharePointPathFromPWTreeDocument
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $pwTreeDocument,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $sharePointSiteURI,    # "{0}/sites/{1}/{2}/"

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $uriEncode
    )
<#
    "FullPath": "Archive Projects\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf"
    https://powereng0.sharepoint.com/sites/SP-GVS-ProjectWise-MigrationTest/Shared Documents/Inactive Projects/136723/DMS/ADF-C Outage Analysis/136723 ADF-C Outage Analysis/Blackstart Preparation/Reports/322-131.pdf
#>
    $me = $MyInvocation.MyCommand
    $fp = $pwTreeDocument.FullPath

    # Verify the tree document is part of the correct ProjectWise Path and project
    #   Changed:  We are going to trust the full path...

    <#
            SPECIAL CASE:  If the fullpath starts with "Archive Projects" use "Inactive Projects" for the SharePoint Site.
    #>
    # Remove all illegal characters from the folder and file names
    $folderAndFiles = $fp.Split(@([System.IO.Path]::DirectorySeparatorChar), [System.StringSplitOptions]::RemoveEmptyEntries)

    if($folderAndFiles.Count -ge 1)
    {
        if($folderAndFiles[0] -match "Archive[d]* Projects")
        {
            $folderAndFiles[0] = "Inactive Projects"
        } `
        else
        {
            # Nothing
        }
    } `
    else
    {
        # Nothing
    }

    $a = 0
    while($a -lt $folderAndFiles.Length)
    {
        # Replace all the illegal characters
        @("`"*:<>?/\|").ForEach({
            $folderAndFiles[$a] = $folderAndFiles[$a].Replace($_, "")
        })

        if($uriEncode.IsPresent)
        {
            $folderAndFiles[$a] = [URI]::EscapeDataString($folderAndFiles[$a])
        } `
        else
        {
            # Nothing, leave it alone.
        }

        $a++
    }

    $fp = $folderAndFiles -join "/"

    $fp = "{0}{1}" -f @($sharePointSiteURI, $fp)

    return $fp
}


function LocalPathFromPWTreeDocument
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $pwTreeDocument,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $localPath
    )
<#
    "FullPath": "Archive Projects\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf"
    C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportTest\136723\DMS\ADF-C Outage Analysis\136723 ADF-C Outage Analysis\Blackstart Preparation\Reports\322-131.pdf
#>
    $me = $MyInvocation.MyCommand
    $fp = $pwTreeDocument.FullPath

    # Verify the tree document is part of the correct ProjectWise Path and project
    if($fp -match ("^{0}\\({1}\\.*)$" -f @($pwProjectPath, $projectName)))
    {
        # We've verified the project name, but we need to leave it in the path for the local folder
        $fp = "{0}\{1}" -f @($localPath, $Matches[1])
    } `
    else
    {
        LogError ("Tree document full path: {0} is not part of {1} in {2}." -f @($fp, $pwProjectPath, $me.Name))
        $fp = $null
    }

    return $fp
}


function ShowExportUploadProgress
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Int32] $activityID,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Int32] $a,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [System.Diagnostics.Stopwatch] $sw,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [Int32] $totalDocuments,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [Int32] $totalRetries,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [Int32] $totalRetried,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $Completed
    )

    if(-not $Completed.IsPresent)
    {
        $pc = [float] ($a + $totalRetried) / [float] ($totalDocuments + $totalRetries)
        $status = "{0} of {1} | {2,7:P2} Complete" -f @($a, $totalDocuments, $pc)
        if($a -gt 0)
        {
            $elapsedTicks = $sw.ElapsedTicks
            $ticksPerItem = $elapsedTicks / (($a + 1) + $totalRetried)
            $totalETATicks = $ticksPerItem * ($totalDocuments + $totalRetries)
            $remainingETATicks = $totalETATicks - $elapsedTicks
            $etaTS = [TimeSpan]::new($remainingETATicks)
            $etaDT = [DateTime]::Now.Add($etaTS)

            $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @(($a + $totalRetried), ($totalDocuments + $totalRetries), $pc, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))
        }
        Write-Progress -Id $activityID -Activity "Exporting/Uploading..." -Status $status -PercentComplete ($pc * 100)
    } `
    else
    {
        Write-Progress -Id $activityID -Completed
    }
}


function FromExportUploadFile
{


                                                            # Did I already pull the version info for the current version of the document?
                                                            if(($null -ne $currentDocument.SPData.SPFile.VersionProperties) -and ($null -ne $currentDocument.SPData.SPFile.VersionLinks))
                                                            {
                                                                # Yes...

                                                                # Get the version object that corresponds to the version of the document we need.
                                                                #   This should work... once all documents are uploaded with the "DocumentVersion" field.
                                                                $correctVersion = $currentDocument.SPData.SPFile.VersionProperties | Where-Object { @($_.FieldValues | Where-Object { ($_.FieldName -eq "DocumentVersion") -and ($_.FieldValue -eq $vp.SourceObject.Version) }).Length -gt 0 }

                                                                # Did I find the correct document version?
                                                                if($null -ne $correctVersion)
                                                                {
                                                                    # Yes, now I need to link it to the right version label.
                                                                }

                                                                # $versions.Where({ $_.FieldValues["DocumentVersion"] -eq $vp.SourceObject.Version }) | Select-Object -First 1

                                                            } `
                                                            else
                                                            {
                                                                # We have to go to SharePoint for the data.
                                                            }

                                                            # First, Get the current version of the file from sharepoint...
                                                            $fileURL = "/sites/{0}/{1}/{2}" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName, ($vp.Paths -join "/"))
                                                            try
                                                            {
                                                                $spFile = Get-PnpFile -Url $fileURL -AsListItem -ErrorAction Stop
                                                            }
                                                            catch
                                                            {
                                                                LogError ("Failed to retrieve {0} from SharePoint in {1}." -f @($fileURL, $me.Name))
                                                            }

                                                            if(-not $Script:HaveError)
                                                            {
                                                                if($null -ne $spFile)
                                                                {
                                                                    # Now, get all the versions of the file from SharePoint.
                                                                    try
                                                                    {
                                                                        # This verison data contains the FieldValues I need to determine which version has the right "DocumentVersion", but does not
                                                                        #    include the document URL I need.  It does have .VersionLabel which I'll use to link to $referenceSPDocVersions below.
                                                                        $versions = Get-PnPProperty -ClientObject $spFile -Property Versions -ErrorAction Stop
                                                                    }
                                                                    catch
                                                                    {
                                                                        LogError ("Failed to get field value versions for {0} in {1}." -f @($fileURL, $me.Name))
                                                                    }

                                                                    if(-not $Script:HaveError)
                                                                    {
                                                                        if($null -ne $versions)
                                                                        {

                                                                            # Get the version object with corresponds to the version of the document we need.
                                                                            $correctVersion = $versions.Where({ $_.FieldValues["DocumentVersion"] -eq $vp.SourceObject.Version }) | Select-Object -First 1

                                                                            if($null -ne $correctVersion)
                                                                            {
                                                                                # Now, get all the version references of the file from SharePoint.
                                                                                try
                                                                                {
                                                                                    # This 'version' data contains the URL and VersionLabel
                                                                                    $referenceSPDocVersions = Get-PnpFileVersion -URL $fileURL -ErrorAction Stop
                                                                                }
                                                                                catch
                                                                                {
                                                                                    LogError ("Failed to get reference versions for {0} in {1}." -f @($fileURL, $me.Name))
                                                                                }

                                                                                if(-not $Script:Error)
                                                                                {
                                                                                    if($null -ne $referenceSPDocVersions)
                                                                                    {
                                                                                        # Match VersionLabel to get the right version of the document...
                                                                                        $refDocVersion = $referenceSPDocVersions | Where-Object { $_.VersionLabel -eq $correctVersion.VersionLabel }

                                                                                        if($null -ne $refDocVersion)
                                                                                        {
                                                                                            $docLink = "{0}/sites/{1}/{2}" -f @($connData.ConnectionInformation.SharePointRootURL, $connData.ConnectionInformation.SharePointSiteName, $refDocVersion.Url)
                                                                                        } `
                                                                                        else
                                                                                        {
                                                                                            LogError ("Unable to locate reference version with VersionLabel {0} for document version {1} of {2} in {3}." -f @($correctVersion.VersionLabel, $vp.SourceObject.Version, $fileURL, $me.Name))
                                                                                        }
                                                                                    } `
                                                                                    else
                                                                                    {
                                                                                        LogError ("Unable to locate version {0} of {1} in {2}." -f @($vp.SourceObject.Version, $fileURL, $me.Name))
                                                                                    }
                                                                                } `
                                                                                else
                                                                                {
                                                                                    # Nothing, already logged an error.
                                                                                }
                                                                            } `
                                                                            else
                                                                            {
                                                                                LogError ("Unable to locate a property version for document version {0} for {1} in {2}." -f @($vp.SourceObject.Version, $fileURL, $me.Name))
                                                                            }
                                                                        } `
                                                                        else
                                                                        {
                                                                            LogError ("Failed to retrieve reference versions for {0} from SharePoint in {1}.  Null value returned." -f @($fileURL, $me.Name))
                                                                        }
                                                                    } `
                                                                    else
                                                                    {
                                                                        # Nothing, already logged an error
                                                                    }
                                                                } `
                                                                else
                                                                {
                                                                    LogError ("Failed to retrieve {0} from SharePoint in {1}.  Null value returned." -f @($fileURL, $me.Name))
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, already logged an error
                                                            }
                                                        }
}

function CheckCustomVSAtributes
{
    # So far, this proves I don't need custom attributes...
    $a = 0

    while($a -lt $pwData.PWFolder.TreeDocuments.Count)
    {
        if($null -ne $pwData.PWFolder.TreeDocuments[$a].Attributes)
        {
            if($null -ne $pwData.PWFolder.TreeDocuments[$a].CustomAttributes)
            {
                $b = 0
                while($b -lt $pwData.PWFolder.TreeDocuments[$a].Attributes.Count)
                {
                    $attrKeys = @($pwData.PWFolder.TreeDocuments[$a].Attributes[$b].Keys)
                    $c = 0
                    while($c -lt $attrKeys.Length)
                    {
                        if($pwData.PWFolder.TreeDocuments[$a].CustomAttributes.ContainsKey($attrKeys[$c]))
                        {
                            if($pwData.PWFolder.TreeDocuments[$a].CustomAttributes[$attrKeys[$c]] -ne $pwData.PWFolder.TreeDocuments[$a].Attributes[$b][$attrKeys[$c]])
                            {
                                Write-Host ("TD: {0}`tCustom[{1}] = [{2}]`tAttributes[{3}][{1}] = [{4}]" -f @($a, $attrKeys[$c], $pwData.PWFolder.TreeDocuments[$a].CustomAttributes[$attrKeys[$c]], $b, $pwData.PWFolder.TreeDocuments[$a].Attributes[$b][$attrKeys[$c]]))
                            }
                        }
                        $c++
                    }

                    $customAttrKeys = @($pwData.PWFolder.TreeDocuments[$a].CustomAttributes.Keys)
                    $c = 0
                    while($c -lt $customAttrKeys.Length)
                    {
                        if($pwData.PWFolder.TreeDocuments[$a].Attributes[$b].ContainsKey($customAttrKeys[$c]))
                        {
                            if($pwData.PWFolder.TreeDocuments[$a].CustomAttributes[$customAttrKeys[$c]] -ne $pwData.PWFolder.TreeDocuments[$a].Attributes[$b][$customAttrKeys[$c]])
                            {
                                Write-Host ("TD: {0}`tCustom[{1}] = [{2}]`tAttributes[{3}][{1}] = [{4}]" -f @($a, $customAttrKeys[$c], $pwData.PWFolder.TreeDocuments[$a].CustomAttributes[$customAttrKeys[$c]], $b, $pwData.PWFolder.TreeDocuments[$a].Attributes[$b][$customAttrKeys[$c]]))
                            }
                        } `
                        else
                        {
                            Write-Host ("Missing custom attribute [{0}] = [{1}] in Attributes[{2}]" -f @($customAttrKeys[$c], $pwData.PWFolder.TreeDocuments[$a].CustomAttributes[$customAttrKeys[$c]], $b))
                        }
                        $c++
                    }

                    $b++
                }
            }
        }
        $a++
    }
}

function AddPWDocumentToPathDictNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[String],[Object]]] $testPaths,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [Object] $td
    )

    $fullPathParts = $td.FullPath -split "\\"

    $spDocLibName = TranslateToDocLibName -name $fullPathParts[0]
    if(-not $connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocLibName))
    {
        # Need to create the document library...
        CreateNewDocumentLibrary -connData $connData -spDocLibName $spDocLibName
    } `
    else
    {
        # When I know, I'll fix this.
    }

    $a = 0
    $tdAdded = $false

    while((-not $Script:HaveError) -and (-not $tdAdded) -and ($a -lt $fullPathParts.Length))
    {
        $parentNode = $null
        # Get to the node where the document/folder needs to be added.
        while((-not $Script:HaveError) -and ($testPaths.ContainsKey($fullPathParts[$a])) -and ($a -lt $fullPathParts.Length))
        {
            $parentNode = $testPaths
            $testPaths = $testPaths[$fullPathParts[$a]].Children
            $a++
        }

        # When we exit the loop above, one of these conditions will be true:
        #    1) $Script:HaveError -eq $true -- We have an error ... all bets are off.
        #    2) $a -eq $fullPathParts.Length -- We have checked every path part and we know about everything
        #    3) -not $testPaths.ContainsKey($fullPathParts[$a])  -- Need to add a new node.
        #
        # If condition 3 hits:
        #    $testPaths will be set to where a new node needs to be added.
        #       Do not confuse this with needing to add another source object to the node, we need a new node.
        #       In other words $testPaths did not contain a key named $fullPathParts[$a] therefore we need to add a new node.


        # Did we find nodes for everything?
        if($a -lt $fullPathParts.Length)
        {
            # No, need to add this subfolder to the dictionary.
            $srcObject = $null

            # Is this part the final one?
            if($a -eq ($fullPathParts.Length - 1))
            {
                # Yes...
                $srcObject = $td
                $tdAdded = $true
            } `
            else
            {
                # No... then we need a real projectwise folder for the source object....

                # First, see if there is a subfolder in the project
                $potentialFullPath = $fullPathParts[0..$a] -join "\"
                $existingSubfolder = $pwData.PWFolder.SubFolders | Where-Object { $_.FullPath -eq $potentialFullPath }
                if($null -ne $existingSubfolder)
                {
                    $srcObject = $existingSubfolder
                } `
                else
                {
                    # We need to get the folder from ProjectWise.
                    try
                    {
                        $sf = Get-PWFolders -FolderPath $potentialFullPath -JustOne -Slow -ErrorAction Stop 3> $null

                        if($null -ne $sf)
                        {
                            $srcObject = $sf
                        } `
                        else
                        {
                            LogError ("Failed to retrieve folder {0} from ProjectWise in {1}.  Null value returned." -f @($potentialFullPath, $me.Name))
                        }
                    }
                    catch
                    {
                        LogError ("Failed to retrieve folder {0} from ProjectWise in {1}." -f @($potentialFullPath, $me.Name))
                    }
                }
            }

            if((-not $Script:HaveError) -and ($null -ne $srcObject))
            {
                $newNode = NewPathDictNode -nodeName $fullPathParts[$a] -parentNode $parentNode -isFixed (($a -eq 0) -or ($a -eq 1)) -srcObject $srcObject
                $testPaths.Add($newNode.OriginalName, $newNode)
            } `
            else
            {
                LogError ("Attempt to add new new with no source object in {0}." -f @($me.Name))
                LogError ("`tfull path part: {0}" -f @($td.FullPath))
                LogError ("`tpath part: {0}" -f @($fullPathParts[$a]))
            }
        } `
        else
        {
            # Yes... we found nodes for everything....

            # Make sure the parent node contains a child for the last part of the path.
            if($parentNode.ContainsKey($fullPathParts[-1]))
            {
                if(-not $tdAdded)
                {
                    if($td -is [PWPS_DAB.CommonTypes+ProjectWiseFolder])
                    {
                        $existingSrcObject = $parentNode[$fullPathParts[-1]].SourceObjects | Where-Object { ($_ -is [PWPS_DAB.CommonTypes+ProjectWiseFolder]) -and ($_.FullPath -eq $td.FullPath) }
                    } `
                    else
                    {
                        $existingSrcObject = $parentNode[$fullPathParts[-1]].SourceObjects | Where-Object { ($_ -is [PWPS_DAB.CommonTypes+ProjectWiseDocument]) -and ($_.DocumentGUID -eq $td.DocumentGuid) }
                    }

                    if($null -eq $existingSrcObject)
                    {
                        $parentNode[$fullPathParts[-1]].SourceObjects.Add($td)
                    } `
                    else
                    {
                        # Nothing, don't add the same source object more than once.
                        if($Script:DoDebugging)
                        {
                            # LogInfo ("Duplicate TD: {0}" -f @($td.FullPath))
                        }
                    }
                } `
                else
                {
                    # Nothing, this was likely the first time seeing the path and we already added the source object to a new node...
                }
            } `
            else
            {
                LogError ("ParentNode does not contain a value for {0} in {1}." -f @($fullPathParts[-1], $me.Name))
                LogError ("`tFullPath: {0}" -f @($td.FullPath))
            }
            # Nothing, at the end of the path...
        }
    }

    # Now all the subfolders and file name have been added to $testPath.
}

function CreatePathDictionary_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData
    )

    # Build another dictionary used to shorten paths.
    # $testPaths = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()

    # Create the dictionary root
    $topPaths = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
    $newNode = NewPathDictNode -nodeName "ROOT" -isFixed $true -parentNode $null -srcObject $null
    $topPaths.Add($newNode.OriginalName, $newNode)

    $Error.Clear()

    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $pwData.PWFolder.SubFolders.Count))
    {
        $pc = [float] $a / [float] $pwData.PWFolder.SubFolders.Count
        Write-Progress -Id 1 -Activity ("Processing subfolder {0} of {1}" -f @(($a + 1), $pwData.PWFolder.SubFolders.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

        AddPWDocumentToPathDictNew -connData $connData -pwData $pwData -testPaths $topPaths["ROOT"].Children -td $pwData.PWFolder.SubFolders[$a]
        $a++
    }
    Write-Progress -Id 1 -Completed

    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $pwData.PWFolder.TreeDocuments.Count))
    {
        $pc = [float] $a / [float] $pwData.PWFolder.TreeDocuments.Count
        Write-Progress -Id 1 -Activity ("Processing Document {0} of {1}" -f @(($a+1), $pwData.PWFolder.TreeDocuments.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

        $td = $pwData.PWFolder.TreeDocuments[$a]

        AddPWDocumentToPathDictNew -connData $connData -pwData $pwData -testPaths $topPaths["ROOT"].Children -td $td
        $a++
    }
    Write-Progress -Id 1 -Completed

    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $pwData.FlatSets.Count))
    {
        $pc = [float] $a / [float] $pwData.FlatSets.Count
        Write-Progress -Id 1 -Activity ("Processing Flatset document {0} of {1}" -f @(($a+1),$pwData.FlatSets.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

        # Add the referenced documents to the dictionary.
        $b = 0
        while((-not $Script:HaveError) -and ($b -lt $pwData.FlatSets[$a].References.Count))
        {
            AddPWDocumentToPathDictNew -connData $connData -pwData $pwData -testPaths $topPaths["ROOT"].Children -td $pwData.FlatSets[$a].References[$b]

            $b++
        }

        # Add the referenced document versions to the dictionary.
        $b = 0
        $fsDocuments = @($pwData.FlatSets[$a].Documents.Values)
        while((-not $Script:HaveError) -and ($b -lt $fsDocuments.Length))
        {
            AddPWDocumentToPathDictNew -connData $connData -pwData $pwData -testPaths $topPaths["ROOT"].Children -td $fsDocuments[$b]

            $b++
        }

        $a++
    }
    Write-Progress -Id 1 -Completed

    return @( , $topPaths)
}

function BuildViablePathsDictionaryNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $fromNode,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyString()]
        [String] $parentPath = "",

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[Guid,Object]] $allTestPaths = $null
    )

    $me = $MyInvocation.MyCommand
    if($null -eq $parentPath)
    {
        $parentPath = ""
    } `
    else
    {
        # Nothing
    }

    if($null -eq $allTestPaths)
    {
        $allTestPaths = [System.Collections.Generic.SortedDictionary[Guid,Object]]::new()
    } `
    else
    {
        # Nothing
    }

    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $fromNode[$keys[$a]].ShortenedName

        if($fromNode[$keys[$a]].SourceObjects.Count -gt 0)
        {
            $b = 0
            while($b -lt $fromNode[$keys[$a]].SourceObjects.Count)
            {
                # If this source object is a document, then check to see if there is a flatset that references it.
                $isFlatSetReference = $false
                if($fromNode[$keys[$a]].SourceObjects[$b] -is [PWPS_DAB.CommonTypes+ProjectWiseDocument])
                {
                    $isFlatSetReference = @(@($pwData.FlatSets).Foreach({ $_.References | Where-Object { $_.DocumentGUID -eq $fromNode[$keys[$a]].SourceObjects[$b].DocumentGUID }})).Length -gt 0
                } `
                else
                {
                    # Nothing, not a document
                }
                $paths = @($pathToTest -split "/")

                $d = NewViablePathsNode
                $d.Paths = $paths
                $d.SourceObject = $fromNode[$keys[$a]].SourceObjects[$b]
                $d.IsFlatSetReference = $isFlatSetReference    # If this document is referenced by a flatset, then we need version information for it.

                $paths[0] = TranslateToDocLibName -name $paths[0]

                if($fromNode[$keys[$a]].SourceObjects[$b] -is [PWPS_DAB.CommonTypes+ProjectWiseDocument])
                {
                    $d.SPData.FolderName = $paths[0..($paths.Length - 2)] -join "/"
                    $d.SPData.FileName = $paths[-1]
                    $nodeGUID = $fromNode[$keys[$a]].SourceObjects[$b].DocumentGUID
                } `
                else
                {
                    $d.SPData.FolderName = $paths -join "/"
                    $nodeGUID = [Guid]::NewGuid()     # Just need a placeholder...
                }

                $allTestPaths.Add($nodeGUID, $d)

                $b++
            }
        } `
        else
        {
            # Nothing....right???
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            $null = BuildViablePathsDictionaryNew -pwData $pwData -fromNode $fromNode[$keys[$a]].Children -parentPath ($pathToTest + "/") -allTestPaths $allTestPaths
        } `
        else
        {
            # Nothing, no child nodes to follow...
        }
        $a++
    }

    return @( , $allTestPaths)
}

function LoadViablePaths_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $savePath
    )

    $me = $MyInvocation.MyCommand
    $viablePathsDict2 = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()

    try
    {
        $jsonContent = Get-Content -Path $savePath -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to read JSON data from {0} in {1}." -f @($savePath, $me.Name))
    }

    try
    {
        $data = $jsonContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to convert JSON data from {0} into an object in {1}." -f @($savePath, $me.Name))
    }

    if(-not $Script:HaveError)
    {
        $a = 0
        while($a -lt $data.Length)
        {
            $d = NewViablePathsNode

            $d.Paths = $data[$a].Paths
            $d.SourceObject = $data[$a].SourceObject
            $d.CopyOutPath = $data[$a].CopyOutPath
            $d.SPData.FolderName = $data[$a].SPData.FolderName
            $d.SPData.FileName = $data[$a].SPData.FileName
            $d.SPData.SPFile.ServerRelativeURL = $data[$a].SPData.SPFile.ServerRelativeURL
            $d.SPData.SPFile.VersionLabel = $data[$a].SPData.SPFile.VersionLabel
            $d.SPData.Processed = $data[$a].SPData.Processed
            $d.SPData.WhenUploaded = $data[$a].SPData.WhenUploaded
            $d.SPData.DocVersionToLink = $null     # Can't initialize this, or later in the code, it won't know to build the list
            $data[$a].SPData.DocSetLinksCreated.Foreach({ $d.SPData.DocSetLinksCreated.Add($_) })
            $d.IsFlatSetReference = $data[$a].IsFlatSetReference

            if($data[$a].SPData.DocVersionToLink.Length -gt 0)
            {
                # It's safe to initialize this here, because we actually have stuff to add to it.
                $d.SPData.DocVersionToLink = [System.Collections.Generic.SortedDictionary[String, String]]::new()
                $data[$a].SPData.DocVersionToLink.ForEach({
                    $d.SPData.DocVersionToLink.Add($_.DocumentVersion, $_.Link)
                })
            } `
            else
            {
                # Nothing, no document versions to links...
            }

            $viablePathsDict2.Add($data[$a].GUID, $d)
            $a++
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    return @(, $viablePathsDict2)
}

function GetProjectWiseData_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $pwProjectPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $projectName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [String] $localPath
    )

    $me = $MyInvocation.MyCommand
    $retval = [PSCustomObject]@{
        StorageAreas = $null
        JSONData = $null
        JSONFile = $null
        PWFolder = $null
        FlatSets = $null
        Security = $null
        Groups = $null
        UserLists = $null
        SubFolderGuidToPWSubFolder = [System.Collections.Generic.SortedDictionary[Guid, PWPS_DAB.CommonTypes+ProjectWiseFolder]]::new()
    }

    $retval2 = [PSCustomObject]@{
        PWFolder = $null
        ProjectWiseObjects = [System.Collections.Generic.SortedDictionary[Guid, Object]]::new()
        Security = $null
    }

    $Error.Clear()

    $lookupDict = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()

    if([System.IO.Directory]::Exists($localPath))
    {
        $pwPath = "{0}\{1}" -f @($pwProjectPath, $projectName)
        try
        {
            # Get the associated ProjectWise folder along with all the relevant data "-Slow" ...
            LogInfo ("Getting PW Folder for {0}..." -f @($pwPath))
            $retval.PWFolder = Get-PWFolders -FolderPath $pwPath -JustOne -Slow 3> $null

            if($null -ne $retval.PWFolder)
            {
                $newNode = NewMyProjectWiseFolder -folder $retval.PWFolder
                $retval2.PWFolder = $newNode
                $retval2.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)
            } `
            else
            {
                LogError ("Failed to get ProjectWise project folder for {0} in {1}." -f @($pwPath, $me.Name))
            }
        }
        catch
        {
            LogError ("Failed to locate ProjectWise Folder using path: {0}" -f @($pwPath))
            $retval.PWFolder = $null
        }

        if(-not $Script:HaveError)
        {
            $retval.StorageAreas = GetStorageDictionary
        } `
        else
        {
            # Nothing, already displayed an error.
        }

        if((-not $Script:HaveError) -and ($null -ne $retval.PWFolder))
        {
            $retval.FlatSets = [System.Collections.Generic.List[Object]]::new()

            # The code below looks odd, we are getting data, but returning it to $null.  The reason is,
            #    the code behind actaully populates $retval.PWFolder with the returned data.

            try
            {
                # Get a list of all the subfolders in the project
                LogInfo "Getting project subfolders..."
                $null = $retval.PWFolder.GetSubFolders()
            }
            catch
            {
                LogError ("Failed to get project subfolders.")
                $retval.PWFolder = $null
            }

            if((-not $Script:HaveError) -and ($null -ne $retval.PWFolder))
            {
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $retval.PWFolder.SubFolders.Count))
                {
                    $existingFolders = @(@($retval2.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseFolder") -and ($_.FullPath -eq $retval.PWFolder.SubFolders[$a].FullPath) }))
                    if($existingFolders.Length -eq 0)
                    {
                        $newNode = NewMyProjectWiseFolder -folder $retval.PWFolder.SubFolders[$a]
                        $retval2.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)
                    } `
                    else
                    {
                        # Don't add duplicate folders.
                    }
                    $retval.SubFolderGuidToPWSubFolder.Add([Guid]::NewGuid(), $retval.PWFolder.SubFolders[$a])
                    $a++
                }
            } `
            else
            {
                # should have already logged an error
            }

            # Get the project folder security info
            if((-not $Script:HaveError) -and ($null -ne $retval.PWFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    LogInfo "Getting project folder security..."
                    $retval.Security = @($retval.PWFolder | Get-PWFolderSecurity -ErrorAction Stop | Where-Object { $_.WorkFlow -is [System.DBNull] } | Select-Object ProjectName,SecurityType,Type,Name,Access_Control_Settings,WorkFlow,State,InheritingFrom,FullPath)
                    $retval2.Security = $retval.Security
                }
                catch
                {
                    LogError ("Failed to get project folder security details.")
                    $retval.PWFolder = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if((-not $Script:HaveError) -and ($null -ne $retval.PWFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    LogInfo "Getting project document tree..."
                    $null = $retval.PWFolder.GetTreeDocuments()
                }
                catch
                {
                    LogError ("Failed to get project documents.")
                    $retval.PWFolder = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if((-not $Script:HaveError) -and ($null -ne $retval.PWFolder))
            {
                #  NOTE:  Check for IsSet before GetGeneralProperties and GetCustomAttributes ....
                #     Need to know if they need to be successful before evaluting .IsSet...

                LogInfo "Getting project document properties and custom attributes..."
                # Now, populate all the attributes for the documents.
                $totalDocuments = $retval.PWFolder.TreeDocuments.Count
                $i = 0
                while((-not $Script:HaveError) -and ($null -ne $retval.PWFolder) -and ($i -lt $retval.PWFolder.TreeDocuments.Count))
                {

                    if(-not $lookupDict.ContainsKey($retval.PWFolder.TreeDocuments[$i].DocumentGUID))
                    {
                        $lookupDict.Add($retval.PWFolder.TreeDocuments[$i].DocumentGUID, $retval.PWFolder.TreeDocuments[$i])
                    } `
                    else
                    {
                        LogError ("Duplicate document GUID [{0}] in {1}." -f @($retval.PWFolder.TreeDocuments[$i].DocumentGUID))
                    }
                    $pc = [float] $i / [float] $totalDocuments
                    Write-Progress -Id 1 -Activity ("Processing Document {0} of {1}" -f @(($i+1), $totalDocuments)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                    GetPWDocumentAttributes -doc $retval.PWFolder.TreeDocuments[$i]

                    if(-not $Script:HaveError)
                    {
                        $newNode = NewMyProjectWiseDocument -doc $retval.PWFolder.TreeDocuments[$i]
                        $retval2.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)

                        if($retval.PWFolder.TreeDocuments[$i].IsSet)
                        {
                            $flatSetNode = $newNode
                            $flatSetNode.FlatSetReferences = [System.Collections.Generic.List[Guid]]::new()
                            try
                            {
                                $fs =  $retval.PWFolder.TreeDocuments[$i] | Get-PWDocumentFlatSetMembers -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to acquire flat set: {0} from {1}.  Index: {2}" -f @($retval.PWFolder.TreeDocuments[$i].Name, $retval.PWFolder.TreeDocuments[$i].FolderPath, $i))
                            }

                            if((-not $Script:HaveError) -and ($null -ne $fs))
                            {
                                $j = [PSCustomObject]@{
                                    TreeDocument = $retval.PWFolder.TreeDocuments[$i]
                                    References = $fs
                                    Documents = [System.Collections.Generic.SortedDictionary[Guid, Object]]::new()     # This will be where I put all versions of the referenced documents.
                                }

                                $q = 0
                                while((-not $Script:HaveError) -and ($q -lt $fs.Count))
                                {
                                    try
                                    {
                                        # This is a slow mess, but I don't see a better solution...
                                        # First have to get documents full path... DUMB!!
                                        $null = $fs[$q].GetFolderPath()
                                        $allDocVersions = Get-PWDocumentsBySearch -DocumentName $fs[$q].Name -FolderPath $fs[$q].FolderPath -JustThisFolder -GetVersionsToo -PopulatePath -GetAttributes -ErrorAction Stop
                                    }
                                    catch
                                    {
                                        LogError ("Failed to retrieve all document versions for flatset document {0}:{1} in {2}." -f @($fs[$q].DocumentGUID, $fs[$q].FullPath, $me.Name))
                                    }

                                    if(-not $Script:HaveError)
                                    {
                                        if($null -ne $allDocVersions)
                                        {
                                            $r = 0
                                            while((-not $Script:HaveError) -and ($r -lt $allDocVersions.Length))
                                            {
                                                if(-not $j.Documents.ContainsKey($allDocVersions[$r].DocumentGUID))
                                                {
                                                    GetPWDocumentAttributes -doc $allDocVersions[$r]

                                                    if(-not $Script:HaveError)
                                                    {
                                                        if(-not $retval2.ProjectWiseObjects.ContainsKey($allDocVersions[$r].DocumentGUID))
                                                        {
                                                            $flatSetReferencedNode = NewMyProjectWiseDocument -doc $allDocVersions[$r]
                                                            $retval2.ProjectWiseObjects.Add($flatSetReferencedNode.DocumentGuid, $flatSetReferencedNode)
                                                        } `
                                                        else
                                                        {
                                                            $flatSetReferencedNode = $retval2.ProjectWiseObjects[$allDocVersions[$r].DocumentGUID]
                                                        }

                                                        # Is this the actual version of the reference we need?
                                                        #   NOTE: Still need to add it to .ProjectWiseObjects so we can upload it, but right now, I just want to annotate if it's the real mccoy.
                                                        if($allDocVersions[$r].DocumentGUID -eq $fs[$q].DocumentGUID) # $allDocVersions[$r].Version -eq $fs[$q].Version)
                                                        {
                                                            $flatSetReferencedNode.IsFlatSetReference = $true

                                                            if($flatSetNode.FlatSetReferences -notcontains $flatSetReferencedNode.DocumentGUID)
                                                            {
                                                                $flatSetNode.FlatSetReferences.Add($flatSetReferencedNode.DocumentGUID)
                                                            } `
                                                            else
                                                            {
                                                                # Sorry, only 1 reference per original document
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, don't mark the node as a flatset reference, nor add it to the flatset's references...
                                                        }
                                                        $j.Documents.Add($allDocVersions[$r].DocumentGUID, $allDocVersions[$r])
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already logged an error.
                                                    }
                                                } `
                                                else
                                                {
                                                    # Nothing, just don't add a duplicate document...
                                                }
                                                $r++
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Failed to retrieve all document versions for flatset document {0}:{1} in {2}.  No documents returned." -f @($fs[$q].DocumentGUID, $fs[$q].FullPath, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, already logged an error.
                                    }
                                    $q++
                                }

                                $retval.FlatSets.Add($j)
                            } `
                            else
                            {
                                LogError ("No flat set returned from ProjectWise for document GUID {0} to flatset for {1} in {2}." -f @($retval.PWFolder.TreeDocuments[$i].DocumentGUID, $retval.PWFolder.TreeDocuments[$i].FullPath, $me.Name))
                            }
                        } `
                        else
                        {
                            # Not a flatset, so nothing to do here.
                        }
                    } `
                    else
                    {
                        $retval.PWFolder = $null
                    }

                    $i++
                }

                if($retval.FlatSets.Count -gt 0)
                {
                    LogInfo "Resolving flatset items..."
                } `
                else
                {
                    # Nothing.
                }

                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $retval.FlatSets.Count))
                {
                    $pc = [float] $a / [float] $retval.FlatSets.Count
                    Write-Progress -Id 1 -Activity ("Processing flatset item {0} of {1}" -f @(($a+1), $retval.FlatSets.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                    $b = 0
                    while((-not $Script:HaveError) -and ($b -lt $retval.FlatSets[$a].References.Count))
                    {
                        if($lookupDict.ContainsKey($retval.FlatSets[$a].References[$b].DocumentGUID))
                        {
                            $retval.FlatSets[$a].References[$b] = $lookupDict[$retval.FlatSets[$a].References[$b].DocumentGUID]
                        } `
                        else
                        {
                            Write-Progress -Id 2 -Activity ("Retrieving {0} from PW." -f @($retval.FlatSets[$a].References[$b].DocumentURN)) -Status "..." -PercentComplete 0

                            try
                            {
                                $fp = Get-PWDocumentByURN -URN $retval.FlatSets[$a].References[$b].DocumentURN -ErrorAction Stop

                                # $fp = Get-PWDocumentsBySearch -DocumentName $retval.FlatSets[$a].References[$b].Name -FolderPath $retval.FlatSets[$a].References[$b].FolderPath -Version $retval.FlatSets[$a].References[$b].Version -PopulatePath -GetAttributes -ErrorAction Stop
                                if($null -ne $fp)
                                {
                                    $lookupDict.Add($fp.DocumentGUID, $fp)
                                    $retval.FlatSets[$a].References[$b] = $fp

                                    GetPWDocumentAttributes -doc $retval.FlatSets[$a].References[$b]
                                } `
                                else
                                {
                                    LogError ("Failed to retrieve flatset reference document {0} in {1}.  Null return value." -f @($retval.FlatSets[$a].References[$b].DocumentGUID, $me.Name))
                                }
                            }
                            catch
                            {
                                LogError ("Failed to retrieve flatset reference document {0} in {1}." -f @($retval.FlatSets[$a].References[$b].DocumentGUID, $me.Name))
                            }
                            Write-Progress -Id 2 -Completed
                        }

                        $b++
                    }

                    $a++
                }
                Write-Progress -Id 1 "Finished" -Completed
            } `
            else
            {
                # Should have already displayed an error
            }
        } `
        else
        {
            # Should have already displayed an error.
        }
    } `
    else
    {
        LogError ("{0} not found.  Please provide an existing path." -f @($localPath))
    }

    return @($retval,$retval2)
}

function FixLongPathsNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pathDict
    )

    $spLimitPrefix = "sites/{0}/{1}/" -f @($connData.ConnectionInformation.SharePointSiteName, $connData.ConnectionInformation.DocumentLibraryName)
    $spLimitPrefixLength = $spLimitPrefix.Length

    $pathTooLongToOriginalPath = [System.Collections.Generic.SortedDictionary[String,String]]::new()
    $pathsTooLong = [System.Collections.Generic.List[String]]::new()
    # $pathsTooLong | Set-Clipboard

    GetPathsTooLongFromDictionaryNew -connData $connData -fromNode $pathDict["ROOT"].Children -parentPath "" -originalParentPath "" -pathsTooLong $pathsTooLong -pathTooLongToOriginalPath $pathTooLongToOriginalPath

    if(-not $Script:HaveError)
    {
        # GetPathsTooLongFromDictionary -fromNode $pathDict -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
        $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending)
        # $pathsTooLong is now an array....

        $maxLongPaths = $pathsTooLong.Length
        while((-not $Script:HaveError) -and ($pathsTooLong.Length -gt 0))
        {
            $pc = [float] ($maxLongPaths - $pathsTooLong.Length) / [float] $maxLongPaths
            Write-Progress -Id 1 -Activity ("Processing {0}" -f @($pathsTooLong[0])) -Status ("{0} of {1} ({2,7:P}) Complete" -f @(($maxLongPaths - $pathsTooLong.Length), $maxLongPaths, $pc)) -PercentComplete ($pc * 100)

            if($pathTooLongToOriginalPath.ContainsKey($pathsTooLong[0]))
            {
                $originalPath = $pathTooLongToOriginalPath[$pathsTooLong[0]]
                $originalPathPieces = @($originalPath -split "/")

                if(($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength))
                {
                    $pathPieces = @($pathsTooLong[0] -split "/")

                    if($pathPieces.Length -gt 2)
                    {
                        # The first 2 placeholders in the path are always fixed....
                        $longestPiece = ($pathPieces | Select-Object -Skip 2) | Sort-Object Length -Descending | Select-Object -First 1
                        $longestPieceIdx = $pathPieces.IndexOf($longestPiece)
                        $lpMinLength = 2

                        # $node = $pathDict
                        $node = $pathDict["ROOT"].Children
                        $c = 0
                        while((-not $Script:HaveError) -and ($c -lt $longestPieceIdx))
                        {
                            if($node.ContainsKey($originalPathPieces[$c]))
                            {
                                $node = $node[$originalPathPieces[$c]].Children
                            } `
                            else
                            {
                                LogError ("Missing node for {0}" -f @($originalPathPieces[$c]))
                            }
                            $c++
                        }

                        $fi = $null

                        # Is the longest piece the file name??
                        if($longestPieceIdx -eq ($pathPieces.Length - 1))
                        {
                            # This is the file name...
                            $fi = [System.IO.FileInfo]::new($longestPiece)
                            $longestPiece = $fi.BaseName
                            $lpMinLength += $fi.Extension.Length
                        } `
                        else
                        {
                            # Nothing....
                        }

                        $originalLP = $longestPiece

                        # When $x -eq 0 the script first removes leading and trailing spaces from the name and replaces all double spaces with single spaces.
                        $x = 0

                        # Start at the first counter character if we need it...
                        $i = 0

                        do {
                            if($x -eq 0)
                            {
                                $longestPiece = $longestPiece.Trim()
                                while($longestPiece -match "  ")
                                {
                                    $longestPiece = $longestPiece.Replace("  ", " ")
                                }
                                $x++
                            } `
                            elseif($x -gt 0)
                            {
                                do
                                {
                                    $longestPiece = $originalLP.SubString(0, $originalLP.Length - $x)
                                    if($longestPiece.EndsWith(" "))
                                    {
                                        $x++
                                    }
                                } while(($longestPiece.Length -gt $lpMinLength) -and ($longestPiece.EndsWith(" ")))

                                if($x -gt 1)
                                {
                                    $longestPiece += $COUNTER_CHARACTERS[$i]
                                    $i++
                                    if($i -eq $COUNTER_CHARACTERS.Length)
                                    {
                                        $i = 0
                                        $x++
                                    }
                                } `
                                else
                                {
                                    $x++
                                }
                            } `
                            else
                            {
                                # TODO:  What????
                            }

                            if($x -ge ($originalLP.Length - 3))
                            {
                                LogError ("Unable to shorten {0} enough.`r`n`tOffending piece: {1}" -f @($pathsTooLong[0], $originalLP))
                            } `
                            else
                            {
                                if($null -ne $fi)
                                {
                                    $longestPiece += $fi.Extension
                                } `
                                else
                                {
                                    # Nothing, don't add a non-existant extension...
                                }
                            }
                            $isDuplicate = @(@($node.Values) | Where-Object { ($_.ShortenedName -eq $longestPiece) -or ($_.OriginalName -eq $longestPiece) }).Length -gt 0
                        } while((-not $Script:HaveError) -and ($x -lt ($originalLP.Length - 3)) -and ($i -lt $COUNTER_CHARACTERS.Length) -and ($longestPiece.Length -gt $lpMinLength) -and ($isDuplicate))

                        # Found a substitute name...
                        if(-not $Script:HaveError)
                        {
                            $pathPieces[$longestPieceIdx] = $longestPiece
                            $pathsTooLong[0] = $pathPieces -join "/"
                            if(-not $pathTooLongToOriginalPath.ContainsKey($pathsTooLong[0]))
                            {
                                # Since we changed $pathsTooLong[0], we need to add a new dictionary entry for it...
                                $pathTooLongToOriginalPath.Add($pathsTooLong[0], $originalPath)

                                if($node.ContainsKey($originalPathPieces[$longestPieceIdx]))
                                {
                                    $node[$originalPathPieces[$longestPieceIdx]].ShortenedName = $longestPiece

                                    if($null -eq $fi)
                                    {
                                        if($null -ne $node[$longestPiece].Children)
                                        {
                                            @($node[$longestPiece].Children).ForEach({ RevertToOriginalNew -fromNode $_ })
                                        } `
                                        else
                                        {
                                            # Nothing, no children to revert.
                                        }

                                        # If this was not a file node, then rebuild the list of paths which are too long...
                                        $pathsTooLong = [System.Collections.Generic.List[String]]::new()   # Can't just clear $pathsTooLong....it's an array...

                                        $pathTooLongToOriginalPath.Clear()
                                        GetPathsTooLongFromDictionaryNew -connData $connData -fromNode $pathDict["ROOT"].Children -parentPath "" -originalParentPath "" -pathsTooLong $pathsTooLong -pathTooLongToOriginalPath $pathTooLongToOriginalPath
                                    } `
                                    else
                                    {
                                        # Nothing, we didn't alter a subfolder name, so no need to re-initialize everything...
                                    }
                                } `
                                else
                                {
                                    LogError ("Missing node for {0}" -f @($originalPathPieces[$c]))
                                }
                                # Sort $pathsTooLong, putting the longest one on top and removing any paths which are now viable....
                                $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending | Where-Object { ($_.Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)})

                                # ($pathsTooLong[0].Length + 1) -gt ($MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength)
                            } `
                            else
                            {
                                LogError ("Duplicate path too long in path to original dictionary for shortened path [{0}] in {1}" -f @($pathsTooLong[0], $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        LogError ("Path too short [{0}], cannot shorten in {1}." -f @($pathsTooLong[0], $me.Name))
                    }
                } `
                else
                {
                    LogError ("Why is {0} in the list of paths too long? Length={1}" -f @($pathsTooLong[0], $pathsTooLong[0].Length))
                }
            } `
            else
            {
                LogError ("Missing original path for path too long {0} in {1}." -f @($pathsTooLong[0], $me.Name))
            }
        }

        if($maxLongPaths -gt 0)
        {
            Write-Progress -Id 1 -Completed
        } `
        else
        {
            # Nothing, didn't have any paths to fix...
        }
    } `
    else
    {
        # Nothing, already logged an error
    }
}

function ExportPW2SPNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $viablePathsExportPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [String] $localPath,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $uriEncode
    )

    $me = $MyInvocation.MyCommand
    $PSStyle.Progress.View = 'Minimal'
    $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
    $Error.Clear()
    $sw = [System.Diagnostics.Stopwatch]::new()
    $sw.Start()

    $null = CreateSharePointProjectFolder -connData $connData -pwFolder $pwData.PWFolder -viablePathsDict $viablePathsDict

    if(-not $Script:HaveError)
    {
        CreateSharePointProjectSubFoldersNew -connData $connData -pwData $pwData -viablePathsDict $viablePathsDict
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    # Where we export $viablePathsDict to, to track progress.
    ExportViablePathsStructureNew -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath

    $sw = [System.Diagnostics.Stopwatch]::new()
    $sw.Start()
    if(-not $Script:HaveError)
    {
        $documentsToUpload = [System.Collections.Generic.List[System.Object]]::new()
        $allDocuments = [System.Collections.Generic.List[System.Object]]::new()
        $flatSets = [System.Collections.Generic.List[System.Object]]::new()
        $flatSetReferences = [System.Collections.Generic.List[System.Object]]::new()

        # Only get:
        #    Objects which are more than 2 levels deep  $_.Paths.Length -eq 1 = Active/Inactive projects (the document library), $_.Paths.Length -eq 2 = project folder.
        #    ProjectWise Documents
        #    which have not been uploaded
        #    are not flatsets -- I'll handle them differently
        @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseDocument]) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} ).Foreach({
            if(-not $_.SourceObject.IsSet)
            {
                $allDocuments.Add($_)
            } `
            else
            {
                $flatSets.Add($_)
            }

            if($_.IsFlatSetReference)
            {
                $flatSetReferences.Add($_)
            } `
            else
            {
                # Nothing...
            }

            if(-not $_.SPData.Processed)
            {
                $documentsToUpload.Add($_)
            } `
            else
            {
                # Nothing, not uploading this document
            }
        })

        $totalUploadSize = ($documentsToUpload | Measure-Object -Sum { $_.SourceObject.FileSize }).Sum
        $totalSizeUploaded = 0
        $documentsUploaded = 0
        $uploadSkipped = 0
        LogInfo ("Total Documents: {0}" -f @($allDocuments.Count))
        LogInfo ("Total FlatSets: {0}" -f @($flatSets.Count))
        LogInfo ("Documents to upload: {0}" -f @($documentsToUpload.Count))
        LogInfo ("Flatset referenced documents: {0}" -f @($documentsToUpload.Count))

        $a = 0
        while((-not $Script:HaveError) -and ($documentsToUpload.Count -gt 0))
        {
            $documentVersionsToUpload = @($documentsToUpload | Where-Object { $_.SourceObject.FullPath -eq $documentsToUpload[0].SourceObject.FullPath })

            $pc = [float] ($totalSizeUploaded) / [float] ($totalUploadSize)
            $status = "{0} of {1} | {2,7:P2} Complete" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc)
            if($totalSizeUploaded -gt 0)
            {
                $elapsedTicks = $sw.ElapsedTicks
                $ticksPerItem = $elapsedTicks / $totalSizeUploaded
                $totalETATicks = $ticksPerItem * ($totalUploadSize)
                $remainingETATicks = $totalETATicks - $elapsedTicks
                $etaTS = [TimeSpan]::new($remainingETATicks)
                $etaDT = [DateTime]::Now.Add($etaTS)

                $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss"))
            }
            $activity = "Uploading {0}" -f @($documentsToUpload[0].SourceObject.FullPath)
            Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($pc * 100)

<#
    These are the possibilities: from a single document perspective.
        1) This document is part of the project we are uploading.
            1a) If we are not restarting an upload (this is a new upload), then ALL this project's documents need to be uploaded -- Hence no need to check if they exist or not.
            1b) We did restart the upload, in which case, we would have re-loaded viablePathsDict and flagged all previously uploaded documents.  .SPData.Processed = $true

            Either way, if .SPData.Processed -eq $true, then we don't need to upload the document.

        2) This document is NOT part of the project we are uploading.
            To determine if I need to upload the document, I have to see if the document exists in SharePoint.


    Before I upload a file, I need to see if the current version has already been uploaded.  If it has, then I should be safe to assume all versions have been uploaded... YEAH RIGHT!!

    CORRECTION.  I only need to know if a file has already been uploaded if it is outside this project.  If I'm exporting Project X, then it's either a fresh export, or I'm restarting
    in which case, I have .SPData.Processed to know if it's already been uploaded.

    Therefore, only check for existing documents/versions for documents outside the currenting exporting project.

    Also, when I upload a document which is not part of this project, I upload ALL versions of the document.  Which is true for every document.  When a document is uploaded,
        all versions of it are uploaded -- in order of oldest file to newest.
#>

            if($documentVersionsToUpload.Length -gt 0)
            {
                <#
                    Only upload the document if it is part of this project, or if it's not a part of this project and has not already been uploaded
                    Explanation:
                        If the document is part of this project, then:
                            .SPData.Processed will determine if a document needs to be uploaded or not.
                                Infact, the line:
                                    @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseDocument]) -and (-not $_.SPData.Processed) -and (-not $_.SourceObject.IsSet) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} ).Foreach({ $documentsToUpload.Add($_) })
                                will filter out all documents which have already been uploaded.

                        If the document is NOT part of this project, then we have to go to Sharepoint to determine if the document has been uploaded or not.
                #>
                # Is this document part of this project?  If so, then upload it, if not, further work is needed.
                $uploadDocument = $documentsToUpload[0].SourceObject.FullPath -match ("^{0}" -f @($pwData.PWFolder.FullPath))

                # If this document is outside the current project, then I need check to see if it has already been uploaded and get it's version information since it MUST be a
                #   flatset reference.
                if(-not $uploadDocument)
                {
                    # Use the last document in $documentVersionsToUpload so we are looking at what should be the latest version of the document.  Remember, the list is sorted by FullPath and VersionSequence.
                    $currentVersionOfDocument = $documentVersionsToUpload[-1]


                    # If .DocVersionToLink has not been built, then build it.
                    #   The reason we need this is because I need 1) a way to determine if any of the versions need to be uploaded, and 2) it's a way
                    #   to determine if a file exists.
                    if($null -eq $currentVersionOfDocument.SPData.DocVersionToLink)
                    {
                        GetSPDocumentVersionLinks -connData $connData -currentVersionOfDocument $currentVersionOfDocument
                        if(-not $Script:HaveError)
                        {
                            # If we have no version to links, then upload the document.
                            $uploadDocument = $null -eq $currentVersionOfDocument.SPData.DocVersionLink
                        } `
                        else
                        {
                            # Nothing, either displayed an error, or no file was found.
                        }
                    } `
                    else
                    {
                        # Already have version info for this file...
                    }
                } `
                else
                {
                    # Nothing, upload the document....
                }

                # Even if we are not uploading the document, we still need to run through the following loop to remove the documents from the list of documents to upload.
                #   At this point, the only way we are NOT uploading a document is if the document is part of another project and was already uploaded.
                $b = 0
                while((-not $Script:HaveError) -and ($b -lt $documentVersionsToUpload.Length))
                {
                    $pc = [float] ($b) / [float] ($documentVersionsToUpload.Length)
                    $status = "{0,7:P2} Complete" -f @($pc)
                    $activity = "Uploading {0,2} of {1,2} versions of {2}" -f @(($b + 1), $documentVersionsToUpload.Length, $documentVersionsToUpload[$b].SourceObject.Name)
                    Write-Progress -Id 2 -Activity $activity -Status $status -PercentComplete ($pc * 100)

                    if($uploadDocument)
                    {
                        # If this is the last document in $documentVersionsToUpload, then do not use the version sequence number to determine it's location on storage.
                        ExportDocumentFromPW_UploadToSPNew -pwData $pwData -connData $connData -obj2Upload $documentVersionsToUpload[$b] -useVersion:($b -ne ($documentVersionsToUpload.Length - 1))
                    } `
                    else
                    {
                        # Nothing, don't need to upload a document that already exists.
                        LogInfo ("Skipping upload of {0}.  Already exists." -f @($documentVersionsToUpload[$b].SourceObject.FullPath))
                        $uploadSkipped++
                    }

                    if(-not $Script:HaveError)
                    {
                        $documentsUploaded++
                        if(($documentsUploaded % 10) -eq 0)
                        {
                            ExportViablePathsStructureNew -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                        } `
                        else
                        {
                            # Nothing
                        }
                        if(-not $Script:HaveError)
                        {
                            $totalSizeUploaded += $documentVersionsToUpload[$b].SourceObject.FileSize
                            $uploadedDocIdx = $documentsToUpload.IndexOf($documentVersionsToUpload[$b])
                            if($uploadedDocIdx -gt -1)
                            {
                                $documentsToUpload.RemoveAt($uploadedDocIdx)
                            } `
                            else
                            {
                                Write-Error ("Failed to remove uploaded document {0}:{1} from documents to upload in {2}." -f @($documentVersionsToUpload[$b].SourceObject.DocumentGUID, $documentVersionsToUpload[$b].SourceObject.FullPath, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }
                    # Redo the top level progress bar each time we upload a new file.
                    $pc = [float] ($totalSizeUploaded) / [float] ($totalUploadSize)
                    $status = "{0} of {1} | {2,7:P2} Complete" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc)
                    if($totalSizeUploaded -gt 0)
                    {
                        $elapsedTicks = $sw.ElapsedTicks
                        $ticksPerItem = $elapsedTicks / $totalSizeUploaded
                        $totalETATicks = $ticksPerItem * ($totalUploadSize)
                        $remainingETATicks = $totalETATicks - $elapsedTicks
                        $etaTS = [TimeSpan]::new($remainingETATicks)
                        $etaDT = [DateTime]::Now.Add($etaTS)

                        $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss"))
                    }
                    $activity = "Uploading {0}" -f @($documentsToUpload[0].SourceObject.FullPath)
                    Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($pc * 100)

                    $b++
                }
                Write-Progress -Id 2 -Completed

                if($Script.HaveError)
                {
                    LogError ("***** DELETE ALL VERSIONS OF {0}, then fix viablePathsDict export so documents get recreated on -restart *****" -f @($documentsToUpload[0].SourceObject.FullPath))
                } `
                else
                {
                    #  In a later version, I might automate this...
                }
            } `
            else
            {
                LogError ("Missing document versions to uplad for {0}:{1} in {2}." -f @($documentsToUpload[0].SourceObject.DocumentGUID, $documentsToUpload[0].SourceObject.FullPath, $me.Name))
            }
            $a++
        }
        Write-Progress -Id 1 -Completed
        LogInfo ("Documents uploaded: {0}" -f @($documentsUploaded))
        LogInfo ("Documents skipped: {0}" -f @($uploadSkipped))

        <#

            Upload ... err create document sets from $pwData.FlatSets...
                1) Create the docment set in the appropriate folder
                2) Add links to the document set for each document reference.

        #>

        # Need to look at all flatsets, not just the ones with .SPUpload.Processed -eq $false, since we also need to see if all the flatset reference have been uploaded.
        $fsToProcess =  @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseDocument]) -and ($_.SourceObject.IsSet) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} )
        LogInfo ("Processing {0} Flatsets" -f @($fsToProcess.Length))
        # Just some admin stuff...
        $totalProcesses = 0
        $fsToProcess.Foreach({
            $totalProcesses++       # Create the document set.
            $fs = $_
            $pwFS = $pwData.FlatSets | Where-Object { $_.TreeDocument.DocumentGUID -eq $fs.SourceObject.DocumentGUID }
            if($null -ne $pwFS)
            {
                $pwFS.References.Foreach({ $totalProcesses++ })    # Create a document link for each referenced document.
            } `
            else
            {
                LogError ("Missing PW FlatSet object for {0}:{1} at {2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsName, $fsFolder, $me.Name))
            }
        })
        $processesCompleted = 0
        LogInfo ("`tReferenced documents: {0}" -f @(($totalProcesses - $fsToProcess.Length)))
        if(-not $Script:HaveError)
        {
            # Reset some admin stuff..
            $sw.Restart()

            # Next need to create all the document sets and add the document links.
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $fsToProcess.Length))
            {
                # This will not fail, we checked above when we were calculating how many processes are required.
                $pwFS = $pwData.FlatSets | Where-Object { $_.TreeDocument.DocumentGUID -eq $fsToProcess[$a].SourceObject.DocumentGUID }

                $pc = [float] $processesCompleted / [float] $totalProcesses
                Write-Progress -Id 1 -Activity ("Processing FlatSet {0} of {1}" -f @(($a + 1), $fsToProcess.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                if($viablePathsDict.ContainsKey($fsToProcess[$a].SourceObject.DocumentGUID))
                {
                    $vp = $viablePathsDict[$fsToProcess[$a].SourceObject.DocumentGUID]

                    if($connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($vp.Paths[0]))
                    {
                        $library = $connData.ConnectionInformation.SharePointDocumentLibraries[$vp.Paths[0]]

                        $docLibURL = GetLibraryURL -connData $connData -name $vp.Paths[0]
                        if(-not [String]::IsNullOrEmpty($docLibURL))
                        {
                            # The folder where the document set will live
                            $fsFolder = "{0}/{1}" -f @($docLibURL, (($vp.Paths[1..($vp.Paths.Length - 2)]) -join "/"))

                            # [-1] is the last item in the array...
                            $fsName = $vp.Paths[-1]

                            # If we don't think we've processed this document set, then proceed like we need to create it.
                            $createDocumentSet = -not $vp.SPData.Processed
                            if(-not $vp.SPData.Processed)
                            {
                                $createDocumentSet = $true

                                try
                                {
                                    $existingDS = Get-PnPListItem -List $library -FolderServerRelativeUrl $fsFolder -IncludeContentType -ErrorAction Stop | Where-Object { $_.ContentType.Name -eq "Document Set" }
                                    if($null -ne $existingDS)
                                    {
                                        $createDocumentSet = $false    # No need to create what already exists.
                                        $ds = $existingDS.FieldValues["FileRef"]
                                        $vp.SPData.Processed = $true
                                        [DateTime] $dt = [DateTime]::Now    # Just use the current date and time unless we get a value for when it was created.
                                        if(-not [String]::IsNullOrEmpty($existingDS.FieldValues["Created_x0020_Date"]))
                                        {
                                            # Capture the return value... it really doesn't matter, either way we'll have a useable value in $dt.
                                            $null = [DateTime]::TryParse($existingDS.FieldValues["Created_x0020_Date"], [ref] $dt)
                                        } `
                                        else
                                        {
                                            # Nothing, just the default...
                                        }
                                        $vp.SPData.WhenUploaded = $dt.ToString()
                                    } `
                                    else
                                    {
                                        # Nothing, there is no document set...
                                    }
                                }
                                catch
                                {
                                    # No big deal, the docment set does not exist.
                                    $Error.Clear()
                                }

                                if($createDocumentSet)
                                {
                                    try
                                    {
                                        $ds = Add-PnPDocumentSet -List $library -ContentType "Document Set" -Name $fsName -Folder $fsFolder -ErrorAction Stop
                                        if(-not [String]::IsNullOrEmpty($ds))
                                        {
                                            $vp.SPData.SPFile.ServerRelativeURL = $ds
                                            $vp.SPData.Processed = $true    # We created the document set.
                                            $vp.SPData.WhenUploaded = [DateTime]::Now.ToString()
                                        } `
                                        else
                                        {
                                            LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0}:{1}/{2} in {3}." -f @($flatsetTreeDocuments[$a].DocumentGUID, $fsFolder, $fsName, $me.Name))
                                        }
                                    }
                                    catch
                                    {
                                        LogError ("Failed to add document set: {0}:{1} at {2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsName, $fsFolder, $me.Name))
                                    }
                                } `
                                else
                                {
                                    # Nothing, document set already exists.
                                }
                            } `
                            else
                            {
                                # Need to populate variable for below that didn't get populated since we didn't create a new document set...
                                $ds = $vp.SPData.SPFile.ServerRelativeURL
                            }

                            if(-not $Script:HaveError)
                            {
                                if(-not [String]::IsNullOrEmpty($ds))
                                {
                                    # Now, create all the document links in the document set.

                                    $b = 0
                                    while((-not $Script:HaveError) -and ($b -lt $pwFS.References.Length))
                                    {
                                        $pc = [float] $b / [float] $pwFS.References.Length
                                        Write-Progress -Id 2 -Activity ("Adding links to document set {0} of {1}" -f @(($b + 1), $pwFS.References.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                                        if($viablePathsDict.ContainsKey($pwFS.References[$b].DocumentGUID))
                                        {
                                            $vp2 = $viablePathsDict[$pwFS.References[$b].DocumentGUID]

                                            # Have we already created a link for this flatset??    SORRY, only 1 link per flatset....
                                            if(-not $vp2.SPData.DocSetLinksCreated.Contains($pwFS.References[$b].DocumentGUID))
                                            {
                                                # Need to determine if the referenced document points to the current version of a file, or not.

                                                # Get all the versions of the referenced document.  Sorted by FullPath and VersionSequence so the current version is the last.
                                                $documentVersions = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseDocument]) -and ($_.SourceObject.FullPath -eq $pwFS.References[$b].FullPath) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }})

                                                if($documentVersions.Length -gt 0)
                                                {
                                                    # The last document in the array is always the current document since it's sorted by .FullPath and .VersionSequence.
                                                    #  This is used to place .VersionProperties and .VersionLinks on it... always check the current version for this info.
                                                    $currentDocument = $documentVersions[-1]

                                                    # The current version will be the last file in the sorted array (by fullpath and versionsequence)...So here, we need to get the index
                                                    #    of the version we are needing to check.
                                                    # NOTE: We are not looking for the index of the current document, that is index -1, we are looking for the index of the version of the
                                                    #    document referenced by the flatset.
                                                    $versionIdx = $documentVersions.IndexOf( ($documentVersions | Where-Object {$_.SourceObject.DocumentGUID -eq $pwFS.References[$b].DocumentGUID}))

                                                    if($versionIdx -gt -1)
                                                    {
                                                        # From here, the point is to end up with a viable value for $docLink....
                                                        $docLink = [String]::Empty

                                                        # If the version index is the last item in the array, then we are safe to use the current file URL...
                                                        $isCurrentVersion = ($versionIdx -eq ($documentVersions.Length - 1))
                                                        if($isCurrentVersion)
                                                        {
                                                            if(-not [String]::IsNullOrEmpty($vp2.SPData.SPFile.ServerRelativeURL))
                                                            {
                                                                $docLink = $vp2.SPData.SPFile.ServerRelativeURL
                                                            } `
                                                            else
                                                            {
                                                                LogError ("No SharePoint document relative URL for {0} in {1}." -f @($vp.SourceObject.FullPath, $me.Name))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Not the current file, so we have to get a link to a previous version of the file...

                                                            # If .DocVersionToLink has not been built, then build it.
                                                            if($null -eq $currentDocument.SPData.DocVersionToLink)
                                                            {
                                                                GetSPDocumentVersionLinks -connData $connData -currentVersionOfDocument $currentDocument
                                                            } `
                                                            else
                                                            {
                                                                # Already have version info for this file...
                                                            }

                                                            $versionToFind = $vp2.SourceObject.Version
                                                            if([String]::IsNullOrEmpty($versionToFind))
                                                            {
                                                                $versionToFind = "NoVersion"
                                                            } `
                                                            else
                                                            {
                                                                # Nothing.
                                                            }

                                                            if(-not $Script:HaveError)
                                                            {
                                                                if($null -ne $currentDocument.SPData.DocVersionToLink)
                                                                {
                                                                    if($currentDocument.SPData.DocVersionToLink.ContainsKey($versionToFind))
                                                                    {
                                                                        $docLink = $currentDocument.SPData.DocVersionToLink[$versionToFind]
                                                                    } `
                                                                    else
                                                                    {
                                                                        LogError ("Missing document link for {0} Version {1} in {2}." -f @($vp2.SourceObject.FullPath, $versionToFind, $me.Name))
                                                                    }
                                                                } `
                                                                else
                                                                {
                                                                    LogError ("Missing document link for {0} Version {1} in {2}.  No document version links." -f @($vp2.SourceObject.FullPath, $versionToFind, $me.Name))
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                # Already have version info for this file...
                                                            }
                                                        }

                                                        if(-not $Script:HaveError)
                                                        {
                                                            if(-not [String]::IsNullOrEmpty($docLink))
                                                            {
                                                                if($isCurrentVersion)
                                                                {
                                                                    $docLink = "{0}{1}" -f @($connData.ConnectionInformation.SharePointRootURL, $docLink)
                                                                } `
                                                                else
                                                                {
                                                                    $docLink = "{0}/sites/{1}/{2}" -f @($connData.ConnectionInformation.SharePointRootURL, $connData.ConnectionInformation.SharePointSiteName, $docLink)
                                                                }

                                                                # Create an internet shortcut to the proper document version and add it to the document set.
                                                                $linkContent = "[InternetShortcut]`nURL={0}" -f @($docLink)
                                                                $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))
                                                                $targetFolder = "{0}/{1}" -f @($fsFolder, $fsName)
                                                                $linkName = "{0}.url" -f @($pwFS.References[$b].Name)
                                                                $spDocFields = BuildDocumentProperties -connData $connData -obj2Upload $vp2
                                                                if($null -ne $spDocFields)
                                                                {
                                                                    $spDocFields.Add("_ShortcutUrl", $docLink)
                                                                } `
                                                                else
                                                                {
                                                                    $spDocFields = @{ "_ShortcutUrl" = $docLink }
                                                                }

                                                                try
                                                                {
                                                                    $fsDocLink = Add-PnPFile -FileName $linkName -Folder $targetFolder -Stream $stream -Values $spDocFields -ErrorAction Stop
                                                                }
                                                                catch
                                                                {
                                                                    LogError ("Failed to create document link {0} for document set {1} in {2}." -f @($docLink, $fsName, $me.Name))
                                                                }

                                                                if(-not $Script:HaveError)
                                                                {
                                                                    # $vp2 refers to the referenced document, so all we need to do here is flag that we've created the link for it
                                                                    #   Add the flatset's document GUID to the list to signal we created it.
                                                                    $vp2.SPData.DocSetLinksCreated.Add($pwFS.References[$b].DocumentGUID)
                                                                } `
                                                                else
                                                                {
                                                                    # Nothing, already displayed an error.
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                LogError ("No document link available for {0} Version {1} in {2}.  docLink is empty." -f @($vp2.SourceObject.FullPath, $versionToFind, $me.Name))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, already logged an error
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogError ("Unable to document index of {0}:{1} in {2}" -f @($pwFS.References[$b].DocumentGUID, $pwFS.References[$b].FullPath, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    LogError ("Unable to locate any versions of {0} in viable paths dictionary {1}." -f @($pwFS.References[$b].FullPath, $me.Name))
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, no need to create a duplicate link.
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Missing flat set reference viable path for {0}:{1} in {2}." -f @($pwData.FlatSets[$a].References[$b].DocumentGUID, $pwData.FlatSets[$a].References[$b].FullPath, $me.Name))
                                        }

                                        $processesCompleted++
                                        if(($processesCompleted % 10) -eq 0)
                                        {
                                            ExportViablePathsStructureNew -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                                        } `
                                        else
                                        {
                                            # Nothing
                                        }
                                        $b++
                                    }
                                    Write-Progress -Id 2 -Completed
                                } `
                                else
                                {
                                    LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0}:{1}/{2} in {3}." -f @($flatsetTreeDocuments[$a].DocumentGUID, $fsFolder, $fsName, $me.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        } `
                        else
                        {
                            LogError ("Missing document library URL for {0} in {1}." -f @($vp.Paths[0], $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Missing document library {0} in {1}." -f @($vp.Paths[0], $me.Name))
                    }
                } `
                else
                {
                    LogError ("Missing flat set viable path for {0}:{1} in {2}." -f @($pwData.FlatSets[$a].TreeDocument.DocumentGUID, $pwData.FlatSets[$a].TreeDocument.FullPath, $me.Name))
                }

                $processesCompleted++
                if(($processesCompleted % 10) -eq 0)
                {
                    ExportViablePathsStructureNew -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                } `
                else
                {
                    # Nothing
                }
                $a++
            }
            Write-Progress -Id 1 -Completed
            $sw.Stop()
        } `
        else
        {
            # Nothing, already displayed an error.
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    # Save viablePathsDict one last time.
    ExportViablePathsStructureNew -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
}

function CreateSharePointProjectSubFoldersNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    # Get all the folder objects from viablePathsDict that have not been created and are either for another project, or are more than 2 levels deep.  The first 2 levels are the "Active Projects" | "Inactive Projects" and the project folder
    #    The project folder is created separately so it's properties can be set.
    #    $folderObjectsToCreate = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseFolder]) -and (-not $_.SPData.Processed) } | Sort-Object @{E={ ($_.Paths -join "/") }})

    $folderObjects = @(@($viablePathsDict.Values) | Where-Object { ((($_.Paths.Length -eq 2) -and (($_.Paths[0..1] -join "/") -ne $pwData.PWFolder.FullPath.Replace("\","/"))) -or ($_.Paths.Length -gt 2)) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseFolder]) } | Sort-Object @{E={ ($_.Paths -join "/") }})
    LogInfo ("{0} Folder objects" -f @($folderObjects.Length))
    $folderObjectsToCreate = @($folderObjects | Where-Object { (-not $_.SPData.Processed) })
    LogInfo ("{0} Folders to create" -f @($folderObjectsToCreate.Length))

    $a = 0

    while((-not $Script:HaveError) -and ($a -lt $folderObjectsToCreate.Length))
    {
        $fo = $folderObjectsToCreate[$a]

        if($fo.Paths.Length -eq 2)
        {
            # This is a project folder for another project.
            try
            {
                $projectFolder = Get-PWFolders -FolderPath $fo.SourceObject.FullPath -JustOne -Slow -ErrorAction Stop 3> $null

                if($null -ne $projectFolder)
                {
                    $pFolder = CreateSharePointProjectFolder -connData $connData -pwFolder $projectFolder -viablePathsDict $viablePathsDict
                } `
                else
                {
                    LogError ("Failed to retrieve project folder {0} from ProjectWise in {1}.  Null value returned." -f @($fo.FullPath, $me.Name))
                }

                if(-not $Script::HaveError)
                {
                    if($null -ne $pFolder)
                    {
                        $fo.SPData.SPFile.ServerRelativeURL = $pFolder.ServerRelativeURL
                        $fo.SPData.Processed = $true
                        $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
                    } `
                    else
                    {
                        LogWarning ("Missing SharePoint folder object for project folder {0} in {1}." -f @($projectFolder.FullPath, $me.Name))
                    }
                } `
                else
                {
                    # Nothing, already logged an error
                }
            }
            catch
            {
                LogError ("Failed to retrieve folder {0} from ProjectWise in {1}." -f @($fo.FullPath, $me.Name))
            }
        } `
        else
        {
            # Not a project folder...
            $folderPieces = [System.Collections.Generic.List[String]]::new()
            $v = 0
            while($v -lt $fo.Paths.Length)
            {
                if($v -eq 0)
                {
                    $folderPieces.Add((TranslateToDocLibName -name $fo.Paths[$v]))
                } `
                else
                {
                    $folderPieces.Add($fo.Paths[$v])
                }
                $v++
            }

            $spDocLibName = $folderPieces[0]
            if(-not $connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocLibName))
            {
                # Need to create the document library...
                CreateNewDocumentLibrary -connData $connData -spDocLibName $spDocLibName
            } `
            else
            {
                # When I know, I'll fix this.
            }

            if(-not $Script:HaveError)
            {
                if($connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocLibName))
                {
                    $folderPieces.RemoveAt(0)
                    $library = $connData.ConnectionInformation.SharePointDocumentLibraries[$spDocLibName]
                    $parentFolder = GetLibraryURL -connData $connData -name $spDocLibName
                    if(-not [String]::IsNullOrEmpty($parentFolder))
                    {
                        $parentFolder = "{0}/{1}" -f @($parentFolder, ($folderPieces[0..($folderPieces.Count - 2)] -join "/"))

                        $folderName = $folderPieces[-1]
                        $description = [String]::Empty
                        if((-not [String]::IsNullOrEmpty($fo.SourceObject.Description)) -and ($fo.SourceObject.Description -ne $fo.SourceObject.Name))
                        {
                            $description = $fo.SourceObject.Description
                        } `
                        else
                        {
                            # Don't use a dumb description
                        }

                        $pc = [float] $a / [float] $folderObjectsToCreate.Length
                        Write-Progress -Id 1 -Activity ("Creating SharePoint folder {0} : {1} of {2}" -f @($folderPieces[-1], ($a + 1), $folderObjectsToCreate.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                        $spFolder = AddSharePointFolder -parentFolder $parentFolder -newFolderName $folderName -description $description -originalName $fo.Paths[-1]

                        if(-not $Script:HaveError)
                        {
                            if($null -ne $spFolder)
                            {
                                $fo.SPData.SPFile.ServerRelativeURL = $spFolder.ServerRelativeURL
                                $fo.SPData.Processed = $true
                                $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
                            } `
                            else
                            {
                                LogWarning ("Missing Sharepoint folder object for {0}/{1} in {2}." -f @($parentFolder, $folderName, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        LogError ("Missing document library URL for {0} in {1}." -f @($spDocLibName, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Missing document library {0} in {1}." -f @($spDocLibName, $me.Name))
                }
            } `
            else
            {
                # Nothing, already logged an error
            }
        }
        $a++
    }
    Write-Progress -Id 1 -Completed
}

function CreateSharePointProjectFolder_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwFolder,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $me = $MyInvocation.MyCommand

    $projectPieces = @($pwFolder.FullPath -split "\\")
    if($projectPieces.Length -ge 2)
    {
        $projectPieces[0] = TranslateToDocLibName -name $projectPieces[0]

        $spDocLibName = $projectPieces[0]
        if(-not $connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocLibName))
        {
            # Need to create the document library...
            CreateNewDocumentLibrary -connData $connData -spDocLibName $spDocLibName
        } `
        else
        {
            # When I know, I'll fix this.
        }

        if(-not $Script:HaveError)
        {
            if($connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocLibName))
            {
                $library = $connData.ConnectionInformation.SharePointDocumentLibraries[$spDocLibName]
                $projectName = $projectPieces[1]

                # Add the project folder to the sharepoint document library.
                # OLD: $parentFolderURL = "{0}/{1}" -f @($connData.ConnectionInformation.DocumentLibraryName, $spDocLibName)
                $parentFolderURL = GetLibraryURL -connData $connData -name $spDocLibName
                if(-not [String]::IsNullOrEmpty($parentFolderURL))
                {
                    $folderURL = "{0}/{1}" -f @($parentFolderURL, $projectName)
                    $pFolder = $null
                    $folderListItem = $null
                    try
                    {
                        # See if the folder already exists...
                        $pFolder = Get-PnPFolder -Url $folderURL -Includes ListItemAllFields -ErrorAction Stop
                    }
                    catch
                    {
                        # No big deal, the folder doesn't exist...
                        $Error.Clear()
                    }

                    # If the folder exists, then get it's properties...
                    if($null -ne $pFolder)
                    {
                        try
                        {
                            $folderListItem = Get-PnPListItem -List $library -Id $pFolder.ListItemAllFields.Id

                            if($null -ne $folderListItem)
                            {
                                if($null -ne $folderListItem.FieldValues)
                                {
                                    # Nothing, all good.
                                } `
                                else
                                {
                                    LogError ("Unable to retrieve folder list item for {0} in {1}.  Null value returned" -f @($folderURL, $me.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Unable to retrieve folder list item for {0} in {1}.  Null value returned" -f @($folderURL, $me.Name))
                            }
                        }
                        catch
                        {
                            LogError ("Unable to retrieve folder list item for {0} in {1}." -f @($folderURL, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, can't get properties for a non-existent folder.
                    }

                    if(-not $Script:HaveError)
                    {
                        # If there isn't a pre-existing folder, then try to create it.
                        if($null -eq $pFolder)
                        {
                            try
                            {
                                LogInfo ("Creating project folder: {0}" -f @($projectName))
                                # Create the new top level project folder
                                $pFolder = Add-PnpFolder -Folder $parentFolderURL -Name $projectName -ErrorAction Stop

                                # Reset $pFolder to null so we reget it below.
                                $pFolder = $null
                            }
                            catch
                            {
                                LogError ("Failed to create new Sharepoint Online project folder: {0} in {1}." -f @($folderURL, $me.Name))

                            }
                        } `
                        else
                        {
                            # No need to create a new folder when it already exists.
                        }

                        # Set/Update the properties on the folder.
                        if(-not $Script:HaveError)
                        {
                            # Create a hashtable with all the project properties from ProjectWise
                            $projectParams = @{  }

                            $a = 0
                            $projectPropKeys = @($pwFolder.ProjectProperties.Keys)
                            while((-not $Script:HaveError) -and ($a -lt $projectPropKeys.Length))
                            {
                                if(-not [String]::IsNullOrEmpty($pwFolder.ProjectProperties[$projectPropKeys[$a]]))
                                {
                                    if($connData.documentFields.ContainsKey($projectPropKeys[$a]))
                                    {
                                        $spDocField = $connData.documentFields[$projectPropKeys[$a]]
                                    } `
                                    else
                                    {
                                        $spDocField = $null
                                    }

                                    <#
                                        If...
                                            There was no existing folder  OR
                                            There was a folder and either
                                                there is no existing value for this property  OR
                                                the existing value of the property is different
                                        Then proceed to set the property value if we aren't ignoring it.
                                    #>
                                    if(($null -eq $folderListItem) -or (($null -ne $folderListItem) -and ((-not $folderListItem.FieldValues.ContainsKey($projectPropKeys[$a])) -or ($folderListItem.FieldValues.ContainsKey($projectPropKeys[$a])) -and ($folderListItem.FieldValues[$projectPropKeys[$a]] -ne $pwFolder.ProjectProperties[$projectPropKeys[$a]]))))
                                    {
                                        if(($null -eq $spDocField) -or (($null -ne $spDocField) -and (-not $spDocField.Ignore)))
                                        {
                                            $fld = TestForSPDocumentLibraryField -connData $connData -libraryName $library.Title -fieldName $projectPropKeys[$a]

                                            if(-not $Script:HaveError)
                                            {
                                                if(($null -ne $fld) -and (-not $fld.Ignore))
                                                {
                                                    $projectParams.Add($fld.InternalName, $pwFolder.ProjectProperties[$projectPropKeys[$a]])
                                                } `
                                                else
                                                {
                                                    # Nothing, ignore the property
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, already displayed an error.
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, not a field we care about...
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, can't check the pre-existing value when it doesn't exist.
                                    }
                                }
                                $a++
                            }

                            if(-not $Script:HaveError)
                            {
                                # Did we set any folder properties?
                                if($projectParams.Count -gt 0)
                                {
                                    # Yes...

                                    # Then we need to set the property values on the folder...

                                    # Was there a pre-existing folder?
                                    if($null -eq $pFolder)
                                    {
                                        # No, need to get the folder...
                                        try
                                        {
                                            # Now get the new folder with its fields
                                            $pFolder = Get-PnPFolder -Url $folderURL -Includes ListItemAllFields -ErrorAction Stop
                                        }
                                        catch
                                        {
                                            LogError ("Failed to retrieve newly created project folder: {0} in {1}." -f @($folderRelativeURL, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Yes... then use it to set the properties...
                                    }

                                    if($null -ne $pFolder)
                                    {
                                        $fileListItem = $null
                                        try
                                        {
                                            $fileListItem = Set-PnpListItem -List $library -Identity $pFolder.ListItemAllFields.Id -Values $projectParams -ErrorAction Stop
                                        }
                                        catch
                                        {
                                            LogError ("Failed to set document properties on project folder {0} in {1}." -f @($folderURL, $me.Name))
                                        }

                                        if($null -ne $fileListItem)
                                        {
                                            $projectPropKeys = @($projectParams.Keys)
                                            $a = 0
                                            while($a -lt $projectPropKeys.Length)
                                            {
                                                if($fileListItem.FieldValues.ContainsKey($projectPropKeys[$a]))
                                                {
                                                    if($fileListItem.FieldValues[$projectPropKeys[$a]] -ne $projectParams[$projectPropKeys[$a]])
                                                    {
                                                        LogError ("Project property value mismatch for {0}:{1}:{2}.  Should be: {3}, returned {4} in {5}." -f @($library.Title, $projectName, $projectPropKeys[$a], $projectParams[$projectPropKeys[$a]], $fileListItem.FieldValues[$projectPropKeys[$a]], $me.Name))
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, all is well.
                                                    }
                                                } `
                                                else
                                                {
                                                    LogError ("Failed to verify project property: {0} in {1}." -f @($projectPropKeys[$a], $me.Name))
                                                }
                                                $a++
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Failed to set document properties on project folder {0} in {1}.  NUll object returned." -f @($folderURL, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("Failed to retrieve newly created project folder: {0} in {1}.  Null folder returned." -f @($folderRelativeURL, $me.Name))
                                    }
                                } `
                                else
                                {
                                    # Nothing, no project properties to set...
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }
                } `
                else
                {
                    LogError ("Missing document library URL for {0} in {1}." -f @($pwFolder.FullPath, $me.Name))
                }
            } `
            else
            {
                LogError ("Missing document library {0} in {1}." -f @($spDocLibName, $me.Name))
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }

        if(-not $Script:HaveError)
        {
            # Mark the project folder's viable path node as processed.
            $projectFolderPath = $projectPieces[0..1] -join "\"
            @($viablePathsDict.Values).Where({ $_.SourceObject.FullPath -eq $projectFolderPath }).ForEach({ $_.SPData.Processed = $true })
        } `
        else
        {
            # Nothing, already logged an error.
        }
    } `
    else
    {
        LogError ("Unable to determine SharePoint Project Folder from {0} in {1}." -f @($pwFolder.FullPath, $me.Name))
    }

    return @(, $pFolder)
}

function GetSPDocumentVersionLinks_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyCollection()]
        [Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $currentVersionOfDocument
    )

    $me = $MyInvocation.MyCommand

    if($Script:DoDebugging)
    {
        LogInfo ("Getting version data for {0}" -f @(($currentVersionOfDocument.Paths -join "/")))
    }

    if($connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($currentVersionOfDocument.Paths[0]))
    {
        $docLibURL = GetLibraryURL -connData $connData -name $currentVersionOfDocument.Paths[0]
        if(-not [String]::IsNullOrEmpty($docLibURL))
        {
            $spFileURL = "{0}/{1}" -f @($docLibURL, ($currentVersionOfDocument.Paths[1..($currentVersionOfDocument.Paths.Length - 1)] -join "/"))
            try
            {
                # This only works for the current version of the file....
                $spFile = Get-PnPFile -URL $spFileURL -AsListItem -ErrorAction Stop

                # Leave $uploadDocument set to false so we don't upload it again.
            }
            catch
            {
                if($Error[0].Exception.Message -match "The object does not belong to a list.")
                {
                    # File doesn't exist...
                    $Error.Clear()
                    $spFile = $null
                } `
                else
                {
                    LogError ("Failed to retrieve file [{0}] from SharePoint in {1}." -f @($spFileURL, $me.Name))
                }
            }

            if(-not $Script:HaveError)
            {
                if($null -ne $spFile)
                {
                    # Now, get all the versions of the file from SharePoint.
                    try
                    {
                        # This verison data contains the FieldValues I need to determine which version has the right "DocumentVersion", but does not
                        #    include the document URL I need.  It does have .VersionLabel which I'll use to link to $referenceSPDocVersions below.
                        # This works for a file with only 1 version.
                        $versions = Get-PnPProperty -ClientObject $spFile -Property Versions -ErrorAction Stop
                    }
                    catch
                    {
                        LogError ("Failed to get field value versions for {0} in {1}." -f @($spFileURL, $me.Name))
                    }

                    if(-Not $Script:HaveError)
                    {
                        if($null -ne $versions)
                        {
                            # Always attach the verion information to the current version of the document, it's where it comes from after all.

                            # Now, get all the version references of the file from SharePoint.
                            try
                            {
                                # This 'version' data contains the URL and VersionLabel
                                $referenceSPDocVersions = Get-PnpFileVersion -URL $spFileURL -ErrorAction Stop
                            }
                            catch
                            {
                                LogError ("Failed to get reference versions for {0} in {1}." -f @($spFileURL, $me.Name))
                            }

                            if(-not $Script:HaveError)
                            {
                                $docVerToLink = [System.Collections.Generic.SortedDictionary[String, String]]::new()

                                # Add the current document's version and link to the dictionary.
                                $docVerToLink.Add($currentVersionOfDocument.SourceObject.Version, $spFileURL)

                                if($Script:DoDebugging)
                                {
                                    LogInfo ("`tadded: {0}, {1}" -f @($currentVersionOfDocument.SourceObject.Version, $spFileURL))
                                }

                                if($null -ne $referenceSPDocVersions)
                                {
                                    $f = 0
                                    while($f -lt $versions.Count)
                                    {
                                        $refSPDocVer = $referenceSPDocVersions.Where({ $_.VersionLabel -eq $versions[$f].VersionLabel })
                                        if($null -ne $refSPDocVer)
                                        {
                                            if($versions[$f].FieldValues.ContainsKey("DocumentVersion"))
                                            {
                                                if(-not $docVerToLink.ContainsKey($versions[$f].FieldValues["DocumentVersion"]))
                                                {
                                                    $docVerToLink.Add($versions[$f].FieldValues["DocumentVersion"], $refSPDocVer.Url)
                                                    if($Script:DoDebugging)
                                                    {
                                                        LogInfo ("`tadded: {0}, {1}" -f @($versions[$f].FieldValues["DocumentVersion"], $refSPDocVer.Url))
                                                    }
                                                } `
                                                else
                                                {
                                                    if($versions[$f].FieldValues["DocumentVersion"] -ne $currentVersionOfDocument.SourceObject.Version)
                                                    {
                                                        LogError ("Duplicate document version {0} for {1} in {2}." -f @($versions[$f].FieldValues["DocumentVersion"], $spFileURL, $me.Name))
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, since I added the original version above, ignore it here...
                                                    }
                                                }
                                            } `
                                            else
                                            {
                                                LogError ("Document {0} missing DocumentVersion field in {1}." -f @($spFileURL, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            # This is the current version and there is no "version history" for it...
                                        }
                                        $f++
                                    }
                                } `
                                else
                                {
                                    # LogError ("Failed to get field reference versions for {0} in {1}.  Null value returned" -f @($spFileURL, $me.Name))
                                    # Nothing, no old versions of the file...
                                }

                                if(-not $Script:HaveError)
                                {
                                    $currentVersionOfDocument.SPData.DocVersionToLink = $docVerToLink
                                } `
                                else
                                {
                                    # Nothing, already logged an error.
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        } `
                        else
                        {
                            LogError ("Failed to get field value versions for {0} in {1}.  Null value returned" -f @($spFileURL, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }
                } `
                else
                {
                    # Nothing, file not found...
                }
            } `
            else
            {
                # Nothing, either displayed an error, or no file was found.
            }
        } `
        else
        {
            LogError ("Missing document library URL for {0} in {1}." -f @($currentVersionOfDocument.Paths[0], $me.Name))
        }
    } `
    else
    {
        LogError ("Missing document library {0} in {1}." -f @($currentVersionOfDocument.Paths[0], $me.Name))
    }
}

function ExportDocumentFromPW_UploadToSPNew_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $useVersion
    )

    $me = $MyInvocation.MyCommand

    $td = $obj2Upload.SourceObject

    if(-not $td.IsSet)
    {
        if(-not $obj2Upload.SPData.Processed)
        {
            $srcPath = GetPWDocumentStorageLocation -pwData $pwData -td $td -useVersion:$useVersion
            if(-not [String]::IsNullOrEmpty($srcPath))
            {
                $spDocValues = BuildDocumentProperties -connData $connData -obj2Upload $obj2Upload
                if($null -ne $spDocValues)
                {
                    $successful = $false
                    $retries = 0
                    $docLibURL = GetLibraryURL -connData $connData -name $obj2Upload.Paths[0]
                    if(-not [String]::IsNullOrEmpty($docLibURL))
                    {
                        $folderPath = "{0}/{1}" -f @($docLibURL, ($obj2Upload.Paths[1..($obj2Upload.Paths.Length - 2)] -join "/"))
                        do {
                            if($td.FileSize -eq 0)
                            {
                                $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes("No Contents"))
                                try
                                {
                                    $spFile = Add-PnPFile -FileName $obj2Upload.Paths[-1] -Folder $folderPath -Stream $stream -Values $spdocValues -ErrorAction Stop
                                    $successful = $true
                                }
                                catch
                                {
                                    LogError ("Failed to create no content file {0} in folder {1} in {2}." -f @($td.Name, $folderPath, $me.Name))
                                }
                            } `
                            else
                            {
                                try
                                {
                                    # I can't just assume I can upload a file ... if I do, what will happen if I'm uploading a file which doesn't belong to this project?
                                    #    Initially, nothing, but what about later when I export the actual project?
                                    #    If I just upload all the documents and versions, I will be doubling the version history.

                                    $spFile = Add-PnPFile -Path $srcPath -Folder $folderPath -Values $spdocValues -NewFileName $obj2Upload.Paths[-1] -ErrorAction Stop
                                    $successful = $true
                                }
                                catch
                                {
                                    if($Error[0].Exception.Message -match "Save Conflict")
                                    {
                                        $retries++
                                        if($retries -lt $maxRetries)
                                        {
                                            $Error.Clear()
                                            Start-Sleep -Milliseconds 250
                                        } `
                                        else
                                        {
                                            LogError ("Failed to upload {0}:{1} to {2} after {3} retries in {4}." -f @($td.DocumentGUID, $viablePathsDict[$td.DocumentGUID].CopyOutPath, $spFolder, $retries, $me.Name))
                                            @($spdocValues.Keys).ForEach({
                                                LogInfo ("`t{0} = {1}" -f @($_, $spdocValues[$_]))
                                            })
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("Failed to upload {0}:{1} to {2} in {3}." -f @($td.DocumentGUID, $viablePathsDict[$td.DocumentGUID].CopyOutPath, $spFolder, $me.Name))

                                    }
                                }
                            }
                        } while((-not $Script:HaveError) -and (-not $successful) -and ($retries -lt $maxRetries))

                        if(-not $Script:HaveError)
                        {
                            if($successful)
                            {
                                if($null -ne $spFile)
                                {
                                    $obj2Upload.SPData.Processed = $true
                                    $obj2Upload.SPData.WhenUploaded = [DateTime]::Now.ToString()
                                    $obj2Upload.SPData.SPFile.ServerRelativeURL = $spFile.ServerRelativeURL
                                    $obj2Upload.SPData.SPFile.VersionLabel = $spFile.UIVersionLabel
                                } `
                                else
                                {
                                    LogWarning ("Missing spFile for {0}/{1} in {2}." -f @($folderName, $td.Name, $me.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        LogError ("Missing document library URL for {0} in {1}." -f @($obj2Upload.Paths[0], $me.Name))
                    }
                } `
                else
                {
                    # Nothing, already logged an error
                }
            } `
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            # Nothing, skip this file, already uploaded it.
        }
    } `
    else
    {
        # Sets are handled differently.
    }
}

function GetPWDocumentStorageLocation_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $td,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $useVersion
    )

    $me = $MyInvocation.MyCommand
    $srcPath = [String]::Empty

    if($pwData.StorageAreas.ContainsKey($td.StorageName))
    {
        if($td.ProjectID -le 99999)
        {
            $srcFolder = "{0}\dms{1:D5}" -f @($pwData.StorageAreas[$td.StorageName], $td.ProjectID)
        } `
        else
        {
            $srcFolder = "{0}\d{1:D7}" -f @($pwData.StorageAreas[$td.StorageName], $td.ProjectID)
        }
        if([System.IO.Directory]::Exists($srcFolder))
        {
            if(-not $useVersion.IsPresent)
            {
                $srcPath = "{0}\{1}" -f @($srcFolder, $td.Name)
            } `
            else
            {
                $srcPath = "{0}\ver{1:D5}\{2}" -f @($srcFolder, $td.VersionSequence, $td.Name)
            }

            if([System.IO.File]::Exists($srcPath))
            {
                $fi = [System.IO.FileInfo]::new($srcPath)
                if($fi.Length -ne $td.FileSize)
                {
                    LogError ("{0} file size mismatch in {3}.  TD.FileSize: {1}, FI.Length: {2}" -f @($srcPath, $td.FileSize, $fi.Length, $me.Name))
                } `
                else
                {
                    # Nothing, all is well.
                }
            } `
            else
            {
                LogError ("Source file {0} not found for {1}:{2} in {3}." -f @($srcPath, $td.DocumentGUID, $td.FullPath, $me.Name))
            }
        } `
        else
        {
            LogError ("Source folder {0} not found for {1}:{2} in {3}." -f @($srcFolder, $td.DocumentGUID, $td.FullPath, $me.Name))
        }
    } `
    else
    {
        LogError ("Missing storage area {0} for {1} in {2}." -f @($td.StorageName, $td.FullPath, $me.Name))
    }

    return $srcPath
}

function BuildDocumentProperties_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $connData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $obj2Upload
    )

    $me = $MyInvocation.MyCommand

    $td = $obj2Upload.SourceObject
    $libraryName = $obj2Upload.Paths[0]

    if($null -ne $td)
    {
        # Build the document properties...
        $spdocValues = @{
            Created = $td.CreateDate
            Modified = $td.FileUpdateDate
        }

        if($obj2Upload.Paths[-1] -ne $td.Name)
        {
            $spDocValues.Add("OriginalName", $td.Name)
        } `
        else
        {
            # Nothing.
        }

        $fields = @("DocumentOwnerName","Status","DocumentCreatorName","FileUpdaterName", "FileUpdateDate", "DocumentOutTo","DocumentOutToName", "WorkFlow", "WorkFlowState", "DocumentUpdaterName", "DocumentUpdateDate")
        $fields.Foreach({
            if(-not [String]::IsNullOrEmpty($td.$_))
            {
                $spdocValues.Add($_, $td.$_)
            } `
            else
            {
                # Nothing, don't add the property
            }
        })

        if(-not [String]::IsNullOrEmpty($td.Status))
        {
            $status = $td.Status
            if($td.Status -eq "I")
            {
                $status = "Checked In"
            } `
            elseif($td.Status -eq "IF")
            {
                $status = "Final"
            }
            else
            {
                # Leave as is until I know better.
            }
            $spdocValues.Status = $status
        } `
        else
        {
            # Nothing, don't add the property
        }

        if((-not [String]::IsNullOrEmpty($td.Description)) -and ($td.Description -ne $td.Name))
        {
            $spDocValues.Add("FileDescription", $td.Description)
        } `
        else
        {
            # Nothing, no file description.
        }

        if(-not [String]::IsNullOrEmpty($td.Version))
        {
            $spDocValues.Add("DocumentVersion", $td.Version)
        } `
        else
        {
            $spDocValues.Add("DocumentVersion", "NoVersion")
        }

        if($null -ne $td.Attributes)
        {
            $b = 0
            while((-not $Script:HaveError) -and ($b -lt $td.Attributes.Count))
            {
                $listKeys = @($td.Attributes[$b].Keys)

                $c = 0
                while((-not $Script:HaveError) -and ($c -lt $listKeys.Length))
                {
                    if(-not [String]::IsNullOrEmpty($td.Attributes[$b][$listKeys[$c]]))
                    {
                        $fld = TestForSPDocumentLibraryField -connData $connData -libraryName $libraryName -fieldName $listKeys[$c]

                        if(-not $Script:HaveError)
                        {
                            if(($null -ne $fld) -and (-not $fld.Ignore))
                            {
                                $spdocValues.Add($fld.InternalName, $td.Attributes[$b][$listKeys[$c]])
                            } `
                            else
                            {
                                # Nothing, ignore the property
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        # Nothing, the attribute value is empty
                    }
                    $c++
                }

                $b++
            }
        } `
        else
        {
            # Nothing, no attributes to add...
        }
    } `
    else
    {
        LogError ("No ProjectWise document found in `$obj2Upload in {0}." -f @($me.Name))
    }

    if($Script:HaveError)
    {
        $spdocValues = $null
    } `
    else
    {
        $spKeys = @($spdocValues.Keys)
        $a = 0
        while((-not $Script:HaveError) -and ($a -lt $spKeys.Length))
        {
            $fld = TestForSPDocumentLibraryField -connData $connData -libraryName $obj2Upload.Paths[0] -fieldName $spKeys[$a]
            $a++
        }
    }

    return @(, $spdocValues)
}


function ExportDocumentFromPW_UploadToSP_newer
{
                            <#
                            If we got here, then CheckDocumentVersions has already been called.  This means, since we are here,
                                we need to upload the document, it doesn't exist, so let's now waste time checking again.
                        #>
                        try
                        {
                            $spFile = Get-PnPFile -Url $libInfo.FileURL -AsListItem -ErrorAction Stop

                            if($null -ne $spFile)
                            {
                                $Script:reportData.Documents.PreExisting++
                                $Script:reportData.Size.Skipped += $td.Size
                                $successful = $true
                                $obj2Upload.SPData.Processed = $true
                                if($null -ne $spFile.FieldValues)
                                {
                                    if($spFile.FieldValues.ContainsKey("FileRef"))
                                    {
                                        $obj2Upload.SPData.SPFile.ServerRelativeURL = $spFile.FieldValues["FileRef"]
                                    }

                                    if($spFile.FieldValues.ContainsKey("Created_x0020_Date"))
                                    {
                                        $obj2Upload.SPData.WhenUploaded = $spFile.FieldValues["Created_x0020_Date"]
                                    }
                                } `
                                else
                                {
                                    # Nothing, no field values to pull from...
                                }
                            } `
                            else
                            {
                                # File doesn't exist...
                            }
                        }
                        catch
                        {
                            if(($Error.Count -gt 0) -and ($Error[0].Exception.Message -match "File Not Found"))
                            {
                                $Error.Clear()
                            } `
                            else
                            {
                                LogError ("Failed to get file {0} from Sharepoint in {1}." -f @($libInfo.FileURL, $me.Name))
                            }
                        }

                        if($null -ne $spFile)
                        {
                            if($null -ne $spFile.FieldValues)
                            {
                                if($spFile.FieldValues["DocumentVersion"] -ne $obj2Upload.SourceObject.Version)
                                {
                                    $spFile = $null    # To make the code below upload the file.
                                } `
                                else
                                {
                                    # Nothing, all good.
                                }
                            } `
                            else
                            {
                                # Nothing, can't check what isn't there.
                            }
                        } `
                        else
                        {
                            # Nothing...
                        }

                        if($null -eq $spFile)
                        {
                        } `
                        else
                        {
                            # Nothing, don't upload over an existing document/version
                        }



                # If this document is outside the current project, then I need to check to see if it has already been uploaded and get it's version information since it MUST be a
                #   flatset reference.
                if(-not $uploadDocument)
                {
                    # Use the last document in $documentVersionsToUpload so we are looking at what should be the latest version of the document.  Remember, the list is sorted by FullPath and VersionSequence.
                    $currentVersionOfDocument = $documentVersionsToUpload[-1]

                    # If .DocVersionToLink has not been built, then build it.
                    #   The reason we need this is because I need 1) a way to determine if any of the versions need to be uploaded, and 2) it's a way
                    #   to determine if a file exists.
                    if($null -eq $currentVersionOfDocument.SPData.DocVersionToLink)
                    {
                        GetSPDocumentVersionLinks -currentVersionOfDocument $currentVersionOfDocument
                        if(-not $Script:HaveError)
                        {
                            # If we have no version to links, then upload the document.
                            $uploadDocument = $null -eq $currentVersionOfDocument.SPData.DocVersionToLink
                        } `
                        else
                        {
                            # Nothing, either displayed an error, or no file was found.
                        }
                    } `
                    else
                    {
                        # Already have version info for this file...
                    }
                } `
                else
                {
                    # Nothing, upload the document....
                }



                # Is this document part of this project?  If so, then upload it, if not, further work is needed.
                $uploadDocument = $documentsToUpload[0].SourceObject.FullPath -match ("^{0}" -f @([RegEx]::Escape($pwData.PWFolder.FullPath)))

                # If this document is outside the current project, then I need to check to see if it has already been uploaded and get it's version information since it MUST be a
                #   flatset reference.
                if(-not $uploadDocument)
                {
                    # Use the last document in $documentVersionsToUpload so we are looking at what should be the latest version of the document.  Remember, the list is sorted by FullPath and VersionSequence.
                    $currentVersionOfDocument = $documentVersionsToUpload[-1]

                    # If .DocVersionToLink has not been built, then build it.
                    #   The reason we need this is because I need 1) a way to determine if any of the versions need to be uploaded, and 2) it's a way
                    #   to determine if a file exists.
                    if($null -eq $currentVersionOfDocument.SPData.DocVersionToLink)
                    {
                        GetSPDocumentVersionLinks -currentVersionOfDocument $currentVersionOfDocument
                        if(-not $Script:HaveError)
                        {
                            # If we have no version to links, then upload the document.
                            $uploadDocument = $null -eq $currentVersionOfDocument.SPData.DocVersionToLink
                        } `
                        else
                        {
                            # Nothing, either displayed an error, or no file was found.
                        }
                    } `
                    else
                    {
                        # Already have version info for this file...
                    }
                } `
                else
                {
                    # Nothing, upload the document....
                }

                # Even if we are not uploading the document, we still need to run through the following loop to remove the documents from the list of documents to upload.
                #   At this point, the only way we are NOT uploading a document is if the document is part of another project and was already uploaded.
                $b = 0
                while((-not $Script:HaveError) -and ($b -lt $documentVersionsToUpload.Length))
                {
                    if($documentVersionsToUpload.Length -gt 1)
                    {
                        $pc = [float] ($b) / [float] ($documentVersionsToUpload.Length)
                        $status = "{0,7:P2} Complete" -f @($pc)
                        $activity = "Uploading {0,2} of {1,2} versions of {2}" -f @(($b + 1), $documentVersionsToUpload.Length, $documentVersionsToUpload[$b].SourceObject.Name)
                        Write-Progress -Id 2 -Activity $activity -Status $status -PercentComplete ($pc * 100)
                    } `
                    else
                    {
                        # No progress bar for a single file.
                    }

                    # Yes, this is correct.  If I have versions of the document, then don't mess with them.
                    if($uploadDocument)
                    {
                        # If this is the last document in $documentVersionsToUpload, then do not use the version sequence number to determine it's location on storage.

                        # FORDBG:   $obj2Upload = $documentVersionsToUpload[$b]; [Switch] $useVersion = ($b -ne ($documentVersionsToUpload.Length - 1))
                        ExportDocumentFromPW_UploadToSP -pwData $pwData -obj2Upload $documentVersionsToUpload[$b] -useVersion:($b -ne ($documentVersionsToUpload.Length - 1))
                    } `
                    else
                    {
                        # Nothing, don't need to upload a document that already exists.
                        LogInfo ("Skipping upload of {0}.  Already exists." -f @($documentVersionsToUpload[$b].SourceObject.FullPath))
                        $documentVersionsToUpload[$b].SPData.Processed = $true
                        $uploadSkipped++
                    }

                    if(-not $Script:HaveError)
                    {
                        if($uploadDocument)
                        {
                            $documentsUploaded++
                        }
                        else
                        {
                            # Don't increment uploaded if we didn't upload.
                        }

                        if((($documentsUploaded + $uploadSkipped) % 10) -eq 0)
                        {
                            ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                        } `
                        else
                        {
                            # Nothing
                        }

                        if(-not $Script:HaveError)
                        {
                            $totalSizeUploaded += $documentVersionsToUpload[$b].SourceObject.FileSize
                            $uploadedDocIdx = $documentsToUpload.IndexOf($documentVersionsToUpload[$b])
                            if($uploadedDocIdx -gt -1)
                            {
                                $documentsToUpload.RemoveAt($uploadedDocIdx)
                            } `
                            else
                            {
                                LogError ("Failed to remove uploaded document {0}:{1} from documents to upload in {2}." -f @($documentVersionsToUpload[$b].SourceObject.DocumentGUID, $documentVersionsToUpload[$b].SourceObject.FullPath, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed an error.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }

                    # Redo the top level progress bar each time we upload a new file.
                    $pc = [float] ($totalSizeUploaded) / [float] ($totalUploadSize)
                    $status = "{0} of {1} | {2,7:P2} Complete" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc)
                    if($totalSizeUploaded -gt 0)
                    {
                        $elapsedTicks = $sw.ElapsedTicks
                        $ticksPerItem = $elapsedTicks / $totalSizeUploaded
                        $totalETATicks = $ticksPerItem * ($totalUploadSize)
                        $remainingETATicks = $totalETATicks - $elapsedTicks
                        $etaTS = [TimeSpan]::new($remainingETATicks)
                        $etaDT = [DateTime]::Now.Add($etaTS)

                        $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString("dd\.hh\:mm\:ss"), $etaTS.ToString("dd\.hh\:mm\:ss"), $etaDT.ToString())
                    }

                    # This is just for the progress bar...
                    $fpStr = $documentsToUpload[0].SourceObject.FullPath
                    if($fpStr.Length -gt $MAXFPSTRLEN)
                    {
                        $startIdx = $fpStr.Length - $MAXFPSTRLEN
                        $fpStr = "...{0}" -f @($fpStr.SubString($startIdx))
                    }
                    $activity = $Script:uploadProgressFMTStr -f @(($documentsUploaded + $uploadSkipped), $numDocToUpload, $documentsToUpload[0].SourceObject.FullPath, (Format-StorageNumber $documentsToUpload[0].SourceObject.FileSize))
                    Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($pc * 100)
                    $b++
                }

                if($documentVersionsToUpload.Length -gt 1)
                {
                    Write-Progress -Id 2 -Completed
                } `
                else
                {
                    # Nothing, no progress bar for 1 file.
                }


                if($Script:HaveError)
                {
                    LogError ("***** DELETE ALL VERSIONS OF {0}, then fix viablePathsDict export so documents get recreated on -restart *****" -f @($documentsToUpload[0].SourceObject.FullPath))
                } `
                else
                {
                    #  In a later version, I might automate this...
                }


}

function GetLibraryDataFromObj_20251122_1606
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $CreateMissingLibrary
    )

    $retval = [PSCustomObject]@{
        SPFolderPathPieces = $null
        LibraryName = $null
        Library = $null
        LibURL = $null
        FolderURL = $null
        FileURL = $null
        LibraryFolderName = $null
    }

    if($null -ne $obj2Upload.SourceObject)
    {
        if(-not [String]::IsNullOrEmpty($obj2Upload.SPData.FolderName))
        {
            $retval.SPFolderPathPieces = @($obj2Upload.SPData.FolderName -split "/")

            if(-not [String]::IsNullOrEmpty($retval.SPFolderPathPieces[0]))
            {
                $retval.LibraryName = TranslateToDocLibName -name $retval.SPFolderPathPieces[0]

                if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($retval.LibraryName))
                {
                    if($CreateMissingLibrary.IsPresent)
                    {
                        CreateNewDocumentLibrary -spDocLibName $retval.LibraryName
                        if(-not $Script:HaveError)
                        {
                            if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($retval.LibraryName))
                            {
                                $retval.Library = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName]
                                $retval.LibURL = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName].RootFolder.ServerRelativeURL
                                $retval.LibraryFolderName = @($retval.LibURL -split "/")[-1]
                            } `
                            else
                            {
                                LogError ("Missing document library for {0} in {1} after trying to create." -f @($obj2Upload.SourceObject.FullPath, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        LogError ("Missing document library for {0} in {1}." -f @($obj2Upload.SourceObject.FullPath, $me.Name))
                    }
                } `
                else
                {
                    $retval.Library = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName]
                    $retval.LibURL = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName].RootFolder.ServerRelativeURL
                    $retval.LibraryFolderName = @($retval.LibURL -split "/")[-1]
                }
            } `
            else
            {
                LogError ("Malformed Sharepoint folder name [{0}], missing document library name in {1}." -f @($obj2Upload.SPData.FolderName, $me.Name))
            }
        } `
        else
        {
            LogError ("Missing SharePoint folder name for {0} in {1}." -f @($td.FullPath, $me.Name))
        }
    } `
    else
    {
        LogError ("Missing source object for object to upload in {0}" -f @($me.Name))
    }

    if(-not $Script:HaveError)
    {
        $retval.FolderURL = "{0}/{1}" -f @($retval.LibURL, ($retval.SPFolderPathPieces[1..($retval.SPFolderPathPieces.Length - 1)] -join "/"))

        if($obj2Upload.SourceObject.MyType -eq "ProjectWiseDocument")
        {
            if(-not [String]::IsNullOrEmpty($obj2Upload.SPData.FileName))
            {
                $retval.FileURL = "{0}/{1}" -f @($retval.FolderURL, $obj2Upload.SPData.FileName)
            } `
            else
            {
                LogError ("Missing SharePoint file name for {0} in {1}." -f @($obj2Upload.SourceObject.FullPath, $me.Name))
                $retval = $null
            }
        } `
        else
        {
            # Nothing, folders don't have file names.
        }
    } `
    else
    {
        $retval = $null
    }

    return @(, $retval)
}

function MakeKeyDocumentFields
{
    # Make sure some key document fields are available.
    $fields = @("DocumentVersion","OriginalName", "DocumentOwnerName","Status","DocumentCreatorName","FileUpdaterName", "FileUpdateDate", "DocumentOutTo","DocumentOutToName", "WorkFlow", "WorkFlowState", "DocumentUpdaterName", "DocumentUpdateDate", "FileDescription")
    $errorOccurred = $false
    $docLibNames = @($Script:connData.ConnectionInformation.SharePointDocumentLibraries.Keys)
    $docLibNames.ForEach({
        $libraryName = $_
        $fields.ForEach({
            try
            {
                $fld = TestForSPDocumentLibraryField -library $libraryName -fieldName $_
            }
            catch
            {
                $errorOccurred = $true
            }
        })
    })

    $Script:HaveError = $errorOccurred
}



function GetDefinedFieldsLists
{
    $me = $MyInvocation.MyCommand
    $libraryNames = @($Script:connData.ConnectionInformation.SharePointDocumentLibraries.Keys)
    $libraryNames.Foreach({
        GetLibraryDefinedFieldsList -libraryName $_
    })
}


function ExportPW2SP_20251123_2013
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $viablePathsExportPath,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $uriEncode
    )

    $me = $MyInvocation.MyCommand
    $PSStyle.Progress.View = 'Minimal'
    $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
    $Error.Clear()
    $sw = [System.Diagnostics.Stopwatch]::new()
    $sw.Start()

    $projectFolderObjs = @(@($viablePathsDict.Values).Where({ $_.Paths.Length -eq 2 }))
    LogInfo ("Checking for existing folders and files...")
    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $projectFolderObjs.Length))
    {
        $pathPieces = $projectFolderObjs[$a].SPData.FolderName -split "/"
        if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($pathPieces[0]))
        {
            # If we have to create the document library, then there are no pre-existing folders and files.
            CreateNewDocumentLibrary -spDocLibName $pathPieces[0]
        } `
        else
        {
            $lib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$pathPieces[0]]
            $libPathPieces = $lib.RootFolder.ServerRelativeUrl -split "/"
            $folderPath = "{0}/{1}" -f @($libPathPieces[-1], $pathPieces[-1])

            $pc = [float] ($a) / [float] ($projectFolderObjs.Length)
            $status = "{0,7:P2} Complete" -f @($pc)
            $activity = "Checking existing folders and files in {0} ({1,2} of {2,2})" -f @($folderPath, ($a + 1), $projectFolderObjs.Length)
            Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($pc * 100)

            # Build a dictionary of sourceobjects to process by sourceobject type.
            #   Within each dictionary, create a sorted dictionary of url to sourceobject.
            # The point of this dictionary is to make searching for existing SharePoint objects faster.
            $pwObjDict = [System.Collections.Generic.SortedDictionary[String, Object]]::new()
            $keys = @($viablePathsDict.Keys)
            $processedKeys = 0
            $keys.ForEach({
                $pc = [float] ($processedKeys) / [float] ($keys.Length)
                $status = "{0,7:P2} Complete" -f @($pc)
                $activity = "Building lookup dictionary"
                Write-Progress -Id 2 -Activity $activity -Status $status -PercentComplete ($pc * 100)
                $processedKeys++

                $vp = $viablePathsDict[$_]

                # Let's reset the Processed to $false, and let the loop below change it back to $true based on what we
                #    actually find in SharePoint.
                $vp.SPData.Processed = $false

                $libInfo = GetLibraryDataFromObj -obj2Upload $vp

                if($null -ne $libInfo)
                {
                    # Replace the leading folder name with the document library's folder name.
                    $folderPieces = $vp.SPData.FolderName -split "/"
                    $folderPieces[0] = $libInfo.LibraryFolderName
                    $folderName = $folderPieces -join "/"

                    if(-not $pwObjDict.ContainsKey($vp.SourceObject.MyType))
                    {
                        $typeDict = [System.Collections.Generic.SortedDictionary[String, System.Collections.Generic.List[Object]]]::new()
                        $pwObjDict.Add($vp.SourceObject.MyType, $typeDict)
                    } `
                    else
                    {
                        $typeDict = $pwObjDict[$vp.SourceObject.MyType]
                    }

                    if($vp.SourceObject.MyType -eq "ProjectWiseDocument")
                    {
                        $url = "/sites/{0}/{1}/{2}" -f @($Script:connData.ConnectionInformation.SharePointSiteName, $folderName, $vp.SPData.FileName)
                    } `
                    else
                    {
                        $url = "/sites/{0}/{1}" -f @($Script:connData.ConnectionInformation.SharePointSiteName, $folderName)
                    }

                    if(-not $typeDict.ContainsKey($url))
                    {
                        $newList = [System.Collections.Generic.List[Object]]::new()
                        $typeDict.Add($url, $newList)
                    } `
                    else
                    {
                        # No dups please.
                    }

                    $typeDict[$url].Add($vp)
                } `
                else
                {
                    # Already logged an error in GetLibraryDataFromObj
                    break
                }
            })
            Write-Progress -Id 2 -Completed

            try
            {
                # Get all the folders and files SharePoint knows about under this project.
                LogInfo ("Retrieving existing folders and files from SharePoint.  This could take some time....")
                $fnf = Get-PnPFolderItem -FolderSiteRelativeUrl $folderPath -Recursive -ErrorAction Stop
                if($null -ne $fnf)
                {
                    $b = 0
                    while((-not $Script:HaveError) -and ($b -lt $fnf.Length))
                    {
                        $pc = [float] ($b) / [float] ($fnf.Length)
                        $status = "{0,7:P2} Complete" -f @($pc)
                        $activity = "Checking object ({0,2} of {1,2}" -f @(($b + 1), $fnf.Length)
                        Write-Progress -Id 2 -Activity $activity -Status $status -PercentComplete ($pc * 100)

                        $f = $fnf[$b]
                        $existingObjs = $null
                        if($f -is [Microsoft.SharePoint.Client.File])
                        {
                            if($pwObjDict.ContainsKey("ProjectWiseDocument"))
                            {
                                if($pwObjDict["ProjectWiseDocument"].ContainsKey($f.ServerRelativeURL))
                                {
                                    $existingObjs = $pwObjDict["ProjectWiseDocument"][$f.ServerRelativeURL].Where({ $_.SourceObject.FileSize -eq $f.Length })
                                } `
                                else
                                {
                                    # Nothing, doesn't exist.... WHAT?  How is there a SharePoint document that ProjectWise doesn't have....
                                    LogInfo ("Extra SharePoint file: [{0}]" -f @($f.ServerRelativeURL))
                                }
                            } `
                            else
                            {
                                LogError ("No ProjectDocuments in viable paths lookup dictionary!!!")
                            }
                        } `
                        elseif($f -is [Microsoft.SharePoint.Client.Folder])
                        {
                            if($pwObjDict.ContainsKey("ProjectWiseFolder"))
                            {
                                if($pwObjDict["ProjectWiseFolder"].ContainsKey($f.ServerRelativeURL))
                                {
                                    $existingObjs = $pwObjDict["ProjectWiseFolder"][$f.ServerRelativeURL]
                                } `
                                else
                                {
                                    # Nothing, doesn't exist.... WHAT?  How is there a SharePoint document that ProjectWise doesn't have....
                                    LogInfo ("Extra SharePoint file: [{0}]" -f @($f.ServerRelativeURL))
                                }
                            } `
                            else
                            {
                                LogError ("No ProjectFolders in viable paths lookup dictionary!!!")
                            }
                        }
                        else
                        {
                            LogWarning ("Unknown object type [{0}] while checking existing folders and files." -f @($f.TypedObject.ToString()))
                        }

                        if($null -ne $existingObjs)
                        {
                            $existingObjs | ForEach-Object {
                                $_.SPData.Processed = $true
                                $_.SPData.WhenUploaded = $f.TimeCreated.ToString()
                                $_.SPData.SPFile.ServerRelativeURL = $f.ServerRelativeUrl
                            }
                        } `
                        else
                        {
                            LogWarning ("Extra SharePoint object [{0}] while checking existing folders and files." -f @($f.ServerRelativeURL))
                        }

                        $b++
                    }
                    Write-Progress -Id 2 -Completed
                } `
                else
                {
                    # Nothing there....
                }
            }
            catch
            {
                $Error.Clear()
                # This is fine, just nothing there....
            }
        }
        $a++
    }
    Write-Progress -Id 1 -Completed

    # make sure we have a viable path for the main project folder
    if($viablePathsDict.ContainsKey($pwData.PWFolder.DocumentGUID))
    {
        $fo = $viablePathsDict[$pwData.PWFolder.DocumentGUID]

        # Have we already created the project folder in SharePoint?
        if(-not $fo.SPData.Processed)
        {
            $null = CreateSharePointProjectFolder -fo $fo
            if(-not $Script:HaveError)
            {
                $fo.SPData.Processed = $true
                $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
            }
        } `
        else
        {
            # Nothing, the project folder should already exist.
        }
    } `
    else
    {
        LogError ("Missing viable path object for project folder {0} in {1}." -f @($pwData.PWFolder.FullPath))
    }

    if(-not $Script:HaveError)
    {
        CreateSharePointSubFolders -pwData $pwData -viablePathsDict $viablePathsDict
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    # Where we export $viablePathsDict to, to track progress.
    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath

    $sw.Reset()
    $sw.Start()
    if(-not $Script:HaveError)
    {
        $documentsToUpload = [System.Collections.Generic.List[System.Object]]::new()
        $allDocuments = [System.Collections.Generic.List[System.Object]]::new()
        $flatSets = [System.Collections.Generic.List[System.Object]]::new()
        $flatSetReferences = [System.Collections.Generic.List[System.Object]]::new()

        # Only get:
        #    Objects which are more than 2 levels deep  $_.Paths.Length -eq 1 = Active/Inactive projects (the document library), $_.Paths.Length -eq 2 = project folder.
        #    ProjectWise Documents
        #  Sorted by FullPath and VersionSequence
        #    This should ensure documents with lower VersionSequence numbers are uploaded first, that way, when the next version is uploaded over the top of the existing document
        #       the higher VersionSequence becomes the current version.
        @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} ).Foreach({
            if(-not $_.SourceObject.IsSet)
            {
                $allDocuments.Add($_)
            } `
            else
            {
                $flatSets.Add($_)
            }

            if($_.IsFlatSetReference)
            {
                $flatSetReferences.Add($_)
            } `
            else
            {
                # Nothing...
            }

            if(($Script:reprocess.IsPresent) -or (-not $_.SPData.Processed))
            {
                $documentsToUpload.Add($_)
            } `
            else
            {
                # Nothing, not uploading this document
            }
        })

        $totalUploadSize = ($documentsToUpload | Measure-Object -Sum { $_.SourceObject.FileSize }).Sum
        $totalSizeUploaded = 0
        $documentsUploaded = 0
        $uploadSkipped = 0
        LogInfo ("Total Documents: {0}" -f @($allDocuments.Count))
        LogInfo ("Total FlatSets: {0}" -f @($flatSets.Count))
        LogInfo ("Documents to upload: {0}" -f @($documentsToUpload.Count))
        LogInfo ("Flatset referenced documents (links to create): {0}" -f @($flatSetReferences.Count))

        $a = 0
        $numDocToUpload = $documentsToUpload.Count
        while((-not $Script:HaveError) -and ($documentsToUpload.Count -gt 0))
        {
            $documentVersionsToUpload = @($documentsToUpload | Where-Object { $_.SourceObject.FullPath -eq $documentsToUpload[0].SourceObject.FullPath } | Sort-Object @{E={ $_.SourceObject.VersionSequence }})

<#    FOR DEBUGGING... REMOVE documents from documents to upload until I find what I want...

$documentsToUpload.Count
$documentVersionsToUpload.Length

$documentVersionsToUpload.ForEach({
    $idx = $documentsToUpload.IndexOf($_)
    if($idx -ge 0)
    {
        $documentsToUpload.RemoveAt($idx)
    }
})

#>

            $pc = [float] ($totalSizeUploaded) / [float] ($totalUploadSize)
            $status = "{0} of {1} | {2,7:P2} Complete" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc)
            if($totalSizeUploaded -gt 0)
            {
                $elapsedTicks = $sw.ElapsedTicks
                $ticksPerItem = $elapsedTicks / $totalSizeUploaded
                $totalETATicks = $ticksPerItem * ($totalUploadSize)
                $remainingETATicks = $totalETATicks - $elapsedTicks
                $etaTS = [TimeSpan]::new($remainingETATicks)
                $etaDT = [DateTime]::Now.Add($etaTS)

                $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString("dd\.hh\:mm\:ss"), $etaTS.ToString("dd\.hh\:mm\:ss"), $etaDT.ToString())
            }
            $fpStr = $documentsToUpload[0].SourceObject.FullPath
            if($fpStr.Length -gt $MAXFPSTRLEN)
            {
                $startIdx = $fpStr.Length - $MAXFPSTRLEN
                $fpStr = "...{0}" -f @($fpStr.SubString($startIdx))
            }
            $activity = $Script:uploadProgressFMTStr -f @(($documentsUploaded + $uploadSkipped), $numDocToUpload, $documentsToUpload[0].SourceObject.FullPath, (Format-StorageNumber $documentsToUpload[0].SourceObject.FileSize))

            if($documentVersionsToUpload.Length -gt 0)
            {
                # The last object in $documentVersionsToUpload is the current ProjectWise document (based on .VersionSequence)
                #   After CheckDocumentVersions, we either upload all of $documentVersionsToUpload or none of them...
                $spDocVer = CheckDocumentVersions -documentsToCheck $documentVersionsToUpload

                if(-not $Script:HaveError)
                {
                    if($null -ne $spDocVer)
                    {
                        # Woot!  All versions are intact... Nothing to upload...
                    } `
                    else
                    {
                        # Ah crap... guess we uploading...
                        UploadDocumentsToSharePoint -pwData $pwData -documentsToUpdate $documentVersionsToUpload
                    }


                    if(-not $Script:HaveError)
                    {
                        $documentVersionsToUpload.ForEach({
                            # Do this whether we upload or not... still counts towards the total.
                            $totalSizeUploaded += $_.SourceObject.FileSize

                            # Also remove the files we skip/upload from the list of documents we need to process...
                            $uploadedDocIdx = $documentsToUpload.IndexOf($docsToUpload[$a])
                            if($uploadedDocIdx -gt -1)
                            {
                                $documentsToUpload.RemoveAt($uploadedDocIdx)
                            } `
                            else
                            {
                                LogError ("Failed to remove uploaded document {0}:{1} from documents to upload in {2}." -f @($documentVersionsToUpload[$b].SourceObject.DocumentGUID, $documentVersionsToUpload[$b].SourceObject.FullPath, $me.Name))
                            }
                        })
                    } `
                    else
                    {
                        # Nothing, already logged an error
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Missing document versions to uplad for {0}:{1} in {2}." -f @($documentsToUpload[0].SourceObject.DocumentGUID, $documentsToUpload[0].SourceObject.FullPath, $me.Name))
            }
            $a++
        }
        Write-Progress -Id 1 -Completed
        LogInfo ("Documents uploaded: {0}" -f @($documentsUploaded))
        LogInfo ("Documents skipped: {0}" -f @($uploadSkipped))




<#    Continue here with processing flat sets....   #>


        <#

            Upload ... err create document sets
                1) Create the docment set in the appropriate folder
                2) Add links to the document set for each document reference.

        #>

        # Need to look at all flatsets, not just the ones with .SPUpload.Processed -eq $false, since we also need to see if all the flatset reference have been uploaded.
        $fsToProcess =  @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and ($_.SourceObject.IsSet) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} )
        LogInfo ("Processing {0} Flatsets" -f @($fsToProcess.Length))

        # Just some admin stuff...
        $totalProcesses = 0
        $fsToProcess.Foreach({
            $totalProcesses++       # Create the document set.
            if($null -ne $_.SourceObject.FlatSetReferences)
            {
                $totalProcesses += $_.SourceObject.FlatSetReferences.Count   # Create each of the links
            } `
            else
            {
                LogError ("Missing PW FlatSet references for {0}:{1} in {2}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SourceObject.FullPath, $me.Name))
            }
        })
        $processesCompleted = 0

        LogInfo ("`tReferenced documents: {0}" -f @(($totalProcesses - $fsToProcess.Length)))
        if(-not $Script:HaveError)
        {
            # Reset some admin stuff..
            $sw.Restart()

            $docSetsCreated = 0
            # Next need to create all the document sets and add the document links.
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $fsToProcess.Length))
            {
                $pc = [float] $processesCompleted / [float] $totalProcesses
                Write-Progress -Id 1 -Activity ("Processing FlatSet {0} of {1}" -f @(($a + 1), $fsToProcess.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                $libInfo = GetLibraryDataFromObj -obj2Upload $fsToProcess[$a] -CreateMissingLibrary
                if($null -ne $libInfo)
                {
                    # If we don't think we've processed this document set, then proceed like we need to create it.
                    $createDocumentSet = -not $fsToProcess[$a].SPData.Processed
                    if(-not $fsToProcess[$a].SPData.Processed)
                    {
                        $createDocumentSet = $true

                        try
                        {
                            $existingDS = Get-PnPListItem -List $libInfo.Library -FolderServerRelativeUrl $libInfo.FolderURL -IncludeContentType -ErrorAction Stop | Where-Object { ($_.ContentType.Name -eq "Document Set") -and ($_.Title -eq $fsToProcess[$a].SPData.Name) }
                            if($null -ne $existingDS)
                            {
                                $Script:reportData.DocumentSets.PreExisting++
                                $createDocumentSet = $false    # No need to create what already exists.
                                $ds = $existingDS.FieldValues["FileRef"]
                                $fsToProcess[$a].SPData.Processed = $true
                                [DateTime] $dt = [DateTime]::Now    # Just use the current date and time unless we get a value for when it was created.
                                if(-not [String]::IsNullOrEmpty($existingDS.FieldValues["Created_x0020_Date"]))
                                {
                                    # Capture the return value... it really doesn't matter, either way we'll have a useable value in $dt.
                                    $null = [DateTime]::TryParse($existingDS.FieldValues["Created_x0020_Date"], [ref] $dt)
                                } `
                                else
                                {
                                    # Nothing, just the default...
                                }
                                $fsToProcess[$a].SPData.WhenUploaded = $dt.ToString()
                            } `
                            else
                            {
                                # Nothing, there is no document set...
                            }
                        }
                        catch
                        {
                            # No big deal, the docment set does not exist.
                            $Error.Clear()
                        }

                        if($createDocumentSet)
                        {
                            LogInfo ("Creating document set {0} in {1}" -f @($fsToProcess[$a].SPData.FileName, $libInfo.FolderURL))
                            try
                            {
                                $ds = Add-PnPDocumentSet -List $libInfo.Library -ContentType "Document Set" -Name $fsToProcess[$a].SPData.FileName -Folder $libInfo.FolderURL -ErrorAction Stop
                                if(-not [String]::IsNullOrEmpty($ds))
                                {
                                    $Script:reportData.DocumentSets.Created++
                                    $docSetsCreated++
                                    $fsToProcess[$a].SPData.SPFile.ServerRelativeURL = $ds
                                    $fsToProcess[$a].SPData.Processed = $true    # We created the document set.
                                    $fsToProcess[$a].SPData.WhenUploaded = [DateTime]::Now.ToString()
                                } `
                                else
                                {
                                    LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0} to {1}/{2} in {3}." -f @($fsToProcess[$a].SPData.FileName, $libInfo.FolderURL, $fsToProcess[$a].SPData.FileName, $me.Name))
                                }
                            }
                            catch
                            {
                                LogError ("Failed to add document set: {0}:{1} to {2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SPData.FileName, $libInfo.FolderURL, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, document set already exists.
                        }
                    } `
                    else
                    {
                        # Need to populate $ds so it's available below since we didn't create a new document set.
                        $ds = $fsToProcess[$a].SPData.SPFile.ServerRelativeURL
                    }

                    if(-not $Script:HaveError)
                    {
                        if(-not [String]::IsNullOrEmpty($ds))
                        {
                            # Now, create all the document links in the document set.
                            LogInfo ("Creating {0} reference link for document set {1}/{2}" -f @($fsToProcess[$a].SourceObject.FlatSetReferences.Count, $libInfo.FolderURL, $fsToProcess[$a].SPData.FileName))
                            $linksCreated = 0
                            $b = 0
                            while((-not $Script:HaveError) -and ($b -lt $fsToProcess[$a].SourceObject.FlatSetReferences.Count))
                            {
                                $pc = [float] $b / [float] $fsToProcess[$a].SourceObject.FlatSetReferences.Count
                                Write-Progress -Id 2 -Activity ("Adding links to document set {0} of {1}" -f @(($b + 1), $fsToProcess[$a].FlatSetReferences.Count)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)

                                if($viablePathsDict.ContainsKey($fsToProcess[$a].SourceObject.FlatSetReferences[$b]))
                                {
                                    $referencedDoc = $viablePathsDict[$fsToProcess[$a].SourceObject.FlatSetReferences[$b]]

                                    # Have we already created a link for this flatset??    SORRY, only 1 link per flatset....
                                    if(-not $referencedDoc.SPData.DocSetLinksCreated.Contains($fsToProcess[$a].SourceObject.FlatSetReferences[$b]))
                                    {
                                        # Need to determine if the referenced document points to the current version of a file, or not.

                                        # Get all the versions of the referenced document.  Sorted by FullPath and VersionSequence so the current version is the last.
                                        $documentVersions = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and ($_.SourceObject.FullPath -eq $referencedDoc.SourceObject.FullPath) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }})

                                        if($documentVersions.Length -gt 0)
                                        {
                                            # The last document in the array is always the current document since it's sorted by .FullPath and .VersionSequence.
                                            $currentDocument = $documentVersions[-1]

                                            # The current version will be the last file in the sorted array (by fullpath and versionsequence)...So here, we need to get the index
                                            #    of the version we are needing to check.
                                            # NOTE: We are not looking for the index of the current document, that is index -1, we are looking for the index of the version of the
                                            #    document referenced by the flatset.
                                            $versionIdx = $documentVersions.IndexOf( ($documentVersions | Where-Object {$_.SourceObject.DocumentGUID -eq $fsToProcess[$a].SourceObject.FlatSetReferences[$b]}))

                                            if($versionIdx -gt -1)
                                            {
                                                # From here, the point is to end up with a viable value for $docLink....
                                                $docLink = [String]::Empty

                                                # If the version index is the last item in the array, then we are safe to use the current file URL...
                                                $isCurrentVersion = ($versionIdx -eq ($documentVersions.Length - 1))
                                                if($isCurrentVersion)
                                                {
                                                    if(-not [String]::IsNullOrEmpty($referencedDoc.SPData.SPFile.ServerRelativeURL))
                                                    {
                                                        $docLink = $referencedDoc.SPData.SPFile.ServerRelativeURL
                                                    } `
                                                    else
                                                    {
                                                        LogError ("No SharePoint document relative URL for {0} in {1}." -f @($fsToProcess[$a].SourceObject.FullPath, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    # Not the current file, so we have to get a link to a previous version of the file...

                                                    # If .DocVersionToLink has not been built, then build it.
                                                    if($null -eq $currentDocument.SPData.DocVersionToLink)
                                                    {
                                                        GetSPDocumentVersionLinks -currentVersionOfDocument $currentDocument
                                                    } `
                                                    else
                                                    {
                                                        # Already have version info for this file...
                                                    }

                                                    $versionToFind = $referencedDoc.SourceObject.Version
                                                    if([String]::IsNullOrEmpty($versionToFind))
                                                    {
                                                        $versionToFind = "NoVersion"
                                                    } `
                                                    else
                                                    {
                                                        # Nothing.
                                                    }

                                                    if(-not $Script:HaveError)
                                                    {
                                                        if($null -ne $currentDocument.SPData.DocVersionToLink)
                                                        {
                                                            if($currentDocument.SPData.DocVersionToLink.ContainsKey($versionToFind))
                                                            {
                                                                $docLink = $currentDocument.SPData.DocVersionToLink[$versionToFind]
                                                            } `
                                                            else
                                                            {
                                                                LogError ("Missing document link for {0} Version {1} in {2}." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            LogError ("Missing document link for {0} Version {1} in {2}.  No document version links." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Already have version info for this file...
                                                    }
                                                }

                                                if(-not $Script:HaveError)
                                                {
                                                    if(-not [String]::IsNullOrEmpty($docLink))
                                                    {
                                                        if($isCurrentVersion)
                                                        {
                                                            $docLink = "{0}{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $docLink)
                                                        } `
                                                        else
                                                        {
                                                            $docLink = "{0}/sites/{1}/{2}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $Script:connData.ConnectionInformation.SharePointSiteName, $docLink)
                                                        }

                                                        $existingLink = $null
                                                        try
                                                        {
                                                            $existingLink = Get-PnPFile -Url $docLink -ErrorAction Stop
                                                        }
                                                        catch
                                                        {
                                                            # No worries, the link already exists.
                                                            $Script:reportData.DocumentLinks.PreExisting++
                                                            $Error.Clear()
                                                            $existingLink = $null
                                                        }

                                                        if($null -eq $existingLink)
                                                        {
                                                            # Create an internet shortcut to the proper document version and add it to the document set.
                                                            $linkContent = "[InternetShortcut]`nURL={0}" -f @($docLink)
                                                            $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))
                                                            $targetFolder = "{0}/{1}" -f @($libInfo.FolderURL, $fsToProcess[$a].SPData.FileName)
                                                            $linkName = "{0}.url" -f @($referencedDoc.SourceObject.Name)
                                                            $spDocFields = BuildDocumentProperties -obj2Upload $referencedDoc
                                                            if($null -ne $spDocFields)
                                                            {
                                                                $spDocFields.Add("_ShortcutUrl", $docLink)
                                                            } `
                                                            else
                                                            {
                                                                $spDocFields = @{ "_ShortcutUrl" = $docLink }
                                                            }

                                                            try
                                                            {
                                                                $null = Add-PnPFile -FileName $linkName -Folder $targetFolder -Stream $stream -Values $spDocFields -ErrorAction Stop
                                                                $linksCreated++
                                                                $Script:reportData.DocumentLinks.Created++
                                                            }
                                                            catch
                                                            {
                                                                LogError ("Failed to create document link {0} for document set {1} in {2}." -f @($docLink, $fsToProcess[$a].SPData.FileName, $me.Name))
                                                            }

                                                            if(-not $Script:HaveError)
                                                            {
                                                                # $referencedDoc refers to the referenced document, so all we need to do here is flag that we've created the link for it
                                                                #   Add the flatset's document GUID to the list to signal we created it.
                                                                $referencedDoc.SPData.DocSetLinksCreated.Add($fsToProcess[$a].SourceObject.DocumentGUID)
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, already displayed an error.
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, link already exists.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogError ("No document link available for {0} Version {1} in {2}.  docLink is empty." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    # Nothing, already logged an error
                                                }
                                            } `
                                            else
                                            {
                                                LogError ("Unable to document index of {0}:{1} in {2}" -f @($referencedDoc.SourceObject.DocumentGUID, $referencedDoc.SourceObject.FullPath, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Unable to locate any versions of {0}:{1} in viable paths dictionary {2}." -f@($referencedDoc.SourceObject.DocumentGUID, $referencedDoc.SourceObject.FullPath, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, no need to create a duplicate link.
                                    }
                                } `
                                else
                                {
                                    LogError ("Missing viable path object for {0} in {1}." -f @($fsToProcess[$a].SourceObject.FlatSetReferences[$b], $me.Name))
                                }

                                $processesCompleted++
                                if(($processesCompleted % 10) -eq 0)
                                {
                                    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                                } `
                                else
                                {
                                    # Nothing
                                }
                                $b++
                            }
                            Write-Progress -Id 2 -Completed
                            LogInfo ("Created {0} links" -f @($linksCreated))
                        } `
                        else
                        {
                            LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0}:{1}/{2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SourceObject.FullPath, $fsToProcess[$a].SPData.FileName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }

                    $processesCompleted++
                    if(($processesCompleted % 10) -eq 0)
                    {
                        ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                    } `
                    else
                    {
                        # Nothing
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }

                $a++
            }
            Write-Progress -Id 1 -Completed
            LogInfo ("Created {0} document sets" -f @($docSetCreated))
            $sw.Stop()
        } `
        else
        {
            # Nothing, already displayed an error.
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    # Save viablePathsDict one last time.
    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
}
function FixUpViablePaths_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $me = $MyInvocation.MyCommand
    if($viablePathsDict.ContainsKey($pwData.PWFolder.DocumentGUID))
    {
        if(-not [String]::IsNullOrEmpty($viablePathsDict[$pwData.PWFolder.DocumentGUID].SPData.FolderName))
        {
            # Have we already fixed this viable paths dictionary up?  Or perhaps created it correctly??
            if($viablePathsDict[$pwData.PWFolder.DocumentGUID].SPData.FolderName -match "^Active|Inactive Projects")
            {
                # Nope, still need to fix it up.

                $vpKeys = @($viablePathsDict.Keys)
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $vpKeys.Length))
                {
                    $vp = $viablePathsDict[$vpKeys[$a]]

                    if(-not [String]::IsNullOrEmpty($vp.SPData.FolderName))
                    {
                        $pathPieces = $vp.SPData.FolderName -split "/"
                        if($pathPieces[0] -match "Active|Inactive Projects")
                        {
                            if($pathPieces.Length -gt 1)
                            {
                                $vp.SPData.FolderName = $pathPieces[1..($pathPieces.Length -1)] -join "/"
                            } `
                            else
                            {
                                # This will be the top level project folder....
                                $vp.SPData.FolderName = [String]::Empty
                            }
                        } `
                        else
                        {
                            LogError ("Unknown path for {0}:{1} in {2}." -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Empty SPData folder name for {0}:{1}")
                    }
                    $a++
                }
            } `
            else
            {
                # Nothing, already fixed up this viable paths dictionary.
            }
        } `
        else
        {
            LogError ("Missing SPData.FolderName for {0}:{1} in {2}." -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
        }

    } `
    else
    {
        LogError ("Viable paths data and PW Data are out of sync in {0}." -f @($me.Name))
    }
}

function BuildViablePathsDictionary_20251125_1249
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [Object] $fromNode,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyString()]
        [String] $parentPath = "",

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[Guid,Object]] $allTestPaths = $null
    )

    $me = $MyInvocation.MyCommand
    if($null -eq $parentPath)
    {
        $parentPath = ""
    } `
    else
    {
        # Nothing
    }

    if($null -eq $allTestPaths)
    {
        $allTestPaths = [System.Collections.Generic.SortedDictionary[Guid,Object]]::new()
    } `
    else
    {
        # Nothing
    }

    $a = 0
    $keys = @($fromNode.Keys)
    while($a -lt $keys.Length)
    {
        $pathToTest = $parentPath + $fromNode[$keys[$a]].ShortenedName

        if($fromNode[$keys[$a]].SourceObjects.Count -gt 0)
        {
            $b = 0
            while($b -lt $fromNode[$keys[$a]].SourceObjects.Count)
            {
                $paths = @($pathToTest -split "/")

                $d = NewViablePathsNode
                $d.Paths = $paths
                $d.SourceObject = $fromNode[$keys[$a]].SourceObjects[$b]

                # If this source object is a document, then check to see if there is a flatset that references it.
                $d.IsFlatSetReference = ($fromNode[$keys[$a]].SourceObjects[$b].MyType -eq "ProjectWiseDocument") -and ($fromNode[$keys[$a]].SourceObjects[$b].IsFlatSetReference)    # If this document is referenced by a flatset, then we need version information for it.

                $paths[0] = TranslateToDocLibName -name $paths[0]

                if($fromNode[$keys[$a]].SourceObjects[$b].MyType -eq "ProjectWiseDocument")
                {
                    $d.SPData.FolderName = $paths[0..($paths.Length - 2)].ForEach({ $_.Trim() }) -join "/"
                    $d.SPData.FileName = $paths[-1].Trim()
                } `
                else
                {
                    $d.SPData.FolderName = $paths.ForEach({ $_.Trim() }) -join "/"
                }

                $allTestPaths.Add($fromNode[$keys[$a]].SourceObjects[$b].DocumentGUID, $d)

                $b++
            }
        } `
        else
        {
            # Nothing....right???
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            $null = BuildViablePathsDictionary -pwData $pwData -fromNode $fromNode[$keys[$a]].Children -parentPath ($pathToTest + "/") -allTestPaths $allTestPaths
        } `
        else
        {
            # Nothing, no child nodes to follow...
        }
        $a++
    }

    return @( , $allTestPaths)
}

function LoadViablePaths_20251125_1729
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $savePath
    )

    $me = $MyInvocation.MyCommand
    $viablePathsDict2 = [System.Collections.Generic.SortedDictionary[[Guid],[Object]]]::new()

    try
    {
        $jsonContent = Get-Content -Path $savePath -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to read JSON data from {0} in {1}." -f @($savePath, $me.Name))
    }

    try
    {
        $data = $jsonContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to convert JSON data from {0} into an object in {1}." -f @($savePath, $me.Name))
    }

    if(-not $Script:HaveError)
    {
        $a = 0
        while($a -lt $data.Length)
        {
            $d = NewViablePathsNode

            $d.Paths = $data[$a].Paths
            $d.SourceObject = $data[$a].SourceObject
            $d.CopyOutPath = $data[$a].CopyOutPath
            $d.SPData.FolderName = $data[$a].SPData.FolderName
            $d.SPData.FileName = $data[$a].SPData.FileName
            $d.SPData.SPFile.ServerRelativeURL = $data[$a].SPData.SPFile.ServerRelativeURL
            $d.SPData.SPFile.VersionLabel = $data[$a].SPData.SPFile.VersionLabel
            $d.SPData.Processed = $data[$a].SPData.Processed
            $d.SPData.WhenUploaded = $data[$a].SPData.WhenUploaded
            $d.SPData.DocVersionToLink = $null     # Can't initialize this, or later in the code, it won't know to build the list
            $d.IsFlatSetReference = $data[$a].IsFlatSetReference

            if($data[$a].SPData.DocVersionToLink.Length -gt 0)
            {
                # It's safe to initialize this here, because we actually have stuff to add to it.
                $d.SPData.DocVersionToLink = [System.Collections.Generic.SortedDictionary[String, String]]::new()
                $data[$a].SPData.DocVersionToLink.ForEach({
                    $d.SPData.DocVersionToLink.Add($_.DocumentVersion, $_.Link)
                })
            } `
            else
            {
                # Nothing, no document versions to links...
            }

            $data[$a].SPData.DocSetLinksCreated.ForEach({
                $d.SPData.DocSetLinksCreated.Add($_)
            })

            $viablePathsDict2.Add($data[$a].GUID, $d)
            $a++
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    return @(, $viablePathsDict2)
}

function CreateSharePointProjectSubFolders_20251125_2000
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    # Get all the folder objects from viablePathsDict that have not been created and are either for another project, or are more than 2 levels deep.  The first 2 levels are the "Active Projects" | "Inactive Projects" and the project folder
    #    The project folder is created separately so it's properties can be set.
    #    $folderObjectsToCreate = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseFolder]) -and (-not $_.SPData.Processed) } | Sort-Object @{E={ ($_.Paths -join "/") }})
    $folderObjects = @(@($viablePathsDict.Values).Where({ ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and (($_.Paths.Length -gt 2) -or (($_.Paths.Length -eq 2) -and ($_.Paths[0..1] -join "\") -ne $pwData.PWFolder.FullPath)) }) | Sort-Object @{E={ ($_.Paths -join "/") }} )

    LogInfo ("{0} Folder objects" -f @($folderObjects.Length))
    $folderObjectsToCreate = @($folderObjects | Where-Object { (-not $_.SPData.Processed) })
    LogInfo ("{0} Folders to create" -f @($folderObjectsToCreate.Length))
    $foldersCreated = 0
    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $folderObjectsToCreate.Length))
    {
        $fo = $folderObjectsToCreate[$a]

        $libInfo = ($null -ne $fo.LibInfo) ? $fo.LibInfo : (GetLibraryDataFromObj -obj2Upload $fo -CreateMissingLibrary)
        if($null -ne $libInfo)
        {
            if($libInfo.SPFolderPathPieces.Length -eq 2)
            {
                # This is a project folder for another project.
                $null = CreateSharePointProjectFolder -fo $fo
            } `
            else
            {
                # Not a project folder...
                $folderPieces = [System.Collections.Generic.List[String]]::new()
                $v = 1
                while($v -lt $libInfo.SPFolderPathPieces.Length)
                {
                    $folderPieces.Add($libInfo.SPFolderPathPieces[$v])
                    $v++
                }

                if(-not $Script:HaveError)
                {
                    $parentFolder = "{0}/{1}" -f @($libInfo.LibURL, ($folderPieces[0..($folderPieces.Count - 2)] -join "/"))
                    $folderName = $folderPieces[-1]
                    $description = [String]::Empty
                    if((-not [String]::IsNullOrEmpty($fo.SourceObject.Description)) -and ($fo.SourceObject.Description -ne $fo.SourceObject.Name))
                    {
                        $description = $fo.SourceObject.Description
                    } `
                    else
                    {
                        # Don't use a dumb description
                    }

                    $pc = [float] $a / [float] $folderObjectsToCreate.Length
                    Write-Progress -Id 1 -Activity ("Creating SharePoint folder {0} : {1} of {2}" -f @($folderPieces[-1], ($a + 1), $folderObjectsToCreate.Length)) -Status ("{0,7:P} Complete" -f @($pc)) -PercentComplete ($pc * 100)
                    LogInfo ("Creating folder {0}/{1}" -f @($parentFolder, $folderName))
                    $spFolder = AddSharePointFolder -parentFolder $parentFolder -newFolderName $folderName -description $description -originalName $fo.Paths[-1]

                    if(-not $Script:HaveError)
                    {
                        if($null -ne $spFolder)
                        {
                            $foldersCreated++
                            $fo.SPData.SPFile.ServerRelativeURL = $spFolder.ServerRelativeURL
                            $fo.SPData.Processed = $true
                            $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
                        } `
                        else
                        {
                            LogWarning ("Missing Sharepoint folder object for {0}/{1} in {2}." -f @($parentFolder, $folderName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    # Nothing, already logged an error
                }
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }

        $a++
    }
    Write-Progress -Id 1 -Completed
    LogInfo ("Created {0} folders" -f @($foldersCreated))
}

function ExportPW2SP_20251126_1748
{



    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $projectFolderObjs.Length))
    {
        # No longer adding folders to "Active Projects" or "Inactive Projects"... now they go to their own document library


        $pathPieces = $projectFolderObjs[$a].SPData.FolderName -split "/"
        if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($pathPieces[0]))
        {
            # If we have to create the document library, then there are no pre-existing folders and files.
            CreateNewDocumentLibrary -spDocLibName $pathPieces[0]
        } `
        else
        {
            $lib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$pathPieces[0]]
            $libPathPieces = $lib.RootFolder.ServerRelativeUrl -split "/"
            $folderPath = "{0}/{1}" -f @($libPathPieces[-1], $pathPieces[-1])

            ShowProgress -progressID 1 -activity "Checking existing folders and files" -counter $a -counterMax $projectFolderObjs.Length -statusSuffix $folderPath

            # Build a dictionary of sourceobjects to process by sourceobject type.
            #   Within each dictionary, create a sorted dictionary of url to sourceobject.
            # The point of this dictionary is to make searching for existing SharePoint objects faster.
            $pwObjDict = [System.Collections.Generic.SortedDictionary[String, Object]]::new()
            $keys = @($viablePathsDict.Keys)
            $processedKeys = 0
            $keys.ForEach({
                ShowProgress -progressID 2 -activity "Building viable path lookup dictionary" -counter $processedKeys -counterMax $keys.Length
                $processedKeys++

                $vp = $viablePathsDict[$_]

                # Let's reset the Processed to $false, and let the loop below change it back to $true based on what we
                #    actually find in SharePoint.
                $vp.SPData.Processed = $false

                $libInfo = ($null -ne $vp.LibInfo) ? $vp.LibInfo : (GetLibraryDataFromObj -obj2Upload $vp)

                if($null -ne $libInfo)
                {
                    # Replace the leading folder name with the document library's folder name.
                    $folderPieces = $vp.SPData.FolderName -split "/"
                    $folderPieces[0] = $libInfo.LibraryFolderName
                    $folderName = $folderPieces -join "/"

                    if(-not $pwObjDict.ContainsKey($vp.SourceObject.MyType))
                    {
                        $typeDict = [System.Collections.Generic.SortedDictionary[String, System.Collections.Generic.List[Object]]]::new()
                        $pwObjDict.Add($vp.SourceObject.MyType, $typeDict)
                    } `
                    else
                    {
                        $typeDict = $pwObjDict[$vp.SourceObject.MyType]
                    }

                    if($vp.SourceObject.MyType -eq "ProjectWiseDocument")
                    {
                        $url = "/sites/{0}/{1}/{2}" -f @($Script:connData.ConnectionInformation.SharePointSiteName, $folderName, $vp.SPData.FileName)
                    } `
                    else
                    {
                        $url = "/sites/{0}/{1}" -f @($Script:connData.ConnectionInformation.SharePointSiteName, $folderName)
                    }

                    if(-not $typeDict.ContainsKey($url))
                    {
                        $newList = [System.Collections.Generic.List[Object]]::new()
                        $typeDict.Add($url, $newList)
                    } `
                    else
                    {
                        # No dups please.
                    }

                    $typeDict[$url].Add($vp)
                } `
                else
                {
                    # Already logged an error in GetLibraryDataFromObj
                    break
                }
            })
            ShowProgress -progressID 2 -complete

            try
            {
                # Get all the folders and files SharePoint knows about under this project.
                LogInfo ("Retrieving existing folders and files from SharePoint.  This could take some time....")
                $fnf = Get-PnPFolderItem -FolderSiteRelativeUrl $folderPath -Recursive -ErrorAction Stop
                if($null -ne $fnf)
                {
                    $b = 0
                    while((-not $Script:HaveError) -and ($b -lt $fnf.Length))
                    {
                        ShowProgress -progressID 2 -activity "Checking folder item" -counter $b -counterMax $fnf.Length

                        $f = $fnf[$b]
                        $existingObjs = $null
                        if($f -is [Microsoft.SharePoint.Client.File])
                        {
                            if($pwObjDict.ContainsKey("ProjectWiseDocument"))
                            {
                                if($pwObjDict["ProjectWiseDocument"].ContainsKey($f.ServerRelativeURL))
                                {
                                    $existingObjs = $pwObjDict["ProjectWiseDocument"][$f.ServerRelativeURL].Where({ $_.SourceObject.FileSize -eq $f.Length })
                                } `
                                else
                                {
                                    # Nothing, doesn't exist.... WHAT?  How is there a SharePoint document that ProjectWise doesn't have....
                                    LogInfo ("Extra SharePoint file: [{0}]" -f @($f.ServerRelativeURL))
                                }
                            } `
                            else
                            {
                                LogError ("No ProjectDocuments in viable paths lookup dictionary!!!")
                            }
                        } `
                        elseif($f -is [Microsoft.SharePoint.Client.Folder])
                        {
                            if($pwObjDict.ContainsKey("ProjectWiseFolder"))
                            {
                                if($pwObjDict["ProjectWiseFolder"].ContainsKey($f.ServerRelativeURL))
                                {
                                    $existingObjs = $pwObjDict["ProjectWiseFolder"][$f.ServerRelativeURL]
                                } `
                                else
                                {
                                    # Nothing, doesn't exist.... WHAT?  How is there a SharePoint document that ProjectWise doesn't have....
                                    LogInfo ("Extra SharePoint file: [{0}]" -f @($f.ServerRelativeURL))
                                }
                            } `
                            else
                            {
                                LogError ("No ProjectFolders in viable paths lookup dictionary!!!")
                            }
                        }
                        else
                        {
                            LogWarning ("Unknown object type [{0}] while checking existing folders and files." -f @($f.TypedObject.ToString()))
                        }

                        if($null -ne $existingObjs)
                        {
                            $existingObjs | ForEach-Object {
                                $_.SPData.Processed = $true
                                $_.SPData.WhenUploaded = $f.TimeCreated.ToString()
                                $_.SPData.SPFile.ServerRelativeURL = $f.ServerRelativeUrl
                            }
                        } `
                        else
                        {
                            LogWarning ("Extra SharePoint object [{0}] while checking existing folders and files." -f @($f.ServerRelativeURL))
                        }

                        $b++
                    }
                    ShowProgress -progressID 2 -complete
                } `
                else
                {
                    # Nothing there....
                }
            }
            catch
            {
                $Error.Clear()
                # This is fine, just nothing there....
            }
        }
        $a++
    }

    # make sure we have a viable path for the main project folder
    if($viablePathsDict.ContainsKey($pwData.PWFolder.DocumentGUID))
    {
        $fo = $viablePathsDict[$pwData.PWFolder.DocumentGUID]

        # Have we already created the project folder in SharePoint?
        if(-not $fo.SPData.Processed)
        {
            $null = CreateSharePointProjectFolder -fo $fo
            if(-not $Script:HaveError)
            {
                $fo.SPData.Processed = $true
                $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
            }
        } `
        else
        {
            # Nothing, the project folder should already exist.
        }
    } `
    else
    {
        LogError ("Missing viable path object for project folder {0} in {1}." -f @($pwData.PWFolder.FullPath))
    }

    if(-not $Script:HaveError)
    {
        CreateSharePointSubFolders -pwData $pwData -viablePathsDict $viablePathsDict
    } `
    else
    {
        # Nothing, already displayed an error.
    }

    # Where we export $viablePathsDict to, to track progress.
    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath

    $sw.Reset()
    $sw.Start()
    if(-not $Script:HaveError)
    {
        $documentsToUpload = [System.Collections.Generic.List[System.Object]]::new()
        $allDocuments = [System.Collections.Generic.List[System.Object]]::new()
        $flatSets = [System.Collections.Generic.List[System.Object]]::new()
        $flatSetReferences = [System.Collections.Generic.List[System.Object]]::new()

        # Only get:
        #    Objects which are more than 2 levels deep  $_.Paths.Length -eq 1 = Active/Inactive projects (the document library), $_.Paths.Length -eq 2 = project folder.
        #    ProjectWise Documents
        #  Sorted by FullPath and VersionSequence
        #    This should ensure documents with lower VersionSequence numbers are uploaded first, that way, when the next version is uploaded over the top of the existing document
        #       the higher VersionSequence becomes the current version.
        @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} ).Foreach({
            if(-not $_.SourceObject.IsSet)
            {
                $allDocuments.Add($_)
            } `
            else
            {
                $flatSets.Add($_)
            }

            if($_.IsFlatSetReference)
            {
                $flatSetReferences.Add($_)
            } `
            else
            {
                # Nothing...
            }

            if(($Script:reprocess.IsPresent) -or (-not $_.SPData.Processed))
            {
                $documentsToUpload.Add($_)
            } `
            else
            {
                # Nothing, not uploading this document
            }
        })

        $totalUploadSize = ($documentsToUpload | Measure-Object -Sum { $_.SourceObject.FileSize }).Sum
        $totalSizeUploaded = 0
        $documentsUploaded = 0
        $uploadSkipped = 0
        LogInfo ("Total Documents: {0}" -f @($allDocuments.Count))
        LogInfo ("Total FlatSets: {0}" -f @($flatSets.Count))
        LogInfo ("Documents to upload: {0}" -f @($documentsToUpload.Count))
        LogInfo ("Flatset referenced documents (links to create): {0}" -f @($flatSetReferences.Count))

        $a = 0
        $numDocToUpload = $documentsToUpload.Count
        while((-not $Script:HaveError) -and ($documentsToUpload.Count -gt 0))
        {
            $documentVersionsToUpload = @($documentsToUpload | Where-Object { $_.SourceObject.FullPath -eq $documentsToUpload[0].SourceObject.FullPath } | Sort-Object @{E={ $_.SourceObject.VersionSequence }})

<#    FOR DEBUGGING... REMOVE documents from documents to upload until I find what I want...

$documentsToUpload.Count
$documentVersionsToUpload.Length

$documentVersionsToUpload.ForEach({
    $idx = $documentsToUpload.IndexOf($_)
    if($idx -ge 0)
    {
        $documentsToUpload.RemoveAt($idx)
    }
})

#>

            $pc = [float] ($totalSizeUploaded) / [float] ($totalUploadSize)
            $status = "{0} of {1} | {2,7:P2} Complete" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc)
            if($totalSizeUploaded -gt 0)
            {
                $elapsedTicks = $sw.ElapsedTicks
                $ticksPerItem = $elapsedTicks / $totalSizeUploaded
                $totalETATicks = $ticksPerItem * ($totalUploadSize)
                $remainingETATicks = $totalETATicks - $elapsedTicks
                $etaTS = [TimeSpan]::new($remainingETATicks)
                $etaDT = [DateTime]::Now.Add($etaTS)

                $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $totalSizeUploaded), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString("dd\.hh\:mm\:ss"), $etaTS.ToString("dd\.hh\:mm\:ss"), $etaDT.ToString())
            }
            $fpStr = $documentsToUpload[0].SourceObject.FullPath
            if($fpStr.Length -gt $MAXFPSTRLEN)
            {
                $startIdx = $fpStr.Length - $MAXFPSTRLEN
                $fpStr = "...{0}" -f @($fpStr.SubString($startIdx))
            }
            $activity = $Script:uploadProgressFMTStr -f @(($documentsUploaded + $uploadSkipped), $numDocToUpload, $documentsToUpload[0].SourceObject.FullPath, (Format-StorageNumber $documentsToUpload[0].SourceObject.FileSize))

            if($documentVersionsToUpload.Length -gt 0)
            {
                # The last object in $documentVersionsToUpload is the current ProjectWise document (based on .VersionSequence)
                #   After CheckDocumentVersions, we either upload all of $documentVersionsToUpload or none of them...
                $spDocVer = CheckDocumentVersions -documentsToCheck $documentVersionsToUpload

                if(-not $Script:HaveError)
                {
                    if($null -ne $spDocVer)
                    {
                        # Woot!  All versions are intact... Nothing to upload...
                    } `
                    else
                    {
                        # Ah crap... guess we uploading...
                        UploadDocumentsToSharePoint -pwData $pwData -documentsToUpdate $documentVersionsToUpload
                    }


                    if(-not $Script:HaveError)
                    {
                        $documentVersionsToUpload.ForEach({
                            # Do this whether we upload or not... still counts towards the total.
                            $totalSizeUploaded += $_.SourceObject.FileSize

                            # Also remove the files we skip/upload from the list of documents we need to process...
                            $uploadedDocIdx = $documentsToUpload.IndexOf($docsToUpload[$a])
                            if($uploadedDocIdx -gt -1)
                            {
                                $documentsToUpload.RemoveAt($uploadedDocIdx)
                            } `
                            else
                            {
                                LogError ("Failed to remove uploaded document {0}:{1} from documents to upload in {2}." -f @($documentVersionsToUpload[$b].SourceObject.DocumentGUID, $documentVersionsToUpload[$b].SourceObject.FullPath, $me.Name))
                            }
                        })
                    } `
                    else
                    {
                        # Nothing, already logged an error
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Missing document versions to uplad for {0}:{1} in {2}." -f @($documentsToUpload[0].SourceObject.DocumentGUID, $documentsToUpload[0].SourceObject.FullPath, $me.Name))
            }
            $a++
        }
        LogInfo ("Documents uploaded: {0}" -f @($documentsUploaded))
        LogInfo ("Documents skipped: {0}" -f @($uploadSkipped))




        <#

            Upload ... err create document sets
                1) Create the docment set in the appropriate folder
                2) Add links to the document set for each document reference.

        #>

        # Need to look at all flatsets, not just the ones with .SPUpload.Processed -eq $false, since we also need to see if all the flatset reference have been uploaded.
        $fsToProcess =  @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and ($_.SourceObject.IsSet) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} )
        LogInfo ("Processing {0} Flatsets" -f @($fsToProcess.Length))

        # Just some admin stuff...
        $totalProcesses = 0
        $fsToProcess.Foreach({
            $totalProcesses++       # Create the document set.
            if($null -ne $_.SourceObject.FlatSetReferences)
            {
                $totalProcesses += $_.SourceObject.FlatSetReferences.Count   # Create each of the links
            } `
            else
            {
                LogError ("Missing PW FlatSet references for {0}:{1} in {2}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SourceObject.FullPath, $me.Name))
            }
        })
        $processesCompleted = 0

        LogInfo ("`tReferenced documents: {0}" -f @(($totalProcesses - $fsToProcess.Length)))
        if(-not $Script:HaveError)
        {
            # Reset some admin stuff..
            $sw.Restart()

            $docSetsCreated = 0
            # Next need to create all the document sets and add the document links.
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $fsToProcess.Length))
            {
                $pc = [float] $processesCompleted / [float] $totalProcesses
                ShowProgress -progressID 1 -activity "Processing flat sets" -counter $a -counterMax $fsToProcess.Length

                $libInfo = ($null -ne $fsToProcess[$a].LibInfo) ? $fsToProcess[$a].LibInfo : (GetLibraryDataFromObj -obj2Upload $fsToProcess[$a] -CreateMissingLibrary)
                if($null -ne $libInfo)
                {
                    # If we don't think we've processed this document set, then proceed like we need to create it.
                    $createDocumentSet = -not $fsToProcess[$a].SPData.Processed
                    if(-not $fsToProcess[$a].SPData.Processed)
                    {
                        $createDocumentSet = $true

                        try
                        {
                            $existingDS = Get-PnPListItem -List $libInfo.Library -FolderServerRelativeUrl $libInfo.FolderURL -IncludeContentType -ErrorAction Stop | Where-Object { ($_.ContentType.Name -eq "Document Set") -and ($_.Title -eq $fsToProcess[$a].SPData.Name) }
                            if($null -ne $existingDS)
                            {
                                $Script:reportData.DocumentSets.PreExisting++
                                $createDocumentSet = $false    # No need to create what already exists.
                                $ds = $existingDS.FieldValues["FileRef"]
                                $fsToProcess[$a].SPData.Processed = $true
                                [DateTime] $dt = [DateTime]::Now    # Just use the current date and time unless we get a value for when it was created.
                                if(-not [String]::IsNullOrEmpty($existingDS.FieldValues["Created_x0020_Date"]))
                                {
                                    # Capture the return value... it really doesn't matter, either way we'll have a useable value in $dt.
                                    $null = [DateTime]::TryParse($existingDS.FieldValues["Created_x0020_Date"], [ref] $dt)
                                } `
                                else
                                {
                                    # Nothing, just the default...
                                }
                                $fsToProcess[$a].SPData.WhenUploaded = $dt.ToString()
                            } `
                            else
                            {
                                # Nothing, there is no document set...
                            }
                        }
                        catch
                        {
                            # No big deal, the docment set does not exist.
                            $Error.Clear()
                        }

                        if($createDocumentSet)
                        {
                            LogInfo ("Creating document set {0} in {1}" -f @($fsToProcess[$a].SPData.FileName, $libInfo.FolderURL))
                            try
                            {
                                $ds = Add-PnPDocumentSet -List $libInfo.Library -ContentType "Document Set" -Name $fsToProcess[$a].SPData.FileName -Folder $libInfo.FolderURL -ErrorAction Stop
                                if(-not [String]::IsNullOrEmpty($ds))
                                {
                                    $Script:reportData.DocumentSets.Created++
                                    $docSetsCreated++
                                    $fsToProcess[$a].SPData.SPFile.ServerRelativeURL = $ds
                                    $fsToProcess[$a].SPData.Processed = $true    # We created the document set.
                                    $fsToProcess[$a].SPData.WhenUploaded = [DateTime]::Now.ToString()
                                } `
                                else
                                {
                                    LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0} to {1}/{2} in {3}." -f @($fsToProcess[$a].SPData.FileName, $libInfo.FolderURL, $fsToProcess[$a].SPData.FileName, $me.Name))
                                }
                            }
                            catch
                            {
                                LogError ("Failed to add document set: {0}:{1} to {2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SPData.FileName, $libInfo.FolderURL, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, document set already exists.
                        }
                    } `
                    else
                    {
                        # Need to populate $ds so it's available below since we didn't create a new document set.
                        $ds = $fsToProcess[$a].SPData.SPFile.ServerRelativeURL
                    }

                    if(-not $Script:HaveError)
                    {
                        if(-not [String]::IsNullOrEmpty($ds))
                        {
                            # Now, create all the document links in the document set.
                            LogInfo ("Creating {0} reference link for document set {1}/{2}" -f @($fsToProcess[$a].SourceObject.FlatSetReferences.Count, $libInfo.FolderURL, $fsToProcess[$a].SPData.FileName))
                            $linksCreated = 0
                            $b = 0
                            while((-not $Script:HaveError) -and ($b -lt $fsToProcess[$a].SourceObject.FlatSetReferences.Count))
                            {
                                ShowProgress -progressID 2 -activity "Adding links to document set" -counter $b -counterMax $fsToProcess[$a].FlatSetReferences.Count

                                if($viablePathsDict.ContainsKey($fsToProcess[$a].SourceObject.FlatSetReferences[$b]))
                                {
                                    $referencedDoc = $viablePathsDict[$fsToProcess[$a].SourceObject.FlatSetReferences[$b]]

                                    # Have we already created a link for this flatset??    SORRY, only 1 link per flatset....
                                    if(-not $referencedDoc.SPData.DocSetLinksCreated.Contains($fsToProcess[$a].SourceObject.FlatSetReferences[$b]))
                                    {
                                        # Need to determine if the referenced document points to the current version of a file, or not.

                                        # Get all the versions of the referenced document.  Sorted by FullPath and VersionSequence so the current version is the last.
                                        $documentVersions = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and ($_.SourceObject.FullPath -eq $referencedDoc.SourceObject.FullPath) } | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }})

                                        if($documentVersions.Length -gt 0)
                                        {
                                            # The last document in the array is always the current document since it's sorted by .FullPath and .VersionSequence.
                                            $currentDocument = $documentVersions[-1]

                                            # The current version will be the last file in the sorted array (by fullpath and versionsequence)...So here, we need to get the index
                                            #    of the version we are needing to check.
                                            # NOTE: We are not looking for the index of the current document, that is index -1, we are looking for the index of the version of the
                                            #    document referenced by the flatset.
                                            $versionIdx = $documentVersions.IndexOf( ($documentVersions | Where-Object {$_.SourceObject.DocumentGUID -eq $fsToProcess[$a].SourceObject.FlatSetReferences[$b]}))

                                            if($versionIdx -gt -1)
                                            {
                                                # From here, the point is to end up with a viable value for $docLink....
                                                $docLink = [String]::Empty

                                                # If the version index is the last item in the array, then we are safe to use the current file URL...
                                                $isCurrentVersion = ($versionIdx -eq ($documentVersions.Length - 1))
                                                if($isCurrentVersion)
                                                {
                                                    if(-not [String]::IsNullOrEmpty($referencedDoc.SPData.SPFile.ServerRelativeURL))
                                                    {
                                                        $docLink = $referencedDoc.SPData.SPFile.ServerRelativeURL
                                                    } `
                                                    else
                                                    {
                                                        LogError ("No SharePoint document relative URL for {0} in {1}." -f @($fsToProcess[$a].SourceObject.FullPath, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    # Not the current file, so we have to get a link to a previous version of the file...

                                                    # If .DocVersionToLink has not been built, then build it.
                                                    if($null -eq $currentDocument.SPData.DocVersionToLink)
                                                    {
                                                        GetSPDocumentVersionLinks -currentVersionOfDocument $currentDocument
                                                    } `
                                                    else
                                                    {
                                                        # Already have version info for this file...
                                                    }

                                                    $versionToFind = $referencedDoc.SourceObject.Version
                                                    if([String]::IsNullOrEmpty($versionToFind))
                                                    {
                                                        $versionToFind = "NoVersion"
                                                    } `
                                                    else
                                                    {
                                                        # Nothing.
                                                    }

                                                    if(-not $Script:HaveError)
                                                    {
                                                        if($null -ne $currentDocument.SPData.DocVersionToLink)
                                                        {
                                                            if($currentDocument.SPData.DocVersionToLink.ContainsKey($versionToFind))
                                                            {
                                                                $docLink = $currentDocument.SPData.DocVersionToLink[$versionToFind]
                                                            } `
                                                            else
                                                            {
                                                                LogError ("Missing document link for {0} Version {1} in {2}." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            LogError ("Missing document link for {0} Version {1} in {2}.  No document version links." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Already have version info for this file...
                                                    }
                                                }

                                                if(-not $Script:HaveError)
                                                {
                                                    if(-not [String]::IsNullOrEmpty($docLink))
                                                    {
                                                        if($isCurrentVersion)
                                                        {
                                                            $docLink = "{0}{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $docLink)
                                                        } `
                                                        else
                                                        {
                                                            $docLink = "{0}/sites/{1}/{2}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $Script:connData.ConnectionInformation.SharePointSiteName, $docLink)
                                                        }

                                                        $existingLink = $null
                                                        try
                                                        {
                                                            $existingLink = Get-PnPFile -Url $docLink -ErrorAction Stop
                                                        }
                                                        catch
                                                        {
                                                            # No worries, the link already exists.
                                                            $Script:reportData.DocumentLinks.PreExisting++
                                                            $Error.Clear()
                                                            $existingLink = $null
                                                        }

                                                        if($null -eq $existingLink)
                                                        {
                                                            # Create an internet shortcut to the proper document version and add it to the document set.
                                                            $linkContent = "[InternetShortcut]`nURL={0}" -f @($docLink)
                                                            $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))
                                                            $targetFolder = "{0}/{1}" -f @($libInfo.FolderURL, $fsToProcess[$a].SPData.FileName)
                                                            $linkName = "{0}.url" -f @($referencedDoc.SourceObject.Name)
                                                            $spDocFields = BuildDocumentProperties -obj2Upload $referencedDoc
                                                            if($null -ne $spDocFields)
                                                            {
                                                                $spDocFields.Add("_ShortcutUrl", $docLink)
                                                            } `
                                                            else
                                                            {
                                                                $spDocFields = @{ "_ShortcutUrl" = $docLink }
                                                            }

                                                            try
                                                            {
                                                                $null = Add-PnPFile -FileName $linkName -Folder $targetFolder -Stream $stream -Values $spDocFields -ErrorAction Stop
                                                                $linksCreated++
                                                                $Script:reportData.DocumentLinks.Created++
                                                            }
                                                            catch
                                                            {
                                                                LogError ("Failed to create document link {0} for document set {1} in {2}." -f @($docLink, $fsToProcess[$a].SPData.FileName, $me.Name))
                                                            }

                                                            if(-not $Script:HaveError)
                                                            {
                                                                # $referencedDoc refers to the referenced document, so all we need to do here is flag that we've created the link for it
                                                                #   Add the flatset's document GUID to the list to signal we created it.
                                                                $referencedDoc.SPData.DocSetLinksCreated.Add($fsToProcess[$a].SourceObject.DocumentGUID)
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, already displayed an error.
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, link already exists.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogError ("No document link available for {0} Version {1} in {2}.  docLink is empty." -f @($referencedDoc.SourceObject.FullPath, $versionToFind, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    # Nothing, already logged an error
                                                }
                                            } `
                                            else
                                            {
                                                LogError ("Unable to document index of {0}:{1} in {2}" -f @($referencedDoc.SourceObject.DocumentGUID, $referencedDoc.SourceObject.FullPath, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            LogError ("Unable to locate any versions of {0}:{1} in viable paths dictionary {2}." -f@($referencedDoc.SourceObject.DocumentGUID, $referencedDoc.SourceObject.FullPath, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, no need to create a duplicate link.
                                    }
                                } `
                                else
                                {
                                    LogError ("Missing viable path object for {0} in {1}." -f @($fsToProcess[$a].SourceObject.FlatSetReferences[$b], $me.Name))
                                }

                                $processesCompleted++
                                if(($processesCompleted % 10) -eq 0)
                                {
                                    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                                } `
                                else
                                {
                                    # Nothing
                                }
                                $b++
                            }
                            ShowProgress -progressID 2 -complete
                            LogInfo ("Created {0} links" -f @($linksCreated))
                        } `
                        else
                        {
                            LogError ("Null/empty string returned from Add-PnPDocumentSet adding document set {0}:{1}/{2} in {3}." -f @($fsToProcess[$a].SourceObject.DocumentGUID, $fsToProcess[$a].SourceObject.FullPath, $fsToProcess[$a].SPData.FileName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed an error.
                    }

                    $processesCompleted++
                    if(($processesCompleted % 10) -eq 0)
                    {
                        ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
                    } `
                    else
                    {
                        # Nothing
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }

                $a++
            }
            ShowProgress -progressID 1 -complete
            LogInfo ("Created {0} document sets" -f @($docSetCreated))
            $sw.Stop()
        } `
        else
        {
            # Nothing, already displayed an error.
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    # Save viablePathsDict one last time.
    ExportViablePathsStructure -viablePathsDict $viablePathsDict -savePath $viablePathsExportPath
}

# Later... let's just get the flat set dealt with first
function NewMyProjectWiseFolderFromFlatSet
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object] $fsDoc
    )

    $newNode = [PSCustomObject]@{
        MyType = "ProjectWiseFolder"
        FullPath = @($fsDoc.FullPath -split "\\").ForEach({ $_ -replace $Script:IlegalCharactersInFoldersAndFilesRegEx, "_" }) -join "\"
        DocumentGUID = [Guid]::NewGuid()
        StorageFolder = $fsDoc.StorageName
        Name = $fsDoc.Name
        CreateDateTime = $fsDoc.CreateDate
        UpdateDateTime = $fsDoc.FileUpdateDate
        Description = $fsDoc.Description
        FolderOwnerName = $fsDoc.DocumentUpdaterName
        FolderCreatorName = $fsDoc.DocumentCreatorName
        FolderUpdaterName = $fsDoc.DocumentUpdaterName
        ProjectProperties = $fsDoc.Attributes
    }

    $newNode.Name = ($newNode.FullPath -split "\\")[-1]

    return @(, $newNode)
}

function NewViablePathsNodeFromFlatSetNode
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object] $fsDocNode
    )

    $d = $null
    if($fsDocNode.SourceObject.IsSet)
    {
        $d = [PSCustomObject]@{
            GUID = $null      # Only used when exporting and importing viablePathsDict from file.
            Paths = $fsDocNode.Paths
            SourceObject = NewMyProjectWiseFolderFromFlatSet -fsDoc $fsDocNode.SourceObject
            CopyOutPath = [String]::Empty
            SPData = [PSCustomObject]@{
                FolderName = [String]::Empty
                FileName = [String]::Empty
                SPFile = [PSCustomObject]@{
                    ServerRelativeURL = $fsDocNode.SPData.SPFile.ServerRelativeURL
                    VersionLabel = $fsDocNode.SPData.SPFile.VersionLabel
                    VersionProperties = $fsDocNode.SPData.SPFile.VersionProperties
                    VersionLinks = $fsDocNode.SPData.SPFile.VersionLinks
                }
                Processed = $fsDocNode.SPData.Processed
                DocVersionToLink = $fsDocNode.SPData.DocVersionLink
                WhenUploaded = $fsDocNode.SPData.WhenUploaded
                DocSetLinksCreated = [System.Collections.Generic.List[Guid]]::new()    # This flags whether or not the document set reference link was added to the document set.
            }
            IsFlatSetReference = $fsDocNode.IsFlatSetReference  # If this document is referenced by a flatset, then we need version information for it.
        }
        $d.SPData.FolderName = @($fsDocNode.SPData.FolderName, $d.SourceObject.Name) -join "/"
        @($fsDocNode.SPData.DocSetLinksCreated).ForEach({ $d.SPData.DocSetLinksCreated.Add($_) })
    } `
    else
    {
        # Nothing, not a flat set node.
    }

    return @(, $d)
}


function frommain
{
                                                    if(-not $Script:HaveError)
                                                {
                                                    # Mark all the viable path objects which match document libraries as processed
                                                    @($viablePathsDict.Values).Where({ $_.Paths.Length -eq 1 }).ForEach({
                                                        $vp = $_
                                                        $tName = TranslateToDocLibName -name ($vp.Paths -join "\")
                                                        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($tName))
                                                        {
                                                            $vp.SPData.Processed = $true
                                                            Write-Host ("Marking {0} processed." -f @($vp.SourceObject.FullPath))
                                                        } `
                                                        else
                                                        {
                                                            # Nothing
                                                        }
                                                    })
                                                } `
                                                else
                                                {
                                                    # Nothing.
                                                }

                                                $nps = @(@($viablePathsDict.Values).Where({ -not $_.SPData.Processed }))
                                                LogInfo ("Unprocessed objects: {0}" -f @($nps.Length))
                                                if($nps.Length -le 10)
                                                {
                                                    $nps.ForEach({
                                                        LogInfo ("{0}" -f @($_.SourceObject.FullPath))
                                                    })
                                                }
}

# TODO: Check the functionality of this function... not sure I still need it.
function CreateNewDocumentLibrary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $spDocLibName
    )

    if($Script:DoDebugging)
    {
        LogInfo ("Creating new document library: {0}" -f @($spDocLibName))
    }

    $me = $MyInvocation.MyCommand
    try
    {
        $newDocLib = New-PnPList -Title $spDocLibName -Template "DocumentLibrary" -EnableVersioning -EnableContentTypes -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to create document library {0} in {1}." -f @($spDocLibName, $me.Name))
    }

    if(-not $Script:HaveError)
    {
        if($null -ne $newDocLib)
        {
            try
            {
                $newDocLib = Get-PnPList -Identity $spDocLibName -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to verify if new document library {0} was created in {1}." -f @($spDocLibName, $me.Name))
            }

            if(-not $Script:HaveError)
            {
                if($null -ne $newDocLib)
                {
                    if(-not $Script:HaveError)
                    {
                        $libInfo = [PSCustomObject]@{
                            Library = $newDocLib
                            RealName = @($newDocLib.RootFolder.ServerRelativeURL -split "/") | Select-Object -Last 1
                        }
                        $Script:connData.ConnectionInformation.SharePointDocumentLibraries.Add($newDocLib.Title, $libInfo)
                        GetLibraryDefinedFieldsList -libraryName $newDocLib.Title


                        # Need to add the key document fields.
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    LogError ("Null value returned verifying new document library {0} in {1}." -f @($spDocLibName, $me.Name))
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            LogError ("Null value returned creating new document library {0} in {1}." -f @($spDocLibName, $me.Name))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

$pp = @(GCI -Path "E:\PWProposals\Test" -Filter "*_PWData.json" -File)
$Script:projectName = "master"
$uniqueProjects = [System.Collections.Generic.List[String]]::new()
$Script:dupPWObjects = [System.Collections.Generic.List[Guid]]::new()
$pw = $null
$pw2 = $null
$a = 0
while($a -lt $pp.Length)
{
    if($pp[$a].Name -notmatch "master")
    {
        if($pp[$a].Name -match "([\d]{8}\-[\d]{6})")
        {
            $pName = $pp[$a].Name.Replace($Matches[1],"").Replace("__PWData.json","")
            $i = $uniqueProjects.BinarySearch($pName)
            if($i -lt 0)
            {
                $uniqueProjects.Insert(-bnot $i, $pName)

                if($null -eq $pw)
                {
                    $pw = LoadPWDataFromJSON -filePath $pp[$a].FullName
                } `
                else
                {
                    $pw2 = LoadPWDataFromJSON -filePath $pp[$a].FullName
                    MergePWData -pwData $pw -pwData2 $pw2
                }

                Write-Host ("Unique: {0}, A: {1}, PWObjects: {2}, Dups: {3}" -f @($uniqueProjects.Count, $a, $pw.ProjectWiseObjects.Count, $Script:dupPWObjects.Count))
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red ("Funky name: {0}" -f @($pp[$a].FullName))
        }
    }
    $a++
}

$vpKeys = @(($viablePathsDict.Keys).Where({$viablePathsDict[$_].SourceObject.MyType -eq "ProjectWiseDocument" }))
$notFound = [System.Collections.Generic.List[Guid]]::new()
$a = 0
$sw = [System.Diagnostics.StopWatch]::new()
$sw.Start()
while($a -lt $vpKeys.Length)
{
    $vp = $viablePathsDict[$vpKeys[$a]]

    if($vp.SourceObject.MyType -eq "ProjectWiseDocument")
    {
        $url = "Proposal Archives/" + $vp.SPData.FolderName + "/" + $vp.SPData.FileName
        #Write-Host -NoNewline ("Checking {0}) {1}..." -f @($a, $url))
        if(-not $vp.SourceObject.IsSet)
        {
            try
            {
                $file = Get-PnPFile -URL $url -ErrorAction Stop
            }
            catch
            {
                #Write-Host -ForegroundColor Red "not found"
                $i = $notFound.BinarySearch($vpKeys[$a])
                if($i -lt 0)
                {
                    $notFound.Insert(-bnot $i, $vpKeys[$a])
                }
            }
        } `
        else
        {
            try
            {
                $folder = Get-PnPFolder -URL $url -ErrorAction Stop
            }
            catch
            {
                #Write-Host -ForegroundColor Red "not found"
                $i = $notFound.BinarySearch($vpKeys[$a])
                if($i -lt 0)
                {
                    $notFound.Insert(-bnot $i, $vpKeys[$a])
                }
            }
        }
        $a++

        $statusSuffix = [String]::Empty
        if($a -gt 0)
        {
            $elapsedStr = $sw.Elapsed.ToString("d\.hh\:mm\:ss")
            $elapsedTicks = $sw.ElapsedTicks
            $ticksPerFile = $elapsedTicks / $a
            $totalETATicks = $ticksPerFile * $vpKeys.Length
            $remainingETATicks = $totalETATicks - $elapsedTicks
            $etaTS = [TimeSpan]::new($remainingETATicks)
            $etaDT = [DateTime]::Now.Add($etaTS)
            $statusSuffix = "Not found: {0} | Elapsed: {1} | Est Remaining: {2} | ETC: {3} | {4}" -f @($notFound.Count, $elapsedStr, $etaTS.ToString("d\.hh\:mm\:ss"), $etaDT.ToString("yyyyMMdd-HH:mm:ss"), $url)
        }
        ShowProgress -progressID 1 -activity "Checking files" -counter $a -counterMax $vpKeys.Length -statusSuffix $statusSuffix
    }
}
$sw.Stop()
ShowProgress -progressID 1 -activity "Checking files" -complete

$urlsNotFound = [System.Collections.Generic.List[Object]]::new()
$a = 0
while($a -lt $notFound.Count)
{
    $vp = $viablePathsDict[$notFound[$a].Guid]
    $url = "Proposal Archives/" + $vp.SPData.FolderName + "/" + $vp.SPData.FileName
    $d = [PSCustomObject]@{
        DocumentGUID = $notFound[$a].Guid
        URL = $url
        IsSet = $vp.SourceObject.IsSet
        IsFlatSetReference = $vp.SourceObject.IsFlatSetReference
    }
    $urlsNotFound.Add($d)
    $a++
}

$urlsNotFound | ConvertTo-CSV -Delimiter "`t" | scb

$uncheckedOrReUpload = @(
    @($notFound).ForEach({
        if($viablePathsDict.ContainsKey($_))
        {
            if(($viablePathsDict[$_].SourceObject.MyType -eq "ProjectWiseDocument") -and ($viablePathsDict[$_].Paths.Length -gt 0))
            {
                $viablePathsDict[$_]
            }
        }
    })
)


function GetProposalFlatSetReferences
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $propName
    )

    $retval = [System.Collections.Generic.SortedDictionary[Guid,Object]]::new()
    $pNameMatch = "Proposals - Archive\{0}\" -f @($propName)
    $proposalSets = @(@($pwData.ProjectWiseObjects.Values).Where({ ($_.FullPath.StartsWith($pNameMatch)) -and ($_.IsSet) }))
    $proposalSets.ForEach({
        @($_.FlatSetReferences).ForEach({
            if($pwData.ProjectWiseObjects.ContainsKey($_))
            {
                if(-not $retval.ContainsKey($_))
                {
                    $retval.Add($_, $pwData.ProjectWiseObjects[$_])
                } `
                else
                {
                    # Nothing, no dupes
                }
            } `
            else
            {
                Write-Host -ForegroundColor Red ("Missing ProjectWiseObject for GUID: {0}" -f @($_))
            }
        })
    })

    return @( ,$retval)
}

function GetProposalFlatSetReferenceSources
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [Guid] $docGuid
    )

    $retval = @(@($viablePathsDict.Values).Where({ $_.SourceObject.FlatSetReferences -contains $docGuid }))

    return @( ,$retval)
}

<#
    Make a function to get a link for a documentversion of a projectwisedocument.
    If I have this, then I should be able to easily build a "flatset" reference link...

    Basically, $t = GetSPDocumentVersions -docUrl "xyz"

    $verData = $t.SPDocument.Versions | Where-Object { $_.FieldValues["DocumentVersion"] -eq "A" } | Select-Object -First 1
#>

$pathKeys = @($Script:viablePathsLookupDict.Keys)
$pathToUpload = $pathKeys[$a]

$uncheckedOrReUpload = @($viablePathsDict.Values).Where({ ($_.Paths.Length -gt 0) -and (($_.SourceObject.DocumentGUID -notin $checked.CheckedGUIDs) -or ($_.SourceObject.DocumentGUID -in $checked.ReuploadGUIDs)) -and (-not $_.SPData.Verified)})
$allFilesToUpload = $uncheckedOrReUpload.Where({ ($_.SourceObject.MyType -eq "ProjectWiseDocument") })
$stdFilesToUpload = @($allFilesToUpload.Where({ -not $_.SourceObject.IsSet }))
$documentsToUpload = @($stdFilesToUpload.Where({ ($_.Paths -join "/") -eq $pathToUpload }) | Sort-Object @{ E={ $_.SourceObject.VersionSequence } })


$guidStr = "255f0f9b-51ea-4eff-89c8-83a6ccf2dec6"
& $scriptBlock

$scriptBlock = {
    if($viablePathsDict.ContainsKey($guidStr))
    {
        $vp = $viablePathsDict[$guidStr]
        if($null -ne $vp)
        {
            $pathToUpload = $vp.Paths -join "/"
            $documentsToUpload = @($viablePathsDict.Values).Where({ ($_.Paths -join "/") -eq $pathToUpload }) | Sort-Object @{ E={ $_.SourceObject.VersionSequence } }

            if($documentsToUpload.Length -gt 0)
            {
                UploadDocumentsToSharePoint -pwData $pwData -docsToUpload $documentsToUpload  # $docsToUpload = $documentsToUpload
            }
        }
    }
}





$flatSets = @(@($viablePathsDict.Values).Where( { $_.SourceObject.IsSet } ))
$brokenFlatSets = [System.Collections.Generic.List[Object]]::new()

$referencesToCheck = 0
$referencesChecked = 0
$flatSets.ForEach({ $referencesToCheck += $_.SourceObject.FlatSetReferences.Count })

$sw = [System.Diagnostics.StopWatch]::new()
$sw.Start()

$a = 0
while($a -lt $flatSets.Length)
{
    $fs = $flatSets[$a]
    $fsPath = $fs.Paths -join "/"
    $fsRefs = [System.Collections.Generic.List[Object]]::new()
    @($fs.SourceObject.FlatSetReferences).ForEach({
        $fsRefs.Add($viablePathsDict[$_])
    })


    $b = 0
    while($b -lt $fsRefs.Count)
    {
        $url = "{0}/{1}.url" -f @(($fs.Paths -join "/"), $fsRefs[$b].SPData.FileName)
        $d = $null

        try
        {
            $matchingLine = [String]::Empty
            $file = Get-PnPFile -Url $url -AsString -ErrorAction Stop
            $contentLines = @($file -split "`n")
            $matchingLine = @($contentLines -match "^URL=(.*)$") | Select-Object -First 1
            if($matchingLine -match "^URL=(.*)$")
            {
                $linkURL = $Matches[1]
                try
                {
                    $file = Get-PnPFile -Url $linkURL -ErrorAction Stop
                }
                catch
                {
                    $d = [PSCustomObject]@{
                        FlatSet = $fsPath
                        FlatSetGUID = $fs.SourceObject.DocumentGUID
                        FlatSetURL = $url
                        MissingReferenceGUID = $fsRefs[$b].SourceObject.DocumentGUID
                        MissingReferenceURL = $linkURL
                        Issue = "Missing flatset original reference file"
                    }
                }
            } `
            else
            {
                $d = [PSCustomObject]@{
                    FlatSet = $fsPath
                    FlatSetGUID = $fs.SourceObject.DocumentGUID
                    FlatSetURL = $url
                    MissingReferenceGUID = $fsRefs[$b].SourceObject.DocumentGUID
                    MissingReferenceURL = $linkURL
                    Issue = "Missing URL = '' in file"
                }
            }
        }
        catch
        {
            $d = [PSCustomObject]@{
                FlatSet = $fsPath
                FlatSetGUID = $fs.SourceObject.DocumentGUID
                FlatSetURL = $url
                MissingReferenceGUID = $fsRefs[$b].SourceObject.DocumentGUID
                MissingReferenceURL = $linkURL
                Issue = "Missing flatset reference URL"
            }
        }

        if($null -ne $d)
        {
            $brokenFlatSets.Add($d)
            $brokenFlatSets | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | scb
        }

        $b++

        $referencesChecked++

        $statusSuffix = [String]::Empty
        $elapsedStr = $sw.Elapsed.ToString("d\.hh\:mm\:ss")
        $elapsedTicks = $sw.ElapsedTicks
        $ticksPerFile = $elapsedTicks / $referencesChecked
        $totalETATicks = $ticksPerFile * $referencesToCheck
        $remainingETATicks = $totalETATicks - $elapsedTicks
        $etaTS = [TimeSpan]::new($remainingETATicks)
        $etaDT = [DateTime]::Now.Add($etaTS)
        $statusSuffix = "Issues: {0} | E: {1} | R: {2} | ETC: {3} | {4}:{5}" -f @($brokenFlatSets.Count, $elapsedStr, $etaTS.ToString("d\.hh\:mm\:ss"), $etaDT.ToString("dd-HH:mm:ss"), $fsPath, $linkURL)
        ShowProgress -progressID 1 -activity "Checking flatsets/references" -counter $referencesChecked -counterMax $referencesToCheck -statusSuffix $statusSuffix
    }

    $a++
}
$sw.Stop()

$docGUID = "d819f0a0-1fd0-42cc-b07f-3f598643a989"

$missingDocGUIDs = @(
	"8ad85b53-af77-4568-a430-9ae42f0ba34c",
	"a2e65514-ec6d-453d-b373-b1a4e1a8da8a",
	"7b9a666e-5b4c-4bce-8352-4077f3f7880b"
)

$takeAction = $true
$q = 0
$Error.Clear()
$Script:HaveError = $false
while($q -lt $missingDocGUIDs.Length)
{
    $docGUID = $missingDocGUIDs[$q]

    if($viablePathsDict.ContainsKey($docGUID))
    {
        # $vp is the file that needs to be reference.  So it needs to be uploaded.
        $vp = $viablePathsDict[$docGUID]

        if($vp.SourceObject.FullPath -notmatch ("^Active Projects"))
        {
            # Get all the broken links that reference the uploaded document.
            $bknFS = @($brokenFlatSets.Where({ $_.MissingReferenceGUID -eq $vp.SourceObject.DocumentGUID}))

            # $refSources are all the vp objects which reference $docToUpload.  -- They are all the FlatSets which contain $docToUpload
            $refSources = GetProposalFlatSetReferenceSources -pwData $pwData -viablePathsDict $viablePathsDict -docGuid $vp.SourceObject.DocumentGUID

            LogInfo ("`r`nProcessing {0}:{1} Version {2}" -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $vp.SourceObject.Version))
            # $documentsToUpload are all the versions of $vp...
            $documentsToUpload = @(@($viablePathsDict.Values).Where({ $_.SourceObject.FullPath -eq $vp.SourceObject.FullPath })) | Sort-Object @{E={ $_.SourceObject.VersionSequence }}

            if($documentsToUpload.Length -gt 0)
            {
                if($takeAction)
                {
                    $documentsToUpload.ForEach({
                        $_.SPData.Processed = $false
                        $null = GetLibraryDataFromObj -obj2Upload $_
                    })
                    UploadDocumentsToSharePoint -pwData $pwData -docsToUpload $documentsToUpload  # $docsToUpload = $documentsToUpload
                } `
                else
                {
                    $documentsToUpload.ForEach({
                        LogInfo ("  Uploading {0}:{1}:{2}" -f @($_.SourceObject.DocumentGUID, $_.SourceObject.FullPath, $_.SourceObject.Version))
                    })
                }

                LogInfo ("  Checking Doc 2 Upload: {0}:{1} Version: {2}" -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $vp.SourceObject.Version))

                # One at time, remove the broken link and create a new working link.
                $b = 0
                while($b -lt $bknFS.Length)
                {
                    try
                    {
                        $file = Get-PnPFile -Url $bknFS[$b].MissingReferenceURL -ErrorAction Stop
                        LogInfo ("    URL Not broken: [{0}]" -f @($bknFS[$b].MissingReferenceURL))
                    }
                    catch
                    {
                        if($Error[0].Exception.Message -match "File Not Found.")
                        {
                            $Error.Clear();
                            $Script:HaveError = $false

                            LogInfo ("    Removing broken link: [{0}]" -f @($bknFS[$b].FlatSetURL))

                            if($takeAction)
                            {
                                try
                                {
                                    Remove-PnpFile -SiteRelativeUrl $bknFS[$b].FlatSetURL -Force -ErrorAction Stop
                                }
                                catch
                                {
                                    if($Error[0].Exception.Message -match "does not exist")
                                    {
                                        $Error.Clear()
                                        $Script:HaveError = $false
                                    } `
                                    else
                                    {
                                        LogWarning ("Failed to remove broken URL [{0}]" -f @($bknFS[$b].FlatSetURL))
                                        LogWarning $Error[0].Exception.Message
                                    }
                                }
                            }

                            if(-not $Script:HaveError)
                            {
                                $refSrc = $refSources.Where({ $_.SourceObject.DocumentGUID -eq $bknFS[$b].FlatSetGUID }) | Select-Object -First 1
                                if($null -ne $refSrc)
                                {
                                    $vpLib = GetLibraryDataFromObj -obj2Upload $vp
                                    if((-not $Script:HaveError) -and ($null -ne $vpLib))
                                    {
                                        $refLib = GetLibraryDataFromObj -obj2Upload $refSrc
                                        if((-not $Script:HaveError) -and ($null -ne $refLib))
                                        {
                                            $linkParts = $bknFS[$b].FlatSetURL -split "/"
                                            $linkName = $linkParts[-1]
                                            $linkURL = $vp.LibInfo.FileURL
                                            $folderURL = $refLib.FileURL
                                            $linkParams = BuildDocumentProperties -obj2Upload $vp

                                            if ($takeAction)
                                            {
                                                CreateLinkInFolder -linkName $linkName -linkURL $linkURL -folderURL $folderURL -linkParams $linkParams
                                            } `
                                            else # NOT ($takeAction)
                                            {
                                                LogInfo ("    Creating link [{0}] in [{1}] to [{2}]" -f @($linkName, $folderURL, $linkURL))
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, already logged an error
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, already logged an error
                                    }
                                } `
                                else
                                {
                                    LogWarning ("No references sources for {0}" -f @($bknFS[$b].FlatSetGUID))
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            LogWarning $Error[0].Exception.Message
                        }
                    }
                    $b++
                }
            } `
            else
            {
                LogWarning ("No documents to upload for [{0}]" -f @($docGUID))
            }
        } `
        else
        {
            LogWarning ("Skipping external reference: {0}:{1} Version {2}" -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $vp.SourceObject.Version))
        }
    }

    $q++

}
