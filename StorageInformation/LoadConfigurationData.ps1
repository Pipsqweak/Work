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
    "LogsToKeep":                  # Number of log files to keep.
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
    "vCenter": {                   # Object for vCenter connection information
        "Server": "",              # DNS name for the vCenter server to connect to.
        "UserName": "",            # User name used to connect to vCenter.
        "Password": "",            # Encrypted password for the previous user account.
    }
}

#>

# Ensure CM logging capabilities are available.
if ($Global:CMLoggingAvailable)
{
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
            LogError ("Configuration data missing {0}." -f @($label))
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
                LogError ("{0} [{1}] is invalid" -f @($label, $pathToTest))
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
                    LogError ("Unable to create/remove temporary folder in {0}." -f @($pathToTest))
                    $pathToTest = $null
                }
            }
        }

        return $pathToTest
    }

    # Function to load the script configuration file and verify all settings are available.
    #   The function is prefixed with Global: to ensure it is available outside the if statement
    #   above that ensures CM logging is available
    function Global:LoadConfigurationData
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory=$true,Position=0)]
            [String]
            $JSONArgsFile
        )

        # Assume all is well with the data unless...
        $scriptConfig = $null

        if(-not [String]::IsNullOrEmpty($JSONArgsFile))
        {
            if(Test-Path -Path $JSONArgsFile -PathType Leaf)
            {
                try
                {
                    $scriptConfig = Get-Content -Path $JSONArgsFile | ConvertFrom-Json

                    if($null -ne $scriptConfig)
                    {
                        $tempPath = TestConfigPath $scriptConfig.LogPath "LogPath"

                        if(-not $Global:ErrorLogged)
                        {
                            $scriptConfig.LogPath = $tempPath
                            # Use configuration data to define the log file name.
                            $Global:LogPath = "{0}\{1}.log" -f @($scriptConfig.LogPath, [DateTime]::Now.ToString("yyyyMMdd"))

                            LogInfo ("Loaded configuration:`r`n{0}" -f @(($scriptConfig | ConvertTo-Json -Depth 10).Replace("    ", " ")))

                            if($null -eq $scriptConfig.LogsToKeep)
                            {
                                LogError "Configuration data missing 'LogsToKeep'."
                            }

                            if($null -ne $scriptConfig.Filers)
                            {
                                if($null -ne $scriptConfig.Filers.CDOT)
                                {
                                    if(($null -eq $scriptConfig.Filers.CDOT.UserName) -or ([String]::IsNullOrEmpty($scriptConfig.Filers.CDOT.UserName)))
                                    {
                                        LogError "Configuration data missing CDOT 'Filers' user name."
                                    }

                                    if($null -eq $scriptConfig.Filers.CDOT.Password)
                                    {
                                        LogError "Configuration data missing CDOT 'Filers' password."
                                    }

                                    if(($null -eq $scriptConfig.Filers.CDOT.Controllers) -or ($scriptConfig.Filers.CDOT.Controllers.Length -eq 0))
                                    {
                                        LogError "Configuration data missing CDOT 'Filers' controller list."
                                    }
                                }
                                else
                                {
                                    LogError "Configuration data missing CDOT 'Filers' data."
                                }
                            }
                            else
                            {
                                LogError "Configuration data missing 'Filers' data."
                            }

                            if($null -ne $scriptConfig.vCenter)
                            {
                                if(($null -eq $scriptConfig.vCenter.UserName) -or ([String]::IsNullOrEmpty($scriptConfig.vCenter.UserName)))
                                {
                                    LogError "Configuration data missing vCenter user name."
                                }

                                if($null -eq $scriptConfig.vCenter.Password)
                                {
                                    LogError "Configuration data missing vCenter password."
                                }

                                if(($null -eq $scriptConfig.vCenter.Server) -or ([String]::IsNullOrEmpty($scriptConfig.vCenter.Server)))
                                {
                                    LogError "Configuration data missing vCenter server name."
                                }
                            }
                            else
                            {
                                LogError "Configuration data missing 'vCenter' data."
                            }
                        }
                        else
                        {
                            Write-Error ("Log path: {0} is unavailable." -f @($scriptConfig.LogPath))
                        }
                    }
                    else
                    {
                        LogError ("Failed to create configuration data from contents of {0}." -f @($JSONArgsFile))
                    }
                }
                catch
                {
                    LogError ("Failed to create configuration data from contents of {0}." -f @($JSONArgsFile))
                }
            }
            else
            {
                LogError ("{0} does not exist." -f @($JSONArgsFile))
            }
        }
        else
        {
            LogError "Missing argument for .json configuration file."
        }

        # If there is something wrong with the script configuration data, clear it so it's not used.
        if ($Global:ErrorLogged)
        {
            $scriptConfig = $null
        }

        return $scriptConfig
    }
}
else
{
    Write-Error "CM Logging capability not available."
}
