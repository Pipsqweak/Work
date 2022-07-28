<#
.SYNOPSIS
Display a yellow warning message on the host.

.DESCRIPTION
Prepend "WARNING" to the specified message and display it in yellow on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a warning message on the host.

.EXAMPLE
PS> ReportWarning "This is a warning."
WARNING: This is a warning.

.LINK
None
#>
function ReportWarning
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Yellow ("WARNING: {0}" -f @($message))
}

<#
.SYNOPSIS
Display a white message on the host.

.DESCRIPTION
Display the specified message in white on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a message on the host.

.EXAMPLE
PS> ReportNotice "This is a notice."
This is a notice.

.LINK
None
#>
function ReportNotice
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor White $message
}

<#
.SYNOPSIS
Display a green message on the host.

.DESCRIPTION
Display the specified message in green on the host.

.PARAMETER Message
The message to display.

.INPUTS
None.

.OUTPUTS
Displays a message on the host.

.EXAMPLE
PS> ReportSuccess "This is a successful message."
This is a successful message.

.LINK
None
#>
function ReportSuccess
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Green $message
}

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
        # TRUE

        $myValueStr = $myValue.ToString()

        if (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # TRUE

            $quotedValue = "`"{0}`"" -f @($myValue.ToString())
        }
        else # NOT (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ($null -ne $myValue)
    {
        # FALSE

        # Nothing.
    }

    return $quotedValue
}




# $virtualizationDefinition = Get-Content -Path ".\VMware\cdcDMZv2.json" | ConvertFrom-Json
# $virtualizationDefinition = Get-Content -Path ".\VMware\ddcInternalv2.json" | ConvertFrom-Json
