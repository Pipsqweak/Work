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



$resultFiles = @(Get-ChildItem -Path "\\cdcfs1\Reference\PerfTest\Results" -Filter "*.csv")

$combinedResults = [System.Collections.Generic.List[System.Object]]::new()
$combinedFiles = [System.Collections.Generic.List[System.String]]::new()

$a = 0
while($a -lt $resultFiles.Length)
{
    $results = Import-CSV -Path $resultFiles[$a].FullName -Delimiter "`t"
    $included = $false

    $b = 0
    while($b -lt $results.Length)
    {
        if($results[$b].Description -eq "Before SDWAN conversion")
        {
            $combinedResults.Add($results[$b])
            $included = $true
        }
        $b++
    }

    if($included)
    {
        Write-Host -NoNewline ("{0}" -f @($resultFiles[$a].FullName))
        # Do not add PreSDWANCombined.csv to the list of combined files, or it will be removed just after it is recreated...
        if($resultFiles[$a].Name -notmatch "PreSDWANCombined.csv")
        {
            $combinedFiles.Add($resultFiles[$a].FullName)
            Write-Host -NoNewline (" to be deleted")
        }
        else
        {
        }

        Write-Host ""
    }

    $a++
}

try
{
    $combinedResults | Export-CSV -Path "\\cdcfs1\Reference\PerfTest\Results\PreSDWANCombined.csv" -Delimiter "`t" -NoTypeInformation -Force -Confirm:$false -ErrorAction Stop
    $combinedFiles | Foreach-Object { Remove-Item -Path $_ -Force -Confirm:$false -ErrorAction Stop }
}
catch
{

}
