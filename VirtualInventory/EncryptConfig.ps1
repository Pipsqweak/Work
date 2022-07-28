<#
	Encrypt passwords in the virtual inventory configuration json file.

	The input file will be replaced with the same data it contained, except passwords will be encrypted.

    Encrypted strings, which are safe to store in a file are creating using native Windows Data Protection API (DAPI).
	The clear text passwords are first converted to a SecureString then into an encrypted string to be stored back in
	the configuration file.
	
	NOTE:  The way DAPI works, the encryption is such that only the original user on the original machine the encryption was
	performed on can decrypt the string back into a SecureString to be reused.  Therefore, this script must be executed using the
	save computer and user account that will be used to ultimately consume the encrypted passwords.
	
	This script assumes passwords are in plain text.  So, if the passwords have already been encrypted, running this script
	against the same file twice will result in double encrypted passwords, which will likely cause authentication issues for
	any other script that consumes the data in the file.
#>
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

# Source in the [Log] class because it is used in LoadConfigurationData.ps1.
. .\Log.ps1   # Once the [Log] class is loaded

# If the assignment statement below is executed outside a try-catch, it throws an error.  I like to catch it myself.
try
{
    $logClassFound = ($null -eq [Log])
}
catch
{
    Write-Error "Unable to locate the [Log] class, terminating script."
    return
}

# Source in LoadConfigurationData function.  This function is stored externally since it is used in other scripts.
. .\LoadConfigurationData.ps1

# Verify LoadConfigurationData was source into the script.
try
{
    Get-ChildItem -Path Function:\LoadConfigurationData -ErrorAction Stop | Out-Null
}
catch
{
    Write-Error "Unable to locate Function:\LoadConfigurationData, terminating script."
    return
}

# Load script configuration information.
$inventoryConfig = LoadConfigurationData $JSONArgsFile

# Convert all the plain text passwords into encrypted strings.
$inventoryConfig.Filers.CDOT.Password = ConvertTo-SecureString -String $inventoryConfig.Filers.CDOT.Password -AsPlainText -Force | ConvertFrom-SecureString
$inventoryConfig.Filers.SM.Password = ConvertTo-SecureString -String $inventoryConfig.Filers.SM.Password -AsPlainText -Force | ConvertFrom-SecureString
$inventoryConfig.xClarity.Password = ConvertTo-SecureString -String $inventoryConfig.xClarity.Password -AsPlainText -Force | ConvertFrom-SecureString
$inventoryConfig.vCenter.Password = ConvertTo-SecureString -String $inventoryConfig.vCenter.Password -AsPlainText -Force | ConvertFrom-SecureString
$inventoryConfig.IPAMDB.Password = ConvertTo-SecureString -String $inventoryConfig.IPAMDB.Password -AsPlainText -Force | ConvertFrom-SecureString
$inventoryConfig.Statseeker.Password = ConvertTo-SecureString -String $inventoryConfig.Statseeker.Password -AsPlainText -Force | ConvertFrom-SecureString

# Save the configuration data back to the same file it was read from.
$inventoryConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $JSONArgsFile -Force