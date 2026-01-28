Import-Module pwps_dab
. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\LogFunctions.ps1

<#
    Per: https://support.microsoft.com/en-us/office/restrictions-and-limitations-in-onedrive-and-sharepoint-64883a5d-228e-48f5-b3d2-eb39e07630fa#filenamepathlengths
#>

$Script:MAX_SP_DOC_PATH_LEN = 390  # Actual Number is 400.  I'm using 200 to force some issues.

$Script:IlegalCharactersInFoldersAndFilesRegEx = "([\t\`"\*\:\<\>\?\/\\\|])"

$Script:COUNTER_CHARACTERS = @("0".."9") + @("A".."Z")

$Script:MAXFPSTRLEN = 75

$Script:MaxUploadetries = 3

$Script:uploadProgressFMTStr = "Uploading file {{0:N0}} of {{1:N0}} {{2,-{0}}}  ({{3,10}})" -f @($Script:MAXFPSTRLEN + 3)

$Script:fieldsToCreateForExistingProjects = @(
    "_update_toggle", "_xfer_to_pw02", "a_attrno", "appendix", "approval_id_QAQC", "calc_type1", "calc_type2", "confidential", "contract_agreement_type01",
    "contract_counterprty", "contract_coversheet", "contract_division", "contract_effectdate", "contract_exhibits", "contract_num_legal", "contract_price",
    "contract_project_country", "contract_project_name", "contract_project_nbr", "contract_project_pm", "contract_project_state", "contract_umbrella_num",
    "copies", "createdate", "creator", "date_received", "deliverable", "department_no", "discipline", "doc_class", "doc_date", "doc_no", "doc_type1",
    "doc_type2", "draw_date", "draw_num", "draw_revdate", "draw_revnum", "draw_title1", "draw_title2", "draw_title3", "draw_title4", "draw_type1",
    "draw_type2", "equip_type1", "folder_description", "folder_name", "group_type", "incoming_outgoing", "interface", "invoice_number", "issue_date",
    "keywords", "kmp_author", "LAFN", "lastmodifier", "lastmodifydate", "log", "percent_complete", "photo_datetaken", "photo_takenby", "photo_title1",
    "photo_title2", "pmo_pm", "pmo_proj_enddate", "pmo_proj_startdate", "PROJECT_cad_coordinator", "PROJECT_certified_payroll", "project_client",
    "PROJECT_crm_opportunity_name", "PROJECT_crm_opportunity_number", "PROJECT_customer_name", "PROJECT_destruction_date", "PROJECT_div_organization_name",
    "PROJECT_env", "PROJECT_fac", "PROJECT_federal_government_work", "PROJECT_federal_gsa_contract", "PROJECT_gen", "PROJECT_international",
    "PROJECT_is_consulting_client", "PROJECT_legal_hold", "PROJECT_market", "PROJECT_mpd_coordinator", "PROJECT_non_traditional_svcs_project",
    "PROJECT_nuclear", "PROJECT_organization_name", "PROJECT_pd", "project_pma", "PROJECT_pma", "PROJECT_program_manager",
    "PROJECT_proj_close_date", "PROJECT_proj_nbr", "PROJECT_proj_open_date", "PROJECT_project_country",
    "PROJECT_project_engineer", "PROJECT_project_manager", "PROJECT_project_name", "PROJECT_project_sponsor", "PROJECT_project_state",
    "PROJECT_project_status", "PROJECT_project_status_name", "PROJECT_project_type", "PROJECT_project_type_category", "PROJECT_project_type_class_code",
    "PROJECT_proposal_destruction_date", "PROJECT_proposal_due_date", "PROJECT_proposal_go_no", "PROJECT_proposal_keywords",
    "PROJECT_proposal_project_number", "PROJECT_proposal_status", "PROJECT_proposal_task_number", "PROJECT_proposal_type", "project_psa", "PROJECT_psa",
    "PROJECT_public_sector_flag", "PROJECT_retention_permanent", "PROJECT_retention_proposal", "PROJECT_retention_special", "PROJECT_retention_standard",
    "PROJECT_sec_prj", "PROJECT_service_type_code", "PROJECT_sub_market", "PROJECT_workarea_notes", "ProjectTypeId", "received_via_email", "report_type1",
    "revision", "revision_prefix", "section", "sequence", "site", "source", "source_name", "sources", "spec_type1", "spec_type2", "status",
    "status_backcheck", "status_pecheck", "status_QAQC", "transmittal_description", "transmittal_doctype", "transmittal_issuedfor", "update_toggle",
    "voltage_class", "year", "year_case", "zipfile_name"
)
# These are fields I really don't care about when verifying a file.
$Script:InsignificantFields = @("Modified","Created")

$Script:requiredParams = @("connDataJSONFile","pwDatasource","pwPassword","pwProjectPath","projectName","localPath")

$Script:IgnoredDocumentLibraryNames = @(
    "Access Requests", "appdata", "appfiles", "CAD-BIM Project testing", "Composed Looks", "Converted Forms", "Events", "Federal Pursuit Collaboration", "Form Templates",
    "List Template Gallery", "Maintenance Log Library", "Master Page Gallery", "Pursuit Collaboration", "Sharing Links", "Site Assets", "Site Pages", "Solution Gallery",
    "Style Library", "TaxonomyHiddenList", "Template Extensions", "Theme Gallery", "User Information List", "Web Part Gallery", "ZUsers"
)

$Script:initialized = $false

function InitializeReport
{
    $Script:reportData = [PSCustomObject]@{
        Folders = [PSCustomObject]@{
            ReportedFromProjectWise = 0
            InProject = 0
            Created = 0
            PreExisting = 0
        }
        Documents = [PSCustomObject]@{
            ReportedFromProjectWise = 0
            DuplicatesFound = 0
            InProject = 0
            Created = 0
            PreExisting = 0
        }
        DocumentSets = [PSCustomObject]@{
            InProject = 0
            Created = 0
            PreExisting = 0
        }
        DocumentLinks = [PSCustomObject]@{
            InProject = 0
            Created = 0
            PreExisting = 0
        }
        Size = [PSCustomObject]@{
            InProjectWise = 0
            Uploaded = 0
            Skipped = 0
        }
    }
}

function LoadConnectionDataFromFile
{
    $me = $MyInvocation.MyCommand
    $Script:connData = $null
    if ([System.IO.Path]::Exists($Script:connDataJSONFile))
    {
        try
        {
            LogInfo ("Loading connection file: {0}" -f @($Script:connDataJSONFile))
            $connDataText = Get-Content -Path $Script:connDataJSONFile -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to read Sharepoint data from {0} in {1}." -f @($Script:connDataJSONFile, $me.Name))
        }

        if(-not $Script:HaveError)
        {
            try
            {
                $Script:connData = $connDataText | ConvertFrom-JSon -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to convert Sharepoint JSON data text to object in {0}." -f @($me.Name))
            }
        }

        if(-not $Script:HaveError)
        {
            if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.AzureAppId))
            {
                LogError ("Missing AzureAppId in Sharepoint Connection data in {0}." -f @($me.Name))
            } `
            else
            {
                # Nothing, continue
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if(-not $Script:HaveError)
        {
            if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.pfxBase64Encoded))
            {
                LogError ("Missing base 64 encoded PFX in Sharepoint Connection data in {0}." -f @($me.Name))
            } `
            else
            {
                # Nothing, continue
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if(-not $Script:HaveError)
        {
            if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.SharePointRootURL))
            {
                LogError ("Missing SharePoint Online root URL in {0}." -f @($me.Name))
            } `
            else
            {
                # Nothing, continue
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if(-not $Script:HaveError)
        {
            if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.SharePointSiteName))
            {
                LogError ("Missing SharePoint Online site name in {0}." -f @($me.Name))
            } `
            else
            {
                # Nothing, continue
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }

        if(-not $Script:HaveError)
        {
            # Not strictly needed here, but I'll check it anyway.
            if($null -eq $Script:connData.documentFields)
            {
                LogError ("Missing SharePoint project property definitions in {0}." -f @($me.Name))
            } `
            else
            {
                # Nothing, continue
            }
        } `
        else
        {
            # Nothing, already displayed an error
        }

        # Convert .documentFields into a dictionary...
        $docFields = [System.Collections.Generic.SortedDictionary[String, Object]]::new()
        $Script:connData.documentFields.Foreach({
            if(-not $docFields.ContainsKey($_.InternalName))
            {
                $docFields.Add($_.InternalName, $_)
            } `
            else
            {
                LogError ("Duplicate document field {0}, idx: {1} in {2}." -f @($_.InternalName, $Script:connData.documentFields.IndexOf($_), $me.Name))
            }
        })

        if(-not $Script:HaveError)
        {
            $Script:connData.documentFields = $docFields
        } `
        else
        {
            # Nothing, already logged an error.
        }

        if(-not $Script:HaveError)
        {
            $attrSets = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $Script:connData.attributeSets.Length))
            {
                if(-not $attrSets.ContainsKey($Script:connData.attributeSets[$a].Name))
                {
                    $attrSets.Add($Script:connData.attributeSets[$a].Name, $Script:connData.attributeSets[$a].Attributes)
                } `
                else
                {
                    LogError ("Duplicate attribute set name: {0} in {1}." -f @($Script:connData.attributeSets[$a].Name, $me.Name))
                }
                $a++
            }

            if(-not $Script:HaveError)
            {
                $Script:connData.attributeSets = $attrSets
            } `
            else
            {
                # Nothing, already logged an error.
            }
        }
    } `
    else # NOT ([System.IO.Directory]::Exists())
    {
        LogError ("{0} does not exist in {1}." -f @($Script:connDataJSONFile, $me.Name))
    }
}

function ConnectToSPOL
{
    $me = $MyInvocation.MyCommand

    if(-not $Script:HaveError)
    {
        $siteURL = "{0}/sites/{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $Script:connData.ConnectionInformation.SharePointSiteName)

        $spOLConnected = $false
        try
        {
            $currentSPOLConn = Get-PnpConnection -ErrorAction Stop
            if($null -ne $currentSPOLConn)
            {
                if(($currentSPOLConn.Url -split "/")[-1] -match $Script:connData.ConnectionInformation.SharePointSiteName)
                {
                    LogInfo ("Already connected to SharePoint Online")
                    $spOLConnected = $true
                } `
                else
                {
                    LogInfo ("Connect wrong SharePoint site. {0}" -f @(($currentSPOLConn.Url -split "/")[-1]))
                    LogInfo ("Disconnecting..." -f @(($currentSPOLConn.Url -split "/")[-1]))
                    Disconnect-PnPOnline
                    $spOLConnected = $false
                }
            }
        }
        catch
        {
            $Error.Clear()
        }

        if(-not $spOLConnected)
        {
            try
            {
                LogInfo ("Connecting to SharePoint Online...")
                Connect-PnPOnline $siteURL -ClientId $Script:connData.ConnectionInformation.AzureAppId -Tenant powereng0.onmicrosoft.com -CertificateBase64Encoded $Script:connData.ConnectionInformation.pfxBase64Encoded -ErrorAction Stop
                LogInfo ("`tconnected")
            }
            catch
            {
                LogError ("Unable to connect to SharePoint Online in {0}." -f @($me.Name))
            }
        } `
        else
        {
            # Nothing, already connected.
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    return (-not $Script:HaveError)
}

function BuildDocumentLibraryDictionary
{
    $me = $MyInvocation.MyCommand
    try
    {
        $docLibraries = Get-PnpList -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to get all document libraries from {0} in {1}." -f @($Script:connData.ConnectionInformation.SharePointSiteName, $me.Name))
    }

    if(-not $Script:HaveError)
    {
        $Script:connData.ConnectionInformation.SharePointDocumentLibraries = [System.Collections.Generic.SortedDictionary[String, Object]]::new()
        $docLibraries.Foreach({
            if($_.BaseType -eq [Microsoft.SharePoint.Client.BaseType]::DocumentLibrary)
            {
                # Ignore the default document libraries...
                if($_.Title -notin $Script:IgnoredDocumentLibraryNames)
                {
                    if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($_.Title))
                    {
                        if($null -ne $_.RootFolder)
                        {
                            if(-not [String]::IsNullOrEmpty($_.RootFolder.ServerRelativeUrl))
                            {
                                $libInfo = [PSCustomObject]@{
                                    Library = $_
                                    RealName = @($_.RootFolder.ServerRelativeURL -split "/") | Select-Object -Last 1
                                }
                                $Script:connData.ConnectionInformation.SharePointDocumentLibraries.Add($_.Title, $libInfo)
                            } `
                            else
                            {
                                LogError ("Missing document library URL for {0} in {1}." -f @($_.Title, $me.Name))
                            }
                        } `
                        else
                        {
                            LogError ("Missing document library root folder for {0} in {1}." -f @($_.Title, $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Duplicate document library {0} in {1}." -f @($_.Title, $me.Name))
                    }
                } `
                else
                {
                    # Nothing, this is a document library we don't care about.
                }
            } `
            else
            {
                # Nothing, only want document libraries
            }
        })
    }
}

function Init
{
    $me = $MyInvocation.MyCommand

    if(-not $Script:initialized)
    {
        $Script:itemsVerified = 0

        # Global error indicator.
        $Script:HaveError = $false
        $Error.Clear()

        # Changing the script to only connect to ProjectWise if I need to.
        $Script:connectedToPW = $false

        # Reset the data export path
        $Script:pwDataExportPath = [String]::Empty

        # Reset the viable path export path
        $Script:viablePathExportPath = [String]::Empty
        Write-Host ("`t`t`tViable Path Export Path: [{0}]" -f @($Script:viablePathExportPath))

        # Reset the viable paths verification lookup dictionary
        $Script:viablePathsLookupDict = $null

        # Used to name the export files for $pwData and $viablePathsDict
        $Script:exportDateTime = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")

        $missingParams = [System.Collections.Generic.List[String]]::new()
        $Script:requiredParams.ForEach({
            $pn = $_
            try
            {
                $null = Get-Variable -Scope Script -Name $_ -ErrorAction Stop
            }
            catch
            {
                $missingParams.Add($pn)
            }
        })

        if($missingParams.Count -gt 0)
        {
            Write-Host -ForegroundColor Red ("Missing required variables:`r`n`t`$Script:{0}" -f @(($missingParams -join "`r`n`t`$Script:")))
            Write-Host "`tAnd you might want to check on these switches: DoExport, restart, and dbgOut"
            $Script:HaveError = $true
        }

        if(-not $Script:HaveError)
        {
            $Script:DoDebugging = $Script:dbgOut.IsPresent

            if(-not [String]::IsNullOrEmpty($Script:localPath))
            {
                $Script:LogFolder = "{0}\Logs" -f @($Script:localPath)
                if(-not [System.IO.Directory]::Exists($Script:LogFolder))
                {
                    try
                    {
                        $null = New-Item -ItemType Directory -Path $Script:LogFolder -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Error ("Unable to create log folder: {0}." -f @($Script:LogFolder))
                        $Script:HaveError = $true
                    }
                } `
                else
                {
                    # Nothing, $Script:localPath already exists.
                }
            } `
            else
            {
                Write-Host -ForegroundColor Red ("Missing local path.")
                $Script:HaveError = $true
            }

            if(-not $Script:HaveError)
            {
                # Reset the log file name...
                $Script:LogFileName = [String]::Empty
                $Script:LogFileNamePrefix = $Script:projectName
                $Script:LogFileName = "{0}\{1}-{2}.log" -f @($Script:LogFolder, $Script:LogFileNamePrefix, [DateTime]::Now.ToString("yyyyMMdd-HHmmssfff"))
            } `
            else
            {
                # Nothing, already displayed an error.
            }

            InitializeReport
            if(-not [System.IO.Directory]::Exists($Script:localPath))
            {
                try
                {
                    $null = New-Item -ItemType Directory -Path $Script:localPath -ErrorAction Stop
                }
                catch
                {
                    Write-Error ("Unable to create local folder: {0}." -f @($Script:localPath))
                    $Script:HaveError = $true
                }
            } `
            else
            {
                # Nothing, $Script:localPath already exists.
            }

            $projectExportFolder = "{0}\{1}" -f @($Script:localPath, $Script:pwProjectPath)
            if(-not [System.IO.Directory]::Exists($projectExportFolder))
            {
                try
                {
                    $null = New-Item -ItemType Directory -Path $projectExportFolder -ErrorAction Stop
                }
                catch
                {
                    Write-Error ("Unable to create project export folder: {0}." -f @($projectExportFolder))
                    $Script:HaveError = $true
                }
            } `
            else
            {
                # Nothing, $Script:localPath already exists.
            }

            LogInfo ("PID: {0}`r`nLog file: {1}" -f @($PID, $Script:LogFileName))
            if(-not $Script:HaveError)
            {
                # From here, we are able to use the log functions...

                $PSStyle.Progress.View = 'Minimal'
                $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
                $Error.Clear()
                LoadConnectionDataFromFile
                LogInfo ("Processing {0}" -f @($Script:projectName))

                if($null -ne $Script:connData)
                {
                    if(ConnectToSPOL)
                    {
                        LogInfo "Connected to SharePoint Online"
                        BuildDocumentLibraryDictionary
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

            if(-not $Script:HaveError)
            {
                $Script:AttributeSetName = "Default"
                if($Script:isProposal.IsPresent)
                {
                    $Script:AttributeSetName = "Proposal"
                } `
                else
                {
                    # Nothing
                }
            } `
            else
            {
                # Nothing, already logged an error
            }
        } `
        else
        {
            # Nothing, already logged/displayed an error.
        }
        $Script:initialized = $true
    } `
    else
    {
        # Nothing, already initialized.
    }
}

function InitProposals
{
    $me = $MyInvocation.MyCommand

    # Global error indicator.
    $Script:HaveError = $false
    $Error.Clear()

    # Changing the script to only connect to ProjectWise if I need to.
    $Script:connectedToPW = $false

    if(-not [String]::IsNullOrEmpty($Script:proposalName))
    {
        $Script:DoDebugging = $Script:dbgOut.IsPresent

        if(-not [String]::IsNullOrEmpty($Script:localPath))
        {
            if(-not [System.IO.Directory]::Exists($Script:localPath))
            {
                try
                {
                    $null = New-Item -ItemType Directory -Path $Script:localPath -ErrorAction Stop
                }
                catch
                {
                    Write-Error ("Unable to create local folder: {0}." -f @($Script:localPath))
                    $Script:HaveError = $true
                }
            } `
            else
            {
                # Nothing, $Script:localPath already exists.
            }

            if(-not $Script:HaveError)
            {
                $Script:LogFolder = "{0}\Logs" -f @($Script:localPath)
                if(-not [System.IO.Directory]::Exists($Script:LogFolder))
                {
                    try
                    {
                        $null = New-Item -ItemType Directory -Path $Script:LogFolder -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Error ("Unable to create log folder: {0}." -f @($Script:LogFolder))
                        $Script:HaveError = $true
                    }
                } `
                else
                {
                    # Nothing, $Script:LogFolder already exists.
                }
            } `
            else
            {
                Write-Host -ForegroundColor Red ("Missing local path.")
                $Script:HaveError = $true
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red ("Missing value for `$Script:localPath")
        }
    } `
    else
    {
        Write-Host -ForegroundColor Red ("Missing value for `$Script:proposalName")
        $Script:HaveError = $true
    }

    if(-not $Script:HaveError)
    {
        # Reset the log file name...
        $Script:LogFileName = [String]::Empty
        $Script:LogFileNamePrefix = $Script:proposalName
        $Script:LogFileName = "{0}\{1}-{2}.log" -f @($Script:LogFolder, $Script:LogFileNamePrefix, [DateTime]::Now.ToString("yyyyMMdd-HHmmssfff"))
        LogInfo ("PID: {0}`r`nLog file: {1}" -f @($PID, $Script:LogFileName))

        # From here, we are able to use the log functions...

        $PSStyle.Progress.View = 'Minimal'
        $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
        LoadConnectionDataFromFile
        if($null -ne $Script:connData)
        {
            LogInfo ("Processing {0}" -f @($Script:proposalName))

            if(ConnectToSPOL)
            {
                LogInfo "Connected to SharePoint Online"
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
}

function ShowProgress
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="Complete", ValueFromPipeline=$false, Position=0)]
        [Int32] $progressID,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=1)]
        [String] $activity,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=2)]
        [Int32] $counter,

        [Parameter(Mandatory=$true, ParameterSetName="Running", ValueFromPipeline=$false, Position=3)]
        [Int32] $counterMax,

        [Parameter(Mandatory=$false, ParameterSetName="Running", ValueFromPipeline=$false, Position=4)]
        [String] $statusSuffix = [String]::Empty,

        [Parameter(Mandatory=$false, ParameterSetName="Complete", ValueFromPipeline=$false, Position=1)]
        [Switch] $complete
    )

    if(-not $complete.IsPresent)
    {
        $pc = [float] ($counter + 1) / [float] $counterMax
        if($pc -gt 1)
        {
            $pc = [Float] 0.99
        }
        $counterMaxStrLen = $counterMax.ToString("N0").Length
        $activityStr = ("{0} {{0,{1}:N0}} of {{1,{1}:N0}}" -f ($activity, $counterMaxStrLen)) -f @(($counter + 1), $counterMax)
        $statusStr = "{0,7:P} Complete" -f @($pc)
        if(-not [String]::IsNullOrEmpty($statusSuffix))
        {
            $statusStr = @($statusStr, $statusSuffix) -join " | "
        }
        Write-Progress -Id $progressID -Activity $activityStr -Status $statusStr -PercentComplete ($pc * 100)
    } `
    else
    {
        Write-Progress -Id $progressID -Completed
    }
}

function LoadPWDataFromJSON
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String]
        [System.Object] $filePath
    )

    $me = $MyInvocation.MyCommand
    if([System.IO.File]::Exists($filePath))
    {
        LogInfo ("Loading pwData from: [{0}]" -f @($filePath))
        try
        {
            $jsonContent = Get-Content -Path $filePath -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to read JSON data from {0} in {1}." -f @($filePath, $me.Name))
        }

        if(-not $Script:HaveError)
        {
            try
            {
                $data = $jsonContent | ConvertFrom-Json -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to convert JSON data from {0} into an object in {1}." -f @($filePath, $me.Name))
            }
        } `
        else
        {
            $retval = $null
        }

        if(-not $Script:HaveError)
        {
            $retval = [PSCustomObject]@{
                PWFolder = $null
                ProjectWiseObjects = [System.Collections.Generic.SortedDictionary[Guid, Object]]::new()
                Security = $null
                StorageAreas = [System.Collections.Generic.SortedDictionary[String, String]]::new()
                PWFolders = [System.Collections.Generic.List[Guid]]::new()
            }

            # I don't need to add $retval.PWFolder to .ProjectWiseObjects, it was there when the data was exported.
            $retval.PWFolder = $data.PWFolder
            $i = $retval.PWFolders.BinarySearch($data.PWFolder.DocumentGUID)
            if($i -lt 0)
            {
                $retval.PWFolders.Insert(-bnot $i, $data.PWFolder.DocumentGUID)
            }

            # Rebuild the project properties
            $pps = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
            if($null -ne $retval.PWFolder.ProjectProperties)
            {
                $mbrs = @($retval.PWFolder.ProjectProperties | Get-Member -MemberType NoteProperty)
                $a = 0
                while($a -lt $mbrs.Length)
                {
                    if(-not [String]::IsNullOrEmpty($data.PWFolder.ProjectProperties.$($mbrs[$a].Name)))
                    {
                        $pps.Add($mbrs[$a].Name, $data.PWFolder.ProjectProperties.$($mbrs[$a].Name))
                    } `
                    else
                    {
                        # skip empty properties
                    }
                    $a++
                }
            }
            $retval.PWFolder.ProjectProperties = $pps

            $a = 0
            while($a -lt $data.ProjectWiseObjects.Length)
            {
                ShowProgress -progressID 1 -activity "Converting PW Data objects" -counter $a -counterMax $data.ProjectWiseObjects.Length

                $retval.ProjectWiseObjects.Add($data.ProjectWiseObjects[$a].DocumentGUID, $data.ProjectWiseObjects[$a])
                $ro = $retval.ProjectWiseObjects[$data.ProjectWiseObjects[$a].DocumentGUID]

                $fpOld = $ro.FullPath
                $ro.FullPath = @($ro.FullPath -split "\\").ForEach({ $_ -replace $Script:IlegalCharactersInFoldersAndFilesRegEx, "_" }) -join "\"
                if($fpOld -ne $ro.FullPath)
                {
                    LogTrace ("Fixed illegal characters in FP.") -traceLevel 1
                    LogTrace ("`tOld: {0}" -f @($fpOld)) -traceLevel 1
                    LogTrace ("`tnew: {0}" -f @($ro.FullPath)) -traceLevel 1
                }

                if($ro.MyType -eq "ProjectWiseDocument")
                {
                    $fsRefs = [System.Collections.Generic.List[Guid]]::new()
                    if($ro.FlatSetReferences -is [Array])
                    {
                        # Convert the $retval.ProjectWiseObjects[$data.ProjectWiseObjects[$a].DocumentGUID].FlatSetReferences into a list.
                        #   Which is odd, after ConvertFrom-Json, $data.ProjectWiseObjects[$a].FlatSetReferences is a list, but after
                        #      $retval.ProjectWiseObjects.Add($data.ProjectWiseObjects[$a].DocumentGUID, $data.ProjectWiseObjects[$a]), it's an array
                        $b = 0
                        while($b -lt $ro.FlatSetReferences.Length)
                        {
                            $fsRefs.Add($ro.FlatSetReferences[$b])
                            $b++
                        }
                    } `
                    else
                    {
                        # Can't convert an empty object...
                    }
                    $ro.FlatSetReferences = $fsRefs

                    $attrs = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
                    if($null -ne $data.ProjectWiseObjects[$a].Attributes)
                    {
                        $mbrs = @($data.ProjectWiseObjects[$a].Attributes | Get-Member -MemberType NoteProperty)
                        $b = 0
                        while($b -lt $mbrs.Length)
                        {
                            if(-not [String]::IsNullOrEmpty($data.ProjectWiseObjects[$a].Attributes.$($mbrs[$b].Name)))
                            {
                                $attrs.Add($mbrs[$b].Name, $data.ProjectWiseObjects[$a].Attributes.$($mbrs[$b].Name))
                            } `
                            else
                            {
                                # Skip empty attributes
                            }
                            $b++
                        }
                    } `
                    else
                    {
                        # No worries.. no attributes to convert
                    }
                    $ro.Attributes = $attrs
                } `
                elseif($data.ProjectWiseObjects[$a].MyType -eq "ProjectWiseFolder")
                {
                    $pps = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
                    if($null -ne $data.PWFolder.ProjectProperties)
                    {
                        $mbrs = @($ro.ProjectProperties | Get-Member -MemberType NoteProperty)
                        $b = 0
                        while($b -lt $mbrs.Length)
                        {
                            if(-not [String]::IsNullOrEmpty($ro.ProjectProperties.$($mbrs[$b].Name)))
                            {
                                $pps.Add($mbrs[$b].Name, $ro.ProjectProperties.$($mbrs[$b].Name))
                            } `
                            else
                            {
                                # Skip empty properties
                            }
                            $b++
                        }
                    } `
                    else
                    {
                        # No worries...
                    }
                    $ro.ProjectProperties = $pps
                }
                $a++
            }
            ShowProgress -progressID 1 -complete
            $data.StorageAreas.Foreach({ $retval.StorageAreas.Add($_.Name, $_.Path) })
        } `
        else
        {
            $retval = $null
        }
    } `
    else
    {
        LogError ("Missing PW data file {0} in {1}." -f @($filePath, $me.Name))
    }

    return @(, $retval)
}

function MergePWData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData2
    )

    $a = 0
    $pwKeys = @($pwData2.ProjectWiseObjects.Keys)
    while($a -lt $pwKeys.Length)
    {
        if(-not $pwData.ProjectWiseObjects.ContainsKey($pwKeys[$a]))
        {
            $pwData.ProjectWiseObjects.Add($pwKeys[$a], $pwData2.ProjectWiseObjects[$pwKeys[$a]])
        } `
        else
        {
            if($null -eq $Script:dupPWObjects)
            {
                $Script:dupPWObjects = [System.Collections.Generic.List[GUID]]::new()
            } `
            else
            {
                # Nothing
            }
            $i = $Script:dupPWObjects.BinarySearch($pwKeys[$a])
            if($i -lt 0)
            {
                $Script:dupPWObjects.Insert(-bnot $i, $pwKeys[$a])
            } `
            else
            {
                # Nothing, no dups please.
            }

            $a++
        }
    }

    $i = $pwData.PWFolders.BinarySearch($pwData2.PWFolder.DocumentGUID)
    if($i -lt 0)
    {
        $pwData.PWFolders.Insert(-bnot $i, $pwData2.PWFolder.DocumentGUID)
    }
}

function LoadLatestPWData
{
    $me = $MyInvocation.MyCommand
    $retval = $null
    try
    {
        $latestPWDataExportFile = Get-ChildItem -File -Filter ("{0}_*_PWData.json" -f @($Script:projectName)) -Path ("{0}\{1}" -f @($Script:localPath, $Script:pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
    }
    catch
    {
        # No worries, no old viable path dictionary...
        $Error.Clear()
    }

    $retval = LoadPWDataFromJSON -filePath $latestPWDataExportFile.FullName

    return @(, $retval)
}

function NewMyProjectWiseFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [PWPS_DAB.CommonTypes+ProjectWiseFolder] $folder
    )

    $fpOld = $folder.FullPath
    $newNode = [PSCustomObject]@{
        MyType = "ProjectWiseFolder"
        FullPath = @($folder.FullPath -split "\\").ForEach({ $_ -replace $Script:IlegalCharactersInFoldersAndFilesRegEx, "_" }) -join "\"
        DocumentGUID = [Guid]::NewGuid()
        StorageFolder = $folder.StorageFolder
        Name = $folder.Name
        CreateDateTime = $folder.CreateDateTime
        UpdateDateTime = $folder.UpdateDateTime
        Description = $folder.Description
        FolderOwnerName = $folder.FolderOwnerName
        FolderCreatorName = $folder.FolderCreatorName
        FolderUpdaterName = $folder.FolderUpdaterName
        ProjectProperties = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
    }
    if($fpOld -ne $newNode.FullPath)
    {
        LogTrace ("Fixed illegal characters in FP.") -traceLevel 1
        LogTrace ("`tOld: {0}" -f @($fpOld)) -traceLevel 1
        LogTrace ("`tnew: {0}" -f @($newNode.FullPath)) -traceLevel 1
    }

    if($null -ne $folder.ProjectProperties)
    {
        @($folder.ProjectProperties.Keys).ForEach({
            if(-not [String]::IsNullOrEmpty($folder.ProjectProperties[$_]))
            {
                if(-not $newNode.ProjectProperties.ContainsKey($_))
                {
                    $newNode.ProjectProperties.Add($_, $folder.ProjectProperties[$_])
                } `
                else
                {
                    if($newNode.ProjectProperties[$_] -ne $folder.ProjectProperties[$_])
                    {
                        LogError ("Different project property values for [{0}].  Existing: [{1}], Different: [{2}]" -f @($_, $newNode.ProjectProperties[$_], $folder.ProjectProperties[$_]))
                    } `
                    else
                    {
                        # Nothing.
                    }
                }
            } `
            else
            {
                # Nothing, empty string...
            }
        })
    } `
    else
    {
        # Nothing, no project properties
    }

    return @(, $newNode)
}

function GetStorageDictionary
{
    $storageDict = [System.Collections.Generic.SortedDictionary[String, String]]::new()

    try
    {
        $sa = Get-PWStorageAreaList -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to get ProjectWise Storage Area list.")
    }

    if(-not $Script:HaveError)
    {
        $sa.Foreach({
            if(-not $storageDict.ContainsKey($_.Name))
            {
                $storageDict.Add($_.Name, $_.Path.Replace("/","\"))
            } `
            else
            {
                LogError ("Duplicate storage area name: {0}." -f @($_.Name))
            }
        })
    }

    return @(, $storageDict)
}

function GetPWDocumentAttributes
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $doc
    )

    try
    {
        # LogInfo ("Getting doc properties for: {0} version {1}" -f @($doc.FullPath, $doc.Version))
        $null = $doc.GetGeneralProperties()
    }
    catch
    {
        LogError ("Failed to retrieve general properties for {0}" -f @($doc.FullPath))
    }

    if(-not $Script:HaveError)
    {
        try
        {
            $null = $doc.GetCustomAttributes()
        }
        catch
        {
            LogError ("Failed to retrieve custom attributes for {0}" -f @($doc.FullPath))
        }
    } `
    else
    {
        # Should have already displayed an error
    }
}

function NewMyProjectWiseDocument
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [PWPS_DAB.CommonTypes+ProjectWiseDocument] $doc
    )

    $fpOld = $doc.FullPath
    $newNode = [PSCustomObject]@{
        MyType = "ProjectWiseDocument"
        FullPath = @($doc.FullPath -split "\\").ForEach({ $_ -replace $Script:IlegalCharactersInFoldersAndFilesRegEx, "_" }) -join "\"
        DocumentGUID = $doc.DocumentGUID
        StorageName = $doc.StorageName
        ProjectID = $doc.ProjectID
        Name = $doc.FileName
        Version = $doc.Version
        VersionSequence = $doc.VersionSequence
        FileSize = $doc.FileSize
        CreateDate = $doc.CreateDate
        FileUpdateDate = $doc.FileUpdateDate
        Status = $doc.Status
        Description = $doc.Description
        DocumentOwnerName = $doc.DocumentOwnerName
        DocumentCreatorName = $doc.DocumentCreatorName
        FileUpdaterName = $doc.FileUpdaterName
        DocumentOutTo = $doc.DocumentOutTo
        DocumentOutToName = $doc.DocumentOutToName
        WorkFlow = $doc.Workflow
        WorkFlowState = $doc.WorkflowState
        DocumentUpdaterName = $doc.DocumentUpdaterName
        DocumentUpdateDate = $doc.DocumentUpdateDate
        IsSet = $doc.IsSet
        IsFlatSetReference = $false
        FlatSetReferences = [System.Collections.Generic.List[Guid]]::new()
        Attributes = [System.Collections.Generic.SortedDictionary[String,Object]]::new()
    }
    if($fpOld -ne $newNode.FullPath)
    {
        LogTrace ("Fixed illegal characters in FP.") -traceLevel 1
        LogTrace ("`tOld: {0}" -f @($fpOld)) -traceLevel 1
        LogTrace ("`tnew: {0}" -f @($newNode.FullPath)) -traceLevel 1
    }

    if($newNode.FullPath -notmatch ("{0}$" -f @([Regex]::Escape($newNode.Name))))
    {
        #LogDebug ("FullPath missing FileName || GUID: {0}`tFullPath: [{1}]`tName: [{2}]`tFileName: [{3}]" -f @($doc.DocumentGUID, $doc.FullPath, $doc.Name, $doc.FileName))
        $fpPieces = $newNode.FullPath -split "\\"
        $newNode.FullPath = "{0}\{1}" -f @(($fpPieces[0..($fpPieces.Length - 2)] -join "\"), $newNode.Name)
        #LogDebug ("`tCorrected [{0}]" -f @($newNode.FullPath))
    } `
    else
    {
        # Nothing.
    }

    if($null -ne $doc.Attributes)
    {
        @($doc.Attributes).ForEach({
            $attrs = $_
            @($attrs.Keys).ForEach({
                if((-not [String]::IsNullOrEmpty($attrs[$_])) -and ($attrs[$_] -ne "null"))
                {
                    if(-not $newNode.Attributes.ContainsKey($_))
                    {
                        $newNode.Attributes.Add($_, $attrs[$_])
                    } `
                    else
                    {
                        if($newNode.Attributes[$_] -ne $attrs[$_])
                        {
                            LogError ("Different attribute values for [{0}].  Existing: [{1}], Different: [{2}]" -f @($_, $newNode.Attributes[$_], $attrs[$_]))
                        } `
                        else
                        {
                            # Nothing.
                        }
                    }
                }
            })
        })

        if($null -ne $doc.CustomAttributes)
        {
            @($doc.CustomAttributes.Keys).ForEach({
                if((-not [String]::IsNullOrEmpty($doc.CustomAttributes.Keys[$_])) -and ($attrs[$_] -ne "null"))
                {
                    if(-not $newNode.Attributes.ContainsKey($_))
                    {
                        $newNode.Attributes.Add($_, $doc.CustomAttributes.Keys[$_])
                    } `
                    else
                    {
                        if($newNode.Attributes[$_] -ne $doc.CustomAttributes.Keys[$_])
                        {
                            LogError ("Different custom attribute values for [{0}].  Existing: [{1}], Different: [{2}]" -f @($_, $newNode.Attributes[$_], $doc.CustomAttributes.Keys[$_]))
                        } `
                        else
                        {
                            # Nothing.
                        }
                    }
                }
            })
        } `
        else
        {
            # Nothing.
        }
    } `
    else
    {
        # Nothing, no attributes
    }

    return @(, $newNode)
}

function GetProjectWiseData
{
    $me = $MyInvocation.MyCommand

    $retval = [PSCustomObject]@{
        PWFolder = $null
        ProjectWiseObjects = [System.Collections.Generic.SortedDictionary[Guid, Object]]::new()
        Security = $null
        StorageAreas = $null
        PWFolders = [System.Collections.Generic.List[Guid]]::new()
    }

    $Error.Clear()

    $duplicateDocs = 0
    if([System.IO.Directory]::Exists($Script:localPath))
    {
        $pwPath = "{0}\{1}" -f @($Script:pwProjectPath, $Script:projectName)
        try
        {
            # Get the associated ProjectWise folder along with all the relevant data "-Slow" ...
            LogInfo ("Getting PW Folder for {0}..." -f @($pwPath))
            $pwFolder = Get-PWFolders -FolderPath $pwPath -JustOne -Slow 3> $null

            if($null -ne $pwFolder)
            {
                $newNode = NewMyProjectWiseFolder -folder $pwFolder
                $retval.PWFolder = $newNode
                $i = $retval.PWFolders.BinarySearch($newNode.DocumentGUID)
                if($i -lt 0)
                {
                    $retval.PWFolders.Insert(-bnot $i, $newNode.DocumentGUID)
                }
                $retval.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)
            } `
            else
            {
                LogError ("Failed to get ProjectWise project folder for {0} in {1}." -f @($pwPath, $me.Name))
            }
        }
        catch
        {
            LogError ("Failed to locate ProjectWise Folder using path: {0}" -f @($pwPath))
            $retval = $null
        }

        if(-not $Script:HaveError)
        {
            $retval.StorageAreas = GetStorageDictionary
        } `
        else
        {
            # Nothing, already displayed an error.
        }

        if((-not $Script:HaveError) -and ($null -ne $pwFolder))
        {
            # The code below looks odd, we are getting data, but returning it to $null.  The reason is,
            #    the code behind actaully populates $retval.PWFolder with the returned data.

            # Get the project folder security info
            if((-not $Script:HaveError) -and ($null -ne $pwFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    LogInfo "Getting project folder security..."
                    $retval.Security = @($pwFolder | Get-PWFolderSecurity -ErrorAction Stop | Where-Object { $_.WorkFlow -is [System.DBNull] } | Select-Object ProjectName,SecurityType,Type,Name,Access_Control_Settings,WorkFlow,State,InheritingFrom,FullPath)
                }
                catch
                {
                    LogError ("Failed to get project folder security details.")
                    $retval = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if((-not $Script:HaveError) -and ($null -ne $pwFolder))
            {
                try
                {
                    # Get a list of all the documents in the folder (includes subfolders)
                    LogInfo "Getting project document tree..."
                    $null = $pwFolder.GetTreeDocuments()
                }
                catch
                {
                    LogError ("Failed to get project documents.")
                    $retval = $null
                }
            } `
            else
            {
                # should have already logged an error
            }

            if((-not $Script:HaveError) -and ($null -ne $pwFolder))
            {
                #  NOTE:  Check for IsSet before GetGeneralProperties and GetCustomAttributes ....
                #     Need to know if they need to be successful before evaluting .IsSet...

                LogInfo "Getting project document properties and custom attributes..."
                # Now, populate all the attributes for the documents.
                $Script:reportData.Documents.ReportedFromProjectWise = $pwFolder.TreeDocuments.Count
                $totalDocuments = $pwFolder.TreeDocuments.Count
                $i = 0
                while((-not $Script:HaveError) -and ($null -ne $pwFolder) -and ($i -lt $pwFolder.TreeDocuments.Count))
                {
                    ShowProgress -progressID 1 -activity "Getting document properties and attributes" -counter $i -counterMax $totalDocuments

                    # Have to get the properties, or we don't see if it's a set or not.
                    GetPWDocumentAttributes -doc $pwFolder.TreeDocuments[$i]

                    if(-not $Script:HaveError)
                    {
                        $newNode = NewMyProjectWiseDocument -doc $pwFolder.TreeDocuments[$i]
                        if(-not $retval.ProjectWiseObjects.ContainsKey($newNode.DocumentGUID))
                        {
                            $retval.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)

                            if($pwFolder.TreeDocuments[$i].IsSet)
                            {
                                $flatSetNode = $newNode
                                $flatSetNode.FlatSetReferences = [System.Collections.Generic.List[Guid]]::new()
                                try
                                {
                                    $fs =  $pwFolder.TreeDocuments[$i] | Get-PWDocumentFlatSetMembers -ErrorAction Stop
                                }
                                catch
                                {
                                    LogError ("Failed to acquire flat set: {0} from {1}.  Index: {2}" -f @($pwFolder.TreeDocuments[$i].Name, $pwFolder.TreeDocuments[$i].FolderPath, $i))
                                }

                                if((-not $Script:HaveError) -and ($null -ne $fs))
                                {
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
                                                    if(-not $retval.ProjectWiseObjects.ContainsKey($allDocVersions[$r].DocumentGUID))
                                                    {
                                                        GetPWDocumentAttributes -doc $allDocVersions[$r]

                                                        if(-not $Script:HaveError)
                                                        {
                                                            $flatSetReferencedNode = NewMyProjectWiseDocument -doc $allDocVersions[$r]
                                                            $retval.ProjectWiseObjects.Add($flatSetReferencedNode.DocumentGuid, $flatSetReferencedNode)
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, already logged an error.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        $flatSetReferencedNode = $retval.ProjectWiseObjects[$allDocVersions[$r].DocumentGUID]
                                                    }

                                                    if(-not $Script:HaveError)
                                                    {
                                                        # Is this the actual version of the reference we need?
                                                        #   NOTE: Still need to add it to .ProjectWiseObjects so we can upload it, but right now, I just want to annotate if it's the real mccoy.
                                                        if($allDocVersions[$r].DocumentGUID -eq $fs[$q].DocumentGUID)
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
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already logged an error.
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
                                } `
                                else
                                {
                                    LogError ("No flat set returned from ProjectWise for document GUID {0} to flatset for {1} in {2}." -f @($pwFolder.TreeDocuments[$i].DocumentGUID, $pwFolder.TreeDocuments[$i].FullPath, $me.Name))
                                }
                            } `
                            else
                            {
                                # Not a flatset, so nothing to do here.
                            }
                        } `
                        else
                        {
                            $Script:reportData.Documents.DuplicatesFound++
                            $duplicateDocs++
                        }
                    } `
                    else
                    {
                        $retval = $null
                    }

                    $i++
                }
                LogInfo ("Duplicate documents: {0}" -f @($duplicateDocs))
                ShowProgress -progressID 1 -complete
            } `
            else
            {
                # Should have already displayed an error
            }

            try
            {
                # Get a list of all the subfolders in the project
                LogInfo "Getting project subfolders..."
                $null = $pwFolder.GetSubFolders()
            }
            catch
            {
                LogError ("Failed to get project subfolders.")
                $retval = $null
            }

            if((-not $Script:HaveError) -and ($null -ne $pwFolder) -and ($null -ne $pwFolder.SubFolders))
            {
                $Script:reportData.Folders.ReportedFromProjectWise = $pwFolder.SubFolders.Count
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $pwFolder.SubFolders.Count))
                {
                    $existingFolders = @(@($retval.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseFolder") -and ($_.FullPath -eq $pwFolder.SubFolders[$a].FullPath) }))
                    if($existingFolders.Length -eq 0)
                    {
                        $newNode = NewMyProjectWiseFolder -folder $pwFolder.SubFolders[$a]
                        while($retval.ProjectWiseObjects.ContainsKey($newNode.DocumentGUID))
                        {
                            $newNode.DocumentGUID = [Guid]::NewGuid()
                        }
                        $retval.ProjectWiseObjects.Add($newNode.DocumentGUID, $newNode)
                    } `
                    else
                    {
                        # Don't add duplicate folders.
                    }
                    $a++
                }
            } `
            else
            {
                # should have already logged an error
            }
        } `
        else
        {
            $retval = $null
        }
    } `
    else
    {
        LogError ("{0} not found.  Please provide an existing path." -f @($Script:localPath))
        $retval = $null
    }

    return @( ,$retval)
}

function ExportPWDataToJSON
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData
    )

    $me = $MyInvocation.MyCommand
    if([String]::IsNullOrEmpty($Script:pwDataExportPath))
    {
        $Script:pwDataExportPath = "{0}\{1}\{2}_{3}_PWData.json" -f @($Script:localPath, $Script:pwProjectPath, $Script:projectName, $Script:exportDateTime)
    } `
    else
    {
        # Nothing, already set it.
    }
    $d = [PSCustomObject]@{
        PWFolder = $pwData.PWFolder
        StorageAreas = @($pwData.StorageAreas.Keys).ForEach({
            $e = [PSCustomObject]@{
                Name = $_
                Path = $pwData.StorageAreas[$_]
            }
            $e
        })
        ProjectWiseObjects = @($pwData.ProjectWiseObjects.Values)
        PWFolders = @($pwData.PWFolders)
    }
    try
    {
        $d | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:pwDataExportPath -Force
    }
    catch
    {
        LogError ("Failed to export ProjectWise data for project {0}\{1} to {2} in {3}." -f @($Script:pwProjectPath, $Script:projectName, $Script:pwDataExportPath, $me.Name))
    }
}

function NewViablePathsNode
{
    $d = [PSCustomObject]@{
        GUID = $null      # Only used when exporting and importing viablePathsDict from file.
        Paths = $paths
        SourceObject = $null
        CopyOutPath = [String]::Empty
        SPData = [PSCustomObject]@{
            FolderName = [String]::Empty
            FileName = [String]::Empty
            SPFile = [PSCustomObject]@{
                ServerRelativeURL = [String]::Empty
                VersionLabel = [String]::Empty
                VersionProperties = $null
                VersionLinks = $null
            }
            Processed = $false
            Verified = $false
            DocVersionToLink = $null
            WhenUploaded = $null
            DocSetLinksCreated = [System.Collections.Generic.List[Guid]]::new()    # This flags whether or not the document set reference link was added to the document set.
        }
        IsFlatSetReference = $false  # If this document is referenced by a flatset, then we need version information for it.
    }

    return @(, $d)
}

function TranslateToDocLibName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $name
    )

    $retVal = $name
    if($name -match "Archive[d]* Projects")
    {
        $retval = "Inactive Projects"
    } `
    elseif($name -in @("Proposals - Archive", "Proposals - Active"))
    {
        $retval = "Proposal Archives"
    }

    return $retval
}

function ConnectToPW
{
    $me = $MyInvocation.MyCommand
    $pwConnected = -not [pwwrapper]::aaApi_IsConnectionLost()
    if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.ProjectWiseServer))
    {
        LogError ("Missing ProjectWise server in {0}." -f @($me.Name))
    } `
    else
    {
        # Nothing, continue
    }

    if(-not $Script:HaveError)
    {
        if([String]::IsNullOrEmpty($Script:pwDatasource))
        {
            LogError ("Missing ProjectWise data source name in {0}." -f @($me.Name))
        } `
        else
        {
            # Nothing, continue
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    if(-not $Script:HaveError)
    {
        if([String]::IsNullOrEmpty($Script:connData.ConnectionInformation.ProjectWiseUserName))
        {
            LogError ("Missing ProjectWise user name in {0}." -f @($me.Name))
        } `
        else
        {
            # Nothing, continue
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    $secPassword = $null
    if(-not $Script:HaveError)
    {
        if(-not [String]::IsNullOrEmpty($Script:pwPassword))
        {
            $secPassword = ConvertTo-SecureString -String $Script:pwPassword -AsPlainText -Force
        } `
        else
        {
            LogError ("Missing ProjectWise user name in {0}." -f @($me.Name))
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    if(-not $Script:HaveError)
    {
        $pwEnvironment = "{0}:{1}" -f @($Script:connData.ConnectionInformation.ProjectWiseServer, $Script:pwDatasource)

        if(-not $pwConnected)
        {
            try
            {
                LogInfo ("Connecting to ProjectWise...")
                $pwConnected = New-PWLogin -DatasourceName $pwEnvironment -UserName $Script:connData.ConnectionInformation.ProjectWiseUserName -Password $secPassword -ErrorAction Stop  # *> $null
                LogInfo ("`tconnected")
                $Script:connectedToPW = $true
            }
            catch
            {
                LogError ("Failed to connect to pw:\\{0}\{1} with user name: {2} in {3}." -f @($Script:connData.ConnectionInformation.ProjectWiseServer, $Script:pwDatasource, $Script:connData.ConnectionInformation.ProjectWiseUserName, $me.Name))
            }
        } `
        else
        {
            $Script:connectedToPW = $true
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    return ((-not $Script:HaveError) -and $pwConnected)
}

function NewPathDictNode
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $nodeName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $parentNode = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $srcObject = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Boolean] $isFixed = $false
    )

    $newNode = [PSCustomObject]@{
        OriginalName = $nodeName.Trim()
        ShortenedName = $nodeName.Trim()
        ParentNode = $parentNode
        IsFixed = $isFixed
        # The reason SourceObjects is not an object is because with document versions, there could be multiple documents with the same .FullPath.
        SourceObjects = [System.Collections.Generic.List[Object]]::new()
        Children = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
    }

    if($null -ne $srcObject)
    {
        $newNode.SourceObjects.Add($srcObject)
    } `
    else
    {
        # Nothing, no source object to add.
    }

    return @(, $newNode)
}

function GetLibraryDefinedFieldsList
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $libraryName
    )

    $me = $MyInvocation.MyCommand
    if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($libraryName))
    {
        BuildDocumentLibraryDictionary
    } `
    else
    {
        # Nothing, we have the library
    }

    if(-not $Script:HaveError)
    {
        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($libraryName))
        {
            $docLib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$libraryName]
            try
            {
                $df = Get-PnpField -List $docLib.Library -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to get document fields for {0} in {1}." -f @($docLib.Library.Title, $me.Name))
            }

            if(-not $Script:HaveError)
            {
                if($null -eq $Script:connData.DefinedFields)
                {
                    $Script:connData.DefinedFields = [System.Collections.Generic.SortedList[String,Object]]::new()
                } `
                else
                {
                    # Nothing, already made the dictionary.
                }

                if(-not $Script:connData.DefinedFields.ContainsKey($docLib.Library.Title))
                {
                    $Script:connData.DefinedFields.Add($docLib.Library.Title, $df)
                } `
                else
                {
                    $Script:connData.DefinedFields[$docLib.Library.Title] = $df
                }
            } `
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            LogError ("Missing document library {0} in {1}." -f @($libraryName, $me.Name))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

<#
    Given $propertyName, return the document field name corresponding to the property.
        If there is no defined field for the property create a new "text" document field for it.
#>
function GetSharePointDocumentFieldNameForProperty
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String] $libraryName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String] $propertyName
    )

    if($null -eq $Script:DefinedFieldTranslationDict)
    {
        $Script:DefinedFieldTranslationDict = [System.Collections.Generic.SortedDictionary[String,String]]::new()
    } `
    else
    {
        # Nothing, already created the dictionary.
    }
    $retval = [String]::Empty

    if($Script:DefinedFieldTranslationDict.ContainsKey($propertyName))
    {
        $retval = $Script:DefinedFieldTranslationDict[$propertyName]
    } `
    else
    {
        if(($null -eq $Script:connData.DefinedFields) -or ($libraryName -ne $Script:projectName))
        {
            GetLibraryDefinedFieldsList -libraryName $libraryName
        } `
        else
        {
            # Nothing, already have the defined fields...
        }

        if(-not $Script:HaveError)
        {
            if($Script:connData.documentFields.ContainsKey($propertyName))
            {
                $spFieldDef = $Script:connData.documentFields[$propertyName]
            } `
            else
            {
                $spFieldDef = $null
            }

            if($null -ne $spFieldDef)
            {
                # Fake the first pass at the loop if there is a .UseField value...
                $spFieldDef2 = $spFieldDef

                while((-not [String]::IsNullOrEmpty($spFieldDef.UseField)) -and ($null -ne $spFieldDef2))
                {
                    if($Script:connData.documentFields.ContainsKey($spFieldDef.UseField))
                    {
                        $spFieldDef2 = $Script:connData.documentFields[$spFieldDef.UseField]
                    } `
                    else
                    {
                        $spFieldDef2 = $null
                    }

                    if($null -ne $spFieldDef2)
                    {
                        $spFieldDef = $spFieldDef2
                    } `
                    else
                    {
                        # Nothing, $spFieldDef2 -eq $null will stop the loop
                    }
                }

                if(-not [String]::IsNullOrEmpty($spFieldDef.InternalName))
                {
                    $retval = $spFieldDef.InternalName
                } `
                else
                {
                    LogError ("Missing .InternalName for properties: {0} in {1}." -f @($propertyName, $me.Name))
                }
            } `
            else
            {
                # We'll have to create a new document field for this property, so just return the property's name.
                $retval = $propertyName
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }

        if(-not $Script:HaveError)
        {
            if(-not [String]::IsNullOrEmpty($retval))
            {
                $Script:DefinedFieldTranslationDict.Add($propertyName, $retval)
            } `
            else
            {
                LogError ("Missing property to document field translation for {0} in {1}." -f @($propertyName, $me.Name))
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }
    }

    return $retval
}

function TestForSPDocumentLibraryField
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $libraryName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $fieldName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String] $displayName = [String]::Empty
    )

    $me = $MyInvocation.MyCommand

    if($null -eq $Script:SPDocLibFieldDict)
    {
        $Script:SPDocLibFieldDict = [System.Collections.Generic.SortedDictionary[String, Object]]::new()
    } `
    else
    {
        # Nothing.
    }
    $newFieldParams = $null
    $key = "{0}_{1}" -f @($libraryName, $fieldName)
    if($Script:SPDocLibFieldDict.ContainsKey($key))
    {
        $newFieldParams = $Script:SPDocLibFieldDict[$key]
    } `
    else
    {
        <#
            I'll use a mutex to ensure only 1 script at a time can check for a document field and possibly create a new one.

            I only want to go back to SharePoint for defined fields if the document field I need to check belongs to a different project.
            Since I've converted project folders into document libraries, then there should rarely be a need to go back to SharePoint
            unless I'm looking at a different document library.
        #>
        $mutexName = "{0}_SPDocumentFieldTestMutex" -f @($libraryName)
        $spFieldTestMutex = [System.Threading.Mutex]::new($false, $mutexName)
        $spFieldDef = $null
        try
        {
            $null = $spFieldTestMutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...

            $library = $null
            if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($libraryName))
            {
                $library = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$libraryName]

                # If there is no defined field list, or I'm checking on another document library, get a fresh set of document fields.
                if(($null -eq $Script:connData.DefinedFields) -or ($libraryName -ne $Script:projectName))
                {
                    GetLibraryDefinedFieldsList -libraryName $libraryName
                } `
                else
                {
                    # Nothing, already have the defined fields...
                }

                if(-not $Script:HaveError)
                {
                    if([String]::IsNullOrEmpty($displayName))
                    {
                        $displayName = $fieldName
                    }
                    # In case we need to create another document field...
                    $newFieldParams = @{
                        List = $library.Library
                        InternalName = $fieldName
                        DisplayName = $displayName
                        Type = "Text"
                    }

                    if($Script:connData.documentFields.ContainsKey($fieldName))
                    {
                        $spFieldDef = $Script:connData.documentFields[$fieldName]
                    } `
                    else
                    {
                        $spFieldDef = $null
                    }
                    if($null -ne $spFieldDef)
                    {
                        # Fake the first pass at the loop if there is a .UseField value...
                        $spFieldDef2 = $spFieldDef

                        while((-not [String]::IsNullOrEmpty($spFieldDef.UseField)) -and ($null -ne $spFieldDef2))
                        {
                            if($Script:connData.documentFields.ContainsKey($spFieldDef.UseField))
                            {
                                $spFieldDef2 = $Script:connData.documentFields[$spFieldDef.UseField]
                            } `
                            else
                            {
                                $spFieldDef2 = $null
                            }

                            if($null -ne $spFieldDef2)
                            {
                                <#
                                if($Script:DoDebugging)
                                {
                                    LogDebug ("Using field: {0} for {1}" -f @($spFieldDef2.InternalName, $spFieldDef.InternalName))
                                }
                                #>
                                $spFieldDef = $spFieldDef2
                            } `
                            else
                            {
                                # Nothing, $spFieldDef2 -eq $null will stop the loop
                            }
                        }

                        if(-not [String]::IsNullOrEmpty($spFieldDef.InternalName))
                        {
                            $newFieldParams.InternalName = $spFieldDef.InternalName
                        } `
                        else
                        {
                            # No display name
                        }

                        if(-not [String]::IsNullOrEmpty($spFieldDef.DisplayName))
                        {
                            $newFieldParams.DisplayName = $spFieldDef.DisplayName
                        } `
                        else
                        {
                            # No display name
                        }

                        if(-not [String]::IsNullOrEmpty($spFieldDef.Type))
                        {
                            $newFieldParams.Type = $spFieldDef.Type
                        } `
                        else
                        {
                            # No display name
                        }

                        if($newFieldParams.Type -eq "Choice")
                        {
                            if($null -ne $spFieldDef.Choices)
                            {
                                $newFieldParams.Add("Choices", $spFieldDef.Choices)
                            } `
                            else
                            {
                                LogError ("Document field definition for choice {0} missing choices value in {1}." -f @($fieldName, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, not a choice...
                        }
                    } `
                    else
                    {
                        # Net new field we know nothing about...so default it to a text field.
                    }

                    # Here, $newFieldParams will be populated even if we aren't creating a new document field.

                    if($Script:connData.DefinedFields.ContainsKey($libraryName))
                    {
                        $spField = $Script:connData.DefinedFields[$libraryName] | Where-Object { $_.InternalName -eq $newFieldParams.InternalName }
                    } `
                    else
                    {
                        $spField = $null
                    }

                    if(($null -eq $spField) -and (($null -eq $spFieldDef) -or (-not $spFieldDef.Ignore)))
                    {
                        <#
                        if($Script:DoDebugging)
                        {
                            LogDebug ("Adding document field: {0} to libary {1}." -f @($newFieldParams.InternalName, $librayName))
                            @($newFieldParams.Keys).ForEach({ LogDebug ("`t{0}: {1}" -f @($_, $newFieldParams[$_])) })
                        }
                        #>
                        try
                        {
                            $newField = Add-PnpField @newFieldParams -ErrorAction Stop
                            if($null -ne $newField)
                            {
                                # Refresh the list of document fields for this library ...
                                GetLibraryDefinedFieldsList -libraryName $libraryName

                                # Test to see if the field was added...
                                if($Script:connData.DefinedFields.ContainsKey($libraryName))
                                {
                                    $spField2 = $Script:connData.DefinedFields[$libraryName] | Where-Object { $_.InternalName -eq $newFieldParams.InternalName }
                                } `
                                else
                                {
                                    $spField2 = $null
                                }

                                if($null -ne $spField2)
                                {
                                    if($Script:DoDebugging)
                                    {
                                        # LogDebug ("Successfully added field: {0}." -f @($newFieldParams.InternalName))
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to verify creation of document field: {0} in {1}." -f @($newFieldParams.InternalName, $me.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Failed to create new document field (null field returned): {0} in {1}." -f @($newFieldParams.InternalName, $me.Name))
                            }
                        }
                        catch
                        {
                            LogError ("Failed to create new document field (null field returned): [{0}] in {1}." -f @($newFieldParams.InternalName, $me.Name))
                        }
                    } `
                    else
                    {
                        <#
                        if($Script:DoDebugging)
                        {
                            LogDebug ("Document field: {0}:{1} already exists." -f @($libraryName, $newFieldParams.InternalName))
                        }
                        #>
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Missing library {0} in {1}." -f @($libraryName, $me.Name))
            }
        }
        finally   # No matter what happens, make sure to release the mutex...
        {
            $null = $spFieldTestMutex.ReleaseMutex()  # All done, let others play...
            $null = $spFieldTestMutex.Dispose()
        }

        $ignore = $false
        if($null -ne $spFieldDef)
        {
            $ignore = $spFieldDef.Ignore
        } `
        else
        {
            # Nothing
        }
        if($null -ne $newFieldParams)
        {
            if(-not $newFieldParams.ContainsKey("Ignore"))
            {
                $newFieldParams.Add("Ignore", $ignore)
            } `
            else
            {
                $newFieldParams["Ignore"] = $ignore
            }
        }

        $Script:SPDocLibFieldDict.Add($key, $newFieldParams)
    }

    return @(, $newFieldParams)
}

function CheckAndFixDocLibFields
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $projName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $existingProject
    )

    LogInfo ("Checking document fields for project {0}" -f @($projName))
    $missingFields = [System.Collections.Generic.List[String]]::new()
    if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($projName))
    {
        $library = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$projName]
        if($null -ne $library.Library)
        {
            $docLibFields = Get-PnpField -List $library.Library -ErrorAction Stop

            if($null -ne $docLibFields)
            {
                $dfKeys = @($Script:connData.documentFields.Keys)
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $dfKeys.Length))
                {
                    $df = $Script:connData.documentFields[$dfKeys[$a]]
                    if($df.CreateWithNewLibrary)
                    {
                        if($docLibFields.Where({ $_.InternalName -eq $df.InternalName }).Count -ne 1)
                        {
                            $missingFields.Add($dfKeys[$a])
                        }
                    }
                    $a++
                }

                if($existingProject.IsPresent)
                {
                    $a = 0
                    while((-not $Script:HaveError) -and ($a -lt $Script:fieldsToCreateForExistingProjects.Length))
                    {
                        if($docLibFields.Where({ $_.InternalName -eq $Script:fieldsToCreateForExistingProjects[$a] }).Count -ne 1)
                        {
                            $missingFields.Add($Script:fieldsToCreateForExistingProjects[$a])
                        }
                        $a++
                    }
                }

                if($missingFields.Count -gt 0)
                {
                    LogWarning ("Missing document fields for project {0}" -f @($projName))
                    LogWarning ("{0}" -f @(($missingFields -join ", ")))

                    LogWarning ("Attempting to create missing fields.")
                    $a = 0
                    while((-not $Script:HaveError) -and ($a -lt $missingFields.Count))
                    {
                        ShowProgress -progressID 1 -activity "Creating missing fields" -counter $a -counterMax $missingFields.Count -statusSuffix $missingFields[$a]

                        $fld = TestForSPDocumentLibraryField -libraryName $library.Library.Title -fieldName $missingFields[$a]

                        $a++
                    }
                    ShowProgress -progressID 1 -complete

                    if(-not $Script:HaveError)
                    {
                        CheckAndFixDocLibFields -projName $projName -existingProject:$existingProject
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    LogInfo ("All document fields are intact for {0}." -f @($projName))
                }
            } `
            else
            {
                LogWarning ("No document fields for {0}." -f @($projName))
            }
        } `
        else
        {
            LogWarning ("Null library for {0}." -f @($projName))
        }
    } `
    else
    {
        LogWarning ("Missing document library for project {0}." -f @($projName))
    }
}

function CreateProjectDocumentLibrary
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $newDocLibName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $forExistingProject
    )

    $me = $MyInvocation.MyCommand
    # First test to see if the library already exists.
    $libExists = $false

    LogInfo ("Checking for project document library '{0}'." -f @($newDocLibName))
    # Do we have existing info for the library?
    if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($newDocLibName))
    {
        # Test to see if the library exists..
        try
        {
            $newDocLib = Get-PnPList -Identity $newDocLibName -ErrorAction Stop
            LogInfo ("`tlibrary found")
            $libExists = $true
        }
        catch
        {
            if(($Error.Count -gt 0) -and ($Error[0].Exception.Message -match "does not exist"))
            {
                $Error.Clear()
                # No big deal need to create the library.
                LogInfo ("`tlibrary not found")
            }
        }

        # Do not create a document library if we are processing a proposal.
        if(-not $libExists)
        {
            if(-not $Script:isProposal.IsPresent)
            {
                # try to create a new document library
                LogInfo ("Creating new document library '{0}'." -f @($newDocLibName))
                try
                {
                    $newDocLib = New-PnPList -Title $newDocLibName -Template "DocumentLibrary" -EnableVersioning -EnableContentTypes -ErrorAction Stop

                    $null = Set-PnpList -Identity $newDocLib.Title -BreakRoleInheritance
                    $null = Set-PnpListPermission -Identity $newDocLib.Title -Group "SP-Government Services Owners" -AddRole "Full Control"

                    LogInfo ("`tlibrary created")
                }
                catch
                {
                    LogError ("Failed to create document library {0} in {1}." -f @($newDocLibName, $me.Name))
                    $libExists = $false
                }

                if(-not $Script:HaveError)
                {
                    # Retest to make sure the library is there.
                    try
                    {
                        LogInfo ("Verifying project document library '{0}' exists." -f @($newDocLibName))
                        $newDocLib = Get-PnPList -Identity $newDocLibName -ErrorAction Stop
                        $libExists = $true
                        LogInfo ("`tlibrary exists.")
                    }
                    catch
                    {
                        LogError ("Failed verify creation of new document library {0} in {1}." -f @($newDocLibName, $me.Name))
                    }

                    if((-not $Script:HaveError) -and $libExists)
                    {
                        # Let's rebuild the document library dictionary to pick up the library, perhaps it was created after the initial call to BuildDocumentLibraryDictionary (outside this script)
                        BuildDocumentLibraryDictionary
                        GetLibraryDefinedFieldsList -libraryName $newDocLib.Title
                    } `
                    else
                    {
                        # nothing, already logged an error.
                    }

                    if(-not $Script:HaveError)
                    {
                        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($newDocLibName))
                        {
                            # Have the library...
                            if($newDocLibName -notmatch "Proposals")
                            {
                                LogInfo ("Creating key document fields in document library '{0}'." -f @($newDocLibName))
                                CheckAndFixDocLibFields -projName $newDocLibName -existingProject:$forExistingProject
                                if(-not $Script:HaveError)
                                {
                                    # Reload the library dictionary and defined fields...
                                    GetLibraryDefinedFieldsList -libraryName $newDocLibName
                                } `
                                else
                                {
                                    # Nothing, already logged an error
                                }
                            } `
                            else
                            {
                                # Nothing, skip making the document fields for Proposals until I know better.
                            }
                        } `
                        else
                        {
                            LogError ("New document library '{0}' not available in library dictionary in {1}." -f @($newDocLibName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Processing a proposal and tried to create document library {0} in {1}." -f @($newDocLibName, $me.Name))
            }
        } `
        else
        {
            # Nothing, well, still need to check document fields.
        }
    } `
    else
    {
        LogInfo ("Document library '{0}' already exists." -f @($newDocLibName))
        # Library already exists, but we should check on the document fields.... below
    }
}

function SourceObjectIdentity
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Object] $srcObj
    )

    $so = ($null -ne $srcObj.SourceObject) ? $srcObj.SourceObject : $srcObj
    return "[{0}]:[{1}]" -f @($so.DocumentGUID, $so.FullPath)
}

function AddPWDocumentToPathDict
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[[String],[Object]]] $testPaths,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [Object] $obj2Upload,       # Here, $obj2Upload is the SourceObject....

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[Object]] $newFolders,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $CreateMissingLibrary
    )

    $me = $MyInvocation.MyCommand

    if(-not [String]::IsNullOrEmpty($obj2Upload.FullPath))
    {
        $fullPathParts = $obj2Upload.FullPath -split "\\"

        if($fullPathParts.Length -gt 0)
        {
            if(-not [String]::IsNullOrEmpty($fullPathParts[0]))
            {
                # This is for the "pwProjectPath" document library ... Active Projects/Inactive Projects...
                $spDocName = TranslateToDocLibName -name $fullPathParts[0]
                if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($spDocName))
                {
                    if($CreateMissingLibrary.IsPresent)
                    {
                        # Need to create the document library...
                        CreateProjectDocumentLibrary -newDocLibName $spDocName
                    } `
                    else
                    {
                        # Don't create the library
                    }
                } `
                else
                {
                    # When I know, I'll fix this.
                }

                if((-not $Script:isProposal.IsPresent) -and ($fullPathParts.Length -gt 1) -and (-not [String]::IsNullOrEmpty($fullPathParts[1])))
                {
                    # This is for the project name document library
                    if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($fullPathParts[1]))
                    {
                        if($CreateMissingLibrary.IsPresent)
                        {
                            # Need to create the document library...
                            CreateProjectDocumentLibrary -newDocLibName $fullPathParts[1]
                        } `
                        else
                        {
                            # Don't create the library
                        }
                    } `
                    else
                    {
                        # When I know, I'll fix this.
                    }
                } `
                else
                {
                    # Nothing, this is just the pwProjectPath folder...or we are processing proposals
                }

                if(-not $Script:HaveError)
                {
                    $a = 0
                    $tdAdded = $false

                    while((-not $Script:HaveError) -and (-not $tdAdded) -and ($a -lt $fullPathParts.Length))
                    {
                        $parentNode = $null

                        if(-not [String]::IsNullOrEmpty($fullPathParts[$a]))
                        {
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
                                    $srcObject = $obj2Upload
                                    $tdAdded = $true
                                } `
                                else
                                {
                                    # No... then we need a real projectwise folder for the source object....

                                    # First, see if there is a subfolder in the project
                                    $potentialFullPath = $fullPathParts[0..$a] -join "\"

                                    if($pwData.PWFolder.FullPath -eq $potentialFullPath)
                                    {
                                        $srcObject = $pwData.PWFolder
                                    } `
                                    else
                                    {
                                        $existingFolders = @(@($pwData.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseFolder") -and ($_.FullPath -eq $potentialFullPath) }))
                                        if($existingFolders.Length -gt 0)
                                        {
                                            $srcObject = $existingFolders[0]
                                        } `
                                        else
                                        {
                                            # Check the new folders to see if there is a match there... I don't see how it could, but check anyway.
                                            $existingFolders = @(@($newFolders).Where({ ($_.MyType -eq "ProjectWiseFolder") -and ($_.FullPath -eq $potentialFullPath) }))
                                            if($existingFolders.Length -gt 0)
                                            {
                                                $srcObject = $existingFolders[0]
                                            } `
                                            else
                                            {
                                                # We need to get the folder from ProjectWise.
                                                try
                                                {
                                                    $sf = $null
                                                    if(-not $Script:connectedToPW)
                                                    {
                                                        ConnectToPW
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already connected
                                                    }

                                                    if(-not $Script:HaveError)
                                                    {
                                                        $sf = Get-PWFolders -FolderPath $potentialFullPath -JustOne -Slow -ErrorAction Stop 3> $null

                                                        if($null -ne $sf)
                                                        {
                                                            $newFolder = NewMyProjectWiseFolder -folder $sf
                                                            $newFolders.Add($newFolder)
                                                            $srcObject = $newFolder
                                                            # Don't add the new folder yet, it will mess up the loop in CreatePathDictionary
                                                        } `
                                                        else
                                                        {
                                                            LogError ("Failed to retrieve folder {0} from ProjectWise in {1}.  Null value returned." -f @($potentialFullPath, $me.Name))
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already logged a error message
                                                    }
                                                }
                                                catch
                                                {
                                                    LogError ("Failed to retrieve folder {0} from ProjectWise in {1}." -f @($potentialFullPath, $me.Name))
                                                }
                                            }
                                        }
                                    }
                                }

                                if((-not $Script:HaveError) -and ($null -ne $srcObject))
                                {
                                    $nodeName = $fullPathParts[$a].Trim()
                                    if($testPaths.ContainsKey($nodeName))
                                    {
                                        $testPaths[$nodeName].SourceObjects.Add($srcObject)
                                    } `
                                    else
                                    {
                                        $newNode = NewPathDictNode -nodeName $fullPathParts[$a] -parentNode $parentNode -isFixed (($a -eq 0) -or ($a -eq 1)) -srcObject $srcObject
                                        $testPaths.Add($newNode.OriginalName, $newNode)
                                    }
                                } `
                                else
                                {
                                    LogError ("Attempt to add new path dict node with no source object in {0}." -f @($me.Name))
                                    LogError ("`tfull path part: {0}" -f @($obj2Upload.FullPath))
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
                                        if($obj2Upload.MyType -eq "ProjectWiseFolder")
                                        {
                                            $existingSrcObject = $parentNode[$fullPathParts[-1]].SourceObjects | Where-Object { ($_.MyType -eq "ProjectWiseFolder") -and ($_.FullPath -eq $obj2Upload.FullPath) }
                                        } `
                                        else
                                        {
                                            $existingSrcObject = $parentNode[$fullPathParts[-1]].SourceObjects | Where-Object { ($_.MyType -eq "ProjectWiseDocument") -and ($_.DocumentGUID -eq $obj2Upload.DocumentGuid) }
                                        }

                                        if($null -eq $existingSrcObject)
                                        {
                                            $parentNode[$fullPathParts[-1]].SourceObjects.Add($obj2Upload)
                                        } `
                                        else
                                        {
                                            # Nothing, don't add the same source object more than once.
                                            if($Script:DoDebugging)
                                            {
                                                # LogInfo ("Duplicate TD: {0}" -f @($obj2Upload.SourceObject.FullPath))
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
                                    LogError ("`tFullPath: {0}" -f @($obj2Upload.FullPath))
                                }
                                # Nothing, at the end of the path...
                            }
                        } `
                        else
                        {
                            LogError ("Empty full path part at idx {0} for {1} in {2}." -f @($a, $obj2Upload.FullPath, $me.Name))
                        }
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Missing projects document library part of full path for {0}:{1} in {2}." -f @($obj2Upload.DocumentGUID, $obj2Upload.Name, $me.Name))
            }
        } `
        else
        {
            LogError ("Malformed full path for {0} in {1}." -f @((SourceObjectIdentity -srcObj $obj2Upload), $me.Name))
        }
    } `
    else
    {
        LogError ("Missing full path for {0} in {1}." -f @((SourceObjectIdentity -srcObj $obj2Upload), $me.Name))
    }

    # Now all the subfolders and file name have been added to $testPath.
}

function CreatePathDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $CreateMissingLibrary
    )

    # Build another dictionary used to shorten paths.
    # $testPaths = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()

    # Create the dictionary root
    $topPaths = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new()
    $newNode = NewPathDictNode -nodeName "ROOT" -isFixed $true -parentNode $null -srcObject $null
    $topPaths.Add($newNode.OriginalName, $newNode)

    $newFolders = [System.Collections.Generic.List[Object]]::new()
    $Error.Clear()

    $a = 0
    $objsInOrder = @(@($pwData.ProjectWiseObjects.Values) | Sort-Object FullPath, VersionSequence)
    while((-not $Script:HaveError) -and ($a -lt $objsInOrder.Length))
    {
        ShowProgress -progressID 1 -activity "Adding objects to path dictionary" -counter $a -counterMax $objsInOrder.Length

        #    $testPaths = $topPaths["ROOT"].Children; $obj2Upload = $objsInOrder[$a]; $newFolders = $newFolders
        AddPWDocumentToPathDict -pwData $pwData -testPaths $topPaths["ROOT"].Children -obj2Upload $objsInOrder[$a] -newFolders $newFolders -CreateMissingLibrary:$CreateMissingLibrary
        $a++
    }
    ShowProgress -progressID 1 -complete

    $newFolders | ForEach-Object {
        if(-not $pwData.ProjectWiseObjects.ContainsKey($_.DocumentGUID))
        {
            $pwData.ProjectWiseObjects.Add($_.DocumentGUID, $_)
        }
    }

    return @(($newFolders.Count -gt 0) , $topPaths)
}

function GetLibraryURL
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $name
    )

    $url = [String]::Empty
    if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($name))
    {
        $url = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$name].Library.RootFolder.ServerRelativeUrl
    } `
    else
    {
        LogWarning ("No document library name {0} in {1}." -f @($name, $me.Name))
    }

    return $url
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
        [AllowEmptyString()]
        [String] $originalParentPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[String]] $pathsTooLong,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.SortedDictionary[String,String]] $pathTooLongToOriginalPath
    )

    $me = $MyInvocation.MyCommand

    $a = 0
    $keys = @($fromNode.Keys)
    while((-not $Script:HaveError) -and ($a -lt $keys.Length))
    {
        # If this is the start of a path, then we need to get the library URL length for it...
        if([String]::IsNullOrEmpty($originalParentPath))
        {
            $docLibURL = GetLibraryURL -name (TranslateToDocLibName -name $keys[$a])
            if(-not [String]::IsNullOrEmpty($docLibURL))
            {
                $pathToTest = $docLibURL.Trim("/")
            } `
            else
            {
                if(-not $Script:DoExport.IsPresent)
                {
                    LogWarning ("Missing document library URL for {0} in {1}.  Assuming library name..." -f @($keys[$a], $me.Name))
                    $pathToTest = $keys[$a]
                } `
                else
                {
                    LogWarning ("Missing document library URL for {0} in {1}." -f @($keys[$a], $me.Name))
                }
            }
        } `
        else
        {
            # Only add this node's names to the variables if we've already resolved the document library name
            $originalPath = $originalParentPath + $fromNode[$keys[$a]].OriginalName
            $pathToTest = $parentPath + $fromNode[$keys[$a]].ShortenedName
        }

        if(-not $Script:HaveError)
        {
            # Write-Host ("TPL: {0}`tTP: {1}" -f @($pathToTest.Length, $pathToTest))
            if($pathToTest.Length -gt $Script:MAX_SP_DOC_PATH_LEN)
            {
                $pathsTooLong.Add($pathToTest)
                if(-not $pathTooLongToOriginalPath.ContainsKey($pathToTest))
                {
                    $pathTooLongToOriginalPath.Add($pathToTest, $originalPath)
                } `
                else
                {
                    LogError ("Duplicate path {0} too long key in {1}." -f @($pathToTest, $me.Name))
                }
            } `
            else
            {
                # Nothing, the test path is not too long.
            }

            if($null -ne $fromNode[$keys[$a]].Children)
            {
                @($fromNode[$keys[$a]].Children).ForEach({
                    if(-not $Script:HaveError)
                    {
                        GetPathsTooLongFromDictionary -fromNode $_ -parentPath ($pathToTest + "/") -originalParentPath ($originalPath + "/") -pathsTooLong $pathsTooLong -pathTooLongToOriginalPath $pathTooLongToOriginalPath
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                })
            } `
            else
            {
                # Nothing....
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }

        $a++
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
        $fromNode[$keys[$a]].ShortenedName = $fromNode[$keys[$a]].OriginalName

        # Now revert all of the children's children...
        #@($fromNode[$originalName].Children).ForEach({
            RevertToOriginal -fromNode $fromNode[$keys[$a]].Children
        #})

        $a++
    }
}

function FixLongPaths
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pathDict
    )

    $pathTooLongToOriginalPath = [System.Collections.Generic.SortedDictionary[String,String]]::new()
    $pathsTooLong = [System.Collections.Generic.List[String]]::new()
    # $pathsTooLong | Set-Clipboard

    GetPathsTooLongFromDictionary -fromNode $pathDict["ROOT"].Children -parentPath "" -originalParentPath "" -pathsTooLong $pathsTooLong -pathTooLongToOriginalPath $pathTooLongToOriginalPath

    if(-not $Script:HaveError)
    {
        # GetPathsTooLongFromDictionary -fromNode $pathDict -parentPath "" -pathsTooLong $pathsTooLong -maxLength ($Script:MAX_SP_DOC_PATH_LEN - $spLimitPrefixLength + 1)
        $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending)
        # $pathsTooLong is now an array....

        $maxLongPaths = $pathsTooLong.Length
        while((-not $Script:HaveError) -and ($pathsTooLong.Length -gt 0))
        {
            ShowProgress -progressID 1 -activity "Fixing paths too long" -counter ($maxLongPaths - $pathsTooLong.Length) -counterMax $maxLongPaths -statusSuffix $pathsTooLong[0]

            if($pathTooLongToOriginalPath.ContainsKey($pathsTooLong[0]))
            {
                $originalPath = $pathTooLongToOriginalPath[$pathsTooLong[0]]
                $originalPathPieces = @($originalPath -split "/")

                if(($pathsTooLong[0].Length + 1) -gt $Script:MAX_SP_DOC_PATH_LEN)
                {
                    $pathPieces = $pathsTooLong[0].Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)

                    <#
                        Don't change any of the following:

                        $pathPieces[0] = sites
                        $pathPieces[1] = SharePointSiteName
                        $pathPieces[2] = Document Library
                        $pathPieces[3] = Project Folder
                    #>
                    if($pathPieces.Length -gt 4)
                    {
                        $docLibURL = $originalPathPieces[0..2] -join "/"
                        $docLibName = @($Script:connData.ConnectionInformation.SharePointDocumentLibraries.Keys).Where({ $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$_].Library.RootFolder.ServerRelativeURL -eq ("/" + $docLibURL)  })
                        if($null -ne $docLibName)
                        {
                            $docLibName = $docLibName.Normalize()
                        }
                        if(-not [String]::IsNullOrEmpty($docLibName))
                        {
                            if($pathDict["ROOT"].Children.ContainsKey($docLibName))
                            {
                                # The first 2 placeholders in the path are always fixed....
                                $longestPiece = ($pathPieces | Select-Object -Skip 4) | Sort-Object Length -Descending | Select-Object -First 1
                                $longestPieceIdx = $pathPieces.IndexOf($longestPiece)
                                $lpMinLength = 2

                                # $node = $pathDict
                                $node = $pathDict["ROOT"].Children[$docLibName].Children
                                $c = 3   # Start after the document library name....
                                while(($null -ne $node) -and (-not $Script:HaveError) -and ($c -lt $longestPieceIdx))
                                {
                                    if($node.ContainsKey($originalPathPieces[$c]))
                                    {
                                        $node = $node[$nodeKeyToTestFor].Children
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
                                            $longestPiece += $Script:COUNTER_CHARACTERS[$i]
                                            $i++
                                            if($i -eq $Script:COUNTER_CHARACTERS.Length)
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
                                } while((-not $Script:HaveError) -and ($x -lt ($originalLP.Length - 3)) -and ($i -lt $Script:COUNTER_CHARACTERS.Length) -and ($longestPiece.Length -gt $lpMinLength) -and ($isDuplicate))

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
                                                    @($node[$longestPiece].Children).ForEach({ RevertToOriginal -fromNode $_ })
                                                } `
                                                else
                                                {
                                                    # Nothing, no children to revert.
                                                }

                                                # If this was not a file node, then rebuild the list of paths which are too long...
                                                $pathsTooLong = [System.Collections.Generic.List[String]]::new()   # Can't just clear $pathsTooLong....it's an array...

                                                $pathTooLongToOriginalPath.Clear()
                                                GetPathsTooLongFromDictionary -fromNode $pathDict["ROOT"].Children -parentPath "" -originalParentPath "" -pathsTooLong $pathsTooLong -pathTooLongToOriginalPath $pathTooLongToOriginalPath
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
                                        $pathsTooLong = @($pathsTooLong | Sort-Object Length -Descending | Where-Object { ($_.Length + 1) -gt $Script:MAX_SP_DOC_PATH_LEN })
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
                                LogError ("Missing document library node for `"{0}`" in `$pathDict[`"ROOT`"].Children in {1}." -f @($docLibName, $me.Name))
                            }
                        } `
                        else
                        {
                            LogError ("Unable to determine document library name in {0}." -f @($me.Name))
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

        if(($Script:HaveError) -or ($maxLongPaths -gt 0))
        {
            ShowProgress -progressID 1 -complete
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

function BuildViablePathsDictionary
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

    <#
        Builds the viable path dictionary to the new standard.
        .Paths[0] = Document Library (or folder)
        .Paths[1] = First folder Name (if [0] is a document library) - this could also be the file name if a file exists in the root of a project folder.
        .Paths[-1] = File name if the source object is a ProjectWiseDocument, other wise it's the final piece of the complete folder.
    #>

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
    while((-not $Script:HaveError) -and ($a -lt $keys.Length))
    {
        $pathToTest = $parentPath + $fromNode[$keys[$a]].ShortenedName

        if($fromNode[$keys[$a]].SourceObjects.Count -gt 0)
        {
            $b = 0
            while((-not $Script:HaveError) -and ($b -lt $fromNode[$keys[$a]].SourceObjects.Count))
            {
                $so = $fromNode[$keys[$a]].SourceObjects[$b]

                if(-not [String]::IsNullOrEmpty($pathToTest))
                {
                    $paths = @(@($pathToTest -split "/").ForEach({ $_.Trim() }))
                    # [0] = Archive[d]|Active project, etc....
                    # [1] = the project name... i.e. the library name.

                    if($paths.Length -ge 2)
                    {
                        if($paths[0] -match "^(Active|Archive[d]*) Projects")
                        {
                            <#
                                If $paths =
                                    [0] "Active Projects"
                                    [1] "160075"            <----- document library name, needs to be $paths[0]
                                    [2] "somefolder"
                                    [3] "somefile.ext"

                                then remove [0]
                            #>

                            # Remove "^(Active|Archive[d]*) Projects")...
                            $paths = @($paths | Select-Object -Skip 1)
                        } `
                        else
                        {
                            # No changes
                        }

                        # If we are on the project folder parent, i.e. "Archive Projects" then skip it...
                        #  Notice above, we might have removed [0] if it's a pwProjectPath...
                        if($paths.Length -ge 1)
                        {
                            $paths[0] = TranslateToDocLibName -name $paths[0]
                            $d = NewViablePathsNode
                            $d.Paths = $paths
                            $d.SourceObject = $fromNode[$keys[$a]].SourceObjects[$b]

                            # If this source object is a document, then check to see if there is a flatset that references it.
                            $d.IsFlatSetReference = ($fromNode[$keys[$a]].SourceObjects[$b].MyType -eq "ProjectWiseDocument") -and ($fromNode[$keys[$a]].SourceObjects[$b].IsFlatSetReference)    # If this document is referenced by a flatset, then we need version information for it.

                            # Now we can update .SPData.FolderName and .SPData.FileName
                            if($so.MyType -eq "ProjectWiseDocument")
                            {
                                # Remember, $paths[0] is the library name
                                # Minimum is [0] doc library, [1] file name....
                                if($paths.Length -ge 2)
                                {
                                    if($paths.Length -eq 1)
                                    {
                                        LogError ("WTF!!  Is there a file above a project folder???  {0} in {1}." -f @((SourceObjectIdentity -srcObj $d), $me.Name))
                                    } `
                                    elseif($paths.Length -eq 2)
                                    {
                                        $d.SPData.FolderName = [String]::Empty
                                        $d.SPData.FileName = $paths[1]
                                    } `
                                    else
                                    {
                                        $d.SPData.FolderName = @($paths | Select-Object -Skip 1 -Last ($paths.Length - 2)) -join "/"
                                        $d.SPData.FileName = $paths[-1]
                                    }

                                    if((-not [String]::IsNullOrEmpty($d.SPData.FileName)) -and ($d.SPData.FileName.StartsWith(".")))
                                    {
                                        $newName = "noname{0}" -f @($d.SPData.FileName)
                                        if($d.Paths[-1] -eq $d.SPData.FileName)
                                        {
                                            $d.Paths[-1] = $newName
                                        }
                                        $d.SPData.FileName = $newName
                                    } `
                                    else
                                    {
                                        # Nothing, leave it alone
                                    }
                                } `
                                else
                                {
                                    LogWarning ("File path too short. (length = {0}) for {1}:{2} in {3}." -f @($paths.Length, $d.SourceObject.MyType, (SourceObjectIdentity -srcObj $d), $me.Name))
                                }
                            } `
                            elseif($so.MyType -eq "ProjectWiseFolder")
                            {
                                $d.SPData.FileName = [String]::Empty
                                if($paths.Length -ge 2)
                                {
                                    # Remember, $paths[0] is the library name
                                    if($paths.Length -eq 2)
                                    {
                                        $d.SPData.FolderName = $paths[1]
                                    } `
                                    else
                                    {
                                        $d.SPData.FolderName = @($paths | Select-Object -Skip 1) -join "/"
                                    }
                                } `
                                else
                                {
                                    # No worries, this is just another project folder and it will get it's own document library.
                                    # LogError ("Folder path too short. (length = {0}) for {1}:{2} in {3}." -f @($paths.Length, $d.SourceObject.DocumentGUID, $d.SourceObject.FullPath, $me.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Unknown source object type '{0}' for {1}:{2} in {3}." -f @($d.SourceObject.MyType, $d.SourceObject.DocumentGUID, $d.SourceObject.FullPath, $me.Name))
                            }

                            if(-not $Script:HaveError)
                            {
                                $allTestPaths.Add($fromNode[$keys[$a]].SourceObjects[$b].DocumentGUID, $d)
                            } `
                            else
                            {
                                # Nothing, already logged an error...
                            }
                        } `
                        else
                        {
                            # Nothing, skip the project folder's parent
                        }
                    } `
                    else
                    {
                        # No worries, I don't need a viable path a project folder.... it will be the document library...
                        # LogError ("Malformed path for {0}:{1} in {2}.  Not enough path pieces." -f @($d.SourceObject.DocumentGUID, $d.SourceObject.FullPath, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Empty path to test for {0}:[{1}] in {2}.  Not enough path pieces." -f @($d.SourceObject.DocumentGUID, $d.SourceObject.FullPath, $me.Name))
                }
                $b++
            }
        } `
        else
        {
            # Nothing....right???
        }

        if($null -ne $fromNode[$keys[$a]].Children)
        {
            # $fromNode = $fromNode[$keys[$a]].Children; $parentPath = $pathToTest + "/"
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

function LoadViablePaths
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
        LogInfo ("Loading JSON content from {0}." -f @($savePath))
        $jsonContent = Get-Content -Path $savePath -ErrorAction Stop
    }
    catch
    {
        LogError ("Failed to read JSON data from {0} in {1}." -f @($savePath, $me.Name))
    }

    try
    {
        LogInfo ("Parsing JSON structure into data structure.")
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
            ShowProgress -progressID 1 -activity "Converting data objects" -counter $a -counterMax $data.Length

            $d = NewViablePathsNode

            $d.Paths = $data[$a].Paths
            $d.SourceObject = $data[$a].SourceObject
            $d.CopyOutPath = $data[$a].CopyOutPath
            $d.SPData.FolderName = $data[$a].SPData.FolderName
            $d.SPData.FileName = $data[$a].SPData.FileName
            if((-not [String]::IsNullOrEmpty($d.SPData.FileName)) -and ($d.SPData.FileName.StartsWith(".")))
            {
                $newName = "noname{0}" -f @($d.SPData.FileName)
                if($d.Paths[-1] -eq $d.SPData.FileName)
                {
                    $d.Paths[-1] = $newName
                }
                $d.SPData.FileName = $newName
            } `
            else
            {
                # Nothing, leave it alone
            }
            $d.SPData.SPFile.ServerRelativeURL = $data[$a].SPData.SPFile.ServerRelativeURL
            $d.SPData.SPFile.VersionLabel = $data[$a].SPData.SPFile.VersionLabel
            $d.SPData.Processed = $data[$a].SPData.Processed
            $d.SPData.Verified = ($null -eq $data[$a].SPData.Verified) ? $false : $data[$a].SPData.Verified
            $d.SPData.WhenUploaded = $data[$a].SPData.WhenUploaded
            $d.SPData.DocVersionToLink = $null     # Can't initialize this, or later in the code, it won't know to build the list
            $d.IsFlatSetReference = $data[$a].IsFlatSetReference

<#
    Fix up .Paths and .SPData.FolderName...

    .Paths[0] will always be the document library name
    .Paths[1...length - 2] will be folder names
    .Paths[-1] will be the file name (if this is a file)
#>

            if($d.Paths[0] -match "^(Active|Inactive) Projects")
            {
                $d.Paths = @($d.Paths | Select-Object -Skip 1)
            } `
            else
            {
                # Nothing...
            }

            $so = $d.SourceObject
            $oldFP = $so.FullPath
            $newFP = @($oldFP -split "\\").ForEach({ $_ -replace $Script:IlegalCharactersInFoldersAndFilesRegEx, "_" }) -join "\"
            if($oldFP -ne $newFP)
            {
                LogError ("Need to manually fix FullPath for {0} in {1} it contains illegal characters." -f @((SourceObjectIdentity -srcObj $so), $savePath))
            }

            # Now we can update .SPData.FolderName and .SPData.FileName
            if($so.MyType -eq "ProjectWiseDocument")
            {
                # Remember, $paths[0] is the library name
                # Minimum is [0] doc library, [1] file name....
                if($d.Paths.Length -ge 2)
                {
                    if($d.Paths.Length -eq 1)
                    {
                        LogError ("WTF!!  Is there a file above a project folder???  {0}:{1} in {2}." -f @($so.DocumentGUID, $so.FullPath, $me.Name))
                    } `
                    elseif($d.Paths.Length -eq 2)
                    {
                        $d.SPData.FolderName = [String]::Empty
                        $d.SPData.FileName = $d.Paths[1]
                    } `
                    else
                    {
                        $d.SPData.FolderName = @($d.Paths | Select-Object -Skip 1 -Last ($d.Paths.Length - 2)) -join "/"
                        $d.SPData.FileName = $d.Paths[-1]
                    }
                    if((-not [String]::IsNullOrEmpty($d.SPData.FileName)) -and ($d.SPData.FileName.StartsWith(".")))
                    {
                        $newName = "noname{0}" -f @($d.SPData.FileName)
                        if($d.Paths[-1] -eq $d.SPData.FileName)
                        {
                            $d.Paths[-1] = $newName
                        }
                        $d.SPData.FileName = $newName
                    } `
                    else
                    {
                        # Nothing, leave it alone
                    }
                } `
                else
                {
                    LogWarning ("File path too short. (length = {0}) for {1}:{2} in {3}." -f @($d.Paths.Length, $so.MyType, $so.DocumentGUID, $so.FullPath, $me.Name))
                }
            } `
            elseif($so.MyType -eq "ProjectWiseFolder")
            {
                $d.SPData.FileName = [String]::Empty
                if($d.Paths.Length -ge 2)
                {
                    # Remember, $d.Paths[0] is the library name
                    if($d.Paths.Length -eq 2)
                    {
                        $d.SPData.FolderName = $d.Paths[1]
                    } `
                    else
                    {
                        $d.SPData.FolderName = @($d.Paths | Select-Object -Skip 1) -join "/"
                    }
                } `
                else
                {
                    # No worries, this is just another project folder and it will get it's own document library.
                    # LogError ("Folder path too short. (length = {0}) for {1}:{2} in {3}." -f @($paths.Length, $so.DocumentGUID, $so.FullPath, $me.Name))
                }
            } `
            else
            {
                LogError ("Unknown source object type '{0}' for {1}:{2} in {3}." -f @($so.MyType, $so.DocumentGUID, $so.FullPath, $me.Name))
            }

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
                $i = $d.SPData.DocSetLinksCreated.BinarySearch($_)
                if($i -lt 0)
                {
                    $d.SPData.DocSetLinksCreated.Insert(-bnot $i, $_)
                } `
                else
                {
                    # Nothing, no dupes please.
                }
            })

            if($d.Paths.Length -gt 0)
            {
                $viablePathsDict2.Add($data[$a].GUID, $d)
            } `
            else
            {
                # Skip the project folder's parent...
            }

            $a++
        }
        ShowProgress -progressID 1 -complete
    } `
    else
    {
        # Nothing, already logged an error.
    }

    return @(, $viablePathsDict2)
}

function UpdateViablePathsFromLastRun
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

    $latestPathPieces = $pwData.PWFolder.FullPath -split "\\"
    if($latestPathPieces.Length -ge 2)
    {
        try
        {
            $latestViablePathDictExportFile = Get-ChildItem -File -Filter ("{0}*_viablepaths.json" -f @($latestPathPieces[1])) -Path ("{0}\{1}" -f @($Script:localPath, $latestPathPieces[0])) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        }
        catch
        {
            # No worries, no old viable path dictionary...
            $Error.Clear()
        }

        if($null -ne $latestViablePathDictExportFile)
        {
            $oldViablePathsDict = LoadViablePaths -savePath $latestViablePathDictExportFile.FullName
            if(-not $Script:HaveError)
            {
                # Get the keys for all the document sources.... This works for documents... not folders...
                $keys =  @(@($oldViablePathsDict.Keys) | Where-Object { $oldViablePathsDict[$_].SourceObject.MyType -eq "ProjectWiseDocument" })
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $keys.Length))
                {
                    ShowProgress -progressID 1 -activity "Updating document viable paths" -counter $a -counterMax $keys.Length
                    if($viablePathsDict.ContainsKey($keys[$a]))
                    {
                        $viablePathsDict[$keys[$a]].SPData = $oldViablePathsDict[$keys[$a]].SPData
                    } `
                    else
                    {
                        # Nothing, can't assume anything for this object.
                    }

                    $a++
                }
                ShowProgress -progressID 1 -complete

#                $newFolders = @(@($viablePathsDict.Values) | Where-Object { ($_.SourceObject.MyType -eq "ProjectWiseFolder") })
                # Ignore processed folders and document library folders...
                $oldProcessedFolders = @(@($oldViablePathsDict.Values) | Where-Object { ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and $_.SPData.Processed -and ($_.Paths.Length -gt 1) })
                $a = 0
                while($a -lt $oldProcessedFolders.Length)
                {
                    ShowProgress -progressID 1 -activity "Updating folder viable paths" -counter $a -counterMax $oldProcessedFolders.Length

                    if($viablePathsDict.ContainsKey($oldProcessedFolders[$a].SourceObject.DocumentGUID))
                    {
                        $viablePathsDict[$oldProcessedFolders[$a].SourceObject.DocumentGUID].SPData = $oldProcessedFolders[$a].SPData
                    } `
                    else
                    {
                        LogWarning ("Missing ProjectWise folder object for {0} in {1}." -f @((SourceObjectIdentity -srcObj $oldProcessedFolders[$a]), $me.Name))
                    }
<#
                    $nfs = @($newFolders | Where-Object { $_.SourceObject.DocumentGUID -eq $oldProcessedFolders[$a].SourceObject.DocumentGUID })
                    if($nfs.Length -eq 1)
                    {
                        $nfs[0].SPData = $oldProcessedFolders[$a].SPData
                    } `
                    else
                    {
                        LogError ("Too many folder object match {0} in {1}" -f @($oldProcessedFolders[$a].SourceObject.FullPath))
                    }
#>
                    $a++
                }
                ShowProgress -progressID 1 -complete
            }
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            # Nothing, new export...
        }
    } `
    else
    {
        LogError ("Bad ProjectWise Folder name [{0}] in {1}." -f @($pwData.PWFolder.FullName, $me.Name))
    }
}

function ExportViablePathsStructure
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $me = $MyInvocation.MyCommand
    if([String]::IsNullOrEmpty($Script:viablePathExportPath))
    {
        $Script:viablePathExportPath = "{0}\{1}\{2}_{3}_ViablePaths.json" -f @($Script:localPath, $Script:pwProjectPath, $Script:projectName, $Script:exportDateTime)
    } `
    else
    {
        # Nothing, already set it.
    }

    $exportList = [System.Collections.Generic.List[System.Object]]::new()

    $keys = @($viablePathsDict.Keys)
    $a = 0
    while($a -lt $keys.Length)
    {
        ShowProgress -progressID 3 -activity "Converting viable path dictionary object" -counter $a -counterMax $keys.Length
        $d = NewViablePathsNode

        $d.GUID = $keys[$a]     # Convert from a dictionary to an array, so I need to save the key so we can recreate the key on import.
        $d.Paths = $viablePathsDict[$keys[$a]].Paths
        $d.CopyOutPath = $viablePathsDict[$keys[$a]].CopyOutPath
        $d.SourceObject = $viablePathsDict[$keys[$a]].SourceObject
        $d.SPData.FolderName = $viablePathsDict[$keys[$a]].SPData.FolderName
        $d.SPData.FileName = $viablePathsDict[$keys[$a]].SPData.FileName
        if((-not [String]::IsNullOrEmpty($d.SPData.FileName)) -and ($d.SPData.FileName.StartsWith(".")))
        {
            $newName = "noname{0}" -f @($d.SPData.FileName)
            if($d.Paths[-1] -eq $d.SPData.FileName)
            {
                $d.Paths[-1] = $newName
            }
            $d.SPData.FileName = $newName
        } `
        else
        {
            # Nothing, leave it alone
        }
        $d.SPData.SPFile.ServerRelativeURL = $viablePathsDict[$keys[$a]].SPData.SPFile.ServerRelativeURL
        $d.SPData.SPFile.VersionLabel = $viablePathsDict[$keys[$a]].SPData.SPFile.VersionLabel
        $d.SPData.Processed = $viablePathsDict[$keys[$a]].SPData.Processed
        $d.SPData.Verified = $viablePathsDict[$keys[$a]].SPData.Verified
        $d.SPData.WhenUploaded = $viablePathsDict[$keys[$a]].SPData.WhenUploaded
        $d.SPData.DocVersionToLink = [System.Collections.Generic.List[Object]]::new()
        $d.SPData.DocSetLinksCreated = $viablePathsDict[$keys[$a]].SPData.DocSetLinksCreated
        $d.IsFlatSetReference = $viablePathsDict[$keys[$a]].IsFlatSetReference

        # Ignore the LibInfo structure...

        if($null -ne $viablePathsDict[$keys[$a]].SPData.DocVersionToLink)
        {
            @($viablePathsDict[$keys[$a]].SPData.DocVersionToLink.Keys).ForEach({
                $e = [PSCustomObject]@{
                    DocumentVersion = $_
                    Link = $viablePathsDict[$keys[$a]].SPData.DocVersionToLink[$_]
                }
                $d.SPData.DocVersionToLink.Add($e)
            })
        } `
        else
        {
            # Nothing, no DocVersionToLinks yet.
        }
        $exportList.Add($d)

        $a++
    }
    ShowProgress -progressID 3 -complete

    $fi = [System.IO.FileInfo]::new($Script:viablePathExportPath)
    if(-not [System.IO.Directory]::Exists($fi.DirectoryName))
    {
        try
        {
            $null = New-Item -ItemType Directory -Force $fi.DirectoryName -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to create new directory [{0}] in {1}." -f @($fi.DirectoryName, $me.Name))
        }
    } `
    else
    {
        # Nothing, directory already exists.
    }

    if(-not $Script:HaveError)
    {
        LogInfo ("Exporting viable paths data to: {0}" -f @($Script:viablePathExportPath))
        $exportList | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:viablePathExportPath -Force
    } `
    else
    {
        # Nothing, already displayed an error.
    }
}

function BuildInitialReport
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData
    )

    $Script:reportData.Folders.InProject = 0
    $Script:reportData.Documents.InProject = 0
    $Script:reportData.Size.InProjectWise = 0
    $Script:reportData.DocumentSets.InProject = 0
    $Script:reportData.DocumentLinks.InProject = 0

    @($pwData.ProjectWiseObjects.Values).ForEach({
        if($_.MyType -eq "ProjectWiseFolder")
        {
            $Script:reportData.Folders.InProject++
        } `
        else
        {
            $Script:reportData.Documents.InProject++
            $Script:reportData.Size.InProjectWise += $_.FileSize
            if($_.IsSet)
            {
                $Script:reportData.DocumentSets.InProject++
            }

            if($null -ne $_.FlatSetReferences)
            {
                $Script:reportData.DocumentLinks.InProject += $_.FlatSetReferences.Count
            }
        }
    })
}

function GetProjectProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData
    )

    $me = $MyInvocation.MyCommand
    $projectParams = $null
    if($null -ne $pwData.PWFolder)
    {
        if($null -ne $pwData.PWFolder.ProjectProperties)
        {
            $projectParams = @{  }

            $a = 0
            $projectPropKeys = @($pwData.PWFolder.ProjectProperties.Keys)
            while((-not $Script:HaveError) -and ($a -lt $projectPropKeys.Length))
            {
                if(-not [String]::IsNullOrEmpty($pwData.PWFolder.ProjectProperties[$projectPropKeys[$a]]))
                {
                    if($Script:connData.documentFields.ContainsKey($projectPropKeys[$a]))
                    {
                        $spDocField = $Script:connData.documentFields[$projectPropKeys[$a]]
                        if(-not $spDocField.Ignore)
                        {
                            $projectParams.Add($projectPropKeys[$a], $pwData.PWFolder.ProjectProperties[$projectPropKeys[$a]])
                        } `
                        else
                        {
                            # Ignore the value...
                        }
                    } `
                    else
                    {
                        $spDocField = $null
                    }
                } `
                else
                {
                    # ignore empty properties.
                }
                $a++
            }
        } `
        else
        {
            LogError ("No project properties for {0} in {1}.  Dictionary is null.")
        }
    } `
    else
    {
        LogError ("No ProjectWise project folder in pwData in {0}." -f @($me.Name))
    }

    return @(, $projectParams)
}

function CreateLinkInFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $linkName,      # This is the name of the link   ($linkName).url

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $linkURL,      # This is the value which gets added to the .url file...

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $folderURL,      # This is the folder where the link gets created.

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyCollection()]
        [HashTable] $linkParams     # These are the "document fields to attach to the link.
    )

    # Make sure the link name ends with .url
    if($linkName -notmatch "\.url")
    {
        $linkName = "{0}.url" -f @($linkName)
    } `
    else
    {
        # Nothing, all good.
    }

    # for testing to see if the link is already there.
    $docLink = "{0}/{1}" -f @($folderURL, $linkName)

    # Test for an existing link
    $existingLink = $null
    try
    {
        $existingLink = Get-PnPFile -Url $docLink -AsListItem -ErrorAction Stop
        LogInfo ("Link {0} in {1} already exists." -f @($linkName, $folderURL))
    }
    catch
    {
        # No worries, the link doesn't exists.
        $Error.Clear()
        $existingLink = $null
    }

    # If the link isn't there, then create it.
    if($null -eq $existingLink)
    {
        # Make sure the _ShortcutUrl is in the link params.
        if($null -ne $linkParams)
        {
            if(-not $linkParams.ContainsKey("_ShortcutUrl"))
            {
                $linkParams.Add("_ShortcutUrl", $linkURL)
            } `
            else
            {
                $linkParams["_ShortcutUrl"] = $linkURL
            }
        } `
        else
        {
            $linkParams = @{ "_ShortcutUrl" = $linkURL }
        }

        # Create an internet shortcut containing $linkURL.
        $linkContent = "[InternetShortcut]`nURL={0}`n" -f @($linkURL)
        $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($linkContent))

        try
        {
            LogInfo ("Creating link {0} in {1}" -f @($linkName, $folderURL))
            $null = Add-PnPFile -FileName $linkName -Folder $folderURL -Stream $stream -Values $linkParams -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to create link {0} for {1} in {2}." -f @($linkName, $linkURL, $me.Name))
        }
    } `
    else
    {
        # Nothing, link already exists.  Let's make sure the properties are set correctly.
        $changedProps = @{}
        $propKeys = @($linkParams.Keys)
        $a = 0
        while($a -lt $propKeys.Length)
        {
            if($propKeys[$a] -ne "_ShortcutUrl")
            {
                if($existingLink.FieldValues.ContainsKey($propKeys[$a]))
                {
                    $lValue = $linkParams[$propKeys[$a]]
                    $eValue = $existingLink.FieldValues[$propKeys[$a]]

                    if(($lValue -is [DateTime]) -or ($eValue -is [DateTime]))
                    {
                        $lValueDT = [DateTime]::Now
                        if([DateTime]::TryParse($lValue, [ref] $lValueDT))
                        {
                            $lValue = $lValueDT.ToString("yyyyMMdd-HHmmss")
                        } `
                        else
                        {
                            # Guess we go with what we have.
                        }

                        $eValueDT = [DateTime]::Now
                        if([DateTime]::TryParse($eValue, [ref] $eValueDT))
                        {
                            $eValue = $eValueDT.ToString("yyyyMMdd-HHmmss")
                        } `
                        else
                        {
                            # Guess we go with what we have.
                        }
                    } `
                    else
                    {
                        # Nothing, go with the values we already have.
                    }
                    if($lValue -ne $eValue)
                    {
                        $changedProps.Add($propKeys[$a], $linkParams[$propKeys[$a]])
                    } `
                    else
                    {
                        # Nothing, matches.
                    }
                }
            } `
            else
            {
                # Nothing, ignore _ShortcutUrl
            }

            $a++
        }

        if($changedProps.Count -gt 0)
        {
            # We now have to get a version of $existingLink that we can modify...
            try
            {
                $existingLink = Get-PnPFile -Url $docLink -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to retrieve modifiable file object for {0} in {1}." -f @($docLink, $me.Name))
            }

            if(-not $Script:HaveError)
            {
                if($null -ne $existingLink)
                {
                    $a = 0
                    $propKeys = @($changedProps.Keys)
                    while($a -lt $changedProps.Length)
                    {
                        $existingLink.ListItemAllFields[$propKeys[$a]] = $changedProps[$propKeys[$a]]
                        $a++
                    }

                    try
                    {
                        $existingLink.ListItemAllFields.Update()
                        Invoke-PnpQuery
                    }
                    catch
                    {
                        LogError ("Failed to update link properties for {0} in {1}." -f @($linkName, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Null value returned for Get-PnpFile for modifiable link for {0} in {1}." -f @($docLink, $me.Name))
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            # Nothing, no changes required.
        }
    }
}

function CreateProjectLink
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
    # Need: the folder (document library where the link is to be created.)
    # Need the properties to attach to the link
    # Need the URL of the link to create.

    if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($Script:projectName))
    {
        $projectDocLib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$Script:projectName]

        if($null -ne $projectDocLib)
        {
            $projectParams = GetProjectProperties -pwData $pwData

            if($viablePathsDict.ContainsKey($pwData.PWFolder.DocumentGUID))
            {
                $vp = $viablePathsDict[$pwData.PWFolder.DocumentGUID]
                if($null -ne $vp.SourceObject)
                {
                    if(-not [String]::IsNullOrEmpty($vp.SourceObject.FullPath))
                    {
                        $destinationDocLibName = @($vp.SourceObject.FullPath -split "\\")[0]
                        $destinationDocLibName = TranslateToDocLibName -name $destinationDocLibName
                        if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($destinationDocLibName))
                        {
                            $destLib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$destinationDocLibName]

                            # Make sure all the project property document fields exist.
                            $a = 0
                            $projectParamKeys = @($projectParams.Keys)
                            while((-not $Script:HaveError) -and ($a -lt $projectParamKeys.Length))
                            {
                                ShowProgress -progressID 1 -activity "Checking for project property document fields" -counter $a -counterMax $projectParamKeys.Length -statusSuffix $projectParamKeys[$a]
                                $null = TestForSPDocumentLibraryField -libraryName $destinationDocLibName -fieldName $projectParamKeys[$a]
                                $a++
                            }
                            ShowProgress -progressID 1 -complete

                            if(-not $Script:HaveError)
                            {
                                #     $linkName = "{0}" -f @($Script:projectName); $linkURL = "{0}{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $projectDocLib.Library.DefaultViewUrl); $folderURL = $destlib.Library.RootFolder.ServerRelativeUrl; $linkParams = $projectParams
                                CreateLinkInFolder -linkName ("{0}" -f @($Script:projectName)) -linkURL ("{0}{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $projectDocLib.Library.DefaultViewUrl)) -folderURL $destlib.Library.RootFolder.ServerRelativeUrl -linkParams $projectParams
                            } `
                            else
                            {
                                # Nothing, already logged an error
                            }
                        } `
                        else
                        {
                            LogError ("Missing document library for {0}:{1} in {2}" -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
                        }
                    } `
                    else
                    {
                        LogError ("Unable to extract destination library name from {0}:{1} in {2}" -f @($vp.SourceObject.DocumentGUID, $vp.SourceObject.FullPath, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Missing source object for [{0}] in {1}." -f @(($vp.Paths -join "/")))
                }
            } `
            else
            {
                LogError ("Missing ProjectWise folder viable path object for {0} in ProjectWiseObjects in {1}." -f @($pwData.PWFolder.FullPath, $me.Name))
            }
        } `
        else
        {
            LogError ("No document library found for {0} in {1}." -f @($Script:projectName, $me.Name))
        }
    } `
    else
    {
        LogError ("Missing document library for {0} in {1}." -f @($Script:projectName, $me.Name))
    }
}

function GetLibraryDataFromObj
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $CreateMissingLibrary
    )

    $me = $MyInvocation.MyCommand
    if($null -ne $obj2Upload.LibInfo)
    {
        $retval = $obj2Upload.LibInfo
    } `
    else
    {
        <#
            Cannot assume $Script:projectName is the name of the library.  If this is a flatset reference to some other project, then we need to adapt.
        #>
        $retval = [PSCustomObject]@{
            SPFolderPathPieces = @()
            LibraryName = $null
            Library = $null
            LibURL = $null
            FolderURL = $null
            FileURL = $null
            LibraryFolderName = $null
            RealName = [String]::Empty
        }

        if($null -ne $obj2Upload.SourceObject)
        {
            if($null -ne $obj2Upload.Paths)
            {
                if($obj2Upload.Paths.Length -gt 0)
                {
                    if(-not [String]::IsNullOrEmpty($obj2Upload.Paths[0]))
                    {
                        $retval.LibraryName = TranslateToDocLibName -name $obj2Upload.Paths[0]
                        if(-not [String]::IsNullOrEmpty($obj2Upload.SPData.FolderName))
                        {
                            $retval.SPFolderPathPieces = $obj2Upload.SPData.FolderName -split "/"
                        } `
                        else
                        {
                            # Nothing, this is the project document library... not a folder.
                        }

                        if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($retval.LibraryName))
                        {
                            # Never create a document library when processing a proposal.
                            if($CreateMissingLibrary.IsPresent)
                            {
                                if(-not $Script:isProposal.IsPresent)
                                {
                                    CreateProjectDocumentLibrary -newDocLibName $retval.LibraryName
                                } `
                                else
                                {
                                    LogError ("Attempt to create document library when processing a proposal in {0}." -f @($me.Name))
                                }
                            } `
                            else
                            {
                                LogError ("Missing document library for {0} in {1}." -f @($obj2Upload.SourceObject.FullPath, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, we'll finish up below...
                        }

                        # Might have had to build a new document library....
                        if(-not $Script:HaveError)
                        {
                            if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($retval.LibraryName))
                            {
                                $retval.Library = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName].Library
                                $retval.RealName = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName].RealName
                                $retval.LibURL = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$retval.LibraryName].Library.RootFolder.ServerRelativeURL
                                $retval.LibraryFolderName = @($retval.LibURL -split "/")[-1]

                                if($retval.SPFolderPathPieces.Length -gt 0)
                                {
                                    $retval.FolderURL = "{0}/{1}" -f @($retval.LibURL, ($retval.SPFolderPathPieces -join "/"))
                                } `
                                else
                                {
                                    $retval.FolderURL = $retval.LibURL
                                }

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
                        LogError (".Paths[0] is empty for {0}:{1} in {2}." -f @($obj2Upload.SourceObject.DocumentGUID, $obj2Upload.SourceObject.FullPath, $me.Name))
                    }
                } `
                else
                {
                    LogError ("Empty .Paths for {0}:{1} in {2}." -f @($obj2Upload.SourceObject.DocumentGUID, $obj2Upload.SourceObject.FullPath, $me.Name))
                }
            } `
            else
            {
                LogError ("Missing .Paths for {0}:{1} in {2}." -f @($obj2Upload.SourceObject.DocumentGUID, $obj2Upload.SourceObject.FullPath, $me.Name))
            }
        } `
        else
        {
            LogError ("Missing source object for object to upload in {0}" -f @($me.Name))
        }

        if(-not $Script:HaveError)
        {
            Add-Member -InputObject $obj2Upload -MemberType NoteProperty -Name LibInfo -Value $retval
        } `
        else
        {
            $retval = $null
        }
    }

    return @(, $retval)
}

function GetSPDocumentVersions
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $docURL
    )

    $me = $MyInvocation.MyCommand
    $retval = [PSCustomObject]@{
        SPDocument = $null
        Versions = $null
        Special = [String]::Empty
    }
    try
    {
        # This only works for the current version of the file....
        $retval.SPDocument = Get-PnPFile -URL $docURL -AsListItem -ErrorAction Stop

        # If we got a null object, try to escape the URL....
        if($null -eq $retval.SPDocument)
        {
            $retval.SPDocument = Get-PnPFile -URL ([URI]::EscapeUriString($docURL)) -AsListItem -ErrorAction Stop
        } `
        else
        {
            # Nothing, all is good.
        }
    }
    catch
    {
        if($Error[0].Exception.Message -match "The object does not belong to a list.")
        {
            # File doesn't exist...
            $Error.Clear()
        } `
        else
        {
            LogError ("Failed to retrieve file [{0}] from SharePoint in {1}." -f @($docURL, $me.Name))
        }
    }

    if($null -ne $retval.SPDocument)
    {
        # Now, get all the versions of the file from SharePoint.
        try
        {
            # This verison data contains the FieldValues I need to determine which version has the right "DocumentVersion", but does not
            #    include the document URL I need.  It does have .VersionLabel which I'll use to link to $referenceSPDocVersions below.
            # This works for a file with only 1 version.
            # When Get-PnPProperty returns, $retval.SPDocument.Versions will be populated with version information.
            $null = Get-PnPProperty -ClientObject $retval.SPDocument -Property Versions -ErrorAction Stop
        }
        catch
        {
            LogError ("Failed to get SP document versions of {0} in {1}." -f @($spFileURL, $me.Name))
        }
    } `
    else
    {
        # Nothing....
    }

    if($null -ne $retval.SPDocument)
    {
        # Now, get all the versions of the file from SharePoint.
        try
        {
            # This 'version' data contains the URL and VersionLabel
            $retval.Versions = Get-PnpFileVersion -URL $docURL -ErrorAction Stop
        }
        catch
        {
            if($Error.Count -gt 0)
            {
                if($Error[0].Exception.Message -match "Operation is not valid due to the current state of the object.")
                {
                    $retval.Special = ("Manually verify {0}" -f @($docURL))
                    $Error.Clear()
                } `
                else
                {
                    LogError ("Failed to get additional versions of {0} in {1}." -f @($docURL, $me.Name))
                }
            } `
            else
            {
                # WTH!!
            }
        }
    } `
    else
    {
        # Nothing....
    }

    return @( , $retval)
}

function BuildDocumentProperties
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Object] $obj2Upload
    )

    $me = $MyInvocation.MyCommand
    $spdocValues = $null
    $libInfo = ($null -ne $obj2Upload.LibInfo) ? $obj2Upload.LibInfo : (GetLibraryDataFromObj -obj2Upload $obj2Upload)

    if($null -ne $libInfo)
    {
        $td = $obj2Upload.SourceObject
        # Build the document properties...
        $spdocValues = @{
            Created = $td.CreateDate
            Modified = $td.FileUpdateDate
        }

        if($obj2Upload.SPData.FileName.Trim('.',' ') -ne $td.Name)
        {
            $spDocValues.Add("OriginalName", $td.Name)
        } `
        else
        {
            # Nothing.
        }

        $attributeSet = $null
        if($Script:AttributeSetName -ne "Default")
        {
            if($Script:connData.attributeSets.ContainsKey($Script:AttributeSetName))
            {
                $attributeSet = $Script:connData.attributeSets[$Script:AttributeSetName]
            } `
            else
            {
                LogError ("Missing attribute set {0} in {1}." -f @($Script:AttributeSetName, $me.Name))
            }
        } `
        else
        {
            # Nothing -- use the default attribute set... which is everything.
        }

        $fields = @("DocumentOwnerName","Status","DocumentCreatorName","FileUpdaterName", "FileUpdateDate", "DocumentOutToName", "WorkFlow", "WorkFlowState", "DocumentUpdaterName", "DocumentUpdateDate")

        $a = 0
        while((-not $Script:HaveError) -and ($a -lt $fields.Length))
        {
            $setAttribute = ($null -eq $attributeSet) -or ($attributeSet.Contains($fields[$a]))

            if(($setAttribute) -and (-not [String]::IsNullOrEmpty($td.$fields[$a])))
            {
                $spdocValues.Add($fields[$a], $td.$fields[$a])
            } `
            else
            {
                # Nothing, don't add the property
            }
            $a++
        }

        if((-not $Script:isProposal.IsPresent) -and (-not [String]::IsNullOrEmpty($td.Status)))
        {
            $status = $td.Status
            switch($td.Status)
            {
                "I"  { $status = "Checked In"}
                "IF" { $status = "Final" }
                "O"  { $status = "Checked Out" }
                "OX" { $status = "Exported" }
                "CI" { $status = "Coming In (no file in storage)" }
                "GO" { $status = "Going Out (check out or export got interupted) "}
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

        @($spdocValues.Keys).ForEach({
            $null = TestForSPDocumentLibraryField -libraryName $libInfo.LibraryName -fieldName $_

            if($Script:HaveError)
            {
                break
            }
        })

        if(-not $Script:HaveError)
        {
            if($null -ne $td.Attributes)
            {
                $listKeys = @($td.Attributes.Keys)
                $c = 0
                while((-not $Script:HaveError) -and ($c -lt $listKeys.Length))
                {
                    if(-not [String]::IsNullOrEmpty($td.Attributes[$listKeys[$c]]))
                    {
                        $spDocFieldName = GetSharePointDocumentFieldNameForProperty -libraryName $libInfo.LibraryName -propertyName $listKeys[$c]
                        if(-not $Script:HaveError)
                        {
                            if(($null -eq $attributeSet) -or ($attributeSet.Contains($spDocFieldName)))
                            {
                                $fld = TestForSPDocumentLibraryField -libraryName $libInfo.LibraryName -fieldName $spDocFieldName

                                if(-not $Script:HaveError)
                                {
                                    if(($null -ne $fld) -and (-not $fld.Ignore))
                                    {
                                        $spdocValues.Add($fld.InternalName, $td.Attributes[$listKeys[$c]])
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
                                # Nothing, skip it
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        # Nothing, the attribute value is empty
                    }
                    $c++
                }
            } `
            else
            {
                # Nothing, no attributes to add...
            }

            if($Script:HaveError)
            {
                $spdocValues = $null
            } `
            else
            {
                # # Nothing.
            }
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

    if($Script:HaveError)
    {
        $spdocValues = $null
    } `
    else
    {
        # Nothing, let it fly
    }

    return @(, $spdocValues)
}

<#
    Don't be confused by the name SpDocVersionMatchesPWDocVersion, it only checks to see if 2 string values match as afar as a "Version"...look at the logic.
        I just didn't want to use this long comparison in 2 places...
#>
function SPDocVersionMatchesPWDocVersion
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowEmptyString()]
        [String] $spDocVersion,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [AllowEmptyString()]
        [String] $pwDocVersion
    )

    # I put this logic together in this order in hopes of making it short circuit as fast as possible.... i.e. in the order I think is most likely.
    return ([String]::IsNullOrEmpty($pwDocVersion) -and ([String]::IsNullOrEmpty($spDocVersion) -or ($spDocVersion -eq "NoVersion"))) -or ($spDocVersion -eq $pwDocVersion)
}

function VerifyOtherDocumentProperties
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNull()]
        [Microsoft.SharePoint.Client.ListItemVersion] $spVersion,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [Object] $pwDoc
    )

    $me = $MyInvocation.MyCommand
    $propsToChange = @{}
    if(-not $Script:isProposal.IsPresent)
    {
        $pwDocProps = BuildDocumentProperties -obj2Upload $pwDoc
        if($null -ne $spVersion.FieldValues)
        {
            if(-not $Script:HaveError)
            {
                if($null -ne $pwDocProps)
                {
                    $pwDocPropKeys = @(@($pwDocProps.Keys).Where({ $_ -notin $Script:InsignificantFields }))
                    $a = 0
                    while((-not $Script:HaveError) -and ($a -lt $pwDocPropKeys.Length))
                    {
                        if($spVersion.FieldValues.ContainsKey($pwDocPropKeys[$a]))
                        {
                            $fldValue = ($null -ne $spVersion.FieldValues[$pwDocPropKeys[$a]]) ? $spVersion.FieldValues[$pwDocPropKeys[$a]].ToString() : $null
                            $docPropValue = ($null -ne $pwDocProps[$pwDocPropKeys[$a]]) ? $pwDocProps[$pwDocPropKeys[$a]].ToString() : $null
                            if($fldValue -ne $docPropValue)
                            {
                                if($pwDocPropKeys[$a] -eq "DocumentVersion")
                                {
                                    if((SPDocVersionMatchesPWDocVersion -spDocVersion $spVersion.FieldValues[$pwDocPropKeys[$a]]  -pwDocVersion $pwDocProps[$pwDocPropKeys[$a]]))
                                    {
                                        # Nothing, all is good.
                                    } `
                                    else
                                    {
                                        # Got a problem.... A BIG problem, these aren't the same document versions....and I don't want to just trust the file size...
                                        LogWarning ("Document version mismatch for '{0}' and {1}:'{2}' in {3}." -f @($spVersion.FieldValues.FileRef, $pwDoc.SourceObject.DocumentGUID, $pwDoc.SourceObject.FullPath, $me.Name))
                                        LogWarning ("SP Version: [{0}]`tPW Version: [{1}]:{2}" -f @($spVersion.FieldValues.DocumentVersion, $pwDoc.SourceObject.Version, $pwDoc.SourceObject.VersionSequence))
                                    }
                                }
                                else
                                {
                                    # Got a problem
                                    LogTrace  ("SP.{0} = [{1}]`tPW.{0} = [{2}]" -f @($pwDocPropKeys[$a], $spVersion.FieldValues[$pwDocPropKeys[$a]], $pwDocProps[$pwDocPropKeys[$a]])) -traceLevel 2
                                    $propsToChange.Add($pwDocPropKeys[$a], $pwDocProps[$pwDocPropKeys[$a]])
                                }
                            } `
                            else
                            {
                                # Nothing all is good.
                            }
                        } `
                        else
                        {
                            # Something is amiss... if this is the current version, then we can fix it.
                            LogTrace ("SP.{0} = [{1}]`tPW.{0} = [{2}]" -f @($pwDocPropKeys[$a], "<missing>", $pwDocProps[$pwDocPropKeys[$a]])) -traceLevel 2
                            $propsToChange.Add($pwDocPropKeys[$a], $pwDocProps[$pwDocPropKeys[$a]])
                        }
                        $a++
                    }

                    if($propsToChange.Count -gt 0)
                    {
                        # Need to fix the SP document...
                        if($spVersion.$isCurrentVersion)
                        {
                            # Try to fix the issue...
                        } `
                        else
                        {
                            # Bad... not the current version, and right now, I don't know if I can affect older versions... but I'll try
                        }
                    } `
                    else
                    {
                        # Nothing, all is well.
                    }
                } `
                else
                {
                    # Nothing, no document properties to check
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            # Need to change everything...
            $propsToChange = $pwDocProps
        }
    } `
    else
    {
        # Nothing, not worried about properties on proposal documents.
    }

    return @(, $propsToChange)
}

function CheckDocumentVersions
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object[]] $documentsToCheck,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Switch] $doRemoval
    )

    <#
        In an effort to make this a little simpler I'm using the following rules:

        1) If the current version of the document as seen from SharePoint is not the current document, then then delete the all versions of the document and re-upload
        2) If all old versions are not in order and match the source object, then delete the all versions of the document and re-upload
        3) Only exception: If the current documents are ok, then if we can remove old versions while keeping them in the right order, then I will.
            Basically this mean, if there is an extra version of a file, then I'll delete it and hope for the best.

    #>

    $me = $MyInvocation.MyCommand

    # Make sure documents are sorted in FullPath/VersionSequence order
    $documentsToCheck = @($documentsToCheck | Sort-Object @{E={ $_.SourceObject.FullPath }}, @{E={ $_.SourceObject.VersionSequence }} )
    $uniqueFPs = @($documentsToCheck | Select-Object @{Name="FP";E={ $_.SourceObject.FullPath }} | Select-Object -Unique -ExpandProperty FP)
    $deleteAndReupload = $false

    $spDocVer = $null
    if($uniqueFPs.Length -eq 1)
    {
        # This highest VersionSequence number is the most current document.
        $mostCurrDoc = $documentsToCheck[-1]

        # Now get the library/url details based on the document
        $libInfo = ($null -ne $mostCurrDoc.LibInfo) ? $mostCurrDoc.LibInfo : (GetLibraryDataFromObj -obj2Upload $mostCurrDoc -CreateMissingLibrary)

        if($null -ne $libInfo)
        {
            # Get all the versions of the SharePoint document.
            #   $docURL = $libInfo.FileURL
            $spDocVer = GetSPDocumentVersions -docURL $libInfo.FileURL
            if($null -ne $spDocVer)
            {
                if([String]::IsNullOrEmpty($spDocVer.Special))
                {
                    $spDoc = $spDocVer.SPDocument
                    $versionIndicesToRemove = [System.Collections.Generic.List[Int32]]::new()
                    if($null -ne $spDoc)
                    {
                        if($null -ne $spDoc.FieldValues)
                        {
                            # Check the current versions of what SharePoint has and what I think there should be.
                            #   $spVersion = $spDoc.Versions[0];  $pwDoc = $documentsToCheck[-1]
                            $propsToChange = VerifyOtherDocumentProperties -spVersion $spDoc.Versions[0] -pwDoc $documentsToCheck[-1]

                            if(-not $Script:HaveError)
                            {
                                # If there are no props to change... well, hell, then I know DocumentVersion is good too.

                                # Now to check all the other versions...

                                # Now check the order of the older versions.
                                # SharePoint version object idx increments for older versions.
                                # PW VersionSequence increments for newer versions.
                                #   $documentsToCheck is sorted by VersionSequence  [-1] is the current

                                if($propsToChange.Count -eq 0)
                                {
                                    $e = 1    # $spDoc.Versions[0] is the current document so start at 1
                                    $f = $documentsToCheck.Length - 2   # - 1 = the current version so start at - 2.

                                    # Keep checking until we hit the end or determine there's a problem.
                                    while((-not $Script:HaveError) -and (-not $deleteAndReupload) -and ($e -lt $spDoc.Versions.Count) -and ($f -ge 0))
                                    {
                                        if($null -ne $spDoc.Versions[$e])
                                        {
                                            if($spDoc.Versions[$e].FieldValues.ContainsKey("DocumentVersion"))
                                            {
                                                if((SPDocVersionMatchesPWDocVersion -spDocVersion $spDoc.Versions[$e].FieldValues["DocumentVersion"] -pwDocVersion $documentsToCheck[$f].SourceObject.Version))
                                                {
                                                    # DocumentVersions match, check other properties...
                                                    #   Don't need to pass in $libInfo, if we made it here, then it's already a part of $documentsToCheck[$f]

                                                    $changedProps = VerifyOtherDocumentProperties -spVersion $spDoc.Versions[$e] -pwDoc $documentsToCheck[$f]
                                                    if(-not $Script:HaveError)
                                                    {
                                                        # If anything is messed up, delete and reupload...
                                                        if($changedProps.Count -gt 0)
                                                        {
                                                            # Don't need to check any further, we are redoing this file...
                                                            $deleteAndReupload = $true
                                                        } `
                                                        else
                                                        {
                                                            # Nothing.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already logged an error.
                                                    }

                                                    # Only decrement $f if the document versions match...
                                                    $f--
                                                } `
                                                else
                                                {
                                                    # Out of order version, remove it...
                                                    $versionIndicesToRemove.Add($e)
                                                }
                                            } `
                                            else
                                            {
                                                # Again, all bets are off.
                                                $deleteAndReupload = $true
                                            }
                                        } `
                                        else
                                        {
                                            # all bets are off...
                                            $deleteAndReupload = $true
                                            LogWarning ("Missing version information from SharePoint for {0}:{1}" -f @($mostCurrDoc.SourceObject.DocumentGUID, $mostCurrDoc.SourceDocument.FullPath))
                                        }
                                        $e++
                                    }

                                    if(-not $Script:HaveError)
                                    {
                                        # Everything ok so far?
                                        if(-not $deleteAndReupload)
                                        {
                                            # yes, so far, all old versions are correct...

                                            # Did we check all PW document versions?
                                            if($f -eq -1)
                                            {
                                                # Yes, all PW versions checked...
                                                # If there are any more versions, then they are extraneous and can be removed.
                                                while((-not $Script:HaveError) -and ($e -lt $spDoc.Versions.Count))
                                                {
                                                    if(-not $spDoc.Versions[$e].$isCurrentVersion)
                                                    {
                                                        if($doRemoval.IsPresent)
                                                        {
                                                            $versionIndicesToRemove.Add($e)
                                                        } `
                                                        else
                                                        {
                                                            # Nothing ...
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogWarning ("Conditions seem to indicate we need to delete the current version, but I cannot remove {0} it is the current version." -f @($spDoc.Versions[$e].FieldValues.FileRef))
                                                        LogWarning ("Perhaps a restored version?")
                                                    }
                                                    $e++
                                                }
                                            } `
                                            else
                                            {
                                                # Remember the rules.  Current version on SharePoint must match the current PS version...
                                                #   So if we didn't check all the versions then we need to delete, cause I don't know how to upload to a version.
                                                #   Hence I need to redo...

                                                # More $documentsToCheck ...
                                                # This means there are missing old versions of the file.  Delete and re-upload.
                                                LogWarning ("Not all versions of {0}:{1} are present in SharePoint" -f @($mostCurrDoc.SourceObject.DocumentGUID, $mostCurrDoc.SourceDocument.FullPath))
                                                $deleteAndReupload = $true
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, already signaled we need to delete and reupload
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, already logged an error.
                                    }
                                } `
                                else
                                {
                                    # There are changes needed.
                                    <#
                                        If I change document fields, a new minor version of the file will be created.  On its own, no big deal, but if I have to recheck
                                        this project again, then I'll have messed up versions to deal with and it will likely cause me to have to delete and try again.

                                        So, for simplicity's sake, I'm just going to make the decision.  If a documents properties are not right on the current document,
                                        then it needs to be re-uploaded.
                                    #>

                                    $deleteAndReupload = $true
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # No field values... that sucks... gonna have to delete and re-upload...
                            $deleteAndReupload = $true
                        }

                        # We made all the checks we want to make, now take action...
                        if(-not $Script:HaveError)
                        {
                            # Delete all versions of the file?
                            if($deleteAndReupload)
                            {
                                # Yes...
                                if($doRemoval.IsPresent)
                                {
                                    try
                                    {
                                        LogWarning ("Removing ALL versions of {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                                        Remove-PnpFile -ServerRelativeUrl $libInfo.FileURL -Force -ErrorAction Stop

                                        $documentsToCheck.ForEach({
                                            $_.SPData.Processed = $false
                                            $_.SPData.WhenUploaded = [String]::Empty
                                            $_.SPData.SPFile.ServerRelativeURL = [String]::Empty
                                            $_.SPData.SPFile.VersionLabel = [String]::Empty
                                        })
                                        $spDocVer = $null
                                    }
                                    catch
                                    {
                                        LogError ("Failed to delete all versions of {0} of {1} from Sharepoint in {2}." -f @($libInfo.FileURL, $me.Name))
                                    }
                                } `
                                else
                                {
                                    LogInfo ("ALL versions of {0} would have been removed if doRemovals was specified in {1}." -f @($libInfo.FileURL, $me.Name))
                                }
                            } `
                            else
                            {
                                # No, not deleting all versions, but are there any we are removing?
                                if($versionIndicesToRemove.Count -gt 0)
                                {
                                    # Yes, there are versions to remove, so log it or remove it.
                                    $versionIndicesToRemove | Select-Object -Unique | Sort-Object | ForEach-Object {
                                        $idx = $_
                                        if($doRemoval.IsPresent)
                                        {
                                            if($null -ne $spDoc.Versions[$idx])
                                            {
                                                LogInfo ("Removing version {0} of {1} in {2}." -f @($spDoc.Versions[$idx].VersionId, $libInfo.FileURL, $me.Name))
                                                $spDoc.Versions[$idx].DeleteObject()
                                            } `
                                            else
                                            {
                                                LogWarning ("Attempt to delete a version of {0} with idx {1} when version is null." -f @($libInfo.FileURL, $idx, $me.Name))
                                            }
                                        } `
                                        else
                                        {
                                            LogInfo ("Version {0} of {1} would have been removed if doRemoval was specified in {2}." -f @($spDoc.Versions[$idx].VersionId, $libInfo.FileURL, $me.Name))
                                        }
                                    }

                                    # Commit the removals...
                                    if($doRemoval.IsPresent)
                                    {
                                        try
                                        {
                                            Invoke-PnpQuery
                                        }
                                        catch
                                        {
                                            LogError ("Failed to commit removal of versions of {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                                        }

                                        $spDocVer = GetSPDocumentVersions -docURL $libInfo.FileURL
                                    } `
                                    else
                                    {
                                        # Nothing, not doing removals here.
                                    }
                                    $versionIndicesToRemove.Clear()
                                } `
                                else
                                {
                                    # Nothing, don't need to remove anything.
                                }
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        # No document to look at... guess we just upload.
                    }
                } `
                else
                {
                    if($spDocVer.Special -match "Manually verify")
                    {
                        LogWarning $spDocVer.Special
                        LogWarning $spDocVer.Special
                        LogWarning $spDocVer.Special
                    } `
                    else
                    {
                        LogError $spDocVer.Special
                    }
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            # Nothing, just have to upload everything I guess.
        }
    } `
    else
    {
        LogError ("Multiple full paths in documents to check in {0}." -f @($me.Name))
        $uniqueFPs.ForEach({
            LogError ($_)
        })
    }

    return @($deleteAndReupload, $spDocVer)
}

function CheckObjectsInSharePoint
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]] $viablePathsLookupDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [AllowEmptyString()]
        [String] $docLibName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [AllowNull()]
        [Microsoft.SharePoint.Client.ClientObject] $folderItem = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [AllowNull()]
        [System.Collections.Generic.List[Guid]] $checkedGuids = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [AllowNull()]
        [System.Collections.Generic.List[String]] $extraObjects = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [AllowNull()]
        [System.Collections.Generic.List[Guid]] $needToUploadGuids = $null,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=7)]
        [Switch] $doRemoval,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=8)]
        [Object] $lib
    )

    $me = $MyInvocation.MyCommand
    if($null -eq $checkedGuids)
    {
        $checkedGuids = [System.Collections.Generic.List[Guid]]::new()
    } `
    else
    {
        # Nothing, already made the list.
    }

    if($null -eq $extraObjects)
    {
        $extraObjects = [System.Collections.Generic.List[String]]::new()
    } `
    else
    {
        # Nothing, already created the list.
    }

    if($null -eq $needToUploadGuids)
    {
        $needToUploadGuids = [System.Collections.Generic.List[Guid]]::new()
    } `
    else
    {
        # Nothing, already created the list.
    }

    if($null -eq $lib)
    {
        if(-not [String]::IsNullOrEmpty($docLibName))
        {
            if(-not $Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($docLibName))
            {
                # Ok, try to get the document libraries...
                BuildDocumentLibraryDictionary
            } `
            else
            {
                $lib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$docLibName]
            }

            if(($null -eq $lib) -and (-not $Script:HaveError))
            {
                if($Script:connData.ConnectionInformation.SharePointDocumentLibraries.ContainsKey($docLibName))
                {
                    $lib = $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$docLibName]
                } `
                else
                {
                    LogError ("Missing document library for {0} in {1}." -f @($docLibName, $me.Name))
                }
            } `
            else
            {
                # Nothing, we either have a document library to check, or already logged an error.
            }
        } `
        else
        {
            LogError ("Empty document library name and no folder item specified in {0}." -f @($me.Name))
        }
    } `
    else
    {
        # Nothing, already have it.
    }

    if($null -eq $folderItem)
    {
        if(-not $Script:HaveError)
        {
            # Use the library's real name here, but only here...we need $docLibName intact to locate objects in $viablePathsLookupDict
            #   Also, if we are processing a proposal, start at the proposal's folder...
            #   NOTE: The problem here is.... what about items outside the project/proposal folder???
            if($Script:isProposal.IsPresent)
            {
                $foldersAndFiles = [System.Collections.Generic.List[Object]]::new()
                $proposalFoldersToCheck = @(@($Script:viablePathsLookupDict.Values).Where({ ($null -ne $_.SPData) -and (-not [String]::IsNullOrEmpty($_.SPData.FolderName)) }).ForEach({ ($_.SPData.FolderName -split "/")[0] }) | Select-Object -Unique | Sort-Object)
                $a = 0
                while((-not $Script:HaveError) -and ($a -lt $proposalFoldersToCheck.Length))
                {
                    $ffName = "{0}/{1}" -f @($lib.RealName, $proposalFoldersToCheck[$a])
                    LogTrace ("Get files and folders from: {0}" -f @($ffName)) -traceLevel 1
                    $ff = @()
                    try
                    {
                        $ff =  @(Get-PnpFolderItem -Identity $ffName -ErrorAction Stop)
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

                    if(-not $Script:HaveError)
                    {
                        $b = 0
                        while($b -lt $ff.Length)
                        {
                            $foldersAndFiles.Add($ff[$b])
                            $b++
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }

                    $a++
                }
                $foldersAndFiles = @($foldersAndFiles)

#                    $foldersAndFiles = @(Get-PnpFolderItem -Identity ("{0}/{1}" -f @($lib.RealName, $Script:projectName)) -ErrorAction Stop)
            } `
            else
            {
                try
                {
                    $foldersAndFiles = @(Get-PnpFolderItem -Identity $lib.RealName -ErrorAction Stop | Where-Object { $_.Name -ne "Forms" })
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

            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $foldersAndFiles.Length))
            {
                # Don't need the results here... only need them at the original caller.
                #   $folderItem = $foldersAndFiles[$a]
                #   Yes, use $docLibName here vs $lib.RealName because the doc library dictionary still uses it.
                #   $folderItem = $foldersAndFiles[$a]
                $null = CheckObjectsInSharePoint -viablePathsDict $viablePathsDict -viablePathsLookupDict $viablePathsLookupDict -docLibName $docLibName -folderItem $foldersAndFiles[$a] -checkedGuids $checkedGuids -extraObjects $extraObjects -needToUploadGuids $needToUploadGuids -doRemoval:$doRemoval
                $a++
            }
        } `
        else
        {
            # Nothing, already logged an error
        }
    } `
    else
    {
        # What are we looking for??
        # LogInfo ("Checking {0}" -f @($folderItem.ServerRelativeURL))
        ShowProgress -progressID 1 -activity "Checking objects" -counter ($checkedGuids.Count + $extraObjects.Count) -counterMax $viablePathsDict.Count -statusSuffix $folderItem.ServerRelativeURL

        $pathPieces = $folderItem.ServerRelativeURL -split "/"
        <#
            $pathToMatch construction:
                $pathPieces[0] is blank, so skip it.
                $pathPieces[1] = "sites", so skip it.
                $pathPieces[2] = Sharepoint site name, so skip it
                $pathPieces[3] = the document library so skip it. The "real name" may not match what we get from PW, for instance:
                    PW Name, Document Library Title, Document Library URL "Real" Name
                    "Active Projects", "Active Projects", "Shared Documents"
                    "Archive Projects", "Inactive Projects", "Closed Projects"
                    "Archived Projects", "Inactive Projects", "Closed Projects"
                    "Proposals - Archive", "Proposals - Archive", "Proposals  Archive"

                $docLibName/$pathPieces[4]/$pathPieces[...]/$pathPieces[-1]
        #>
        $pathToMatch = "{0}/{1}" -f @($docLibName, ($pathPieces[4..($pathPieces.Length - 1)] -join "/"))

        $i = $extraObjects.BinarySearch($folderItem.ServerRelativeURL)
        if(-not $viablePathsLookupDict.ContainsKey($pathToMatch))
        {
            if($i -lt 0)
            {
                $extraObjects.Insert(-bnot $i, $folderItem.ServerRelativeURL)
            } `
            else
            {
                # Nothing, no dups please.
            }
        } `
        else
        {
            # If we found something we previous added to $extraObjects, remove it.
            if($i -ge 0)
            {
                $extraObjects.RemoveAt($i)
            } `
            else
            {
                # Nothing, don't remove an item that doesn't exist :)
            }

            $matchingVPsToCheck = $viablePathsLookupDict[$pathToMatch]

            if($matchingVPsToCheck.Count -gt 0)
            {
                # Check the folderItem...
                if($folderItem -is [Microsoft.SharePoint.Client.File])
                {
                    # Since we check all versions of a document at once, if we find any of their
                    #   GUIDs in the list, we are assured we checked them all.
                    $i = $checkedGuids.BinarySearch($matchingVPsToCheck[0].SourceObject.DocumentGUID)
                    if($i -lt 0)
                    {
                        # Haven't checked any of these yet...or rather, we haven't added the Document GUIDs to the list.

                        if(-not $matchingVPsToCheck[0].SPData.Verified)
                        {
                            # CheckDocumentVersions is an all or nothing deal.  Either all document versions are good, or none are...
                            #    So if we make it through it, then we can say we've .SPData.Verified all matching documents, and not have to check them again.
                            #   $documentsToCheck = @($matchingVPsToCheck)
                            $deleteAndReupload, $spDocVers = CheckDocumentVersions -documentsToCheck @($matchingVPsToCheck) -doRemoval:$doRemoval

                            if(-not $Script:HaveError)
                            {
                                if(-not $deleteAndReupload)
                                {
                                    # If $spDocVers.SPDocument is null, then the document doesn't exist.
                                    #    Further, if $spDocVers.Versions is null, then there are no other versions of the document.
                                    $doesNotExist = (($null -ne $spDocVers) -and ($null -eq $spDocVers.SPDocument))

                                    $matchingVPsToCheck | ForEach-Object {
                                        $vp = $_

                                        $i = $checkedGuids.BinarySearch($vp.SourceObject.DocumentGUID)
                                        if($i -lt 0)
                                        {
                                            # Add this one to the list.
                                            $checkedGuids.Insert(-bnot $i, $vp.SourceObject.DocumentGUID)
                                        } `
                                        else
                                        {
                                            # Nothing, all is well.
                                        }

                                        if($doesNotExist)
                                        {
                                            $vp.SPData.Processed = $false
                                            $i = $needToUploadGuids.BinarySearch($vp.SourceObject.DocumentGUID)
                                            if($i -lt 0)
                                            {
                                                $needToUploadGuids.Insert(-bnot $i, $vp.SourceObject.DocumentGUID)
                                            } `
                                            else
                                            {
                                                # no dupes please
                                            }
                                        } `
                                        else
                                        {
                                            $vp.SPData.Processed = $true
                                            $vp.SPData.Verified = $true
                                            $Script:itemsVerified++
                                            if(($Script:itemsVerified % 500) -eq 0)
                                            {
                                                ExportViablePathsStructure -viablePathsDict $viablePathsDict
                                            }
                                            LogTrace ("Marked {0} as verified" -f @((SourceObjectIdentity $vp))) -traceLevel 1
                                        }
                                    }
                                } `
                                else
                                {
                                    $matchingVPsToCheck | ForEach-Object {
                                        $vp = $_
                                        $vp.SPData.Processed = $false
                                        $i = $needToUploadGuids.BinarySearch($vp.SourceObject.DocumentGUID)
                                        if($i -lt 0)
                                        {
                                            $needToUploadGuids.Insert(-bnot $i, $vp.SourceObject.DocumentGUID)
                                        } `
                                        else
                                        {
                                            # no dupes please
                                        }
                                    }
                                } `
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # save a little time, we've already checked and verified this object.
                            $matchingVPsToCheck | ForEach-Object {
                                $vp = $_

                                $i = $checkedGuids.BinarySearch($vp.SourceObject.DocumentGUID)
                                if($i -lt 0)
                                {
                                    # Add this one to the list.
                                    $checkedGuids.Insert(-bnot $i, $vp.SourceObject.DocumentGUID)
                                } `
                                else
                                {
                                    # Nothing, all is well.
                                }
                            }
                        }
                    } `
                    else
                    {
                        # Already checked these..
                    }
                } `
                elseif($folderItem -is [Microsoft.SharePoint.Client.Folder])
                {
                    # Skip the Forms folder...
                    if($folderItem.Name -ne "Forms")
                    {
                        # Now what??  ;-)

                        if($matchingVPsToCheck.Count -eq 1)
                        {
                            $matchingVPsToCheck[0].SPData.Processed = $true
                            $i = $checkedGuids.BinarySearch($matchingVPsToCheck[0].SourceObject.DocumentGUID)
                            if($i -lt 0)
                            {
                                $checkedGuids.Insert(-bnot $i, $matchingVPsToCheck[0].SourceObject.DocumentGUID)
                            } `
                            else
                            {
                                # Skip this source object, already checked it.
                            }
                        }
                        else  # Already ruled out 0 above, so this has to be -gt 1
                        {
                            # More than 1 matching folder???
                            LogError ("Multiple matching viable path objects for folder {0} in {1}." -f @($folderItem.ServerRelativeURL, $me.Name))
                            @($matchingVPsToCheck).ForEach({
                                LogError ("`t{0}:{1}" -f @($_.SourceObject.DocumentGUID, $_.SourceObject.FullPath))
                            })
                        }

                        # Now check all the sub-folders and files...
                        try
                        {
                            $foldersAndFiles = @(Get-PnpFolderItem -Identity $folderItem.ServerRelativeURL -ErrorAction Stop | Where-Object { $_.Name -ne "Forms" })
                        }
                        catch
                        {
                            LogError ("Failed to retrieve folders and files for {0} in {1}." -f @($folderItem.ServerRelativeURL, $me.Name))
                        }

                        if(-not $Script:HaveError)
                        {
                            $b = 0
                            while((-not $Script:HaveError) -and ($b -lt $foldersAndFiles.Length))
                            {
                                # Don't need the results here... only need them at the original caller.
                                #    $folderItem = $foldersAndFiles[$b]
                                $null = CheckObjectsInSharePoint -viablePathsDict $viablePathsDict -viablePathsLookupDict $viablePathsLookupDict -docLibName $docLibName -folderItem $foldersAndFiles[$b] -checkedGuids $checkedGuids -extraObjects $extraObjects -needToUploadGuids $needToUploadGuids -doRemoval:$doRemoval

                                $b++
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error
                        }
                    } `
                    else
                    {
                        # Nothing, skip Forms (Should be filtered out above, but incase it makes it through, ignore it.)
                    }
                } `
                else
                {
                    LogWarning ("Unknown SharePoint object")
                }
            } `
            else
            {
                # Missing folder, or maybe one I don't have to check...
            }
        }
    }

    $retval = [PSCustomObject]@{
        CheckedGUIDs = $checkedGuids
        ReuploadGUIDs = $needToUploadGuids
        ExtraSPObjects = $extraObjects
    }
    return @( ,$retval)
}

function AddSharePointFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String] $libraryName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String] $parentFolder,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.String] $newFolderName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [AllowEmptyString()]
        [System.String] $description = [String]::Empty,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [AllowEmptyString()]
        [System.String] $originalName = [String]::Empty
    )

    $me = $MyInvocation.MyCommand
    $nf = $null
    try
    {
        $nf = Add-PnPFolder -Folder $parentFolder -Name $newFolderName -ErrorAction Stop
        $Script:reportData.Folders.Created++
    }
    catch
    {
        if($Error.Exception.Message -match "already exists.$")
        {
            $Script:reportData.Folders.PreExisting++
            $Error.Clear()
            $folderURL = "{0}/{1}" -f @($parentFolder, $newFolderName)
            try
            {
                $nf = Get-PnPFolder -URL $folderURL -ErrorAction Stop
            }
            catch
            {
                LogError ("Failed to retrieve existing folder {0} after attempting to create a new folder in {1}." -f @($folderURL, $me.Name))
            }
        } `
        else
        {
            LogError ("Failed to create new folder {0} under {1} in {2}." -f @($newFolderName, $parentFolder, $me.Name))
        }
    }

    if(-not $Script:HaveError)
    {
        if($null -ne $nf)
        {
            $setDocFields = $false

            if((-not [String]::IsNullOrEmpty($originalName)) -and ($originalName -ne $newFolderName))
            {
                $spDocFieldName = GetSharePointDocumentFieldNameForProperty -libraryName $libraryName -propertyName "OriginalName"
                if(-not $Script:HaveError)
                {
                    if(-not [String]::IsNullOrEmpty($spDocFieldName))
                    {
                        $null = TestForSPDocumentLibraryField -libraryName $libraryName -fieldName $spDocFieldName
                        if(-not $Script:HaveError)
                        {
                            $nf.ListItemAllFields[$spDocFieldName] = $originalName
                            $setDocFields = $true
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        LogError("Missing document field name for attribute OriginalName in {0}." -f @(me.Name))
                    }
                } `
                else
                {
                    # Nothing, already logged an error
                }
            } `
            else
            {
                # Nothing.
            }

            if(-not [String]::IsNullOrEmpty($description))
            {
                if($description -ne $newFolderName)
                {
                    $spDocFieldName = GetSharePointDocumentFieldNameForProperty -libraryName $libraryName -propertyName "FileDescription"
                    if(-not $Script:HaveError)
                    {
                        if(-not [String]::IsNullOrEmpty($spDocFieldName))
                        {
                            $null = TestForSPDocumentLibraryField -libraryName $libraryName -fieldName $spDocFieldName
                            if(-not $Script:HaveError)
                            {
                                $nf.ListItemAllFields[$spDocFieldName] = $description
                                $setDocFields = $true
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            LogError("Missing document field name for attribute FileDescription in {0}." -f @(me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error
                    }
                } `
                else
                {
                    # Nothing, don't set the description to the name of the folder.
                }
            } `
            else
            {
                # Nothing, no description.
            }

            if(-not $Script:HaveError)
            {
                if($setDocFields)
                {
                    try
                    {
                        $nf.ListItemAllFields.Update()
                        Invoke-PnPQuery
                    }
                    catch
                    {
                        LogError ("Failed to apply description `"{0}`" to folder {1}/{2} in {3}." -f @($description, $parentFolder, $newFolderName, $me.Name))
                    }
                } `
                else
                {
                    # Nothing...
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            LogError ("Failed to set folder description on new folder {0} under {1} in {2}.  Null folder returned from Add-PnPFolder." -f @($parentFolder, $newFolderName, $me.Name))
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }

    return @(, $nf)
}

function CreateSharePointSubFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object[]] $foldersToCreate
    )

    # Get all the folder objects from viablePathsDict that have not been created and are either for another project, or are more than 2 levels deep.  The first 2 levels are the "Active Projects" | "Inactive Projects" and the project folder
    #    The project folder is created separately so it's properties can be set.
    #    $folderObjectsToCreate = @(@($viablePathsDict.Values) | Where-Object { ($_.Paths.Length -gt 2) -and ($_.SourceObject -is [PWPS_DAB.CommonTypes+ProjectWiseFolder]) -and (-not $_.SPData.Processed) } | Sort-Object @{E={ ($_.Paths -join "/") }})
    $folderObjects = @($foldersToCreate | Sort-Object @{E={ ($_.Paths -join "/") }})

    LogInfo ("{0} Folder objects" -f @($folderObjects.Length))
    $folderObjectsToCreate = @($folderObjects | Where-Object { ($_.Paths.Length -gt 1) -and (-not $_.SPData.Processed) })
    LogInfo ("{0} Folders to create" -f @($folderObjectsToCreate.Length))
    $foldersCreated = 0
    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $folderObjectsToCreate.Length))
    {
        $fo = $folderObjectsToCreate[$a]

        $libInfo = ($null -ne $fo.LibInfo) ? $fo.LibInfo : (GetLibraryDataFromObj -obj2Upload $fo -CreateMissingLibrary)
        if($null -ne $libInfo)
        {
            $folderPieces = @($libInfo.FolderURL -split "/")
            $parentFolder = $folderPieces[0..($folderPieces.Length - 2)] -join "/"
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

            $originalPaths = $fo.SourceObject.FullPath -split "\\"
            if($originalPaths[0] -match "^(Active|Archive[d]*) Projects")
            {
                $originalPaths = @($originalPaths | Select-Object -Skip 1)
            } `
            else
            {
                # Nothing, keep it...
            }

            $originalNameIdx = $folderPieces.Length - 4     # Need to remove the empty entry before site, then site, then the site name, and finally adjust for 0 based array
            if($originalPaths.Length -ge $originalNameIdx)
            {
                if($originalPaths[$originalNameIdx].StartsWith($folderName))
                {
                    $originalName = $originalPaths[$originalNameIdx]
                } `
                else
                {
                    LogWarning ("Original folder name [{0}] does not start with folder name [{1}] in {2}." -f @($originalPaths[$originalNameIdx], $folderName, $me.Name))
                }
            } `
            else
            {
                LogWarning ("Unable to determine original folder name fromm {0}:{1} in {2}.  Original name index [{3}] is beyond the length of full path." -f @($fo.SourceObject.DocumentGUID, $fo.SourceObject.FullPath, $me.Name, $originalNameIdx))
                $originalName = [String]::Empty
            }

            ShowProgress -progressID 1 -activity "Creating project folders" -counter $a -counterMax $folderObjectsToCreate.Length -statusSuffix $libInfo.FolderURL
            LogInfo ("Creating folder {0}/{1}" -f @($parentFolder, $folderName))

            while((-not [String]::IsNullOrEmpty($folderName)) -and ($folderName.EndsWith(".")))
            {
                $folderName = $folderName.SubString(0, $folderName.Length - 1)
            }

            #  $newFolderName = $folderName
            $spFolder = AddSharePointFolder -libraryName $libInfo.LibraryName -parentFolder $parentFolder -newFolderName $folderName -description $description -originalName $originalName

            if(-not $Script:HaveError)
            {
                if($null -ne $spFolder)
                {
                    $foldersCreated++
                    $fo.SPData.SPFile.ServerRelativeURL = $spFolder.ServerRelativeURL
                    $fo.SPData.Processed = $true
                    $fo.SPData.Verified = $true
                    $fo.SPData.WhenUploaded = [DateTime]::Now.ToString()
                } `
                else
                {
                    LogWarning ("Missing Sharepoint folder object for {0}/{1} in {2}.  Null value returned from AddSharePointFolder." -f @($parentFolder, $folderName, $me.Name))
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
        $a++
    }
    ShowProgress -progressID 1 -complete
    LogInfo ("Created {0} folders" -f @($foldersCreated))
}

function GetDocumentFromProjectWise
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object] $td
    )

    $me = $MyInvocation.MyCommand
    $retval = [PSCustomObject]@{
        SrcPath = [String]::Empty
        IsTemp = $false
        Missing = $false
    }

    if($null -ne $td)
    {
        LogInfo ("Going to ProjectWise for {0}:{1}" -f @($td.DocumentGUID, $td.FullPath))
        try
        {
            $pwFile = Get-PWDocumentsByGUIDs -DocumentGUIDs $td.DocumentGUID -ErrorAction Stop

            try
            {
                $outPath = $pwFile.CopyOut([System.IO.Path]::GetTempPath())
                if(-not [String]::IsNullOrEmpty($outPath))
                {
                    if($outPath -notmatch "Error copying document")
                    {
                        $outFI = [System.IO.FileInfo]::new($outPath)
                        if([System.IO.File]::Exists($outPath))
                        {
                            $retval.SrcPath = $outFI.FullName
                            $retval.IsTemp = $true
                        } `
                        else
                        {
                            LogError ("CopyOut seemed to work, but the resulting file [{0}] does not exist in {1}." -f @($outPath, $me.Name))
                        }
                    } `
                    else
                    {
                        LogWarning ("File {0} is missing from storage and PW was unable to copy it to the local drive." -f @($pwFile.FullPath))
                        $retval.SrcPath = [String]::Empty
                        $retval.IsTemp = $false
                        $retval.Missing = $true
                    }
                } `
                else
                {
                    LogError ("CopyOut seemed to work, but the resulting file name is empty in {0}." -f @($me.Name))
                }
            }
            catch
            {
                LogError ("Failed to copy out {0} in {1}" -f @($pwFile.FullPath, $me.Name))
            }
        }
        catch
        {
            LogError ("Failed to retrieve document by GUID from ProjectWise for {0}:{1} in {2}" -f @($td.DocumentGUID, $td.FullPath, $me.Name))
        }
    }
    else
    {
        LogError ("Null td in {0}." -f @($me.Name))
    }

    return @(, $retval)
}

function GetPWDocumentStorageLocation
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object] $td,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $useVersion
    )

    $me = $MyInvocation.MyCommand
    $retval = [PSCustomObject]@{
        SrcPath = [String]::Empty
        IsTemp = $false
        Missing = $false
    }

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
                $retval.SrcPath = "{0}\{1}" -f @($srcFolder, $td.Name)
            } `
            else
            {
                $retval.SrcPath = "{0}\ver{1:D5}\{2}" -f @($srcFolder, $td.VersionSequence, $td.Name)
            }

            if([System.IO.File]::Exists($retval.SrcPath))
            {
                $fi = [System.IO.FileInfo]::new($retval.SrcPath)
                if($fi.Length -ne $td.FileSize)
                {
                    LogWarning ("{0} file size mismatch in {3}.  TD.FileSize: {1}, FI.Length: {2}" -f @($retval.SrcPath, $td.FileSize, $fi.Length, $me.Name))
                    LogWarning ("Getting fresh copy from ProjectWise")
                    if($Script:DoExport.IsPresent)
                    {
                        if(-not $Script:connectedToPW)
                        {
                            ConnectToPW
                        } `
                        else
                        {
                            # Nothing, already connected.
                        }

                        if(-not $Script:HaveError)
                        {
                            $retval = GetDocumentFromProjectWise -td $td
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        # Nothing???  Not exporting, so we really don't need the src path...
                    }
                } `
                else
                {
                    # Nothing, all is well.
                }
            } `
            else
            {
                LogWarning ("Source file {0} not found for {1}:{2} in {3}." -f @($retval.SrcPath, $td.DocumentGUID, $td.FullPath, $me.Name))
                $retval.SrcPath = [String]::Empty

                if($Script:DoExport.IsPresent)
                {
                    if(-not $Script:connectedToPW)
                    {
                        ConnectToPW
                    } `
                    else
                    {
                        # Nothing, already connected.
                    }

                    if(-not $Script:HaveError)
                    {
                        $retval = GetDocumentFromProjectWise -td $td
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else
                {
                    # Nothing???  Not exporting, so we really don't need the src path...
                }
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

    return @( , $retval)
}

function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KB","MB","GB","TB","PB","EB","ZB","YB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}

function UploadDocumentToSP
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $obj2Upload,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $useVersion
    )

    $me = $MyInvocation.MyCommand
    $libInfo = ($null -ne $obj2Upload.LibInfo) ? $obj2Upload.LibInfo : (GetLibraryDataFromObj -obj2Upload $obj2Upload -CreateMissingLibrary)

    # If I have to go to PW to get the file, it will be copied out to a temporary file, so let the caller know.
    if($null -ne $libInfo)
    {
        $td = $obj2Upload.SourceObject
        if(-not $td.IsSet)
        {
            if(-not $obj2Upload.SPData.Processed)
            {
                if($td.FileSize -gt 0)
                {
                    $srcFileData = GetPWDocumentStorageLocation -pwData $pwData -td $td -useVersion:$useVersion
                } `
                else
                {
                    # It's a 0 byte size file, so it's not like I really need the file...
                    $srcFileData = [PSCustomObject]@{
                        SrcPath = $obj2Upload.SourceObject.FullPath
                        IsTemp = $false
                        Missing = $false
                    }
                }

                if(-not [String]::IsNullOrEmpty($srcFileData.SrcPath))
                {
                    #$sw1 = [System.Diagnostics.Stopwatch]::new()
                    #$sw1.Start()
                    $spDocValues = BuildDocumentProperties -obj2Upload $obj2Upload
                    #$sw1.Stop()
                    #LogTrace ("BDP: {0}" -f @($sw1.Elapsed.ToString())) -traceLevel 1

                    if($null -ne $spDocValues)
                    {
                        $successful = $false
                        $retries = 0

                        if($td.FileSize -gt 0)
                        {
                            LogInfo ("Uploading {0} Size {1} from {2}" -f @($obj2Upload.SourceObject.FullPath, (Format-StorageNumber $obj2Upload.SourceObject.FileSize), $srcFileData.SrcPath))
                        } `
                        else
                        {
                            LogInfo ("Creating 'no content' file for {0}" -f @($obj2Upload.SourceObject.FullPath))
                        }

                        do {
                            if($td.FileSize -eq 0)
                            {
                                $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes("No Contents"))
                                try
                                {
                                    LogTrace ("Upload file: {0}`tParent Folder: {1}" -f @($obj2Upload.Paths[-1], $libInfo.FolderURL)) -traceLevel 1
                                    $spFile = Add-PnPFile -FileName $obj2Upload.Paths[-1] -Folder $libInfo.FolderURL -Stream $stream -Values $spdocValues -ErrorAction Stop
                                    $Script:reportData.Documents.Created++
                                    $obj2Upload.SPData.Verified = $true
                                    $successful = $true
                                }
                                catch
                                {
                                    LogError ("Failed to create no content file {0} in folder {1} in {2}." -f @($td.Name, $libInfo.FolderURL, $me.Name))
                                }
                            } `
                            else
                            {
                                try
                                {
                                    # I can't just assume I can upload a file ... if I do, what will happen if I'm uploading a file which doesn't belong to this project?
                                    #    Initially, nothing, but what about later when I export the actual project?
                                    #    If I just upload all the documents and versions, I will be doubling the version history.

                                    if($obj2Upload.SPData.FileName.StartsWith("."))
                                    {
                                        $newName = "noname{0}" -f @($obj2Upload.SPData.FileName)
                                        if($d.Paths[-1] -eq $obj2Upload.SPData.FileName)
                                        {
                                            $obj2Upload.Paths[-1] = $newName
                                        }
                                        $obj2Upload.SPData.FileName = $newName
                                    } `
                                    else
                                    {
                                        # Nothing, leave it alone.
                                    }

                                    $folder = $libInfo.FolderURL
                                    while((-not [String]::IsNullOrEmpty($folder)) -and ($folder.EndsWith(".")))
                                    {
                                        $folder = $folder.SubString(0, $folder.Length - 1)
                                    }

                                    $folder = $folder.Replace("./","/")
                                    # LogTrace ("Path: {0}`tFolder: {1}" -f @($srcFileData.SrcPath, $folder)) -traceLevel 1
                                    $spFile = Add-PnPFile -Path $srcFileData.SrcPath -Folder $folder -Values $spdocValues -NewFileName $obj2Upload.SPData.FileName.Trim('.',' ') -ErrorAction Stop

                                    $successful = $true
                                }
                                catch
                                {
                                    if($Error[0].Exception.Message -match "Save Conflict")
                                    {
                                        $retries++
                                        if($retries -lt $Script:MaxUploadetries)
                                        {
                                            $Error.Clear()
                                            Start-Sleep -Seconds ($retries * 3)
                                        } `
                                        else
                                        {
                                            LogError ("Failed to upload {0}:{1} to {2} after {3} retries in {4}." -f @($td.DocumentGUID, $srcFileData.SrcPath, $libInfo.FolderURL, $retries, $me.Name))
                                            @($spdocValues.Keys).ForEach({
                                                LogInfo ("`t{0} = {1}" -f @($_, $spdocValues[$_]))
                                            })
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("Failed to upload {0}:{1} to {2} in {3}." -f @($td.DocumentGUID, $srcFileData.SrcPath, $libInfo.FolderURL, $me.Name))
                                    }
                                }

                                if(-not $Script:HaveError)
                                {
                                    if($null -ne $spFile)
                                    {
                                        $Script:reportData.Documents.Created++
                                        $Script:reportData.Size.Uploaded += $td.FileSize

                                        if([String]::IsNullOrEmpty($obj2Upload.SPData.WhenUploaded))
                                        {
                                            $obj2Upload.SPData.WhenUploaded = [DateTime]::Now.ToString()
                                        } `
                                        else
                                        {
                                            # Nothing
                                        }
                                        if($obj2Upload.SPData.SPFile.ServerRelativeURL -ne $spFile.ServerRelativeURL)
                                        {
                                            $obj2Upload.SPData.SPFile.ServerRelativeURL = $spFile.ServerRelativeURL
                                        } `
                                        else
                                        {
                                            # Nothing
                                        }
                                        if($obj2Upload.SPData.SPFile.VersionLabel -ne $spFile.UIVersionLabel)
                                        {
                                            $obj2Upload.SPData.SPFile.VersionLabel =  $spFile.UIVersionLabel
                                        } `
                                        else
                                        {
                                            # Nothing
                                        }
                                    } `
                                    else
                                    {
                                        LogWarning ("Null object returned from Add-PnPFile for {0} in {1}." -f @($libInfo.FolderURL, $obj2Upload.SPData.FileName.Trim('.',' ')))
                                    }
                                } `
                                else
                                {
                                    # Nothing, already logged an error.
                                }
                            }
                        } while((-not $Script:HaveError) -and (-not $successful) -and ($retries -lt $Script:MaxUploadetries))

                        if(-not $Script:HaveError)
                        {
                            if($successful)
                            {
                                if($null -ne $spFile)
                                {
                                    $obj2Upload.SPData.Processed = $true
                                } `
                                else
                                {
                                    LogWarning ("Missing spFile for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
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
                        # Nothing, already logged an error
                    }

                    if($srcFileData.IsTemp)
                    {
                        # Let's make doubly sure we are on the local machine....
                        #   the projectwise share paths will ALWAYS start with '\' i.e. \\cdc-pwfs01.powereng.com\PW\Prod\DMS_Active_06\active_dms_storage06\d5989895\322-0901_180015_Basis of Design_2024-07-12.docx
                        #   whereas a local path will always start with a drive letter...
                        if($srcFileData.SrcPath[0] -ne "\")
                        {
                            try
                            {
                                Remove-Item -Path $srcFileData.SrcPath -Force -Confirm:$false -ErrorAction Stop
                            }
                            catch
                            {
                                LogWarning ("Failed to remove temp file {0} in {1}." -f @($srcFileData.SrcPath, $me.Name))
                                if($Error.Count -gt 0)
                                {
                                    LogWarning $Error[0].Exception.Message
                                } `
                                else
                                {
                                    # Nothing, no exception message to log.
                                }
                            }
                        } `
                        else
                        {
                            LogInfo ("IsTemp is true, but source path doesn't seem local, not deleting [{0}] in {1}." -f @($srcFileData.SrcPath, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, leave PW files alone...
                    }
                } `
                else
                {
                    # Nothing, already displayed an error or warning.
                    if($srcFileData.Missing)
                    {
                        $obj2Upload.SPData.Verified = $true     # Verified that the file doesn't exist...
                    } `
                    else
                    {
                        # Nothing, no assumptions please
                    }
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
    } `
    else
    {
        # Nothing, already logged an error.
    }
}
<#
    UploadDocumentsToSharePoint assumes all documents in $docsToUpload are the same file and [-1] is the current version.
#>
function UploadDocumentsToSharePoint
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Object] $pwData,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.Object[]] $docsToUpload
    )

    # No need to check for unique FullPaths.  If we are here, the CheckDocumentVersions has already done that.
    #  Also, CheckDocumentVersions decided we needed to upload, it's all or nothing....

    # Make sure documents are sorted in FullPath/VersionSequence order
    $docsToUpload = @($docsToUpload | Sort-Object @{E={ $_.SourceObject.VersionSequence }})

    <#
        When the data was collected from ProjectWise if a flat set was encountered, I collected all versions of the referenced document, so no need to get funky with stuff here.
    #>

    $a = 0
    while($a -lt $docsToUpload.Length)
    {
        if($docsToUpload.Length -gt 1)
        {
            ShowProgress -progressID 2 -activity "Uploading document versions" -counter $a -counterMax $docsToUpload.Length -statusSuffix ("{0} ({1})" -f @($docsToUpload[$a].SourceObject.Name, (Format-StorageNumber $docsToUpload[$a].SourceObject.FileSize)))
        } `
        else
        {
            # No progress bar for a single file.
        }

# For debugging:     $obj2Upload = $docsToUpload[$a]; [Switch] $useVersion = ($a -ne ($docsToUpload.Length - 1))
        UploadDocumentToSP -pwData $pwData -obj2Upload $docsToUpload[$a] -useVersion:($a -ne ($docsToUpload.Length - 1))

        if(-not $Script:HaveError)
        {
            $totalSizeUploaded += $docsToUpload[$a].SourceObject.FileSize

            if(($Script:reportData.Documents.Created % 1000) -eq 0)
            {
                ExportViablePathsStructure -viablePathsDict $viablePathsDict
            } `
            else
            {
                # Nothing
            }
        } `
        else
        {
            # Nothing, already displayed an error.
        }
        $a++
    }

    if($docsToUpload.Length -gt 1)
    {
        ShowProgress -progressID 2 -complete
    } `
    else
    {
        # Nothing, no progress bar for 1 file.
    }

    # If this (or any versions of this document) is a flat set reference, then we need to update the ServerRelativeURLs for the documents.
    if(@($docsToUpload.Where({ $_.IsFlatSetReference })).Length -gt 0)
    {
        if($docsToUpload[-1].SPData.Processed)
        {
            if(-not [String]::IsNullOrEmpty($docsToUpload[-1].SPData.SPFile.ServerRelativeURL))
            {
                $spDocVers = GetSPDocumentVersions -docURL $docsToUpload[-1].SPData.SPFile.ServerRelativeURL
                if($null -ne $spDocVers)
                {
                    if($null -ne $spDocVers.SPDocument)
                    {
                        $a = 1     # Remember, start at 1, [0] is the current version....
                        while($a -lt $spDocVers.SPDocument.Versions.Count)
                        {
                            if($null -ne $spDocVers.SPDocument.Versions[$a].FieldValues)
                            {
                                if($spDocVers.SPDocument.Versions[$a].FieldValues.ContainsKey("DocumentVersion"))
                                {
                                    $doc = $docsToUpload.Where({ $_.SourceObject.Version -eq $spDocVers.SPDocument.Versions[$a].FieldValues["DocumentVersion"] })
                                    if($null -ne $doc)
                                    {
                                        $ver = $spDocVers.Versions.Where({ $_.Id -eq $spDocVers.SPDocument.Versions[$a].VersionId })
                                        if($null -ne $ver)
                                        {
                                            $doc.SPData.SPFile.ServerRelativeURL = $ver.Url
                                            $doc.SPData.SPFile.VersionLabel = $ver.VersionLabel
                                        } `
                                        else
                                        {
                                            LogWarning ("Unable to locate URL version Id {0} of {1} after upload in {2}." -f @($spDocVers.SPDocument.Versions[$a].VersionId, $docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                                        }
                                    } `
                                    else
                                    {
                                        LogWarning ("Unable to locate version {0} of {1} after upload in {2}." -f @($spDocVers.SPDocument.Versions[$a].FieldValues["DocumentVersion"], $docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                                    }
                                } `
                                else
                                {
                                    LogWarning ("Missing SharePoint document versions 'SPDocument' FieldValues['DocumentVersion'] for idx {0} after uploading {1} in {2}." -f @($a, $docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                                }
                            } `
                            else
                            {
                                LogWarning ("Missing SharePoint document versions 'SPDocument' FieldValues for idx {0} after uploading {1} in {2}." -f @($a, $docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                            }
                            $a++
                        }
                    } `
                    else
                    {
                        LogWarning ("Missing SharePoint document versions 'SPDocument' after uploading {0} in {1}." -f @($docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                    }
                } `
                else
                {
                    LogWarning ("Missing SharePoint document versions after uploading {0} in {1}." -f @($docsToUpload[-1].SPData.SPFile.ServerRelativeURL, $me.Name))
                }
            } `
            else
            {
                LogWarning ("Missing server relative URL for {0}:{1} in {2}" -f @($docsToUpload[-1].SourceObject.DocumentGUID, $docsToUpload[-1].SourceObject.FullPath, $me.Name))
            }
        } `
        else
        {
            LogWarning ("Document not marked processed {0}:{1} in {2}" -f @($docsToUpload[-1].SourceObject.DocumentGUID, $docsToUpload[-1].SourceObject.FullPath, $me.Name))
        }
    } `
    else
    {
        # Nothing, no flat set references here, so don't worry about it.
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

<#
    Going to only log warning here, and likely when I create the "flat sets" in SharePoint, so I can get everything done that can be done without manual intervention.
#>
function UpdateFileURLsForFlatSetReferences
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    $checkedGUIDs = [System.Collections.Generic.List[Guid]]::new()
    $fsReferencedDocs = @(@($viablePathsDict.Values).Where({ $_.IsFlatSetReference }))

    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $fsReferencedDocs.Length))
    {
        ShowProgress -progressID 1 -activity "Updating reference doc URLs" -counter $a -counterMax $fsReferencedDocs.Length
        # We need the current version of an flat set referenced document so we can get its version history

        $i = $checkedGUIDs.BinarySearch($fsReferencedDocs[$a].SourceObject.DocumentGUID)
        if($i -lt 0)
        {
            $checkedGUIDs.Insert(-bnot $i, $fsReferencedDocs[$a].SourceObject.DocumentGUID)
            $fsReferencedDocVersions = @(@($viablePathsDict.Values).Where({ $_.SourceObject.FullPath -eq $fsReferencedDocs[$a].SourceObject.FullPath }) | Sort-Object @{E={$_.SourceObject.VersionSequence }})
            $fsReferencedDocVersions.ForEach({
                $i = $checkedGUIDs.BinarySearch($_.SourceObject.DocumentGUID)
                if($i -lt 0)
                {
                    $checkedGUIDs.Insert(-bnot $i, $_.SourceObject.DocumentGUID)
                } `
                else
                {
                    # Nothing, no dupes please.
                }
            })

            if($fsReferencedDocVersions[-1].SPData.Processed)
            {
                $libInfo = GetLibraryDataFromObj -obj2Upload $fsReferencedDocVersions[-1]
                if($null -ne $libInfo)
                {
                    if(-not [String]::IsNullOrEmpty($libInfo.FileURL))
                    {
                        $fsReferencedDocVersions[-1].SPData.SPFile.ServerRelativeURL = $libInfo.FileURL
                        $spDocVers = GetSPDocumentVersions -docURL $libInfo.FileURL
                        if($null -ne $spDocVers)
                        {
                            if($null -ne $spDocVers.SPDocument)
                            {
                                if($spDocVers.SPDocument.Versions.Count -gt 0)
                                {
                                    $b = 0     # Remember, start at 1, [0] is the current version....
                                    while($b -lt $spDocVers.SPDocument.Versions.Count)
                                    {
                                        if($spDocVers.SPDocument.Versions.Count -gt 1)
                                        {
                                            ShowProgress -progressID 2 -activity "Updating versions" -counter $b -counterMax $spDocVers.SPDocument.Versions.Count
                                        } `
                                        else
                                        {
                                            # Only show for 2 or more versions...
                                        }
                                        if($spDocVers.SPDocument.Versions[$b].IsCurrentVersion)
                                        {
                                            $fsReferencedDocVersions[-1].SPData.SPFile.VersionLabel = $spDocVers.SPDocument.Versions[$b].VersionLabel
                                        } `
                                        else
                                        {
                                            if($null -ne $spDocVers.SPDocument.Versions[$b].FieldValues)
                                            {
                                                if($spDocVers.SPDocument.Versions[$b].FieldValues.ContainsKey("DocumentVersion"))
                                                {
                                                    $doc = $fsReferencedDocVersions.Where({ $_.SourceObject.Version -eq $spDocVers.SPDocument.Versions[$b].FieldValues["DocumentVersion"] })
                                                    if($null -ne $doc)
                                                    {
                                                        $ver = $spDocVers.Versions.Where({ $_.Id -eq $spDocVers.SPDocument.Versions[$b].VersionId })
                                                        if($null -ne $ver)
                                                        {
                                                            $doc.SPData.SPFile.ServerRelativeURL = $ver.Url
                                                            $doc.SPData.SPFile.VersionLabel = $ver.VersionLabel
                                                        } `
                                                        else
                                                        {
                                                            LogWarning ("Unable to locate version Id {0} of {1} after upload in {2}." -f @($spDocVers.SPDocument.Versions[$b].VersionId, $libInfo.FileURL, $me.Name))
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogWarning ("Unable to locate flat set referenced document version {0} of {1} after upload in {2}." -f @($spDocVers.SPDocument.Versions[$b].FieldValues["DocumentVersion"], $libInfo.FileURL, $me.Name))
                                                    }
                                                } `
                                                else
                                                {
                                                    LogWarning ("Missing SharePoint document versions .SPDocument.FieldValues['DocumentVersion'] for idx {0} of {1} in {2}." -f @($b, $libInfo.FileURL, $me.Name))
                                                }
                                            } `
                                            else
                                            {
                                                LogWarning ("Missing `$spDocVers.SPDocument.FieldValues for idx {0} of {1} in {2}." -f @($b, $libInfo.FileURL, $me.Name))
                                            }
                                        }

                                        $b++
                                    }
                                    if($spDocVers.SPDocument.Versions.Count -gt 1)
                                    {
                                        ShowProgress -progressID 2 -complete
                                    } `
                                    else
                                    {
                                        # Only show for 2 or more versions...
                                    }
                                } `
                                else
                                {
                                    LogWarning ("Missing all SharePoint version data for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                                }
                            } `
                            else
                            {
                                LogWarning ("Missing `$spDocVers.SPDocument for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                            }
                        } `
                        else
                        {
                            LogWarning ("Missing `$spDocVers for {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                        }
                    } `
                    else
                    {
                        LogWarning ("Missing `$libInfo.FileURL for {0}:{1} in {2}" -f @($fsReferencedDocVersions[-1].SourceObject.DocumentGUID, $fsReferencedDocVersions[-1].SourceObject.FullPath, $me.Name))
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogWarning ("Document not marked processed {0}:{1} in {2}" -f @($fsReferencedDocVersions[-1].SourceObject.DocumentGUID, $fsReferencedDocVersions[-1].SourceObject.FullPath, $me.Name))
            }
        } `
        else
        {
            # No need to check it twice.
        }

        $a++
    }
    ShowProgress -progressID 1 -complete
}

function ProcessFlatSets
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object[]] $fsToProcess
    )

    $me = $MyInvocation.MyCommand
    $a = 0
    while((-not $Script:HaveError) -and ($a -lt $fsToProcess.Length))
    {
        $good2Go = $true
        $fs = $fsToProcess[$a]

        # Until proven otherwise, assume the flat set is good.
        #   If anything has to be created then the flatset is not verified.
        #   The flatset is only verified on a subsequent run when everything is already in place.
        $fsVerified = $true

        # Is there an old 'crusty' document set for this flat set?

        $libInfo = GetLibraryDataFromObj -obj2Upload $fs
        ShowProgress -progressID 1 -activity "Building flat sets" -counter $a -counterMax $fsToProcess.Length -statusSuffix $libInfo.FileURL

        $fsFolder = $null
        if($null -ne $libInfo)
        {
            try
            {
                $existingDS = @(Get-PnpFolderItem -Identity $libInfo.FolderURL -ErrorAction Stop).Where({ ($_.Name -eq $fs.SPData.FileName) })
                if($existingDS.Length -gt 0)
                {
                    if($existingDS.Length -eq 1)
                    {
                        if($existingDS[0].ProgID -eq "Sharepoint.DocumentSet")
                        {
                            # This was an old document set, so we have to delete it and create a folder, therefore, it's not verified.
                            $fsVerified = $false
                            try
                            {
                                # Found an old document set... let's delete it.
                                LogInfo ("Removing old document set {0}/{1}" -f @($libInfo.FolderURL, $existingDS[0].Name))
                                Remove-PnpFolder -Name $existingDS[0].Name -Folder $libInfo.FolderURL -Force
                                $existingDS = $null
                            }
                            catch
                            {
                                LogWarning ("Failed to remove document set {0} in folder {1} in {2}." -f @($existingDS[0].Name, $libInfo.FolderURL, $me.Name))
                                $good2Go = $false
                            }
                        } `
                        else
                        {
                            # Convert $existingDS from an array to an object
                            $fsFolder = $existingDS[0]
                        }
                    } `
                    else
                    {
                        LogWarning ("There are {0} document sets named {1} in {2}.  Not removing in {3}." -f @($existingDS.Length, $fs.SPData.FileName, $libInfo.FolderURL, $me.Name))
                        $good2Go = $false
                        $fsVerified = $false
                    }
                } `
                else
                {
                    # Nothing... no old flat set.
                }
            }
            catch
            {
                LogWarning ("Failed to retrieve folder items for {0} in {1}." -f @($libInfo.FolderURL, $me.Name))
                $good2Go = $false
                $fsVerified = $false
            }

            if((-not $Script:HaveError) -and ($good2Go))
            {
                $fsExistingLinks = [System.Collections.Generic.SortedDictionary[String,String]]::new()
                # Do I need to create the flat set folder?
                if($null -eq $fsFolder)
                {
                    # Yup, create the folder...

                    # TODO: Create a new folder .... HEY!!!!  I can create "flat set" folders when I create the rest of the folders.... Hrm.... next version.
                    LogInfo ("Creating 'flat set' [{0}] in {1}." -f @($fs.SPData.FileName, $libInfo.FolderURL))
                    $fsFolder = AddSharePointFolder -libraryName $libInfo.LibraryName -parentFolder $libInfo.FolderURL -newFolderName $fs.SPData.FileName -description $fs.SourceObject.Description -originalName (($fs.SourceObject.FullPath -split "\\")[-1])
                    $fsVerified = $false
                } `
                else
                {
                    # Nope, folder already exists.
                    LogInfo ("Using existing 'flat set' [{0}] in {1}." -f @($fs.SPData.FileName, $libInfo.FolderURL))
                    try
                    {
                        $existingFnF = @(Get-PnPFolderItem -Identity $libInfo.FileURL -ErrorAction Stop)
                        $b = 0
                        while($b -lt $existingFnF.Length)
                        {
                            if($existingFnF[$b].Name -match "\.url$")
                            {
                                try
                                {
                                    $matchingLine = [String]::Empty
                                    $linkContents = Get-PnPFile -Url ([Uri]::EscapeUriString($existingFnF[$b].ServerRelativeUrl)) -AsString -ErrorAction Stop
                                    $contentLines = @($linkContents -split "`n")
                                    $matchingLine = @($contentLines -match "^URL=(.*)$") | Select-Object -First 1
                                    if((-not [String]::IsNullOrEmpty($matchingLine)) -and ($matchingLine -match "^URL=(.*)$"))
                                    {
                                        $fsExistingLinks.Add($existingFnF[$b].Name, $Matches[1])
                                    } `
                                    else
                                    {
                                        LogWarning ("Unable to extract reference URL from {0} in {1}." -f @($existingFnF[$b].ServerRelativeUrl, $me.Name))
                                        LogWarning ("Removing faulty file.")
                                        try
                                        {
                                            Remove-PnpFile -ServerRelativeUrl $existingFnF[$b].ServerRelativeUrl -Force
                                        }
                                        catch
                                        {
                                            LogWarning ("Failed to remove faulty reference {0} in {1}." -f @($existingFnF[$b].ServerRelativeUrl, $me.Name))
                                            $good2Go = $false
                                        }

                                        $good2Go = $false
                                        $fsVerified = $false
                                    }
                                }
                                catch
                                {
                                    LogWarning ("Unable to get link contents for {0} in {1}." -f @($existingFnF[$b].ServerRelativeUrl, $me.Name))
                                    $fsVerified = $false
                                }
                            } `
                            else
                            {
                                LogWarning ("Flat set reference is not a .url file [{0}] in {1}." -f @($existingFnF[$b].ServerRelativeUrl, $me.Name))
                                $fsVerified = $false
                                # Need to remove it.
                            }
                            $b++
                        }
                    }
                    catch
                    {
                        LogWarning ("Failed to get existing contents of {0} in {1}." -f @($libInfo.FileURL, $me.Name))
                        LogWarning ("Potentially {0} document reference links not created." -f @($fs.SourceObject.FlatSetReferences.Count))
                        $good2Go = $false
                        $fsVerified = $false
                    }
                }

                if((-not $Script:HaveError) -and $good2Go)
                {
                    if($null -ne $fsFolder)
                    {
                        # Now to create all the links to referenced documents....

                        # Does this flat set have any referenced documents?
                        if($fs.SourceObject.FlatSetReferences.Count -gt 0)
                        {
                            # Sure does...

                            # Get all the referenced documents for this flat set.
                            $fsRefs = @($viablePathsDict.Values).Where({ $fs.SourceObject.FlatSetReferences.Contains($_.SourceObject.DocumentGUID) })

                            # Let's make sure everything is in order for them
                            $b = 0
                            $existingCount = 0
                            while($b -lt $fs.SourceObject.FlatSetReferences.Count)
                            {
                                ShowProgress -progressID 2 -activity "Creating reference links" -counter $b -counterMax $fs.SourceObject.FlatSetReferences.Count
                                # First off, do we have a document for the reference?
                                if($viablePathsDict.ContainsKey($fs.SourceObject.FlatSetReferences[$b]))
                                {
                                    # Yes, there is a document for this reference.

                                    $fsRef = $viablePathsDict[$fs.SourceObject.FlatSetReferences[$b]]

                                    $fsRefsWithDuplicateNames = @($fsRefs.Where({ $_.SourceObject.Name -eq $fsRef.SourceObject.Name }) | Sort-Object @{E={ $_.SourceObject.DocumentGUID }})

                                    if($fsRef.SPData.Processed)
                                    {
                                        if(-not [String]::IsNullOrEmpty($fsRef.SPData.SPFile.ServerRelativeURL))
                                        {
                                            # I discovered there are flat sets which reference files with the exact same names.  To combat this,
                                            #    I'll create the link names by adding a suffix to the file for the duplicate names.
                                            #    So I'll end up with something like:
                                            #
                                            #         file.pdf.url
                                            #         file.pdf_1.url
                                            #         file.pdf_2.url
                                            #
                                            #    Placing the _X after the file extension won't matter, because the short cut the .url file points to will be correct.
                                            $linkNameSuffix = [String]::Empty
                                            if($fsRefsWithDuplicateNames.Length -gt 1)
                                            {
                                                $idx = $fsRefsWithDuplicateNames.IndexOf($fsRef)
                                                if($idx -gt 0)
                                                {
                                                    $linkNameSuffix = "_{0}" -f @(($idx + 1))
                                                } `
                                                else
                                                {
                                                    # Only add a suffix for idx > 0
                                                }
                                            } `
                                            else
                                            {
                                                # only add a link suffix for duplicate name reference...
                                            }

                                            # If the link already exists and has the right URL, then skip it... otherwise remove it so we can recreate it.
                                            $linkName = "{0}{1}.url" -f @($fsRef.SPData.FileName, $linkNameSuffix)
                                            #                                                                  NOT EQUAL (you want $false)
                                            #                                                                             |
                                            #                                                                             v
                                            if($fsExistingLinks.ContainsKey($linkName))
                                            {
                                                if($fsExistingLinks[$linkName] -ne $fsRef.SPData.SPFile.ServerRelativeURL)
                                                {
                                                    # Need to create the link, but need to remove the existing link first.
                                                    $badLinkURL = "{0}/{1}" -f @($libInfo.FileURL, $linkName)
                                                    try
                                                    {
                                                        Remove-PnpFile -ServerRelativeUrl $badLinkURL -Force
                                                        $null = $fsExistingLinks.Remove($linkName)
                                                    }
                                                    catch
                                                    {
                                                        LogWarning ("Failed to remove faulty reference {0} in {1}." -f @($badLinkURL, $me.Name))
                                                        $good2Go = $false
                                                    }
                                                } `
                                                else
                                                {
                                                    # Nothing, either the link does not exist, or it does and is set to the correct reference.
                                                }
                                            } `
                                            else
                                            {
                                                # The link does not exist, so we need to create it.
                                            }

                                            if($good2Go)
                                            {
                                                # If the link is still in $fsExistingLinks, then it's good...
                                                if(-not $fsExistingLinks.ContainsKey($linkName))
                                                {
                                                    # Get the properties from the referenced document
                                                    $linkParams = BuildDocumentProperties -obj2Upload $fsRef

                                                    if(-not $Script:HaveError)
                                                    {
                                                        $refLib = GetLibraryDataFromObj -obj2Upload $fsRef

                                                        if($null -ne $refLib)
                                                        {
                                                            if($refLib.LibraryName -ne $libInfo.LibraryName)
                                                            {
                                                                # Make sure all the document fields exist on the library.  This was the result of document fields missing from a project library for a document referenced in another document librayr
                                                                #   Yes, I'm using the right library below... I want to make sure the document fields from a referenced document library are in-place on this project's document library
                                                                @($linkParams.Keys).ForEach({
                                                                    $null = TestForSPDocumentLibraryField -libraryName $libInfo.LibraryName -fieldName $_

                                                                    if($Script:HaveError)
                                                                    {
                                                                        break
                                                                    }
                                                                })
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, same library, no need to check document fields.
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            LogWarning ("Missing document library data for {0} in {1}." -f @((SourceObjectIdentity -srcObj $fsRef), $me.Name))
                                                            $fsVerified = $false
                                                        }

                                                        if(-not $Script:HaveError)
                                                        {
                                                            # Create the link to the document...
                                                            CreateLinkInFolder -linkName $linkName -linkURL $fsRef.SPData.SPFile.ServerRelativeURL -folderURL $libInfo.FileURL -linkParams $linkParams
                                                            $fsVerified = $false
                                                            if(-not $Script:HaveError)
                                                            {
                                                                if(-not $fs.SPData.DocSetLinksCreated.Contains($fsRef.SourceObject.DocumentGUID))
                                                                {
                                                                    $i = $fs.SPData.DocSetLinksCreated.BinarySearch($fsRef.SourceObject.DocumentGUID)
                                                                    if($i -lt 0)
                                                                    {
                                                                        $fs.SPData.DocSetLinksCreated.Insert(-bnot $i, $fsRef.SourceObject.DocumentGUID)
                                                                    } `
                                                                    else
                                                                    {
                                                                        # Nothing, no dupes please.
                                                                    }
                                                                } `
                                                                else
                                                                {
                                                                    # Nothing, only need it once.
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, already logged an error.
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, already logged an error.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, already logged an error -- Failed to build document properties
                                                    }
                                                } `
                                                else
                                                {
                                                    # Remove the link now so we'll know if there's anything extra...
                                                    $null = $fsExistingLinks.Remove($linkName)
                                                    # This link is already there, so add it to the list of links created.
                                                    $i = $fs.SPData.DocSetLinksCreated.BinarySearch($fsRef.SourceObject.DocumentGUID)
                                                    if($i -lt 0)
                                                    {
                                                        $fs.SPData.DocSetLinksCreated.Insert(-bnot $i, $fsRef.SourceObject.DocumentGUID)
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, no dupes please.
                                                    }
                                                    $existingCount++
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, already logged a warning or error
                                            }
                                        } `
                                        else
                                        {
                                            LogWarning ("Missing .SPData.SPFile.ServerRelativeURL for {0} in {1}." -f @((SourceObjectIdentity -srcObj $viablePathsDict[$fs.SourceObject.FlatSetReferences[$b]]), $me.Name))
                                            $fsVerified = $false
                                        }
                                    } `
                                    else
                                    {
                                        LogWarning ("{0} does not appear to have been processed in {1}." -f @((SourceObjectIdentity -srcObj $viablePathsDict[$fs.SourceObject.FlatSetReferences[$b]]), $me.Name))
                                        $fsVerified = $false
                                    }
                                } `
                                else
                                {
                                    LogWarning ("Missing document {0} for flat set {1} in {2}." -f @($fs.SourceObject.FlatSetReferences[$b], (SourceObjectIdentity -srcObj $fs), $me.Name))
                                    $fsVerified = $false
                                }
                                $b++
                            }
                            ShowProgress -progressID 2 -complete

                            if((-not $Script:HaveError) -and ($good2Go))
                            {
                                if($fsExistingLinks.Count -gt 0)
                                {
                                    LogWarning ("Removing {0} extra references in {1}." -f @($fsExistingLinks.Count, $libInfo.FileURL))
                                    $badLinkKeys = @($fsExistingLinks.Keys)
                                    while((-not $Script:HaveError) -and ($c -lt $badLinkKeys.Length))
                                    {
                                        $badLink = "{0}/{1}" -f @($libInfo.FileURL, $badLinkKeys[$c])
                                        try
                                        {
                                            Remove-PnpFile -ServerRelativeUrl $badLink -Force
                                        }
                                        catch
                                        {
                                            LogWarning ("Failed to remove extra reference {0} in {1}." -f @($badLink, $me.Name))
                                            $good2Go = $false
                                        }
                                        $a++
                                    }
                                } `
                                else
                                {
                                    # Nothing, nothing extra to remove.
                                }

                                if(($existingCount -eq $fs.SourceObject.FlatSetReferences.Count) -or ($fs.SPData.DocSetLinksCreated.Count -eq $fs.SourceObject.FlatSetReferences.Count))
                                {
                                    LogInfo ("All flat set references [{0}] accounted for {1}." -f @($fs.SourceObject.FlatSetReferences.Count, $libInfo.FileURL))
                                } `
                                else
                                {
                                    LogInfo ("Flat Set count mismatch.  Should have created {0} links, only created {1} for {2}." -f @($fs.SourceObject.FlatSetReferences.Count, $fs.SPData.DocSetLinksCreated.Count, $libInfo.FileURL))
                                    $fsVerified = $false
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error or warning.
                            }
                        } `
                        else
                        {
                            LogWarning ("{0} says it's a flat set, but has {1} flat set references." -f @((SourceObjectIdentity -srcObj $fs), $fs.SourceObject.FlatSetReferences.Count))
                            $fsVerified = $false
                        }
                    } `
                    else
                    {
                        $good2Go = $false
                        $fsVerified = $false
                    }
                } `
                else
                {
                    # Nothing, aLready logged an error or warning
                }
            } `
            else
            {
                # Nothing, already logged an error or warning.
            }
        } `
        else
        {
            LogWarning ("Missing document library data for {0} in {1}." -f @((SourceObjectIdentity -srcObj $fs), $me.Name))
            $fsVerified = $false
        }

        $fs.SPData.Verified = $fsVerified

        $a++
    }
    ShowProgress -progressID 1 -complete
}

function BuildVerificationLookupDictionary_old2
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $rebuild
    )

    if(($null -eq $Script:viablePathsLookupDict) -or ($rebuild.IsPresent))
    {
        $Script:viablePathsLookupDict = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]]::new()

        # First add unverified objects...
        $b = 0
        $viablePathKeys = @($viablePathsDict.Keys)
        while((-not $Script:HaveError) -and ($b -lt $viablePathKeys.Length))
        {
            $vp = $viablePathsDict[$viablePathKeys[$b]]
            ShowProgress -progressID 1 -activity "Building verification lookup dictionary" -counter $b -counterMax $viablePathKeys.Length

            if(-not $vp.SPData.Verified)
            {
                $vp.SPData.Processed = $false
                # Ignore the pwProjectPath and project folder...
                if($vp.Paths.Length -ge 1)
                {
                    $pathToCheck = $vp.Paths -join "/"
                    if(-not [String]::IsNullOrEmpty($pathToCheck))
                    {
                        if(-not $Script:viablePathsLookupDict.ContainsKey($pathToCheck))
                        {
                            $Script:viablePathsLookupDict.Add($pathToCheck, [System.Collections.Generic.List[Object]]::new())
                        } `
                        else
                        {
                            # Nothing, don't want dups...
                        }
                        $Script:viablePathsLookupDict[$pathToCheck].Add($vp)
                    } `
                    else
                    {
                        LogError("Empty paths for {0} in {1}." -f @((SourceObjectIdentity -srcObj $vp), $me.Name))
                        break
                    }
                } `
                else
                {
                    # Nothing, ignoring the pwProjectPath folder.
                }
            } `
            else
            {
                # Already verified... skip it.
            }

            $b++
        }

        ShowProgress -progressID 1 -complete
    } `
    else
    {
        # Nothing, already built it.
    }
}

function BuildVerificationLookupDictionary_old
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $rebuild
    )

    $viablePathsDictValues = @($viablePathsDict.Values)

    if(($null -eq $Script:viablePathsLookupDict) -or ($rebuild.IsPresent))
    {
        $Script:viablePathsLookupDict = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]]::new()

        # First add unverified objects...
        $b = 0
        $viablePathKeys = @($viablePathsDict.Keys)
        while((-not $Script:HaveError) -and ($b -lt $viablePathKeys.Length))
        {
            $vp = $viablePathsDict[$viablePathKeys[$b]]
            ShowProgress -progressID 1 -activity "Building verification lookup dictionary" -counter $b -counterMax $viablePathKeys.Length

            if(-not $vp.SPData.Verified)
            {
                $vp.SPData.Processed = $false
                # Ignore the pwProjectPath and project folder...
                if($vp.Paths.Length -ge 1)
                {
                    $pathToCheck = $vp.Paths -join "/"
                    if(-not [String]::IsNullOrEmpty($pathToCheck))
                    {
                        if(-not $Script:viablePathsLookupDict.ContainsKey($pathToCheck))
                        {
                            $Script:viablePathsLookupDict.Add($pathToCheck, [System.Collections.Generic.List[Object]]::new())
                            $Script:viablePathsLookupDict[$pathToCheck].Add($vp)
                        } `
                        else
                        {
                            # Nothing, don't want dups...
                            $existing = @($Script:viablePathsLookupDict[$pathToCheck].Where({ ($_.SourceObject.MyType -eq $vp.SourceObject.MyType) -and ($_.SourceObject.DocumentGUID -eq $vp.SourceObject.DocumentGUID)}))
                            if($existing.Length -eq 0)
                            {
                                $Script:viablePathsLookupDict[$pathToCheck].Add($vp)
                            } `
                            else
                            {
                                # No, really, don't want dups.
                            }
                        }

                        # Now add all parent folders for the object to the dictionary
                        $p = $vp.Paths.Length - 2
                        while($p -gt 0)
                        {
                            # Get a smaller list of folder objects to look at.
                            $folderVPs = @($viablePathsDictValues | Where-Object { ($_.Paths.Length -eq ($p + 1)) -and ($_.SourceObject.MyType -eq "ProjectWiseFolder") })
                            $folderPathToMatch = $vp.Paths[0..$p] -join "/"

                            # Narrow the list even more.
                            $folderVPs = @($folderVPs | Where-Object { ($_.Paths[0..$p] -join "/") -eq $folderPathToMatch })

                            $folderVPs.ForEach({
                                if(-not $Script:viablePathsLookupDict.ContainsKey($folderPathToMatch))
                                {
                                    $Script:viablePathsLookupDict.Add($folderPathToMatch, [System.Collections.Generic.List[Object]]::new())
                                    $Script:viablePathsLookupDict[$folderPathToMatch].Add($_)
                                } `
                                else
                                {
                                    # Nothing, don't want dups...
                                }
                            })
                            $p--
                        }
                    } `
                    else
                    {
                        LogError("Empty paths for {0} in {1}." -f @((SourceObjectIdentity -srcObj $vp), $me.Name))
                        break
                    }
                } `
                else
                {
                    # Nothing, ignoring the pwProjectPath folder.
                }
            } `
            else
            {
                # Already verified... skip it.
            }

            $b++
        }

        ShowProgress -progressID 1 -complete
    } `
    else
    {
        # Nothing, already built it.
    }
}

function BuildVerificationLookupDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $rebuild
    )

    $viablePathsDictValues = @($viablePathsDict.Values)

    $vpByPathLength = [System.Collections.Generic.SortedDictionary[int,[System.Collections.Generic.SortedDictionary[Guid,Object]]]]::new()
    $vpByPath = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.SortedDictionary[Guid,Object]]]]::new()

    $a = 0
    while($a -lt $viablePathsDictValues.Length)
    {
        $path = $viablePathsDictValues[$a].Paths -join "/"
        if(-not $vpByPath.ContainsKey($path))
        {
            $vpByPath.Add($path, [System.Collections.Generic.SortedDictionary[Guid,Object]]::new())
        }

        if(-not $vpByPath[$path].ContainsKey($viablePathsDictValues[$a].SourceObject.DocumentGuid))
        {
            $vpByPath[$path].Add($viablePathsDictValues[$a].SourceObject.DocumentGuid, $viablePathsDictValues[$a])
        }

        $a++
    }

<#
    $a = 0
    while($a -lt $viablePathsDictValues.Length)
    {
        $b = $viablePathsDictValues[$a].Paths.Length

        if(-not $vpByPathLength.ContainsKey($b))
        {
            $vpByPathLength.Add($b, [System.Collections.Generic.SortedDictionary[Guid,Object]]::new())
        } `
        else
        {
            # Nothing, already have a list...
        }

        if(-not $vpByPathLength[$b].ContainsKey($viablePathsDictValues[$a].SourceObject.DocumentGuid))
        {
            $vpByPathLength[$b].Add($viablePathsDictValues[$a].SourceObject.DocumentGuid, $viablePathsDictValues[$a])
        }
        $a++
    }
#>
    if(($null -eq $Script:viablePathsLookupDict) -or ($rebuild.IsPresent))
    {
        $Script:viablePathsLookupDict = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]]::new()

        # First add unverified objects...
        $b = 0
        $viablePathKeys = @($viablePathsDict.Keys)
        while((-not $Script:HaveError) -and ($b -lt $viablePathKeys.Length))
        {
            $vp = $viablePathsDict[$viablePathKeys[$b]]
            ShowProgress -progressID 1 -activity "Building verification lookup dictionary" -counter $b -counterMax $viablePathKeys.Length

            if(-not $vp.SPData.Verified)
            {
                $vp.SPData.Processed = $false
                # Ignore the pwProjectPath and project folder...
                if($vp.Paths.Length -ge 1)
                {
                    $pathToCheck = $vp.Paths -join "/"
                    if(-not [String]::IsNullOrEmpty($pathToCheck))
                    {
                        if(-not $Script:viablePathsLookupDict.ContainsKey($pathToCheck))
                        {
                            $Script:viablePathsLookupDict.Add($pathToCheck, [System.Collections.Generic.List[Object]]::new())
                            $Script:viablePathsLookupDict[$pathToCheck].Add($vp)
                        } `
                        else
                        {
                            # Nothing, don't want dups...
                            $existing = @($Script:viablePathsLookupDict[$pathToCheck].Where({ ($_.SourceObject.MyType -eq $vp.SourceObject.MyType) -and ($_.SourceObject.DocumentGUID -eq $vp.SourceObject.DocumentGUID)}))
                            if($existing.Length -eq 0)
                            {
                                $Script:viablePathsLookupDict[$pathToCheck].Add($vp)
                            } `
                            else
                            {
                                # No, really, don't want dups.
                            }
                        }

                        # Now add all parent folders for the object to the dictionary
                        $p = $vp.Paths.Length - 2
                        while($p -gt 0)
                        {
                            # Get a smaller list of folder objects to look at.
                            $folderPathToMatch = $vp.Paths[0..$p] -join "/"

                            if($vpByPath.ContainsKey($folderPathToMatch))
                            {
                                $folderVPs = @(@($vpByPath[$folderPathToMatch].Values).Where({ $_.SourceObject.MyType -eq "ProjectWiseFolder" }))
                            } `
                            else
                            {
                                $folderVPs = @()
                            }

                            # $folderVPs = @($viablePathsDictValues | Where-Object { ($_.Paths.Length -eq ($p + 1)) -and ($_.SourceObject.MyType -eq "ProjectWiseFolder") })
                            # $folderVPs = @(@($vpByPathLength[($p + 1)].Values).Where({ ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and (($_.Paths[0..$p] -join "/") -eq $folderPathToMatch) }))

                            # Narrow the list even more.
                            # $folderVPs = @($folderVPs | Where-Object { ($_.Paths[0..$p] -join "/") -eq $folderPathToMatch })

                            $folderVPs.ForEach({
                                if(-not $Script:viablePathsLookupDict.ContainsKey($folderPathToMatch))
                                {
                                    $Script:viablePathsLookupDict.Add($folderPathToMatch, [System.Collections.Generic.List[Object]]::new())
                                    $Script:viablePathsLookupDict[$folderPathToMatch].Add($_)
                                } `
                                else
                                {
                                    # Nothing, don't want dups...
                                }

                                #if($vpByPathLength[($p + 1)].ContainsKey($_.SourceObject.DocumentGuid))
                                #{
                                #    $null = $vpByPathLength[($p + 1)].Remove($_.SourceObject.DocumentGuid)
                                #}
                            })
                            $p--
                        }
                    } `
                    else
                    {
                        LogError("Empty paths for {0} in {1}." -f @((SourceObjectIdentity -srcObj $vp), $me.Name))
                        break
                    }
                } `
                else
                {
                    # Nothing, ignoring the pwProjectPath folder.
                }
            } `
            else
            {
                # Already verified... skip it.
            }

            $b++
        }

        ShowProgress -progressID 1 -complete
    } `
    else
    {
        # Nothing, already built it.
    }
}

function FixNames
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

    $changes = 0
    $a = 0
    $pwKeys = @($pwData.ProjectWiseObjects.Keys)
    while($a -lt $pwKeys.Length)
    {
        if($pwData.ProjectWiseObjects[$pwKeys[$a]].FullPath -match "\.\\")
        {
            $fpBefore = $pwData.ProjectWiseObjects[$pwKeys[$a]].FullPath
            $pwData.ProjectWiseObjects[$pwKeys[$a]].FullPath = $pwData.ProjectWiseObjects[$pwKeys[$a]].FullPath.Replace(".\","\")
            $fpAfter = $pwData.ProjectWiseObjects[$pwKeys[$a]].FullPath

            if($fpBefore -ne $fpAfter)
            {
                $changes++
                LogTrace "FullPath" -traceLevel 1
                LogTrace ("`tBefore: [{0}]" -f @($fpBefore)) -traceLevel 1
                LogTrace ("`t After: [{0}]" -f @($fpAfter)) -traceLevel 1
            }

            if($viablePathsDict.ContainsKey($pwKeys[$a]))
            {
                $vp = $viablePathsDict[$pwKeys[$a]]
                $p = 0
                $pathsBefore = $vp.Paths -join "/"
                $paths2Check = $vp.Paths.Length - 2
                if($vp.SourceObject.MyType -eq "ProjectWiseFolder")
                {
                    $paths2Check++
                }
                while($p -lt $paths2Check)   # The last entry is the file name...unless this is for a folder...
                {
                    while((-not [String]::IsNullOrEmpty($vp.Paths[$p])) -and ($vp.Paths[$p].EndsWith(".")))
                    {
                        $vp.Paths[$p] = $vp.Paths[$p].SubString(0, $vp.Paths[$p].Length - 1)
                    }
                    $p++
                }
                $pathsAfter = $vp.Paths -join "/"

                if($pathsBefore -ne $pathsAfter)
                {
                    $changes++
                    LogTrace "Paths" -traceLevel 1
                    LogTrace ("`tBefore: [{0}]" -f @($pathsBefore)) -traceLevel 1
                    LogTrace ("`t After: [{0}]" -f @($pathsAfter)) -traceLevel 1
                }

                $fldrNameBefore = $vp.SPData.FolderName
                while((-not [String]::IsNullOrEmpty($vp.SPData.FolderName)) -and ($vp.SPData.FolderName.EndsWith(".")))
                {
                    $vp.SPData.FolderName = $vp.SPData.FolderName.Substring(0, $vp.SPData.FolderName.Length - 1)
                }

                if(-not [String]::IsNullOrEmpty($vp.SPData.FolderName))
                {
                    $vp.SPData.FolderName = $vp.SPData.FolderName.Replace("./","/")
                }
                $fldrNameAfter = $vp.SPData.FolderName

                if($fldrNameBefore -ne $fldrNameAfter)
                {
                    $changes++
                    LogTrace "FolderName" -traceLevel 1
                    LogTrace ("`tBefore: [{0}]" -f @($fldrNameBefore)) -traceLevel 1
                    LogTrace ("`t After: [{0}]" -f @($fldrNameAfter)) -traceLevel 1
                }
            }
        }
        $a++
    }

    return ($changes -gt 0)
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
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    <#
    $changesMade = FixNames -pwData $pwData -viablePathsDict $viablePathsDict
    if($changesMade)
    {
        ExportPWDataToJSON -pwData $pwData
        ExportViablePathsStructure -viablePathsDict $viablePathsDict
    } `
    else
    {
        # Nothing.
    }
    #>
    if(-not $Script:HaveError)
    {
        $me = $MyInvocation.MyCommand
        $PSStyle.Progress.View = 'Minimal'
        $PSStyle.Progress.MaxWidth = [Console]::WindowWidth - 10
        $Error.Clear()
        $sw = [System.Diagnostics.Stopwatch]::new()
        $sw.Start()

        $sw.Stop()
        LogInfo ("Checking for existing folders and files...")

        <#
            Make sure document libraries exist for any project which might be referenced in the project.
            Since "Project" folders follow this pattern:
                Active Projects\Project Name
                Archive Projects\Project Name
                Archived Projects\Project Name

            After I FixUpViablePaths, project folders (document libraries names) will be viable path object
            where .Paths.Length -eq 0

            And further, since I don't modify the pwProjectPath or project name folder, I can narrow this
            down to only object where splitting .SourceObject.FullPath by "\" is length 2.

            From here, the document library name I need to check will be [1] of the split.
        #>
        $documentLibrariesName = [System.Collections.Generic.List[String]]::new()
        @($viablePathsDict.Values).ForEach({
            $vp = $_
            if($vp.Paths.Length -gt 0)
            {
                $i = $documentLibrariesName.BinarySearch($vp.Paths[0])
                if($i -lt 0)
                {
                    $documentLibrariesName.Insert(-bnot $i, $vp.Paths[0])
                }
            }
        })

        if(-not $Script:isProposal.IsPresent)
        {
            $a = 0
            while((-not $Script:HaveError) -and ($a -lt $documentLibrariesName.Count))
            {
                # Create/Check the document libraries needed for this project.
                #   I could check $Script:connData.ConnectionInformation.SharePointDocumentLibraries for the libary, but calling
                #       CreateProjectDocumentLibrary does that and checks for document fields.
                # For the project folders, .SPData.FolderName will be the name of the document library...

                # $newDocLibName = $documentLibrariesName[$a]
                CreateProjectDocumentLibrary -newDocLibName $documentLibrariesName[$a]

                $a++
            }

            if(-not $Script:HaveError)
            {
                CreateProjectLink -pwData $pwData -viablePathsDict $viablePathsDict
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            # Don't mess with document libraries for Proposals, but we do need to verify there is a folder for the proposal.

        }

        if(-not $Script:HaveError)
        {
            # Now let's check everything that's already in the project's document library...yeah, I know...ugly

            BuildVerificationLookupDictionary -viablePathsDict $viablePathsDict
            if(-not $Script:HaveError)
            {
                if($Script:viablePathsLookupDict.Count -gt 0)
                {
                    $a = 0
                    while((-not $Script:HaveError) -and ($a -lt $documentLibrariesName.Count))
                    {
                        if($a -eq 0)
                        {
                            <#
                                Continue proposal checks here.
                            #>
                            $checked = CheckObjectsInSharePoint -viablePathsDict $viablePathsDict -viablePathsLookupDict $Script:viablePathsLookupDict -docLibName $documentLibrariesName[$a] -doRemoval
                        } `
                        else
                        {    #     $docLibName = $documentLibrariesName[$a]; $checkedGuids = $checked.CheckedGUIDs; $extraObjects = $checked.ExtraSPObjects; $needToUploadGuids = $checked.ReuploadGUIDs
                            $checked = CheckObjectsInSharePoint -viablePathsDict $viablePathsDict -viablePathsLookupDict $Script:viablePathsLookupDict -docLibName $documentLibrariesName[$a] -checkedGuids $checked.CheckedGUIDs -extraObjects $checked.ExtraSPObjects -needToUploadGuids $checked.ReuploadGUIDs -doRemoval
                        }

                        $a++
                    }
                    ShowProgress -progressID 1 -complete
                    ExportViablePathsStructure -viablePathsDict $viablePathsDict

                    if(-not $Script:HaveError)
                    {
                        LogInfo ("Checked {0} objects" -f @($checked.CheckedGUIDs.Count))
                        # $unchecked are all the objects not found in SharePoint.
                        # $checked.ReuploadGUIDs are all the objects we need to remove and reupload -- once I verify this script is functioning correctly, I'll just have CheckObjectsInSharePoint do the removal.
                        # $checked.ExtraSPObjects are stuff I can't explain and probably need to remove.
                        $checked.CheckedGUIDs | ForEach-Object {
                            $viablePathsDict[$_].SPData.Processed = $true
                        }
                        $uncheckedOrReUpload = @($viablePathsDict.Values).Where({ ($_.Paths.Length -gt 0) -and (($_.SourceObject.DocumentGUID -notin $checked.CheckedGUIDs) -or ($_.SourceObject.DocumentGUID -in $checked.ReuploadGUIDs)) -and (-not $_.SPData.Verified)})
                        $foldersToCreate = @($uncheckedOrReUpload.Where({ ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and (-not [String]::IsNullOrEmpty($_.SPData.FolderName)) }))
                        $allFilesToUpload = $uncheckedOrReUpload.Where({ ($_.SourceObject.MyType -eq "ProjectWiseDocument") })
                        $stdFilesToUpload = @($allFilesToUpload.Where({ -not $_.SourceObject.IsSet }))
                        $fsToProcess = @(@($viablePathsDict.Values).Where({ ($_.SourceObject.IsSet) -and (-not $_.SPData.Verified) }))

                        LogInfo ("Remaining unchecked: {0}" -f @($uncheckedOrReUpload.Length))
                        LogInfo ("Folders to create: {0}" -f @($foldersToCreate.Length))
                        LogInfo ("Uncheck documents: {0}" -f @($allFilesToUpload.Count))
                        LogInfo ("Unchecked 'normal' documents: {0}" -f @($stdFilesToUpload.Count))
                        if($null -ne $checked.ReuploadGUIDs)
                        {
                            LogInfo ("Objects to re-upload: {0}" -f @($checked.ReuploadGUIDs.Count))
                        } `
                        else
                        {
                            LogInfo ("No objects to reupload.")
                        }

                        if($null -ne $checked.ExtraSPObjects)
                        {
                            LogInfo ("Extra objects: {0}" -f @($checked.ExtraSPObjects.Count))
                        } `
                        else
                        {
                            LogInfo ("No extra objects.")
                        }
                        LogInfo ("Flat sets: {0}" -f @($fsToProcess.Length))
                        $fsRefs = 0
                        $fsToProcess.ForEach({ $fsRefs += $_.SourceObject.FlatSetReferences.Count })
                        LogInfo ("Flat set references: {0}" -f @($fsRefs))

                        # Create unchecked folders.
                        if($foldersToCreate.Length -gt 0)
                        {
                            CreateSharePointSubFolders -pwData $pwData -foldersToCreate $foldersToCreate
                        } `
                        else
                        {
                            # Nothing, No folders to create
                        }

                        if($stdFilesToUpload.Count -gt 0)
                        {
                            $totalUploadSize = 0
                            $uploadedSize = 0
                            $stdFilesToUpload | ForEach-Object {
                                $totalUploadSize += $_.SourceObject.FileSize
                            }
                            $sw = [System.Diagnostics.StopWatch]::new()
                            # Upload unchecked standard files.
                            $pathKeys = @($Script:viablePathsLookupDict.Keys)
                            $a = 0
                            $uploadedFiles = 0
                            $sw.Start()
                            while((-not $Script:HaveError) -and ($a -lt $pathKeys.Length))
                            {
                                $pc = [float] $uploadedSize / [float] $totalUploadSize
                                if($pc -gt 1)
                                {
                                    $pc = [float] 0.99
                                }
                                $statusSuffix = (Format-StorageNumber $totalUploadSize)
                                if($uploadedSize -gt 0)
                                {
                                    $elapsedTicks = $sw.ElapsedTicks
                                    $ticksPerByte = $elapsedTicks / $uploadedSize
                                    $totalETATicks = $ticksPerByte * $totalUploadSize
                                    $remainingETATicks = $totalETATicks - $elapsedTicks
                                    $etaTS = [TimeSpan]::new($remainingETATicks)
                                    $etaDT = [DateTime]::Now.Add($etaTS)
                                    $statusSuffix = "{0} of {1} ({2,7:P} Complete)| Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @((Format-StorageNumber $uploadedSize), (Format-StorageNumber $totalUploadSize), $pc, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString())
                                }
                                ShowProgress -progressID 1 -activity "Uploading documents" -counter $uploadedFiles -counterMax $stdFilesToUpload.Count -statusSuffix $statusSuffix

                                $pathToUpload = $pathKeys[$a]
                                $documentsToUpload = @($stdFilesToUpload.Where({ ($_.Paths -join "/") -eq $pathToUpload }) | Sort-Object @{ E={ $_.SourceObject.VersionSequence } })
                                if($documentsToUpload.Length -gt 0)
                                {
                                    UploadDocumentsToSharePoint -pwData $pwData -docsToUpload $documentsToUpload  # $docsToUpload = $documentsToUpload
                                    if(-not $Script:HaveError)
                                    {
                                        $uploadedFiles += $documentsToUpload.Length
                                        $documentsToUpload.ForEach({
                                            $uploadedSize += $_.SourceObject.FileSize
                                        })
                                    } `
                                    else
                                    {
                                        # Nothing, already logged and error.
                                    }
                                } `
                                else
                                {
                                    # Nothing, no documents to upload
                                }

                                $a++
                            }
                            ShowProgress -progressID 1 -complete
                        } `
                        else
                        {
                            LogInfo ("No files to upload...")
                        }

                        <#
                            On to flat set.
                            The way these will work is to create a folder in the folder where the flat set lives, then create .url files to the referenced documents.
                        #>
                        if($fsToProcess.Length -gt 0)
                        {
                            # Before I can process flat sets, make sure all flat set referenced documents have accurate file URLs.
                            UpdateFileURLsForFlatSetReferences -viablePathsDict $viablePathsDict

                            if(-not $Script:HaveError)
                            {
                                ProcessFlatSets -viablePathsDict $viablePathsDict -fsToProcess $fsToProcess

                                if(-not $Script:HaveError)
                                {
                                    # Damn!!  I think I'm done...
                                }
                                else
                                {
                                    # Nothing, already logged an error.
                                }
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # Nothing, no flatsets ...
                        }
                    } `
                    else
                    {
                        # Nothing, would have already logged an error
                    }
                } `
                else
                {
                    # Nothing, everything is verified.
                    LogInfo ("Everything is verified")
                }
            } `
            else
            {
                # Nothing, already logged an error.
            }
        } `
        else
        {
            # Nothing, would have already logged an error
        }
    } `
    else
    {
        # Nothing, already logged an error
    }
}

function VerifiedComplete
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.SortedDictionary[[Guid],[Object]]] $viablePathsDict
    )

    BuildVerificationLookupDictionary -viablePathsDict $viablePathsDict -rebuild
    if(-not $Script:HaveError)
    {
        $vpKeys = @($viablePathsDict.Keys)
        $a = 0
        $documentCount = 0
        $verifiedDocumentCount = 0
        $flatSetCount = 0
        $verifiedFlatSetCount = 0
        while($a -lt $vpKeys.Length)
        {
            $vp = $viablePathsDict[$vpKeys[$a]]
            if($vp.SourceObject.MyType -eq "ProjectWiseDocument")
            {
                if($vp.SourceObject.IsSet)
                {
                    $flatSetCount++
                    if($vp.SPData.Verified)
                    {
                        $verifiedFlatSetCount++
                    } `
                    else
                    {
                        # Well Damn, guess we aren't done yet.
                    }
                } `
                else
                {
                    $documentCount++
                    if($vp.SPData.Verified)
                    {
                        $verifiedDocumentCount++
                    } `
                    else
                    {
                        # Well Damn, guess we aren't done yet.
                    }
                }
            } `
            else
            {
                # ProjectWiseFolder
            }
            $a++
        }

        # Assume the project is verified until we determine it is not.
        $projectVerified = $true
        if($documentCount -eq $verifiedDocumentCount)
        {
            LogInfo ("All documents ({0:N0}) verified ({1:N0})." -f @($documentCount, $verifiedDocumentCount))
        } `
        else
        {
            LogWarning ("All documents ({0:N0}) verified ({1:N0}), remaining unverified ({2:N0})." -f @($documentCount, $verifiedDocumentCount, ($documentCount - $verifiedDocumentCount)))
            $projectVerified = $false
        }

        if($flatSetCount -eq $verifiedFlatSetCount)
        {
            LogInfo ("All flatsets ({0:N0}) verified ({1:N0})." -f @($flatSetCount, $verifiedFlatSetCount))
        } `
        else
        {
            LogWarning ("All flatsets ({0:N0}), verified ({1:N0}), remaining unverified ({2:N0})." -f @($flatSetCount, $verifiedFlatSetCount, ($flatSetCount - $verifiedFlatSetCount)))
            $projectVerified = $false
        }

        $spFolders = @(@($viablePathsDict.Values).Where({ ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and (-not [String]::IsNullOrEmpty($_.SPData.FolderName)) }) | Select-Object @{N='Name';E={$_.SPData.FolderName}},@{N='GUID'; E={ $_.SourceObject.DocumentGUID }} | Sort-Object Name)
        $unverifiedDocumentsInFoldersCount = 0
        $unverifiedFoldersInFoldersCount = 0
        $a = 0
        while($a -lt $spFolders.Length)
        {
            $spFolder = $spFolders[$a]
            ShowProgress -progressID 1 -activity "Verifying folders" -counter $a -counterMax $spFolders.Length -statusSuffix $viablePathsDict[$spFolder.GUID].SPData.FolderName
            $vp = $viablePathsDict[$spFolder.GUID]

            if($vp.Paths.Length -ge 1)
            {
                $pathToCheck = $vp.Paths -join "/"
                if(-not [String]::IsNullOrEmpty($pathToCheck))
                {
                    if($Script:viablePathsLookupDict.ContainsKey($pathToCheck))
                    {
                        $unverifiedDocumentsInFoldersCount += $Script:viablePathsLookupDict[$pathToCheck].Where({ ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and (-not $_.SPData.Verified)}).Count
                        $unverifiedFoldersInFoldersCount += $Script:viablePathsLookupDict[$pathToCheck].Where({ ($_.SourceObject.MyType -eq "ProjectWiseFolder") -and (-not $_.SPData.Verified)}).Count
                    } `
                    else
                    {
                        # Nothing, looks like this path didn't have any documents that were unverified... :)
                    }
                } `
                else
                {
                    LogError("Empty paths for {0} in {1}." -f @((SourceObjectIdentity -srcObj $vp), $me.Name))
                    break
                }
            } `
            else
            {
                # Nothing, ignoring the pwProjectPath folder.
            }
<#
            $unverifiedSPFolderDocs = @(@($viablePathsDict.Values).Where({ ($_.SourceObject.MyType -eq "ProjectWiseDocument") -and ($_.SPData.FolderName -eq $spFolder.Name) -and (-not $_.SPData.Verified) }))
            $viablePathsDict[$spFolder.GUID].SPData.Verified = ($unverifiedSPFolderDocs.Length -eq 0)
            $unverifiedFoldersCount += ($unverifiedSPFolderDocs.Length -eq 0) ? 0 : 1
#>
            $a++
        }
        ShowProgress -progressID 1 -complete

        if($unverifiedFoldersInFoldersCount -eq 0)
        {
            LogInfo ("All folders ({0:N0}) verified ({1:N0})." -f @($spFolders.Length, ($spFolders.Length - $unverifiedDocumentsInFoldersCount)))
        } `
        else
        {
            LogWarning ("All folders ({0:N0}), verified ({1:N0}), remaining unverified ({2:N0})." -f @($spFolders.Length, ($spFolders.Length - $unverifiedDocumentsInFoldersCount), $unverifiedDocumentsInFoldersCount))
            $projectVerified = $false
        }

        if($projectVerified)
        {
            LogInfo ("{0} is verified complete." -f @($Script:projectName))
        } `
        else
        {
            LogWarning ("{0} is not verified." -f @($Script:projectName))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }

    return $projectVerified
}

function main
{
    $me = $MyInvocation.MyCommand
    $projectData = [PSCustomObject]@{
        Folders = 0
        Documents = 0
        FlatSets = 0
        Size = 0
        Discovered = $false
        Exported = $false
        Uploaded = $false
        FlatSetProcessed = $false
        Verified = $false
        HaveError = $false
    }
    $Script:initialized = $false
    Init
    if(-not $Script:HaveError)
    {
        # Only connect to ProjectWise if we are not restarting.
        #    NOTE:  This pre-supposes that the reporting phase completed successfully
        # This "short-circuit" expression will fall through if -restart is specified.
        if(($Script:restart.IsPresent) -or (ConnectToPW))
        {
            if(-not $Script:restart.IsPresent)
            {
                LogInfo ("Connected to ProjectWise")
            }

            if(-not $Script:HaveError)
            {
                if($Script:restart.IsPresent)
                {
                    $pwData = LoadLatestPWData

                    if($Script:HaveError)
                    {
                        LogInfo ("Failed to reload latest ProjectWise data from file.  Proceeding to getting it from ProjectWise.")
                        $Script:HaveError = $false
                        $Error.Clear()
                        $pwData = GetProjectWiseData
                        if(-not $Script:HaveError)
                        {
                            if($null -ne $pwData)
                            {
                                $projectData.Discovered = $true
                                $projectData.Folders = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseFolder" }).Count
                                $projectData.Documents = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }).Count
                                $projectData.FlatSets = @($pwData.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseDocument") -and ($_.IsSet) }).Count
                                $projectData.Size = (@($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }) | Measure-Object -Sum -Property FileSize).Sum
                                ExportPWDataToJSON -pwData $pwData
                            } `
                            else
                            {
                                LogError ("Failed to get ProjectWise data for project {0}\{1} in {2}." -f @($Script:pwProjectPath, $Script:projectName, $me.Name))
                            }
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }
                    } `
                    else
                    {
                        $projectData.Discovered = $true
                        $projectData.Folders = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseFolder" }).Count
                        $projectData.Documents = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }).Count
                        $projectData.FlatSets = @($pwData.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseDocument") -and ($_.IsSet) }).Count
                        $projectData.Size = (@($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }) | Measure-Object -Sum -Property FileSize).Sum
                    }
                } `
                else
                {
                    # Get relevant information from ProjectWise
                    $pwData = GetProjectWiseData
                    if(-not $Script:HaveError)
                    {
                        if($null -ne $pwData)
                        {
                            $projectData.Discovered = $true
                            $projectData.Folders = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseFolder" }).Count
                            $projectData.Documents = @($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }).Count
                            $projectData.FlatSets = @($pwData.ProjectWiseObjects.Values).Where({ ($_.MyType -eq "ProjectWiseDocument") -and ($_.IsSet) }).Count
                            $projectData.Size = (@($pwData.ProjectWiseObjects.Values).Where({ $_.MyType -eq "ProjectWiseDocument" }) | Measure-Object -Sum -Property FileSize).Sum

                            ExportPWDataToJSON -pwData $pwData
                        } `
                        else
                        {
                            LogError ("Failed to get ProjectWise data for project {0}\{1} in {2}." -f @($Script:pwProjectPath, $Script:projectName, $me.Name))
                        }
                    } `
                    else
                    {
                        # Nothing, already logged an error.
                    }
                }

                if(-not $Script:HaveError)
                {
                    $addedNewFolders,$pathDict = CreatePathDictionary -pwData $pwData
                    if(-not $Script:HaveError)
                    {
                        if($addedNewFolders)
                        {
                            ExportPWDataToJSON -pwData $pwData
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
                } `
                else
                {
                    # Nothing, already logged an error.
                }

                if(-not $Script:HaveError)
                {
                    if($null -ne $pathDict)
                    {
                        FixLongPaths -pathDict $pathDict

                        if(-not $Script:HaveError)
                        {
                            # $fromNode = $pathDict["ROOT"].Children
                            $viablePathsDict = BuildViablePathsDictionary -pwData $pwData -fromNode $pathDict["ROOT"].Children

                            if(-not $Script:HaveError)
                            {
                                if($Script:restart.IsPresent)
                                {
                                    # Add progress display to this...
                                    UpdateViablePathsFromLastRun -pwData $pwData -viablePathsDict $viablePathsDict
                                } `
                                else
                                {
                                    # Nothing, starting from scratch
                                }

                                if(-not $Script:HaveError)
                                {
                                    # No longer need to fix up viable paths, BuildViablePathsDictionary creates the dictionary as it needs to be....
                                    # FixUpViablePaths -pwData $pwData -viablePathsDict $viablePathsDict
                                    if(-not $Script:restart.IsPresent)
                                    {
                                        ExportViablePathsStructure -viablePathsDict $viablePathsDict
                                    } `
                                    else
                                    {
                                        # Heck, we just loaded it, no sense in saving it again.
                                    }
                                    BuildInitialReport -pwData $pwData
                                    #$reportJSON = $Script:reportData | ConvertTo-Json -Depth 10
                                    #LogInfo ($reportJSON)
                                    LogInfo ("{0}`t{1}`t{2}`t{3}`t{4}" -f @($Script:reportData.Folders.InProject, $Script:reportData.Documents.InProject, $Script:reportData.DocumentSets.InProject, $Script:reportData.DocumentLinks.InProject, (Format-StorageNumber $Script:reportData.Size.InProjectWise)))
                                    if($Script:DoExport.IsPresent)
                                    {
                                        if(-not $Script:HaveError)
                                        {
                                            $projectData.Verified = VerifiedComplete -viablePathsDict $viablePathsDict
                                            if(-not $projectData.Verified)
                                            {
                                                ExportPW2SP -pwData $pwData -viablePathsDict $viablePathsDict

                                                if(-not $Script:HaveError)
                                                {
                                                    $projectData.FlatSetProcessed = $true
                                                    $projectData.Exported = $true
                                                    $projectData.Uploaded = $true
                                                } `
                                                else
                                                {
                                                    # Nothing.
                                                }
                                                ExportViablePathsStructure -viablePathsDict $viablePathsDict
                                                $projectData.Verified = VerifiedComplete -viablePathsDict $viablePathsDict
                                            } `
                                            else
                                            {
                                                $projectData.FlatSetProcessed = $true
                                                $projectData.Exported = $true
                                                $projectData.Uploaded = $true
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, already displayed an error.
                                        }
                                    } `
                                    else
                                    {
                                        # TODO: Nothing, I suppose...   really makes DoExport non-functional.
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
                        LogError ("Failed to build path dictionary in {0}." -f @($me.Name))
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
            # $null = Undo-PWLogin
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

    $projectData.HaveError = $Script:HaveError
    return @(, $projectData)
}

function BasicSPOLConnection
{
    $Error.Clear()
    $Script:HaveError = $false
    ConnectToSPOL
}

Write-Host -ForegroundColor Yellow "Don't forget to set the following before calling Init."
Write-Host -ForegroundColor Yellow ("`t`$Script:{0}" -f @(($Script:requiredParams -join "`r`n`t`$Script:")))
Write-Host -ForegroundColor Yellow ("`r`n`Optional:`r`n`t`$Script:DoExport`r`n`t`$Script:restart`r`n`t`$Script:dbgOut")
