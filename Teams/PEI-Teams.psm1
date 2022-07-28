#Requires -Modules @{ ModuleName = "AzureAD"; ModuleVersion = "2.0" }
#Requires -Modules @{ ModuleName = "MicrosoftTeams"; ModuleVersion = "4.0.0" }

<#
    NOTES:  VMWare modules interfere with MicrosoftTeams.  Need to use a no-profile powershell to avoid loading the incorrect assemblies
#>

function Connect-ToAzureADAndTeams
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [Switch] $Force=$false
    )

    $pass = 1

    # If we haven't checked connectivity, or the last test is stale, or we are forced, reset variables and retest.
    if(($null -eq $Global:LastTestedServiceConnectivity) -or ([DateTime]::Now.AddHours(-6) -ge $Global:LastTestedServiceConnectivity) -or ($Force))
    {
        # TRUE

        try
        {
            [void] (Disconnect-AzureAD -ErrorAction Stop)
        }
        catch
        {
            # Nothing -- probably not connected...
        }

        try
        {
            [void] (Disconnect-MicrosoftTeams -ErrorAction Stop)
        }
        catch
        {
            # Nothing -- probably not connected...
        }
        $Global:AzureADTenantDetails = $null
        $Global:TeamsCompanyInformation = $null
        $Global:LastTestedServiceConnectivity = $null
    }
    else # NOT (($null -eq $Global:LastTestedServiceConnectivity) -or ([DateTime]::Now.AddHours(6) -lt $Global:LastTestedServiceConnectivity) -or ($Force))
    {
        # FALSE

        # We've tested for connectivity within the past 6 hours, and have not been forced to test so...
        # ... set $pass to 10 so the while loop is bypassed.
        $pass = 10
    }

    <#
        Pass #1:
            Try to retrieve company information from Microsoft Azure AD and Teams as a
            way to test for connectivity to each service.

            If I'm unable to retrieve the information, I'll then attempt to connect to whichever service data source failed

        Pass #2:
            Retry to get the necessary company data from each service provider.
            Do not try to connect again, just fail.
    #>
    while((($null -eq $Global:AzureADTenantDetails) -or ($null -eq $Global:TeamsCompanyInformation)) -and ($pass -le 2))
    {
        # Try to retrieve company information from Microsoft Online and Teams
        try
        {
            # If I haven't retrieved the Microsoft Azure AD tenant details, then try to get it.
            if($null -eq $Global:AzureADTenantDetails)
            {
                # TRUE

                $Global:AzureADTenantDetails = Get-AzureADTenantDetail -ErrorAction Stop
            }
            else # NOT ($null -eq $Global:AzureADTenantDetails)
            {
                # FALSE

                # Nothing, already have Microsoft Azure AD tenant details.
            }

            # If I haven't retrieved the Microsoft Teams company information, then try to get it.
            if($null -eq $Global:TeamsCompanyInformation)
            {
                # TRUE

                $Global:TeamsCompanyInformation = Get-CSTenant -ErrorAction Stop
            }
            else # NOT ($null -eq $Global:TeamsCompanyInformation)
            {
                # FALSE

                # Nothing, already have Microsoft Teams company information.
            }
        }
        catch
        {
            # Nothing, I'll check data after the try-catch for errors.
        }

        # If we did not get the Microsoft Azure AD tenant details and this is pass #1, then
        #    try to connect to Microsoft Azure AD.
        if(($null -eq $Global:AzureADTenantDetails) -and ($pass -eq 1))
        {
            # TRUE

            try
            {
                Write-Host -ForegroundColor Green "`r`nNOTICE: There may be a popup window behind other applications waiting for you to authenticate to Azure AD.`r`n"
                [void] (Connect-AzureAD -ErrorAction Stop)
            }
            catch
            {
                $pass = 10  # Skip any more tries if we cannot connect to Microsoft Azure AD
                Write-Host -ForegroundColor Red "ERROR: Failed to connect to Microsoft Azure AD."
            }
        }
        else # NOT (($null -eq $Global:AzureADTenantDetails) -and ($pass -eq 1))
        {
            # FALSE

            # Nothing, already have Microsoft Azure AD tenant details, or we are not on pass #1
        }

        # If we did not get the Microsoft Teams company information and this is the first time through the loop (and connecting to Microsoft
        #    Azure AD did not fail), then try to connect to Microsoft Teams.
        if(($null -eq $Global:TeamsCompanyInformation) -and ($pass -eq 1))
        {
            # TRUE

            try
            {
                Write-Host -ForegroundColor Green "`r`nNOTICE: There may be a popup window behind other applications waiting for you to authenticate to Microsoft Teams.`r`n"
                [void] (Connect-MicrosoftTeams -ErrorAction Stop)
            }
            catch
            {
                $pass = 10  # Skip any more tries if we cannot connect to Microsoft Teams
                Write-Host -ForegroundColor Red "ERROR: Failed to connect to Microsoft Teams."
            }
        }
        else # NOT (($null -eq $Global:TeamsCompanyInformation) -and ($tries -eq 1))
        {
            # FALSE

            # Nothing, already have Microsoft Teams company information, or we are not on pass #1
        }

        $pass++
    }

    $Global:LastTestedServiceConnectivity = [DateTime]::Now

    return ($null -ne $Global:AzureADTenantDetails) -and ($null -ne $Global:TeamsCompanyInformation)
}

function Get-PhoneSystemVirtualUserSkuId
{
    if([String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
    {
        # TRUE

        if(Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Populate $Global:phoneSystemVirtualUserSkuId
            try
            {
                $subscribedSKUs = Get-AzureADSubscribedSku -ErrorAction Stop
                $Global:phoneSystemVirtualUserSkuId = ($subscribedSKUs | Where-Object { $_.SkuPartNumber -eq "PHONESYSTEM_VIRTUALUSER" }).SkuId

                # Create the license structures needed to add the PHONESYSTEM_VIRTUALUSER license to/from an account
                $license =  [Microsoft.Open.AzureAD.Model.AssignedLicense]::new()
                $license.SkuId = $Global:phoneSystemVirtualUserSkuId

                # Add the PHONESYSTEM_VIRTUALUSER license
                $Global:AddPhoneSystemVirtualUserLicenses = [Microsoft.Open.AzureAD.Model.AssignedLicenses]::new()
                $Global:AddPhoneSystemVirtualUserLicenses.AddLicenses = $license

                # Remove the PHONESYSTEM_VIRTUALUSER license
                $Global:RemovePhoneSystemVirtualUserLicenses = [Microsoft.Open.AzureAD.Model.AssignedLicenses]::new()

                # NOTE: For the remove operation, .RemoveLicenses only needs a list of GUIDs (SKU IDs) to remove vs a list of [Microsoft.Open.AzureAD.Model.AssignedLicense] objects
                $Global:RemovePhoneSystemVirtualUserLicenses.RemoveLicenses = $Global:phoneSystemVirtualUserSkuId
            }
            catch
            {
                Write-Host -ForegroundColor Red "ERROR: Failed to retrieve PHONESYSTEM_VIRTUALUSER SKU ID from Microsoft Azure AD."
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would already have been displayed
        }
    }
    else # NOT ([String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
    {
        # FALSE

        # Nothing, already set.
    }

    return (-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
}

function Invoke-WithRetries
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Scriptblock] $cmdToExecute,

        [Parameter(Mandatory=$true,Position=1)]
        [Object[]] $cmdArgs,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $retval = $null

    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
    {
        Write-Host -ForegroundColor Green -NoNewline $message
    }

    $tries = 0
    do
    {
        $tries++
        $needToRetry = $false

        try
        {
            # Clear existing errors
            $Error.Clear()

            $retVal = Invoke-Command -ScriptBlock $cmdToExecute -ArgumentList $cmdArgs -ErrorAction stop
            $success = $true
        }
        catch
        {
            # An exception was thrown setting the user's location...so handle it
            $needToRetry = $tries -lt $maxRetries

            # Pause/write another '.' only if we are going to retry...
            if($needToRetry)
            {
                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host -ForegroundColor Green -NoNewline "."
                }
                Start-Sleep -Milliseconds $retryDelay
            }
            else
            {
                $success = $false
            }
        }
    }
    while($needToRetry)

    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
    {
        Write-Host "" # Close the open output line...
    }

    return @($success, $retval)
}

function Test-PhoneNumberValid
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $PhoneNumber,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $isValid = $false

    if (-not [String]::IsNullOrEmpty($phoneNumber))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            $scriptBlock = {
                param($pn) Get-CsOnlineTelephoneNumber -TelephoneNumber $pn -WarningAction SilentlyContinue -ErrorAction Stop
            }
            $success, $retval = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($phoneNumber) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput

            $isValid = ($success) -and ($null -ne $retval)
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Not connected to online services, so I couldn't test the phone number so leave $isValid -eq $false
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($phoneNumber))
    {
        # FALSE

        # Nothing, $phoneNumber is not valid, so leave $isValid -eq $false
    }

    return $isValid
}

function Get-ResourceAccountByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $appInstance = $null

    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Scriptblock to execute...
            $scriptBlock = {
                param($upn) Get-CsOnlineApplicationInstance -Identity $upn -ErrorAction Stop
            }
            $success, $appInstance = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($userPrincipalName) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would already have been displayed
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while retrieving resource account."
    }

    return $appInstance
}

function New-ResourceAccount
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $displayName,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch] $VerboseOutput=$false
    )

    $newResourceAccount = $null
    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (-not [String]::IsNullOrEmpty($displayName))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                # Make sure there isn't already a resource account with a matching user principal name.
                $existingResourceAccount = Get-ResourceAccountByUPN -userPrincipalName $UserPrincipalName -message ("Checking for an existing resource account with user principal name: {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput
                if ($null -eq $existingResourceAccount)
                {
                    # TRUE

                    # There was not a resource account with userPrincipalName -eq $UserPrincipalName
                    try
                    {
                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host -ForegroundColor Green $message
                        }

                        # Create the ApplicationInstance object -- This is the "Resource Account"  -- it's just a "special" Azure AD user.
                        $newResourceAccount = New-CsOnlineApplicationInstance -UserPrincipalName $userPrincipalName -ApplicationId "11cd3e2e-fccb-42ad-ad00-878b93575e07" -DisplayName $displayName -ErrorAction Stop
                        <#
                            https://docs.microsoft.com/en-us/powershell/module/skype/new-csonlineapplicationinstance?view=skype-ps

                                Application IDs:
                                    Auto Attendant: ce933385-9390-45d1-9512-c8d228074e07
                                    Call Queue:     11cd3e2e-fccb-42ad-ad00-878b93575e07
                        #>
                    }
                    catch
                    {
                        # Nothing, leave $newResourceAccount -eq $null
                    }
                }
                else # NOT ($null -eq $existingResourceAccount)
                {
                    # FALSE

                    # There is an existing resource account with userPrincipalName -eq $UserPrincipalName
                    Write-Host -ForegroundColor Red ("ERROR: A resource account already exists with user principal name: {0} while creating resource account." -f @($userPrincipalName))
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error would have already been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($displayName))
        {
            # FALSE

            Write-Host -ForegroundColor Red "ERROR: Missing display name while creating resource account."
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while creating resource account."
    }

    return $newResourceAccount
}

function Get-AzureADUserByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $azADUser = $null
    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Scriptblock to execute...
            $scriptBlock = {
                param($upn) Get-AzureADUser -ObjectId $upn -ErrorAction Stop
            }
            $success, $azADUser = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($userPrincipalName) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while trying to retrieve Azure AD user."
    }

    return $azADUser
}

function Set-UsageLocation
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $country,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if(-not [String]::IsNullOrEmpty($country))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host -ForegroundColor Green $message
                }

                try
                {
                    [void] (Set-AzureADUser -ObjectId $userPrincipalName -UsageLocation $country -Country $country -ErrorAction Stop)
                    $azADUser = Get-AzureADUserByUPN -userPrincipalName $userPrincipalName -message ("Verifying usage location is set to {0} for {1}..." -f @($country, $userPrincipalName)) -VerboseOutput:$VerboseOutput
                    $success = ($null -ne $azADUser) -and ($azADUser.UsageLocation -eq $country)
                }
                catch
                {
                    # Nothing, leave $success -eq $false
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error message would have already been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($country))
        {
            Write-Host -ForegroundColor Red ("ERROR: Missing country while trying to set resource account location.")
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while trying to set resource account location.")
    }

    return $success
}


function Test-UserForPhoneSystemVirtualUserLicense
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [Microsoft.Open.AzureAD.Model.User] $azADUser = $null
    )

    $hasLicense = $false
    if (Connect-ToAzureADAndTeams)
    {
        # TRUE

        if (Get-PhoneSystemVirtualUserSkuId)
        {
            # TRUE

            $hasLicense = ($null -ne $azADUser) -and
                          ($null -ne $azADUser.AssignedLicenses) -and
                          ($null -ne $azADUser.AssignedPlans) -and
                          ($null -ne ($azADUser.AssignedLicenses | Where-Object { $_.SkuId -eq $Global:phoneSystemVirtualUserSkuId })) -and
                          ($null -ne ($azADUser.AssignedPlans | Where-Object { $_.Service -eq "MicrosoftCommunicationsOnline"}))
        }
        else # NOT (Get-PhoneSystemVirtualUserSkuId)
        {
            # FALSE

            # Nothing, an error would have already been displayed.
        }
    }
    else # NOT (Connect-ToAzureADAndTeams)
    {
        # FALSE

        # Nothing, an error would have already been displayed.
    }

    return $hasLicense
}

function Test-ForPhoneSystemVirtualUserLicense
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false
    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            if (Get-PhoneSystemVirtualUserSkuId)
            {
                # TRUE

                $azADUser = Get-AzureADUserByUPN -userPrincipalName $userPrincipalName -message $message -VerboseOutput:$VerboseOutput
                $success = Test-UserForPhoneSystemVirtualUserLicense -azADUser $azADUser
            }
            else # NOT (Get-PhoneSystemVirtualUserSkuId)
            {
                # FALSE

                # Nothing, an error would have already been displayed.
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while checking for PHONESYSTEM_VIRTUALUSER license.")
    }

    return $success
}

function Add-PhoneSystemVirtualUserLicense
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Make we have retrieved the PHONESYSTEM_VIRTUALUSER SKU ID
            if (Get-PhoneSystemVirtualUserSkuId)
            {
                # TRUE

                $azADUser = Get-AzureADUserByUPN -userPrincipalName $userPrincipalName -message ("Verifying {0} exists." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
                if ($null -ne $azADUser)
                {
                    # TRUE

                    # Make sure the account's usage location is set prior to trying to assign the PHONESYSTEM_VIRTUALUSER license
                    if (-not [String]::IsNullOrEmpty($azADUser.UsageLocation))
                    {
                        # TRUE

                        # If the account does not have the PHONESYSTEM_VIRTUALUSER license assigned...
                        if (-not (Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Checking to see if PHONESYSTEM_VIRTUALUSER is assigned to {0}..." -f @($userPrincipalName)) -maxRetries 0 -VerboseOutput:$VerboseOutput))
                        {
                            # TRUE

                            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                            {
                                Write-Host -NoNewline -ForegroundColor Green $message
                            }

                            # Then try to assign it.
                            try
                            {
                                Set-AzureADUserLicense -ObjectId $azADUser.ObjectId -AssignedLicenses $Global:AddPhoneSystemVirtualUserLicenses -ErrorAction Stop
                                $success = Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Verifying PHONESYSTEM_VIRTUALUSER is assigned to {0}..." -f @($userPrincipalName)) -maxRetries 50 -VerboseOutput:$VerboseOutput
                            }
                            catch
                            {
                                # Nothing, leave $success -eq $false
                            }
                        }
                        else # NOT (-not (Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Checking to see if PHONESYSTEM_VIRTUALUSER is assigned to {0}..." -f @($userPrincipalName)) -maxRetries 0 -VerboseOutput:$VerboseOutput))
                        {
                            # FALSE

                            $success = $true   # Not technically true, but the resource account is already assigned the PHONESYSTEM_VIRTUALUSER license
                        }
                    }
                    else # NOT (-not [String]::IsNullOrEmpty($azADUser.UsageLocation))
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red ("ERROR: Cannot assigned PHONESYSTEM_VIRTUALUSER license to {0} without first setting usage location." -f @($userPrincipalName))
                    }
                }
                else # NOT ($null -ne $azADUser)
                {
                    # FALSE

                    # Nothing.
                }
            }
            else # NOT (Get-PhoneSystemVirtualUserSkuId)
            {
                # FALSE

                # Nothing, an error would have already been displayed.
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while trying to assign PHONESYSTEM_VIRTUALUSER license.")
    }

    return $success
}

function Set-UserPhoneNumberAssignment
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $phoneNumber,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if(-not [String]::IsNullOrEmpty($phoneNumber))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                # Assign phone number to the resource account.
                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host -ForegroundColor Green -NoNewline $message
                }

                try
                {
                    # If Set-CsPhoneNumberAssignment fails, it returns an object.  So to avoid having extraneous output on the script, surpress it.
                    [void] (Set-CsPhoneNumberAssignment -Identity $userPrincipalName -PhoneNumber $phoneNumber -PhoneNumberType "CallingPlan" -ErrorAction Stop)
                    $success = $true
                }
                catch
                {
                    # Nothing, leave $success -eq $false
                }

                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host ""
                }

                if($success)
                {
                    # TRUE

                    # Verify usage location to be assigned
                    if($VerboseOutput)
                    {
                        Write-Host -ForegroundColor Green -NoNewline ("Waiting/verifying {0} was successfully assigned to {1}." -f @($phoneNumber, $userPrincipalName))
                    }

                    # Cannot use Invoke-WithRetries here since I have to test return values.
                    $tries = 0
                    do
                    {
                        $tries++
                        $needToRetry = $false
                        try
                        {
                            $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -VerboseOutput:$VerboseOutput
                            $success = ($null -ne $resourceAccount) -and (-not [String]::IsNullOrEmpty($resourceAccount.PhoneNumber)) -and ($resourceAccount.PhoneNumber.Contains($phoneNumber))
                        }
                        catch
                        {
                            # Set $success to false since the first action (above) would have set it to $true
                            $success = $false
                        }

                        if(-not $success)
                        {
                            # TRUE

                            # I've already determined we don't have the proper information in the if conditional, now I just need to set $needToRetry based on how many times we've already tried.
                            $needToRetry = $tries -lt $maxRetries

                            # Pause/write another '.' only if we are going to retry...
                            if($needToRetry)
                            {
                                if($VerboseOutput)
                                {
                                    Write-Host -ForegroundColor Green -NoNewline "."
                                }
                                Start-Sleep -Milliseconds $retryDelay
                            }
                            else
                            {
                                # Nothing, leave $success -eq $false
                            }
                        }
                        else # NOT (-not $success)
                        {
                            # FALSE

                            # Nothing
                        }
                    }
                    while($needToRetry)
                    if($VerboseOutput)
                    {
                        Write-Host "" # Close the open output line...
                    }
                }
                else # NOT ($success)
                {
                    # FALSE

                    # Nothing, leave $success -eq $false
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error would have already been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($phoneNumber))
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Phone number not provided while trying to set user's phone number.")
            $success = $false
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while assigning phone number to resource account."
    }

    return $success
}

function Get-CallQueueByName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $callQueueName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $callQueue = $null
    if (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            $scriptBlock = {
                param($cqn) Get-CsCallQueue -NameFilter $cqn -WarningAction SilentlyContinue -ErrorAction Stop
               }
            $success, $callQueue = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($callQueueName) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would already have been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to retrieve call queue.")
    }

    return $callQueue
}

function New-CallQueue
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $callQueueName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $newCQ = $null
    if (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # TRUE

        if (-not [String]::IsNullOrEmpty($userPrincipalName))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                # Make sure there isn't already a call queue with $callQueueName
                $existingCallQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} does not already exist." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                if ($null -eq $existingCallQueue)
                {
                    # TRUE
                    # No call queue exists with name $callQueueName

                    # Get the resource account that is to be associated with the new call queue.
                    $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $UserPrincipalName -message ("Retrieving resource account {0} to be assigned to {1}.." -f @($userPrincipalName, $callQueueName)) -VerboseOutput:$VerboseOutput
                    if ($null -ne $resourceAccount)
                    {
                        # TRUE

                        # Time to create the call queue
                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host -ForegroundColor Green $message
                        }

                        <#
                            The parameter list for New-CsCallQueue is quite long, so I'm going to splat it...
                        #>

                        $newCallQueueParams = @{
                            Name = $callQueueName
                            AllowOptOut = $false
                            LanguageId = "en-US"
                            OverflowAction = "Forward"
                            OverflowActionTarget = $resourceAccount.ObjectID
                            OverflowThreshold = 1
                            TimeoutAction = "Forward"
                            TimeoutActionTarget = $resourceAccount.ObjectID
                            TimeoutThreshold = 0
                            UseDefaultMusicOnHold = $true
                            WarningAction = "SilentlyContinue"
                            ErrorAction = "Stop"
                        }

                        try
                        {
                            # Clear any existing errors.
                            $Error.Clear()

                            $newCQ = New-CsCallQueue @newCallQueueParams
                            if($null -ne $newCQ)
                            {
                                $newCQ = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} was created..." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                            }
                            else
                            {
                                # Nothing, leave $success -eq $false
                            }
                        }
                        catch
                        {
                            # Nothing, leave $success -eq $false
                        }
                    }
                    else # NOT ($null -ne $resourceAccount)
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve resource account for {0}." -f @($userPrincipalName))
                    }
                }
                else # NOT ($null -eq $existingCallQueue)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Call queue with name {0} already exists." -f @($callQueueName))
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error would have already been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Resource account user principal name while trying to create call queue.")
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to create call queue.")
    }

    return $newCQ
}

function Get-ApplicationInstanceAssociationByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $accountAssociation = $null
    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Retrieving resource account {0}." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
            if ($null -ne $resourceAccount)
            {
                # TRUE

                $scriptBlock = {
                    param($objID) Get-CsOnlineApplicationInstanceAssociation -Identity $objID -ErrorAction Stop
                }
                $success, $accountAssociation = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($resourceAccount.objectID) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
            }
            else # NOT ($null -ne $resourceAccount)
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve resource account {0} while trying to retrieve application association." -f @($userPrincipalName))
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would already have been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Green "ERROR: User principal name while trying to retrieve application instance association."
    }

    return $accountAssociation
}

function Set-CallQueueResourceAccount
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $callQueueName,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $newCqAssoc = $null
    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (-not [String]::IsNullOrEmpty($callQueueName))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Retrieving resource account {0}." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
                if ($null -ne $resourceAccount)
                {
                    # TRUE

                    $callQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Retrieve call queue {0}." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                    if ($null -ne $callQueue)
                    {
                        # TRUE

                        $accountAssociation = Get-ApplicationInstanceAssociationByUPN -userPrincipalName $userPrincipalName -message ("Checking for existing application instance associations for {0}." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
                        if ($null -eq $accountAssociation)
                        {
                            # TRUE
                            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                            {
                                Write-Host -ForegroundColor Green $message
                            }

                            try
                            {
                                # Associate the RA account with the new call queue
                                [void] (New-CsOnlineApplicationInstanceAssociation -Identities @($resourceAccount.ObjectId) -ConfigurationId $callQueue.Identity -ConfigurationType "CallQueue" -ErrorAction Stop)
                                $newCqAssoc = Get-ApplicationInstanceAssociationByUPN -userPrincipalName $userPrincipalName -message ("Verifying resource account was associated to call queue.") -VerboseOutput:$VerboseOutput
                            }
                            catch
                            {
                                # Nothing, just return $null for $newCqAssoc
                            }
                        }
                        else # NOT ($null -eq $accountAssociation)
                        {
                            # FALSE

                            Write-Host -ForegroundColor Red ("ERROR: There is an existing application instance association for {0}." -f @($userPrincipalName))
                        }
                    }
                    else # NOT ($null -ne $callQueue)
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve call queue {0} while trying to associate resource account to the call queue." -f @($callQueueName))
                    }
                }
                else # NOT ($null -ne $resourceAccount)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve resource account {0} while trying to associate resource account to the call queue." -f @($userPrincipalName))
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error message would have already been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($callQueueName))
        {
            # FALSE

            Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to associate resource account to the call queue.")
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: No resource account user principal name provided while trying to associate resource account to the call queue.")
    }

    return $newCqAssoc
}

function Remove-CallQueueByName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $callQueueName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false
    $removedCallQueue = $null

    if (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Make sure there is a call queue named $callQueueName
            $existingCallQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} exists." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
            if ($null -ne $existingCallQueue)
            {
                # TRUE

                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host -ForegroundColor Green $message
                }

                try
                {
                    # Clear any existing errors
                    $Error.Clear()

                    # Try to remove the existing call queue.
                    $removedCallQueue = Remove-CsCallQueue -Identity $existingCallQueue.Identity -ErrorAction Stop
                    if($null -ne $removedCallQueue)
                    {
                        $existingCallQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} was removed..." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                        $success = ($null -eq $existingCallQueue)
                    }
                    else
                    {
                        # Nothing, leave $success -eq $false
                    }
                }
                catch
                {
                    # Nothing, leave $success -eq $false
                }
            }
            else # NOT ($null -ne $existingCallQueue)
            {
                # FALSE

                $success = $true    # Again, not technically true, but there doesn't appear to be a call queue with name -eq $callQueueName
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would have already been displayed
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($callQueueName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to remove call queue.")
    }

    return $success
}

function Remove-ResourceAccountPhoneNumberAssignment
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $phoneNumber,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (-not [String]::IsNullOrEmpty($phoneNumber))
        {
            # TRUE

            if (Connect-ToAzureADAndTeams)
            {
                # TRUE

                # Make sure $userPrincipalName is a resource account
                $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Verifying {0} is a resource account." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
                if ($null -ne $resourceAccount)
                {
                    # TRUE

                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host -ForegroundColor Green -NoNewline $message
                    }

                    # Unassign phone number from the resource account.
                    try
                    {
                        [void] (Remove-CsPhoneNumberAssignment -Identity $userPrincipalName -PhoneNumber $phoneNumber -PhoneNumberType "CallingPlan" -ErrorAction Stop)

                        # Verify usage location to be assigned
                        if($VerboseOutput)
                        {
                            Write-Host -ForegroundColor Green -NoNewline ("Verifying {0} was successfully unassigned from {1}." -f @($phoneNumber, $userPrincipalName))
                        }

                        # Cannot use Invoke-WithRetries here since I have to test return values.
                        $tries = 0
                        do
                        {
                            $tries++
                            $needToRetry = $false
                            try
                            {
                                $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -VerboseOutput:$VerboseOutput
                                $success = ($null -ne $resourceAccount) -and [String]::IsNullOrEmpty($resourceAccount.PhoneNumber)
                            }
                            catch
                            {
                                # Nothing, leave $success set to $false
                            }

                            # NOTE: $success is not based solely on an exception being thrown trying to get the resource account, but also
                            #       by whether or not the phone number is still showing on the account, so handle the retry determination outside
                            #       the try-catch.
                            if(-not $success)
                            {
                                # I've already determined we don't have the proper information based on  in the if conditional, now I just need to set $needToRetry based on how many times we've already tried.
                                $needToRetry = $tries -lt $maxRetries

                                # Pause/write another '.' only if we are going to retry...
                                if($needToRetry)
                                {
                                    if($VerboseOutput)
                                    {
                                        Write-Host -ForegroundColor Green -NoNewline "."
                                    }
                                    Start-Sleep -Milliseconds $retryDelay
                                }
                                else
                                {
                                    # Nothing, leave $success -eq $false
                                }
                            }
                            else
                            {
                                # Nothing
                            }
                        }
                        while($needToRetry)
                        if($VerboseOutput)
                        {
                            Write-Host "" # Close the open output line...
                        }
                    }
                    catch
                    {
                        # Nothing, leave $success -eq $false
                    }

                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host ""
                    }
                }
                else # NOT ($null -ne $resourceAccount)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: {0} is not a resource account." -f @($userPrincipalName))
                }
            }
            else # NOT (Connect-ToAzureADAndTeams)
            {
                # FALSE

                # Nothing, an error message would already have been displayed.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($phoneNumber))
        {
            # FALSE

            Write-Host -ForegroundColor Red "ERROR: Phone number not provided while trying to unassign phone number from resource account."
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while trying to unassign phone number from resource account."
    }

    return $success
}

function Remove-ResourceAccountPhoneSystemVirtualUserLicense
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Make sure there is a resource account with $userPrincipalName
            $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Verifying {0} exists." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
            if ($null -ne $resourceAccount)
            {
                # TRUE

                # Make sure there is no phone number assigned to the resource account
                if ([String]::IsNullOrEmpty($resourceAccount.PhoneNumber))
                {
                    # TRUE

                    # Make we have retrieved the PHONESYSTEM_VIRTUALUSER SKU ID
                    if (Get-PhoneSystemVirtualUserSkuId)
                    {
                        # TRUE

                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host -NoNewline -ForegroundColor Green $message
                        }

                        # Try to unassign the PHONESYSTEM_VIRTUALUSER license.
                        #   NOTE:  I did not test for the existence of the license prior to trying to unassign to avoid 2 round-trip to Microsoft Teams.
                        #          If the license is not assigned, the I'll
                        try
                        {
                            [void] (Set-AzureADUserLicense -ObjectId $resourceAccount.ObjectId -AssignedLicenses $Global:RemovePhoneSystemVirtualUserLicenses -ErrorAction Stop)
                            $success = -not (Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Verifying PHONESYSTEM_VIRTUALUSER has been removed from {0}..." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput)
                        }
                        catch
                        {
                            # Nothing, leave $success -eq $false
                        }

                    }
                    else # NOT (Get-PhoneSystemVirtualUserSkuId)
                    {
                        # FALSE

                        # Nothing, an error would have already been displayed.
                    }
                }
                else # NOT ([String]::IsNullOrEmpty($resourceAccount.PhoneNumber))
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Resource account {0} still has phone number {1} assigned to it while trying to unassign PHONESYSTEM_VIRTUALUSER license." -f @($userPrincipalName, $resourceAccount.PhoneNumber))
                }
            }
            else # NOT ($null -ne $resourceAccount)
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: {0} is not a resource account while trying to unassign PHONESYSTEM_VIRTUALUSER license." -f @($userPrincipalName))
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while trying to unassign PHONESYSTEM_VIRTUALUSER license.")
    }

    return $success
}

function Remove-ResourceAccountByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Verifying the existence of resource account {0}" -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
            if($null -ne $resourceAccount)
            {
                # TRUE

                # Make sure there is no phone number assigned to the resource account
                if ([String]::IsNullOrEmpty($resourceAccount.PhoneNumber))
                {
                    # TRUE

                    # Ensure the PHONESYSTEM_VIRTUALUSER license has been removed
                    if (-not (Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Verifying PHONESYSTEM_VIRTUALUSER has been removed from {0}..." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput))
                    {
                        # TRUE

                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host -ForegroundColor Green $message
                        }

                        try
                        {
                            # Clear any outstanding errors.
                            $Error.Clear()

                            # Remove the Azure AD User account.
                            [void] (Remove-AzureADUser -ObjectId $resourceAccount.ObjectId -ErrorAction Stop)
                            $success = $true
                        }
                        catch
                        {
                            # Nothing, leave $success set to $false
                        }
                    }
                    else # NOT (-not (Test-ForPhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Verifying PHONESYSTEM_VIRTUALUSER has been removed from {0}..." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput))
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red ("ERROR: Resource account {0} still has the PHONESYSTEM_VIRTUALUSER license assigned while trying to remove resouce account." -f @($userPrincipalName))
                    }
                }
                else # NOT ([String]::IsNullOrEmpty($resourceAccount.PhoneNumber))
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Resource account {0} still has phone number {1} assigned to it while trying to remove resouce account." -f @($userPrincipalName, $resourceAccount.PhoneNumber))
                }
            }
            else # NOT ($null -ne $resourceAccount)
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: No resource account found matching {0} while trying to remove resource account." -f @($userPrincipalName))
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while trying to remove resource account."
    }

    return $success
}

<#
    Undo-CallForwardingFor should only be called from Set-CallForwardingFor
#>
function Undo-CallForwardingFor
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Boolean] $CallQueueCreated,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $CallQueueName,

        [Parameter(Mandatory=$true, Position=2)]
        [Boolean] $PhoneNumberAssigned,

        [Parameter(Mandatory=$true, Position=3)]
        [String] $PhoneNumber,

        [Parameter(Mandatory=$true, Position=4)]
        [Boolean] $PhoneSystemVirtualUserLicenseAssigned,

        [Parameter(Mandatory=$true, Position=5)]
        [Boolean] $ResourceAccountCreated,

        [Parameter(Mandatory=$true, Position=6)]
        [String] $UserPrincipalName,

        [Parameter(Mandatory=$false, Position=7)]
        [Switch] $VerboseOutput=$false
    )

<#
    Order of operations:

        1. Remove the call queue
        2. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
        3. Remove the phone number from the resource account
        4. Remove the resource account

    NOTE: We will not have to unassociate the resource account from the call queue.  Associating the resource account to the call queue is the last step in setting up call forwarding
          If associating the resource account to the call queue fails, then we don't have to unassociate them.
          If associating the resource account to the call queue succeeds, then we don't have to unassociate them.

          So, either way, we don't have to unassociate the resource account from the call queue.
#>

    # Make sure this function is only called from function:Set-CallForwardingFor
    $caller = (Get-PSCallStack)[1].Command

    if($caller -eq "Set-CallForwardingFor")
    {
        # TRUE

        $phoneNumberUnassigned = $false
        $phoneSystemVirtualUserLicenseUnassigned = $false

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            # Undo changes in the reverse order...

            # If a call queue was created, then remove it.
            if ($CallQueueCreated)
            {
                # TRUE

                if (Remove-CallQueueByName -callQueueName $newCallQueue.Name -message ("Removing call queue {0}." -f @($newCallQueue.Name)) -VerboseOutput:$VerboseOutput)
                {
                    # TRUE

                    Write-Host -ForegroundColor Green ("Call queue {0} was successfully removed." -f @($CallQueueName))
                }
                else # NOT (Remove-CallQueueByName -callQueueName $newCallQueue.Name -message ("Removing call queue {0}." -f @($newCallQueue.Name)) -VerboseOutput:$VerboseOutput)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red "ERROR: Failed to remove call queue.  Manual clean up may be required."
                }
            }
            else # NOT ($CallQueueCreated)
            {
                # FALSE

                # Nothing, no call queue was created, so nothing to do here.
            }

            # If the phone number was assigned to the resource account, then remove it.
            if ($phoneNumberAssigned)
            {
                # TRUE

                if (Remove-ResourceAccountPhoneNumberAssignment -userPrincipalName $UserPrincipalName -phoneNumber $PhoneNumber -message ("Unassigning {0} from {1}." -f @($PhoneNumber, $UserPrincipalName)))
                {
                    # TRUE

                    $phoneNumberUnassigned = $true
                    Write-Host -ForegroundColor Green ("Unassign {0} from {1}." -f @($PhoneNumber, $UserPrincipalName))
                }
                else # NOT (Remove-ResourceAccountPhoneNumberAssignment -userPrincipalName $UserPrincipalName -phoneNumber $PhoneNumber -message ("Unassigning {0} from {1}." -f @($PhoneNumber, $UserPrincipalName)))
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Failed to unassign {0} from {1}.  Manual clean up may be required." -f @($PhoneNumber, $UserPrincipalName))
                }
            }
            else # NOT ($assignedPhoneNumber)
            {
                # FALSE

                # Simulate phone number was unassigned.
                $phoneNumberUnassigned = $true
            }

            # If the PHONESYSTEM_VIRTUALUSER license was assigned to the resource account, remove it.
            if($phoneSystemVirtualUserLicenseAssigned)
            {
                # TRUE

                if ($phoneNumberUnassigned)
                {
                    # TRUE

                    if (Remove-ResourceAccountPhoneSystemVirtualUserLicense -userPrincipalName $UserPrincipalName -VerboseOutput:$VerboseOutput)
                    {
                        # TRUE

                        $phoneSystemVirtualUserLicenseUnassigned = $true
                        Write-Host -ForegroundColor Green ("Remove phone virtual user license from resource account {0}." -f @($UserPrincipalName))
                    }
                    else # NOT (Remove-ResourceAccountPhoneSystemVirtualUserLicense -userPrincipalName $UserPrincipalName -VerboseOutput:$VerboseOutput)
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red "ERROR: Unable to remove phone virtual user license from resource account.  Manual clean up is required."
                    }
                }
                else # NOT ($phoneNumberUnassigned)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red "ERROR: Unable to remove phone virtual user license while phone number is still assigned.  Manual clean up is required."
                }
            }
            else # NOT ($phoneSystemVirtualUserLicenseAssigned)
            {
                $phoneSystemVirtualUserLicenseUnassigned = $true  # Techincally not true, but the license was not assigned.
            }

            # Finally, if a resource account was created, then remove it.
            if($resourceAccountCreated)
            {
                # TRUE

                # Don't need to test $phoneNumberUnassigned, because $phoneSystemVirtualUserLicenseUnassigned could not be $true unless $phoneNumberUnassigned -eq $true
                if ($phoneSystemVirtualUserLicenseUnassigned)
                {
                    # TRUE

                    if(Remove-ResourceAccountByUPN -upn $UserPrincipalName -message ("Removing resource account {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                    {
                        Write-Host -ForegroundColor Green ("Removed resource account {0}." -f @($UserPrincipalName))
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to remove resource account {0}.  Manual clean up may be required." -f @($UserPrincipalName))
                    }
                }
                else # NOT ($licenseUnassigned)
                {
                    # FALSE

                    Write-Host -ForegroundColor Red ("ERROR: Unable to remove resource account {0} while phone virtual user license is still assigned.  Manual clean up is required." -f @($UserPrincipalName))
                }
            }
            else # NOT ($resourceAccountCreated)
            {
                # FALSE

                # Nothing, nothing to do.
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would already have been displayed.
        }
    }
    else # NOT ($caller -eq "Set-CallForwardingFor")
    {
        Write-Host -ForegroundColor Red "ERROR: Undo-CallForwardingFor should only be called from Set-CallForwardingFor to undo changes made in Set-CallForwardingFor."
    }
}

<#
    1. Validate parameters are provided
    2. Make sure we are connected to Azure AD and Microsoft Teams and have tenant details for each
    3. Make sure we have the SKU ID for PHONESYSTEM_VIRTUALUSER
    4. Make sure $PhoneNumber is assigned to the Microsoft Teams Tenant
    5. Create the new resource account
        a. Verify there is no matching resource account
    6. Set the usage location for the resource account
        This is required before the PHONESYSTEM_VIRTUALUSER license can be assigned to the resource account
        a. If this fails, remove the resource account
    7. Assign PHONESYSTEM_VIRTUALUSER license to the resource account
        a. If this fails, remove the resource account
    8. Assign the phone number to the resource account
        a. If this fails
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. Remove the resource account
    9. Create the call queue for the resource account
        a. If this fails:
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. Remove the phone number from the resource account
            3. Remove the resource account
    10. Associate the resource account to the call queue
        a. If this fails:
            1. Remove the call queue
            2. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            3. Remove the phone number from the resource account
            4. Remove the resource account

    If the entire process is not successful, actions are "undone" in the reverse order they were attempted based on what actions were successful.
#>

<#
.SYNOPSIS

Set up call forwarding based on the given parameters.

.DESCRIPTION

    1. Validate parameters are provided
    2. Make sure we are connected to Azure AD and Microsoft Teams and have tenant details for each
    3. Make sure we have the SKU ID for PHONESYSTEM_VIRTUALUSER
    4. Make sure $PhoneNumber is assigned to the Microsoft Teams Tenant
    5. Create the new resource account
        a. Verify there is no matching resource account
    6. Set the usage location for the resource account
        This is required before the PHONESYSTEM_VIRTUALUSER license can be assigned to the resource account
        a. If this fails, remove the resource account
    7. Assign PHONESYSTEM_VIRTUALUSER license to the resource account
        a. If this fails, remove the resource account
    8. Assign the phone number to the resource account
        a. If this fails
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. Remove the resource account
    9. Create the call queue for the resource account
        a. If this fails:
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. Remove the phone number from the resource account
            3. Remove the resource account
    10. Associate the resource account to the call queue
        a. If this fails:
            1. Remove the call queue
            2. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            3. Remove the phone number from the resource account
            4. Remove the resource account

    If the entire process is not successful, actions are "undone" in the reverse order they were attempted based on what actions were successful.

.PARAMETER UserPrincipalName
User principal name for the resource account used to forward calls

.PARAMETER DisplayName
Display name for the resource account

.PARAMETER PhoneNumber
The phone number to forward

.PARAMETER Country
The country abbreviation where the resource account is used

.PARAMETER CallQueueName
The name (display name) of the call queue

.PARAMETER UndoOnFailure
Switch parameter used to signal if the script should try to undo any changes it made while setting up the call forwarding.

.PARAMETER VerboseOutput
If specified, verbose output will be displayed.

.INPUTS
None. You cannot pipe objects to Set-CallForwardingFor

.OUTPUTS

True or false based on the success of the function.

.EXAMPLE

PS> $success = Set-CallForwardingFor -UserPrincipalName "ratestklb@powereng0.onmicrosoft.com" -DisplayName "RA Test Account KLB" -PhoneNumber "+16025625530" -Country "US" -CallQueueName "CQ Test Account KLB" -UndoOnFailure -VerboseOutput

.EXAMPLE

PS> $forwardCallForParams = @{
    UserPrincipalName = "ratestklb@powereng0.onmicrosoft.com"
    DisplayName = "RA Test Account KLB"
    PhoneNumber = "+16025625530"
    Country = "US"
    CallQueueName = "CQ Test Account KLB"
    VerboseOutput = $true
}

PS> $success = Set-CallForwardingFor @forwardCallForParams

#>

function Set-CallForwardingFor
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $UserPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $DisplayName,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $PhoneNumber,

        [Parameter(Mandatory=$false, Position=3)]
        [String] $Country,

        [Parameter(Mandatory=$false, Position=4)]
        [String] $CallQueueName,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $UndoOnFailure=$false,

        [Parameter(Mandatory=$false, Position=6)]
        [Switch] $VerboseOutput=$false
    )

    if (-not [String]::IsNullOrEmpty($UserPrincipalName))
    {
        # TRUE

        if (-not [String]::IsNullOrEmpty($DisplayName))
        {
            # TRUE

            if (-not [String]::IsNullOrEmpty($PhoneNumber))
            {
                # TRUE

                if (-not [String]::IsNullOrEmpty($Country))
                {
                    # TRUE

                    if (-not [String]::IsNullOrEmpty($CallQueueName))
                    {
                        # TRUE

                        if (Connect-ToAzureADAndTeams)
                        {
                            # TRUE

                            if (Get-PhoneSystemVirtualUserSkuId)
                            {
                                # TRUE

                                # Verify $PhoneNumber is valid...
                                if (Test-PhoneNumberValid -PhoneNumber $PhoneNumber -message ("Validating {0}." -f @($PhoneNumber)) -VerboseOutput:$VerboseOutput)
                                {
                                    # TRUE

                                    # Some variables to track what needs to be undone if an error occurs.
                                    $resourceAccountCreated = $false
                                    $phoneSystemVirtualUserLicenseAssigned = $false
                                    $callQueueCreated = $false
                                    $phoneNumberAssigned = $false

                                    # Flag the overall success of the process
                                    $successful = $false

                                    # Create a new resource account
                                    $newResourceAccount = New-ResourceAccount -userPrincipalName $UserPrincipalName -displayName $DisplayName -message ("Creating resource account for {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput
                                    if ($null -ne $newResourceAccount)
                                    {
                                        # TRUE
                                        # The resource account was successfully created.

                                        # Wait for the resource account to be available to this script.
                                        #   This may take a while.  Some tuning of maxRetries and retryDelay may be needed.
                                        $newResourceAccount = Get-ResourceAccountByUPN -userPrincipalName $UserPrincipalName -message ("Waiting for resource account {0} to be available." -f @($UserPrincipalName)) -maxRetries 25 -retryDelay 1000 -VerboseOutput:$VerboseOutput

                                        if ($null -ne $newResourceAccount)
                                        {
                                            # TRUE
                                            # The script was able to verify the resource account was created and registered with Azure AD.
                                            $resourceAccountCreated = $true

                                            if (Set-UsageLocation -userPrincipalName $UserPrincipalName -country $Country -message ("Assigning usage location {0} to {1}." -f @($Country, $UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                                            {
                                                # TRUE
                                                # The resource account's usage location was successfully set.

                                                if (Add-PhoneSystemVirtualUserLicense -userPrincipalName $UserPrincipalName -message ("Assigning PHONESYSTEM_VIRTUALUSER license to {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                                                {
                                                    # TRUE
                                                    # The PHONESYSTEM_VIRTUALUSER license was successfully assigned to the resource account, or it already had the license assigned.
                                                    $phoneSystemVirtualUserLicenseAssigned = $true

                                                    # Assign phone number to the resource account...
                                                    # Seems it can take a bit for the phone number to get associated with the resource account, so increase $maxRetries and $retryDelay...
                                                    if (Set-UserPhoneNumberAssignment -userPrincipalName $UserPrincipalName -phoneNumber $PhoneNumber -message ("Setting phone number for {0} to {1}." -f @($displayName, $phoneNumber)) -maxRetries 25 -retryDelay 2000 -VerboseOutput:$VerboseOutput)
                                                    {
                                                        # TRUE
                                                        # The phone number was successfully assigned to the resource account.
                                                        $phoneNumberAssigned = $true

                                                        # Create the call queue...
                                                        $newCallQueue = New-CallQueue -callQueueName $CallQueueName -userPrincipalName $UserPrincipalName -message ("Creating new call queue {0}." -f @($CallQueueName)) -VerboseOutput:$VerboseOutput
                                                        if ($null -ne $newCallQueue)
                                                        {
                                                            # TRUE
                                                            # The call queue was successfully created...
                                                            $callQueueCreated = $true

                                                            # Finally, associate the resouce account with the new call queue
                                                            $newAppInstanceAssociation = Set-CallQueueResourceAccount -userPrincipalName $UserPrincipalName -callQueue $newCallQueue -message "Associating resource account to call queue." -VerboseOutput:$VerboseOutput
                                                            if ($null -ne $newAppInstanceAssociation)
                                                            {
                                                                # TRUE

                                                                Write-Host -ForegroundColor Green ("Calls for {0} have successfully been forwarded to {1}." -f @($PhoneNumber, $UserPrincipalName))
                                                                $successful = $true
                                                            }
                                                            else # NOT ($null -ne $newAppInstanceAssociation)
                                                            {
                                                                # FALSE

                                                                Write-Host -ForegroundColor Red ("ERROR: Failed to associate resource account {0} to call queue: {0} for {1}." -f @($UserPrincipalName, $CallQueueName))
                                                            }
                                                        }
                                                        else # NOT ($null -ne $newCallQueue)
                                                        {
                                                            # FALSE
                                                            # The call queue was NOT successfully created...

                                                            Write-Host -ForegroundColor Red ("ERROR: Failed to create call queue: {0} for {1}." -f @($CallQueueName, $UserPrincipalName))
                                                        }
                                                    }
                                                    else # NOT (Set-UserPhoneNumberAssignment -userPrincipalName $UserPrincipalName -phoneNumber $PhoneNumber -message ("Setting phone number for {0} to {1}." -f @($displayName, $phoneNumber)) -maxRetries 25 -retryDelay 2000 -VerboseOutput:$VerboseOutput)
                                                    {
                                                        # FALSE

                                                        # The phonue number was NOT successfully assigned to the resource account.
                                                        Write-Host -ForegroundColor Red ("ERROR: Failed to set phone number for {0}." -f @($UserPrincipalName))
                                                    }
                                                }
                                                else # NOT (Add-PhoneSystemVirtualUserLicense -userPrincipalName $UserPrincipalName -message ("Assigning PHONESYSTEM_VIRTUALUSER license to {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                                                {
                                                    # FALSE
                                                    # The PHONESYSTEM_VIRTUALUSER license was NOT successfully assigned to the resource account

                                                    Write-Host -ForegroundColor Red ("ERROR: Failed to assign PHONESYSTEM_VIRTUALUSER license to {0}." -f @($UserPrincipalName))
                                                }
                                            }
                                            else # NOT (Set-UsageLocation -userPrincipalName $UserPrincipalName -country $Country -message ("Assigning usage location {0} to {1}." -f @($Country, $UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                                            {
                                                # FALSE
                                                # The resource account's usage location was NOT successfully set.

                                                Write-Host -ForegroundColor Red ("ERROR: Failed to set usage location for {0}." -f @($UserPrincipalName))
                                            }
                                        }
                                        else # NOT ($null -ne $newResourceAccount)
                                        {
                                            # FALSE

                                            # The script was NOT able to verify the resource account was created and registered with Azure AD.

                                            Write-Host -ForegroundColor Red ("ERROR: Failed to acquire Azure AD user account for resource account {0}." -f @($UserPrincipalName))
                                            Write-Host -ForegroundColor Red "ERROR: Manual clean up of resource account may be required."
                                        }
                                    }
                                    else # NOT ($null -ne $newResourceAccount)
                                    {
                                        # FALSE

                                        Write-Host -ForegroundColor Red ("ERROR: Failed to create resource account for {0}." -f ($UserPrincipalName))
                                    }
                                }
                                else # NOT (IsPhoneNumberVal -PhoneNumber $PhoneNumber -message ("Validating {0}." -f @($PhoneNumber)) -VerboseOutput:$ver)
                                {
                                    # FALSE

                                    Write-Host -ForegroundColor Red ("ERROR: {0} is invalid or not assigned to {1}." -f @($PhoneNumber, $Global:AzureADTenantDetails.DisplayName)).Replace("..",".")
                                }
                            }
                            else # NOT (Get-PhoneSystemVirtualUserSkuId)
                            {
                                # FALSE

                                Write-Host -ForegroundColor Red "ERROR: Cannot set up call forwarding without the PHONESYSTEM_VIRTUALUSER account SKU ID."
                            }
                        }
                        else # NOT (Connect-ToAzureADAndTeams)
                        {
                            # FALSE

                            Write-Host -ForegroundColor Red "ERROR: Unable to verify connectivity to Microsoft Online and/or Microsoft Teams."
                        }
                    }
                    else # NOT (-not [String]::IsNullOrEmpty($CallQueueName))
                    {
                        # FALSE

                        Write-Host -ForegroundColor Red "ERROR: Missing call queue name while trying to set up call forwarding."
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($Country))
                {
                    # FALSE

                    Write-Host -ForegroundColor Red "ERROR: Missing country while trying to set up call forwarding."
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($PhoneNumber))
            {
                # FALSE

                Write-Host -ForegroundColor Red "ERROR: Missing phone number while trying to set up call forwarding."
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($DisplayName))
        {
            # FALSE

            Write-Host -ForegroundColor Red "ERROR: Missing display name while trying to set up call forwarding."
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($UserPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while trying to set up call forwarding."
    }

    if((-not $successful) -and ($UndoOnFailure))
    {
        # TRUE
        # Something went wrong setting up the resource account and call queue, and we've been told to undo changes, so reverse any actions taken.

        # Splat the parameter to Undo-CallForwardingFor
        $undoParameters = @{
            CallQueueCreated = $callQueueCreated
            CallQueueName = $CallQueueName
            PhoneNumberAssigned = $phoneNumberAssigned
            PhoneNumber = $PhoneNumber
            PhoneSystemVirtualUserLicenseAssigned = $phoneSystemVirtualUserLicenseAssigned
            ResourceAccountCreated = $resourceAccountCreated
            UserPrincipalName = $UserPrincipalName
            VerboseOutput = $VerboseOutput
        }
        Undo-CallForwardingFor @undoParameters
    }
    else
    {
        # FALSE

        # Nothing, all went according to plan.
    }
}

function Get-CallQueueByIdentity
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [System.GUID] $callQueueId,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $callQueue = $null
    if ($null -ne $callQueueId)
    {
        # TRUE

        if ([GUID]::TryParse($callQueueId, $([ref][GUID]::Empty)))
        {
            # TRUE

            $scriptBlock = {
                param($cqID) Get-CsCallQueue -Identity $cqID -WarningAction SilentlyContinue -ErrorAction Stop
            }
            $success, $callQueue = Invoke-WithRetries -cmdToExecute $scriptBlock -cmdArgs @($callQueueId) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
        }
        else # NOT ([GUID]::TryParse($callQueueId, $([ref][GUID]::Empty)))
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ($null -ne $callQueueId)
    {
        # FALSE

        # Nothing.
    }

    return $callQueue
}

function Remove-ResourceAccountByUPNFromCallQueue
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )
    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # TRUE

        if (Connect-ToAzureADAndTeams)
        {
            # TRUE

            $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Verifying the existence of resource account {0}" -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
            if($null -ne $resourceAccount)
            {
                # TRUE

                $appAssociation = Get-ApplicationInstanceAssociationByUPN -userPrincipalName $userPrincipalName -message ("Checking for application instance associations for {0}." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
                if($null -ne $appAssociation)
                {
                    $callQueue = Get-CallQueueByIdentity -callQueueId $appAssociation.ConfigurationId -message ("Retrieving call queue associated with {0}." -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput

                    if ($null -ne $callQueue)
                    {
                        # TRUE

                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host -ForegroundColor Green $message
                        }

                        try
                        {
                            [void] (Remove-CsOnlineApplicationInstanceAssociation -Identities @($resourceAccount.ObjectId) -ErrorAction Stop)

                            # Verify the association was removed.
                            $appAssoc = Get-ApplicationInstanceAssociation -ObjectId $resourceAccount.ObjectId -message ("Verifying {0} was unassociated from {1}." -f @($resourceAccount.DisplayName, $callQueue.Name)) -VerboseOutput:$VerboseOutput
                            $success = ($null -eq $appAssoc)
                        }
                        catch
                        {
                            # Nothing, leave $success -eq $false
                        }
                    }
                    else # NOT ($null -ne $callQueue)
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve call queue with identity {0} while trying to unassociate resource account from the call queue." -f @($accountAssociation.ConfigurationId))
                    }
                }
                else # NOT ($null -ne $appAssociation)
                {
                    # FALSE

                    $success = $true  # Not techincally true, but there is no application instance association for $userPrincipalName
                }
            }
            else # NOT ($null -ne $resourceAccount)
            {
                # FALSE

                Write-Host -ForegroundColor Red ("ERROR: No resource account found matching {0} while trying to unassociate resource account from the call queue." -f @($userPrincipalName))
            }
        }
        else # NOT (Connect-ToAzureADAndTeams)
        {
            # FALSE

            # Nothing, an error message would have already been displayed.
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        # FALSE

        Write-Host -ForegroundColor Red ("ERROR: No user principal name provided while trying to unassociate resource account from the call queue.")
    }

    return $success
}

function Set-CallQueueRouting
{
    [CmdLetBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $callQueueName,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $redirectToUser,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput
    )

    if (Connect-ToAzureADAndTeams)
    {
        # Get the SKU ID for license: MCOEV
        try
        {
            $subscribedSKUs = Get-AzureADSubscribedSku -ErrorAction Stop
            $mcoevSkuID = ($subscribedSKUs | Where-Object { $_.SkuPartNumber -eq "MCOEV" }).SkuId
        }
        catch
        {
            $mcoevSkuID = $null
        }

        if (-not [String]::IsNullOrEmpty($mcoevSkuID))
        {
            # TRUE

            try
            {
                $callQueue = Get-CsCallQueue -NameFilter $callQueueName -WarningAction SilentlyContinue -ErrorAction Stop
                if ($null -ne $callQueue)
                {
                    # Get only Azure AD Users that have the MCOEV license assigned
                    try
                    {
                        $objectID = [Guid]::Parse($redirectToUser)
                        $azureADUser = @(Get-AzureADUser -ObjectId $objectID -ErrorAction Stop | Where-Object { @($_.AssignedLicenses | Where-Object { $_.SkuId -eq $mcoevSkuID }).Length -gt 0 })
                    }
                    catch
                    {
                        $azureADUser = @(Get-AzureADUser -SearchString $redirectToUser -ErrorAction Stop | Where-Object { @($_.AssignedLicenses | Where-Object { $_.SkuId -eq $mcoevSkuID }).Length -gt 0 })
                    }

                    if ($azureADUser.Length -eq 1)
                    {
                        $azureADUser = $azureADUser[0]
                        $promptMsg = "redirect calls to {0}" -f @($azureADUser.DisplayName)
                        if ($PSCmdlet.ShouldProcess($callQueue.Name, $promptMsg))
                        {
                            try
                            {
                                $changedCQ = Set-CSCallQueue -Identity $callqueue.Identity -OverflowActionTarget $azureADUser.ObjectID -TimeoutActionTarget $azureADUser.ObjectID -WarningAction SilentlyContinue -ErrorAction Stop
                                if ($null -ne $changedCQ)
                                {
                                    try
                                    {
                                        $overFlowUser = (Get-AzureADUser -ObjectId $changedCQ.OverflowActionTarget.Id -ErrorAction Stop).DisplayName
                                    }
                                    catch
                                    {
                                        $overFlowUser = $changedCQ.OverflowActionTarget.Id
                                    }
                                    try
                                    {
                                        $timeoutUser = (Get-AzureADUser -ObjectId $changedCQ.TimeoutActionTarget.Id -ErrorAction Stop).DisplayName
                                    }
                                    catch
                                    {
                                        $timeoutUser = $changedCQ.TimeoutActionTarget.Id
                                    }

                                    Write-Host -ForegroundColor Green ("Redirected {0}..." -f @($callQueue.Name))
                                    Write-Host -ForegroundColor Green ("`tOverflow: {0}" -f @($overFlowUser))
                                    Write-Host -ForegroundColor Green ("`tTimeout: {0}" -f @($timeoutUser))
                                }
                                else # NOT ($null -ne $changedCQ)
                                {
                                    Write-Host -ForegroundColor Red ("ERROR: Failed to redirect {0} to {1}.  Set-CSCallQueue returned `$null." -f @($callQueue.Name, $azureADUser.DisplayName))
                                }
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("ERROR: Failed to redirect {0} to {1}.  Set-CSCallQueue threw an exception." -f @($callQueue.Name, $azureADUser.DisplayName))
                            }
                        }
                        else # NOT ($PSCmdlet.ShouldProcess($callQueue.Name))
                        {
                            # Nothing.
                        }

                    }
                    elseif ($azureADUser.Length -gt 1)  # NOT ($azureADUser.Length -eq 1)
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Multiple enterprise voice enabled Azure AD users found matching `"{0}`".`r`n" -f @($redirectToUser))
                        Write-Host -ForegroundColor Red "Refine redirect to user to one of the following ObjectIDs, DisplayNames, or UserPrincipalNames and rerun:`r`n"
                        $maxDisplayNameLength = $azureADUser | Select-Object  @{N="ML"; E={$_.DisplayName.Length}} | Sort-Object -Property ML -Descending | Select-Object -First 1 -ExpandProperty ML
                        $maxUPNLength = $azureADUser | Select-Object  @{N="ML"; E={$_.UserPrincipalName.Length}} | Sort-Object -Property ML -Descending | Select-Object -First 1 -ExpandProperty ML

                        $formatStr = "{{0,-37}} | {{1,-{0}}} | {{2,-{1}}}" -f @($maxDisplayNameLength, $maxUPNLength)
                        Write-Host -ForegroundColor Red ($formatStr -f @("ObjectID", "DisplayName", "UserPrincipalName"))
                        Write-Host -ForegroundColor Red ([String]::new('-', (43 + $maxDisplayNameLength + $maxUPNLength)))
                        $a = 0
                        while($a -lt $azureADUser.Length)
                        {
                            Write-Host -ForegroundColor Red ($formatStr -f @($azureADUser[$a].ObjectID, $azureADUser[$a].DisplayName, $azureADUser[$a].UserPrincipalName))
                            $a++
                        }
                    }
                    else  # NOT ($azureADUser.Length -gt 1)
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve an enterprise voice enabled Azure AD user based on search string: {0}." -f @($redirectToUser))
                    }
                }
                else # NOT ($null -ne $callQueue)
                {
                    Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve call queue named: {0}.  Get-CsCallQueue returned `$null." -f @($callQueueName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve call queue named: {0}.  Get-CsCallQueue threw an exception." -f @($callQueueName))
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($mcoevSkuID))
        {
            # FALSE

            Write-Host -ForegroundColor Red "ERROR: Failed to retrieve MCOEV license SKU ID from Azure AD."
        }
    }
    else
    {
        # Nothing, Connect-ToAzureADAndTeams displays it's own errors.
    }
}

function RedirectAutoAttendant($autoAttendant, $redirectToNumber)
{
    $a = 0
    $callFlowTargetUpdated = $false
    while($a -lt $autoAttendant.CallFlows.Length)
    {
        if (($null -ne $autoAttendant.CallFlows[$a].Menu) -and ($null -ne $null -ne $autoAttendant.CallFlows[$a].Menu.MenuOptions))
        {
            $b = 0
            while($b -lt $autoAttendant.CallFlows[$a].Menu.MenuOptions.Length)
            {
                <#
                    If:
                        1) There is a call flow call target, and
                        2) The call target is type 4 (ExternalPstn), and
                        3) The call target Id matches "^tel:\d+" -- is a phone number, and
                        4) The call target Id is not already set to $redirectToNumber
                #>
                if (($null -ne $autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget) -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Type -eq 4) -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id -match "^tel:\d+") -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id -ne $redirectToNumber))
                {
                    # ...then change the call target Id to $redirectToNumber
                    Write-Host -ForegroundColor Yellow ("Changing auto attendant '{0}' call routing for call flow '{1}' from '{2}' to '{3}'." -f @($autoAttendant.Name,  $autoAttendant.CallFlows[$a].Name, $autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id, $redirectToNumber))
                    $autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id = $redirectToNumber
                    $callFlowTargetUpdated = $true
                }
                else # NOT (($null -ne $autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget) -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Type -eq 4) -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id -match "^tel:\d+") -and ($autoAttendant.CallFlows[$a].Menu.MenuOptions[$b].CallTarget.Id -ne $redirectToNumber))
                {
                    # Nothing.
                }

                $b++
            }
        }
        else # NOT (($null -ne $autoAttendant.CallFlows[$a].Menu) -and ($null -ne $null -ne $autoAttendant.CallFlows[$a].Menu.MenuOptions))
        {
            # Nothing.
        }

        $a++
    }

    return $callFlowTargetUpdated
}

function Set-AutoAttendantRouting
{
    [CmdLetBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $autoAttendantName,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $redirectToNumber,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput
    )

    if ($redirectToNumber -match "^tel:\d+$")
    {
        if (Connect-ToAzureADAndTeams)
        {
            try
            {
                $autoAttendant = Get-CsAutoAttendant -NameFilter $autoAttendantName -WarningAction SilentlyContinue -ErrorAction Stop
                if ($null -ne $autoAttendant)
                {
                    # If any of the call target Ids are changed...
                    if (RedirectAutoAttendant $autoAttendant $redirectToNumber)
                    {
                        $promptMsg = "reroute calls to {0}" -f @($redirectToNumber)
                        if ($PSCmdlet.ShouldProcess($autoAttendant.Name, $promptMsg))
                        {
                            try
                            {
                                $updatedAutoAttendant = Set-CsAutoAttendant -Instance $autoAttendant -ErrorAction Stop

                                # Make sure the change took.  If "RedirectAutoAttendant" returns $false, then none of the call targets are different than $redirectToNumber
                                if (-not (RedirectAutoAttendant $updatedAutoAttendant $redirectToNumber))
                                {
                                    Write-Host -ForegroundColor Green ("Successfully redirected '{0}' to '{1}'." -f @($autoAttendant.Name, $redirectToNumber))
                                }
                                else # NOT (-not (RedirectAutoAttendant $updatedAutoAttendant $redirectToNumber))
                                {
                                    Write-Host -ForegroundColor Red ("ERROR: Failed to redirect '{0}' to '{1}'.  Please verify." -f @($autoAttendant.Name, $redirectToNumber))
                                }
                            }
                            catch
                            {
                                Write-Host -ForegroundColor Red ("ERROR: Failed to redirect auto attendant {0} to {1}.  Set-CSAutoAttendant threw an exception." -f @($autoAttendant.Name, $redirectToNumber))
                            }
                        }
                        else
                        {

                        }
                    }
                    else # NOT ($callFlowTargetUpdated)
                    {
                        # Nothing.
                    }
                }
                else # NOT ($null -ne $autoAttendant)
                {
                    Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve auto attendant named: {0}.  Get-CsAutoAttendant returned `$null." -f @($autoAttendantName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("ERROR: Failed to retrieve auto attendant named: {0}.  Get-CsAutoAttendant threw an exception." -f @($autoAttendantName))
            }
        }
        else
        {
            # Nothing, Connect-ToAzureADAndTeams displays it's own errors.
        }
    }
    else # NOT ($redirectToNumber -match "^tel:\d+$")
    {
        Write-Host -ForegroundColor Red "ERROR: Redirection phone number must be in the form: 'tel:12345678910'."
    }
}
