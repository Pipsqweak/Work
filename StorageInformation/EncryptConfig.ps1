<#
	Encrypt passwords in the script configuration json file.

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

$requiredFilesAvailable = $true
$requiredFiles = @(
    $JSONArgsFile,                 # Contains information used in the operation of the script.
    "CMTraceLog.ps1",              # PS script to provide CMTrace formatted logging
    "LoadConfigurationData.ps1"    # Loads the script configuration data and validates it.
)

$scriptRoot = $PSScriptRoot
if([String]::IsNullOrEmpty($scriptRoot))
{
    $scriptRoot = (Get-Location).Path
}
# Make sure all the files required to make this script functional are available.
foreach($requiredFile in $requiredFiles)
{
    $testFile = "{0}\{1}" -f @($scriptRoot, $requiredFile)
    if(-not [System.IO.File]::Exists($testFile))
    {
        Write-Error ("Missing required file: {0}." -f @($testFile))
        $requiredFilesAvailable = $false
    }
}

# If we are missing any of the required files, terminate the script.
if(-not $requiredFilesAvailable) { return }

# Source in the logging functions.
. .\CMTraceLog.ps1
if(-not $Global:CMLoggingAvailable)
{
    Write-Error "CM Logging capabilities not available"
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

# Load script initialization information.
$Global:scriptConfig = LoadConfigurationData $JSONArgsFile

# If errors were logged terminate the script
if($Global:ErrorLogged) { return }

# Use configuration data to define the log file name.
$Global:LogPath = "{0}\{1}.log" -f @($Global:scriptConfig.LogPath, [DateTime]::Now.ToString("yyyyMMdd"))

# Convert all the plain text passwords into encrypted strings.
$Global:scriptConfig.Filers.CDOT.Password = ConvertTo-SecureString -String $Global:scriptConfig.Filers.CDOT.Password -AsPlainText -Force | ConvertFrom-SecureString
$Global:scriptConfig.Filers.SM.Password = ConvertTo-SecureString -String $Global:scriptConfig.Filers.SM.Password -AsPlainText -Force | ConvertFrom-SecureString
$Global:scriptConfig.vCenter.Password = ConvertTo-SecureString -String $Global:scriptConfig.vCenter.Password -AsPlainText -Force | ConvertFrom-SecureString

# Save the configuration data back to the same file it was read from.
$Global:scriptConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $JSONArgsFile -Force
