using namespace System.IO

<#
    This script uses 2 external files.  One to tell it which DirectAccess servers to query,
    and another to tell it which NetScalers to query.

    DirectAccess File format (json)
    --------------------------------------------------------------------

#>

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $DAQueryInfoFileName,

    [Parameter(Mandatory=$false,Position=1)]
    [String]
    $LogFileName = [String]::Empty
)

<#
   Test Data

   $DAQueryInfoFileName = "C:\Users\kbriney\KLB\PEI-IT-OPS\DAStats\DAQueryInfo.json"
#>

# Ensure parameter $LogFileName is globally accessible
$Global:LogFileName = $LogFileName

function Log
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $message
    )

    # Decorate the message
    $msg = "{0} : {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HH:mm:ss"), $message)

    # Should the function log to a file, or STDOUT?
    if (($null -ne $Global:LogFileName) -and [Directory]::Exists([Path]::GetFullPath([Path]::GetDirectoryName($Global:LogFileName))))
    {
        # TRUE : Log to file

        $msg | Out-File -FilePath $Global:LogFileName -Append
    }
    else # NOT (($null -ne $Global:LogFileName) -and [Directory]::Exists([Path]::GetFullPath([Path]::GetDirectoryName($Global:LogFileName))))
    {
        # FALSE : Log to STDOUT

        Write-Output $msg
    }
}  # End Log

function LoadQueryData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $DAQueryInfoFileName
    )

    # Initialize some variables
    [Object] $qd = $null

    # Did the user provide a file specifying DirectAccess/NetScaler query information?
    if (-not [String]::IsNullOrEmpty($DAQueryInfoFileName))
    {
        # TRUE

        # Does the DA Sites file exist?
        if ([File]::Exists($DAQueryInfoFileName))
        {
            # TRUE
            try
            {
                $qd = Get-Content -Path $DAQueryInfoFileName -Raw -ErrorAction Stop | ConvertFrom-Json
            }
            catch
            {
                Log ("ERROR: Unable to read query data from {0}" -f @($DAQueryInfoFileName))
            }
        }
        else # NOT ([File]::Exists($DAQueryInfoFileName))
        {
            # FALSE

            Log ("ERROR: Query data file ({0}) does not exist." -f @($DAQueryInfoFileName))
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($DAQueryInfoFileName))
    {
        # FALSE

        Log "ERROR: Query data file name is blank."
    }

    return $qd
}  # End LoadQueryData

# Data used to query DirectAccess Servers and NetScalers
[Object] $queryData = LoadQueryData $DAQueryInfoFileName

if ($null -ne $queryData)
{
    # TRUE

}
else # NOT ($null -ne $queryData)
{
    # FALSE

    Log "No query data available."
}
