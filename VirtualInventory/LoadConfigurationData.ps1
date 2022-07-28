<#

    Initialization data for the script is stored in JSON format.  The following items are required.
        Notes:
              Comments in the JSON file are not supported, they are in this file for documentation purposes only.

              All password entries are created by another script that MUST be ran using the same user account this script
                 will run as, and on the same computer where this script will run.  Native Windows Data Protection API (DAPI)
                 functionality is used to encrypt the password from a SecureString (Get-Credential) into a text string.
                 This string can be written to a plain text file, but the way that DAPI works, the encryption is such that
                 only the original user on the original machine the encryption was performed on can decrypt the string back
                 into a SecureString to be reused.

{
    "LogPath": "",                 # Path where log files are stored.
    "ExportPath": "",              # Path where data is exported to.
    "Filers": {                    # Object for NetApp connection information.
        "CDOT": {                  # Clustered DataONTAP (CDOT) connection information
            "UserName": "",        # User name used to connect to CDOT controller.
            "Password": "",        # Encrypted password for the previous user account.
            "Controllers": [ ]     # An array of DNS names for all the cluster DataONTAP controllers to connect to.
        },
        "SM": {                    # 7-mode connection information
            "UserName": "",        # User name used to connect to 7-mode nodes.
            "Password": "",        # Encrypted password for the previous user account.
            "Nodes": [ ]           # An array of DNS names for all the 7-mode nodes to connect to.
        }
    },
    "UCS": {                       # Object for UCS connection information
        "UserName": "",            # User name used to connect to UCS.  For domain credentials use form: ucs-DOMAINFQDN\\userName
        "Password": "",            # Encrypted password for the previous user account.
        "Managers": [ ]            # An array of DNS name for all the UCS managers to connect to.
    },
    "vCenter": {                   # Object for vCenter connection information
        "Server": "",              # DNS name for the vCenter server to connect to.
        "UserName": "",            # User name used to connect to vCenter.
        "Password": "",            # Encrypted password for the previous user account.
    },
    "xClarity": {                  # Object for xClarity connection information
        "Server": "",              # DNS name for the xClarity server to connect to.
        "UserName": "",            # User name used to connect to xClarity.
        "Password": "",            # Encrypted password for the previous user account.
    },
    "IPAMDB": {                    # Object for IPAM Database connection information
        "Server": "",              # DNS name for the IPAM database server to connect to.
        "Port": ,                  # The port the MySQL or MariaDB server listens on.  (integer)
        "Database": "",            # The name of the IPAM database
        "UserName": "",            # User name used to connect to the IPAM database.
        "Password": ""             # Encrypted password for the previous user account.
    },
    "Statseeker": {
        "Server": "",              # DNS name for the Statseeker server to connect to.
        "APIBase": "",             # Base URL for API access to Statseeker.
        "UserName": "",            # User name used to connect to the IPAM database.
        "Password": ""             # Encrypted password for the previous user account.
    }
}

#>

if ($null -ne [Log])
{
    # TRUE
    <#
        Function to test if a temporary file can be written to a path or not.

        If the function returns $null, the path is not valid, otherwise the path is returned.
    #>
    function TestConfigPath
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory=$true,Position=0)]
            [String]
            $pathToTest,

            [Parameter(Mandatory=$true,Position=1)]
            [String]
            $label
        )

        if([String]::IsNullOrEmpty($pathToTest))
        {
            [Log]::Error("Configuration data missing {0}." -f @($label))
            $pathToTest = $null
        }
        else
        {
            $tempPath = $pathToTest
            while((-not [String]::IsNullOrEmpty($tempPath)) -and ($tempPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)))
            {
                $tempPath = $tempPath.Substring(0, $tempPath.Length - 1)
            }
    
            if([String]::IsNullOrEmpty($tempPath))
            {
                [Log]::Error("{0} [{1}] is invalid" -f @($label, $pathToTest))
                $pathToTest = $null
            }
            else
            {
                $testFolder = "{0}\{1}.tmp" -f @($tempPath, [DateTime]::Now.ToString("yyyyMMddHHmmssfff"))
                try
                {
                    New-Item -Path $testFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Remove-Item -Path $testFolder -Confirm:$false -Force -ErrorAction Stop
                    $pathToTest = $tempPath
                }
                catch
                {
                    [Log]::Error("Unable to create/remove temporary folder in {0}." -f @($pathToTest))
                    $pathToTest = $null
                }
            }
        }

        return $pathToTest
    }

    # Function to load the virtual inventory configuration file and verify all settings are available.
    function Global:LoadConfigurationData
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory=$true,Position=0)]
            [String]
            $JSONArgsFile
        )

        # Assume all is well with the data unless...
        $cfgError = $false
        $inventoryConfig = $null

        if(-not [String]::IsNullOrEmpty($JSONArgsFile))
        {
            if([System.IO.File]::Exists($JSONArgsFile))
            {
                try
                {
                    $inventoryConfig = Get-Content -Path $JSONArgsFile | ConvertFrom-Json

                    if($null -ne $inventoryConfig)
                    {
                        [Log]::Info("Loaded configuration:`r`n{0}" -f @(($inventoryConfig | ConvertTo-Json -Depth 10).Replace("    ", " ")))

                        $tempPath = TestConfigPath $inventoryConfig.LogPath "LogPath"
                        if([String]::IsNullOrEmpty($tempPath))
                        {
                            # Message was already logged.
                            $cfgError = $true
                        }
                        else
                        {
                            $inventoryConfig.LogPath = $tempPath
                        }

                        $tempPath = TestConfigPath $inventoryConfig.ExportPath "ExportPath"
                        if([String]::IsNullOrEmpty($tempPath))
                        {
                            # Message was already logged.
                            $cfgError = $true
                        }
                        else
                        {
                            $inventoryConfig.ExportPath = $tempPath
                        }

                        if($null -ne $inventoryConfig.Filers)
                        {
                            if($null -ne $inventoryConfig.Filers.CDOT)
                            {
                                if(($null -eq $inventoryConfig.Filers.CDOT.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.Filers.CDOT.UserName)))
                                {
                                    [Log]::Error("Configuration data missing CDOT 'Filers' user name.")
                                    $cfgError = $true
                                }

                                if($null -eq $inventoryConfig.Filers.CDOT.Password)
                                {
                                    [Log]::Error("Configuration data missing CDOT 'Filers' password.")
                                    $cfgError = $true
                                }

                                if(($null -eq $inventoryConfig.Filers.CDOT.Controllers) -or ($inventoryConfig.Filers.CDOT.Controllers.Length -eq 0))
                                {
                                    [Log]::Error("Configuration data missing CDOT 'Filers' controller list.")
                                    $cfgError = $true
                                }
                            }
                            else
                            {
                                [Log]::Error("Configuration data missing CDOT 'Filers' data.")
                                $cfgError = $true
                            }

                            if($null -ne $inventoryConfig.Filers.SM)
                            {
                                if(($null -eq $inventoryConfig.Filers.SM.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.Filers.SM.UserName)))
                                {
                                    [Log]::Error("Configuration data missing SM 'Filers' user name.")
                                    $cfgError = $true
                                }

                                if($null -eq $inventoryConfig.Filers.SM.Password)
                                {
                                    [Log]::Error("Configuration data missing SM 'Filers' password.")
                                    $cfgError = $true
                                }

                                if(($null -eq $inventoryConfig.Filers.SM.Nodes) -or ($inventoryConfig.Filers.SM.Nodes.Length -eq 0))
                                {
                                    [Log]::Error("Configuration data missing SM 'Filers' nodes list.")
                                    $cfgError = $true
                                }
                            }
                            else
                            {
                                [Log]::Error("Configuration data missing SM 'Filers' data.")
                                $cfgError = $true
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'Filers' data.")
                            $cfgError = $true
                        }

                        if($null -ne $inventoryConfig.Intersight)
                        {
                            if(($null -eq $inventoryConfig.Intersight.URL) -or ([String]::IsNullOrEmpty($inventoryConfig.Intersight.URL)))
                            {
                                [Log]::Error("Configuration data missing Intersight URL.")
                                $cfgError = $true
                            }

                            if($null -eq $inventoryConfig.Intersight.APIKey)
                            {
                                [Log]::Error("Configuration data missing Intersight API Key.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.Intersight.PrivateKeyFile) -or ($inventoryConfig.Intersight.PrivateKeyFile -eq 0))
                            {
                                [Log]::Error("Configuration data missing Intersight private key file.")
                                $cfgError = $true
                            }

                            if (-not [System.IO.File]::Exists($inventoryConfig.Intersight.PrivateKeyFile))
                            {
                                # TRUE
                                [Log]::Error("Intersight private key file {0} does not exist." -f @($inventoryConfig.Intersight.PrivateKeyFile))
                                $cfgError = $true
                            }
                            else # NOT (-not [System.IO.File]::Exists($inventoryConfig.Intersight.PrivateKeyFile))
                            {
                                # FALSE

                                # Nothing, all is well
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'Intersight' data.")
                            $cfgError = $true
                        }

                        if($null -ne $inventoryConfig.vCenter)
                        {
                            if(($null -eq $inventoryConfig.vCenter.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.vCenter.UserName)))
                            {
                                [Log]::Error("Configuration data missing vCenter user name.")
                                $cfgError = $true
                            }

                            if($null -eq $inventoryConfig.vCenter.Password)
                            {
                                [Log]::Error("Configuration data missing vCenter password.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.vCenter.Server) -or ([String]::IsNullOrEmpty($inventoryConfig.vCenter.Server)))
                            {
                                [Log]::Error("Configuration data missing vCenter server name.")
                                $cfgError = $true
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'vCenter' data.")
                            $cfgError = $true
                        }

                        if($null -ne $inventoryConfig.xClarity)
                        {
                            if(($null -eq $inventoryConfig.xClarity.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.xClarity.UserName)))
                            {
                                [Log]::Error("Configuration data missing xClarity user name.")
                                $cfgError = $true
                            }

                            if($null -eq $inventoryConfig.xClarity.Password)
                            {
                                [Log]::Error("Configuration data missing xClarity password.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.xClarity.Server) -or ([String]::IsNullOrEmpty($inventoryConfig.xClarity.Server)))
                            {
                                [Log]::Error("Configuration data missing xClarity server name.")
                                $cfgError = $true
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'xClarity' data.")
                            $cfgError = $true
                        }

                        if($null -ne $inventoryConfig.IPAMDB)
                        {
                            if(($null -eq $inventoryConfig.IPAMDB.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.IPAMDB.UserName)))
                            {
                                [Log]::Error("Configuration data missing IPAMDB user name.")
                                $cfgError = $true
                            }

                            if($null -eq $inventoryConfig.IPAMDB.Password)
                            {
                                [Log]::Error("Configuration data missing IPAMDB password.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.IPAMDB.Server) -or ([String]::IsNullOrEmpty($inventoryConfig.IPAMDB.Server)))
                            {
                                [Log]::Error("Configuration data missing IPAMDB server name.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.IPAMDB.Database) -or ([String]::IsNullOrEmpty($inventoryConfig.IPAMDB.Database)))
                            {
                                [Log]::Error("Configuration data missing IPAMDB database name.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.IPAMDB.Port) -or ($inventoryConfig.IPAMDB.Port -lt 1) -or ($inventoryConfig.IPAMDB.Port -gt 65535))
                            {
                                [Log]::Error("Configuration data missing IPAMDB database port or port is invalid.")
                                $cfgError = $true
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'IPAMDB' data.")
                            $cfgError = $true
                        }

                        if($null -ne $inventoryConfig.Statseeker)
                        {
                            if(($null -eq $inventoryConfig.Statseeker.UserName) -or ([String]::IsNullOrEmpty($inventoryConfig.Statseeker.UserName)))
                            {
                                [Log]::Error("Configuration data missing Statseeker user name.")
                                $cfgError = $true
                            }

                            if($null -eq $inventoryConfig.Statseeker.Password)
                            {
                                [Log]::Error("Configuration data missing Statseeker password.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.Statseeker.URL) -or ([String]::IsNullOrEmpty($inventoryConfig.Statseeker.URL)))
                            {
                                [Log]::Error("Configuration data missing Statseeker URL.")
                                $cfgError = $true
                            }

                            if(($null -eq $inventoryConfig.Statseeker.APIBase) -or ([String]::IsNullOrEmpty($inventoryConfig.Statseeker.APIBase)))
                            {
                                [Log]::Error("Configuration data missing Statseeker API Base.")
                                $cfgError = $true
                            }
                        }
                        else
                        {
                            [Log]::Error("Configuration data missing 'Statseeker' data.")
                            $cfgError = $true
                        }
                    }
                    else
                    {
                        [Log]::Error(("Failed to create configuration data from contents of {0}." -f @($JSONArgsFile)))
                        $cfgError = $true
                    }
                }
                catch
                {
                    [Log]::Error(("Failed to create configuration data from contents of {0}." -f @($JSONArgsFile)))
                    $cfgError = $true
                }
            }
            else
            {
                [Log]::Error(("{0} does not exist." -f @($JSONArgsFile)))
                $cfgError = $true
            }
        }
        else
        {
            [Log]::Error("Missing argument for .json configuration file.")
            $cfgError = $true
        }

        # If there is something wrong with the virtual inventory configuration data, clear it so it's not used.
        if ($cfgError)
        {
            # TRUE

            $inventoryConfig = $null
        }
        else # NOT ($cfgError)
        {
            # FALSE

            # Nothing.
        }

        return $inventoryConfig
    }
}
else # NOT ($Global:LoggerClassLoaded -eq $true)
{
    # FALSE

    Write-Error "[Log] class not available."
}
