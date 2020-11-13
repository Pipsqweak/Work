<#
    -----------------------------------------------------------------------------
    Script: POWER-ENG.EasyVista.psm1
    Script File: C\POWER-ENG.EasyVista\POWER-ENG.EasyVista.psm1
    Author: tford-adm Tim Ford
    Company: POWER Engineers
    ISE Steroids Version: 3.117
    Release Version - 1.4.0.0
    Initial Release: 09/06/2019 11:34:06
    Keywords:

    Last Revised: Thursday, September 19, 2019 9:30:47 AM
    -----------------------------------------------------------------------------
    Revisions:

    9/19/2019
    - Removed Test Functions
    - Edited the Update-EVasset function to addd last-update date to updated EV record.
    - Updated section to remove variables/reset the environment.

    10/4/2019 - When connected to the prod account found a bug. Line 4020
#>

Function Connect-EasyVista {

    [CmdletBinding()]
    Param(
      [ValidateSet('Prod', 'Q04', 'Q05')]
      [Parameter(ParameterSetName='Paramset1',Mandatory=$true, HelpMessage='Connect to one of three environments. Prod, Q04, Q05')]
      [string]$EVEnvironment

      #[ValidateSet('Yes', 'No')]
      #[Parameter(ParameterSetName='Paramset2',Mandatory=$true, HelpMessage='Yes to clear Variables from current environments. Prod, Q04, or Q05')]
      #[switch]$EVClearEnvironment

    )

    Begin{

      $evSC = 'SilentlyContinue'
      $global:evWorkingPath = '\\boifs1\ITxchange\Automation'
      $global:evWorkingTitle = 'EV_CatalogItems'
      $global:evModuleVersion = '1.4.0.0'
      $global:evEasyVistaModule = 'POWER-ENG.EasyVista'
      Write-Verbose "Setting the $EVEnvironment"
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      #  Global Common environment variables.
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

      # Company
      $global:evSite ="POWER Engineers"
      # SMTP server address
      $global:evSmtpSrv ="smtp.powereng.com"
      # Email Sender
      $global:evEmailFrom ="bdc-mgmt01@powereng.com"
      # Email To
      $global:evEmailTo ="timothy.ford@powereng.com"
      # Email subject
      $global:evEmailSubject=('{0} - EasyVista Report' -f $global:evSite)

      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      # Dot source variables script again.
      #. C:\windows\System32\WindowsPowerShell\v1.0\Modules\POWER-ENG.EasyVista\POWER-ENG.EasyVista-Variables.ps1
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      $global:evDate = (get-Date -Format MM/dd/yyyy )
      $global:evDateStamp = (get-Date -Format MM-dd-yyyy )
      $global:evTempPath = $env:TEMP
      $global:evTitle = 'POWER-ENG.EasyVista Module'
      $global:evCatalogWorkingPath = ('{0}\{1}' -f $global:evWorkingPath, $global:evWorkingTitle)

      $global:evBase = 'EV_Request'
      $global:evJsonAssetFile = ('{0}\{1}.json' -f $evTempPath, $env:Computername)
      $global:evJsonFile = ('{0}-{1}.json' -f $evTempPath , $global:evDateStamp)
      $global:evCsvFile = ('{0}-{1}.csv' -f $evBase, $global:evDateStamp)
      $global:evHtml = ('{0}.html' -f ($evBase))
      $global:evJsonOutFile = ('{0}\{1}' -f $evTempPath, $evJsonFile)
      $global:evCsvOutFile = ('{0}\{1}' -f $evTempPath, $evCsvFile)
      $global:evHtmlOutFile = ('{0}\{1}' -f $evTempPath, $evHtml)
      $global:evFGColorInfo = 'Yellow'
      $global:evFGColorBad = 'Red'
      $global:evFGColorNum = 'Green'
      $global:evFGColorVerbose = 'Cyan'
      $global:evInputCSV = '\\boifs1\ITxchange\Automation\APC-UPS-Builds\Production Builds\APC-UPS-Deployed-Builds.csv'


    }

    Process{

      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      #  Authentication Keys. Get Basic authorization key from Postman
      #  (user = restapi).
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

      Switch ($EVEnvironment) {
        'Prod' {
          $global:evRestUser = 'infrastructureapi'
          $global:evBaseurl = "https://powereng.easyvista.com"
          $global:evAapiPath = "api/v1/50004"
          $global:evEnvironment = 'Prod'


        }

        'Q04' {
          $global:evRestUser = 'restapiq04'
          $global:evBaseurl = "https://powereng-qualif.easyvista.com"
          $global:evAapiPath = "api/v1/50004"
          $global:evEnvironment = 'Q04'

        }

        'Q05' {
          $global:evRestUser = 'restapiq05'
          $global:evBaseurl = "https://powereng-qualif.easyvista.com"
          $global:evAapiPath = "api/v1/50005"
          $global:evEnvironment = 'Q05'
        }


      } # Switch($EVEnvironment)

      $global:evKeyFile = "$global:evWorkingPath\$global:evEasyVistaModule\$global:evEnvironment\EV-$global:evEnvironment-AES.key"

      If (!(Test-Path -LiteralPath $global:evKeyFile -ErrorAction $evSC)) {

        Write-Warning "$global:evKeyFile not found. Please contact your POWER-ENG.EasyVista module administrator."
        break

      } Else {

        $global:evKey = Get-Content $global:evKeyFile

      }

      $global:evPasswordFile = "$global:evWorkingPath\$global:evEasyVistaModule\$global:evEnvironment\EV-$global:evEnvironment-APIkey.txt"
      If (!(Test-Path -LiteralPath $global:evPasswordFile -ErrorAction $evSC)) {
            Write-Warning "$global:evPasswordFile not found. Please contact your POWER-ENG.EasyVista module administrator."
            break
          } Elseif (Test-Path $global:evPasswordFile -PathType Leaf) {
        # Get the contents of the encrypted secure string file by using the provided key.
        Try {

          # Access the encrypted password file using the key.
          $evPassword = Get-Content $global:evPasswordFile | ConvertTo-SecureString -Key $global:evKey
          $evBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($evPassword)
          $evUnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($evBSTR)
          $global:evApi_key = ('Basic ' + $evUnsecurePassword)  ####
          # Free the BSTR when finishing the call.
          $evBSTR = $null

        } Catch {
          Write-Warning -Message 'The api key cannot be obtained.  Check that the keyfile and password keyfile exist.'
          break
        }# Try/Catch
      } # Elseif

      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      #  Header, Baseurl, Specific item URLs, Maximum Rows returned.
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

      $global:evHeader = @{
        'Authorization' = ('{0}' -f $global:evApi_key)
      }

      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      #  Global specific URLs based on the environment.
      #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

      $global:evEmployeeUrl = ('{0}/{1}/Employees' -f $global:evBaseurl, $global:evAapiPath)
      $global:evAssetsUrl = ('{0}/{1}/assets' -f $global:evBaseurl, $global:evAapiPath)
      $global:evRequestsUrl = ('{0}/{1}/Requests' -f $global:evBaseurl, $global:evAapiPath)
      $global:evCatalogAssetUrl = ('{0}/{1}/catalog-assets' -f $global:evBaseurl, $global:evAapiPath)
      $global:evConfigItemstUrl = ('{0}/{1}/configuration-items' -f $global:evBaseurl, $global:evAapiPath)
      $global:evLocationUrl = ('{0}/{1}/locations' -f $global:evBaseurl, $global:evAapiPath)
      $global:evStatusUrl = ('{0}/{1}/status' -f $global:evBaseurl, $global:evAapiPath)
      $global:evMaxRows = 100  # Max Rows Returned from EasyVist - Default is 100.


    } # Process


    End {



      Write-Host "Running from the $global:evEnvironment environment." -ForegroundColor Yellow
      return ('Url: {0}/{1}' -f $global:evBaseurl, $global:evAapiPath),('User: {0}' -f $global:evRestUser)

    } # End


  } # Function Connect-EasyVista

  Function Get-EVEmployeeData  {
    <#
        .SYNOPSIS
        Retrieves Employee information.

        .DESCRIPTION
        Get-EVEmployeeData retrieves specific information about an employee.

        .PARAMETER EmployeeId
        The EmployeeId as defined in EasyVista.

        .PARAMETER Option
        Choose from All-Options or a single item.

        .EXAMPLE
        Get-EVEmployeeData -EmployeeId <Value> -evOption All-Options
        By passing the employee ID you can retrieve all information about the employee or a single item such as Employee
        Name.

        .EXAMPLE
        Get-EVEmployeeData -EmployeeId (Get-EVEmployee -EmployeeName 'Ford, Timothy' -ReturnData EmployeeID) -evOption ALL-Options

        This example uses function Get-EVEmploee to get the EmployeeID to pass as a parameter to Get-EVEmployeeData .

        .EXAMPLE Get-EVEmployeeData -EmployeeID 24308 -evOption E_MAIL

        Returns:
        E_MAIL for 24308
        timothy.ford@powereng.com

        .NOTES
        This function used is used often with function Get-EVEmployee

        .LINK


        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        All-options, invidual employee items, such as email, phone, id, etc.
    #>



    Param(
      [Parameter(Mandatory=$true,Position=0,
      HelpMessage='Enter the Employee ID,')]
      [string]$evEmployeeId,

      [ValidateSet('ALL-Options','BEGIN_OF_CONTRACT','CELLULAR_NUMBER','DEPARTMENT_CODE','DEPARTMENT_EN','DEPARTMENT_ID','DEPARTMENT_LABEL','DEPARTMENT_PATH','EMPLOYEE_ID','E_MAIL','HREF','LAST_NAME','LOCATION_CITY','LOCATION_CODE','LOCATION_EN','LOCATION_ID','LOCATION_PATH','LOCATION_PATH','MANAGER.BEGIN_OF_CONTRACT','MANAGER.CELLULAR_NUMBER','MANAGER.LOCATION_PATH','MANAGER.PHONE_NUMBERPHONE_NUMBER','MANAGER_DEPARTMENT_PATH','MANAGER_EMPLOYEE_ID','MANAGER_E_MAIL','MANAGER_LAST_NAME','PHONE_NUMBER')]
      [Parameter(Mandatory=$True,HelpMessage='Please hit tab to see selection options')]
      [string]$evOption
    )

    $evResponseData = ''

    $evUrl = ('{0}/{1}' -f $global:evEmployeeurl, $evEmployeeId)

    # Make the GET request
    $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

    #Write-Host "Employee ID: $evEmployeeId" -ForegroundColor Yellow
    Switch ($evOption) {
      'BEGIN_OF_CONTRACT'               { $evResponseData=$evResponseData.BEGIN_OF_CONTRACT }
      'CELLULAR_NUMBER'                 { $evResponseData=$evResponseData.CELLULAR_NUMBER }
      'DEPARTMENT_CODE'                 { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_CODE }
      'DEPARTMENT_EN'                   { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_EN }
      'DEPARTMENT_ID'                   { $evResponseData=$evResponseData.DEPARTMENT_ID }
      'DEPARTMENT_LABEL'                { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_LABEL }
      'DEPARTMENT_PATH'                 { $evResponseData=$evResponseData.DEPARTMENT_PATH }
      'EMPLOYEE_ID'                     { $evResponseData=$evResponseData.EMPLOYEE_ID }
      'E_MAIL'                          { $evResponseData=$evResponseData.E_MAIL }
      'HREF'                            { $evResponseData=$evResponseData.HREF }
      'LAST_NAME'                       { $evResponseData=$evResponseData.LAST_NAME }
      'LOCATION_CITY'                   { $evResponseData=$evResponseData.LOCATION.CITY }
      'LOCATION_CODE'                   { $evResponseData=$evResponseData.LOCATION.LOCATION_CODE }
      'LOCATION_EN'                     { $evResponseData=$evResponseData.LOCATION.LOCATION_EN }
      'LOCATION_ID'                     { $evResponseData=$evResponseData.LOCATION_ID }
      'LOCATION_PATH'                   { $evResponseData=$evResponseData.LOCATION_PATH }
      'MANAGER.BEGIN_OF_CONTRACT'       { $evResponseData=$evResponseData.MANAGER.BEGIN_OF_CONTRACT }
      'MANAGER.CELLULAR_NUMBER'         { $evResponseData=$evResponseData.MANAGER.CELLULAR_NUMBER }
      'MANAGER.LOCATION_PATH'           { $evResponseData=$evResponseData.MANAGER.LOCATION_PATH }
      'MANAGER.PHONE_NUMBERPHONE_NUMBER' { $evResponseData=$evResponseData.MANAGER.PHONE_NUMBER }
      'MANAGER_DEPARTMENT_PATH'          { $evResponseData=$evResponseData.MANAGER.DEPARTMENT_PATH }
      'MANAGER_EMPLOYEE_ID'              { $evResponseData=$evResponseData.MANAGER.EMPLOYEE_ID }
      'MANAGER_E_MAIL'                   { $evResponseData=$evResponseData.MANAGER.E_MAIL }
      'MANAGER_LAST_NAME'                { $evResponseData=$evResponseData.MANAGER.LAST_NAME }
      'PHONE_NUMBER'                     { $evResponseData=$evResponseData.PHONE_NUMBER }
    }# Switch ($evOption)

      If (! $evResponseData ) {
        $evResponseData = 'NotDefined'
      }

      Write-Host ('{0} for {1}' -f $evOption, $evEmployeeId) -ForegroundColor $evFGColorInfo
      return $evResponseData


  }# Function Get-EVEmployeeItemData

  Function Get-EVEmployee {
    <#
        .SYNOPSIS
        Retrieves information about a single employee.

        .DESCRIPTION
        Get-EVEmployee

        .PARAMETER EmployeeName
        Employee's last name followed by the first name.

        .PARAMETER ReturnData
        -ReturnData is used to specify what data you want to retrieve.

        .PARAMETER ExportDatatoExcel
        -ExportDatatoExcel allows the data retrieved to exported to Excel.

        .PARAMETER Help
        -Help. Provides the basic syntax of the function.

        .EXAMPLE
        Get-EVEmployee -evEmployeeName <Value> -ReturnData <Value> -ExportDatatoExcel -Help

        .EXAMPLE
        Example: Get-EVEmployee -evEmployeeName 'Williams, jo' -ReturnData ALL | ft -AutoSize

        This example searches for all employees containing the 'Williams jo' and will provide the data in a table format.

        .NOTES
        You can use wild cards the name but try to be as unique as possible.

        Example: Get-EVEmployee -evEmployeeName 'Ford, Tim*' -ReturnData EmployeeDeptID

        .LINK
        None

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        All employee data or a subset of one item per function call.
    #>


    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
      HelpMessage='Enter the Employee Last Name, First Name.  Example: "Ford, Timothy"')]
      [string]$evEmployeeName,
      [Parameter(Mandatory=$true,HelpMessage='Select the parameter to return. EmployeeID | EmployeeLocationID | EmployeeDeptID')]
      [ValidateSet('ALL','EmployeeID','EmployeeLocationID','EmployeeDeptID')]
      [string]$evReturnData,
      [switch]$evExportDatatoExcel,
      [switch]$evHelp

    )

    $Error.clear()

    $evUrl = (('{0}?max_rows={1}&search=last_name~"{2}"' -f $global:evEmployeeurl, $evMaxRows, $evEmployeeName))

    $evHelpmsg =  @"
      Try narrowing your search to one of these.  Be sure to use quotes around the name.  You may use an * to wildcard your search, but then adjust if
      you are seeing more than one record.

      For example:

      Get-EVEmployee -evEmployeeName '*Ford, Timothy' -ReturnData evEmployeeDeptID
        returns results of two individuals:

          Dunford, Timothy
          Ford, Timothy

      But running without *, 'Ford, Timothy' returns a single employee results.

        BEGIN_OF_CONTRACT :
        CELLULAR_NUMBER   : 208-8691681
        DEPARTMENT_PATH   : Ops IT Infrastructure Dept
        DEPARTMENT_ID     : 1669
        E_MAIL            : timothy.ford@powereng.com
        EMPLOYEE_ID       : 24308
        HREF              : /api/v1/50004/employees/24308
        LAST_NAME         : Ford, Timothy
        LOCATION_PATH     : Boise
        LOCATION_ID       : 1086
        PHONE_NUMBER      : 1-208-288-6268
        LOCATION          : @{CITY=Meridian; LOCATION_CODE=142; LOCATION_EN=Boise; LOCATION_PATH=Boise; LOCATION_ID=1086}
        DEPARTMENT        : @{DEPARTMENT_CODE=1540; DEPARTMENT_EN=Ops IT Infrastructure Dept; DEPARTMENT_PATH=Ops IT Infrastructure Dept; DEPARTMENT_ID=1669;
                            DEPARTMENT_LABEL=0003}
        MANAGER           : @{BEGIN_OF_CONTRACT=; CELLULAR_NUMBER=1-425-223-8346; DEPARTMENT_PATH=Ops IT Infrastructure Dept; E_MAIL=jeff.folz@powereng.com;
                            EMPLOYEE_ID=20779; LAST_NAME=Folz, Jeff; LOCATION_PATH=Boise; PHONE_NUMBER=1-208-288-6151}
"@
    # Capture employee info.
    Try {
      $evEmployeeLists = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue

      IF ($evEmployeeLists -and $evEmployeeLists.record_count -gt 1) {

        Write-host $evHelpmsg -ForegroundColor $evFGColorInfo
        Write-Host ('Results of {0}.' -f $evEmployeeName) -ForegroundColor $evFGColorInfo
        $evOutput = $evEmployeeLists.records | Select-Object Last_Name, Department_ID, Location_Path, employee_id, phone_number

      } Elseif ($evEmployeeLists -and $evEmployeeLists.record_count -eq 1) {

        $evEmployee = ($evEmployeeLists.records | Select-Object Last_Name).Last_Name
        $evEmployeeId = ($evEmployeeLists.records | Select-Object Employee_ID).Employee_ID
        #$evEmployeeLocationID = ($evEmployeeLists.records | Select-Object Location_ID).Location_ID
        #$evEmployeeDeptID = ($evEmployeeLists.records | Select-Object Department_ID).Department_ID

        Switch ($evReturnData) {
          'ALL'{
            $evOutput = ($evEmployeeLists.records)
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee Data: $evOutput" -ForegroundColor $evFGColorInfo
          }

          'Employee' {
            $evOutput = ($evEmployeeLists.records | Select-Object Last_Name).Last_Name
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee ID: $evOutput" -ForegroundColor $evFGColorNum
          }

          'EmployeeID'{
            $evOutput = ($evEmployeeLists.records | Select-Object Employee_ID).Employee_ID
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee ID: $evOutput" -ForegroundColor $evFGColorNum
          }

          'EmployeeLocationID'{
            $evOutput = ($evEmployeeLists.records | Select-Object Location_ID).Location_ID
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee Location ID: $evOutput" -ForegroundColor $evFGColorNum
          }

          'EmployeeDeptID' {
            $evOutput = ($evEmployeeLists.records | Select-Object Department_ID).Department_ID
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee Department ID: $evOutput" -ForegroundColor $evFGColorNum

          }
          Default {
            $evOutput = ($evEmployeeLists.records)
            Write-Host "Employee: $evEmployee" -ForegroundColor $evFGColorInfo
            Write-Host "Employee Data: $evOutput" -ForegroundColor $evFGColorInfo
          }

        } #Switch


      } Else {
        Write-Warning  'The query did not return any data.'
      }


    } Catch {
      Write-Warning  'There was a problem with the query. Please narrow your search.'
      Write-Warning "Error is $($.Exception.Message)"
    }

    If ($evEmployeeLists.record_count -gt 0 -and $evExportDatatoExcel) {
      $evEmployFolder = 'Employee_Numbers'

      $evBasePath = '\\boifs1\ITxchange\Automation\EV_CatalogItems'
      $evXlsxfile = ('{0}\{1}\{2}-Catalog-{2}.xlsx' -f $evBasePath, $evEmployFolder, $global:evDateStamp)

      If ( ! (test-path ('{0}\{1}' -f $evBasePath, $evEmployFolder) -PathType Container)) {

        New-Item  -ItemType 'directory' -Path ('{0}\{1}' -f $evBasePath, $evEmployFolder)
      }

      $evEmployeeLists.records | Export-Excel -Path $evXlsxfile -WorkSheetname ('{0} Catalog' -f $evEmployFolder) -AutoSize
    }# If $ExportDatatoExccel


    #Write-Host $evHelpmsg -ForegroundColor $evFGColorInfo
    return $evOutput



  }# Function Get-Employee by Last Name, First name - Gold

  Function Get-EVLocation {
    <#
        .SYNOPSIS
        Get-EVLocation" returns the location id.

        .DESCRIPTION
        Get-EVLocation" returns the location id for a specific Power Engineers location as defined by EasyVista.

        .PARAMETER Location
        Enter the location by name

        .PARAMETER ReturnData
        Returns all data about the location or a subset of a single item.

        .PARAMETER ExportDatatoExcel
        -ExportDatatoExcel function provides the output into an excel file.

        .PARAMETER Help
        For instructions on how to use the function.

        .EXAMPLE
        Get-EVLocation -evLocation Value -ReturnData Value -ExportDatatoExcel -Help
        Describe what this call does

        Get-EVLocation -evLocation 'Airdrie*' -ReturnData ALL

        Get-EVLocation -evLocation 'Airdrie' -ReturnData LocationID

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVLocation

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>


    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
      HelpMessage='Enter the location name.  Example: "Airdrie (Air)')]
      [string]$evLocation,
      [Parameter(Mandatory=$true,HelpMessage='Select the parameter to return. All, Location id, Location, city, HREF')]
      [ValidateSet('ALL','CITY','Site','LocationID','HREF')]
      [string]$evReturnData,
      [switch]$evExportDatatoExcel,
      [switch]$evHelp

    )

    $Error.clear()

    $evUrl = (('{0}?max_rows={1}&search=location_en~"{2}"' -f $evLocationUrl , $evMaxRows, $evLocation))

    $evHelpmsg =  @"
      Try narrowing your search to one of these.  Be sure to use quotes around the name.

      You may use an * to wildcard your search, but then adjust if you are seeing
      more than one record.

      For example:

      Get-EVLocation -Location 'Airdrie*' -ReturnData ALL

        Returns recors for both Airdrie, and Airdrie (Air).

      Get-EVLocation -Location 'Airdrie' -ReturnData ALL

        Returns a single record for Airdrie.

"@
    # Capture employee info.
    Try {
      $evLocationLists = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue

      IF ($evLocationLists -and $evLocationLists.record_count -gt 1) {

        Write-host $evHelpmsg -ForegroundColor $evFGColorInfo
        #Write-Host "Results of $evLocationLists." -ForegroundColor $FGColor
        $evOutput = $evLocationLists.records | Select-Object City, Location_en, Location_Path, Location_ID, HREF

      } Elseif ($evLocationLists -and $evLocationLists.record_count -eq 1) {

        $evLocation = ($evLocationLists.records | Select-Object LOCATION_EN).LOCATION_EN
        $evLocationID = ($evLocationLists.records | Select-Object LOCATION_ID).LOCATION_ID


        Switch ($evReturnData) {
          'ALL'{
            $evOutput = ($evLocationLists.records)
            Write-Host "Location Data: $evOutput" -ForegroundColor $evFGColorInfo
          }

          'CITY' {
            $evOutput = ($evLocationLists.records | Select-Object CITY).CITY
            Write-Host "Location City: $evOutput" -ForegroundColor $evFGColorInfo
          }

          'Location'{
            $evOutput = ($evLocationLists.records | Select-Object LOCATION_EN).LOCATION_EN
            Write-Host "Location Name: $evOutput" -ForegroundColor $evFGColorInfo
          }

          'LoationPath'{
            $evOutput = ($evLocationLists.records | Select-Object Location_Path).Location_Path
            Write-Host "Location Path: $evOutput" -ForegroundColor $evFGColorInfo
          }

          'LocationID' {
            $evOutput = ($evLocationLists.records | Select-Object LOCATION_ID).LOCATION_ID
            Write-Host "Location ID: $evOutput" -ForegroundColor $evFGColorInfo

          }
          'HREF' {
            $evOutput = ($evLocationLists.records | Select-Object HREF).HREF
            Write-Host "HREF: $evOutput" -ForegroundColor $evFGColorInfo

          }

          Default {
            $evOutput = ($evLocationLists.records | Select-Object LOCATION_ID).LOCATION_ID
            Write-Host "Location ID: $evOutput" -ForegroundColor $evFGColorInfo
          }

        } #Switch


      } Else {
        Write-Warning  'The query did not return any data.'
      }


    } Catch {
      Write-Warning  'There was a problem with the query. Please narrow your search.'
      Write-Warning "Error is $($.Exception.Message)"
    }

    If ($evLocationLists.record_count -gt 0 -and $evExportDatatoExcel) {
      $evLocationFolder = 'EV_Locations'

      $evXlsxfile = ('{0}-{1}-{2}-Locations.xlsx' -f $evWorkingPath, $evLocationFolder, $global:evDateStamp)

      If ( ! (test-path ('{0}\{1}' -f $evWorkingPath, $evLocationFolder) -PathType Container)) {

        New-Item  -ItemType 'directory' -Path ('{0}\{1}' -f $evWorkingPath, $evLocationFolder)
      }

      $evLocationLists.records | Export-Excel -Path $evXlsxfile -WorkSheetname ('{0} Locations' -f $evLocationFolder) -AutoSize
    }# If $ExportDatatoExccel


    #Write-Host $evHelpmsg -ForegroundColor $FGColor
    return $evOutput



  }# Get-EVLocation

  Function Get-EVModel {
    <#
        .SYNOPSIS
        D"Get-EVModel" function

        .DESCRIPTION
        Retrieves model information

        .PARAMETER Model
        Enter a model

        .PARAMETER Maxrows
        Maximum rows to return.

        .PARAMETER SaveReport
        A save report option.

        .PARAMETER Help
        Display help information.

        .EXAMPLE
        Get-EVModel -Model Value -Maxrows Value -SaveReport -Help

        .EXAMPLE


        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVModel

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>



    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
      HelpMessage='Enter the Model information')]
      [string]$evModel,
      [Parameter(Mandatory=$False)]
      [string]$evMaxRows = 500,
      [switch]$evSaveReport,
      [switch]$evHelp

    )

    $Error.clear()

    $evHlpMsg = @'
        Usage:

          Example:  Get-EVModel <Model Name>
'@

    # Create URL
    $evUrl = (('{0}' -f $evCatalogAssetUrl) +'?search=Article_Model~'+ ('"*{0}*"' -f ($evModel)) + ('&fields=Catalog_id,Article_model&max_rows={0}' -f $evMaxRows))

    # Capture APC model info.
    $evModels = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue

    If (!($evModel) ) {
      Write-Host "Manufacturer: $evModel" -ForegroundColor $evFGColorVerbose
      Write-Host "Record Count: $($evModels.records.Count)" -ForegroundColor  $evFGColorNum
      Write-Host "Choose from these models: Example: get-catalogid -Manufacturer $evModel -Model $(($evModels.records[-1]).ARTICLE_MODEL)" -ForegroundColor $evFGColorVerbose
      (($evModels.records | Select-Object ARTICLE_MODEL).Article_Model)

    } Else {

      $evCatalogID =  ($evModels.records | Select-Object ARTICLE_MODEL, CATALOG_ID | Where-Object {$_.Article_Model -like "*$($evModel)*"}).Catalog_ID

      If ($evCatalogID -and $evCatalogID.count -eq 1) {
        Write-Host "Model: $evModel Catalog ID is: $evCatalogID" -ForegroundColor $

      } Elseif ($evCatalogID -and $evCatalogID.count -gt 1) {
        Write-Host 'It appears that you need to narrow your search to one of these models.' -ForegroundColor $evFGColorVerbose
        $evCatalogID =  (($evModels.records) | Select-Object Article_Model).Article_Model

        Foreach ($item in $evCatalogID) {
          Write-Host $Item -ForegroundColor $evFGColorInfo
        }

        If ([int]$($evModels).total_record_count -gt [int]$evMaxRows) {
          Write-Warning "There are more records to display.  You're only displaying $evMaxRows records.  Try increasing the -maxrows parater from $evMaxRows to $($evModels.total_record_count)."
          break

        }
        $evCatalogID = '---'

      } Else {

        $evCatalogID = '---'
        Write-Host 'Model not found.' -ForegroundColor $evFGColorBad
      }

    }# !($evModel)

    If ($evHelp) {
      Write-Host $evHlpMsg -ForegroundColor $evFGColorInfo
    }

    If ($evSaveReport){
      $evBasePath = '\\boifs1\ITxchange\Automation\EV_CatalogItems'
      $evXlsxfile = "$evBasePath\$evModel\$evModel-Catalog-$global:evDateStamp.xlsx"
      $evModels.records | Export-Excel -Path $evXlsxfile -WorkSheetname "$evModel Models" -AutoSize

      If ( ! (test-path "$evBasePath\$evModel" -PathType Container)) {
        $null = New-Item  -ItemType 'directory' -Path "$evBasePath\$evModel"
      }
    }# If $evSaveReport

    return $evCatalogID

    <#
        Results of query.
        It appears that you need to narrow your search to one of these models.
        ThinkCentre M55
        ThinkCentre M57p
        ThinkCentre M57e
        ThinkCentre M51
        ThinkCentre M52
        ThinkCentre M52 (Server)
        BCM50
        ThinkCentre M55p
        ACM5504-2-P
        xSeries 3650 M5
        CPAP-SM5003-EVNT
        NeXtScale System nx360 M5
        M506DN
        UCSB-B200-M5
        UCS-C240-M5SX
        ---

        Get-EVModel -Model "xSeries 3650 M5"

        Return of query.
        Model: xSeries 3650 M5 Catalog ID is: 133877
        133877
    #>
  }

  Function Get-EVStatus {
    <#
        .SYNOPSIS
        "Get-EVStatus" function to returns the status id or status name.

        .DESCRIPTION
        This function retrieves the status id or status name.

        .PARAMETER EVStatusName
        Examples are Closed, Archived, Releasing, etc.

        .PARAMETER EVStatusID
        A numerical refernce to the the name of the status.

        .PARAMETER All
        Retrives all status's and Id's.

        .PARAMETER ExportDatatoExcel
        Dump the data to Excel

        .PARAMETER Help
        Describe parameter -Help.

        .EXAMPLE
        Get-EVStatus -EVStatusName Approved

        Status Id: 30 (Yellow) - data returned to the screen.
        30 (White) - data returned to the calling function.

        .EXAMPLE
        Get-EVStatus -EVStatusID 8

        Status Name: Closed  (Yellow) - data returned to the screen.
        Closed (White) - data returned to the calling function.

        .EXAMPLE
        Get-EVStatus -All -ExportDatatoExcel

        .EXAMPLE
        Get-EVStatus -ExportDatatoExcel -Help
        Describe what this call does

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVStatus

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>


    [CmdletBinding()]
    Param(
      [Parameter(ParameterSetName='p1',Mandatory=$true,HelpMessage='Enter the Status name.')]
      [ValidateSet('Accepted','Approved','Archived','Assigning Stock','Attached to a Release','Cancelled','Cancelled',
          'Cancelled: Input Error','Cancelled: for Reschedule','Closed','Closed: Duplicate','Computer Build In Process',
          'Developing','Escalated','Evaluating License Requirements','Fulfilled','IT Scheduling Setup/Install','In progress',
          'Installation Complete','New','On Hold','On hold for completion','Ordered','Pending Approval','Pending CM Review',
          'Pending COA Approval','Pending Documentation','Pending Manager Approval','Pending Planification','Pending Purchase',
          'Pending RMA Request','Pending Reschedule','Pending Service Desk Analysis','Pending Service Desk Contact',
          'Pending Stock Recieving','Pending Validation','Pending installation','Purchase Complete','Purchase In Process',
          'Received','Redirected','Rejected','Rejected Operation','Rejected Transition','Related Incident','Released','Releasing',
          'Reopened','Scheduled','Service Desk Re-Evaluation','Shipped','Solved','Testing/Validating','Transferred','Validation RFI')]
      [string]$evStatusName,

      [Parameter(ParameterSetName='p2',Mandatory=$true,HelpMessage='Enter the status id to return the status name.')]
      [ValidateSet('1','2','3','4','5','6','7','8','9','10',
          '11','12','13','14','15','16','17','18','19','20',
          '21','22','23','24','25','26','27','28','29','30',
          '31','32','33','34','35','36','37','38','39','40',
          '41','42','43','44','45','46','47','48','49','50',
          '51','52','53','54','55')]
      [string]$evStatusID,

      [Parameter(ParameterSetName='p3',Mandatory=$true,HelpMessage='Enter the status id to return the status name.')]
      [Switch]$All,

      [switch]$evExportDatatoExcel,
      [switch]$evHelp

    )

    $Error.clear()


    $evUrl = (('{0}?' -f $evStatusUrl))


    # Capture Status info.

    Try {
      $evStatusLists = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue

      switch ($PsCmdlet.ParameterSetName)
      {
        'p1'  {
                #Write-Host $evStatusName -ForegroundColor Cyan
                $evOutput = ($evStatusLists.records | Select-Object Status_en, Status_id | Where-Object {$_.Status_en -like $evStatusName}).Status_id
                Write-Host "Status Id: $evOutput" -ForegroundColor $evFGColorNum
                break
              }

        'p2'  {
                #Write-Host $evStatusID  -ForegroundColor Cyan
                $evOutput = ($evStatusLists.records | Select-Object Status_en, Status_id | Where-Object {$_.Status_id -like $evStatusID}).Status_en
                Write-Host "Status Name: $evOutput" -ForegroundColor $evFGColorInfo
                break
              }

        'p3'  {
                #Write-Host $All -ForegroundColor Cyan
                $evOutput = ($evStatusLists.records | Select-Object Status_id, Status_en,href)
                Write-Host 'All Status IDs.' -ForegroundColor $evFGColorInfo
                break
              }
      }# Switch on ParameterSet


    } Catch {
      Write-Warning  'There was a problem with executing the query.'
    } # End of Try/Catch

    If ($evStatusLists.record_count -gt 0 -and $evExportDatatoExcel) {
      $evStatusFolder = 'Status_Numbers'

      $evBasePath = '\\boifs1\ITxchange\Automation\EV_CatalogItems'
      $evXlsxfile = ('{0}\{1}\{2}-Catalog-{2}.xlsx' -f $evBasePath, $evStatusFolder, $global:evDateStamp)

      If ( ! (test-path ('{0}\{1}' -f $evBasePath, $evStatusFolder) -PathType Container)) {

        New-Item  -ItemType 'directory' -Path ('{0}\{1}' -f $evBasePath, $evStatusFolder)

        $evStatusFolder.records | Export-Excel -Path $evXlsxfile -WorkSheetname ('{0} Catalog' -f $evStatusFolder) -AutoSize
      }
    }# If $ExportDatatoExccel


    return $evOutput

  }# Function Get-EVStatus

  Function Get-EVRequestDataOption  {
    <#
        .SYNOPSIS
        "Get-EVRequestDataOption" Function

        .DESCRIPTION
        A function that returns data from a change request.

        .PARAMETER RequestId
        -RequestId is a numerical reference to the request.

        .PARAMETER Option
        Use -evOption to return all data or a subset of data.

        .EXAMPLE
        Get-EVRequestDataOption -evRequestId <Value> -evOption <Value>

        .EXAMPLE
        Get-EVRequestDataOption -evRequestId CHG000115 -evOption All-Options

        .EXAMPLE
        Get-EVRequestDataOption -evRequestId CHG000115 -evOption All-Options

        .EXAMPLE
        Get-EVRequestDataOption -evRequestId CHG000115 -evOption 'Change Release Manager'

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Change Request ID number.

        .OUTPUTS
        Detail on the change request.
    #>



    Param(
      [Parameter(Mandatory=$true,Position=0,
      HelpMessage='Enter Request ID,')]
      [string]$evRequestId,

      [Parameter(Mandatory=$true)][ValidateSet('All-Options',
          'Analytical Charge Id','Analytical Charge Path','Asset Id','Available Field 4',
          'Back Out Plan','Budget Effective','Budget Id','Budget Planned','Cab Flag',
          'Can BDuplicated','Catalog Request Catalog Request Path','Catalog Request Code',
          'Catalog Request Sd Catalog Id','Catalog Request Title','Catalog Request',
          'Change Additional Information Href','Change Additional Resources','Change Cvs Project',
          'Change Information Link','Change Release Manager','Ci Id','Click 2 Get Install Result',
          'Comment Href ','Communication Plan Href','Continuity Plan Id','Cost Center Id',
          'Creation Date','Delay','Department Code','Department Name','Department Id','Department Label',
          'Department Path','Department Path','Description Href','Dynamic Details Href',
          'Effective Change Date End','Effective Change Date Start','End Date','Estimated Net Price',
          'Estimated Percent Complete','Expected Date','Expected Duration','Expected End Date',
          'Expected Start Date','External Reference','First Call Resolution','Hour Per Day','Href',
          'Impact Id','Imputation Date','Initial Sd Catalog Id','Initial Sd Catalog Path',
          'Is Emergency Change','Is Financial Completed','Is Major Incident','Is Standard Change',
          'Is Template','Kbase Id','Known Problem Known Problem Path','Known Problem Known Problems Id',
          'Known Problem Kp Number','Known Problem Question','Known Problems Id','Known Problems Path',
          'Last DoneBy Id','Last Group Id','Last Update','Location City','Location Id',
          'Location Location Code','Location','Location Location Id','Location Location Path',
          'Location Path','Mark 1','Mark 2','Max Resolution Date','Ms Project Import Validation Waiting',
          'Net Price Cur Id','Net Price','News Id','Not Deduced Call','Order Id','Order Net Price',
          'Origin Tool Id','Owner Id','Owning Group Id','Parent Request Id','Planned Change Date End',
          'Planned Change Date Start','Pm Status Id','Potential Impact','Project Id','Project Name',
          'Project Start Date','Qty','Recipient Begin Of Contract','Recipient Cellular Number',
          'Recipient Department Path','Recipient EmployeId','Recipient Id','Recipient Last Name',
          'Recipient Location Path','Recipient Mail','Recipient PhonNumber','Release Id',
          'Rental Net PricCur Id','Rental Net Price','Requalification Processing','Request Id',
          'Request Origin Id','Request Project Id','Requested ChangDatEnd','Requested ChangDatStart',
          'Requestor Begin Of Contract','Requestor Cellular Number','Requestor Department Path',
          'Requestor Employee Id','Requestor Feedback','Requestor Id','Requestor Ip Address',
          'Requestor Last Name','Requestor Location Path','Requestor Mail','Requestor Phone Number',
          'Requestor Phone','Required Downtime','Rfc Number','Risk Amount','Risk Description Href',
          'Risk Level Id','Root CausId','Sd Catalog Id','Sd Catalog Path','Severity Id','Sla Id',
          'Status Id','Status','Status Guid','Status Id','Status','Submit Date','Submitted By',
          'Successful Change','Survey Result','System Id','Testing Details Href','Time Used To Deliver Feedback',
          'Time Used To Solve Request','Trigger','Urgency Id','Validation Level Required','Variable 1',
      'Variable 2','Variable 3','Variable 4','Variable 5','Wave Id Target')]
      [string]$evOption
    )

    $evResponseData = ''

    $evUrl = ('{0}/{1}' -f $evRequestsUrl, $evRequestId)

    # Make the GET request
    $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

    #Write-Host "Employee ID: $evEmployeeId" -ForegroundColor $evFGColorNum
    Switch ($evOption) {
      'Analytical Charge Id'                      { $evResponseData=$evResponseData.ANALYTICAL_CHARGE_ID }
      'Analytical Charge Path'										{ $evResponseData=$evResponseData.ANALYTICAL_CHARGE_PATH }
      'Asset Id'                                  { $evResponseData=$evResponseData.ASSET_ID }
      'Available Field 4'                         { $evResponseData=$evResponseData.AVAILABLE_FIELD_4 }
      'Back Out Plan'                             { $evResponseData=$evResponseData.E_BACK_OUT_PLAN }
      'Budget Effective'                          { $evResponseData=$evResponseData.BUDGET_EFFECTIVE }
      'Budget Id'                                 { $evResponseData=$evResponseData.BUDGET_ID }
      'Budget Planned'                            { $evResponseData=$evResponseData.BUDGET_PLANNED }
      'Cab Flag'                                  { $evResponseData=$evResponseData.E_CAB_FLAG }
      'Can BDuplicated'                           { $evResponseData=$evResponseData.CAN_BE_DUPLICATED }
      'Catalog Request Catalog Request Path'      { $evResponseData=$evResponseData.CATALOG_REQUEST.CATALOG_REQUEST_PATH }
      'Catalog Request Code'                      { $evResponseData=$evResponseData.CATALOG_REQUEST.CODE }
      'Catalog Request Sd Catalog Id'             { $evResponseData=$evResponseData.CATALOG_REQUEST.SD_CATALOG_ID }
      'Catalog Request Title'                     { $evResponseData=$evResponseData.CATALOG_REQUEST.TITLE_EN }
      'Catalog Request'                           { $evResponseData=$evResponseData.CATALOG_REQUEST }
      'Change Additional Information Href'        { $evResponseData=$evResponseData.E_CHANGE_ADDITIONAL_INFORMATION.HREF }
      'Change Additional Resources'               { $evResponseData=$evResponseData.E_CHANGE_ADDITIONAL_RESOURCES }
      'Change Cvs Project'                        { $evResponseData=$evResponseData.E_CHANGE_CVS_PROJECT }
      'Change Information Link'                   { $evResponseData=$evResponseData.E_CHANGE_INFORMATION_LINK }
      'Change Release Manager'                    { $evResponseData=$evResponseData.E_CHANGE_RELEASE_MANAGER }
      'Ci Id'                                     { $evResponseData=$evResponseData.CI_ID }
      'Click 2 Get Install Result'                { $evResponseData=$evResponseData.CLICK_2_GET_INSTALL_RESULT }
      'Comment Href '                             { $evResponseData=$evResponseData.COMMENT.HREF }
      'Communication Plan Href'                   { $evResponseData=$evResponseData.E_COMMUNICATION_PLAN.HREF }
      'Continuity Plan Id'                        { $evResponseData=$evResponseData.CONTINUITY_PLAN_ID }
      'Cost Center Id'                            { $evResponseData=$evResponseData.COST_CENTER_ID }
      'Creation Date'                             { $evResponseData=$evResponseData.CREATION_DATE_UT }
      'Delay'                                     { $evResponseData=$evResponseData.DELAY }
      'Department Code'                           { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_CODE }
      'Department Name'                           { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_EN }
      'Department Id'                             { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_ID }
      'Department Label '                         { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_LABEL }
      'Department Path'                           { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_PATH }
      'Department Path'                           { $evResponseData=$evResponseData.DEPARTMENT_PATH }
      'Description Href'                          { $evResponseData=$evResponseData.DESCRIPTION.HREF }
      'Dynamic Details Href'                      { $evResponseData=$evResponseData.DYNAMIC_DETAILS.HREF }
      'Effective Change Date End'                 { $evResponseData=$evResponseData.EFFECTIVE_CHANGE_DATE_END }
      'Effective Change Date Start'               { $evResponseData=$evResponseData.EFFECTIVE_CHANGE_DATE_START }
      'End Date'                                  { $evResponseData=$evResponseData.END_DATE_UT }
      'Estimated Net Price'                       { $evResponseData=$evResponseData.ESTIMATED_NET_PRICE }
      'Estimated Percent Complete'                { $evResponseData=$evResponseData.ESTIMATED_PERCENT_COMPLETE }
      'Expected Date'                             { $evResponseData=$evResponseData.EXPECTED_DATE_UT }
      'Expected Duration'                         { $evResponseData=$evResponseData.EXPECTED_DURATION }
      'Expected End Date'                         { $evResponseData=$evResponseData.EXPECTED_END_DATE_UT }
      'Expected Start Date'                       { $evResponseData=$evResponseData.EXPECTED_START_DATE_UT }
      'External Reference'                        { $evResponseData=$evResponseData.EXTERNAL_REFERENCE }
      'First Call Resolution'                     { $evResponseData=$evResponseData.FIRST_CALL_RESOLUTION }
      'Hour Per Day'                              { $evResponseData=$evResponseData.HOUR_PER_DAY }
      'Href'                                      { $evResponseData=$evResponseData.HREF }
      'Impact Id'                                 { $evResponseData=$evResponseData.IMPACT_ID }
      'Imputation Date'                           { $evResponseData=$evResponseData.IMPUTATION_DATE }
      'Initial Sd Catalog Id'                     { $evResponseData=$evResponseData.INITIAL_SD_CATALOG_ID }
      'Initial Sd Catalog Path'                   { $evResponseData=$evResponseData.INITIAL_SD_CATALOG_PATH }
      'Is Emergency Change'                       { $evResponseData=$evResponseData.E_IS_EMERGENCY_CHANGE }
      'Is Financial Completed'                      { $evResponseData=$evResponseData.IS_FINANCIAL_COMPTED }
      'Is Major Incident'                         { $evResponseData=$evResponseData.IS_MAJOR_INCIDENT }
      'Is Standard Change'                        { $evResponseData=$evResponseData.E_IS_STANDARD_CHANGE }
      'Is Template'                               { $evResponseData=$evResponseData.IS_TEMPLATE }
      'Kbase Id'                                  { $evResponseData=$evResponseData.KBASE_ID }
      'Known Problem Known Problem Path'          { $evResponseData=$evResponseData.KNOWN_PROBLEM.KNOWN_PROBLEM_PATH }
      'Known Problem Known Problems Id'           { $evResponseData=$evResponseData.KNOWN_PROBLEM.KNOWN_PROBLEMS_ID }
      'Known Problem Kp Number'                   { $evResponseData=$evResponseData.KNOWN_PROBLEM.KP_NUMBER }
      'Known Problem Question'                    { $evResponseData=$evResponseData.KNOWN_PROBLEM.QUESTION_EN }
      'Known Problems Id'                         { $evResponseData=$evResponseData.KNOWN_PROBLEMS_ID }
      'Known Problems Path'                       { $evResponseData=$evResponseData.KNOWN_PROBLEMS_PATH }
      'Last DoneBy Id'                            { $evResponseData=$evResponseData.LAST_DONE_BY_ID }
      'Last Group Id'                             { $evResponseData=$evResponseData.LAST_GROUP_ID }
      'Last Update'                               { $evResponseData=$evResponseData.LAST_UPDATE }
      'Location City'                             { $evResponseData=$evResponseData.LOCATION.CITY }
      'Location Id'                               { $evResponseData=$evResponseData.LOCATION_ID }
      'Location Location Code'                    { $evResponseData=$evResponseData.LOCATION.LOCATION_CODE }
      'Location'                                  { $evResponseData=$evResponseData.LOCATION.LOCATION_EN }
      'Location Location Id'                      { $evResponseData=$evResponseData.LOCATION.LOCATION_ID }
      'Location Location Path'                    { $evResponseData=$evResponseData.LOCATION.LOCATION_PATH }
      'Location Path'                             { $evResponseData=$evResponseData.LOCATION_PATH }
      'Mark 1'                                    { $evResponseData=$evResponseData.MARK_1 }
      'Mark 2'                                    { $evResponseData=$evResponseData.MARK_2 }
      'Max Resolution Date'                       { $evResponseData=$evResponseData.MAX_RESOLUTION_DATE_UT }
      'Ms Project Import Validation Waiting'      { $evResponseData=$evResponseData.MS_PROJECT_IMPORT_VALIDATION_WAITING }
      'Net Price Cur Id'                          { $evResponseData=$evResponseData.NET_PRICE_CUR_ID }
      'Net Price'                                 { $evResponseData=$evResponseData.NET_PRICE }
      'News Id'                                   { $evResponseData=$evResponseData.NEWS_ID }
      'Not Deduced Call'                          { $evResponseData=$evResponseData.NOT_DEDUCED_CALL }
      'Order Id'                                  { $evResponseData=$evResponseData.ORDER_ID }
      'Order Net Price'                           { $evResponseData=$evResponseData.ORDER_NET_PRICE }
      'Origin Tool Id'                            { $evResponseData=$evResponseData.ORIGIN_TOOL_ID }
      'Owner Id'                                  { $evResponseData=$evResponseData.OWNER_ID }
      'Owning Group Id'                           { $evResponseData=$evResponseData.OWNING_GROUP_ID }
      'Parent Request Id'                         { $evResponseData=$evResponseData.PARENT_REQUEST_ID }
      'Planned Change Date End'                   { $evResponseData=$evResponseData.PLANNED_CHANGE_DATE_END }
      'Planned Change Date Start'                 { $evResponseData=$evResponseData.PLANNED_CHANGE_DATE_START }
      'Pm Status Id'                              { $evResponseData=$evResponseData.PM_STATUS_ID }
      'Potential Impact'                          { $evResponseData=$evResponseData.E_POTENTIAL_IMPACT }
      'Project Id'                                { $evResponseData=$evResponseData.PROJECT_ID }
      'Project Name'                              { $evResponseData=$evResponseData.PROJECT_NAME }
      'Project Start Date'                        { $evResponseData=$evResponseData.PROJECT_START_DATE_UT }
      'Qty'                                       { $evResponseData=$evResponseData.QTY }
      'Recipient Begin Of Contract'               { $evResponseData=$evResponseData.RECIPIENT.BEGIN_OF_CONTRACT }
      'Recipient Cellular Number'                 { $evResponseData=$evResponseData.RECIPIENT.CELLULAR_NUMBER }
      'Recipient Department Path'                 { $evResponseData=$evResponseData.RECIPIENT.DEPARTMENT_PATH }
      'Recipient EmployeId'                       { $evResponseData=$evResponseData.RECIPIENT.EMPLOYEE_ID }
      'Recipient Id'                              { $evResponseData=$evResponseData.RECIPIENT_ID }
      'Recipient Last Name'                       { $evResponseData=$evResponseData.RECIPIENT.LAST_NAME }
      'Recipient Location Path'                   { $evResponseData=$evResponseData.RECIPIENT.LOCATION_PATH }
      'Recipient Mail'                            { $evResponseData=$evResponseData.RECIPIENT.E_MAIL }
      'Recipient PhonNumber'                      { $evResponseData=$evResponseData.RECIPIENT.PHONE_NUMBER }
      'Release Id'                                { $evResponseData=$evResponseData.RELEASE_ID }
      'Rental Net PricCur Id'                     { $evResponseData=$evResponseData.RENTAL_NET_PRICE_CUR_ID }
      'Rental Net Price'                          { $evResponseData=$evResponseData.RENTAL_NET_PRICE }
      'Requalification Processing'                { $evResponseData=$evResponseData.REQUALIFICATION_PROCESSING }
      'Request Id'                                { $evResponseData=$evResponseData.REQUEST_ID }
      'Request Origin Id'                         { $evResponseData=$evResponseData.REQUEST_ORIGIN_ID }
      'Request Project Id'                        { $evResponseData=$evResponseData.REQUEST_PROJECT_ID }
      'Requested ChangDatEnd'                     { $evResponseData=$evResponseData.REQUESTED_CHANGE_DATE_END }
      'Requested ChangDatStart'                   { $evResponseData=$evResponseData.REQUESTED_CHANGE_DATE_START }
      'Requestor Begin Of Contract'               { $evResponseData=$evResponseData.REQUESTOR.BEGIN_OF_CONTRACT }
      'Requestor Cellular Number'                 { $evResponseData=$evResponseData.REQUESTOR.CELLULAR_NUMBER }
      'Requestor Department Path'                 { $evResponseData=$evResponseData.REQUESTOR.DEPARTMENT_PATH }
      'Requestor Employee Id'                     { $evResponseData=$evResponseData.REQUESTOR.EMPLOYEE_ID }
      'Requestor Feedback'                        { $evResponseData=$evResponseData.REQUESTOR_FEEDBACK }
      'Requestor Id'                              { $evResponseData=$evResponseData.REQUESTOR_ID }
      'Requestor Ip Address'                      { $evResponseData=$evResponseData.REQUESTOR_IP_ADDRESS }
      'Requestor Last Name'                       { $evResponseData=$evResponseData.REQUESTOR.LAST_NAME }
      'Requestor Location Path'                   { $evResponseData=$evResponseData.REQUESTOR.LOCATION_PATH }
      'Requestor Mail'                            { $evResponseData=$evResponseData.REQUESTOR.E_MAIL }
      'Requestor Phone Number'                    { $evResponseData=$evResponseData.REQUESTOR.PHONE_NUMBER }
      'Requestor Phone'                           { $evResponseData=$evResponseData.REQUESTOR_PHONE }
      'Required Downtime'                         { $evResponseData=$evResponseData.REQUIRED_DOWNTIME }
      'Rfc Number'                                { $evResponseData=$evResponseData.RFC_NUMBER }
      'Risk Amount'                               { $evResponseData=$evResponseData.RISK_AMOUNT }
      'Risk Description Href'                     { $evResponseData=$evResponseData.RISK_DESCRIPTION.HREF }
      'Risk Level Id'                             { $evResponseData=$evResponseData.RISK_LEVEL_ID }
      'Root CausId'                               { $evResponseData=$evResponseData.ROOT_CAUSE_ID }
      'Sd Catalog Id'                             { $evResponseData=$evResponseData.SD_CATALOG_ID }
      'Sd Catalog Path'                           { $evResponseData=$evResponseData.SD_CATALOG_PATH }
      'Severity Id'                               { $evResponseData=$evResponseData.SEVERITY_ID }
      'Sla Id'                                    { $evResponseData=$evResponseData.SLA_ID }
      'Status Id'                                 { $evResponseData=$evResponseData.STATUS_ID }
      'Status'                                    { $evResponseData=$evResponseData.STATUS.STATUS_EN }
      'Status Guid'                               { $evResponseData=$evResponseData.STATUS.STATUS_GUID }
      'Status Id'                                 { $evResponseData=$evResponseData.STATUS.STATUS_ID }
      'Status'                                    { $evResponseData=$evResponseData.STATUS }
      'Submit Date'                               { $evResponseData=$evResponseData.SUBMIT_DATE_UT }
      'Submitted By'                              { $evResponseData=$evResponseData.SUBMITTED_BY }
      'Successful Change'                         { $evResponseData=$evResponseData.E_SUCCESSFUL_CHANGE }
      'Survey Result'                             { $evResponseData=$evResponseData.E_survey_result }
      'System Id'                                 { $evResponseData=$evResponseData.SYSTEM_ID }
      'Testing Details Href'                      { $evResponseData=$evResponseData.E_TESTING_DETAILS.HREF }
      'Time Used To Deliver Feedback'             { $evResponseData=$evResponseData.TIME_USED_TO_DELIVER_FEEDBACK }
      'Time Used To Solve Request'                { $evResponseData=$evResponseData.TIME_USED_TO_SOLVE_REQUEST }
      'Trigger'                                   { $evResponseData=$evResponseData.E_TRIGGER }
      'Urgency Id'                                { $evResponseData=$evResponseData.URGENCY_ID }
      'Validation Level Required'                 { $evResponseData=$evResponseData.VALIDATION_LEVEL_REQUIRED }
      'Variable 1'                                { $evResponseData=$evResponseData.E_VARIABLE_1 }
      'Variable 2'                                { $evResponseData=$evResponseData.E_VARIABLE_2 }
      'Variable 3'                                { $evResponseData=$evResponseData.E_VARIABLE_3 }
      'Variable 4'                                { $evResponseData=$evResponseData.E_VARIABLE_4 }
      'Variable 5'                                { $evResponseData=$evResponseData.E_VARIABLE_5 }
      'Wave Id Target'                            { $evResponseData=$evResponseData.WAVE_ID_TARGET }
    }# Switch ($evOption)

    Write-Host "$evOption for $evRequestId" -ForegroundColor $evFGColorNum
    return $evResponseData

  }# Function Get-EVRequestData

  Function Get-EVConfigurationItemData  {
    <#
        .SYNOPSIS
        Describe purpose of "Get-EVConfigurationItemData" in 1-2 sentences.

        .DESCRIPTION
        Add a more complete description of what the function does.

        .PARAMETER AssetID
        Describe parameter -AssetID.

        .PARAMETER Option
        Describe parameter -evOption.

        .EXAMPLE
        Get-EVConfigurationItemData -AssetID <Value> -evOption <Value>

        .EXAMPLE
        Get-EVConfigurationItemData -AssetID 9372 -evOption ALL-Options

        ALL-Options for 9372

        ACQUISITION_TYPE_ID           : 33
        ASSET_GUID                    : {7FB048C0-6030-4B2E-896C-D568D8E44883}
        ASSET_ID                      : 9372
        HREF                          : /api/v1/50004/configuration-items/9372
        ASSET_LABEL                   :
        ASSET_TAG                     : CMC
        ...

        .EXAMPLE
        Get-EVConfigurationItemData -AssetID 9372 -evOption ALL-Options | select Network_Identifier, Serial_Number, Location_Path, END_OF_WARANTY | Where-Object {$_.END_OF_WARANTY -ge '2016-06-07'}

        ALL-Options for 9372

        NETWORK_IDENTIFIER SERIAL_NUMBER LOCATION_PATH END_OF_WARANTY
        ------------------ ------------- ------------- --------------
        riverbedcmc        V58QS000C924D Boise         2016-07-07

        .EXAMPLE
        Get-EVConfigurationItemData -AssetID 9372 -evOption E_IP_ADDRESS

        E_IP_ADDRESS for 9372
        10.102.1.47

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVConfigurationItemData

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>


    Param(
      [Parameter(Mandatory=$true,Position=0,
      HelpMessage='Enter the Assset ID,')]
      [string]$evAssetID,

      [ValidateSet('ALL-Options','ACQUISITION_TYPE_ID','ASSET_GUID','ASSET_ID','ASSET_NAME','ASSET_TAG',
          'AUTOMATIC_RENEWAL','AVAILABILITY_SLA_ID','AVAILABLE_FIELD_1','AVAILABLE_FIELD_2','AVAILABLE_FIELD_3',
          'AVAILABLE_FIELD_5','AVAILABLE_FIELD_6','BEFORE_LOAN_DEPARTMENT_ID','BEFORE_LOAN_DEPARTMENT_PATH',
          'BEFORE_LOAN_EMPLOYEE_ID','BEFORE_LOAN_LOCATION_ID','BEFORE_LOAN_LOCATION_PATH','BILLING_PERIODICITY_IN_MONTH',
          'BUDGET_ID','BUY_BACK_VALUE','BUY_BACK_VALUE_CUR_ID','CATALOG_ID','CHARGE_BACK','CHARGE_BACK_CUR_ID',
          'CI_BACKUP_BY_DEFAULT','CI_STATUS_ID','CI_VERSION','CM_DEFAULT_CHANGE_ID','CM_DEFAULT_CHANGE_PATH',
          'COMMENT_ASSET','CONFIGURATION_ID''CONTRACT_TYPE_ID','CRITICAL_LEVEL_ID','DELIVERY_DATE','DELIVERY_NUMBER',
          'DEPARTMENT_ID','DEPARTMENT_PATH','DEPRECIATION_RULE_ID','D_HARDWARE_GUID','EMPLOYEE_ID','END_OF_WARRANTY',
          'ENTRY_DATE','ESTIMATED_PERCENTAGE_USE','EXPECTED_END_LEND_DATE','EXPECTED_RETURN_DATE','E_BW_BEFORE_OVERAGE',
          'E_COLOR_BEFORE_OVERAGE','E_CONTRACT_RENEWED','E_CONTRACT_STATUS','E_COST_BW_COVERAGE','E_COST_BW_OVERAGE',
          'E_COST_COLOR_COVERAGE','E_COST_COLOR_OVERAGE','E_COST_PER_BW_CLICK','E_COST_PER_CLICK','E_COST_PER_COLOR_CLICK',
          'E_FAX_NUMBER','E_IP_ADDRESS','E_MAC_ADDRESS','E_NOTES','E_NOTIFICATION_DUR','E_OPERATING_SYSTEM','E_OVERAGE_COST',
          'E_PAGE_PER_MINUTE','E_PO_NUMBER','E_PRINT_SERVER','E_RELATED_TICKET_NUMBER','E_RLS_MANAGING_GROUP',
          'E_RLS_OWNING_GROUP','E_RLS_SUPPORTING_GROUP','E_RLS_USING_GROUP','E_SUPPLIER_EQUIP_NUM','E_TERM_LANG',
          'E_VMO_CONTACT','E_WIDE_BASE_CHARGE','E_WIDE_SQUARE_FEET','E_primary_employee','FALLEN_TERM','FIXED_ASSET_NUMBER',
          'HREF','HREF','INITIAL_START','INSTALLATION_DATE','INTERNAL_DELIVERY_DATE','INTERNAL_DISPO','INVENTORY_ID',
          'INVOICE_NUMBER','IS_CI','IS_DML','IS_LOCKED','IS_SERVICE','LAST_AUTOMATIC_DISCOVERY','LAST_INTEGRATION',
          'LAST_PAYMENT','LAST_PAYMENT_CUR_ID','LAST_PHYSICAL_INVENTORY','LAST_UPDATE','LICENSE_VERSION','LOCATION_ID',
          'LOCATION_PATH','LOCATION_TO_CHECK_REQUEST_ID','MAINTENANCE_COST','MAINTENANCE_COST_CUR_ID','MAIN_USAGE_ID',
          'MAX_INSTALLS','MONTHLY_FIXED_COST','MONTHLY_FIXED_COST_CUR_ID','MONTHLY_NET_RENTAL','MONTHLY_NET_RENTAL_CUR_ID',
          'MONTH_DURATION','NETWORK_IDENTIFIER','NEXT_CI_VERSION','NEXT_DEPARTMENT_ID','NEXT_DEPARTMENT_PATH',
          'NEXT_MAINTENANCE_DATE','NEXT_STATUS_ID','NEXT_USER_APPLICATION_DATE','NEXT_USER_ID','NOTICE','ORDER_DETAILS_ID',
          'ORDER_NUMBER','OWNERSHIP_TO_CHECK_REQUEST_ID','PACKAGE_PATH','PIPELINE_STATUS_ID','POWER_CONSUMPTION_WH',
          'PROCESSOR_COUNT','PROCESSOR_SOCKET_COUNT','PROJECT_ID','PROVIDER_ID','PROVIDER_PATH','PURCHASE_DATE','PURCHASE_PRICE',
          'PURCHASE_PRICE_CUR_ID','PURCHASE_RATE_ID','RECYCLED_DATE','RECYCLING_PROVIDER_ID','RECYCLING_PROVIDER_PATH',
          'REFORM_NUMBER','REMOVED_DATE','RENEWAL_DECISION_ID','RENEWAL_VALUE','RENEWAL_VALUE_CUR_ID','REPAIRED_BY_ID',
          'REPAIRED_BY_PATH','REQUEST_ID','RESALES_VALUE','SCHEDULED_END','SD_CATALOG_ID','SD_CATALOG_PATH','SD_DEFAULT_INCIDENT_ID',
          'SD_DEFAULT_INCIDENT_PATH','SD_DEFAULT_REQUEST_ID','SD_DEFAULT_REQUEST_PATH','SERIAL_NUMBER','SERVER_TYPE_ID',
          'SLA_ID','STATUS_ID','SUPPLIER_ID','SUPPLIER_PATH','TERM','UPDATED_BY_DISCOVERY','UPDATE_COVERAGE_TERM','WARRANTY_TYPE_ID',
          'WARRANTY_NUM','XPOS','YPOS','ZPOS')]
      [Parameter(Mandatory=$True,HelpMessage='Please hit tab to see selection options')]
      [string]$evOption
    )

    $evResponseData = ''


    $evUrl = ('{0}/{1}' -f $evConfigItemstUrl, $evAssetID)

    # Make the GET request
    $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

    Switch ($evOption) {
      'ALL-Options' {
        $evResponseData = $evResponseData
      }

      'ACQUISITION_TYPE_ID' {
        $evResponseData = $evResponseData.ACQUISITION_TYPE_ID
      }

      'ASSET_GUID' {
        $evResponseData = $evResponseData.ASSET_GUID
      }

      'ASSET_ID' {
        $evResponseData = $evResponseData.ASSET_ID
      }

      'HREF' {
        $evResponseData = $evResponseData.HREF
      }

      'ASSET_NAME' {
        $evResponseData = $evResponseData.ASSET_LABEL
      }

      'ASSET_TAG' {
        $evResponseData = $evResponseData.ASSET_TAG
      }

      'AUTOMATIC_RENEWAL' {
        $evResponseData = $evResponseData.AUTOMATIC_RENEWAL
      }

      'AVAILABILITY_SLA_ID' {
        $evResponseData = $evResponseData.AVAILABILITY_SLA_ID
      }

      'AVAILABLE_FIELD_1' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_1
      }

      'AVAILABLE_FIELD_2' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_2
      }

      'AVAILABLE_FIELD_3' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_3
      }

      'WARRANTY_NUM' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_4
      }

      'AVAILABLE_FIELD_5' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_5
      }

      'AVAILABLE_FIELD_6' {
        $evResponseData = $evResponseData.AVAILABLE_FIELD_6
      }

      'BEFORE_LOAN_DEPARTMENT_PATH' {
        $evResponseData = $evResponseData.BEFORE_LOAN_DEPARTMENT_PATH
      }

      'BEFORE_LOAN_DEPARTMENT_ID' {
        $evResponseData = $evResponseData.BEFORE_LOAN_DEPARTMENT_ID
      }

      'BEFORE_LOAN_EMPLOYEE_ID' {
        $evResponseData = $evResponseData.BEFORE_LOAN_EMPLOYEE_ID
      }

      'BEFORE_LOAN_LOCATION_PATH' {
        $evResponseData = $evResponseData.BEFORE_LOAN_LOCATION_PATH
      }

      'BEFORE_LOAN_LOCATION_ID' {
        $evResponseData = $evResponseData.BEFORE_LOAN_LOCATION_ID
      }

      'BILLING_PERIODICITY_IN_MONTH' {
        $evResponseData = $evResponseData.BILLING_PERIODICITY_IN_MONTH
      }

      'BUDGET_ID' {
        $evResponseData = $evResponseData.BUDGET_ID
      }

      'BUY_BACK_VALUE' {
        $evResponseData = $evResponseData.BUY_BACK_VALUE
      }

      'BUY_BACK_VALUE_CUR_ID' {
        $evResponseData = $evResponseData.BUY_BACK_VALUE_CUR_ID
      }

      'CATALOG_ID' {
        $evResponseData = $evResponseData.CATALOG_ID
      }

      'CHARGE_BACK' {
        $evResponseData = $evResponseData.CHARGE_BACK
      }

      'CHARGE_BACK_CUR_ID' {
        $evResponseData = $evResponseData.CHARGE_BACK_CUR_ID
      }

      'CI_BACKUP_BY_DEFAULT' {
        $evResponseData = $evResponseData.CI_BACKUP_BY_DEFAULT
      }

      'CI_STATUS_ID' {
        $evResponseData = $evResponseData.CI_STATUS_ID
      }

      'CI_VERSION' {
        $evResponseData = $evResponseData.CI_VERSION
      }

      'CM_DEFAULT_CHANGE_PATH' {
        $evResponseData = $evResponseData.CM_DEFAULT_CHANGE_PATH
      }

      'CM_DEFAULT_CHANGE_ID' {
        $evResponseData = $evResponseData.CM_DEFAULT_CHANGE_ID
      }

      'COMMENT_ASSET' {
        $evResponseData = $evResponseData.COMMENT_ASSET
      }

      'HREF' {
        $evResponseData = $evResponseData.HREF
      }

      'CONFIGURATION_ID' {
        $evResponseData = $evResponseData.CONFIGURATION_ID
      }

      'CONTRACT_TYPE_ID' {
        $evResponseData = $evResponseData.CONTRACT_TYPE_ID
      }

      'CRITICAL_LEVEL_ID' {
        $evResponseData = $evResponseData.CRITICAL_LEVEL_ID
      }

      'D_HARDWARE_GUID' {
        $evResponseData = $evResponseData.D_HARDWARE_GUID
      }

      'DELIVERY_DATE' {
        $evResponseData = $evResponseData.DELIVERY_DATE
      }

      'DELIVERY_NUMBER' {
        $evResponseData = $evResponseData.DELIVERY_NUMBER
      }

      'DEPARTMENT_PATH' {
        $evResponseData = $evResponseData.DEPARTMENT_PATH
      }

      'DEPARTMENT_ID' {
        $evResponseData = $evResponseData.DEPARTMENT_ID
      }

      'DEPRECIATION_RULE_ID' {
        $evResponseData = $evResponseData.DEPRECIATION_RULE_ID
      }

      'E_BW_BEFORE_OVERAGE' {
        $evResponseData = $evResponseData.E_BW_BEFORE_OVERAGE
      }

      'E_COLOR_BEFORE_OVERAGE' {
        $evResponseData = $evResponseData.E_COLOR_BEFORE_OVERAGE
      }

      'E_CONTRACT_RENEWED' {
        $evResponseData = $evResponseData.E_CONTRACT_RENEWED
      }

      'E_CONTRACT_STATUS' {
        $evResponseData = $evResponseData.E_CONTRACT_STATUS
      }

      'E_COST_BW_COVERAGE' {
        $evResponseData = $evResponseData.E_COST_BW_COVERAGE
      }

      'E_COST_BW_OVERAGE' {
        $evResponseData = $evResponseData.E_COST_BW_OVERAGE
      }

      'E_COST_COLOR_COVERAGE' {
        $evResponseData = $evResponseData.E_COST_COLOR_COVERAGE
      }

      'E_COST_COLOR_OVERAGE' {
        $evResponseData = $evResponseData.E_COST_COLOR_OVERAGE
      }

      'E_COST_PER_BW_CLICK' {
        $evResponseData = $evResponseData.E_COST_PER_BW_CLICK
      }

      'E_COST_PER_CLICK' {
        $evResponseData = $evResponseData.E_COST_PER_CLICK
      }

      'E_COST_PER_COLOR_CLICK' {
        $evResponseData = $evResponseData.E_COST_PER_COLOR_CLICK
      }

      'E_FAX_NUMBER' {
        $evResponseData = $evResponseData.E_FAX_NUMBER
      }

      'E_IP_ADDRESS' {
        $evResponseData = $evResponseData.E_IP_ADDRESS
      }

      'E_MAC_ADDRESS' {
        $evResponseData = $evResponseData.E_MAC_ADDRESS
      }

      'E_NOTES' {
        $evResponseData = $evResponseData.E_NOTES
      }

      'E_NOTIFICATION_DUR' {
        $evResponseData = $evResponseData.E_NOTIFICATION_DUR
      }

      'E_OPERATING_SYSTEM' {
        $evResponseData = $evResponseData.E_OPERATING_SYSTEM
      }

      'E_OVERAGE_COST' {
        $evResponseData = $evResponseData.E_OVERAGE_COST
      }

      'E_PAGE_PER_MINUTE' {
        $evResponseData = $evResponseData.E_PAGE_PER_MINUTE
      }

      'E_PO_NUMBER' {
        $evResponseData = $evResponseData.E_PO_NUMBER
      }

      'E_primary_employee' {
        $evResponseData = $evResponseData.E_primary_employee
      }

      'E_PRINT_SERVER' {
        $evResponseData = $evResponseData.E_PRINT_SERVER
      }

      'E_RELATED_TICKET_NUMBER' {
        $evResponseData = $evResponseData.E_RELATED_TICKET_NUMBER
      }

      'E_RLS_MANAGING_GROUP' {
        $evResponseData = $evResponseData.E_RLS_MANAGING_GROUP
      }

      'E_RLS_OWNING_GROUP' {
        $evResponseData = $evResponseData.E_RLS_OWNING_GROUP
      }

      'E_RLS_SUPPORTING_GROUP' {
        $evResponseData = $evResponseData.E_RLS_SUPPORTING_GROUP
      }

      'E_RLS_USING_GROUP' {
        $evResponseData = $evResponseData.E_RLS_USING_GROUP
      }

      'E_SUPPLIER_EQUIP_NUM' {
        $evResponseData = $evResponseData.E_SUPPLIER_EQUIP_NUM
      }

      'E_TERM_LANG' {
        $evResponseData = $evResponseData.E_TERM_LANG
      }

      'E_VMO_CONTACT' {
        $evResponseData = $evResponseData.E_VMO_CONTACT
      }

      'E_WIDE_BASE_CHARGE' {
        $evResponseData = $evResponseData.E_WIDE_BASE_CHARGE
      }

      'E_WIDE_SQUARE_FEET' {
        $evResponseData = $evResponseData.E_WIDE_SQUARE_FEET
      }

      'EMPLOYEE_ID' {
        $evResponseData = $evResponseData.EMPLOYEE_ID
      }

      'END_OF_WARRANTY' {
        $evResponseData = $evResponseData.END_OF_WARANTY
      }

      'ENTRY_DATE' {
        $evResponseData = $evResponseData.ENTRY_DATE
      }

      'ESTIMATED_PERCENTAGE_USE' {
        $evResponseData = $evResponseData.ESTIMATED_PERCENTAGE_USE
      }

      'EXPECTED_END_LEND_DATE' {
        $evResponseData = $evResponseData.EXPECTED_END_LEND_DATE
      }

      'EXPECTED_RETURN_DATE' {
        $evResponseData = $evResponseData.EXPECTED_RETURN_DATE
      }

      'FALLEN_TERM' {
        $evResponseData = $evResponseData.FALLEN_TERM
      }

      'FIXED_ASSET_NUMBER' {
        $evResponseData = $evResponseData.FIXED_ASSET_NUMBER
      }

      'INITIAL_START' {
        $evResponseData = $evResponseData.INITIAL_START
      }

      'INSTALLATION_DATE' {
        $evResponseData = $evResponseData.INSTALLATION_DATE
      }

      'INTERNAL_DELIVERY_DATE' {
        $evResponseData = $evResponseData.INTERNAL_DELIVERY_DATE
      }

      'INTERNAL_DISPO' {
        $evResponseData = $evResponseData.INTERNAL_DISPO
      }

      'INVENTORY_ID' {
        $evResponseData = $evResponseData.INVENTORY_ID
      }

      'INVOICE_NUMBER' {
        $evResponseData = $evResponseData.INVOICE_NUMBER
      }

      'IS_CI' {
        $evResponseData = $evResponseData.IS_CI
      }

      'IS_DML' {
        $evResponseData = $evResponseData.IS_DML
      }

      'IS_LOCKED' {
        $evResponseData = $evResponseData.IS_LOCKED
      }

      'IS_SERVICE' {
        $evResponseData = $evResponseData.IS_SERVICE
      }

      'LAST_AUTOMATIC_DISCOVERY' {
        $evResponseData = $evResponseData.LAST_AUTOMATIC_DISCOVERY
      }

      'LAST_INTEGRATION' {
        $evResponseData = $evResponseData.LAST_INTEGRATION
      }

      'LAST_PAYMENT' {
        $evResponseData = $evResponseData.LAST_PAYMENT
      }

      'LAST_PAYMENT_CUR_ID' {
        $evResponseData = $evResponseData.LAST_PAYMENT_CUR_ID
      }

      'LAST_PHYSICAL_INVENTORY' {
        $evResponseData = $evResponseData.LAST_PHYSICAL_INVENTORY
      }

      'LAST_UPDATE' {
        $evResponseData = $evResponseData.LAST_UPDATE
      }

      'LICENSE_VERSION' {
        $evResponseData = $evResponseData.LICENSE_VERSION
      }


      'LOCATION_PATH' {
        $evResponseData = $evResponseData.LOCATION_PATH
      }

      'LOCATION_ID' {
        $evResponseData = $evResponseData.LOCATION_ID
      }

      'LOCATION_TO_CHECK_REQUEST_ID' {
        $evResponseData = $evResponseData.LOCATION_TO_CHECK_REQUEST_ID
      }

      'MAIN_USAGE_ID' {
        $evResponseData = $evResponseData.MAIN_USAGE_ID
      }
      'MAINTENANCE_COST' {
        $evResponseData = $evResponseData.MAINTENANCE_COST
      }

      'MAINTENANCE_COST_CUR_ID' {
        $evResponseData = $evResponseData.MAINTENANCE_COST_CUR_ID
      }

      'MAX_INSTALLS' {
        $evResponseData = $evResponseData.MAX_INSTALLS
      }

      'MONTH_DURATION' {
        $evResponseData = $evResponseData.MONTH_DURATION
      }

      'MONTHLY_FIXED_COST' {
        $evResponseData = $evResponseData.MONTHLY_FIXED_COST
      }

      'MONTHLY_FIXED_COST_CUR_ID' {
        $evResponseData = $evResponseData.MONTHLY_FIXED_COST_CUR_ID
      }

      'MONTHLY_NET_RENTAL' {
        $evResponseData = $evResponseData.MONTHLY_NET_RENTAL
      }

      'MONTHLY_NET_RENTAL_CUR_ID' {
        $evResponseData = $evResponseData.MONTHLY_NET_RENTAL_CUR_ID
      }

      'NETWORK_IDENTIFIER' {
        $evResponseData = $evResponseData.NETWORK_IDENTIFIER
      }

      'NEXT_CI_VERSION' {
        $evResponseData = $evResponseData.NEXT_CI_VERSION
      }

      'NEXT_DEPARTMENT_PATH' {
        $evResponseData = $evResponseData.NEXT_DEPARTMENT_PATH
      }

      'NEXT_DEPARTMENT_ID' {
        $evResponseData = $evResponseData.NEXT_DEPARTMENT_ID
      }

      'NEXT_MAINTENANCE_DATE' {
        $evResponseData = $evResponseData.NEXT_MAINTENANCE_DATE
      }

      'NEXT_STATUS_ID' {
        $evResponseData = $evResponseData.NEXT_STATUS_ID
      }

      'NEXT_USER_APPLICATION_DATE' {
        $evResponseData = $evResponseData.NEXT_USER_APPLICATION_DATE
      }

      'NEXT_USER_ID' {
        $evResponseData = $evResponseData.NEXT_USER_ID
      }

      'NOTICE' {
        $evResponseData = $evResponseData.NOTICE
      }

      'ORDER_DETAILS_ID' {
        $evResponseData = $evResponseData.ORDER_DETAILS_ID
      }

      'ORDER_NUMBER' {
        $evResponseData = $evResponseData.ORDER_NUMBER
      }

      'OWNERSHIP_TO_CHECK_REQUEST_ID' {
        $evResponseData = $evResponseData.OWNERSHIP_TO_CHECK_REQUEST_ID
      }

      'PACKAGE_PATH' {
        $evResponseData = $evResponseData.PACKAGE_PATH
      }

      'PIPELINE_STATUS_ID' {
        $evResponseData = $evResponseData.PIPELINE_STATUS_ID
      }

      'POWER_CONSUMPTION_WH' {
        $evResponseData = $evResponseData.POWER_CONSUMPTION_WH
      }

      'PROCESSOR_COUNT' {
        $evResponseData = $evResponseData.PROCESSOR_COUNT
      }

      'PROCESSOR_SOCKET_COUNT' {
        $evResponseData = $evResponseData.PROCESSOR_SOCKET_COUNT
      }

      'PROJECT_ID' {
        $evResponseData = $evResponseData.PROJECT_ID
      }

      'PROVIDER_PATH' {
        $evResponseData = $evResponseData.PROVIDER_PATH
      }

      'PROVIDER_ID' {
        $evResponseData = $evResponseData.PROVIDER_ID
      }

      'PURCHASE_DATE' {
        $evResponseData = $evResponseData.PURCHASE_DATE
      }

      'PURCHASE_PRICE' {
        $evResponseData = $evResponseData.PURCHASE_PRICE
      }

      'PURCHASE_PRICE_CUR_ID' {
        $evResponseData = $evResponseData.PURCHASE_PRICE_CUR_ID
      }

      'PURCHASE_RATE_ID' {
        $evResponseData = $evResponseData.PURCHASE_RATE_ID
      }

      'RECYCLED_DATE' {
        $evResponseData = $evResponseData.RECYCLED_DATE
      }

      'RECYCLING_PROVIDER_PATH' {
        $evResponseData = $evResponseData.RECYCLING_PROVIDER_PATH
      }

      'RECYCLING_PROVIDER_ID' {
        $evResponseData = $evResponseData.RECYCLING_PROVIDER_ID
      }

      'REFORM_NUMBER' {
        $evResponseData = $evResponseData.REFORM_NUMBER
      }

      'REMOVED_DATE' {
        $evResponseData = $evResponseData.REMOVED_DATE
      }

      'RENEWAL_DECISION_ID' {
        $evResponseData = $evResponseData.RENEWAL_DECISION_ID
      }

      'RENEWAL_VALUE' {
        $evResponseData = $evResponseData.RENEWAL_VALUE
      }

      'RENEWAL_VALUE_CUR_ID' {
        $evResponseData = $evResponseData.RENEWAL_VALUE_CUR_ID
      }

      'REPAIRED_BY_PATH' {
        $evResponseData = $evResponseData.REPAIRED_BY_PATH
      }

      'REPAIRED_BY_ID' {
        $evResponseData = $evResponseData.REPAIRED_BY_ID
      }

      'REQUEST_ID' {
        $evResponseData = $evResponseData.REQUEST_ID
      }

      'RESALES_VALUE' {
        $evResponseData = $evResponseData.RESALES_VALUE
      }

      'SCHEDULED_END' {
        $evResponseData = $evResponseData.SCHEDULED_END
      }

      'SD_CATALOG_PATH' {
        $evResponseData = $evResponseData.SD_CATALOG_PATH
      }

      'SD_CATALOG_ID' {
        $evResponseData = $evResponseData.SD_CATALOG_ID
      }

      'SD_DEFAULT_INCIDENT_PATH' {
        $evResponseData = $evResponseData.SD_DEFAULT_INCIDENT_PATH
      }

      'SD_DEFAULT_INCIDENT_ID' {
        $evResponseData = $evResponseData.SD_DEFAULT_INCIDENT_ID
      }

      'SD_DEFAULT_REQUEST_PATH' {
        $evResponseData = $evResponseData.SD_DEFAULT_REQUEST_PATH
      }

      'SD_DEFAULT_REQUEST_ID' {
        $evResponseData = $evResponseData.SD_DEFAULT_REQUEST_ID
      }

      'SERIAL_NUMBER' {
        $evResponseData = $evResponseData.SERIAL_NUMBER
      }

      'SERVER_TYPE_ID' {
        $evResponseData = $evResponseData.SERVER_TYPE_ID
      }

      'SLA_ID' {
        $evResponseData = $evResponseData.SLA_ID
      }

      'STATUS_ID' {
        $evResponseData = $evResponseData.STATUS_ID
      }

      'SUPPLIER_PATH' {
        $evResponseData = $evResponseData.SUPPLIER_PATH
      }

      'SUPPLIER_ID' {
        $evResponseData = $evResponseData.SUPPLIER_ID
      }

      'TERM' {
        $evResponseData = $evResponseData.TERM
      }

      'UPDATE_COVERAGE_TERM' {
        $evResponseData = $evResponseData.UPDATE_COVERAGE_TERM
      }

      'UPDATED_BY_DISCOVERY' {
        $evResponseData = $evResponseData.UPDATED_BY_DISCOVERY
      }

      'WARRANTY_TYPE_ID' {
        $evResponseData = $evResponseData.WARANTY_TYPE_ID
      }

      'XPOS' {
        $evResponseData = $evResponseData.XPOS
      }

      'YPOS' {
        $evResponseData = $evResponseData.YPOS
      }

      'ZPOS' {
        $evResponseData = $evResponseData.ZPOS
      }
    }# Switch ($evOption)

    Write-Host "$evOption for $evAssetID" -ForegroundColor $evFGColorNum
    return $evResponseData

  }# Function Get-EVConfigurationItemData

  Function Get-EVRequestData {
    <#
        .SYNOPSIS
        "Get-EVRequestData" function

        .DESCRIPTION
        This function returns data from a configuation item in EasyVista.

        .PARAMETER SearchType
        Catalog_Requests or Requests.

        .PARAMETER StatusName
        Specifies the status you are searching for.

        .PARAMETER SearchTitle
        A keyword type description in the title of the request.

        .PARAMETER Employee
        The name of the employee who submitted the request.

        .PARAMETER timespan
        Duration in time as specified in general terms below or spcified time range.
         To search a range of dates for example: 05/10/2016 to 06/10/2019
          search=Submit_Date_UT:(05/10/2016;06/10/2019)

          this_year
          this_month
          this_week
          this_day
          today
          last_year
          last_month
          last_week
          first_quarter
          Q1
          second_quarter
          Q2
          third_quarter
          Q3
          fourth_quarter
          last_quarter
          Q4
          next_day
          tomorrow
          next_week
          next_month
          next_year
          daysbefore
          daysafter

        .PARAMETER MaxRows
        Describe parameter -MaxRows.

        .PARAMETER Help
        Describe parameter -Help.

        .EXAMPLE
        Get-EVRequestData -SearchType Requests -StatusName Closed -SearchTitle *Net* -timespan '05/10/2016;06/10/2019' -MaxRows 100

        .EXAMPLE
        Get-EVRequestData -SearchType Value -StatusName Value -SearchTitle Value -Employee Value -timespan Value -MaxRows Value

        .EXAMPLE
        Get-EVRequestByStatus -SearchType Catalog_Request -StatusName Cancelled -SearchTitle *C* -MaxRows 30 -Employee 'Green, Dan'

        .EXAMPLE
        Get-EVRequestByStatus -SearchType Catalog_Request -StatusName * -SearchTitle *Network* -MaxRows 30 -Employee 'Green, Dan' | Select-Object RFC_Number, Recipient

        .EXAMPLE
        Get-EVRequestByStatus -SearchType Catalog_Request -StatusName * -SearchTitle *Network* -MaxRows 30 -Employee 'Green, Dan' | Select-Object RFC_Number, Requestor

        .EXAMPLE
        Get-EVRequestByStatus -SearchType Catalog_Request -StatusName * -SearchTitle *Network* -MaxRows 300 -Employee 'Green, Dan' | ft -AutoSize

        .EXAMPLE
        Get-EVRequestData -Help
        Returns basic

        .NOTES
        Flexible searching criteria.

        .LINK
        None

        .INPUTS
        See parameters

        .OUTPUTS
        Requests data.
    #>


    [CmdletBinding(DefaultParametersetName='p1')]
    Param(
      [ValidateSet('Requests','Catalog_Request')]
      [Parameter(ParameterSetName='p1',Mandatory=$true,Position=0,
      HelpMessage='Enter the search type,')]
      [string]$evSearchType,

      [ValidateSet('*','Closed','Cancelled','Archived','Releasing','Solved','Pending','On Hold','Fulfilled','Escalated','Shipped','Computer Build In Process','IT Scheduling')]
      [Parameter(ParameterSetName='p1',Mandatory=$False,Position=1)]
      [string]$evStatusName,


      [Parameter(ParameterSetName='p1',Mandatory=$True,Position=2,
      HelpMessage='Enter the search type,')]
      [string]$evSearchTitle,

      [Parameter(ParameterSetName='p1',Mandatory=$False)]
      [string]$evEmployee,

      # https://wiki.easyvista.com/xwiki/bin/view/Documentation/REST+API+-+Options+for+Fields
      #[ValidateSet('this_year','this_month','this_week','this_day','today','last_year','last_month','last_week','first_quarter','Q1','second_quarter','Q2','third_quarter','Q3','fourth_quarter','last_quarter','Q4','next_day','tomorrow','next_week','next_month','next_year','daysbefore','daysafter')]
      [Parameter(ParameterSetName='p1',Mandatory=$False)]
      [string]$evTimeSpan,

      [Parameter(ParameterSetName='p1',Mandatory=$False)]
      [int]$evMaxRows,

      [Parameter(ParameterSetName='p2',Mandatory=$True)]
      [switch]$evHelp

    )

    $Error.clear()

    switch ($PsCmdlet.ParameterSetName)
    {
      'P1'  { Write-Host $evSearchTitle
        break
      }
      'P2'  { Write-Host $evHelp
        break
      }
    }


    Switch ($evSearchType) {
      'Requests' {  $evUri = $evRequestsUrl }
      'Catalog_Request' { $evUri = $evCatalogAssetUrl}
    }

    # & max_rows key
    If ($evMaxRows) {

      $evUri += "?max_rows=$evMaxRows&"
    } Else {
      $evUri += '?'
    }

    #
    If ($evSearchType) {

      $evUri += 'search=' + ('{0}' -f $evSearchType) + '.title_en~' + '"' + $evSearchTitle +'"'
    }

    If ($evStatusName) {

      $evUri += ',status.status_en~' + '"' + $evStatusName +'"'
    }

    If ($evEmployee) {

      $evUri += ',Requestor.Last_Name~' + '"' + $evEmployee + '"'
    }

    If ($evTimeSpan) {

      $evUri += ',submit_date_ut=' + '"' + $evTimeSpan + '"'
    }

    Write-Host "Uri: $evUri" -ForegroundColor $evFGColorInfo

    # Get Status Id's.

    Try {
      $evResponseData =  Invoke-RestMethod -Method GET -Uri  $evUri -Headers $global:evHeader -ErrorAction SilentlyContinue

    } Catch {
      Write-Host 'There was a problem collecting the data. Try modifying your request.' -ForegroundColor $evFGColorInfo
    }


    If ($evResponseData -and ($evResponseData.record_count -eq 1) ) {
      $evResponseData =  $evResponseData.records | Select-Object RFC_NUMBER,
      @{n='Status';e={$_.Status.Status_en} },
      @{n='Submit_Date';e={$_.Submit_date_ut} },
      @{n='Deptartment';e={$_.Department.Department_EN} },
      @{n='Location';e={$_.Location.Location_en} },
      @{n='Requestor';e={$_.Requestor.E_Mail} },
      @{n='Requestor_Phone';e={$_.Requestor.Phone_Number} },
      @{n='Requestor_Cell';e={$_.Requestor.Cellular_Number} },
      @{n='Recipient';e={$_.Recipient.Last_Name} },
      @{n='RecipientPhone';e={$_.Recipient.Phone_Number} },
      @{n='HREF';e={$_.Comment.href} }

      Write-Host ('Search Type: {0}' -f $evSearchType) -ForegroundColor $evFGColorInfo
      Write-Host ('Record Count: {0} of {1}' -f $evResponseData.records.Count, $evResponseData.total_record_count) -ForegroundColor $evFGColorNum


    } Elseif ($evResponseData.record_count -lt 1) {

      $evResponseData = '---'
      Write-Host ('No records meet the criteria. {0}' -f $evResponseData) -ForegroundColor $evFGColorInfo

    } Else {
      $evResponseData = $evResponseData.records

    }  # If (!$Data)

    # Validate status input.

    return $evResponseData


  }# Function Get-EVRequestData

  Function Get-EVRequestComment([string]$evReqNumber) {
    <#
        .SYNOPSIS
        "Get-EVRequestComment" function to return comment data

        .DESCRIPTION
        An input of the href of a record will expose the comments.

        .PARAMETER ReqNumber
        Enter the RFC, Incident, or Reqeust number

        .EXAMPLE
        Get-EVRequestComment -ReqNumber <Value>

        .EXAMPLE
        Get-EVRequestComment -ReqNumber INC042770

        Returns:
        <p>Our Boise Data Center is seeing intermittent issues accessing TDC and other locations over the Masergy WAN. This
        is an issue that primarily has been impacting TDC but it issue is a rolling one that has caused connectivity
        issues to CDC as well as KCK and other locations. Masergy is currently working with the local LEC to
        investigate a possible MAC address filtering issue. We are asking for 30 minute updates from Masergy
        until the issue is resolved.</p>
        <p></p>
        <p>Please create ticket and assign to Dan Green.</p>
        <p></p>
        <p>Thanks,</p>
        <p>Dan</p>

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Request or Incident number

        .OUTPUTS
        Request or Incident comments.
    #>

    $evUrl = "$evRequestsUrl/$evReqNumber/comment"

    # Make the GET request
    Try {
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

      If ($evResponseData.comment -eq '') {
        $evResponseData = 'Not present.'
        return $evResponseData
      } Else {
        return $evResponseData.comment
      }

      return $($evResponseData.comment)
    } Catch {
      Write-Warning "$evReqNumber doesn't exist."
    }

    return $evResponseData


  }# Function Get-EVRequestComment

  Function Get-EVConfigurationItemDeviceName([string]$evAssetID)  {
    <#
        .SYNOPSIS
        "Get-EVConfigurationItemDeviceName" to retrieve the name of the device.

        .DESCRIPTION
        Requires that you obtain the Asset ID to retrieve the device name.

        .PARAMETER AssetID

        .EXAMPLE
        Get-EVConfigurationItemDeviceName -evAssetID <Value>

        .EXAMPLE
        Get-EVConfigurationItemDeviceName -evAssetID 91672
        air-idf2-ups1

        Get-EVConfigurationItemDeviceName -evAssetID (Get-EVAssetDetailByAssetName -evHostname itrockss -evOption ASSET_ID)

        ASSET_ID for itrockss is 117391. - (Yellow)
        117391


        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVConfigurationItemDeviceName

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>



    $evUrl = "$evConfigItemstUrl/$evAssetID"

    # Make the GET request
    Try {
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

      If ($evResponseData.NETWORK_IDENTIFIER -eq '') {
        $evResponseData = '---'
      } Else {
        $evResponseData = $evResponseData.NETWORK_IDENTIFIER
      }

    } Catch {

      Write-Host "Did not find a record mathing asset id: $evAssetID" -ForegroundColor $evFGColorBad
    }

    If ($evResponseData) {
      Write-Host "Device Name: $evResponseData" -ForegroundColor $evFGColorInfo
    }
    return $evResponseData
  }# Function Get-EVConfigurationItem

  Function Get-EVConfigurationItemIPAddress([string]$evAssetID)  {
    <#
        .SYNOPSIS
        "Get-EVConfigurationItemIPAddress" Function to return the IP address.

        .DESCRIPTION
        Returns the IP address for a given Asset ID if it exists.

        .PARAMETER AssetID
        Enter the Asset ID.

        .EXAMPLE
        Get-EVConfigurationItemIPAddress -AssetID <Value>
        Returns xxx.xxx.xxx.xxx

        .EXAMPLE
        Get-EVConfigurationItemIPAddress -AssetID 91672

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Asset ID

        .OUTPUTS
        IP Address.
    #>

      $evUrl = "$evConfigItemstUrl/$evAssetID"

    # Make the GET request
    Try {
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

      If ($evResponseData.E_IP_ADDRESS -eq '') {
        $evResponseData = '---'
        Write-Host "No IP address listed. $evResponseData" -ForegroundColor $evFGColorBad
        return $evResponseData
      } Else {
        $evResponseData = $evResponseData.E_IP_ADDRESS
        Write-Host "IP Address: $evResponseData" -ForegroundColor $evFGColorInfo
        return $evResponseData
      }

    } Catch {
      Write-Host "Did not find a record mathing asset id: $evAssetID" -ForegroundColor $evFGColorBad
    }

  }# Function Get-EVConfigurationItemIPAddress

  Function Get-EVConfigurationItemtExtendedNotes([string]$evAssetID)  {
    <#
        .SYNOPSIS
        "Get-EVConfigurationItemtExtendedNotes" function.

        .DESCRIPTION
        Function to retrieve the notes from a given asset id..

        .PARAMETER AssetID
        Enter the AssetID.

        .EXAMPLE
        Get-EVConfigurationItemtExtendedNotes -AssetID <Value>
        Retrieves the notes for a given asset.

        .EXAMPLE
        Get-EVConfigurationItemtExtendedNotes -AssetID 5983

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Asset ID

        .OUTPUTS
        Asset Notes
    #>

     $evUrl = "$evConfigItemstUrl/$evAssetID/e_notes"

    # Make the GET request
    Try {
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader  #-UseBasicParsing

      If (!$evResponseData.E_NOTES) {

        $evResponseData = '---'
        Write-Host "No extended notes are present for asset id: $evAssetID $evResponseData" -ForegroundColor $evFGColorInfo
        #return $evResponseData

      } Else {
        $evResponseData = $evResponseData.E_NOTES
        Write-Host "Configuration Item extended notes: $evResponseData" -ForegroundColor $evFGColorInfo
        #return $evResponseData

      }
    }

    Catch   {
      Write-Host "Did not find a record mathing asset id: $evAssetID" -ForegroundColor $evFGColorBad
    }
    return $evResponseData

  }# Function Get-EVConfigurationItemtExtendedNotes

  Function Get-EVCatalogAssetData  {
    <#
        .SYNOPSIS
        "Get-EVCatalogAssetData" function.

        .DESCRIPTION
        Retrieves asset catalog id and option (param) data.

        .PARAMETER Option
        Specify an option for the data to retriveve.

        .PARAMETER MaxRows
        -MaxRows defaults to 100.  There may be a need to increase this if your search doesn't return any data.

        .EXAMPLE
        Get-EVCatalogAssetData -evOption Value -MaxRows <Value>

        .EXAMPLE
        Get-EVCatalogAssetData -Option MANUFACTURER -MaxRows 50

        MANUFACTURER for all records.
        Record 50 of 1805 possible records.
        You may want to extend the -MaxRows parameter to 1805.

        CATALOG_ID MANUFACTURER
        ---------- ------------
        2143       Lenovo
        2144       Juniper Networks
        2145       Juniper Networks
        2146       Juniper Networks
        2147       Juniper Networks
        2148       Check Point Software Technologies
        2149       Check Point Software Technologies
        2150       Lenovo
        2151       Lenovo
        2152       Lenovo ...
        ......................continues to 50 rows....................

        .EXAMPLE
        Get-EVCatalogAssetData -evOption E_SUPPORT_END_DATE -MaxRows 10

        E_SUPPORT_END_DATE for all records.
        Record 10 of 1805 possible records.
        You may want to extend the -MaxRows parameter to 1805.

        CATALOG_ID E_SUPPORT_END_DATE
        ---------- ------------------
        2143
        2144       2019-11-01
        2145
        2146       2019-05-01
        2147       2019-05-01
        2148       2018-01-01
        2149       2018-01-01
        2150
        2151
        2152

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVCatalogAssetData

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>



    Param(

      [ValidateSet('ALL-Options',
          'ARTICLE_MODEL','ARTICLE_MODEL_URL','AVAILABLE_FIELD_1','AVAILABLE_FIELD_2',
          'AVAILABLE_FIELD_3','WARRANTY NUMBEr','AVAILABLE_FIELD_5','AVAILABLE_FIELD_6',
          'CAN_BE_PURCHASED','CATALOG_GUID','CATALOG_ID','CURRENT_LICENSE_VERSION',
          'DEFAULT_BUY_BACK_VALUE','DEFAULT_BUY_BACK_VALUE_CUR_ID','DEFAULT_CHARGE_BACK',
          'DEFAULT_CHARGE_BACK_CUR_ID','DEFAULT_DISPOSAL_VALUE','DEFAULT_DISPOSAL_VALUE_CUR_ID',
          'DEFAULT_RENEWAL_VALUE','DEFAULT_RENEWAL_VALUE_CUR_ID','DESCRIPTION_EN.HREF','END_DATE',
          'END_OF_NEWS','ESTIMATED_PERCENTAGE_USE','ESTIMATED_POWER_CONSUMPTION_WH',
          'E_DECOMMISSION_DATE','E_DISCOVERY_START_DATE','E_PLANNING_START_DATE','E_PRODUCTION_START_DATE',
          'E_SUPPORT_END_DATE','HREF','IMPACT_ID','INITIAL_STOCK','LAST_INTEGRATION','LAST_UPDATE',
          'LEVEL_VERSION','LICENSE_PRICE_PER_SEAT','LICENSE_PRICE_PER_SEAT_CUR_ID','LICENSE_PROGRAM',
          'MAINTENANCE_DURATION','MANAGED_LICENSE','MANAGER_ID','MANUFACTURER DISCOVERY NAME',
          'MANUFACTURER','MANUFACTURER_ID','MANUFACTURER_REF',
          'MANUFACTURER_WARRANTY_DURATION','MONTHLY_NET_RENTAL','MONTHLY_NET_RENTAL_CUR_ID','NB_INSTALLS',
          'NET_PRICE','NET_PRICE_CUR_ID','PERCENT_MAINTENANCE_COST','QTY_PACKAGED','REF_GLPI','REF_LANDESK',
          'REF_SCCM','SLA_ID','SMBIOS_NAME','START_DATE','TAX_ID','TECHNICAL_VALIDATION_REQUIRED','TITLE_EN',
          'TITLE_FR','TITLE_GE','TITLE_IT','TITLE_L1','TITLE_L2','TITLE_L3','TITLE_L4','TITLE_L5','TITLE_L6',
        'TITLE_PO','TITLE_SP','YEARS_EXPECTED_USAGE')]
      [Parameter(Mandatory=$True,HelpMessage='Please hit tab to see selection options')]
      [string]$evOption,
      [string]$evMaxRows
    )

    $evResponseData = ''

    $evUrl = (('{0}' -f $evCatalogAssetUrl) + ('?fields=href&max_rows={0}' -f $evMaxRows))

    # Make the GET request
    $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing
    $evTotRecCount = $evResponseData.total_record_count

    $evResults = ($evResponseData.records | Select-Object HREF).href

    $evReport = @()
    Foreach ($evResult in $evResults) {
        #Write-Host $evResult -ForegroundColor $evFGColorInfo
        $evOutput = Invoke-RestMethod -Uri "$global:evBaseurl$evResult"  -Method Get -Headers $global:evHeader
        $evReport += $evOutput

    }

    $evResponseData = $evReport
    #$evReport | Select-Object Article_Model, Catalog_ID, HREF, Last_Update, @{name='Manufacturer';e={$_.Manufacturer.Manufacturer}}, @{name='Manufacturer_id';e={$_.Manufacturer.Manufacturer_id}}

    #$evReport

    Switch ($evOption) {
      'ALL-Options'                             { $evResponseData = $evResponseData }
      'ARTICLE_MODEL'														{ $evResponseData = $evResponseData | Select-object Catalog_ID,ARTICLE_MODEL }
      'ARTICLE_MODEL_URL'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,ARTICLE_MODEL_URL }
      'AVAILABLE_FIELD_1'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_1 }
      'AVAILABLE_FIELD_2'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_2 }
      'AVAILABLE_FIELD_3'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_3 }
      'WARRANTY NUMBER'                         { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_4 }
      'AVAILABLE_FIELD_5'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_5 }
      'AVAILABLE_FIELD_6'                       { $evResponseData = $evResponseData | Select-object Catalog_ID,AVAILABLE_FIELD_6 }
      'CAN_BE_PURCHASED'                        { $evResponseData = $evResponseData | Select-object Catalog_ID,CAN_BE_PURCHASED }
      'CATALOG_GUID'                            { $evResponseData = $evResponseData | Select-object Catalog_ID,CATALOG_GUID }
      'CATALOG_ID'                              { $evResponseData = $evResponseData | Select-object Catalog_ID,CATALOG_ID }
      'CURRENT_LICENSE_VERSION'                 { $evResponseData = $evResponseData | Select-object Catalog_ID,CURRENT_LICENSE_VERSION }
      'DEFAULT_BUY_BACK_VALUE'                  { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_BUY_BACK_VALUE }
      'DEFAULT_BUY_BACK_VALUE_CUR_ID'           { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_BUY_BACK_VALUE_CUR_ID }
      'DEFAULT_CHARGE_BACK'                     { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_CHARGE_BACK }
      'DEFAULT_CHARGE_BACK_CUR_ID'              { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_CHARGE_BACK_CUR_ID }
      'DEFAULT_DISPOSAL_VALUE'                  { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_DISPOSAL_VALUE }
      'DEFAULT_DISPOSAL_VALUE_CUR_ID'           { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_DISPOSAL_VALUE_CUR_ID }
      'DEFAULT_RENEWAL_VALUE'                   { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_RENEWAL_VALUE }
      'DEFAULT_RENEWAL_VALUE_CUR_ID'            { $evResponseData = $evResponseData | Select-object Catalog_ID,DEFAULT_RENEWAL_VALUE_CUR_ID }
      'DESCRIPTION_EN.HREF'                     { $evResponseData = $evResponseData | Select-object Catalog_ID,DESCRIPTION_EN.HREF }
      'END_DATE'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,END_DATE }
      'END_OF_NEWS'                             { $evResponseData = $evResponseData | Select-object Catalog_ID,END_OF_NEWS }
      'ESTIMATED_PERCENTAGE_USE'                { $evResponseData = $evResponseData | Select-object Catalog_ID,ESTIMATED_PERCENTAGE_USE }
      'ESTIMATED_POWER_CONSUMPTION_WH'          { $evResponseData = $evResponseData | Select-object Catalog_ID,ESTIMATED_POWER_CONSUMPTION_WH }
      'E_DECOMMISSION_DATE'                     { $evResponseData = $evResponseData | Select-object Catalog_ID,E_DECOMMISSION_DATE }
      'E_DISCOVERY_START_DATE'                  { $evResponseData = $evResponseData | Select-object Catalog_ID,E_DISCOVERY_START_DATE }
      'E_PLANNING_START_DATE'                   { $evResponseData = $evResponseData | Select-object Catalog_ID,E_PLANNING_START_DATE }
      'E_PRODUCTION_START_DATE'                 { $evResponseData = $evResponseData | Select-object Catalog_ID,E_PRODUCTION_START_DATE }
      'E_SUPPORT_END_DATE'                      { $evResponseData = $evResponseData | Select-object Catalog_ID,E_SUPPORT_END_DATE }
      'HREF'                                    { $evResponseData = $evResponseData | Select-object Catalog_ID,HREF }
      'IMPACT_ID'                               { $evResponseData = $evResponseData | Select-object Catalog_ID,IMPACT_ID }
      'INITIAL_STOCK'                           { $evResponseData = $evResponseData | Select-object Catalog_ID,INITIAL_STOCK }
      'LAST_INTEGRATION'                        { $evResponseData = $evResponseData | Select-object Catalog_ID,LAST_INTEGRATION }
      'LAST_UPDATE'                             { $evResponseData = $evResponseData | Select-object Catalog_ID,LAST_UPDATE }
      'LEVEL_VERSION'                           { $evResponseData = $evResponseData | Select-object Catalog_ID,LEVEL_VERSION }
      'LICENSE_PRICE_PER_SEAT'                  { $evResponseData = $evResponseData | Select-object Catalog_ID,LICENSE_PRICE_PER_SEAT }
      'LICENSE_PRICE_PER_SEAT_CUR_ID'           { $evResponseData = $evResponseData | Select-object Catalog_ID,LICENSE_PRICE_PER_SEAT_CUR_ID }
      'LICENSE_PROGRAM'                         { $evResponseData = $evResponseData | Select-object Catalog_ID,LICENSE_PROGRAM }
      'MAINTENANCE_DURATION'                    { $evResponseData = $evResponseData | Select-object Catalog_ID,MAINTENANCE_DURATION }
      'MANAGED_LICENSE'                         { $evResponseData = $evResponseData | Select-object Catalog_ID,MANAGED_LICENSE }
      'MANAGER_ID'                              { $evResponseData = $evResponseData | Select-object Catalog_ID,MANAGER_ID }
      'MANUFACTURER DISCOVERY NAME'             { $evResponseData = $evResponseData | Select-object Catalog_ID,@{n='MANUFACTURER.DISCOVERY_NAME';e={$_.MANUFACTURER.DISCOVERY_NAME }} }
      'MANUFACTURER'                            { $evResponseData = $evResponseData | Select-object Catalog_ID,@{n='MANUFACTURER';e={$_.MANUFACTURER.MANUFACTURER}} }
      'MANUFACTURER_ID'                         { $evResponseData = $evResponseData | Select-object Catalog_ID,MANUFACTURER_ID }
      'MANUFACTURER_REF'                        { $evResponseData = $evResponseData | Select-object Catalog_ID,MANUFACTURER_REF }
      'MANUFACTURER_WARRANTY_DURATION'          { $evResponseData = $evResponseData | Select-object Catalog_ID,MANUFACTURER_WARRANTY_DURATION }
      'MONTHLY_NET_RENTAL'                      { $evResponseData = $evResponseData | Select-object Catalog_ID,MONTHLY_NET_RENTAL }
      'MONTHLY_NET_RENTAL_CUR_ID'               { $evResponseData = $evResponseData | Select-object Catalog_ID,MONTHLY_NET_RENTAL_CUR_ID }
      'NB_INSTALLS'                             { $evResponseData = $evResponseData | Select-object Catalog_ID,NB_INSTALLS }
      'NET_PRICE'                               { $evResponseData = $evResponseData | Select-object Catalog_ID,NET_PRICE }
      'NET_PRICE_CUR_ID'                        { $evResponseData = $evResponseData | Select-object Catalog_ID,NET_PRICE_CUR_ID }
      'PERCENT_MAINTENANCE_COST'                { $evResponseData = $evResponseData | Select-object Catalog_ID,PERCENT_MAINTENANCE_COST }
      'QTY_PACKAGED'                            { $evResponseData = $evResponseData | Select-object Catalog_ID,QTY_PACKAGED }
      'REF_GLPI'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,REF_GLPI }
      'REF_LANDESK'                             { $evResponseData = $evResponseData | Select-object Catalog_ID,REF_LANDESK }
      'REF_SCCM'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,REF_SCCM }
      'SLA_ID'                                  { $evResponseData = $evResponseData | Select-object Catalog_ID,SLA_ID }
      'SMBIOS_NAME'                             { $evResponseData = $evResponseData | Select-object Catalog_ID,SMBIOS_NAME }
      'START_DATE'                              { $evResponseData = $evResponseData | Select-object Catalog_ID,START_DATE }
      'TAX_ID'                                  { $evResponseData = $evResponseData | Select-object Catalog_ID,TAX_ID }
      'TECHNICAL_VALIDATION_REQUIRED'           { $evResponseData = $evResponseData | Select-object Catalog_ID,TECHNICAL_VALIDATION_REQUIRED }
      'TITLE_EN'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_EN }
      'TITLE_FR'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_FR }
      'TITLE_GE'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_GE }
      'TITLE_IT'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_IT }
      'TITLE_L1'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L1 }
      'TITLE_L2'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L2 }
      'TITLE_L3'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L3 }
      'TITLE_L4'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L4 }
      'TITLE_L5'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L5 }
      'TITLE_L6'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_L6 }
      'TITLE_PO'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_PO }
      'TITLE_SP'                                { $evResponseData = $evResponseData | Select-object Catalog_ID,TITLE_SP }
      'YEARS_EXPECTED_USAGE'                    { $evResponseData = $evResponseData | Select-object Catalog_ID,YEARS_EXPECTED_USAGE }

    }# Switch ($evOption)

    Write-Host "$evOption for all records." -ForegroundColor $evFGColorInfo
    #Write-Host "TotalRecordCount $evTotRecCount"
    Write-Host "Record $($evResponseData.count) of $evTotRecCount possible records." -ForegroundColor $evFGColorNum
    Write-Host "You may want to extend the -MaxRows parameter to $evTotRecCount."  -ForegroundColor $evFGColorNum
    return $evResponseData

  }# Function Get-EVCatalogAssetData

  Function Get-EVAssetsAllNoFilter([string]$evMaxRows)  {
    <#
        .SYNOPSIS
        "Get-EVAssetsAllNoFilter" function to retreive configuration item records from EasyVista.

        .DESCRIPTION
        Returns the network device name, asset id, and a few other parameters for EasyVista configuration items.

        .PARAMETER MaxRows
        Describe parameter -MaxRows.

        .EXAMPLE
        Get-EVAssetsAllNoFilter -MaxRows <Value>

        .EXAMPLE
        Get-EVAssetsAllNoFilter -maxrows 200 | Select-Object Network_IDentifier, CI_Version | Where-Object {$_.Ci_version -ge 8.6}

        Gather Network CI versions.

        NETWORK_IDENTIFIER CI_VERSION
        ------------------ ----------
        boifw1             R77.10
        boifw2             R77.10
        STL-AP49           9.0.4.6.0_021115
        TAC5520            v6.3.2.011
        VAN5520 (1)        v6.3.2.011
        ITOSH              8.6.0
        TAC-AP01 (WLA65)   9.0.4.6.0_021115
        PHX-AP62           9.0.4.6.0_021115
        PHX-AP61           9.0.4.6.0_021115
        STL-AP45           9.0.4.6.0_021115
        STL-AP46           9.0.4.6.0_021115
        CIN-AP03 (WLA82)   9.0.4.6.0_021115
        CIN-AP02 (WLA81)   9.0.4.6.0_021115
        CIN-AP01 (WLA80)   9.0.4.6.0_021115
        CINSH              8.6.0
        KNX-AP01 (WLA85)   9.0.4.6.0_021115
        CINFW2             R77.10
        CINFW1             R77.10
        HAMSH              8.6.0

        .EXAMPLE
        Get-EVAssetsAllNoFilter -maxrows 200 | Select-Object Network_IDentifier, Asset_tag, asset_id
        Retrieves network device name, asset tag, and asset id for 200 records.

        .EXAMPLE
        Get-EVAssetsAllNoFilter -maxrows 2000 | Select-Object Network_IDentifier, Asset_tag, asset_id | Where-Object {$_.Network_Identifier -like 'BOI-DMD*'}
        Retrieves network name, asset tag, and asset id for device names starting with boi-dmd.

        .EXAMPLE
        Get-EVAssetsAllNoFilter -maxrows 2000 | Select-Object Network_IDentifier, Asset_tag, asset_id | Where-Object {$_.Asset_tag -like "*-"}
        Retrieves assets with no Asset Tags.


        .NOTES
        Additionally, you can output the data to any format.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVAssetsAllNoFilter

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>


     $evUrl = ('{0}' -f $evConfigItemstUrl) + '?' + ('max_rows={0}' -f $evMaxRows)

    # Make the GET request
    Try {
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader  #-UseBasicParsing

      If (!$evResponseData) {
        $evResponseData = 'No notes present.'
      } Else {
        return $evResponseData.records
      }
    }

    Catch   {
      Write-Warning 'Did not find any records.'
    }

  }# Function Get-EVAssets

  Function Get-EVAssetComment([string]$evAssetID)  {
    <#
        .SYNOPSIS
        "Get-EVAssetComment"

        .DESCRIPTION
        Retrieves asset comments for a given asset id.

        .PARAMETER AssetID
        Asset ID.

        .EXAMPLE
        Get-EVAssetComment -AssetID <Value>

        .EXAMPLE
        Get-EVAssetComment -AssetID 5974
        xxxx / R9W398C / ThinkPad X230

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Asset ID.

        .OUTPUTS
        Asset Comments.
    #>



    $evUrl = "$evConfigItemstUrl/$evAssetID/comment_asset"

    Try {
      # Make the GET request
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader -ErrorAction SilentlyContinue -UseBasicParsing

      If ($evResponseData.comment_asset -eq '') {
        $evResponseData = 'Not present.'
        return $evResponseData
      } Else {
        return $evResponseData.comment_asset
      }
    }

    Catch   {
      Write-Warning "Did not find a record mathing asset id: $evAssetID"
    }

  }# Function Get-EVCommentAsset

  Function Set-EVAssetComment([string]$evAssetID, [string]$evNewComment)  {
    <#
        .SYNOPSIS
        "Set-EVAssetComment"

        .DESCRIPTION
        Set the comments in an asset defined by the asset id.

        .PARAMETER AssetID
        Enter the Asset ID

        .PARAMETER NewComment
        Adds new comments to the asset.

        .EXAMPLE
        Set-EVAssetComment -AssetID Value -NewComment <Value>

        .EXAMPLE
        Set-EVAssetComment -AssetID 5974 -NewComment 'Changed via script.'

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Asset ID

        .OUTPUTS
        New comments added.
    #>


      $evJson = @'
  {
  }
'@

    $evJson = $evJson | Add-Member -MemberType NoteProperty -name 'COMMENT_ASSET' -value "$evNewComment"
    $evMember += "COMMENT_ASSET: $evNewComment"


    # Start with an empty Json file.
    $evJson | Set-Content $global:evJsonAssetFile

    # Convert Json file to a standard key-value pair.
    $evJson = Get-Content $global:evJsonAssetFile | Out-String | ConvertFrom-Json


    $evJson | ConvertTo-Json | Set-Content $global:evJsonAssetFile

    $evJson = Get-Content $global:evJsonAssetFile

    Remove-Item $global:evJsonAssetFile -Force -Confirm:$false -ErrorAction SilentlyContinue

    $evUrl = "$evConfigItemstUrl/$evAssetID/comment_asset"

    Try {
      # Make the GET request
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Put -Headers $global:evHeader -Body $evJson  -ContentType 'application/json' -ErrorAction SilentlyContinue -UseBasicParsing

      If ($evResponseData.comment_asset -eq '') {
        $evResponseData = 'Not present.'
        return $evResponseData
      } Else {
        return $evResponseData.comment_asset
      }
    }

    Catch   {
      Write-Warning "Did not find a record mathing asset id: $evAssetID"
    }

  }# Function Set-EVCommentAsset

  Function Get-EVConfigurationItemReleaseManagingGroupID([string]$evAssetID)  {
    <#
        .SYNOPSIS
        "Get-EVConfigurationItemReleaseManagingGroupID" function

        .DESCRIPTION
        Retrieves the Release Managing group for a configuration item.

        .PARAMETER AssetID
        Enter the AssetID.

        .EXAMPLE
        Get-EVConfigurationItemReleaseManagingGroupID -AssetID <Value>

        .EXAMPLE
        Get-EVConfigurationItemReleaseManagingGroupID -AssetID 91672

        Returns.
        3

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVConfigurationItemReleaseManagingGroup

        .INPUTS
        Asset ID.

        .OUTPUTS
        Release Managing Group ID.
    #>



    $evUrl = "$evConfigItemstUrl/$evAssetID"

    Try {

      # Make the GET request
      $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

      If ($evResponseData.E_RLS_MANAGING_GROUP -eq '') {
        $evResponseData = 'Not present.'

      } Else {
        # Write-Host "Release Managing Group Id: $evResponseData.E_RLS_MANAGING_GROUP"
        return $evResponseData.E_RLS_MANAGING_GROUP
      }

    } Catch {

      Write-Warning "Did not find a record mathing asset id: $evAssetID.  Likely a CI doesn't exist."

    }



  }# Function Get-EVReleaseManagingGroup

  Function Get-EVManufactuerCatalogId {
    <#
        .SYNOPSIS
        "Get-EVManufactuerCatalogId"

        .DESCRIPTION
        Function to return the CatalogID of any model from a given manufacturer.

        .PARAMETER Manufacturer
        Enter a manufacturer

        .PARAMETER Model
        A model to search from.

        .PARAMETER Maxrows
        Set the maximum rows to return in the search.

        .PARAMETER Help
        Display help parameter.

        .PARAMETER SaveReport
        Option to save the report to an Excel file.

        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer Value -Model Value -Maxrows Value -Help -SaveReport

        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer LENOVO -Model *x3650* -Maxrows 100

        Increased the -Maxrows parameter to 138 to cover all possible matches.  You've elected to only display 100 maxium rows.
        Model: *x3650* Catalog ID is:

        ARTICLE_MODEL               CATALOG_ID
        -------------               ----------
        System x3650 M3 -[7945AC1]- 3431
        System x3650 M2 -[7947K9G]- 3466


        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer IBM -Model *x3650* -Maxrows 100

        Model: *x3650* Catalog ID is:

        ARTICLE_MODEL                CATALOG_ID
        -------------                ----------
        System x3650 M3 -[7944AC1]-  3489
        IBM System x3650 -[7979B9U]- 3490

        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer Dell -Model 'PowerEdge R710' -Maxrows 10

        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer Dell -Model 'PowerEdge R710' -Maxrows 102

        Get-EVManufactuerCatalogId -Manufacturer APC -Maxrows 100
        (Returns a list of APC models.)

        .EXAMPLE
        Get-EVManufactuerCatalogId -Manufacturer APC -Model SRT6KRMXLT -Maxrows 100
        (Returns the Catalog Id).


        .NOTES
        Can wildcard the model you are searching for.

        .LINK
        None

        .INPUTS
        Manufacturer, Model, and maximum rows.
        Savereport switch

        .OUTPUTS
        Article Model and Catalog ID.
        Saved report in Excel if using the Savereport parameter.
    #>


    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
      HelpMessage='Enter the Manufacturer information')]
      [ValidateSet('APC','Avaya','IBM','Cisco','Check Point Software Technologies','Dell','Juniper','Kemp','LENOVO','Meraki','NetApp','Open','Riverbed','VMWare')]
      [string]$evManufacturer,
      [Parameter(Mandatory=$False)]
      [string]$evModel,
      [Parameter(Mandatory=$true)][int]$evMaxRows,
      [switch]$evHelp,
      [switch]$evSaveReport

    )

    $Error.clear()

    $evBasePath = '\\boifs1\ITxchange\Automation\EV_CatalogItems'
    $evXlsxfile = "$evBasePath\$evManufacturer\$evManufacturer-Catalog-$global:evDateStamp.xlsx"


    If ( ! (test-path "$evBasePath\$evManufacturer" -PathType Container)) {

      New-Item  -ItemType 'directory' -Path "$evBasePath\$evManufacturer"
    }

    $evUrl = ("$evCatalogAssetUrl" +'?search=manufacturer.manufacturer~' + ('"{0}*"' -f ($evManufacturer)) + ('&fields=Catalog_id,manufacturer.manufacturer,Article_model&max_rows={0}' -f $evMaxRows))
    #$evUrl = ("$evCatalogAssetUrl" +'?search=manufacturer.manufacturer~' + "$($evManufacturer)*" + "&fields=Catalog_id,Article_model&max_rows=$evMaxRows")


    # Capture APC model info.
    $evModels = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue

    If ($([int]$evModels.total_record_count) -gt [int]$evMaxRows) {
      Write-Host "Increased the -Maxrows parameter to $($evModels.total_record_count) to cover all possible matches.  You've elected to only display $evMaxRows maxium rows."
      $evMaxRows = $($evModels.total_record_count)
      $evUrl = ("$evCatalogAssetUrl" +'?search=manufacturer.manufacturer~' + ('"{0}*"' -f ($evManufacturer)) + ('&fields=Catalog_id,manufacturer.manufacturer,Article_model&max_rows={0}' -f $evMaxRows))
      $evModels = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader -ErrorAction SilentlyContinue
    }


    If ($evSaveReport){

      $evModels.records | Export-Excel -Path $evXlsxfile -WorkSheetname "$evManufacturer Models" -AutoSize

      If ( ! (test-path "$evBasePath\$evManufacturer" -PathType Container)) {
        $null = New-Item  -ItemType 'directory' -Path "$evBasePath\$evManufacturer"
      }
    }# If $evSaveReport



    If (!($evModel) ) {
      Write-Host "Manufacturer: $evManufacturer"  -ForegroundColor $evFGColorInfo
      Write-Host "Record Count: $($evModels.records.Count)"  -ForegroundColor $evFGColorNum
      Write-Host "Choose from these models: Example: get-catalogid -Manufacturer $evManufacturer -Model $(($evModels.records[-1]).ARTICLE_MODEL)" -ForegroundColor Cyan
      (($evModels.records | Select-Object ARTICLE_MODEL).Article_Model)
    } Else {

      # Check for how many records are returned from the search. Looking for one record to return the CatalogID.
      If ( "$($evModels.records.Count)" -ge 1) {
         $evCatalogID =  ($evModels.records | Select-Object ARTICLE_MODEL, CATALOG_ID | Where-Object {$_.Article_Model -like $evModel})

         If ($evCatalogID -is[array]) {
            $evCatalogID = $evCatalogID
         } Else {
           $evCatalogID =  $evCatalogID.Catalog_ID
           #($evModels.records | Select-Object ARTICLE_MODEL, CATALOG_ID | Where-Object {$_.Article_Model -like $evModel}).Catalog_ID
         }
        #$evCatalogID =  ($evModels.records | Select-Object ARTICLE_MODEL, CATALOG_ID | Where-Object {$_.Article_Model -like $evModel}).Catalog_ID
        #$evCatalogID -is[array]
      }
      <#
          Elseif ("$($evModels.records.Count)" -gt 1) {
          $evCatalogID =  ($evModels.records | Select-Object ARTICLE_MODEL, CATALOG_ID | Where-Object {$_.Article_Model -like $evModel})
          $evCatalogID -is[array]
          }
      #>
      If ($evCatalogID) {
        Write-Host "Model: $evModel Catalog ID is: $evCatalogID"  -ForegroundColor $evFGColorInfo
      } Else {
        Write-Host "It appears that the model you've entered is not in the EasyVista database." -ForegroundColor $evFGColorVerbose
        If ($($evModels).total_record_count -gt $evMaxRows) {
          Write-Host "The maxium value for the -maxrows parameter is $($evModels.total_record_count). You've entered $evMaxRows." $evFGColorNum
        }

        break
      }

    }

    If ($evHelp) {
      $evHlpMsg = @"

        Generally speaking you pass in the manufacturer and model as a parameter.  If you don't know the model, try calling the
        function without the model specified and it will list available models:

          Example:  Get-CatalogId -Manufacturer APC
"@

      $evHlpOutput = @'

          Choose from these models from EasyVista:

          Example: get-catalogid -Manufacturer apc -Model SRT5KRMTF

          Manufacturer: APC
          Record Count: 24

          RT6000RMXLT3U
          SmartUPS x3000
          SmartUPS x2200
          NetShelter SX
          NetShelter AR3814
          SmartUPS RT XL
          Step Down Transformer RM 2U
          AP7541
          AP9563
          NetShelter AR3100TAA
          Symmetra
          SmartUPS 5000VA
          SRT-192RM-BP
          SRT-5KRM-TF
          AP8941
          SMX3000RMLV2UNC
          SRT5KRMXLT
          SRT5KXLT
          SRT6KRMXLT
          SRT6KXLT
          SRT2K
          SRT3K
          SRT5K
          SRT5KRMTF

'@
      Write-Host $evHlpMsg  -ForegroundColor $evFGColorVerbose
      Write-Host $evHlpOutput  -ForegroundColor $evFGColorInfo
    }

    return $evCatalogID


  }# Function Get-CatalogId

  Function Get-EVAssetDetailByAssetName {
    <#
        .SYNOPSIS
        "Get-EVAssetDetailByAssetName" function.

        .DESCRIPTION
        Add a more complete description of what the function does.

        .PARAMETER hostname
        Describe parameter -evHostname.

        .PARAMETER Option
        Describe parameter -evOption.

        .PARAMETER MaxRows
        Describe parameter -MaxRows.

        .PARAMETER SaveReport
        Describe parameter -SaveReport.

        .EXAMPLE
        Get-EVAssetDetailByAssetName -evhostname Value -evOption Value -MaxRows Value -SaveReport

        .EXAMPLE
        Get-EVAssetDetailByAssetName -evhostname CDC-CTX-DC01 -evOption SERIAL_NUMBER -MaxRows 1

        .EXAMPLE
        Get-EVAssetDetailByAssetName -evhostname itrockss -evOption ASSET_COMMENTS -MaxRows 1

        .EXAMPLE
        Get-EVAssetDetailByAssetName -evhostname ITROCKSS -evOption ALL-Data | Select Network_Identifier, Last_update, Installation_Date,Serial_Number

        .NOTES
        None

        .LINK
        None

        .INPUTS
        Hostname and options

        .OUTPUTS
        Selected items from asset details..
    #>

    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
        HelpMessage='Enter a hostname')]
        #[ValidatePattern('^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$')]
        [string]$evHostname,

       [Parameter(Mandatory=$true,
        HelpMessage='Select an option.')]
        [ValidateSet('ALL-Data',
          'ACQUISITION_TYPE_ID','ASSET_GUID','ASSET_ID','ASSET_LABEL','ASSET_TAG','AUTOMATIC_RENEWAL',
          'AVAILABILITY_SLA_ID','AVAILABLE_FIELD_1','AVAILABLE_FIELD_2','AVAILABLE_FIELD_3',
          'AVAILABLE_FIELD_4','AVAILABLE_FIELD_5','AVAILABLE_FIELD_6','BEFORE_LOAN_DEPARTMENT_ID',
          'BEFORE_LOAN_DEPARTMENT_PATH','BEFORE_LOAN_EMPLOYEE_ID','BEFORE_LOAN_LOCATION_ID',
          'BEFORE_LOAN_LOCATION_PATH','BILLING_PERIODICITY_IN_MONTH','BUDGET_ID','BUY_BACK_VALUE',
          'BUY_BACK_VALUE_CUR_ID','CATALOG_ASSET.ARTICLE_MODEL','CATALOG_ASSET.CATALOG_ID',
          'CATALOG_ASSET.NET_PRICE','CATALOG_ASSET.SMBIOS_NAME','CATALOG_ASSET.TITLE_EN','CATALOG_ID',
          'CHARGE_BACK','CHARGE_BACK_CUR_ID','CI_BACKUP_BY_DEFAULT','CI_STATUS_ID','CI_VERSION',
          'CM_DEFAULT_CHANGE_ID','CM_DEFAULT_CHANGE_PATH','ASSET_COMMENTS','COMMENT_ASSET.HREF',
          'CONFIGURATION_ID','CONTRACT_TYPE_ID','CRITICAL_LEVEL_ID','DELIVERY_DATE','DELIVERY_NUMBER',
          'DEPARTMENT.DEPARTMENT_CODE','DEPARTMENT.DEPARTMENT_EN','DEPARTMENT.DEPARTMENT_ID',
          'DEPARTMENT.DEPARTMENT_LABEL','DEPARTMENT.DEPARTMENT_PATH','DEPARTMENT_ID','DEPARTMENT_PATH',
          'DEPRECIATION_RULE_ID','D_HARDWARE_GUID','EMPLOYEE.BEGIN_OF_CONTRACT','EMPLOYEE.CELLULAR_NUMBER',
          'EMPLOYEE.DEPARTMENT_PATH','EMPLOYEE.EMPLOYEE_ID','EMPLOYEE.E_MAIL','EMPLOYEE.LAST_NAME',
          'EMPLOYEE.LOCATION_PATH','EMPLOYEE.PHONE_NUMBER','EMPLOYEE_ID','END_OF_WARANTY','ENTRY_DATE',
          'ESTIMATED_PERCENTAGE_USE','EXPECTED_END_LEND_DATE','EXPECTED_RETURN_DATE','E_BW_BEFORE_OVERAGE',
          'E_COLOR_BEFORE_OVERAGE','E_CONTRACT_RENEWED','E_CONTRACT_STATUS','E_COST_BW_COVERAGE',
          'E_COST_BW_OVERAGE','E_COST_COLOR_COVERAGE','E_COST_COLOR_OVERAGE','E_COST_PER_BW_CLICK',
          'E_COST_PER_CLICK','E_COST_PER_COLOR_CLICK','E_FAX_NUMBER','E_IP_ADDRESS','E_MAC_ADDRESS',
          'E_NOTES.HREF','E_NOTIFICATION_DUR','E_OPERATING_SYSTEM','E_OVERAGE_COST','E_PAGE_PER_MINUTE',
          'E_PO_NUMBER','E_PRINT_SERVER','E_RELATED_TICKET_NUMBER','E_RLS_MANAGING_GROUP','E_RLS_OWNING_GROUP',
          'E_RLS_SUPPORTING_GROUP','E_RLS_USING_GROUP','E_SUPPLIER_EQUIP_NUM','E_TERM_LANG','E_VMO_CONTACT',
          'E_WIDE_BASE_CHARGE','E_WIDE_SQUARE_FEET','E_primary_employee','FALLEN_TERM','FIXED_ASSET_NUMBER',
          'HREF','INITIAL_START','INSTALLATION_DATE','INTERNAL_DELIVERY_DATE','INTERNAL_DISPO','INVENTORY_ID',
          'INVOICE_NUMBER','IS_CI','IS_DML','IS_LOCKED','IS_SERVICE','LAST_AUTOMATIC_DISCOVERY','LAST_INTEGRATION',
          'LAST_PAYMENT','LAST_PAYMENT_CUR_ID','LAST_PHYSICAL_INVENTORY','LAST_UPDATE','LICENSE_VERSION',
          'LOCATION.CITY','LOCATION.LOCATION_CODE','LOCATION.LOCATION_EN','LOCATION.LOCATION_ID',
          'LOCATION.LOCATION_PATH','LOCATION_ID','LOCATION_PATH','LOCATION_TO_CHECK_REQUEST_ID','MAINTENANCE_COST',
          'MAINTENANCE_COST_CUR_ID','MAIN_USAGE_ID','MAX_INSTALLS','MONTHLY_FIXED_COST','MONTHLY_FIXED_COST_CUR_ID',
          'MONTHLY_NET_RENTAL','MONTHLY_NET_RENTAL_CUR_ID','MONTH_DURATION','NETWORK_IDENTIFIER','NEXT_CI_VERSION',
          'NEXT_DEPARTMENT_ID','NEXT_DEPARTMENT_PATH','NEXT_MAINTENANCE_DATE','NEXT_STATUS_ID',
          'NEXT_USER_APPLICATION_DATE','NEXT_USER_ID','NOTICE','ORDER_DETAILS_ID','ORDER_NUMBER',
          'OWNERSHIP_TO_CHECK_REQUEST_ID','PACKAGE_PATH','PIPELINE_STATUS_ID','POWER_CONSUMPTION_WH',
          'PROCESSOR_COUNT','PROCESSOR_SOCKET_COUNT','PROJECT_ID','PROVIDER_ID','PROVIDER_PATH','PURCHASE_DATE',
          'PURCHASE_PRICE','PURCHASE_PRICE_CUR_ID','PURCHASE_RATE_ID','RECYCLED_DATE','RECYCLING_PROVIDER_ID',
          'RECYCLING_PROVIDER_PATH','REFORM_NUMBER','REMOVED_DATE','RENEWAL_DECISION_ID','RENEWAL_VALUE',
          'RENEWAL_VALUE_CUR_ID','REPAIRED_BY_ID','REPAIRED_BY_PATH','REQUEST_ID','RESALES_VALUE','SCHEDULED_END',
          'SD_CATALOG_ID','SD_CATALOG_PATH','SD_DEFAULT_INCIDENT_ID','SD_DEFAULT_INCIDENT_PATH','SD_DEFAULT_REQUEST_ID',
          'SD_DEFAULT_REQUEST_PATH','SERIAL_NUMBER','SERVER_TYPE_ID','SLA_ID','STATUS_ID','SUPPLIER_ID','SUPPLIER_PATH',
          'TERM','UPDATED_BY_DISCOVERY','UPDATE_COVERAGE_TERM','WARANTY_TYPE_ID','XPOS','YPOS','ZPOS'
      )]
        [string]$evOption,
        [string]$evMaxRows = 1,

        [switch]$evSaveReport
    )

    Begin {

      # Setup Basic Authentication to EasyVista.
      #$evUrl = ('{0}/{1}/assets?max_rows={3}&search=NETWORK_IDENTIFIER~{4}' -f $global:evBaseurl, $apipath, $evMaxRows, $evHostname)

      $evUrl = (('{0}?max_rows={1}&search=NETWORK_IDENTIFIER~"{2}"' -f $evAssetsUrl, $evMaxRows, $evHostname))

      $evJsonfile = ('{0}\{1}_{2}.json' -f $evTempPath, $evHostname, $global:evDateStamp)

    }#Begin


    Process {

      Try {
        $evResponseData = Invoke-RestMethod -Method Get -Uri $evUrl -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue #-OutFile $evJsonfile


        If ($evResponseData.record_count -eq '1') {

          #$evHref = $($evResponseData.records.href)
          $evHref = $($evResponseData.records.href) -replace ('http:','https:')
          $evResponseData = Invoke-RestMethod -Method Get -Uri ($evHref) -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue


        } Elseif ($evResponseData.record_count -gt '1') {

            Write-Host 'Could not find a matching system name.' -ForegroundColor $evFGColorVerbose
            Write-Host "Please check for dulicate records.  Your request returned $($evResponseData.record_count) records." -ForegroundColor $evFGColorBad
            $evResponseData = 'Multiple-records-found'

        } Elseif ($evResponseData.record_count -eq 0) {
            Write-Host "Could not find a matching system name ($evHostname) in EasyVista." -ForegroundColor $evFGColorBad
            $evResponseData = '---'
        }


      } Catch {
        Write-Host "Could not find a matching system name ($evHostname) in EasyVista." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }

      If ($evSaveReport) {
        $evResponseData | ConvertTo-Json | Out-File $evJsonfile
        Write-Host "Report saved to $evJsonfile." -ForegroundColor $evFGColorInfo
      }

      Switch ($evOption) {
        'ALL-Data'                        { $evResponseData = $evResponseData }
        'ACQUISITION_TYPE_ID'             { $evResponseData=$evResponseData.ACQUISITION_TYPE_ID }
        'ASSET_GUID'                      { $evResponseData=$evResponseData.ASSET_GUID }
        'ASSET_ID'                        { $evResponseData=$evResponseData.ASSET_ID }
        'ASSET_LABEL'                     { $evResponseData=$evResponseData.ASSET_LABEL }
        'ASSET_TAG'                       { $evResponseData=$evResponseData.ASSET_TAG }
        'AUTOMATIC_RENEWAL'               { $evResponseData=$evResponseData.AUTOMATIC_RENEWAL }
        'AVAILABILITY_SLA_ID'             { $evResponseData=$evResponseData.AVAILABILITY_SLA_ID }
        'AVAILABLE_FIELD_1'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_1 }
        'AVAILABLE_FIELD_2'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_2 }
        'AVAILABLE_FIELD_3'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_3 }
        'AVAILABLE_FIELD_4'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_4 }
        'AVAILABLE_FIELD_5'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_5 }
        'AVAILABLE_FIELD_6'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_6 }
        'BEFORE_LOAN_DEPARTMENT_ID'       { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_ID }
        'BEFORE_LOAN_DEPARTMENT_PATH'     { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_PATH }
        'BEFORE_LOAN_EMPLOYEE_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_EMPLOYEE_ID }
        'BEFORE_LOAN_LOCATION_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_ID }
        'BEFORE_LOAN_LOCATION_PATH'       { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_PATH }
        'BILLING_PERIODICITY_IN_MONTH'    { $evResponseData=$evResponseData.BILLING_PERIODICITY_IN_MONTH }
        'BUDGET_ID'                       { $evResponseData=$evResponseData.BUDGET_ID }
        'BUY_BACK_VALUE'                  { $evResponseData=$evResponseData.BUY_BACK_VALUE }
        'BUY_BACK_VALUE_CUR_ID'           { $evResponseData=$evResponseData.BUY_BACK_VALUE_CUR_ID }
        'CATALOG_ASSET.ARTICLE_MODEL'     { $evResponseData=$evResponseData.CATALOG_ASSET.ARTICLE_MODEL }
        'CATALOG_ASSET.CATALOG_ID'        { $evResponseData=$evResponseData.CATALOG_ASSET.CATALOG_ID }
        'CATALOG_ASSET.NET_PRICE'         { $evResponseData=$evResponseData.CATALOG_ASSET.NET_PRICE }
        'CATALOG_ASSET.SMBIOS_NAME'       { $evResponseData=$evResponseData.CATALOG_ASSET.SMBIOS_NAME }
        'CATALOG_ASSET.TITLE_EN'          { $evResponseData=$evResponseData.CATALOG_ASSET.TITLE_EN }
        'CATALOG_ID'                      { $evResponseData=$evResponseData.CATALOG_ID }
        'CHARGE_BACK'                     { $evResponseData=$evResponseData.CHARGE_BACK }
        'CHARGE_BACK_CUR_ID'              { $evResponseData=$evResponseData.CHARGE_BACK_CUR_ID }
        'CI_BACKUP_BY_DEFAULT'            { $evResponseData=$evResponseData.CI_BACKUP_BY_DEFAULT }
        'CI_STATUS_ID'                    { $evResponseData=$evResponseData.CI_STATUS_ID }
        'CI_VERSION'                      { $evResponseData=$evResponseData.CI_VERSION }
        'CM_DEFAULT_CHANGE_ID'            { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_ID }
        'CM_DEFAULT_CHANGE_PATH'          { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_PATH }
        'ASSET_COMMENTS'                  { $evResponseData = (Get-EVAssetComment -evAssetID ($evResponseData.ASSET_ID)) }
        'COMMENT_ASSET.HREF'              { $evResponseData = $evResponseData.COMMENT_ASSET.HREF }
        'CONFIGURATION_ID'                { $evResponseData=$evResponseData.CONFIGURATION_ID }
        'CONTRACT_TYPE_ID'                { $evResponseData=$evResponseData.CONTRACT_TYPE_ID }
        'CRITICAL_LEVEL_ID'               { $evResponseData=$evResponseData.CRITICAL_LEVEL_ID }
        'DELIVERY_DATE'                   { $evResponseData=$evResponseData.DELIVERY_DATE }
        'DELIVERY_NUMBER'                 { $evResponseData=$evResponseData.DELIVERY_NUMBER }
        'DEPARTMENT.DEPARTMENT_CODE'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_CODE }
        'DEPARTMENT.DEPARTMENT_EN'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_EN }
        'DEPARTMENT.DEPARTMENT_ID'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_ID }
        'DEPARTMENT.DEPARTMENT_LABEL'     { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_LABEL }
        'DEPARTMENT.DEPARTMENT_PATH'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_PATH }
        'DEPARTMENT_ID'                   { $evResponseData=$evResponseData.DEPARTMENT_ID }
        'DEPARTMENT_PATH'                 { $evResponseData=$evResponseData.DEPARTMENT_PATH }
        'DEPRECIATION_RULE_ID'            { $evResponseData=$evResponseData.DEPRECIATION_RULE_ID }
        'D_HARDWARE_GUID'                 { $evResponseData=$evResponseData.D_HARDWARE_GUID }
        'EMPLOYEE.BEGIN_OF_CONTRACT'      { $evResponseData=$evResponseData.EMPLOYEE.BEGIN_OF_CONTRACT }
        'EMPLOYEE.CELLULAR_NUMBER'        { $evResponseData=$evResponseData.EMPLOYEE.CELLULAR_NUMBER }
        'EMPLOYEE.DEPARTMENT_PATH'        { $evResponseData=$evResponseData.EMPLOYEE.DEPARTMENT_PATH }
        'EMPLOYEE.EMPLOYEE_ID'            { $evResponseData=$evResponseData.EMPLOYEE.EMPLOYEE_ID }
        'EMPLOYEE.E_MAIL'                 { $evResponseData=$evResponseData.EMPLOYEE.E_MAIL }
        'EMPLOYEE.LAST_NAME'              { $evResponseData=$evResponseData.EMPLOYEE.LAST_NAME }
        'EMPLOYEE.LOCATION_PATH'          { $evResponseData=$evResponseData.EMPLOYEE.LOCATION_PATH }
        'EMPLOYEE.PHONE_NUMBER'           { $evResponseData=$evResponseData.EMPLOYEE.PHONE_NUMBER }
        'EMPLOYEE_ID'                     { $evResponseData=$evResponseData.EMPLOYEE_ID }
        'END_OF_WARANTY'                  { $evResponseData=$evResponseData.END_OF_WARANTY }
        'ENTRY_DATE'                      { $evResponseData=$evResponseData.ENTRY_DATE }
        'ESTIMATED_PERCENTAGE_USE'        { $evResponseData=$evResponseData.ESTIMATED_PERCENTAGE_USE }
        'EXPECTED_END_LEND_DATE'          { $evResponseData=$evResponseData.EXPECTED_END_LEND_DATE }
        'EXPECTED_RETURN_DATE'            { $evResponseData=$evResponseData.EXPECTED_RETURN_DATE }
        'E_BW_BEFORE_OVERAGE'             { $evResponseData=$evResponseData.E_BW_BEFORE_OVERAGE }
        'E_COLOR_BEFORE_OVERAGE'          { $evResponseData=$evResponseData.E_COLOR_BEFORE_OVERAGE }
        'E_CONTRACT_RENEWED'              { $evResponseData=$evResponseData.E_CONTRACT_RENEWED }
        'E_CONTRACT_STATUS'               { $evResponseData=$evResponseData.E_CONTRACT_STATUS }
        'E_COST_BW_COVERAGE'              { $evResponseData=$evResponseData.E_COST_BW_COVERAGE }
        'E_COST_BW_OVERAGE'               { $evResponseData=$evResponseData.E_COST_BW_OVERAGE }
        'E_COST_COLOR_COVERAGE'           { $evResponseData=$evResponseData.E_COST_COLOR_COVERAGE }
        'E_COST_COLOR_OVERAGE'            { $evResponseData=$evResponseData.E_COST_COLOR_OVERAGE }
        'E_COST_PER_BW_CLICK'             { $evResponseData=$evResponseData.E_COST_PER_BW_CLICK }
        'E_COST_PER_CLICK'                { $evResponseData=$evResponseData.E_COST_PER_CLICK }
        'E_COST_PER_COLOR_CLICK'          { $evResponseData=$evResponseData.E_COST_PER_COLOR_CLICK }
        'E_FAX_NUMBER'                    { $evResponseData=$evResponseData.E_FAX_NUMBER }
        'E_IP_ADDRESS'                    { $evResponseData=$evResponseData.E_IP_ADDRESS }
        'E_MAC_ADDRESS'                   { $evResponseData=$evResponseData.E_MAC_ADDRESS }
        'E_NOTES.HREF'                    { $evResponseData=$evResponseData.E_NOTES.HREF}
        'E_NOTIFICATION_DUR'              { $evResponseData=$evResponseData.E_NOTIFICATION_DUR }
        'E_OPERATING_SYSTEM'              { $evResponseData=$evResponseData.E_OPERATING_SYSTEM }
        'E_OVERAGE_COST'                  { $evResponseData=$evResponseData.E_OVERAGE_COST }
        'E_PAGE_PER_MINUTE'               { $evResponseData=$evResponseData.E_PAGE_PER_MINUTE }
        'E_PO_NUMBER'                     { $evResponseData=$evResponseData.E_PO_NUMBER }
        'E_PRINT_SERVER'                  { $evResponseData=$evResponseData.E_PRINT_SERVER }
        'E_RELATED_TICKET_NUMBER'         { $evResponseData=$evResponseData.E_RELATED_TICKET_NUMBER }
        'E_RLS_MANAGING_GROUP'            { $evResponseData=$evResponseData.E_RLS_MANAGING_GROUP }
        'E_RLS_OWNING_GROUP'              { $evResponseData=$evResponseData.E_RLS_OWNING_GROUP }
        'E_RLS_SUPPORTING_GROUP'          { $evResponseData=$evResponseData.E_RLS_SUPPORTING_GROUP }
        'E_RLS_USING_GROUP'               { $evResponseData=$evResponseData.E_RLS_USING_GROUP }
        'E_SUPPLIER_EQUIP_NUM'            { $evResponseData=$evResponseData.E_SUPPLIER_EQUIP_NUM }
        'E_TERM_LANG'                     { $evResponseData=$evResponseData.E_TERM_LANG }
        'E_VMO_CONTACT'                   { $evResponseData=$evResponseData.E_VMO_CONTACT }
        'E_WIDE_BASE_CHARGE'              { $evResponseData=$evResponseData.E_WIDE_BASE_CHARGE }
        'E_WIDE_SQUARE_FEET'              { $evResponseData=$evResponseData.E_WIDE_SQUARE_FEET }
        'E_primary_employee'              { $evResponseData=$evResponseData.E_primary_employee }
        'FALLEN_TERM'                     { $evResponseData=$evResponseData.FALLEN_TERM }
        'FIXED_ASSET_NUMBER'              { $evResponseData=$evResponseData.FIXED_ASSET_NUMBER }
        'HREF'                            { $evResponseData=$evResponseData.HREF }
        'INITIAL_START'                   { $evResponseData=$evResponseData.INITIAL_START }
        'INSTALLATION_DATE'               { $evResponseData=$evResponseData.INSTALLATION_DATE }
        'INTERNAL_DELIVERY_DATE'          { $evResponseData=$evResponseData.INTERNAL_DELIVERY_DATE }
        'INTERNAL_DISPO'                  { $evResponseData=$evResponseData.INTERNAL_DISPO }
        'INVENTORY_ID'                    { $evResponseData=$evResponseData.INVENTORY_ID }
        'INVOICE_NUMBER'                  { $evResponseData=$evResponseData.INVOICE_NUMBER }
        'IS_CI'                           { $evResponseData=$evResponseData.IS_CI }
        'IS_DML'                          { $evResponseData=$evResponseData.IS_DML }
        'IS_LOCKED'                       { $evResponseData=$evResponseData.IS_LOCKED }
        'IS_SERVICE'                      { $evResponseData=$evResponseData.IS_SERVICE }
        'LAST_AUTOMATIC_DISCOVERY'        { $evResponseData=$evResponseData.LAST_AUTOMATIC_DISCOVERY }
        'LAST_INTEGRATION'                { $evResponseData=$evResponseData.LAST_INTEGRATION }
        'LAST_PAYMENT'                    { $evResponseData=$evResponseData.LAST_PAYMENT }
        'LAST_PAYMENT_CUR_ID'             { $evResponseData=$evResponseData.LAST_PAYMENT_CUR_ID }
        'LAST_PHYSICAL_INVENTORY'         { $evResponseData=$evResponseData.LAST_PHYSICAL_INVENTORY }
        'LAST_UPDATE'                     { $evResponseData=$evResponseData.LAST_UPDATE }
        'LICENSE_VERSION'                 { $evResponseData=$evResponseData.LICENSE_VERSION }
        'LOCATION.CITY'                   { $evResponseData=$evResponseData.LOCATION.CITY }
        'LOCATION.LOCATION_CODE'          { $evResponseData=$evResponseData.LOCATION.LOCATION_CODE }
        'LOCATION.LOCATION_EN'            { $evResponseData=$evResponseData.LOCATION.LOCATION_EN }
        'LOCATION.LOCATION_ID'            { $evResponseData=$evResponseData.LOCATION.LOCATION_ID }
        'LOCATION.LOCATION_PATH'          { $evResponseData=$evResponseData.LOCATION.LOCATION_PATH }
        'LOCATION_ID'                     { $evResponseData=$evResponseData.LOCATION_ID }
        'LOCATION_PATH'                   { $evResponseData=$evResponseData.LOCATION_PATH }
        'LOCATION_TO_CHECK_REQUEST_ID'    { $evResponseData=$evResponseData.LOCATION_TO_CHECK_REQUEST_ID }
        'MAINTENANCE_COST'                { $evResponseData=$evResponseData.MAINTENANCE_COST }
        'MAINTENANCE_COST_CUR_ID'         { $evResponseData=$evResponseData.MAINTENANCE_COST_CUR_ID }
        'MAIN_USAGE_ID'                   { $evResponseData=$evResponseData.MAIN_USAGE_ID }
        'MAX_INSTALLS'                    { $evResponseData=$evResponseData.MAX_INSTALLS }
        'MONTHLY_FIXED_COST'              { $evResponseData=$evResponseData.MONTHLY_FIXED_COST }
        'MONTHLY_FIXED_COST_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_FIXED_COST_CUR_ID }
        'MONTHLY_NET_RENTAL'              { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL }
        'MONTHLY_NET_RENTAL_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL_CUR_ID }
        'MONTH_DURATION'                  { $evResponseData=$evResponseData.MONTH_DURATION }
        'NETWORK_IDENTIFIER'              { $evResponseData=$evResponseData.NETWORK_IDENTIFIER }
        'NEXT_CI_VERSION'                 { $evResponseData=$evResponseData.NEXT_CI_VERSION }
        'NEXT_DEPARTMENT_ID'              { $evResponseData=$evResponseData.NEXT_DEPARTMENT_ID }
        'NEXT_DEPARTMENT_PATH'            { $evResponseData=$evResponseData.NEXT_DEPARTMENT_PATH }
        'NEXT_MAINTENANCE_DATE'           { $evResponseData=$evResponseData.NEXT_MAINTENANCE_DATE }
        'NEXT_STATUS_ID'                  { $evResponseData=$evResponseData.NEXT_STATUS_ID }
        'NEXT_USER_APPLICATION_DATE'      { $evResponseData=$evResponseData.NEXT_USER_APPLICATION_DATE }
        'NEXT_USER_ID'                    { $evResponseData=$evResponseData.NEXT_USER_ID }
        'NOTICE'                          { $evResponseData=$evResponseData.NOTICE }
        'ORDER_DETAILS_ID'                { $evResponseData=$evResponseData.ORDER_DETAILS_ID }
        'ORDER_NUMBER'                    { $evResponseData=$evResponseData.ORDER_NUMBER }
        'OWNERSHIP_TO_CHECK_REQUEST_ID'   { $evResponseData=$evResponseData.OWNERSHIP_TO_CHECK_REQUEST_ID }
        'PACKAGE_PATH'                    { $evResponseData=$evResponseData.PACKAGE_PATH }
        'PIPELINE_STATUS_ID'              { $evResponseData=$evResponseData.PIPELINE_STATUS_ID }
        'POWER_CONSUMPTION_WH'            { $evResponseData=$evResponseData.POWER_CONSUMPTION_WH }
        'PROCESSOR_COUNT'                 { $evResponseData=$evResponseData.PROCESSOR_COUNT }
        'PROCESSOR_SOCKET_COUNT'          { $evResponseData=$evResponseData.PROCESSOR_SOCKET_COUNT }
        'PROJECT_ID'                      { $evResponseData=$evResponseData.PROJECT_ID }
        'PROVIDER_ID'                     { $evResponseData=$evResponseData.PROVIDER_ID }
        'PROVIDER_PATH'                   { $evResponseData=$evResponseData.PROVIDER_PATH }
        'PURCHASE_DATE'                   { $evResponseData=$evResponseData.PURCHASE_DATE }
        'PURCHASE_PRICE'                  { $evResponseData=$evResponseData.PURCHASE_PRICE }
        'PURCHASE_PRICE_CUR_ID'           { $evResponseData=$evResponseData.PURCHASE_PRICE_CUR_ID }
        'PURCHASE_RATE_ID'                { $evResponseData=$evResponseData.PURCHASE_RATE_ID }
        'RECYCLED_DATE'                   { $evResponseData=$evResponseData.RECYCLED_DATE }
        'RECYCLING_PROVIDER_ID'           { $evResponseData=$evResponseData.RECYCLING_PROVIDER_ID }
        'RECYCLING_PROVIDER_PATH'         { $evResponseData=$evResponseData.RECYCLING_PROVIDER_PATH }
        'REFORM_NUMBER'                   { $evResponseData=$evResponseData.REFORM_NUMBER }
        'REMOVED_DATE'                    { $evResponseData=$evResponseData.REMOVED_DATE }
        'RENEWAL_DECISION_ID'             { $evResponseData=$evResponseData.RENEWAL_DECISION_ID }
        'RENEWAL_VALUE'                   { $evResponseData=$evResponseData.RENEWAL_VALUE }
        'RENEWAL_VALUE_CUR_ID'            { $evResponseData=$evResponseData.RENEWAL_VALUE_CUR_ID }
        'REPAIRED_BY_ID'                  { $evResponseData=$evResponseData.REPAIRED_BY_ID }
        'REPAIRED_BY_PATH'                { $evResponseData=$evResponseData.REPAIRED_BY_PATH }
        'REQUEST_ID'                      { $evResponseData=$evResponseData.REQUEST_ID }
        'RESALES_VALUE'                   { $evResponseData=$evResponseData.RESALES_VALUE }
        'SCHEDULED_END'                   { $evResponseData=$evResponseData.SCHEDULED_END }
        'SD_CATALOG_ID'                   { $evResponseData=$evResponseData.SD_CATALOG_ID }
        'SD_CATALOG_PATH'                 { $evResponseData=$evResponseData.SD_CATALOG_PATH }
        'SD_DEFAULT_INCIDENT_ID'          { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_ID }
        'SD_DEFAULT_INCIDENT_PATH'        { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_PATH }
        'SD_DEFAULT_REQUEST_ID'           { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_ID }
        'SD_DEFAULT_REQUEST_PATH'         { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_PATH }
        'SERIAL_NUMBER'                   { $evResponseData=$evResponseData.SERIAL_NUMBER }
        'SERVER_TYPE_ID'                  { $evResponseData=$evResponseData.SERVER_TYPE_ID }
        'SLA_ID'                          { $evResponseData=$evResponseData.SLA_ID }
        'STATUS_ID'                       { $evResponseData=$evResponseData.STATUS_ID }
        'SUPPLIER_ID'                     { $evResponseData=$evResponseData.SUPPLIER_ID }
        'SUPPLIER_PATH'                   { $evResponseData=$evResponseData.SUPPLIER_PATH }
        'TERM'                            { $evResponseData=$evResponseData.TERM }
        'UPDATED_BY_DISCOVERY'            { $evResponseData=$evResponseData.UPDATED_BY_DISCOVERY }
        'UPDATE_COVERAGE_TERM'            { $evResponseData=$evResponseData.UPDATE_COVERAGE_TERM }
        'WARANTY_TYPE_ID'                 { $evResponseData=$evResponseData.WARANTY_TYPE_ID }
        'XPOS'                            { $evResponseData=$evResponseData.XPOS }
        'YPOS'                            { $evResponseData=$evResponseData.YPOS }
        'ZPOS'                            { $evResponseData=$evResponseData.ZPOS }
      } # Switch $evOption

      If ($evResponseData) {

        Write-Host "$evOption returned for $evHostname" -ForegroundColor $evFGColorInfo

      } Else {
        Write-Host "$evOption unavailable for $evHostname." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }# If !$evResponseData

    }#Process

    End {

      return $evResponseData

    }#End

  } # Get-EVAssetDetailByAssetName

  Function Get-EVAssetDetailBySerialNumber {
    <#
        .SYNOPSIS
        "Get-EVAssetDetailBySerialNumber" in 1-2 sentences

        .DESCRIPTION
        Add a more complete description of what the function does.

        .PARAMETER SerialNumber
        Describe parameter -SerialNumber.

        .PARAMETER Option
        Describe parameter -evOption.

        .PARAMETER MaxRows
        Describe parameter -MaxRows.

        .PARAMETER SaveReport
        Describe parameter -SaveReport.

        .EXAMPLE
        Get-EVAssetDetailBySerialNumber -SerialNumber Value -evOption Value -MaxRows Value -SaveReport
        Use the Option parameter to return different asset details.

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption ASSET_ID

          Returns:
            ASSET_ID returned for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea
            75974

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption NETWORK_IDENTIFIER

          Returns:
            NETWORK_IDENTIFIER returned for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea
            CDC-LIC03

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption E_IP_ADDRESS

          Returns:
            E_IP_ADDRESS unavailable for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea.
            ---

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption IS_CI

          Returns:
            IS_CI returned for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea
            1

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption LAST_UPDATE

          Returns:
            LAST_UPDATE returned for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea
            2018-12-18

        .EXAMPLE
          Get-EVAssetDetailBySerialNumber -evSerialNumber 'VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea' -evOption LAST_PHYSICAL_INVENTORY

          Returns:
            LAST_PHYSICAL_INVENTORY unavailable for VMware-42 29 0f a6 18 95 46 80-2a 83 c8 56 7b 83 44 ea.
            ---

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVAssetDetailBySerialNumber

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>



    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
        HelpMessage='Enter a hostname')]
        [string]$evSerialNumber,

       [Parameter(Mandatory=$true,
        HelpMessage='Select an option.')]
        [ValidateSet('ALL-Data',
          'ACQUISITION_TYPE_ID','ASSET_GUID','ASSET_ID','ASSET_LABEL','ASSET_TAG','AUTOMATIC_RENEWAL',
          'AVAILABILITY_SLA_ID','AVAILABLE_FIELD_1','AVAILABLE_FIELD_2','AVAILABLE_FIELD_3',
          'AVAILABLE_FIELD_4','AVAILABLE_FIELD_5','AVAILABLE_FIELD_6','BEFORE_LOAN_DEPARTMENT_ID',
          'BEFORE_LOAN_DEPARTMENT_PATH','BEFORE_LOAN_EMPLOYEE_ID','BEFORE_LOAN_LOCATION_ID',
          'BEFORE_LOAN_LOCATION_PATH','BILLING_PERIODICITY_IN_MONTH','BUDGET_ID','BUY_BACK_VALUE',
          'BUY_BACK_VALUE_CUR_ID','CATALOG_ASSET.ARTICLE_MODEL','CATALOG_ASSET.CATALOG_ID',
          'CATALOG_ASSET.NET_PRICE','CATALOG_ASSET.SMBIOS_NAME','CATALOG_ASSET.TITLE_EN','CATALOG_ID',
          'CHARGE_BACK','CHARGE_BACK_CUR_ID','CI_BACKUP_BY_DEFAULT','CI_STATUS_ID','CI_VERSION',
          'CM_DEFAULT_CHANGE_ID','CM_DEFAULT_CHANGE_PATH','ASSET_COMMENTS','COMMENT_ASSET.HREF',
          'CONFIGURATION_ID','CONTRACT_TYPE_ID','CRITICAL_LEVEL_ID','DELIVERY_DATE','DELIVERY_NUMBER',
          'DEPARTMENT.DEPARTMENT_CODE','DEPARTMENT.DEPARTMENT_EN','DEPARTMENT.DEPARTMENT_ID',
          'DEPARTMENT.DEPARTMENT_LABEL','DEPARTMENT.DEPARTMENT_PATH','DEPARTMENT_ID','DEPARTMENT_PATH',
          'DEPRECIATION_RULE_ID','D_HARDWARE_GUID','EMPLOYEE.BEGIN_OF_CONTRACT','EMPLOYEE.CELLULAR_NUMBER',
          'EMPLOYEE.DEPARTMENT_PATH','EMPLOYEE.EMPLOYEE_ID','EMPLOYEE.E_MAIL','EMPLOYEE.LAST_NAME',
          'EMPLOYEE.LOCATION_PATH','EMPLOYEE.PHONE_NUMBER','EMPLOYEE_ID','END_OF_WARANTY','ENTRY_DATE',
          'ESTIMATED_PERCENTAGE_USE','EXPECTED_END_LEND_DATE','EXPECTED_RETURN_DATE','E_BW_BEFORE_OVERAGE',
          'E_COLOR_BEFORE_OVERAGE','E_CONTRACT_RENEWED','E_CONTRACT_STATUS','E_COST_BW_COVERAGE',
          'E_COST_BW_OVERAGE','E_COST_COLOR_COVERAGE','E_COST_COLOR_OVERAGE','E_COST_PER_BW_CLICK',
          'E_COST_PER_CLICK','E_COST_PER_COLOR_CLICK','E_FAX_NUMBER','E_IP_ADDRESS','E_MAC_ADDRESS',
          'E_NOTES.HREF','E_NOTIFICATION_DUR','E_OPERATING_SYSTEM','E_OVERAGE_COST','E_PAGE_PER_MINUTE',
          'E_PO_NUMBER','E_PRINT_SERVER','E_RELATED_TICKET_NUMBER','E_RLS_MANAGING_GROUP','E_RLS_OWNING_GROUP',
          'E_RLS_SUPPORTING_GROUP','E_RLS_USING_GROUP','E_SUPPLIER_EQUIP_NUM','E_TERM_LANG','E_VMO_CONTACT',
          'E_WIDE_BASE_CHARGE','E_WIDE_SQUARE_FEET','E_primary_employee','FALLEN_TERM','FIXED_ASSET_NUMBER',
          'HREF','INITIAL_START','INSTALLATION_DATE','INTERNAL_DELIVERY_DATE','INTERNAL_DISPO','INVENTORY_ID',
          'INVOICE_NUMBER','IS_CI','IS_DML','IS_LOCKED','IS_SERVICE','LAST_AUTOMATIC_DISCOVERY','LAST_INTEGRATION',
          'LAST_PAYMENT','LAST_PAYMENT_CUR_ID','LAST_PHYSICAL_INVENTORY','LAST_UPDATE','LICENSE_VERSION',
          'LOCATION.CITY','LOCATION.LOCATION_CODE','LOCATION.LOCATION_EN','LOCATION.LOCATION_ID',
          'LOCATION.LOCATION_PATH','LOCATION_ID','LOCATION_PATH','LOCATION_TO_CHECK_REQUEST_ID','MAINTENANCE_COST',
          'MAINTENANCE_COST_CUR_ID','MAIN_USAGE_ID','MAX_INSTALLS','MONTHLY_FIXED_COST','MONTHLY_FIXED_COST_CUR_ID',
          'MONTHLY_NET_RENTAL','MONTHLY_NET_RENTAL_CUR_ID','MONTH_DURATION','NETWORK_IDENTIFIER','NEXT_CI_VERSION',
          'NEXT_DEPARTMENT_ID','NEXT_DEPARTMENT_PATH','NEXT_MAINTENANCE_DATE','NEXT_STATUS_ID',
          'NEXT_USER_APPLICATION_DATE','NEXT_USER_ID','NOTICE','ORDER_DETAILS_ID','ORDER_NUMBER',
          'OWNERSHIP_TO_CHECK_REQUEST_ID','PACKAGE_PATH','PIPELINE_STATUS_ID','POWER_CONSUMPTION_WH',
          'PROCESSOR_COUNT','PROCESSOR_SOCKET_COUNT','PROJECT_ID','PROVIDER_ID','PROVIDER_PATH','PURCHASE_DATE',
          'PURCHASE_PRICE','PURCHASE_PRICE_CUR_ID','PURCHASE_RATE_ID','RECYCLED_DATE','RECYCLING_PROVIDER_ID',
          'RECYCLING_PROVIDER_PATH','REFORM_NUMBER','REMOVED_DATE','RENEWAL_DECISION_ID','RENEWAL_VALUE',
          'RENEWAL_VALUE_CUR_ID','REPAIRED_BY_ID','REPAIRED_BY_PATH','REQUEST_ID','RESALES_VALUE','SCHEDULED_END',
          'SD_CATALOG_ID','SD_CATALOG_PATH','SD_DEFAULT_INCIDENT_ID','SD_DEFAULT_INCIDENT_PATH','SD_DEFAULT_REQUEST_ID',
          'SD_DEFAULT_REQUEST_PATH','SERIAL_NUMBER','SERVER_TYPE_ID','SLA_ID','STATUS_ID','SUPPLIER_ID','SUPPLIER_PATH',
          'TERM','UPDATED_BY_DISCOVERY','UPDATE_COVERAGE_TERM','WARANTY_TYPE_ID','XPOS','YPOS','ZPOS'
      )]
        [string]$evOption,
        [string]$evMaxRows = 50,

        [switch]$evSaveReport
    )

    Begin {

      # Setup Basic Authentication to EasyVista.

      $evUrl = (('{0}?max_rows={1}&search=Serial_Number~"{2}"' -f $evAssetsUrl, $evMaxRows, $evSerialNumber))

      $evJsonfile = ('{0}\{1}_{2}.json' -f $evTempPath, $evSerialNumber, $global:evDateStamp)

    }#Begin


    Process {

      Try {
        $evResponseData = Invoke-RestMethod -Method Get -Uri $evUrl -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue #-OutFile $evJsonfile


        If ($evResponseData.record_count -eq '1') {

          #$evHref = $($evResponseData.records.href)
          $evHref = $($evResponseData.records.href) -replace ('http:','https:')
          $evResponseData = Invoke-RestMethod -Method Get -Uri ($evHref) -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue


        } Elseif ($evResponseData.record_count -gt '1') {

            #Write-Host 'Could not find a matching system with that serial number.' -ForegroundColor $evFGColorVerbose
            Write-Host "Please check for duplicate records.  Your request returned $($evResponseData.record_count) records." -ForegroundColor $evFGColorBad
            $evResponseData = 'Multiple-records-found'

        } Elseif ($evResponseData.record_count -eq 0) {
            Write-Host "Could not find a matching system with serial nuymber ($evSerialNumber) in EasyVista." -ForegroundColor $evFGColorBad
            $evResponseData = '---'
        }


      } Catch {
        Write-Host "Could not find a matching system with serial nuymber ($evSerialNumber) in EasyVista." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }

      If ($evSaveReport) {
        $evResponseData | ConvertTo-Json | Out-File $evJsonfile
        Write-Host "Report saved to $evJsonfile." -ForegroundColor $evFGColorInfo
      }

      Switch ($evOption) {
        'ALL-Data'                        { $evResponseData = $evResponseData }
        'ACQUISITION_TYPE_ID'             { $evResponseData=$evResponseData.ACQUISITION_TYPE_ID }
        'ASSET_GUID'                      { $evResponseData=$evResponseData.ASSET_GUID }
        'ASSET_ID'                        { $evResponseData=$evResponseData.ASSET_ID }
        'ASSET_LABEL'                     { $evResponseData=$evResponseData.ASSET_LABEL }
        'ASSET_TAG'                       { $evResponseData=$evResponseData.ASSET_TAG }
        'AUTOMATIC_RENEWAL'               { $evResponseData=$evResponseData.AUTOMATIC_RENEWAL }
        'AVAILABILITY_SLA_ID'             { $evResponseData=$evResponseData.AVAILABILITY_SLA_ID }
        'AVAILABLE_FIELD_1'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_1 }
        'AVAILABLE_FIELD_2'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_2 }
        'AVAILABLE_FIELD_3'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_3 }
        'AVAILABLE_FIELD_4'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_4 }
        'AVAILABLE_FIELD_5'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_5 }
        'AVAILABLE_FIELD_6'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_6 }
        'BEFORE_LOAN_DEPARTMENT_ID'       { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_ID }
        'BEFORE_LOAN_DEPARTMENT_PATH'     { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_PATH }
        'BEFORE_LOAN_EMPLOYEE_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_EMPLOYEE_ID }
        'BEFORE_LOAN_LOCATION_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_ID }
        'BEFORE_LOAN_LOCATION_PATH'       { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_PATH }
        'BILLING_PERIODICITY_IN_MONTH'    { $evResponseData=$evResponseData.BILLING_PERIODICITY_IN_MONTH }
        'BUDGET_ID'                       { $evResponseData=$evResponseData.BUDGET_ID }
        'BUY_BACK_VALUE'                  { $evResponseData=$evResponseData.BUY_BACK_VALUE }
        'BUY_BACK_VALUE_CUR_ID'           { $evResponseData=$evResponseData.BUY_BACK_VALUE_CUR_ID }
        'CATALOG_ASSET.ARTICLE_MODEL'     { $evResponseData=$evResponseData.CATALOG_ASSET.ARTICLE_MODEL }
        'CATALOG_ASSET.CATALOG_ID'        { $evResponseData=$evResponseData.CATALOG_ASSET.CATALOG_ID }
        'CATALOG_ASSET.NET_PRICE'         { $evResponseData=$evResponseData.CATALOG_ASSET.NET_PRICE }
        'CATALOG_ASSET.SMBIOS_NAME'       { $evResponseData=$evResponseData.CATALOG_ASSET.SMBIOS_NAME }
        'CATALOG_ASSET.TITLE_EN'          { $evResponseData=$evResponseData.CATALOG_ASSET.TITLE_EN }
        'CATALOG_ID'                      { $evResponseData=$evResponseData.CATALOG_ID }
        'CHARGE_BACK'                     { $evResponseData=$evResponseData.CHARGE_BACK }
        'CHARGE_BACK_CUR_ID'              { $evResponseData=$evResponseData.CHARGE_BACK_CUR_ID }
        'CI_BACKUP_BY_DEFAULT'            { $evResponseData=$evResponseData.CI_BACKUP_BY_DEFAULT }
        'CI_STATUS_ID'                    { $evResponseData=$evResponseData.CI_STATUS_ID }
        'CI_VERSION'                      { $evResponseData=$evResponseData.CI_VERSION }
        'CM_DEFAULT_CHANGE_ID'            { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_ID }
        'CM_DEFAULT_CHANGE_PATH'          { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_PATH }
        'ASSET_COMMENTS'                  { $evResponseData = (Get-EVAssetComment -evAssetID ($evResponseData.ASSET_ID)) }
        'COMMENT_ASSET.HREF'              { $evResponseData = $evResponseData.COMMENT_ASSET.HREF }
        'CONFIGURATION_ID'                { $evResponseData=$evResponseData.CONFIGURATION_ID }
        'CONTRACT_TYPE_ID'                { $evResponseData=$evResponseData.CONTRACT_TYPE_ID }
        'CRITICAL_LEVEL_ID'               { $evResponseData=$evResponseData.CRITICAL_LEVEL_ID }
        'DELIVERY_DATE'                   { $evResponseData=$evResponseData.DELIVERY_DATE }
        'DELIVERY_NUMBER'                 { $evResponseData=$evResponseData.DELIVERY_NUMBER }
        'DEPARTMENT.DEPARTMENT_CODE'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_CODE }
        'DEPARTMENT.DEPARTMENT_EN'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_EN }
        'DEPARTMENT.DEPARTMENT_ID'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_ID }
        'DEPARTMENT.DEPARTMENT_LABEL'     { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_LABEL }
        'DEPARTMENT.DEPARTMENT_PATH'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_PATH }
        'DEPARTMENT_ID'                   { $evResponseData=$evResponseData.DEPARTMENT_ID }
        'DEPARTMENT_PATH'                 { $evResponseData=$evResponseData.DEPARTMENT_PATH }
        'DEPRECIATION_RULE_ID'            { $evResponseData=$evResponseData.DEPRECIATION_RULE_ID }
        'D_HARDWARE_GUID'                 { $evResponseData=$evResponseData.D_HARDWARE_GUID }
        'EMPLOYEE.BEGIN_OF_CONTRACT'      { $evResponseData=$evResponseData.EMPLOYEE.BEGIN_OF_CONTRACT }
        'EMPLOYEE.CELLULAR_NUMBER'        { $evResponseData=$evResponseData.EMPLOYEE.CELLULAR_NUMBER }
        'EMPLOYEE.DEPARTMENT_PATH'        { $evResponseData=$evResponseData.EMPLOYEE.DEPARTMENT_PATH }
        'EMPLOYEE.EMPLOYEE_ID'            { $evResponseData=$evResponseData.EMPLOYEE.EMPLOYEE_ID }
        'EMPLOYEE.E_MAIL'                 { $evResponseData=$evResponseData.EMPLOYEE.E_MAIL }
        'EMPLOYEE.LAST_NAME'              { $evResponseData=$evResponseData.EMPLOYEE.LAST_NAME }
        'EMPLOYEE.LOCATION_PATH'          { $evResponseData=$evResponseData.EMPLOYEE.LOCATION_PATH }
        'EMPLOYEE.PHONE_NUMBER'           { $evResponseData=$evResponseData.EMPLOYEE.PHONE_NUMBER }
        'EMPLOYEE_ID'                     { $evResponseData=$evResponseData.EMPLOYEE_ID }
        'END_OF_WARANTY'                  { $evResponseData=$evResponseData.END_OF_WARANTY }
        'ENTRY_DATE'                      { $evResponseData=$evResponseData.ENTRY_DATE }
        'ESTIMATED_PERCENTAGE_USE'        { $evResponseData=$evResponseData.ESTIMATED_PERCENTAGE_USE }
        'EXPECTED_END_LEND_DATE'          { $evResponseData=$evResponseData.EXPECTED_END_LEND_DATE }
        'EXPECTED_RETURN_DATE'            { $evResponseData=$evResponseData.EXPECTED_RETURN_DATE }
        'E_BW_BEFORE_OVERAGE'             { $evResponseData=$evResponseData.E_BW_BEFORE_OVERAGE }
        'E_COLOR_BEFORE_OVERAGE'          { $evResponseData=$evResponseData.E_COLOR_BEFORE_OVERAGE }
        'E_CONTRACT_RENEWED'              { $evResponseData=$evResponseData.E_CONTRACT_RENEWED }
        'E_CONTRACT_STATUS'               { $evResponseData=$evResponseData.E_CONTRACT_STATUS }
        'E_COST_BW_COVERAGE'              { $evResponseData=$evResponseData.E_COST_BW_COVERAGE }
        'E_COST_BW_OVERAGE'               { $evResponseData=$evResponseData.E_COST_BW_OVERAGE }
        'E_COST_COLOR_COVERAGE'           { $evResponseData=$evResponseData.E_COST_COLOR_COVERAGE }
        'E_COST_COLOR_OVERAGE'            { $evResponseData=$evResponseData.E_COST_COLOR_OVERAGE }
        'E_COST_PER_BW_CLICK'             { $evResponseData=$evResponseData.E_COST_PER_BW_CLICK }
        'E_COST_PER_CLICK'                { $evResponseData=$evResponseData.E_COST_PER_CLICK }
        'E_COST_PER_COLOR_CLICK'          { $evResponseData=$evResponseData.E_COST_PER_COLOR_CLICK }
        'E_FAX_NUMBER'                    { $evResponseData=$evResponseData.E_FAX_NUMBER }
        'E_IP_ADDRESS'                    { $evResponseData=$evResponseData.E_IP_ADDRESS }
        'E_MAC_ADDRESS'                   { $evResponseData=$evResponseData.E_MAC_ADDRESS }
        'E_NOTES.HREF'                    { $evResponseData=$evResponseData.E_NOTES.HREF}
        'E_NOTIFICATION_DUR'              { $evResponseData=$evResponseData.E_NOTIFICATION_DUR }
        'E_OPERATING_SYSTEM'              { $evResponseData=$evResponseData.E_OPERATING_SYSTEM }
        'E_OVERAGE_COST'                  { $evResponseData=$evResponseData.E_OVERAGE_COST }
        'E_PAGE_PER_MINUTE'               { $evResponseData=$evResponseData.E_PAGE_PER_MINUTE }
        'E_PO_NUMBER'                     { $evResponseData=$evResponseData.E_PO_NUMBER }
        'E_PRINT_SERVER'                  { $evResponseData=$evResponseData.E_PRINT_SERVER }
        'E_RELATED_TICKET_NUMBER'         { $evResponseData=$evResponseData.E_RELATED_TICKET_NUMBER }
        'E_RLS_MANAGING_GROUP'            { $evResponseData=$evResponseData.E_RLS_MANAGING_GROUP }
        'E_RLS_OWNING_GROUP'              { $evResponseData=$evResponseData.E_RLS_OWNING_GROUP }
        'E_RLS_SUPPORTING_GROUP'          { $evResponseData=$evResponseData.E_RLS_SUPPORTING_GROUP }
        'E_RLS_USING_GROUP'               { $evResponseData=$evResponseData.E_RLS_USING_GROUP }
        'E_SUPPLIER_EQUIP_NUM'            { $evResponseData=$evResponseData.E_SUPPLIER_EQUIP_NUM }
        'E_TERM_LANG'                     { $evResponseData=$evResponseData.E_TERM_LANG }
        'E_VMO_CONTACT'                   { $evResponseData=$evResponseData.E_VMO_CONTACT }
        'E_WIDE_BASE_CHARGE'              { $evResponseData=$evResponseData.E_WIDE_BASE_CHARGE }
        'E_WIDE_SQUARE_FEET'              { $evResponseData=$evResponseData.E_WIDE_SQUARE_FEET }
        'E_primary_employee'              { $evResponseData=$evResponseData.E_primary_employee }
        'FALLEN_TERM'                     { $evResponseData=$evResponseData.FALLEN_TERM }
        'FIXED_ASSET_NUMBER'              { $evResponseData=$evResponseData.FIXED_ASSET_NUMBER }
        'HREF'                            { $evResponseData=$evResponseData.HREF }
        'INITIAL_START'                   { $evResponseData=$evResponseData.INITIAL_START }
        'INSTALLATION_DATE'               { $evResponseData=$evResponseData.INSTALLATION_DATE }
        'INTERNAL_DELIVERY_DATE'          { $evResponseData=$evResponseData.INTERNAL_DELIVERY_DATE }
        'INTERNAL_DISPO'                  { $evResponseData=$evResponseData.INTERNAL_DISPO }
        'INVENTORY_ID'                    { $evResponseData=$evResponseData.INVENTORY_ID }
        'INVOICE_NUMBER'                  { $evResponseData=$evResponseData.INVOICE_NUMBER }
        'IS_CI'                           { $evResponseData=$evResponseData.IS_CI }
        'IS_DML'                          { $evResponseData=$evResponseData.IS_DML }
        'IS_LOCKED'                       { $evResponseData=$evResponseData.IS_LOCKED }
        'IS_SERVICE'                      { $evResponseData=$evResponseData.IS_SERVICE }
        'LAST_AUTOMATIC_DISCOVERY'        { $evResponseData=$evResponseData.LAST_AUTOMATIC_DISCOVERY }
        'LAST_INTEGRATION'                { $evResponseData=$evResponseData.LAST_INTEGRATION }
        'LAST_PAYMENT'                    { $evResponseData=$evResponseData.LAST_PAYMENT }
        'LAST_PAYMENT_CUR_ID'             { $evResponseData=$evResponseData.LAST_PAYMENT_CUR_ID }
        'LAST_PHYSICAL_INVENTORY'         { $evResponseData=$evResponseData.LAST_PHYSICAL_INVENTORY }
        'LAST_UPDATE'                     { $evResponseData=$evResponseData.LAST_UPDATE }
        'LICENSE_VERSION'                 { $evResponseData=$evResponseData.LICENSE_VERSION }
        'LOCATION.CITY'                   { $evResponseData=$evResponseData.LOCATION.CITY }
        'LOCATION.LOCATION_CODE'          { $evResponseData=$evResponseData.LOCATION.LOCATION_CODE }
        'LOCATION.LOCATION_EN'            { $evResponseData=$evResponseData.LOCATION.LOCATION_EN }
        'LOCATION.LOCATION_ID'            { $evResponseData=$evResponseData.LOCATION.LOCATION_ID }
        'LOCATION.LOCATION_PATH'          { $evResponseData=$evResponseData.LOCATION.LOCATION_PATH }
        'LOCATION_ID'                     { $evResponseData=$evResponseData.LOCATION_ID }
        'LOCATION_PATH'                   { $evResponseData=$evResponseData.LOCATION_PATH }
        'LOCATION_TO_CHECK_REQUEST_ID'    { $evResponseData=$evResponseData.LOCATION_TO_CHECK_REQUEST_ID }
        'MAINTENANCE_COST'                { $evResponseData=$evResponseData.MAINTENANCE_COST }
        'MAINTENANCE_COST_CUR_ID'         { $evResponseData=$evResponseData.MAINTENANCE_COST_CUR_ID }
        'MAIN_USAGE_ID'                   { $evResponseData=$evResponseData.MAIN_USAGE_ID }
        'MAX_INSTALLS'                    { $evResponseData=$evResponseData.MAX_INSTALLS }
        'MONTHLY_FIXED_COST'              { $evResponseData=$evResponseData.MONTHLY_FIXED_COST }
        'MONTHLY_FIXED_COST_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_FIXED_COST_CUR_ID }
        'MONTHLY_NET_RENTAL'              { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL }
        'MONTHLY_NET_RENTAL_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL_CUR_ID }
        'MONTH_DURATION'                  { $evResponseData=$evResponseData.MONTH_DURATION }
        'NETWORK_IDENTIFIER'              { $evResponseData=$evResponseData.NETWORK_IDENTIFIER }
        'NEXT_CI_VERSION'                 { $evResponseData=$evResponseData.NEXT_CI_VERSION }
        'NEXT_DEPARTMENT_ID'              { $evResponseData=$evResponseData.NEXT_DEPARTMENT_ID }
        'NEXT_DEPARTMENT_PATH'            { $evResponseData=$evResponseData.NEXT_DEPARTMENT_PATH }
        'NEXT_MAINTENANCE_DATE'           { $evResponseData=$evResponseData.NEXT_MAINTENANCE_DATE }
        'NEXT_STATUS_ID'                  { $evResponseData=$evResponseData.NEXT_STATUS_ID }
        'NEXT_USER_APPLICATION_DATE'      { $evResponseData=$evResponseData.NEXT_USER_APPLICATION_DATE }
        'NEXT_USER_ID'                    { $evResponseData=$evResponseData.NEXT_USER_ID }
        'NOTICE'                          { $evResponseData=$evResponseData.NOTICE }
        'ORDER_DETAILS_ID'                { $evResponseData=$evResponseData.ORDER_DETAILS_ID }
        'ORDER_NUMBER'                    { $evResponseData=$evResponseData.ORDER_NUMBER }
        'OWNERSHIP_TO_CHECK_REQUEST_ID'   { $evResponseData=$evResponseData.OWNERSHIP_TO_CHECK_REQUEST_ID }
        'PACKAGE_PATH'                    { $evResponseData=$evResponseData.PACKAGE_PATH }
        'PIPELINE_STATUS_ID'              { $evResponseData=$evResponseData.PIPELINE_STATUS_ID }
        'POWER_CONSUMPTION_WH'            { $evResponseData=$evResponseData.POWER_CONSUMPTION_WH }
        'PROCESSOR_COUNT'                 { $evResponseData=$evResponseData.PROCESSOR_COUNT }
        'PROCESSOR_SOCKET_COUNT'          { $evResponseData=$evResponseData.PROCESSOR_SOCKET_COUNT }
        'PROJECT_ID'                      { $evResponseData=$evResponseData.PROJECT_ID }
        'PROVIDER_ID'                     { $evResponseData=$evResponseData.PROVIDER_ID }
        'PROVIDER_PATH'                   { $evResponseData=$evResponseData.PROVIDER_PATH }
        'PURCHASE_DATE'                   { $evResponseData=$evResponseData.PURCHASE_DATE }
        'PURCHASE_PRICE'                  { $evResponseData=$evResponseData.PURCHASE_PRICE }
        'PURCHASE_PRICE_CUR_ID'           { $evResponseData=$evResponseData.PURCHASE_PRICE_CUR_ID }
        'PURCHASE_RATE_ID'                { $evResponseData=$evResponseData.PURCHASE_RATE_ID }
        'RECYCLED_DATE'                   { $evResponseData=$evResponseData.RECYCLED_DATE }
        'RECYCLING_PROVIDER_ID'           { $evResponseData=$evResponseData.RECYCLING_PROVIDER_ID }
        'RECYCLING_PROVIDER_PATH'         { $evResponseData=$evResponseData.RECYCLING_PROVIDER_PATH }
        'REFORM_NUMBER'                   { $evResponseData=$evResponseData.REFORM_NUMBER }
        'REMOVED_DATE'                    { $evResponseData=$evResponseData.REMOVED_DATE }
        'RENEWAL_DECISION_ID'             { $evResponseData=$evResponseData.RENEWAL_DECISION_ID }
        'RENEWAL_VALUE'                   { $evResponseData=$evResponseData.RENEWAL_VALUE }
        'RENEWAL_VALUE_CUR_ID'            { $evResponseData=$evResponseData.RENEWAL_VALUE_CUR_ID }
        'REPAIRED_BY_ID'                  { $evResponseData=$evResponseData.REPAIRED_BY_ID }
        'REPAIRED_BY_PATH'                { $evResponseData=$evResponseData.REPAIRED_BY_PATH }
        'REQUEST_ID'                      { $evResponseData=$evResponseData.REQUEST_ID }
        'RESALES_VALUE'                   { $evResponseData=$evResponseData.RESALES_VALUE }
        'SCHEDULED_END'                   { $evResponseData=$evResponseData.SCHEDULED_END }
        'SD_CATALOG_ID'                   { $evResponseData=$evResponseData.SD_CATALOG_ID }
        'SD_CATALOG_PATH'                 { $evResponseData=$evResponseData.SD_CATALOG_PATH }
        'SD_DEFAULT_INCIDENT_ID'          { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_ID }
        'SD_DEFAULT_INCIDENT_PATH'        { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_PATH }
        'SD_DEFAULT_REQUEST_ID'           { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_ID }
        'SD_DEFAULT_REQUEST_PATH'         { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_PATH }
        'SERIAL_NUMBER'                   { $evResponseData=$evResponseData.SERIAL_NUMBER }
        'SERVER_TYPE_ID'                  { $evResponseData=$evResponseData.SERVER_TYPE_ID }
        'SLA_ID'                          { $evResponseData=$evResponseData.SLA_ID }
        'STATUS_ID'                       { $evResponseData=$evResponseData.STATUS_ID }
        'SUPPLIER_ID'                     { $evResponseData=$evResponseData.SUPPLIER_ID }
        'SUPPLIER_PATH'                   { $evResponseData=$evResponseData.SUPPLIER_PATH }
        'TERM'                            { $evResponseData=$evResponseData.TERM }
        'UPDATED_BY_DISCOVERY'            { $evResponseData=$evResponseData.UPDATED_BY_DISCOVERY }
        'UPDATE_COVERAGE_TERM'            { $evResponseData=$evResponseData.UPDATE_COVERAGE_TERM }
        'WARANTY_TYPE_ID'                 { $evResponseData=$evResponseData.WARANTY_TYPE_ID }
        'XPOS'                            { $evResponseData=$evResponseData.XPOS }
        'YPOS'                            { $evResponseData=$evResponseData.YPOS }
        'ZPOS'                            { $evResponseData=$evResponseData.ZPOS }
      } # Switch $evOption

      If ($evResponseData) {

        Write-Host "$evOption returned for $evSerialNumber" -ForegroundColor $evFGColorInfo

      } Else {
        Write-Host "$evOption unavailable for $evSerialNumber." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }# If !$evResponseData

    }#Process

    End {

      return $evResponseData

    }#End

  } # Get-EVAssetDetailByAssetName

  Function Get-EVAssetDetailByAssetID {
    <#
        .SYNOPSIS
        "Get-EVAssetDetailByAssetID" in 1-2 sentences

        .DESCRIPTION
        Add a more complete description of what the function does.

        .PARAMETER evOption
        Describe parameter -evOption.

        .PARAMETER evSaveReport
        Describe parameter -evSaveReport.

        .EXAMPLE
        Get-EVAssetDetailByAssetID -evassetid Value -evOption Value -SaveReport
        Use the Option parameter to return different asset details.

        .EXAMPLE
          Get-EVAssetDetailByAssetID -evAssetID 148069 -evOption SERIAL_NUMBER

        Returns:
          SERIAL_NUMBER returned for 148069
          5853-8637-0429-8249-2563-9209-21

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-EVAssetDetailBySerialNumber

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>



    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
        HelpMessage='Enter an asset ID')]
        [string]$evAssetID,

       [Parameter(Mandatory=$true,
        HelpMessage='Select an option.')]
        [ValidateSet('ALL-Data',
          'ACQUISITION_TYPE_ID','ASSET_GUID','ASSET_ID','ASSET_LABEL','ASSET_TAG','AUTOMATIC_RENEWAL',
          'AVAILABILITY_SLA_ID','AVAILABLE_FIELD_1','AVAILABLE_FIELD_2','AVAILABLE_FIELD_3',
          'AVAILABLE_FIELD_4','AVAILABLE_FIELD_5','AVAILABLE_FIELD_6','BEFORE_LOAN_DEPARTMENT_ID',
          'BEFORE_LOAN_DEPARTMENT_PATH','BEFORE_LOAN_EMPLOYEE_ID','BEFORE_LOAN_LOCATION_ID',
          'BEFORE_LOAN_LOCATION_PATH','BILLING_PERIODICITY_IN_MONTH','BUDGET_ID','BUY_BACK_VALUE',
          'BUY_BACK_VALUE_CUR_ID','CATALOG_ASSET.ARTICLE_MODEL','CATALOG_ASSET.CATALOG_ID',
          'CATALOG_ASSET.NET_PRICE','CATALOG_ASSET.SMBIOS_NAME','CATALOG_ASSET.TITLE_EN','CATALOG_ID',
          'CHARGE_BACK','CHARGE_BACK_CUR_ID','CI_BACKUP_BY_DEFAULT','CI_STATUS_ID','CI_VERSION',
          'CM_DEFAULT_CHANGE_ID','CM_DEFAULT_CHANGE_PATH','ASSET_COMMENTS','COMMENT_ASSET.HREF',
          'CONFIGURATION_ID','CONTRACT_TYPE_ID','CRITICAL_LEVEL_ID','DELIVERY_DATE','DELIVERY_NUMBER',
          'DEPARTMENT.DEPARTMENT_CODE','DEPARTMENT.DEPARTMENT_EN','DEPARTMENT.DEPARTMENT_ID',
          'DEPARTMENT.DEPARTMENT_LABEL','DEPARTMENT.DEPARTMENT_PATH','DEPARTMENT_ID','DEPARTMENT_PATH',
          'DEPRECIATION_RULE_ID','D_HARDWARE_GUID','EMPLOYEE.BEGIN_OF_CONTRACT','EMPLOYEE.CELLULAR_NUMBER',
          'EMPLOYEE.DEPARTMENT_PATH','EMPLOYEE.EMPLOYEE_ID','EMPLOYEE.E_MAIL','EMPLOYEE.LAST_NAME',
          'EMPLOYEE.LOCATION_PATH','EMPLOYEE.PHONE_NUMBER','EMPLOYEE_ID','END_OF_WARANTY','ENTRY_DATE',
          'ESTIMATED_PERCENTAGE_USE','EXPECTED_END_LEND_DATE','EXPECTED_RETURN_DATE','E_BW_BEFORE_OVERAGE',
          'E_COLOR_BEFORE_OVERAGE','E_CONTRACT_RENEWED','E_CONTRACT_STATUS','E_COST_BW_COVERAGE',
          'E_COST_BW_OVERAGE','E_COST_COLOR_COVERAGE','E_COST_COLOR_OVERAGE','E_COST_PER_BW_CLICK',
          'E_COST_PER_CLICK','E_COST_PER_COLOR_CLICK','E_FAX_NUMBER','E_IP_ADDRESS','E_MAC_ADDRESS',
          'E_NOTES.HREF','E_NOTIFICATION_DUR','E_OPERATING_SYSTEM','E_OVERAGE_COST','E_PAGE_PER_MINUTE',
          'E_PO_NUMBER','E_PRINT_SERVER','E_RELATED_TICKET_NUMBER','E_RLS_MANAGING_GROUP','E_RLS_OWNING_GROUP',
          'E_RLS_SUPPORTING_GROUP','E_RLS_USING_GROUP','E_SUPPLIER_EQUIP_NUM','E_TERM_LANG','E_VMO_CONTACT',
          'E_WIDE_BASE_CHARGE','E_WIDE_SQUARE_FEET','E_primary_employee','FALLEN_TERM','FIXED_ASSET_NUMBER',
          'HREF','INITIAL_START','INSTALLATION_DATE','INTERNAL_DELIVERY_DATE','INTERNAL_DISPO','INVENTORY_ID',
          'INVOICE_NUMBER','IS_CI','IS_DML','IS_LOCKED','IS_SERVICE','LAST_AUTOMATIC_DISCOVERY','LAST_INTEGRATION',
          'LAST_PAYMENT','LAST_PAYMENT_CUR_ID','LAST_PHYSICAL_INVENTORY','LAST_UPDATE','LICENSE_VERSION',
          'LOCATION.CITY','LOCATION.LOCATION_CODE','LOCATION.LOCATION_EN','LOCATION.LOCATION_ID',
          'LOCATION.LOCATION_PATH','LOCATION_ID','LOCATION_PATH','LOCATION_TO_CHECK_REQUEST_ID','MAINTENANCE_COST',
          'MAINTENANCE_COST_CUR_ID','MAIN_USAGE_ID','MAX_INSTALLS','MONTHLY_FIXED_COST','MONTHLY_FIXED_COST_CUR_ID',
          'MONTHLY_NET_RENTAL','MONTHLY_NET_RENTAL_CUR_ID','MONTH_DURATION','NETWORK_IDENTIFIER','NEXT_CI_VERSION',
          'NEXT_DEPARTMENT_ID','NEXT_DEPARTMENT_PATH','NEXT_MAINTENANCE_DATE','NEXT_STATUS_ID',
          'NEXT_USER_APPLICATION_DATE','NEXT_USER_ID','NOTICE','ORDER_DETAILS_ID','ORDER_NUMBER',
          'OWNERSHIP_TO_CHECK_REQUEST_ID','PACKAGE_PATH','PIPELINE_STATUS_ID','POWER_CONSUMPTION_WH',
          'PROCESSOR_COUNT','PROCESSOR_SOCKET_COUNT','PROJECT_ID','PROVIDER_ID','PROVIDER_PATH','PURCHASE_DATE',
          'PURCHASE_PRICE','PURCHASE_PRICE_CUR_ID','PURCHASE_RATE_ID','RECYCLED_DATE','RECYCLING_PROVIDER_ID',
          'RECYCLING_PROVIDER_PATH','REFORM_NUMBER','REMOVED_DATE','RENEWAL_DECISION_ID','RENEWAL_VALUE',
          'RENEWAL_VALUE_CUR_ID','REPAIRED_BY_ID','REPAIRED_BY_PATH','REQUEST_ID','RESALES_VALUE','SCHEDULED_END',
          'SD_CATALOG_ID','SD_CATALOG_PATH','SD_DEFAULT_INCIDENT_ID','SD_DEFAULT_INCIDENT_PATH','SD_DEFAULT_REQUEST_ID',
          'SD_DEFAULT_REQUEST_PATH','SERIAL_NUMBER','SERVER_TYPE_ID','SLA_ID','STATUS_ID','SUPPLIER_ID','SUPPLIER_PATH',
          'TERM','UPDATED_BY_DISCOVERY','UPDATE_COVERAGE_TERM','WARANTY_TYPE_ID','XPOS','YPOS','ZPOS'
      )]
        [string]$evOption,
        [string]$evMaxRows = 50,

        [switch]$evSaveReport
    )

    Begin {

      # Setup Basic Authentication to EasyVista.

      $evUrl = (('{0}/{1}' -f $evAssetsUrl,$evAssetID))

      $evJsonfile = ('{0}\{1}_{2}.json' -f $evTempPath, $evAssetID, $global:evDateStamp)

    }#Begin


    Process {

      Try {
        $evResponseData = Invoke-RestMethod -Method Get -Uri $evUrl -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue #-OutFile $evJsonfile


        If ($evResponseData.record_count -eq '1' ) {

          $evHref = $($evResponseData.records.href) -replace ('http:','https:')
          $evResponseData = Invoke-RestMethod -Method Get -Uri ($evHref) -Headers $global:evHeader -ContentType 'application/json'  -ErrorVariable Crappy -ErrorAction SilentlyContinue

        } Elseif ( $evResponseData ) {


        } Else {
            Write-Host "Could not find a matching system with serial nuymber ($evAssetID) in EasyVista." -ForegroundColor $evFGColorBad
            $evResponseData = '---'
        }


      } Catch {
        Write-Host "Could not find a matching system with asset number ($evAssetID) in EasyVista." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }

      If ($evSaveReport) {
        $evResponseData | ConvertTo-Json | Out-File $evJsonfile
        Write-Host "Report saved to $evJsonfile." -ForegroundColor $evFGColorInfo
      }

      Switch ($evOption) {
        'ALL-Data'                        { $evResponseData = $evResponseData }
        'ACQUISITION_TYPE_ID'             { $evResponseData=$evResponseData.ACQUISITION_TYPE_ID }
        'ASSET_GUID'                      { $evResponseData=$evResponseData.ASSET_GUID }
        'ASSET_ID'                        { $evResponseData=$evResponseData.ASSET_ID }
        'ASSET_LABEL'                     { $evResponseData=$evResponseData.ASSET_LABEL }
        'ASSET_TAG'                       { $evResponseData=$evResponseData.ASSET_TAG }
        'AUTOMATIC_RENEWAL'               { $evResponseData=$evResponseData.AUTOMATIC_RENEWAL }
        'AVAILABILITY_SLA_ID'             { $evResponseData=$evResponseData.AVAILABILITY_SLA_ID }
        'AVAILABLE_FIELD_1'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_1 }
        'AVAILABLE_FIELD_2'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_2 }
        'AVAILABLE_FIELD_3'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_3 }
        'AVAILABLE_FIELD_4'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_4 }
        'AVAILABLE_FIELD_5'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_5 }
        'AVAILABLE_FIELD_6'               { $evResponseData=$evResponseData.AVAILABLE_FIELD_6 }
        'BEFORE_LOAN_DEPARTMENT_ID'       { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_ID }
        'BEFORE_LOAN_DEPARTMENT_PATH'     { $evResponseData=$evResponseData.BEFORE_LOAN_DEPARTMENT_PATH }
        'BEFORE_LOAN_EMPLOYEE_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_EMPLOYEE_ID }
        'BEFORE_LOAN_LOCATION_ID'         { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_ID }
        'BEFORE_LOAN_LOCATION_PATH'       { $evResponseData=$evResponseData.BEFORE_LOAN_LOCATION_PATH }
        'BILLING_PERIODICITY_IN_MONTH'    { $evResponseData=$evResponseData.BILLING_PERIODICITY_IN_MONTH }
        'BUDGET_ID'                       { $evResponseData=$evResponseData.BUDGET_ID }
        'BUY_BACK_VALUE'                  { $evResponseData=$evResponseData.BUY_BACK_VALUE }
        'BUY_BACK_VALUE_CUR_ID'           { $evResponseData=$evResponseData.BUY_BACK_VALUE_CUR_ID }
        'CATALOG_ASSET.ARTICLE_MODEL'     { $evResponseData=$evResponseData.CATALOG_ASSET.ARTICLE_MODEL }
        'CATALOG_ASSET.CATALOG_ID'        { $evResponseData=$evResponseData.CATALOG_ASSET.CATALOG_ID }
        'CATALOG_ASSET.NET_PRICE'         { $evResponseData=$evResponseData.CATALOG_ASSET.NET_PRICE }
        'CATALOG_ASSET.SMBIOS_NAME'       { $evResponseData=$evResponseData.CATALOG_ASSET.SMBIOS_NAME }
        'CATALOG_ASSET.TITLE_EN'          { $evResponseData=$evResponseData.CATALOG_ASSET.TITLE_EN }
        'CATALOG_ID'                      { $evResponseData=$evResponseData.CATALOG_ID }
        'CHARGE_BACK'                     { $evResponseData=$evResponseData.CHARGE_BACK }
        'CHARGE_BACK_CUR_ID'              { $evResponseData=$evResponseData.CHARGE_BACK_CUR_ID }
        'CI_BACKUP_BY_DEFAULT'            { $evResponseData=$evResponseData.CI_BACKUP_BY_DEFAULT }
        'CI_STATUS_ID'                    { $evResponseData=$evResponseData.CI_STATUS_ID }
        'CI_VERSION'                      { $evResponseData=$evResponseData.CI_VERSION }
        'CM_DEFAULT_CHANGE_ID'            { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_ID }
        'CM_DEFAULT_CHANGE_PATH'          { $evResponseData=$evResponseData.CM_DEFAULT_CHANGE_PATH }
        'ASSET_COMMENTS'                  { $evResponseData = (Get-EVAssetComment -evAssetID ($evResponseData.ASSET_ID)) }
        'COMMENT_ASSET.HREF'              { $evResponseData = $evResponseData.COMMENT_ASSET.HREF }
        'CONFIGURATION_ID'                { $evResponseData=$evResponseData.CONFIGURATION_ID }
        'CONTRACT_TYPE_ID'                { $evResponseData=$evResponseData.CONTRACT_TYPE_ID }
        'CRITICAL_LEVEL_ID'               { $evResponseData=$evResponseData.CRITICAL_LEVEL_ID }
        'DELIVERY_DATE'                   { $evResponseData=$evResponseData.DELIVERY_DATE }
        'DELIVERY_NUMBER'                 { $evResponseData=$evResponseData.DELIVERY_NUMBER }
        'DEPARTMENT.DEPARTMENT_CODE'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_CODE }
        'DEPARTMENT.DEPARTMENT_EN'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_EN }
        'DEPARTMENT.DEPARTMENT_ID'        { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_ID }
        'DEPARTMENT.DEPARTMENT_LABEL'     { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_LABEL }
        'DEPARTMENT.DEPARTMENT_PATH'      { $evResponseData=$evResponseData.DEPARTMENT.DEPARTMENT_PATH }
        'DEPARTMENT_ID'                   { $evResponseData=$evResponseData.DEPARTMENT_ID }
        'DEPARTMENT_PATH'                 { $evResponseData=$evResponseData.DEPARTMENT_PATH }
        'DEPRECIATION_RULE_ID'            { $evResponseData=$evResponseData.DEPRECIATION_RULE_ID }
        'D_HARDWARE_GUID'                 { $evResponseData=$evResponseData.D_HARDWARE_GUID }
        'EMPLOYEE.BEGIN_OF_CONTRACT'      { $evResponseData=$evResponseData.EMPLOYEE.BEGIN_OF_CONTRACT }
        'EMPLOYEE.CELLULAR_NUMBER'        { $evResponseData=$evResponseData.EMPLOYEE.CELLULAR_NUMBER }
        'EMPLOYEE.DEPARTMENT_PATH'        { $evResponseData=$evResponseData.EMPLOYEE.DEPARTMENT_PATH }
        'EMPLOYEE.EMPLOYEE_ID'            { $evResponseData=$evResponseData.EMPLOYEE.EMPLOYEE_ID }
        'EMPLOYEE.E_MAIL'                 { $evResponseData=$evResponseData.EMPLOYEE.E_MAIL }
        'EMPLOYEE.LAST_NAME'              { $evResponseData=$evResponseData.EMPLOYEE.LAST_NAME }
        'EMPLOYEE.LOCATION_PATH'          { $evResponseData=$evResponseData.EMPLOYEE.LOCATION_PATH }
        'EMPLOYEE.PHONE_NUMBER'           { $evResponseData=$evResponseData.EMPLOYEE.PHONE_NUMBER }
        'EMPLOYEE_ID'                     { $evResponseData=$evResponseData.EMPLOYEE_ID }
        'END_OF_WARANTY'                  { $evResponseData=$evResponseData.END_OF_WARANTY }
        'ENTRY_DATE'                      { $evResponseData=$evResponseData.ENTRY_DATE }
        'ESTIMATED_PERCENTAGE_USE'        { $evResponseData=$evResponseData.ESTIMATED_PERCENTAGE_USE }
        'EXPECTED_END_LEND_DATE'          { $evResponseData=$evResponseData.EXPECTED_END_LEND_DATE }
        'EXPECTED_RETURN_DATE'            { $evResponseData=$evResponseData.EXPECTED_RETURN_DATE }
        'E_BW_BEFORE_OVERAGE'             { $evResponseData=$evResponseData.E_BW_BEFORE_OVERAGE }
        'E_COLOR_BEFORE_OVERAGE'          { $evResponseData=$evResponseData.E_COLOR_BEFORE_OVERAGE }
        'E_CONTRACT_RENEWED'              { $evResponseData=$evResponseData.E_CONTRACT_RENEWED }
        'E_CONTRACT_STATUS'               { $evResponseData=$evResponseData.E_CONTRACT_STATUS }
        'E_COST_BW_COVERAGE'              { $evResponseData=$evResponseData.E_COST_BW_COVERAGE }
        'E_COST_BW_OVERAGE'               { $evResponseData=$evResponseData.E_COST_BW_OVERAGE }
        'E_COST_COLOR_COVERAGE'           { $evResponseData=$evResponseData.E_COST_COLOR_COVERAGE }
        'E_COST_COLOR_OVERAGE'            { $evResponseData=$evResponseData.E_COST_COLOR_OVERAGE }
        'E_COST_PER_BW_CLICK'             { $evResponseData=$evResponseData.E_COST_PER_BW_CLICK }
        'E_COST_PER_CLICK'                { $evResponseData=$evResponseData.E_COST_PER_CLICK }
        'E_COST_PER_COLOR_CLICK'          { $evResponseData=$evResponseData.E_COST_PER_COLOR_CLICK }
        'E_FAX_NUMBER'                    { $evResponseData=$evResponseData.E_FAX_NUMBER }
        'E_IP_ADDRESS'                    { $evResponseData=$evResponseData.E_IP_ADDRESS }
        'E_MAC_ADDRESS'                   { $evResponseData=$evResponseData.E_MAC_ADDRESS }
        'E_NOTES.HREF'                    { $evResponseData=$evResponseData.E_NOTES.HREF}
        'E_NOTIFICATION_DUR'              { $evResponseData=$evResponseData.E_NOTIFICATION_DUR }
        'E_OPERATING_SYSTEM'              { $evResponseData=$evResponseData.E_OPERATING_SYSTEM }
        'E_OVERAGE_COST'                  { $evResponseData=$evResponseData.E_OVERAGE_COST }
        'E_PAGE_PER_MINUTE'               { $evResponseData=$evResponseData.E_PAGE_PER_MINUTE }
        'E_PO_NUMBER'                     { $evResponseData=$evResponseData.E_PO_NUMBER }
        'E_PRINT_SERVER'                  { $evResponseData=$evResponseData.E_PRINT_SERVER }
        'E_RELATED_TICKET_NUMBER'         { $evResponseData=$evResponseData.E_RELATED_TICKET_NUMBER }
        'E_RLS_MANAGING_GROUP'            { $evResponseData=$evResponseData.E_RLS_MANAGING_GROUP }
        'E_RLS_OWNING_GROUP'              { $evResponseData=$evResponseData.E_RLS_OWNING_GROUP }
        'E_RLS_SUPPORTING_GROUP'          { $evResponseData=$evResponseData.E_RLS_SUPPORTING_GROUP }
        'E_RLS_USING_GROUP'               { $evResponseData=$evResponseData.E_RLS_USING_GROUP }
        'E_SUPPLIER_EQUIP_NUM'            { $evResponseData=$evResponseData.E_SUPPLIER_EQUIP_NUM }
        'E_TERM_LANG'                     { $evResponseData=$evResponseData.E_TERM_LANG }
        'E_VMO_CONTACT'                   { $evResponseData=$evResponseData.E_VMO_CONTACT }
        'E_WIDE_BASE_CHARGE'              { $evResponseData=$evResponseData.E_WIDE_BASE_CHARGE }
        'E_WIDE_SQUARE_FEET'              { $evResponseData=$evResponseData.E_WIDE_SQUARE_FEET }
        'E_primary_employee'              { $evResponseData=$evResponseData.E_primary_employee }
        'FALLEN_TERM'                     { $evResponseData=$evResponseData.FALLEN_TERM }
        'FIXED_ASSET_NUMBER'              { $evResponseData=$evResponseData.FIXED_ASSET_NUMBER }
        'HREF'                            { $evResponseData=$evResponseData.HREF }
        'INITIAL_START'                   { $evResponseData=$evResponseData.INITIAL_START }
        'INSTALLATION_DATE'               { $evResponseData=$evResponseData.INSTALLATION_DATE }
        'INTERNAL_DELIVERY_DATE'          { $evResponseData=$evResponseData.INTERNAL_DELIVERY_DATE }
        'INTERNAL_DISPO'                  { $evResponseData=$evResponseData.INTERNAL_DISPO }
        'INVENTORY_ID'                    { $evResponseData=$evResponseData.INVENTORY_ID }
        'INVOICE_NUMBER'                  { $evResponseData=$evResponseData.INVOICE_NUMBER }
        'IS_CI'                           { $evResponseData=$evResponseData.IS_CI }
        'IS_DML'                          { $evResponseData=$evResponseData.IS_DML }
        'IS_LOCKED'                       { $evResponseData=$evResponseData.IS_LOCKED }
        'IS_SERVICE'                      { $evResponseData=$evResponseData.IS_SERVICE }
        'LAST_AUTOMATIC_DISCOVERY'        { $evResponseData=$evResponseData.LAST_AUTOMATIC_DISCOVERY }
        'LAST_INTEGRATION'                { $evResponseData=$evResponseData.LAST_INTEGRATION }
        'LAST_PAYMENT'                    { $evResponseData=$evResponseData.LAST_PAYMENT }
        'LAST_PAYMENT_CUR_ID'             { $evResponseData=$evResponseData.LAST_PAYMENT_CUR_ID }
        'LAST_PHYSICAL_INVENTORY'         { $evResponseData=$evResponseData.LAST_PHYSICAL_INVENTORY }
        'LAST_UPDATE'                     { $evResponseData=$evResponseData.LAST_UPDATE }
        'LICENSE_VERSION'                 { $evResponseData=$evResponseData.LICENSE_VERSION }
        'LOCATION.CITY'                   { $evResponseData=$evResponseData.LOCATION.CITY }
        'LOCATION.LOCATION_CODE'          { $evResponseData=$evResponseData.LOCATION.LOCATION_CODE }
        'LOCATION.LOCATION_EN'            { $evResponseData=$evResponseData.LOCATION.LOCATION_EN }
        'LOCATION.LOCATION_ID'            { $evResponseData=$evResponseData.LOCATION.LOCATION_ID }
        'LOCATION.LOCATION_PATH'          { $evResponseData=$evResponseData.LOCATION.LOCATION_PATH }
        'LOCATION_ID'                     { $evResponseData=$evResponseData.LOCATION_ID }
        'LOCATION_PATH'                   { $evResponseData=$evResponseData.LOCATION_PATH }
        'LOCATION_TO_CHECK_REQUEST_ID'    { $evResponseData=$evResponseData.LOCATION_TO_CHECK_REQUEST_ID }
        'MAINTENANCE_COST'                { $evResponseData=$evResponseData.MAINTENANCE_COST }
        'MAINTENANCE_COST_CUR_ID'         { $evResponseData=$evResponseData.MAINTENANCE_COST_CUR_ID }
        'MAIN_USAGE_ID'                   { $evResponseData=$evResponseData.MAIN_USAGE_ID }
        'MAX_INSTALLS'                    { $evResponseData=$evResponseData.MAX_INSTALLS }
        'MONTHLY_FIXED_COST'              { $evResponseData=$evResponseData.MONTHLY_FIXED_COST }
        'MONTHLY_FIXED_COST_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_FIXED_COST_CUR_ID }
        'MONTHLY_NET_RENTAL'              { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL }
        'MONTHLY_NET_RENTAL_CUR_ID'       { $evResponseData=$evResponseData.MONTHLY_NET_RENTAL_CUR_ID }
        'MONTH_DURATION'                  { $evResponseData=$evResponseData.MONTH_DURATION }
        'NETWORK_IDENTIFIER'              { $evResponseData=$evResponseData.NETWORK_IDENTIFIER }
        'NEXT_CI_VERSION'                 { $evResponseData=$evResponseData.NEXT_CI_VERSION }
        'NEXT_DEPARTMENT_ID'              { $evResponseData=$evResponseData.NEXT_DEPARTMENT_ID }
        'NEXT_DEPARTMENT_PATH'            { $evResponseData=$evResponseData.NEXT_DEPARTMENT_PATH }
        'NEXT_MAINTENANCE_DATE'           { $evResponseData=$evResponseData.NEXT_MAINTENANCE_DATE }
        'NEXT_STATUS_ID'                  { $evResponseData=$evResponseData.NEXT_STATUS_ID }
        'NEXT_USER_APPLICATION_DATE'      { $evResponseData=$evResponseData.NEXT_USER_APPLICATION_DATE }
        'NEXT_USER_ID'                    { $evResponseData=$evResponseData.NEXT_USER_ID }
        'NOTICE'                          { $evResponseData=$evResponseData.NOTICE }
        'ORDER_DETAILS_ID'                { $evResponseData=$evResponseData.ORDER_DETAILS_ID }
        'ORDER_NUMBER'                    { $evResponseData=$evResponseData.ORDER_NUMBER }
        'OWNERSHIP_TO_CHECK_REQUEST_ID'   { $evResponseData=$evResponseData.OWNERSHIP_TO_CHECK_REQUEST_ID }
        'PACKAGE_PATH'                    { $evResponseData=$evResponseData.PACKAGE_PATH }
        'PIPELINE_STATUS_ID'              { $evResponseData=$evResponseData.PIPELINE_STATUS_ID }
        'POWER_CONSUMPTION_WH'            { $evResponseData=$evResponseData.POWER_CONSUMPTION_WH }
        'PROCESSOR_COUNT'                 { $evResponseData=$evResponseData.PROCESSOR_COUNT }
        'PROCESSOR_SOCKET_COUNT'          { $evResponseData=$evResponseData.PROCESSOR_SOCKET_COUNT }
        'PROJECT_ID'                      { $evResponseData=$evResponseData.PROJECT_ID }
        'PROVIDER_ID'                     { $evResponseData=$evResponseData.PROVIDER_ID }
        'PROVIDER_PATH'                   { $evResponseData=$evResponseData.PROVIDER_PATH }
        'PURCHASE_DATE'                   { $evResponseData=$evResponseData.PURCHASE_DATE }
        'PURCHASE_PRICE'                  { $evResponseData=$evResponseData.PURCHASE_PRICE }
        'PURCHASE_PRICE_CUR_ID'           { $evResponseData=$evResponseData.PURCHASE_PRICE_CUR_ID }
        'PURCHASE_RATE_ID'                { $evResponseData=$evResponseData.PURCHASE_RATE_ID }
        'RECYCLED_DATE'                   { $evResponseData=$evResponseData.RECYCLED_DATE }
        'RECYCLING_PROVIDER_ID'           { $evResponseData=$evResponseData.RECYCLING_PROVIDER_ID }
        'RECYCLING_PROVIDER_PATH'         { $evResponseData=$evResponseData.RECYCLING_PROVIDER_PATH }
        'REFORM_NUMBER'                   { $evResponseData=$evResponseData.REFORM_NUMBER }
        'REMOVED_DATE'                    { $evResponseData=$evResponseData.REMOVED_DATE }
        'RENEWAL_DECISION_ID'             { $evResponseData=$evResponseData.RENEWAL_DECISION_ID }
        'RENEWAL_VALUE'                   { $evResponseData=$evResponseData.RENEWAL_VALUE }
        'RENEWAL_VALUE_CUR_ID'            { $evResponseData=$evResponseData.RENEWAL_VALUE_CUR_ID }
        'REPAIRED_BY_ID'                  { $evResponseData=$evResponseData.REPAIRED_BY_ID }
        'REPAIRED_BY_PATH'                { $evResponseData=$evResponseData.REPAIRED_BY_PATH }
        'REQUEST_ID'                      { $evResponseData=$evResponseData.REQUEST_ID }
        'RESALES_VALUE'                   { $evResponseData=$evResponseData.RESALES_VALUE }
        'SCHEDULED_END'                   { $evResponseData=$evResponseData.SCHEDULED_END }
        'SD_CATALOG_ID'                   { $evResponseData=$evResponseData.SD_CATALOG_ID }
        'SD_CATALOG_PATH'                 { $evResponseData=$evResponseData.SD_CATALOG_PATH }
        'SD_DEFAULT_INCIDENT_ID'          { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_ID }
        'SD_DEFAULT_INCIDENT_PATH'        { $evResponseData=$evResponseData.SD_DEFAULT_INCIDENT_PATH }
        'SD_DEFAULT_REQUEST_ID'           { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_ID }
        'SD_DEFAULT_REQUEST_PATH'         { $evResponseData=$evResponseData.SD_DEFAULT_REQUEST_PATH }
        'SERIAL_NUMBER'                   { $evResponseData=$evResponseData.SERIAL_NUMBER }
        'SERVER_TYPE_ID'                  { $evResponseData=$evResponseData.SERVER_TYPE_ID }
        'SLA_ID'                          { $evResponseData=$evResponseData.SLA_ID }
        'STATUS_ID'                       { $evResponseData=$evResponseData.STATUS_ID }
        'SUPPLIER_ID'                     { $evResponseData=$evResponseData.SUPPLIER_ID }
        'SUPPLIER_PATH'                   { $evResponseData=$evResponseData.SUPPLIER_PATH }
        'TERM'                            { $evResponseData=$evResponseData.TERM }
        'UPDATED_BY_DISCOVERY'            { $evResponseData=$evResponseData.UPDATED_BY_DISCOVERY }
        'UPDATE_COVERAGE_TERM'            { $evResponseData=$evResponseData.UPDATE_COVERAGE_TERM }
        'WARANTY_TYPE_ID'                 { $evResponseData=$evResponseData.WARANTY_TYPE_ID }
        'XPOS'                            { $evResponseData=$evResponseData.XPOS }
        'YPOS'                            { $evResponseData=$evResponseData.YPOS }
        'ZPOS'                            { $evResponseData=$evResponseData.ZPOS }
      } # Switch $evOption

      If ($evResponseData) {

        Write-Host "$evOption returned for $evAssetID" -ForegroundColor $evFGColorInfo

      } Else {
        Write-Host "$evOption unavailable for $evAssetID." -ForegroundColor $evFGColorBad
        $evResponseData = '---'
      }# If !$evResponseData

    }#Process

    End {

      return $evResponseData

    }#End

  } # Get-EVAssetDetailByAsssetID

  Function Add-EVAsset {
    <#
        .SYNOPSIS
        "Add-EVAsset" function

        .DESCRIPTION
        This function adds an asset/configuration item record to the EasyVista database.

        .PARAMETER evAssetName
        The network or device name of the asset.

        .PARAMETER evAssetDesc
        A desription of the Asset in its role or function.

        .PARAMETER evCatalogID
        CatalogID is required to create the asset.

        .PARAMETER evAssetTag
        The asset tag that is assigned to that asset.

        .PARAMETER evAcquistionType
        This parameter is typicall virtual.

        .PARAMETER evLocationID
        The location of the asset as defined by the location id.

        .PARAMETER evInstallDate
        Date of installation

        .PARAMETER evDepartmentID
        Department ID of who the asset belongs.

        .PARAMETER evReleaseGrp
        The particluar release group for change managment.

        .PARAMETER evIsCI
        This defines whether the asset should have an assigned Configuration Item.

        .PARAMETER evCIStatusID
        The CI Status ID is either 1 or 0.  Default is 1 for active.

        .PARAMETER evCustomer
        The employee name assigned to the asset.

        .PARAMETER evSerialNumber
        Serial number of the asset.

        .PARAMETER evModel
        The model of the asset as defind in the Asset Catalog.

        .PARAMETER evIPAddress
        The static IP address being consumed by the device/asset.  DHCP if not set statically.

        .PARAMETER evOrderNumber
        The Purchase Order for the acquired asset.

        .PARAMETER evStatusID
        The status of the asset that is currently assigned.  Typicall...production.

        .PARAMETER evWarrantyNum
        The warranty number of the assigned asset if know.

        .PARAMETER evEndWarranty
        The end date on the warranty based on the maintenance purchase agreement.  Typically 5 years/60 months.

        .PARAMETER evNotes
        Notes that describe further detail about the asset or its use.

        .PARAMETER evinputCSV
        The input CSV if used to automatically create the asset record.

        .PARAMETER evSaveReport
        The option to save the report as an Excel file.

        .EXAMPLE
        Add-EVAsset -evAssetName Value -evAssetDesc Value -evCatalogID Value -AssetTag Value -AcquistionType Value -LocationID Value -evInstallDate Value -DepartmentID Value -ReleaseGrp Value -IsCI Value -CIStatusID Value -Customer Value -SerialNumber Value -Model Value -IPAddress Value -OrderNumber Value -StatusID Value -WarrantyNum Value -EndWarranty Value -Notes Value -inputCSV Value -SaveReport

        .EXAMPLE
        Add-EVAsset -evAssetName "ITROCKS" -evAssetDesc 'APC UPS' -evCatalogID (Get-EVManufactuerCatalogId -Manufacturer APC -Model SRT6KRMXLT) -AssetTag "765401" -AcquistionType Virtual -LocationID 1086 -evInstallDate '07/23/2019' -DepartmentID 2719 -ReleaseGrp 3 -IsCI 1 -CIStatusID 1 -Customer 'Ford, Timothy' -SerialNumber "1234567$NUM" -Model SRT6KRMXLT -IPAddress '10.245.3.150' -OrderNumber "123456789" -StatusID 8 -WarrantyNum "123456789" -EndWarranty '07/26/2022' -Notes "Deployed via REST. TF."

        .EXAMPLE
        Add-EVAsset -evAssetName "1234567$NUM" -evAssetDesc 'Backup Unit' -evCatalogID (Get-EVManufactuerCatalogId -Manufacturer APC -Model SRT6KRMXLT) -AssetTag "1234567$NUM" -AcquistionType Virtual -LocationID 1086 -evInstallDate '07/23/2019' -DepartmentID 2719 -ReleaseGrp 3 -IsCI 1 -CIStatusID 1 -Customer 'Ford, Timothy' -SerialNumber "1234567$NUM" -Model SRT6KRMXLT -IPAddress '192.168.1.21' -OrderNumber "1234567$NUM" -StatusID 8 -WarrantyNum "1234567$NUM" -EndWarranty '07/23/2022' -Notes "test $NUM"

        Use of variablized parameters.


        .NOTES
        None

        .LINK
        None

        .INPUTS
        See list of parameters

        .OUTPUTS
        A record is created in EasyVista.
    #>


    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$true,
      HelpMessage='Enter a hostname, system name, or computer name.')]
      [ValidatePattern('^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$')]
      [string]$evAssetName,
      [string]$evAssetDesc,
      [string]$evCatalogID,
      [string]$evAssetTag,
      [String]$evAcquistionType,
      [string]$evLocationID,
      [string]$evInstallDate,
      [string]$evDepartmentID,
      [string]$evReleaseGrp,
      [string]$evIsCI,
      [string]$evCIStatusID,
      [string]$evCustomer, # NEXT_USER_ID from AM_EMPLOYEE
      [string]$evSerialNumber,
      [string]$evModel, ## Returns Catalog_id
      [string]$evIPAddress,
      [string]$evOrderNumber,
      [String]$evStatusID,
      [string]$evWarrantyNum,
      [Datetime]$evEndWarranty,
      [string]$evNotes,
      [string]$evInputCSV,
      [switch]$evSaveReport
    )

    $Error.clear()


    # Setup the json file to create the initial asset.
    $evJson = @"
    {
    "assets": [
      {
        "catalog_id": "$($evCatalogID)",
        "asset_tag": "$($evAssetTag)",
        "serial_number": "$($evSerialNumber)",
        "status_id": "$($evStatusID)",
        "comment_asset": "$($evAssetDesc)",
        "NETWORK_IDENTIFIER": "$($evAssetName.ToUpper())",
        "installation_date": "$($evInstallDate)",
        "ORDER_NUMBER": "$($evOrderNumber)"
       }
    ]
  }
"@

    # Setup the json file to update the asset without a CI but add additional items for devices.
    $evJson2 = @"
      {
        "ASSET_TAG": "$($evAssetTag)",
        "NETWORK_IDENTIFIER": "$($evAssetName.ToUpper())",
        "SERIAL_NUMBER": "$($evSerialNumber)",
        "ORDER_NUMBER": "$($evOrderNumber)",
        "STATUS_ID": $($evStatusID),
        "INSTALLATION_DATE": "$($evInstallDate)",
        "AVAILABLE_FIELD_4": "$($evWarrantyNum)",
        "END_OF_WARRANTY": "$($evEndWarranty)",
        "E_IP_ADDRESS": "$($evIPAddress)",
        "LOCATION_ID": "$($evLocationID)",
        "DEPARTMENT_ID": "$($evDepartmentID)",
        "COMMENT_ASSET": "ASSET CREATED ON $($global:evDate) VIA REST API'S.",
        "E_NOTES": "$($evNotes)"
      }
"@

    # Setup the json file to update the asset with additional items to include a CI.
    $evJson2CI = @"
      {
        "ASSET_TAG": "$($evAssetTag)",
        "NETWORK_IDENTIFIER": "$($evAssetName.ToUpper())",
        "SERIAL_NUMBER": "$($evSerialNumber)",
        "ORDER_NUMBER": "$($evOrderNumber)",
        "STATUS_ID": $($evStatusID),
        "INSTALLATION_DATE": "$($evInstallDate)",
        "AVAILABLE_FIELD_4": "$($evWarrantyNum)",
        "END_OF_WARANTY": "$($evEndWarranty)",
        "E_IP_ADDRESS": "$($evIPAddress)",
        "LOCATION_ID": "$($evLocationID)",
        "DEPARTMENT_ID": "$($evDepartmentID)",
        "COMMENT_ASSET": "ASSET CREATED ON $($global:evDate) VIA REST API'S.",
        "E_NOTES": "$($evNotes)",
        "IS_CI": $evIsCI,
        "CI_STATUS_ID": $evCIStatusID,
        "E_RLS_MANAGING_GROUP": "$($evReleaseGrp)"
      }
"@

    $evUrl = $evAssetsUrl

    Try {
      $evHrefResponse = Invoke-RestMethod -Method Post -Uri $evUrl -Headers $global:evHeader -Body $evJson  -ContentType 'application/json'  -ErrorVariable Crap
      $AssetURL = $($evHrefResponse.href -replace ('http:','https:'))

      $evAssetID = (($evHrefResponse.href) -split 'assets/')[1]
      Write-Host "Adding $($evAssetName.ToUpper())  to EasyVista." -ForegroundColor $evFGColorInfo
      Write-Host "New Asset reference url = $($evHrefResponse.href -replace ('http:','https:'))"  -ForegroundColor $evFGColorInfo
      Write-Host "New Asset ID = $evAssetID" -ForegroundColor $evFGColorNum
    } Catch {
      # get error record
      [Management.Automation.ErrorRecord]$e = $_

      # retrieve information about runtime error
      $info = [PSCustomObject]@{
        Exception = $e.Exception.Message
        Reason    = $e.CategoryInfo.Reason
        Target    = $e.CategoryInfo.TargetName
        Script    = $e.InvocationInfo.ScriptName
        Line      = $e.InvocationInfo.ScriptLineNumber
        Column    = $e.InvocationInfo.OffsetInLine
      }

      # output information. Post-process collected info, and log info (optional)
      $info

      if ($crap -like '*1 id error*') {
        Write-Warning "Duplicate record error. Check for asset tag ($evAssetTag) in EasyVista."
        #Write-Warning "$evUrl\$evAssetID"
      }
      if ($info.Exception -like 'The remote server returned an error: (400) Bad Request'){
        Write-Warning "Possible duplicate record. Check for asset tag ($evAssetTag) in EasyVista."
      }

    }

    Try {
      If ($AssetURL) {

        If ($evIsCI) {
          $null = Invoke-RestMethod -Method Put -Uri $AssetURL -Headers $global:evHeader -Body $evJson2CI  -ContentType 'application/json'  -ErrorVariable Crap
        } Else {
          $null = Invoke-RestMethod -Method Put -Uri $AssetURL -Headers $global:evHeader -Body $evJson2  -ContentType 'application/json'  -ErrorVariable Crap
        }

      } Else {
        Write-Warning 'There seems to be a problem with obtaining the asset url.'
      }

    } Catch {
      Write-Warning 'There seems to be a problem with updating new asset update.'
    }

    <#   # Items need to make the asset a CI.
        {
        "E_NOTES": "Updated Date via REST API",
        "E_IP_ADDRESS": "192.168.1.15",
        "IS_CI": 1,
        "CI_STATUS_ID": 1,
        "STATUS_ID": "8"
        }

        # or

        # if the Asset has a discard date it will not show up in the Available filter
        {
        "E_NOTES": "Updated Date via REST API",
        "E_IP_ADDRESS": "192.168.1.15",
        "INVOICE_NUMBER": "1234567",
        "IS_CI": 1,
        "CI_STATUS_ID": 1,
        "REMOVED_DATE": "",
        "END_OF_WARRANTY": "07/19/2024",
        "STATUS_ID": "8",
        "LOCATION": {
        "CITY": "Meridian",
        "LOCATION_CODE": "142",
        "LOCATION_EN": "Boise",
        "LOCATION_PATH": "Boise",
        "LOCATION_ID": "1086"
        }
        }


        $Title = "Easy Vista New Asset"
        $evBase = $evAssetName
        $evJsonFile = "$($evBase).json"
        $evCsvFile = "$($evBase).csv"
        $evHtml = "$($evBase).html"
        #$evTempPath = 'C:\temp'
        $evTempPath = $env:TEMP
        $evJsonOutFile = "$evTempPath\$evJsonFile"
        $CsvOutFile = "$evTempPath\$evCsvFile"
        $evHtmlOutFile = "$evTempPath\$evHtml"

        If ($evAssetID) {
        $evJson | Out-File -FilePath "$evJsonOutFile"
        }

        $var = (get-content -Path $evJsonOutFile) | ConvertFrom-Json
        $var




        <#  $CSVdata = Import-Csv -LiteralPath $evInputCSV
        $SystemIP = ($CSVdata | Select-Object -Property hostname, SystemIP | Read-hostname).SystemIP
        $evIPAddress = $SystemIP
        $APCModel = ($CSVdata | Select-Object -Property hostname, Model | Read-hostname).Model
        $APCModel

        # Capture APC model info.
        $evXlsxfile = 'EasyVista APC Models.xlsx'
        $workSheetName = 'EasyVista APC Models'
        $evUrl = 'https://powereng-qualif.easyvista.com/api/v1/50004/catalog-assets?search=manufacturer.manufacturer~"APC*"&fields=Catalog_id,Article_model'
        $APCs = Invoke-RestMethod -Method GET -Uri $evUrl -Headers $global:evHeader
        #$APCs.records | Export-Csv -LiteralPath "$evWorkingPath\EasyVista-apc-models-$global:evDateStamp.csv"  -NoTypeInformation
        $APCs.records | Export-Excel -Path $evWorkingPath\$evXlsxfile -WorkSheetname $workSheetName  -AutoSize
        Write-Host "Record Count: $($APCs.records.Count)" -ForegroundColor Yellow

        # Get Catalog_id
        $xlsxdata = Import-Excel -Path "$evWorkingPath\$evXlsxfile" -WorksheetName $workSheetName
        $Catalog_id = ($xlsxdata | select Article_Model, Catalog_id | Where-Object {$_.Article_Model -like "$APCModel"}).catalog_id
        If (! $evCatalogID){
        Write-Warning "You seem to be missing catalog_id information."
        break
        }
    #>
    #>
  }# Function Add-EVAsset

  Function Update-EVAsset {
    <#
        .SYNOPSIS
        "Update-EVAsset" function to update an asset.

        .DESCRIPTION
        This function will apply updates to specified asset items as identified by the parameter name.

        .PARAMETER evAssetName
        The asset name is the same as the device or network name.

        .PARAMETER evIsCI
        Defines whether a Configuration item exists or should be created.

        .PARAMETER evCIStatusID
        Describes the CI Status.

        .PARAMETER evNewAssetName
        Used only when renaming an asset in EasyVista.

        .PARAMETER evAssetDesc
        Description of the asset.

        .PARAMETER evCatalogID
        The CatalogID that will be assigned to the asset.

        .PARAMETER evAssetTag
        The Asset Tag used.

        .PARAMETER evAcquistionType
        Typically - Virtual

        .PARAMETER evLocationID
        The location of the asset as identified by the LocationID

        .PARAMETER evInstallDate
        Installation Date.

        .PARAMETER evDepartmentID
        DepartmentID number

        .PARAMETER evReleaseGrp
        The particular release group assigned to the CI.

        .PARAMETER evCustomer
        Describes the customer who may be accountable for the asset.

        .PARAMETER evSerialNumber
        Serial number of the asset.

        .PARAMETER evModel
        Model defined.

        .PARAMETER evIPAddress
        IP Address if used/assigned.

        .PARAMETER evOrderNumber
        The purchase order number.

        .PARAMETER evStatusID
        Status id of the asset. See function get-help Get-EVStatus -Full

        .PARAMETER evWarrantyNum
        Describe parameter -WarrantyNum.

        .PARAMETER evEndWarranty
        Describe parameter -EndWarranty.

        .PARAMETER evNotes
        Describe parameter -Notes.

        .PARAMETER evinputCSV
        Describe parameter -inputCSV.

        .PARAMETER evSaveReport
        Describe parameter -SaveReport.

        .EXAMPLE
        Update-EVAsset -evAssetName Value -evIsCI Value -evCIStatusID Value -evNewAssetName Value -evAssetDesc Value -evCatalogID Value -evAssetTag Value -evAcquistionType Value -LocationID Value -evInstallDate Value -evDepartmentID Value -evReleaseGrp Value -evCustomer Value -evSerialNumber Value -evModel Value -evIPAddress Value -evOrderNumber Value -evStatusID Value -evWarrantyNum Value -evEndWarranty Value -evNotes Value -inputCSV Value -evSaveReport
        Describe what this call does

        .NOTES
        None

        .LINK
        None.

        .INPUTS
        Status name or Status ID

        .OUTPUTS
        The Status name or Status ID depending on the input.
    #>


    Param(
      [Parameter(ParameterSetName='p1',Mandatory=$true,HelpMessage='Enter a hostname, system name, or computer name.')]
      [ValidatePattern('^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$')]
      [string]$evAssetName,

      [Parameter(ParameterSetName='p1',Mandatory=$true,HelpMessage='You must specify either (0 or 1)')]
      [ValidateSet('1','0')]
      [string]$evIsCI=1,

      [Parameter(ParameterSetName='p1',Mandatory=$true,HelpMessage='You must specify either (0, 1, or 4)')]
      [ValidateSet('0','1','4')]
      [string]$evCIStatusID=1,

      [Parameter(ParameterSetName='p2',Mandatory=$True)]
      [string]$evAssetID,

      [string]$NewAssetName,
      [string]$evAssetDesc,
      [string]$evCatalogID,
      [string]$evAssetTag,
      [String]$evAcquistionType,
      [string]$evLocationID,
      [string]$LastUpdate = $global:evDate,
      [string]$evInstallDate,
      [string]$evDepartmentID,
      [string]$evReleaseGrp,
      [string]$evCustomer, # NEXT_USER_ID from AM_EMPLOYEE
      [string]$evSerialNumber,
      [string]$evModel, ## Returns Catalog_id
      [string]$evIPAddress,
      [string]$evOrderNumber,
      [String]$evStatusID,
      [string]$evWarrantyNum,
      [Datetime]$evEndWarranty,
      [string]$evNotes,
      [string]$evInputCSV,
      [switch]$evSaveReport,
      [switch]$Discard
    )



    $Error.clear()
    $paramoption = $PsCmdlet.ParameterSetName

    switch ($paramoption) {
      'p1' {
        # Get some data.
        Try {
          $evAssetNameDetail = Get-EVAssetDetailByAssetName -evHostname $evAssetName -evOption ALL-Data

          $evAssetID = $evAssetNameDetail.ASSET_ID    # Get-EVAssetDetailByAssetName -evHostname $evAssetName -evOption ASSET_ID
          $evAssetHREF = ($evAssetNameDetail.href -replace ('http:','https:'))     #  Get-EVAssetDetailByAssetName -evHostname $evAssetName -evOption HREF
          $AssetHasCI = $evAssetNameDetail.is_ci    # Get-EVAssetDetailByAssetName -evHostname $evAssetID -evOption IS_CI
          $evAssetNameDetail
        } Catch {
          Write-Warning -Message "Could not locate asset $evAssetName by name."
          break
        }
      }
      'p2' {
        # Get some data.
        Try {
          $evAssetNameDetail = Get-EVAssetDetailByAssetID -evAssetID $evAssetID -evOption ALL-Data

          $evAssetID = $evAssetNameDetail.ASSET_ID    # Get-EVAssetDetailByAssetName -evHostname $evAssetName -evOption ASSET_ID
          $evAssetHREF = ($evAssetNameDetail.href -replace ('http:','https:'))      #  Get-EVAssetDetailByAssetName -evHostname $evAssetName -evOption HREF
          $AssetHasCI = $evAssetNameDetail.is_ci    # Get-EVAssetDetailByAssetName -evHostname $evAssetID -evOption IS_CI
          $evAssetNameDetail
        } Catch {
          Write-Warning -Message "Could not locate an assetid of $evAssetID."
          break
        }
      }

    }



    # Start with an empty Json file.
    $evJsonCI = @'
  {
  }
'@

      # Cleanup any previous files not cleaned up from a broken process.

    Try {
      If (Test-Path $global:evJsonAssetFile) {
        Remove-Item $global:evJsonAssetFile -Force -Confirm:$false -ErrorAction SilentlyContinue
      }
    } Catch {

    }

    # Start with an empty Json file.
    $evJsonCI | Set-Content $global:evJsonAssetFile

    # Convert Json file to a standard key-value pair.
    $evJson = Get-Content $global:evJsonAssetFile | Out-String | ConvertFrom-Json

    $evReport = @()

    $evMember = ''

    # Append passed updated parameters.
    IF ($NewAssetName) {
      $evJson | Add-Member -MemberType NoteProperty -Name 'NETWORK_IDENTIFIER' -Value "$($NewAssetName.toUpper())"
      $evMember += "NETWORK_IDENTIFIER: $NewAssetName`n"
    }
    IF ($evAssetTag) {
      $evJson | Add-Member -MemberType NoteProperty -Name 'ASSET_TAG' -Value "$($evAssetTag.ToUpper())"
      $evMember += "ASSET_TAG: $evAssetTag`n"
    }
    IF ($evModel) {
      $evJson | Add-Member -MemberType NoteProperty -Name 'Model' -Value "$evCatalogID"
      $evMember += "CATALOG_ID: $evModel`n"
    }
    IF ($evCatalogID) {
      $evJson | Add-Member -MemberType NoteProperty -Name 'CATALOG_ID' -Value "$evCatalogID"
      $evMember += "CATALOG_ID: $evCatalogID`n"
    }
    If ($evSerialNumber) {
      $evJson | Add-Member -MemberType NoteProperty -name 'SERIAL_NUMBER' -value "$evSerialNumber"
      $evMember += "SERIAL_NUMBER: $evSerialNumber`n"
    }
    If ($evOrderNumber) {
      $evJson | Add-Member -MemberType NoteProperty -Name 'ORDER_NUMBER' -Value "$evOrderNumber"
      $evMember += "ORDER_NUMBER: $evOrderNumber`n"
    }
    If ($evStatusID) {
      $evJson | Add-Member -MemberType NoteProperty -name 'STATUS_ID' -value "$evStatusID"
      $evMember += "STATUS_ID: $evStatusID`n"
    }
    If ($evInstallDate) {
      $evJson | Add-Member -MemberType NoteProperty -name 'INSTALLATION_DATE' -value "$evInstallDate"
      $evMember += "INSTALLATION_DATE: $evInstallDate`n"
    }
    If ($evWarrantyNum) {
      $evJson | Add-Member -MemberType NoteProperty -name 'AVAILABLE_FIELD_4' -value "$evWarrantyNum"
      $evMember += "AVAILABLE_FIELD_4: $evWarrantyNum`n"
    }
    If ($evEndWarranty) {
      $evJson | Add-Member -MemberType NoteProperty -name 'END_OF_WARANTY' -value "$evEndWarranty"
      $evMember += "END_OF_WARANTY: $evEndWarranty`n"
    }
    If ($evLocationID) {
      $evJson | Add-Member -MemberType NoteProperty -name 'LOCATION_ID' -value "$evLocationID"
      $evMember += "LOCATION_ID: $evLocationID`n"
    }
    If ($evDepartmentID) {
      $evJson | Add-Member -MemberType NoteProperty -name 'DEPARTMENT_ID' -value "$evDepartmentID"
      $evMember += "DEPARTMENT_ID: $evDepartmentID`n"
    }
    If ($evAssetDesc) {
      $evJson | Add-Member -MemberType NoteProperty -name 'COMMENT_ASSET' -value "$evAssetDesc - Created on $($global:evDate) via Rest API."
      $evMember += "COMMENT_ASSET: $evAssetDesc`n"
    }
    If ($evNotes) {
      $evJson | Add-Member -MemberType NoteProperty -name 'E_NOTES' -value "$evNotes"
      $evMember += "$evNotes`n"
    }
    If ($evIsCI) {
      $evJson | Add-Member -MemberType NoteProperty -name 'IS_CI' -value "$evIsCI"
      $evMember += "IS_CI: $evIsCI`n"
    }
    If ($evCIStatusID) {
      $evJson | Add-Member -MemberType NoteProperty -name 'CI_STATUS_ID' -value "$evCIStatusID"
      #$evMember += "CI_STATUS_ID: $evCIStatusID`n"
    }
    If ($evReleaseGrp) {
      $evJson | Add-Member -MemberType NoteProperty -name 'E_RLS_MANAGING_GROUP' -value "$evReleaseGrp"
      $evMember += "E_RLS_MANAGING_GROUP: $evReleaseGrp`n"
    }
    If ($evIPAddress) {
      $evJson | Add-Member -MemberType NoteProperty -name 'E_IP_ADDRESS' -value "$evIPAddress"
      $evMember += "E_IP_ADDRESS: $evIPAddress`n"
    }
    # Add the Discard Date (if the Discard switch is used) as today's date.
    If ($Discard) {
      $evJson | Add-Member -MemberType NoteProperty -name 'REMOVED_DATE' -value "$global:evDate"
      $evMember += "REMOVED_DATE: $global:evDate`n"
    } Else {
       # Remove the Discard Date (if the Discard switch is not used).
      $global:evDateRemoved = ''
      $evJson | Add-Member -MemberType NoteProperty -name 'REMOVED_DATE' -value "$global:evDateRemoved"
      $evMember += "REMOVED_DATE: $global:evDateRemoved`n"
    }


      # Update the record.
      $evJson | Add-Member -MemberType NoteProperty -name 'LAST_UPDATE' -value "$LastUpdate"
      $evMember += "LAST_UPDATE: $LastUpdate`n"

    # Add the last physical inventory as today's date.
      $evJson | Add-Member -MemberType NoteProperty -name 'LAST_PHYSICAL_INVENTORY' -value "$global:evDate"
      $evMember += "LAST_PHYSICAL_INVENTORY: $global:evDate`n"

     #Write-Host $evMember

    $evJson | ConvertTo-Json | Set-Content $global:evJsonAssetFile

    $evJsonCI = Get-Content $global:evJsonAssetFile

    Remove-Item $global:evJsonAssetFile -Force -Confirm:$false -ErrorAction SilentlyContinue

    # Set URL.
    $evUrl = ('{0}' -f $evAssetHREF)


    Try {
      If ($evAssetID) {

        If ($AssetHasCI) {
          $null = Invoke-RestMethod -Method Put -Uri $evUrl -Headers $global:evHeader -Body $evJsonCI  -ContentType 'application/json'  -ErrorVariable Crap
          # Create a report of what was updated.

          Write-Host ('Updated {0}.' -f $evAssetName) -ForegroundColor $evFGColorInfo

        } Else {

          $null = Invoke-RestMethod -Method Put -Uri $evUrl -Headers $global:evHeader -Body $evJson  -ContentType 'application/json'  -ErrorVariable Crap
          If ($NewAssetName) {
             $NewAssetName = $evAssetName.ToUpper()
          }

          Write-Host ('Updated {0}' -f $evAssetName) -ForegroundColor $evFGColorInfo
        }

      } Else {
        Write-Host  ('Update Failed for {0}' -f $evAssetName)
      }

    } Catch {
      Write-Warning 'There seems to be a problem with updating new asset update.'
    }

    If ($evMember){
      Write-Host "Items:`n $evMember" -ForegroundColor $evFGColorInfo
    }
  }# Function Update-EVAsset

  Function Get-EVRequestDataFromHref([string]$evUrl) {
    <#
        .SYNOPSIS
        Use this function to gather the HTML (HREF) Reference to an item.

        .DESCRIPTION
        Function returns the data from a given HREF.

        .PARAMETER url
        The -url provided via a REST API refernce.

        .EXAMPLE
        Get-EVRequestDataFromHref -url <Value>

        .EXAMPLE
        Get-EVRequestDataFromHref -url "/api/v1/50004/requests/CHG002077/comment"

        .EXAMPLE
        Get-EVRequestDataFromHref -url "/api/v1/50004/requests/CHG002077"

        .EXAMPLE
        (Get-EVRequestDataFromHref -url "/api/v1/50004/requests/CHG002077").REQUESTOR_IP_ADDRESS

        .NOTES
        None.

        .LINK
        None

        .INPUTS
        HREF

        .OUTPUTS
        Details of the request or incident as defined by the HREF.
    #>


    # Make the GET request

    $evUrl = ('{0}{1}' -f $global:evBaseurl, $evUrl)
    $evResponseData = Invoke-RestMethod -Uri $evUrl -Method Get -Headers $global:evHeader #-UseBasicParsing

    return $evResponseData
  }# Function Get-EVDataFromHref

  Function Get-ScriptPath {
    <#
        .SYNOPSIS
        Describe purpose of "Get-ScriptPath" in 1-2 sentences.

        .DESCRIPTION
        Add a more complete description of what the function does.

        .EXAMPLE
        Get-ScriptPath
        Describe what this call does

        .NOTES
        Place additional notes here.

        .LINK
        URLs to related sites
        The first link is opened by Get-Help -Online Get-ScriptPath

        .INPUTS
        List of input types that are accepted by this function.

        .OUTPUTS
        List of output types produced by this function.
    #>
    $runfromise = (Test-Path -Path variable:global:psISE)
    If (! $runfromise) {
      return Get-PSScriptRoot
    } Else {
      return Get-ScriptRoot
    }
  }#Function Get-ScriptPath

  Function Get-PSScriptRoot {
      <#
          .SYNOPSIS
          Describe purpose of "Get-PSScriptRoot" in 1-2 sentences.

          .DESCRIPTION
          Add a more complete description of what the function does.

          .EXAMPLE
          Get-PSScriptRoot
          Describe what this call does

          .NOTES
          Place additional notes here.

          .LINK
          URLs to related sites
          The first link is opened by Get-Help -Online Get-PSScriptRoot

          .INPUTS
          List of input types that are accepted by this function.

          .OUTPUTS
          List of output types produced by this function.
      #>

      $ScriptRoot = ''
      Try {
        $ScriptRoot = Get-Variable -Name PSScriptRoot -ValueOnly -ErrorAction Stop
      } Catch {
        $ScriptRoot = Split-Path -Path $script:MyInvocation.MyCommand.Path
      }
      Write-Output -InputObject ('{0}' -f $ScriptRoot)
    }# Function Get-

  Function Get-ScriptRoot {
      <#
          .SYNOPSIS
          Describe purpose of "Get-ScriptRoot" in 1-2 sentences.

          .DESCRIPTION
          Add a more complete description of what the function does.

          .EXAMPLE
          Get-ScriptRoot
          Describe what this call does

          .NOTES
          Place additional notes here.

          .LINK
          URLs to related sites
          The first link is opened by Get-Help -Online Get-ScriptRoot

          .INPUTS
          List of input types that are accepted by this function.

          .OUTPUTS
          List of output types produced by this function.
      #>


      if ($psise) {Split-Path -Path $psise.CurrentFile.FullPath}
      else {$global:PSScriptRoot}
    }# Function Get-ScriptRoot

  Function Out-LogFile {
      <#
        .SYNOPSIS
        Writes data to a log file

        .DESCRIPTION
        Writes data to a log file. The format of the log file attempts to mimic the logging
        used by Configuration Manager, so that the log files will render nicely using cmtrace.

        .PARAMETER logText
        This is the string that will be written to the log file

        .PARAMETER overwrite
        By default, log file entries are appended to the specified log file. If this switch is specified,
        the log file will be overwritten.

        .PARAMETER logFile
        The name of the log file where messages will be written.
      #>
      [cmdletbinding()]
      Param (
          [String]$logText,
          [Switch]$overwrite,
          [String]$logFile=$logFile
      )
      #Do nothing if no log file is defined
      if (($logFile -eq $null) -or ($logFile -eq '')) {
          return
      } else {
          #Create the time stamp for the log entry
          $time = Get-Date -Format HH:mm:ss.fff
          $offset = ([int](Get-Date -Format %z)*-60).ToString().PadLeft(3,'0').PadLeft(4,'+')
          $day = Get-Date -Format MM-dd-yyyy
          if($MyInvocation.ScriptName -ne ''){
              $component = $MyInvocation.ScriptName | Split-Path -Leaf
          }else{
              $component =  'ISE or PS Console'
          }
          $string = "<![LOG[$logText]LOG]!>"+
              "<time=`"$time$offset`" "+
              "date=`"$day`" "+
              "component=`"$component`" "+
              "context=`"$env:USERNAME`" "+
              "type=`"1`" "+
              "thread=`"$PID`" "+
              "file=`"$component`">"
          #Write the data to the log file
          Write-Verbose $logText
          $string | Out-File  -FilePath $logFile -Force -Encoding utf8 -Append:$(!$overwrite)
      }#End else
  }#End Out-Log Function

  Function Invoke-PutWebRequestWithBody([string]$evUrl, [string]$body) {
    # Make the PUT request
    $evResponseData = Invoke-WebRequest -Uri $evUrl -Method PUT -Headers $global:evHeader -Body "$body" -ContentType 'application/json'

    Write-Host "$evResponseData"
    return $evResponseData
  }# Function Send-PutRequestWithBody WIP


  <#

  #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  #  Global Common environment variables.
  #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  # Company
  $global:evSite ="POWER Engineers"
  # SMTP server address
  $global:evSmtpSrv ="smtp.powereng.com"
  # Email Sender
  $global:evEmailFrom ="bdc-mgmt01@powereng.com"
  # Email To
  $global:evEmailTo ="timothy.ford@powereng.com"
  # Email subject
  $global:evEmailSubject=('{0} - EasyVista Report' -f $global:evSite)

  #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Dot source variables script again.
  #. C:\windows\System32\WindowsPowerShell\v1.0\Modules\POWER-ENG.EasyVista\POWER-ENG.EasyVista-Variables.ps1
  #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  $global:evDate = (get-Date -Format MM/dd/yyyy )
  $global:evDateStamp = (get-Date -Format MM-dd-yyyy )
  $global:evTempPath = $env:TEMP
  $global:evTitle = 'POWER-ENG.EasyVista Module'
  $global:evCatalogWorkingPath = ('{0}\{1}' -f $global:evWorkingPath, $global:evWorkingTitle)

  $global:evBase = 'EV_Request'
  $global:evJsonAssetFile = ('{0}\{1}.json' -f $evTempPath, $env:Computername)
  $global:evJsonFile = ('{0}-{1}.json' -f , $global:evDateStamp)
  $global:evCsvFile = ('{0}-{1}.csv' -f $evBase, $global:evDateStamp)
  $global:evHtml = ('{0}.html' -f ($evBase))
  $global:evJsonOutFile = ('{0}\{1}' -f $evTempPath, $evJsonFile)
  $global:evCsvOutFile = ('{0}\{1}' -f $evTempPath, $evCsvFile)
  $global:evHtmlOutFile = ('{0}\{1}' -f $evTempPath, $evHtml)
  $global:evFGColorInfo = 'Yellow'
  $global:evFGColorBad = 'Red'
  $global:evFGColorNum = 'Green'
  $global:evFGColorVerbose = 'Cyan'
  $global:evInputCSV = '\\boifs1\ITxchange\Automation\APC-UPS-Builds\Production Builds\APC-UPS-Deployed-Builds.csv'

  Write-Host $global:evTitle -ForegroundColor $evFGColorInfo
  Write-Host "Module Version:$global:evModuleVersion" -ForegroundColor $evFGColorNum
  # Get variables after doing work.
  #$evMyNewVariables = Get-Variable -Name *ev*

  Write-Verbose "Employee URL: $global:evEmployeeUrl"
  Write-Verbose "Asset URL: $global:evAssetsUrl"
  Write-Verbose "Request URL: $global:evRequestsUrl"
  Write-Verbose "Catalog Asset URL: $global:evCatalogAssetUrl"
  Write-Verbose "Configuration Item URL: $global:evConfigItemstUrl"
  Write-Verbose "Loaction URL: $global:evLocationUrl"
  Write-Verbose "Status URL: $global:evStatusUrl"
  Write-Verbose "Maxium Rows: $global:evMaxRows"

  #>
  Function Clear-evVariables {

    $vars = Get-Variable -name * -scope Global  | Where-Object {$_.Name -match [regex] "^ev[A-Z][a*-z*A*-Z*]"}

    Write-host ('Clearing EasyVista environment variables') -ForegroundColor Cyan

    Foreach ($Var in $vars) {

      Write-host "Removing Variable $($var.name)" -ForegroundColor Yellow

      Remove-Variable -Name $($var.name) -Scope Global -Force -Confirm:$false
    }

   }



   <#
      export-modulemember -Function '*ev*'

      $manifest = @{
      Path           = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules\POWER-ENG.EasyVista\POWER-ENG.EasyVista.psd1'
      RootModule     = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules\POWER-ENG.EasyVista\POWER-ENG.EasyVista.psm1'
      Author         = 'Timothy Ford'
      CompanyName    = 'POWER Engineers, Inc.'
      ModuleVersion  = '1.4.0.0'
      Description    = 'Provides functions for automating tasks for EasyVista.'
      }

  New-ModuleManifest @manifest#>
