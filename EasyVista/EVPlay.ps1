$global:evWorkingPath = "\\boifs1\ITxchange\Automation"
$global:evEasyVistaModule = "POWER-ENG.EasyVista"

$EVEnvironment = "Q05" # Prod, Q04, Q05

Switch ($EVEnvironment) {
    'Prod' {
      $global:evRestUser = "infrastructureapi"
      $global:evBaseurl = "https://powereng.easyvista.com"
      $global:evAapiPath = "api/v1/50004"
      $global:evEnvironment = "Prod"
    }

    'Q04' {
      $global:evRestUser = "restapiq04"
      $global:evBaseurl = "https://powereng-qualif.easyvista.com"
      $global:evAapiPath = "api/v1/50004"
      $global:evEnvironment = "Q04"
    }

    'Q05' {
      $global:evRestUser = "restapiq05"
      $global:evBaseurl = "https://powereng-qualif.easyvista.com"
      $global:evAapiPath = "api/v1/50005"
      $global:evEnvironment = "Q05"
    }


  } # Switch($EVEnvironment)

$global:evKeyFile = "$global:evWorkingPath\$global:evEasyVistaModule\$global:evEnvironment\EV-$global:evEnvironment-AES.key"
$global:evKey = Get-Content $global:evKeyFile

$global:evPasswordFile = "$global:evWorkingPath\$global:evEasyVistaModule\$global:evEnvironment\EV-$global:evEnvironment-APIkey.txt"

$evPassword = Get-Content $global:evPasswordFile | ConvertTo-SecureString -Key $global:evKey
$evBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($evPassword)
$evUnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($evBSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($evBSTR)
Write-Host ("{0}" -f @([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($evUnsecurePassword))))
$global:evApi_key = ('Basic ' + $evUnsecurePassword)  ####



$global:evHeader = @{"Authorization" = ("{0}" -f @($global:evApi_key)) }

$uri = "https://powereng.easyvista.com/api/v1/50004/assets{0}&max_rows=9999&search=ASSET_ID~{1,2:D2}*" -f @($assetFieldsURIPrefix, $a)
$evResponseData = Invoke-RestMethod -Uri $uri -Method Get -Headers $global:evHeader
