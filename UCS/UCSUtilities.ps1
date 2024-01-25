#Requires -Version 5.1
#Requires -Module @{ ModuleName = 'Cisco.UCSManager'; ModuleVersion = '3.0.2.4' }



function Quoted
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Object] $myValue
    )

    $quotedValue = ""
    if ($null -ne $myValue)
    {
        $myValueStr = $myValue.ToString()

        if (-not [String]::IsNullOrEmpty($myValueStr))
        {
            $quotedValue = "`"{0}`"" -f @($myValue.ToString())
        } `
        else # NOT (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $myValue)
    {
        # Nothing.
    }

    return $quotedValue
}


<#
    Start-UcsTransaction
    $mo = Get-UcsOrg -Level root  | Add-UcsFirmwareComputeHostPack -BladeBundleVersion "4.2(1m)B" -Name "test" -OverrideDefaultExclusion "yes" -RackBundleVersion "4.2(1m)C"
    $mo_1 = $mo | Add-UcsFirmwareExcludeServerComponent -ModifyPresent -ServerComponent "local-disk"
    Complete-UcsTransaction
#>


function CreateServiceTemplate
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String] $serviceProfileTemplateName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ValidateNotNull()]
        [String[]] $vNICTemplateNames,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [ValidateNotNullOrEmpty()]
        [String] $biosProfileName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=4)]
        [ValidateNotNullOrEmpty()]
        [String] $bootPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=5)]
        [ValidateNotNullOrEmpty()]
        [String] $hostFwPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=7)]
        [ValidateNotNullOrEmpty()]
        [String] $maintPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=8)]
        [ValidateNotNullOrEmpty()]
        [String] $powerPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=9)]
        [ValidateNotNullOrEmpty()]
        [String] $ScrubPolicyName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=10)]
        [ValidateNotNullOrEmpty()]
        [String] $SolPolicyName
    )

    $success = $true
    $uuidSuffixPoolName = "{0}-UUID" -f @($ucs.Name.Replace(".powereng.com","").ToUpper())

    ReportNotice ("`tCreating service template {0}..." -f @($serviceTemplateName))
    $success, $rootOrg = InvokeUCSFunction -functionName "Get-UcsOrg" -failureMsg "Failed to retrieve root organization." -cmdParams @{ Ucs=$ucs }

    if ($success)
    {
<#
CreateServiceTemplate
    -ucs $rdcConfigurationData.ucsManager
    -serviceProfileTemplateName $rdcConfigurationData.serviceProfileTemplates[_X_].Name
    -vNICTemplates $rdcConfigurationData.serviceProfileTemplates[_X_].vNICTemplates
    -biosProfileName $rdcConfigurationData.BIOSPolicy.Name
    -BootPolicyName $rdcConfigurationData.bootPolicyName
    -HostFwPolicyName $rdcConfigurationData.firmwarePackage.Name
    -MaintPolicyName $rdcConfigurationData.maintenancePolicyName
    -PowerPolicyName $rdcConfigurationData.powerControlPolicyName
    -ScrubPolicyName $rdcConfigurationData.scrubPolicyName
    -SolPolicyName $rdcConfigurationData.serialOverLANPolicyName
#>
        $cmdParams = @{
            Ucs = $ucs
            Org = $rootOrg
            Name = $serviceProfileTemplateName
            BiosProfileName = $biosProfileName
            BootPolicyName = $bootPolicyName
            HostFwPolicyName = $hostFwPolicyName
            IdentPoolName = $uuidSuffixPoolName
            MaintPolicyName = $maintPolicyName
            PowerPolicyName = $powerPolicyName
            ScrubPolicyName = $scrubPolicyName
            SolPolicyName = $solPolicyName
            Type = "updating-template"
        }
        $success, $serviceProfileTemplate = InvokeUCSFunction -functionName "Add-UcsServiceProfile" -failureMsg "Failed to create host firmware package." -cmdParams $cmdParams

<# Right Here #>

        if ($success)
        {
            # This is just a "template line" ...
            $success, $mo = InvokeUCSFunction "Add-UcsFirmwareExcludeServerComponent" -failureMsg ("Failed to modify server component local-disk for host firmware package: {0}" -f @($fwPackageName)) -cmdParams @{Ucs = $ucs; FirmwareComputeHostPack = $fwPackage; ServerComponent = "local-disk"; ModifyPresent = $true }
        } `
        else # NOT ($success)
        {
            # Nothing.
        }
    } `
    else # NOT ($success)
    {
        # Nothing.
    }

    return $success
}

<#
    NOTES:
        Fix up UUID pool name....
#>
function p1()
{
}

<#
# Create LDAP provider...

    Start-UcsTransaction
    $mo = Add-UcsLdapProvider -Basedn "DC=powereng,DC=com" -EnableSSL "yes" -FilterValue "sAMAccountName=`$userid" -Key "THeKUTh33u" -Name "ch3-dc01.powereng.com" -Order "1" -Rootdn "CN=srvcldap,OU=Service Accounts,DC=powereng,DC=com" -Vendor "MS-AD"
    $mo_1 = $mo | Add-UcsLdapGroupRule -ModifyPresent -Authorization "enable" -Descr "" -Name "" -TargetAttr "memberOf" -Traversal "recursive" -UsePrimaryGroup "no"
    Complete-UcsTransaction
#>



<#
function GenericShellFunction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [ValidateNotNull()]
        [Cisco.Ucsm.UcsHandle] $ucs
    )

    $success = $true

    ReportNotice "`tBLAH BLAH BLAH"
    try
    {
        $rootOrg = Get-UcsOrg -Ucs $ucs -Level "root" -ErrorAction Stop

        if ($null -ne $rootOrg)
        {
            try
            {
            }
            catch
            {
            }
        } `
        else # NOT ($null -ne $rootOrg)
        {
            ReportError "`tFailed to retrieve root organization.  Get-UcsOrg returned `$null."
            $success = $false
        }
    }
    catch
    {
        ReportError "`tFailed to retrieve root organization.  Get-UcsOrg threw an exception."
        $success = $false
    }

    return $success
}
#>


$logFiles = Get-ChildItem -Path .\UCS\xmlLogs -Filter *.log
$sb = [System.Text.StringBuilder]::new()
$a = 0
while($a -lt $logFiles.Length)
{
    $baseName = $logFiles[$a].BaseName.Replace("_xmlReq","")
    [void] $sb.AppendLine(("# {0}`r`n#{1}" -f @($baseName, [String]::new("-",120))))

    Write-Host $baseName
    $v = ConvertTo-UcsCmdlet -Xml -Path $logFiles[$a].FullName

    if(-not [String]::IsNullOrEmpty($v))
    {
        $lines = $v.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
        [void] $sb.AppendLine(("{0}`r`n#{1}`r`n" -f @(($lines -join "`r`n"), [String]::new("=",120))))
    }
    $a++
}

$sb.ToString() | Set-Clipboard
