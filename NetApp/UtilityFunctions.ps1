
$scalarTypeNames = @(
    "System.Boolean",
    "System.Boolean[]",
    "System.String",
    "System.String[]",
    "System.Int32",
    "System.Int32[]",
    "System.Int64"
    "System.Int64[]",
    "System.Net.IPAddress",
    "System.Net.IPAddress[]",
    "System.Decimal",
    "System.Decimal[]",
    "System.DateTime",
    "System.DateTime[]",
    "Api.Ontapi.ServerProtocol"
)

function GetNCCleanObj
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $obj,

        [Parameter(Mandatory=$false,Position=1)]
        [System.Object]
        $cleanObj,

        [Parameter(Mandatory=$false,Position=2)]
        [System.String]
        $className="",

        [Parameter(Mandatory=$false,Position=3)]
        [switch]
        $shallow
    )


    $props = @(Get-Member -InputObject $obj -MemberType Property | Select-Object -ExpandProperty Name)
    $nonSpecProps = @($props | Where-Object { $_ -notmatch "Specified$" } )
    $specProps = @($props | Where-Object { $_ -match "Specified$" } | ForEach-Object { $_.Replace("Specified","") })

    if ($null -eq $cleanObj)
    {
        $cleanObj = [PSCustomObject]::new()
    } `
    else # NOT ($null -eq $cleanObj)
    {
        # Nothing.
    }

    $a = 0
    while($a -lt $nonSpecProps.Length)
    {
        $p = $nonSpecProps[$a]
        $addProperty = $false

        if($specProps -contains $p)
        {
            if ($obj.$("{0}Specified" -f @($p)))
            {
                $addProperty = $true
            } `
            else # NOT ($obj.$("{0}Specified" -f @($propName)))
            {
                # Nothing.
            }
        } `
        else
        {
            $addProperty = $true
        }

        if ($addProperty)
        {
            if (-not [String]::IsNullOrEmpty($className))
            {
                $propName = "{0}.{1}" -f @($className, $p)
            } `
            else # NOT (-not [String]::IsNullOrEmpty($className))
            {
                $propName = $p
            }

            try
            {
                $typeName = $obj.$p.GetType().FullName
            }
            catch
            {
                $typeName = "N/A"
            }

            if ($scalarTypeNames -contains($typeName))
            {
                $cleanObj | Add-Member -MemberType NoteProperty -Name $p -Value $obj.$p
            } `
            else
            {
                if ((-not $shallow) -and ($null -ne ($obj.$p)) -and ($propName -notmatch "\.NcController"))
                {
                    if ($typeName -ne "N/A")
                    {
                        Write-Verbose (".{0} is [{1}]" -f @($propName, $typeName))
                    } `
                    else # NOT ($typeName -ne "N/A")
                    {
                        # Nothing.
                    }

                    $newProp = [PSCustomObject]::new()
                    $cleanObj | Add-Member -MemberType NoteProperty -Name $p -Value $newProp

                    # Don't need the return from the nested GetNCCleanObj since we are appending the new property to the parent...
                    #   i.e.: $newProp is already a member of $cleanObj....
                    $null = GetNCCleanObj -obj $obj.$p -cleanObj $newProp -className $propName
                } `
                else # NOT ($deep)
                {
                    # Nothing.
                }
            }
        } `
        else # NOT ($addProperty)
        {
            # Nothing.
        }

        $a++
    }

    return @(, $cleanObj)
}
