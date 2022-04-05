<#
    NOTES:  VMWare modules interfere with MicrosoftTeams.  Need to use a no-profile powershell to avoid loading the incorrect assemblies
#>

$data = Import-Csv "C:\Users\........Production.csv" -Delimiter "`t"
# $msOnlineCredential = Get-Credential -Message "Enter credentials for Azure AD/MS Teams"
$powerAzureADTenantID = "f07fff05-bf71-4ed8-b274-173ea27956dc"
$Global:CallQueueApplicationInstanceID = "11cd3e2e-fccb-42ad-ad00-878b93575e07"  # https://docs.microsoft.com/en-us/powershell/module/skype/new-csonlineapplicationinstance?view=skype-ps
$Global:maximumRetries = 5
$Global:retryDelayTime = 1000   # in milliseconds

$Global:VerboseOutput = $VerbosePreference -eq "Continue"

<#
Hi Ken,
The accounts for testing have been created as follows”
RA Test (Resource Account) – number assigned 602-892-0089
RA Test Backup (Resource Account)

RA Test Call Queue
RA Test Backup Call Queue

Feel free to do whatever you need to these accounts.

#>
Connect-AzureAD # -Credential $msOnlineCredential
Connect-MsolService
Connect-MicrosoftTeams -TenantId $powerAzureADTenantID # -Credential $msOnlineCredential

function GetTenantDetails
{
    if($null -eq $Global:AzureADTenantDetails)
    {
        $Global:TenantName = "<unknown Azure tenant>"
        try
        {
            $Global:AzureADTenantDetails = Get-AzureADTenantDetail -ErrorAction Stop
            $Global:TenantName = $Global:AzureADTenantDetails.DisplayName
        }
        catch
        {
        }
    }
}

function GetPhoneSystemVirtualUserSkuId
{
    if([String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
    {
        # Populate $Global:phoneSystemVirtualUserSkuId
        try
        {
            $msOnlineAccountSKUs = Get-MsolAccountSku -ErrorAction Stop
            $Global:phoneSystemVirtualUserSkuId = ($msOnlineAccountSKUs | Where-Object { $_.AccountSkuId -match "PHONESYSTEM_VIRTUALUSER" }).AccountSkuId
        }
        catch
        {
            Write-Host -ForegroundColor Red "ERROR: Failed to retrieve PHONESYSTEM_VIRTUALUSER account SKU from Microsoft Online."
        }
    }
    else
    {
        # Nothing, already set.
    }
}

if(-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
{
    # Test Item
    $item = "" | Select-Object UPN,DisplayName,PhoneNumber,Country,CQName
    $item.UPN = "ratestklb@powereng0.onmicrosoft.com"
    $item.DisplayName = "RA Test Account KLB"
    $item.PhoneNumber = "123-123-1234"
    $item.Country = "US"
    $item.CQName = "CQ Test Account KLB"

    foreach ($item in $data)
    {
        $forwardCallForParams = @{
            UserPrincipalName = $item.UPN
            DisplayName = $item.DisplayName
            PhoneNumber = $item.PhoneNumber
            Country = $item.Country
            CallQueueName = $item.CQName
            VerboseOutput = $Global:VerboseOutput
        }

        Forward-CallsFor @forwardCallForParams
    }
}
else
{
    # Nothing, can't create call queues without the PHONESYSTEM_VIRTUALUSER account SKU
}

function ExecuteWithRetries
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
            Write-Host "failed"
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

<#
    1. Make sure we have Azure AD Tenant details
    2. Make sure $phoneNumber is assigned to the Azure AD Tenant
    3. Create the new resource account (New-CsOnlineApplicationInstance)
        a. Verify there is no matching resource account
    4. Set the usage location for the resource account
        This is required before the PHONESYSTEM_VIRTUALUSER license can be assigned to the resource account
        a. If this fails, remove the resource account
    5. Assign PHONESYSTEM_VIRTUALUSER license to the resource account
        a. If this fails, remove the resource account
    6. Assign the phone number to the resource account
        a. If this fails
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. remove the resource account
    7. Create the call queue for the resource account
        a. If this fails:
            1. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            2. Remove the resource account
    8. Associate the resource account to the call queue
        a. If this fails:
            1. Remove the call queue
            2. Unassign PHONESYSTEM_VIRTUALUSER license from the resource account
            3. Remove the resource account

    If the entire process is not successful, action are "undone" in the reverse order they were attempted based on what actions were successful.
#>
function Forward-CallsFor
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $UserPrincipalName,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $DisplayName,

        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String] $PhoneNumber,

        [Parameter(Mandatory=$true, Position=3)]
        [ValidateNotNullOrEmpty()]
        [String] $Country,

        [Parameter(Mandatory=$true, Position=4)]
        [ValidateNotNullOrEmpty()]
        [String] $CallQueueName,
        
        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    GetTenantDetails
    if($null -ne $Global:AzureADTenantDetails)
    {
        $havePhoneNumber = $false
        try
        {
            $havePhoneNumber = ($null -ne (Get-CsOnlineTelephoneNumber -TelephoneNumber $PhoneNumber -WarningAction SilentlyContinue -ErrorAction Stop))
        }
        catch
        {
            # Nothing, just leave $havePhoneNumber -eq $false
        }

        if($havePhoneNumber)
        {
            GetPhoneSystemVirtualUserSku
            if(-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
            {
                # Some variables to track what needs to be undone if an error occurs.
                $resourceAccountCreated = $false
                $assignedLicense = $false
                $createdCallQueue = $false
                $resourceAccountAssociated = $false

                # Flag the overall success of the process
                $successful = $false

                # Create a new resource account
                $newResourceAccount = Create-ResourceAccount -userPrincipalName $UserPrincipalName -displayName $DisplayName -message ("Creating resource account for {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput

                if($null -ne $newResourceAccount)
                {
                    # The resource account was successfully created.


                    # Wait for the resource account to be available to this script.
                    #   This may take a while.  Some tuning of maxRetries and retryDelay may be needed.
                    $newResourceAccount = Get-ResourceAccountByUPN -userPrincipalName $UserPrincipalName -message ("Waiting for resource account {0} to be available." -f @($UserPrincipalName)) -maxRetries 25 -retryDelay 1000 -VerboseOutput:$VerboseOutput

                    if($null -ne $newResourceAccount)
                    {
                        # The script was able to verify the resource account was created and registered with Azure AD.


                        # Wait to flag the creation of the resource account until after confirming it exists as an Azure AD user.
                        $resourceAccountCreated = $true

                        # Assign usage location -- this is required before a license can be assigned.  See: https://docs.microsoft.com/en-us/powershell/module/azuread/set-azureaduser?view=azureadps-2.0 Parameter: -UsageLocation
                        $usageLocationSet = Assign-UsageLocation -userPrincipalName $UserPrincipalName -country $Country -message ("Assigning usage location {0} to {1}." -f @($Country, $DisplayName)) -VerboseOutput:$VerboseOutput

                        if($usageLocationSet)
                        {
                            # The resource account's usage location was successfully set.


                            # Assign a PHONESYSTEM_VIRTUALUSER license to the resource account...
                            $assignedLicense = Assign-PhoneSystemVirtualUser -userPrincipalName $UserPrincipalName -message ("Assigning PHONESYSTEM_VIRTUALUSER license to {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput
                        
                            if($assignedLicense)
                            {
                                # The PHONESYSTEM_VIRTUALUSER license was successfully assigned to the resource account, or it already had the license assigned.


                                # Assign phone number to the resource account...
<# --> #>                       $newRAUser = Assign-PhoneNumber -azADUser $newRAUser -phoneNumber $PhoneNumber -message ("Setting phone number for {0} to {1}." -f @($displayName, $phoneNumber)) -VerboseOutput:$VerboseOutput
                
                                if($null -ne $newRAUser)
                                {
                                    # The phone number was successfully assigned to the resource account.


                                    # Create the call queue...
                                    $newCallQueue = Create-CallQueue -azADUser $newRAUser -callQueueName $CallQueueName -message ("Creating new call queue for {0}." -f @($displayName)) -VerboseOutput:$VerboseOutput
                            
                                    if($null -ne $newCallQueue)
                                    {
                                        # The call queue was successfully created...


                                        $createdCallQueue = $true

                                        # Next, associate the RA account with the new call queue
                                        $newAppInstanceAssociation = Associate-ResourceAccountToCallQueue -azADUser $newRAUser -callQueue $newCallQueue -message "Associating resource account to call queue." -VerboseOutput:$VerboseOutput
                                
                                        if($null -ne $newAppInstanceAssociation)
                                        {
                                            # The resource account was successfully associated to the call queue...

                                            $resourceAccountAssociated = $true
                                            $successful = $true
                                        }
                                        else
                                        {
                                            # The resource account was NOT successfully associated to the call queue...
                                        }
                                    }
                                    else
                                    {
                                        # The call queue was NOT successfully created...


                                        Write-Host -ForegroundColor Red ("ERROR: Failed to create call queue: {0} for {1}." -f @($CallQueueName, $DisplayName))
                                    }
                                }
                                else
                                {
                                    # The phonue number was NOT successfully assigned to the resource account.


                                    Write-Host -ForegroundColor Red ("ERROR: Failed to set phone number for {0}." -f @($DisplayName))
                                }
                            }
                            else
                            {
                                # The PHONESYSTEM_VIRTUALUSER license was NOT successfully assigned to the resource account


                                Write-Host -ForegroundColor Red ("ERROR: Failed to assign PHONESYSTEM_VIRTUALUSER license to {0}." -f @($DisplayName))
                            }

                        }
                        else
                        {
                            # The resource account's usage location was NOT successfully set.


                            Write-Host -ForegroundColor Red ("ERROR: Failed to set usage location for {0}." -f @($DisplayName))
                        }
                    }
                    else
                    {
                        # The script was NOT able to verify the resource account was created and registered with Azure AD.


                        Write-Host -ForegroundColor Red ("ERROR: Failed to acquire Azure AD user account for resource account {0}." -f @($UserPrincipalName))
                        Write-Host -ForegroundColor Red "ERROR: Manual clean up of resource account may be required."
                    }
                }
                else
                {
                    # The resource account was not created...


                    Write-Host -ForegroundColor Red ("ERROR: Failed to create resource account for {0}." -f $DisplayName)
                }


                if(-not $successful)
                {
                    $callQueueRemoved = $false
                    $resourceAccountRemoved = $false
                    $resourceAccountUnassociated = $false

                    # Undo changes in the reverse order...

                    if($resourceAccountAssociated)
                    {
                        if(Unassociate-ResourceAccountFromCallQueue -azADUser $newRAUser -message ("Unassociating resource account {0} from {1}." -f @($newRAUser.DisplayName, $newCallQueue.Name)) -VerboseOutput:$VerboseOutput)
                        {
                            $resourceAccountUnassociated = $true
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red "Failed to unassociate resource account from call queue.  Manual clean up may be required."
                        }
                    }
                    else
                    {
                        # Simulate the unassociation of the resource account from the call queue.
                        $resourceAccountUnassociated = $true
                    }

                    if($createdCallQueue -and $resourceAccountUnassociated)
                    {
                        if(Remove-CallQueueByName -callQueueName $newCallQueue.Name -message ("Removing call queue {0}." -f @($newCallQueue.Name)) -VerboseOutput:$VerboseOutput)
                        {
                            $callQueueRemoved = $true
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red "Failed to remove call queue.  Manual clean up may be required."
                        }
                    }
                    else
                    {
                        # Nothing, the call queue was not created
                    }

                    # TODO: Unassign the phone number from the resource account...

                    if($assignedLicense)
                    {
                        Unassign-PhoneSystemVirtualUser -userPrincipalName $UserPrincipalName -VerboseOutput:$VerboseOutput
                    }
                    else
                    {
                        # Nothing the PHONESYSTEM_VIRTUALUSER license was not assigned to the resource account
                    }

                    if($resourceAccountCreated)
                    {
                        if(Remove-ResourceAccount -upn $UserPrincipalName -message ("Removing resource account {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput)
                        {
                            $resourceAccountRemoved = $true
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red "Failed to remove resource account.  Manual clean up may be required."
                        }
                    }
                    else
                    {
                        # Nothing, the resource account was not created.
                    }

                }  
                else
                {
                    # Nothing everything worked as planned.
                }
            }
            else
            {
                Write-Host -ForegroundColor Red "ERROR: Cannot set up call forwarding without the PHONESYSTEM_VIRTUALUSER account SKU ID."
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: {0} is not assigned to {1}." -f @($PhoneNumber, $Global:TenantName))
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "ERROR: Failed to acquire Azure AD tenant details."
        Write-Host -ForegroundColor Red "       Ensure you are connected to Azure AD."
    }

    break
}


function Get-ResourceAccountByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {    
        # Scriptblock to execute...
        $scriptBlock = {
            param($upn) Get-CsOnlineApplicationInstance -Identity $upn -ErrorAction Stop
        }
        $success, $appInstance = ExecuteWithRetries -cmdToExecute $scriptBlock -cmdArgs @($userPrincipalName) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
    }
    else
    {
        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while retrieving resource account."
    }

    return $appInstance
}

function Remove-ResourceAccount
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput=$false
    )
        
    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
        {
            Write-Host -ForegroundColor Green $message
        }
        $resourceAccount = Get-ResourceAccountByUPN -userPrincipalName $userPrincipalName -message ("Verifying the existance of resource account {0}" -f @($userPrincipalName)) -VerboseOutput:$VerboseOutput
        if($null -ne $resourceAccount)
        {
            try
            {
                # Clear any outstanding errors.
                $Error.Clear()

                # Remove the Azure AD User account.
                Remove-AzureADUser -ObjectId $resourceAccount.ObjectId -ErrorAction Stop
                $success = $true
            }
            catch
            {
                # Nothing, leave $success set to $falst
            }
        }
        else
        {
            $success = $true # Well, not techincally true, but the resource account does not appear to exist.
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while creating resource account."
    }

    return $success
}

function Create-ResourceAccount
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $displayName=$null,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch] $VerboseOutput=$false
    )

    $newResourceAccount = $null
    
    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        if(-not [String]::IsNullOrEmpty($displayName))
        {
            # Make sure there isn't already a resource account with a matching user principal name.
            $existingResourceAccount = Get-ResourceAccountByUPN -userPrincipalName $UserPrincipalName -message ("Checking for an existing resource account with user principal name: {0}." -f @($UserPrincipalName)) -VerboseOutput:$VerboseOutput
   
            if($null -eq $existingResourceAccount)
            {
                # There was not a resource account with userPrincipalName -eq $UserPrincipalName

                try
                {
                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host -ForegroundColor Green $message
                    }

                    <#
                        https://docs.microsoft.com/en-us/powershell/module/skype/new-csonlineapplicationinstance?view=skype-ps
                
                            Application IDs:
                                Auto Attendant: ce933385-9390-45d1-9512-c8d228074e07
                                Call Queue:     11cd3e2e-fccb-42ad-ad00-878b93575e07
                    #>

                    # Create the ApplicationInstance object -- This is the "Resource Account"  -- it's just a "special" Azure AD user.
                    $newResourceAccount = New-CsOnlineApplicationInstance -UserPrincipalName $userPrincipalName -ApplicationId "11cd3e2e-fccb-42ad-ad00-878b93575e07" -DisplayName $displayName -ErrorAction Stop
                }
                catch
                {
                    # Nothing, leave $newResourceAccount -eq $null
                }
            }
            else
            {
                # There is an existing resource account with userPrincipalName -eq $UserPrincipalName


                Write-Host -ForegroundColor Red ("ERROR: A resource account already exists with user principal name: {0}." -f @($userPrincipalName))
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "ERROR: Missing display name while creating resource account."
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while creating resource account."
    }

    return $newResourceAccount
}

<#
    FUNCTIONS FOR CALL QUEUES
#>

function Get-CallQueueByName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $callQueueName=$null,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message=$null,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    $scriptBlock = {
        param($cqn) Get-CsCallQueue -NameFilter $callQueueName -WarningAction SilentlyContinue -ErrorAction Stop
    }
    $success, $callQueue = ExecuteWithRetries -cmdToExecute $scriptBlock -cmdArgs @($callQueueName) -message $message -maxRetries $maxRetries -retryDelay $retryDelay -VerboseOutput:$VerboseOutput
   
    return $callQueue
}

function Create-CallQueue
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $resourceAccountID=$null,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $callQueueName=$null,

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
    $newCQ = $null

    if(-not [String]::IsNullOrEmpty($resourceAccountID))
    {
        if([GUID]::TryParse($resourceAccountID, $([ref][GUID]::Empty)))
        {
            if(-not [String]::IsNullOrEmpty($callQueueName))
            {
                # Make sure there isn't already a call queue with $callQueueName
                $existingCallQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} does not already exist." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                if($null -eq $existingCallQueue)
                {
                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host -ForegroundColor Green $message
                    }

                    try
                    {
                        # Clear any existing errors.
                        $Error.Clear()

                        $newCQ = New-CsCallQueue -Name $callQueueName -AllowOptOut $false -LanguageId "en-US" -OverflowAction "Forward" -OverflowActionTarget $resourceAccountID -OverflowThreshold 1 -TimeoutAction "Forward" -TimeoutActionTarget $resourceAccountID -TimeoutThreshold 0 -UseDefaultMusicOnHold $true -WarningAction SilentlyContinue -ErrorAction Stop
                        if($null -ne $newCQ)
                        {
                            $newCQ = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} was created..." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
                            $success = ($null -ne $newCQ)
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
                else
                {
                    Write-Host -ForegroundColor Red ("ERROR: Call queue name {0} already exists." -f @($callQueueName))
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to create call queue.")
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: Resource account object ID {0} is not a GUID while trying to create call queue." -f @($resourceAccountID))
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: Missing resource account object ID while trying to create call queue.")
    }

    if(-not $success)
    {
        $newCQ = $null
    }

    return $newCQ
}

function Remove-CallQueueByName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $callQueueName=$null,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false
    $removedCallQueue = $null

    if(-not [String]::IsNullOrEmpty($callQueueName))
    {
        # Make sure there is a call queue named $callQueueName
        $existingCallQueue = Get-CallQueueByName -callQueueName $callQueueName -message ("Verifying call queue {0} exists." -f @($callQueueName)) -VerboseOutput:$VerboseOutput
        
        if($null -ne $existingCallQueue)
        {
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
                    $existingCallQueue = Get-CallQueueByName -callQueueName $removedCallQueue.Name -message ("Verifying call queue {0} was removed..." -f @($removedCallQueue.Name)) -VerboseOutput:$VerboseOutput
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
        else
        {
            $success = $true    # Again, not technically true, but there doesn't appear to be a call queue with name -eq $callQueueName
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: Call queue name not provided while trying to remove call queue.")
    }

    return $success
}

function Get-ApplicationInstanceAssociation
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Microsoft.Open.AzureAD.Model.User] $azADUser,

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
    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
    {
        Write-Host -NoNewline -ForegroundColor Green $message
    }

    $tries = 0
    do
    {
        $tries++
        $needToRetry = $false

        try
        {
            # Clear any existing errors...
            $Error.Clear()

            # Get resouce account associations
            $accountAssociation = Get-CsOnlineApplicationInstanceAssociation -Identity $azADUser.ObjectId -ErrorAction Stop
            $success = $true
        }
        catch
        {
            # An exception was thrown getting the application instance association...so handle it
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
        Write-Host ""
    } 
        
    return $accountAssociation
}

function Unassociate-ResourceAccountFromCallQueue
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Microsoft.Open.AzureAD.Model.User] $azADUser,

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
    $accountAssociation = Get-ApplicationInstanceAssociation -azADUser $azADUser -message ("Getting application associations for {0}." -f @($azADUser.DisplayName)) -VerboseOutput:$VerboseOutput
    if($null -ne $accountAssociation)
    {
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
                # Remove the application instance associations
                $result = Remove-CsOnlineApplicationInstanceAssociation -Identities @($azADUser.ObjectId) -ErrorAction Stop
                $success = $true
            }
            catch
            {
                # An exception was thrown removing the application instance association...so handle it
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
                $Error.Clear()
            }
        }
        while($needToRetry)

        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
        {
            Write-Host ""
        }         
    }
    else
    {
        $success = $true   # Not technically correct, but there doesn't appear to be an application association for $azADUser
    }

    return $success
}

function Associate-ResourceAccountToCallQueue
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Microsoft.Open.AzureAD.Model.User] $azADUser,

        [Parameter(Mandatory=$true, Position=1)]
        [Object] $callQueue,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=4)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false
    $newCqAssoc = $null

    if($null -ne $azADUser)
    {
        if($azADUser -is [Microsoft.Open.AzureAD.Model.User])
        {
            $accountAssociation = Get-ApplicationInstanceAssociation -azADUser $azADUser -message ("Checking for application instance associations for {0}." -f @($azADUser.DisplayName)) -VerboseOutput:$VerboseOutput
            if($null -eq $accountAssociation)
            {
                $azUserobjectID = $azADUser.ObjectId
                $displayName = $azADUser.DisplayName
                if($null -ne $callQueue)
                {
                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host -ForegroundColor Green $message
                    }

                    try
                    {
                        # Associate the RA account with the new call queue
                        $associationRes = New-CsOnlineApplicationInstanceAssociation -Identities @($azADUser.ObjectId) -ConfigurationId $callQueue.Identity -ConfigurationType "CallQueue" -ErrorAction Stop
                        $success = $true
                    }
                    catch
                    {
                        $success = $false
                    }

                    if($success)
                    {
                        $newCqAssoc = Get-ApplicationInstanceAssociation -azADUser $azADUser -message ("Verifying resource account was associated to call queue.") -VerboseOutput:$VerboseOutput
                        $success = ($null -ne $newCqAssoc)
                    }
                    else
                    {
                        # Nothing...
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red ("ERROR: Call queue not provided while trying to associate resource account to the call queue.")
                    $success = $false
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("ERROR: There is an existing application instance association for {0}." -f @($azADUser.ObjectId))
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: Object provided for resource account is not the correct type while trying to associate resource account to the call queue.")
            $success = $false
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: No resource account provided while trying to associate resource account to the call queue.")
        $success = $false
    }

    if(-not $success)
    {
        $newCqAssoc = $null
    }

    return $newCqAssoc
}

function Get-AzureADUserByUPN
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $upn,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $message,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $VerboseOutput=$false
    )

    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
    {
        Write-Host -ForegroundColor Green -NoNewline $message
    }
    $azADUser = $null
    $tries = 0
    do
    {
        $tries++
        $needToRetry = $false
        $azADUser = $null
        try
        {
            $azADUser = Get-AzureADUser -ObjectId $upn -ErrorAction Stop
        }
        catch
        {
            # Nothing...
        }

        if($null -eq $azADUser)
        {
            # Don't have the information we need, do we need to try again.
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
                if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                {
                    Write-Host ""   # Close the console line
                }
            }
        }
        else
        {
            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
            {
                Write-Host ""   # Close the console line
            }
        }
    }
    while ($needToRetry)

    return $azADUser
}

function Assign-PhoneNumber
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$true, Position=1)]
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
        if(-not [String]::IsNullOrEmpty($phoneNumber))
        {
            # Assign phone number to the resource account.
            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
            {
                Write-Host -ForegroundColor Green -NoNewline $message
            }

            try
            {
                # Code Kevin Betts gave me to associate the phone number:
                
                    ## Sets the phone number to the ApplicationInstance
                    #Set-CsOnlineApplicationInstance -Identity $azADUser.ObjectId -OnpremPhoneNumber $phoneNumber

                $o = Set-CsPhoneNumberAssignment -Identity $userPrincipalName -PhoneNumber $phoneNumber -PhoneNumberType "CallingPlan" -ErrorAction Stop
                $success = $true
            }
            catch
            {
                # Nothing, leave $success -eq $false
            }

            if($success)
            {
                # Cannot use ExecuteWithRetries here since I have to test return values.

                # Verify usage location to be assigned
                if($VerboseOutput)
                {
                    Write-Host -NoNewline ("Verifying usage location is set for {0}..." -f @($displayName))
                }

                $tries = 0
                do
                {
                    $tries++
                    $needToRetry = $false
                    try
                    {
                        $msOLUser = Get-MsolUser -UserPrincipalName $userPrincipalName -ErrorAction Stop
                        $success = ($null -ne $msOLUser) -and ($msOLUser.UsageLocation -eq $country)
                    }
                    catch
                    {
                        $success = $false
                    }

                    if(-not $success)
                    {
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


                # If:
                #    1) no user object was returned, or
                #    2) a user was returned but phone number is wrong
                if(($null -eq $azADUser) -or (($null -ne $azADUser) -and ($azADUser.TelephoneNumber -ne $phoneNumber)))
                {
                    # I've already determined we don't have the proper information in the if conditional, now I just need to set $needToRetry based on how many times we've already tried.
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
                        if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                        {
                            Write-Host "" # Close the open output line...
                        }
                    }
                    $Error.Clear()
                }
                else
                {
                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        # Close the output line...
                        Write-Host ""
                    }
                    $success = $true
                }
            }
            else
            {
                # Nothing, leave $success -eq $false
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: Phone number not provided while trying to set user's phone number.")
            $success = $false
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "ERROR: Missing user principal name while assigning phone number to resource account."
    }

    if($null -ne $azADUser)
    {

    }

    # Signal a failure by returning $null to the caller.
    if(-not $success)
    {
        $azADUser = $null
    }

    return $azADUser
}

function Assign-UsageLocation
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName=$null,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $country=$null,

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
        if(-not [String]::IsNullOrEmpty($country))
        {
            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
            {
                Write-Host -ForegroundColor Green $message
            }

            try
            {
                Set-MsolUser -UserPrincipalName $userPrincipalName -Country $country -ErrorAction Stop
                $success = $true
            }
            catch
            {
                # Nothing, leave $success -eq $false
            }

            # Cannot use ExecuteWithRetries here since I have to test return values.

            if($success)
            {
                # Verify usage location to be assigned
                if($VerboseOutput)
                {
                    Write-Host -NoNewline ("Verifying usage location is set for {0}..." -f @($displayName))
                }

                $tries = 0
                do
                {
                    $tries++
                    $needToRetry = $false
                    try
                    {
                        $msOLUser = Get-MsolUser -UserPrincipalName $userPrincipalName -ErrorAction Stop
                        $success = ($null -ne $msOLUser) -and ($msOLUser.UsageLocation -eq $country)
                    }
                    catch
                    {
                        $success = $false
                    }

                    if(-not $success)
                    {
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
            else
            {
                # Nothing
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: Missing country while trying to set resource account location.")
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while trying to set resource account location.")
    }


    return $success
}

function Has-PhoneSystemVirtualUserLicense
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
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
        GetPhoneSystemVirtualUserSku

        if(-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
        {
            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
            {
                Write-Host -NoNewline -ForegroundColor Green $message
            }

            $tries = 0
            do
            {
                $tries++
                $needToRetry = $false
                $azADUser = $null
                try
                {
                    $msOLUser = Get-MsolUser -UserPrincipalName $userPrincipalName -ErrorAction Stop
                    $success = ($null -ne $msOLUser) -and
                                ($null -ne $msOLUser.Licenses) -and
                                (($msOLUser.Licenses | 
                                    Where-Object { $_.AccountSkuId -eq $Global:phoneSystemVirtualUserSkuId } | 
                                        Select-Object -ExpandProperty ServiceStatus -ErrorAction Stop | 
                                        Select-Object -ExpandProperty ServicePlan -ErrorAction Stop | 
                                        Select-Object -ExpandProperty ServiceType -ErrorAction Stop | 
                                        Where-Object { $_ -eq "MicrosoftCommunicationsOnline" }).Length -gt 0)
                }
                catch
                {
                    $success = $false
                }

                if(-not $success)
                {
                    # I've already determined we don't have the proper information in the if conditional, now I just need to set $needToRetry based on how many times we've already tried.
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
                        # Nothing, leave $success -eq $false
                    }
                }
                else
                {
                    # Nothing
                }
            }
            while($needToRetry)
            if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
            {
                Write-Host "" # Close the open output line...
            }
        }
        else
        {
            # ERROR Global:phoneSystemVirtualUserSku is not populated
            Write-Host -ForegroundColor Red ("ERROR: Missing global phone system virtual user SKU ID while checking for PHONESYSTEM_VIRTUALUSER license.")
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while checking for PHONESYSTEM_VIRTUALUSER license.")
    }

    return $success
}

function Assign-PhoneSystemVirtualUser
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
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
        $hasPhoneSystemVirtualUserLicense = Has-PhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Checking to see if PHONESYSTEM_VIRTUALUSER is assigned to {0}..." -f @($userPrincipalName)) -maxRetries 0 -VerboseOutput:$VerboseOutput

        if(-not $hasPhoneSystemVirtualUserLicense)
        {
            $usageLocationSet = $false
            try
            {
                $msOLUser = Get-MsolUser -UserPrincipalName $userPrincipalName -ErrorAction Stop
                $usageLocationSet = ($null -ne $msOLUser) -and (-not [String]::IsNullOrEmpty($msOLUser.UsageLocation))
            }
            catch
            {
                # Nothing, leave $usageLocationSet -eq $false
            }

            # Before the PHONESYSTEM_VIRTUALUSER can be assigned, the user must be assigned to a location 
            if($usageLocationSet) 
            {
                GetPhoneSystemVirtualUserSku

                if(-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
                {
                    if($VerboseOutput -and (-not [String]::IsNullOrEmpty($message)))
                    {
                        Write-Host -NoNewline -ForegroundColor Green $message
                    }

                    try
                    {
                        Set-MsolUserLicense -UserPrincipalName $userPrincipalName -AddLicenses @($Global:phoneSystemVirtualUserSkuId) -ErrorAction Stop
                        $success = Has-PhoneSystemVirtualUserLicense -userPrincipalName $userPrincipalName -message ("Verifying PHONESYSTEM_VIRTUALUSER is assigned to {0}..." -f @($userPrincipalName)) -maxRetries 50 -VerboseOutput:$VerboseOutput
                    }
                    catch
                    {
                        # Nothing, leave $success -eq $false
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red ("ERROR: Missing global phone system virtual user SKU ID.")
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("ERROR: {0} must be assigned a location prior to assigning PHONESYSTEM_VIRTUALUSER license." -f @($userPrincipalName))
            }
        }
        else
        {
            $success = $true   # Not technically true, but the resource account is already assigned the PHONESYSTEM_VIRTUALUSER license
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("ERROR: Missing user principal name while trying to assign PHONESYSTEM_VIRTUALUSER license.")
    }

    return $success
}

function Unassign-PhoneSystemVirtualUser
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $userPrincipalName,

        [Parameter(Mandatory=$false, Position=1)]
        [Int] $maxRetries=$Global:maximumRetries,

        [Parameter(Mandatory=$false, Position=2)]
        [Int] $retryDelay=$Global:retryDelayTime,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch] $VerboseOutput=$false
    )

    $success = $false

    if(-not [String]::IsNullOrEmpty($userPrincipalName))
    {
        $azADUser = Get-AzureADUserByUPN -upn $userPrincipalName
        if($null -ne $azADUser)
        {
            if($null -ne $Global:phoneSystemVirtualUserSku)
            {
                if(@($azADUser.AssignedLicenses | Where-Object { $_.SkuId -eq $Global:phoneSystemVirtualUserSku.SkuId }).Length -gt 0)
                {
                    <#
                        Old way...

                        $licenses = [Microsoft.Open.AzureAD.Model.AssignedLicenses]::new()  # AssignedLicenses ... plural
                        $licenses.RemoveLicenses = $Global:phoneSystemVirtualUserSku.SkuId
                    #>

                    try
                    {
                        Set-MsolUserLicense -UserPrincipalName $azADUser.UserPrincipalName -RemoveLicenses @($Global:phoneSystemVirtualUserSku.AccountSkuId) -ErrorAction Stop
                        # Old Way:
                        #    Set-AzureADUserLicense -ObjectId $azADUser.UserPrincipalName -AssignedLicenses $licenses -ErrorAction Stop
                        $success = $true
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to unassign PHONESYSTEM_VIRTUALUSER from {0}." -f @($azADUser.DisplayName))
                    }
                }
                else
                {
                    # Not sure if I should return $true or $false.  No license was unassigned, but then again, the user has not been assigned the PHONESYSTEM_VIRTUALUSER license.
                    #  Guess I'll return $true

                    $success = $true
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("ERROR: Missing global phone system virtual user SKU.")
                $success = $false
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: Unable to retrieve Azure AD user using userPrincipalName {0} while unassigning PHONESYSTEM_VIRTUALUSER license." -f @($userPrincipalName))
            $success = $false
        }
    }
    else
    {
        # ERROR: No user specified.
    }

    return $success
}

