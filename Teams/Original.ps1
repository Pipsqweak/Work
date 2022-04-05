$data = Import-Csv "C:\Users\........Production.csv" -Delimiter "`t"
$Credential = Get-Credential
Connect-AzureAD -Credential $Credential
Connect-MicrosoftTeams -TenantId "TennantID" -Credential $Credential

foreach ($item in $data) {
# Collects values to set
$UPN = $item.UPN
$displayName = $item.DisplayName
$Phone = $item.PhoneNumber
$Country = $item.Country
if ($item.Type -ne "AA") {
$AppId = "11cd3e2e-fccb-42ad-ad00-878b93575e07" # CQ
} else {
$AppId = "ce933385-9390-45d1-9512-c8d228074e07" # AA
}

# Creates the ApplicationInstance object
$Object = New-CsOnlineApplicationInstance -UserPrincipalName $UPN -ApplicationId $AppId -DisplayName $displayName

# Waits for the user to exist
while ((Get-AzureADUser -ObjectId $UPN -ErrorAction SilentlyContinue) -eq $null) { sleep 50 }

# Assigns Usage Location
Set-AzureADUser -ObjectId $UPN -UsageLocation $Country

# Assigns the license
$License = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$License.SkuId = (Get-AzureADSubscribedSku |where {$_.skuPartNumber -eq "PHONESYSTEM_VIRTUALUSER" }).SkuId
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.AddLicenses = $License
Set-AzureADUserLicense -ObjectId $UPN -AssignedLicenses $Licenses

# Waits for the license to be assigned
while (((Get-AzureADUser -ObjectId $UPN).AssignedPlans | where {($_.Service -eq "MicrosoftCommunicationsOnline") -and ($_.CapabilityStatus -eq "Enabled")}) -eq $null) {
write-host (get-date)
sleep 1
}

## Sets the phone number to the ApplicationInstance
#Set-CsOnlineApplicationInstance -Identity $Object.ObjectId -OnpremPhoneNumber $Phone

break
}

Disconnect-AzureAD