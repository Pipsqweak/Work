[CmdletBinding(DefaultParameterSetName = "Normal")]
param (
    [Parameter(Mandatory=$true, ParameterSetName="Normal", Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $SourceVServerName,

    [Parameter(Mandatory=$true, ParameterSetName="Normal", Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $DRVServerName,

    [Parameter(Mandatory=$false, ParameterSetName="Normal", Position=2)]
    [Switch]
    $TakeAction,

    [Parameter(Mandatory=$false, ParameterSetName="Normal", Position=3)]
    [String[]]
    $VolumesToInclude,

    [Parameter(Mandatory=$false, ParameterSetName="Retry", Position=0)]
    [String]
    $RetryFileName
)

Write-Host ("{0}" -f @($PSCmdlet.ParameterSetName))

function t1
{
    [CmdletBinding(DefaultParameterSetName = "Normal")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="T1N", Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, ParameterSetName="T1N", Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DRVServerName,

        [Parameter(Mandatory=$false, ParameterSetName="T1N", Position=2)]
        [Switch]
        $TakeAction,

        [Parameter(Mandatory=$false, ParameterSetName="T1N", Position=3)]
        [String[]]
        $VolumesToInclude,

        [Parameter(Mandatory=$false, ParameterSetName="T1R", Position=0)]
        [String]
        $RetryFileName
    )

    Write-Host ("{0}" -f @($PSCmdlet.ParameterSetName))
}

function t2
{
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="T1N", Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, ParameterSetName="T1N", Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DRVServerName,

        [Parameter(Mandatory=$false, ParameterSetName="T1N", Position=2)]
        [Switch]
        $TakeAction,

        [Parameter(Mandatory=$false, ParameterSetName="T1N", Position=3)]
        [String[]]
        $VolumesToInclude,

        [Parameter(Mandatory=$false, ParameterSetName="Default", Position=0)]
        [Switch]
        $RetryFileName
    )

    Write-Host ("{0}" -f @($PSCmdlet.ParameterSetName))
}
