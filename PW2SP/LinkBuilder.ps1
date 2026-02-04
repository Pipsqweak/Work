. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\ExportPW2SPFunctions.ps1

[Switch] $isProposal = $true
$proposalListFile = "E:\PW2SPProd\proposalList.csv"
$Script:localPath = "E:\PWProposals"
$Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataFed.json"
#$Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProposalsKLB.json"
$Script:pwDatasource = "pw_prod_pw01"
$Script:pwPassword = "tX2NPfAK92DhM2"
$Script:TraceLevel = 1
[Switch] $Script:dbgOut = $true
$myProposal = $null


LoadConnectionDataFromFile
ConnectToSPOL

function GetFolderFSLinks
{
    [CmdLetBinding()]
    Param(
        [AllowNull()]
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $folderName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [object] $linkData,

        if($null -eq $linkData)
        {
            $linkData = [System.Collections.Generic.List[Object]]::new()
        } `
        else
        {
            # Nothing
        }

$folderName = "Proposal Archives"
                    $ff = @()
                    try
                    {
                        $ff =  @(Get-PnpFolderItem -Identity $folderName -ErrorAction Stop)
                    }
                    catch
                    {
                        if(($Script:isProposal.IsPresent) -and ($Error.Count -gt 0) -and ($Error[0].Exception.Message -match "File Not Found"))
                        {
                            $Error.Clear()

                            LogInfo ("`tProposal folder not found")
                        } `
                        else
                        {
                            LogError ("Failed to retrieve folders and files for {0} in {1}." -f @($lib.RealName, $me.Name))
                        }
                    }
}
