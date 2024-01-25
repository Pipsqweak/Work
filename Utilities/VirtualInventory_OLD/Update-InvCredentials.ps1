# Update credential in Virtual Inventory configuration .json file.
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

# Temporary StringBuilder for errors.
$sb = [System.Text.StringBuilder]::new()

# Source in LoadConfigurationData function.  This function is stored externally since it is used in other scripts.
. .\LoadConfigurationData.ps1

# Verify LoadConfigurationData was source into the script.
$found = $false
try { Get-ChildItem -Path Function:\LoadConfigurationData -ErrorAction Stop | Out-Null; $found = $true } catch { }

if ($found)
{
    # TRUE

    # Load script initialization information.
    $inventoryConfig = LoadConfigurationData $JSONArgsFile
    if ($null -ne $inventoryConfig)
    {
        # TRUE

        $cdotCredential = Get-Credential -Message "Enter username and password for access to CDOT clusters" -UserName $inventoryConfig.Filers.CDOT.UserName
        if($null -ne $cdotCredential)
        {
            if(-not [String]::IsNullOrEmpty($cdotCredential.GetNetworkCredential().Password))
            {
                $inventoryConfig.Filers.CDOT.Password = $cdotCredential.Password | ConvertFrom-SecureString

                $smCredential = Get-Credential -Message "Enter username and password for access to 7-Mode filers ([ESC] to use CDOT credentials)" -UserName $inventoryConfig.Filers.SM.UserName
                if($null -eq $smCredential)
                {
                    $smCredential = $cdotCredential
                }

                if(-not [String]::IsNullOrEmpty($smCredential.GetNetworkCredential().Password))
                {
                    $inventoryConfig.Filers.SM.Password = $smCredential.Password | ConvertFrom-SecureString

                    $xClarityCredential = Get-Credential -Message "Enter username and password for access to xClarity" -UserName $inventoryConfig.xClarity.UserName
                    if($null -ne $xClarityCredential)
                    {
                        if(-not [String]::IsNullOrEmpty($xClarityCredential.GetNetworkCredential().Password))
                        {
                            $inventoryConfig.xClarity.Password = $xClarityCredential.Password | ConvertFrom-SecureString

                            $vCenterCredential = Get-Credential -Message "Enter username and password for access to vCenter" -UserName $inventoryConfig.vCenter.UserName
                            if($null -ne $vCenterCredential)
                            {
                                if(-not [String]::IsNullOrEmpty($vCenterCredential.GetNetworkCredential().Password))
                                {
                                    $inventoryConfig.vCenter.Password = $vCenterCredential.Password | ConvertFrom-SecureString

                                    $ipamDBCredential = Get-Credential -Message "Enter username and password for access to IPAM DB" -UserName $inventoryConfig.IPAMDB.UserName
                                    if($null -ne $ipamDBCredential)
                                    {
                                        if(-not [String]::IsNullOrEmpty($ipamDBCredential.GetNetworkCredential().Password))
                                        {
                                            $inventoryConfig.IPAMDB.Password = $ipamDBCredential.Password | ConvertFrom-SecureString

                                            $statseekerCredential = Get-Credential -Message "Enter username and password for access to Statseeker" -UserName $inventoryConfig.Statseeker.UserName
                                            if($null -ne $statseekerCredential)
                                            {
                                                if(-not [String]::IsNullOrEmpty($statseekerCredential.GetNetworkCredential().Password))
                                                {
                                                    $inventoryConfig.Statseeker.Password = $statseekerCredential.Password | ConvertFrom-SecureString

                                                    try
                                                    {
                                                        Copy-Item -Path $JSONArgsFile -Destination ("{0}.bak" -f @($JSONArgsFile)) -Force
                                                        $inventoryConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $JSONArgsFile -Force
                                                    }
                                                    catch
                                                    {
                                                        [void] $sb.AppendLine("Failed to update credentials for virtual inventory.")
                                                        Copy-Item -Path ("{0}.bak" -f @($JSONArgsFile)) -Destination $JSONArgsFile -Force
                                                    }
                                                }
                                                else
                                                {
                                                    [void] $sb.AppendLine("Missing required password for Statseeker credentials.")
                                                }
                                            }
                                            else
                                            {
                                                [void] $sb.AppendLine("Missing required credentials for Statseeker access.")
                                            }
                                        }
                                        else
                                        {
                                            [void] $sb.AppendLine("Missing required password for IPAM database credentials.")
                                        }
                                    }
                                    else
                                    {
                                        [void] $sb.AppendLine("Missing required credentials for IPAM database.")
                                    }
                                }
                                else
                                {
                                    [void] $sb.AppendLine("Missing required password for vCenter credentials.")
                                }
                            }
                            else
                            {
                                [void] $sb.AppendLine("Missing required credentials for vCenter.")
                            }
                        }
                        else
                        {
                            [void] $sb.AppendLine("Missing required password for xClarity credentials.")
                        }
                    }
                    else
                    {
                        [void] $sb.AppendLine("Missing required credentials for xClarity.")
                    }
                }
                else
                {
                    [void] $sb.AppendLine("Missing required password for SM node credentials.")
                }
            }
            else
            {
                [void] $sb.AppendLine("Missing required password for CDOT credentials.")
            }
        }
        else
        {
            [void] $sb.AppendLine("Missing required credentials for CDOT clusters.")
        }
    }
    else # NOT ($null -ne $inventoryConfig)
    {
        # FALSE

        [void] $sb.AppendLine("Failed to load virtual inventory configuration data.")
    }
}
else # NOT ($found)
{
    # FALSE

    [void] $sb.AppendLine("Failed to source LoadConfiguationData function into script.")
}

# Write any error information to the error console.
if($sb.Length -gt 0)
{
    Write-Error $sb.ToString()
}
