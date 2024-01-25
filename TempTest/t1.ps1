$tr = Import-csv -path \\cdcfs1\reference\perftest\results\202304101250-AUS-AUS-MGMT01.csv -Delimiter "`t"
$html = $tr |
    Select-Object `
        @{N='Datacenter'; E={$_.DCName}},
        @{N='Test host'; E={$_.TestHost}},
        @{N='File server'; E={$_.ServerName}},
        Description,
        @{N='Small file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileAverageMS)) }},
        @{N='Small file standard<br/>deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileMSStdDev)) }},
        @{N='Small file<br />variance'; E={ if($_.SmallFileMSVariance -gt 25) { ("<div style='color:red;'>{0:N2}%</div>" -f @([decimal]$_.SmallFileMSVariance)) } else { ("{0:N2}%" -f @([decimal]$_.SmallFileMSVariance)) }}},
        @{N='Medium file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileAverageMS)) }},
        @{N='Medium file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileMSStdDev)) }},
        @{N='Medium file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.MediumFileMSVariance)) }},
        @{N='Large file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileAverageMS)) }},
        @{N='Large file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileMSStdDev)) }},
        @{N='Large file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.LargeFileMSVariance)) }} |
    ConvertTo-Html -Head $htmlHeader |
    Set-AlternatingRows -CSSEvenClass even -CSSOddClass odd

$html2 = [System.Collections.Generic.List[String]]::new()
$html | ForEach-Object { $html2.Add( ([System.Web.HttpUtility]::HtmlDecode($_)) )}
$html = $html.Replace("`r`n","__")
    |
    $html | Set-Clipboard


function Set-AlternatingRows {
    <#
    .SYNOPSIS
        Simple function to alternate the row colors in an HTML table
    .DESCRIPTION
        This function accepts pipeline input from ConvertTo-HTML or any
        string with HTML in it.  It will then search for <tr> and replace
        it with <tr class=(something)>.  With the combination of CSS it
        can set alternating colors on table rows.

        CSS requirements:
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }

        Classnames can be anything and are configurable when executing the
        function.  Colors can, of course, be set to your preference.

        This function does not add CSS to your report, so you must provide
        the style sheet, typically part of the ConvertTo-HTML cmdlet using
        the -Head parameter.
    .PARAMETER Line
        String containing the HTML line, typically piped in through the
        pipeline.
    .PARAMETER CSSEvenClass
        Define which CSS class is your "even" row and color.
    .PARAMETER CSSOddClass
        Define which CSS class is your "odd" row and color.
    .EXAMPLE $Report | ConvertTo-HTML -Head $Header | Set-AlternateRows -CSSEvenClass even -CSSOddClass odd | Out-File HTMLReport.html

        $Header can be defined with a here-string as:
        $Header = @"
        <style>
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        </style>
        "@

        This will produce a table with alternating white and grey rows.  Custom CSS
        is defined in the $Header string and included with the table thanks to the -Head
        parameter in ConvertTo-HTML.
    .NOTES
        Author:         Martin Pugh
        Twitter:        @thesurlyadm1n
        Spiceworks:     Martin9700
        Blog:           www.thesurlyadmin.com

        Changelog:
            1.1         Modified replace to include the <td> tag, as it was changing the class
                        for the TH row as well.
            1.0         Initial function release
    .LINK
        http://community.spiceworks.com/scripts/show/1745-set-alternatingrows-function-modify-your-html-table-to-have-alternating-row-colors
    .LINK
        http://thesurlyadmin.com/2013/01/21/how-to-create-html-reports/
    #>
    [CmdletBinding()]
        Param(
            [Parameter(Mandatory,ValueFromPipeline)]
            [string]$Line,

            [Parameter(Mandatory)]
            [string]$CSSEvenClass,

            [Parameter(Mandatory)]
            [string]$CSSOddClass
        )

    Begin
    {
        $ClassName = $CSSEvenClass
    }

    Process
    {
        if ($Line.Contains("<tr><td>"))
        {
            $Line = $Line.Replace("<tr>","<tr class=""$ClassName"">")
            if ($ClassName -eq $CSSEvenClass)
            {
                $ClassName = $CSSOddClass
            }
            else
            {
                $ClassName = $CSSEvenClass
            }
        }

        return $Line
    }
}

$htmlHeader = @"
<head>
    <title>AUS Perf Testing</title>
    <style>
        body { font-family: Consolas,monaco,monospace; font-size: 9pt; }
        th { background-color:#0083FF; padding: 2px; font-size: 10pt; }
        td { text-align: center; padding: 2px; }
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        table, th, td { border: 1px solid black; border-collapse: collapse; }
    </style>
</head>
"@

$html = $allTestResults | Select-Object DCName,
    @{N='TestHost';E={hostname}},
    ServerName, DateTime, Description,

    @{N='SmallFileAverageMS';E={$_.FileTestSummary.Small.AverageMS}},
    @{N='SmallFileMSStdDev';E={$_.FileTestSummary.Small.MSStdDev}},
    @{N='SmallFileMSVariance';E={($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0}},

    @{N='MediumFileAverageMS';E={$_.FileTestSummary.Medium.AverageMS}},
    @{N='MediumFileMSStdDev';E={$_.FileTestSummary.Medium.MSStdDev}},
    @{N='MediumFileMSVariance';E={($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0}},

    @{N='LargeFileAverageMS';E={$_.FileTestSummary.Large.AverageMS}},
    @{N='LargeFileMSStdDev';E={$_.FileTestSummary.Large.MSStdDev}},
    @{N='LargeFileMSVariance';E={($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0}} |
    Select-Object `
        @{N='Datacenter'; E={$_.DCName}},
        @{N='Test host'; E={$_.TestHost}},
        @{N='File server'; E={$_.ServerName}},
        Description,
        @{N='Small file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileAverageMS)) }},
        @{N='Small file standard<br/>deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileMSStdDev)) }},
        @{N='Small file<br />variance'; E={ if($_.SmallFileMSVariance -gt 25) { ("<div style='color:red;'>{0:N2}%</div>" -f @([decimal]$_.SmallFileMSVariance)) } else { ("{0:N2}%" -f @([decimal]$_.SmallFileMSVariance)) }}},
        @{N='Medium file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileAverageMS)) }},
        @{N='Medium file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileMSStdDev)) }},
        @{N='Medium file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.MediumFileMSVariance)) }},
        @{N='Large file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileAverageMS)) }},
        @{N='Large file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileMSStdDev)) }},
        @{N='Large file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.LargeFileMSVariance)) }} |
    ConvertTo-Html -Head $htmlHeader |
    Set-AlternatingRows -CSSEvenClass even -CSSOddClass odd

$html2 = [System.Collections.Generic.List[String]]::new()
$html | ForEach-Object { $html2.Add( ([System.Web.HttpUtility]::HtmlDecode($_)) )}
$html2 | Set-Clipboard



$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
Set-AuthenticodeSignature -Certificate $cert -FilePath "..\PEI-IT-OPS\RDC\Metrics\SpeedTest.ps1"


$results = Import-CSV -Path \\cdcfs1\Reference\PerfTest\Results\PreSDWAN.csv


function NextPow2()
{
    $d = 999
    $c = 0
    while($d -ge 0)
    {
        $s = $Global:digits[$d] + $Global:digits[$d] + $c
        $c = 0
        if($s -gt 9)
        {
            $s -= 10
            $c = 1
        }
        $Global:digits[$d] = $s
        $d--
    }

    $Global:power2++
    $v = ($Global:digits -join "").TrimStart(@('0'))
    if([String]::IsNullOrEmpty($v))
    {
        $v = "0"
    }
    $a = $v.Length - 1
    $v2 = [System.Collections.Generic.Stack[System.Object]]::new()
    while($a -ge 0)
    {
        $v2.Push($v[$a])
        if(($a -gt 0) -and ((($v.Length - $a) % 3) -eq 0))
        {
            $v2.Push(',')
        }
        $a--
    }
    $addedCombos = [System.Collections.Generic.List[System.String]]::new()
    $combos = @(($v2 -join "") -split ",") | Sort-Object
    $combos | ForEach-Object {
        if(-not $Global:comboCount.ContainsKey($_))
        {
            $Global:comboCount.Add($_, 0)
            $addedCombos.Add($_)
        }
        $Global:comboCount[$_]++
    }

    Write-Host ("{0}" -f @(($addedCombos -join ", ")))
    Write-Host ("2^{0,3}: Combos: {1,4} {2,200}" -f @($Global:power2, $comboCount.Count, ($v2 -join "")))
}

$comboCount = [System.Collections.Generic.SortedDictionary[[String],[Int32]]]::new()

$power2 = 0
$digits = @(0..999)

@(0..($digits.Length - 1)) | ForEach-Object { $digits[$_] = 0 }

$digits[999] = 1

$currentCC = $comboCount.Count
do
{
    NextPow2
} until($comboCount.Count -ge 1099)


<#
    To facilitate retrieving AoVPN statistics in parallel (much faster), I need to create a list of objects containing:

        Index of a site within $aoStatsConfig.Sites
        Index of an AoVPNServer with $aoStatsConfig.Sites[_idx_]
        A list object to contain the results of Get-RemoteAccessConnectionStatistics from the AoVPN Server

    This is to ensure each thread created for the Foreach-Object -Parallel, has it's own uniquely addressable list to
    store the results from Get-RemoteAccessConnectionStatistics.
#>
$stats = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $aoStatsConfig.Sites.Length)
{
    $b = 0
    while($b -lt $aoStatsConfig.Sites[$a].VPNServers.Length)
    {
        $stat = "" | Select-Object SiteNumber,ServerNumber,CurrentStats,HourlyStats
        $stat.SiteNumber = $a
        $stat.ServerNumber = $b
        $stat.CurrentStats = [System.Collections.Generic.List[System.Object]]::new()
        $stat.HourlyStats = [System.Collections.Generic.List[System.Object]]::new()

        $stats.Add($stat)
        $b++
    }
    $a++
}

$endDateTime = [DateTime]::Now.ToUniversalTime()
$startDateTime = $endDateTime.AddHours(-4)

# In parallel, get all the AoVPN stats from the various servers.
$stats | Foreach-Object -Parallel {
    <#
        I tried a few variation of the following 7 lines of code, but $using makes it a little more complex.
        What I came up with seemed to work consistently.
    #>
    $eDT = $using:endDateTime
    $sDT = $using:startDateTime
    $ao = $using:aoStatsConfig
    $site = $ao.Sites[$_.SiteNumber]
    $aoVPNServer = $site.VPNServers[$_.ServerNumber]
    $currStats = $_.CurrentStats
    $hourlyStats = $_.HourlyStats

    $currStats.Clear()

    try
    {
        Invoke-Command -ComputerName $aoVPNServer -ScriptBlock { Get-RemoteAccessConnectionStatistics } | Foreach-Object {
            $currStats.Add($_)
        }
    }
    catch
    {
        Write-Error ("Failed to retrieve current AoVPN stats from {0}." -f @($aoVPNServer))
    }
    $hourlyStats.Clear()
    try
    {
        Invoke-Command -ComputerName $aoVPNServer -ScriptBlock { Get-RemoteAccessConnectionStatistics -StartDateTime ([DateTime]::Now.AddHours(-1)) -EndDateTime ([DateTime]::Now) } | Foreach-Object {
            $hourlyStats.Add($_)
        }
    }
    catch
    {
        Write-Error ("Failed to retrieve hourly AoVPN stats from {0}." -f @($aoVPNServer))
    }
}

$stats | ForEach-Object {
    Write-Host ("{0}/{1}: {2}/{3}" -f @($aoStatsConfig.Sites[$_.SiteNumber].SiteCode, $aoStatsConfig.Sites[$_.SiteNumber].VPNServers[$_.ServerNumber], $_.CurrentStats.Count, $_.HourlyStats.Count))
}


$licMgr = Get-View LicenseManager -Server $vCenter
$licAssignmentMgr = Get-View -Id $licMgr.LicenseAssignmentManager -Server $vCenter

$usedLicenses = $licAssignmentMgr.QueryAssignedLicenses($vCenter.InstanceUid)
$usedLicenses | Foreach-Object {
    $_ | Select-Object @{N='vCenter';E={$vCenter.Name}},EntityDisplayName,
        @{N='LicenseKey';E={$_.AssignedLIcense.LicenseKey}},
        @{N='LicenseName';E={$_.AssignedLicense.Name}},
        @{N='ExpirationDate';E={$_.AssignedLicense.Properties.where{$_.Key -eq 'expirationDate'}.Value }}
}


$licenseDataManager = Get-LicenseDataManager
$licenseDataManager.QueryEntityLicenseData()



$LicenseManager = Get-view LicenseManager

$LicenseAssignmentManager = Get-View $LicenseManager.LicenseAssignmentManager

$LicenseAssignmentManager.GetType().GetMethod("QueryAssignedLicenses").Invoke($LicenseAssignmentManager,@($null)) |
    Select-Object EntityDisplayName,
        @{N='Product';E={$_.Properties | where-object {$_.Key -eq 'ProductName'} | select-Object -ExpandProperty Value}},
        @{N='Product Version';E={$_.Properties | where-Object{$_.Key -eq 'FileVersion'} | select-Object -ExpandProperty Value}},
        @{N='License';E={$_.AssignedLicense.LicenseKey}},
        @{N='License Name';E={$_.AssignedLicense.Name}},
        @{N='Used License';E={$_.Properties | where-Object{$_.Key -eq 'EntityCost'} | select-Object -ExpandProperty Value}},
        @{N='Total';E={$_.AssignedLicense.Total}}





        $DN = (Get-ADUser -Identity "jdollus" -Properties DistinguishedName).DistinguishedName
        Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=CN=Ken Briney-adm,OU=Admin Accounts,OU=IT,OU=PEI,DC=powereng,DC=com)"



([ADSISEARCHER]"(member:1.2.840.113556.1.4.1941:=$(([ADSISEARCHER]"samaccountname=jdollus").FindOne().Properties.distinguishedname))").FindAll().Properties.distinguishedname -replace '^CN=([^,]+).+$','$1'


$projects = Get-ChildItem -Path "\\boifs1\shares$\Projects" | Where-Object { $_.PSIsContainer }
$explicitPaths = [System.Collections.Generic.List[System.String]]::new()
$p = 0
while($p -lt $projects.Length)
{
    Write-Host -ForegroundColor White -NoNewline ("Checking {0} of {1}: {2}..." -f @(($p + 1), $projects.Length, $projects[$p].Name))
    $acls = Get-Acl -Path $projects[$p].FullName
    if($null -ne $acls)
    {
        if($null -ne $acls.Access)
        {
            $explicitAccess = @($acls.Access | Where-Object { -not $_.IsInherited })
            if($explicitAccess.Length -gt 0)
            {
                $i = $explicitPaths.BinarySearch($projects[$p].Name)
                if($i -lt 0)
                {
                    $explicitPaths.Insert(-bnot $i, $projects[$p].Name)
                    Write-Host -NoNewline -ForegroundColor Green "explicit"
                }
            }
        }
    }
    Write-Host ""
    $p++
}

$explicitPaths -join ", " | Set-Clipboard


$cifsData = [System.Collections.Generic.List[System.Object]]::new()

$ctrlrs = @($cDOT.Values)
$b = 0
while($b -lt $ctrlrs.Length)
{
    $ctrlr = $ctrlrs[$b]
    $cifsServers = @(Get-NCCifsServer -Controller $ctrlr)
    $cifsSessions = @(Get-NcCifsSession -Controller $ctrlr)
    $a = 0
    while($a -lt $cifsServers.Length)
    {
        $d = "" | Select-Object Controller,VServer,SMB1Enabled,SMB2Enabled,SMB3Enabled,SMB31Enabled,SMBEncryptionRequired,SMBSigningRequired

        $cifsOptions = Get-NcCifsOption -Controller $ctrlr -VserverContext $cifsServers[$a].Vserver

        $d.Controller = $ctrlr.Name
        $d.VServer = $cifsServers[$a].Vserver
        $d.SMB1Enabled = $cifsOptions.IsSmb1Enabled -and $cifsOptions.IsSmb1EnabledSpecified
        $d.SMB2Enabled = $cifsOptions.IsSmb2Enabled -and $cifsOptions.IsSmb2EnabledSpecified
        $d.SMB3Enabled = $cifsOptions.IsSmb3Enabled -and $cifsOptions.IsSmb3EnabledSpecified
        $d.SMB31Enabled = $cifsOptions.IsSmb31Enabled -and $cifsOptions.IsSmb31EnabledSpecified

        $cifsSecurity = Get-NcCifsSecurity -Controller $ctrlr -VserverContext $cifsServers[$a].Vserver
        $d.SMBEncryptionRequired = $cifsSecurity.IsSmbEncryptionRequired -and $cifsSecurity.IsSmbEncryptionRequiredSpecified
        $d.SMBSigningRequired = $cifsSecurity.IsSigningRequired -and $cifsSecurity.IsSigningRequiredSpecified

        $sessions = @($cifsSessions | Where-Object { $_.Vserver -eq $cifsServers[$a].Vserver })
        if($sessions.Length -gt 0)
        {
            $sessionGroups = $cifsSessions | Group-Object -Property ProtocolVerion
            $a = $cifsServers.Length
            $b = $ctrlrs.Length
        }

        Write-Host ("{0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}" -f @($d.Controller, $d.VServer, $d.SMB1Enabled, $d.SMB2Enabled, $d.SMB3Enabled, $d.SMB31Enabled, $d.SMBEncryptionRequired, $d.SMBSigningRequired))
        $cifsData.Add($d)

        $a++
    }
    $b++
}

$cifsData | ConvertTo-Csv -NoTypeInformation -Delimiter "`t" | Set-Clipboard
