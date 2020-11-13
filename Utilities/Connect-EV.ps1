class clsEasyVistaConnection
{
    [String] $restUser = [String]::Empty
    [String] $baseURL = [String]::Empty
    [String] $apiPath = [String]::Empty
    [String] $environment = [String]::Empty

    $global:evRestUser = 'infrastructureapi'
    $global:evBaseurl = "https://powereng.easyvista.com"
    $global:evAapiPath = "api/v1/50004"
    $global:evEnvironment = 'Prod'

    clsEasyVistaConnection([String] $user, [String] $url, [String] $apiPath, [String] $environment)
    {
        $this.restUser = $user
        $this.baseURL = $url
        $this.apiPath = $apiPath
        $this.environment = $environment
    }
}
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
