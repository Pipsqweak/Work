[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,Position=0)]
    [Switch]
    $TakeAction,

    [Parameter(Mandatory=$false,Position=1)]
    [String[]]
    $VolumesToInclude
)

function t1
{
    if($Script:TakeAction)
    {
        Write-Host "t1:Let do it!"
    }
    else
    {
        Write-Host "t1:Chicken!"
    }

    $a = 0
    while(($null -ne $Script:VolumesToInclude) -and ($a -lt $Script:VolumesToInclude.Length))
    {
        Write-Host ("{0}" -f @($Script:VolumesToInclude[$a]))
        $a++
    }
}

if($TakeAction)
{
    Write-Host "Let do it!"
}
else
{
    Write-Host "Chicken!"
}

if($null -ne $VolumesToInclude)
{
    if($VolumesToInclude -isnot [Array])
    {
        $VolumesToInclude = @($VolumesToInclude)
    }
}
else
{
    # Nothing, leave it $null so we include everything
}



t1
