. .\UCS\UCSUtilities.ps1

#$rdcConfigurationData = Get-Content -Path ".\UCS\rdcConfig.json" | ConvertFrom-Json
#$rdcConfigurationData = Get-Content -Path ".\UCS\labConfig.json" | ConvertFrom-Json
#$rdcConfigurationData = Get-Content -Path ".\UCS\ucspe.json" | ConvertFrom-Json


<#
$a = 0
while($success -and ($a -lt $rdcConfigurationData.serviceProfileTemplates.Length))
{
    $success = CreateServiceTemplate
        -ucs $rdcConfigurationData.ucsManager
        -serviceProfileTemplateName $rdcConfigurationData.serviceProfileTemplates[$a].Name
        -vNICTemplates $rdcConfigurationData.serviceProfileTemplates[$a].vNICTemplates
        -biosProfileName $rdcConfigurationData.BIOSPolicy.Name
        -BootPolicyName $rdcConfigurationData.bootPolicyName
        -HostFwPolicyName $rdcConfigurationData.firmwarePackage.Name
        -MaintPolicyName $rdcConfigurationData.maintenancePolicyName
        -PowerPolicyName $rdcConfigurationData.powerControlPolicyName
        -ScrubPolicyName $rdcConfigurationData.scrubPolicyName
        -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName

    $a++
#>
