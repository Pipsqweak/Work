[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 0)]
    [String]
    $publicFolderListFile,

    [Parameter(Mandatory = $true, ParameterSetName = 'Individual', Position = 0)]
    [String]
    $publicFolderEntryID,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 1)]
    [String]
    $PWServerFQDN,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 2)]
    [String]
    $PWDatasourceName,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 3)]
    [String]
    $PWUserName,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 4)]
    [String]
    $PWEncryptedUserPassword,  # This is the result of: ConvertTo-SecureString -String "plainTextPassword" -AsPlainText -Force  | ConvertFrom-SecureString

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 5)]
    [String]
    $ProjectWiseBaseFolderName,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 6)]
    [String]
    $LogFolder,

    [Parameter(Mandatory = $true, ParameterSetName = 'List', Position = 7)]
    [String]
    $BaseWorkingFolder
)

function ProcessPFEntryID
{
    LogInfo "Processing single public folder entry."

    ExportPublicFolder -publicFolderIdentity $Script:publicFolderEntryID
}

function duh
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $publicFolderEntryID
    )

    $cmdArgs = @(
        "-File", $PSCommandPath,
        "-publicFolderEntryID", $publicFolderEntryID,
        "-PWServerFQDN", $Script:PWServerFQDN,
        "-PWDatasourceName", $Script:PWDatasourceName,
        "-PWUserName", $Script:PWUserName,
        "-PWEncryptedUserPassword", $Script:PWEncryptedUserPassword,
        "-ProjectWiseBaseFolderName", $Script:ProjectWiseBaseFolderName,
        "-LogFolder", $Script:LogFolder,
        "-BaseWorkingFolder", $Script:BaseWorkingFolder
    )

    Start-Process -WindowStyle Normal powershell.exe $cmdArgs | Out-Null
}

function ProcessPFList
{
    try
    {
        # Always make sure $pfList is an Array...
        $pfList = @(Import-CSV -Path $Script:publicFolderListFile -Delimiter "`t" -ErrorAction Stop)
    }
    catch
    {
        LogError ("Failed to load list of public folder to transfer from: {0}." -f @($publicFolderListFile))
        $Script:ReturnObject.Good2Go = $false
    }

    if($Script:ReturnObject.Good2Go)
    {
        LogInfo ("Processing {0} public folder entries." -f @($pfList.Length))

        # Proceed with transferring items from public folders to ProjectWise...
        $pfListIdx = 0
        # Don't stop the remaining exports if something went wrong with one.  ExportPublicFolder will reset $Script:ReturnObject.Good2Go each time it runs.
        while($pfListIdx -lt $pfList.Length)
        {
            $percentComplete = ($pfListIdx / $pfList.Length)
            $status = "{0,7:P2} Complete | Exported: {1} | Remaining: {2}" -f @($percentComplete, $pfListIdx, ($pfList.Length - $pfListIdx))
            Write-Progress -Id 0 -Activity "Xfering PFs to PW..." -Status $status -PercentComplete ($percentComplete * 100.0)

            ExportPublicFolder -publicFolderIdentity $pfList[$pfListIdx]
            $pfListIdx++
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing.
    }
}

function main
{
    InitializeExporter

    if([System.IO.Directory]::Exists($Script:BaseWorkingFolder))
    {
        if(-not [System.IO.Directory]::Exists($Script:ResultsFolder))
        {
            try
            {
                [System.IO.Directory]::CreateDirectory($Script:ResultsFolder)
            }
            catch
            {
                LogException ("Unable to create folder {0}." -f @($Script:ResultsFolder))
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else # NOT (-not [System.IO.Directory]::Exists($Script:ResultsFolder))
        {
            # Nothing.
        }

        if($Script:ReturnObject.Good2Go)
        {
            switch($PSCmdlet.ParameterSetName)
            {
                "List"
                {
                    ProcessPFList
                    break
                }
                "Individual"
                {
                    ProcessPFEntryID
                    break
                }
            }

            CleanUp
        } `
        else # NOT ($Script:ReturnObject.Good2Go)
        {
            # Nothing.
        }
    } `
    else # NOT ([System.IO.Directory]::Exists($Script:BaseWorkingFolder))
    {
        LogException ("Base working folder: {0} does not exist.  Please create and retry." -f @($Script:BaseWorkingFolder))
        $Script:ReturnObject.Good2Go = $false
    }
}
