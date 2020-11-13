# Define the database connection class
Write-Host "Checking for MySQL.Data assembly..."
if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
{
    Write-Host "MySQL.Data assembly not found..."
    Write-Host "Loading assembly: MySQL.Data..."
    [System.Reflection.Assembly]::LoadWithPartialName("MySQL.Data") | Out-Null

    Write-Host "Rechecking for MySQL.Data assembly..."
    if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
    {
        throw "Unable to load MySQL.Data assembly."
    }
    else
    {
        Write-Host "Assembly MySQL.Data successfully loaded..."
    }
}
else
{
    Write-Host "MySQL.Data assembly found..."
}