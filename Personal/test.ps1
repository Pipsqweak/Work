[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0)]
    [Switch]
    $NoDBUpdates
)

if($NoDBUpdates)
{
    Write-Host "Not updating the database"
}
else
{
    Write-Host "Updating the database"
}
