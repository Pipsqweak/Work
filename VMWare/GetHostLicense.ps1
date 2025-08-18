$licenseManager = Get-View -Server $vCenter $vCenter.ExtensionData.content.LicenseManager
$licenseAssignmentManager = Get-View -Server $vCenter $LicenseManager.licenseAssignmentManager
$licenseUsage = @()
$a = 0
while($a -lt $vmHosts.Length)
{
    $assignedLicenses = $licenseAssignmentManager.QueryAssignedLicenses($vmHosts[$a].Id.Replace("HostSystem-", ""))
    foreach ($license in $assignedLicenses)
    {
        $lic = $license
        #$assignedLicenses[0].Group[0].AssignedLicense
        $licenseObj = [PSCustomObject]@{
            EntityDisplayName = $lic.EntityDisplayName
            Name = $lic.AssignedLicense.Name
            LicenseKey = $lic.AssignedLicense.LicenseKey
            EditionKey = $lic.AssignedLicense.EditionKey
            ProductName = $lic.AssignedLicense.Properties | Where-Object {$_.Key -eq 'ProductName'} | Select-Object -ExpandProperty Value
            ProductVersion = $lic.AssignedLicense.Properties | Where-Object {$_.Key -eq 'ProductVersion'} | Select-Object -ExpandProperty Value
            EntityId = $lic.EntityId
            Scope = $lic.Scope
        }
        $licenseObj
        $licenseUsage += $licenseObj
    }
    $a++
}
