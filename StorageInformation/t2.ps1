<# TEST CODE FROM HERE ON... #>

<#
    Debugging code to clear datastore data.

    foreach($c in $clusters)
    {
        foreach($v in $c.VServers)
        {
            foreach($vv in $v.Volumes)
            {
                $vv.Datastores.Clear()
            }
        }
    }
#>
<#
    Used to help figure out why I wasn't getting all the VMs in a datestore.  Turns out I had to uninstall POWERCLI and reinstall it.

    $a = 0
    $faults = 0
    while($a -lt $vmDatastores.Length)
    {
        try
        {
            $vms = Get-VM -Server $vcenter -Datastore $vmDatastores[$a] -ErrorAction Stop
            #Write-Host ("{0}: {1}: {2} VMs" -f @($a, $vmDatastores[$a].Name, $vms.Length))
        }
        catch
        {
            $faults++
            Write-Host ("FAULT({2}): {0}: {1}" -f @($a, $vmDatastores[$a].Name, $faults))
        }
        $a++
    }
#>

<#
    Test stuff...

for($a = 0; $a -lt $dataMaps.Length; $a++)
{
    $dataMaps[$a].DataSource = $null
}

$datamaps | ConvertTo-Json -Depth 5 | Set-Clipboard


$cmd = $myConn.CreateCommand()
$cmd.CommandType = [System.Data.CommandType]::Text
$tableDefinitions = @(
    for($a = 0; $a -lt $dataMaps.Length; $a++)
    {
        $d = "" | Select-Object TableName,Columns
        $d.TableName = $dataMaps[$a].TableName
        $cmd.CommandText = "SELECT * FROM [{0}] WHERE (1=0);" -f @($d.TableName)
        $tableSchemaReader = $cmd.ExecuteReader()
        $dtTableSchema = $tableSchemaReader.GetSchemaTable()
        $d.Columns = $dtTableSchema | Select-Object ColumnName,DataType

        $d
        $tableSchemaReader.Close()
    }
)



$dataMaps | ForEach-Object {
    if(@($_.PropertyMap | Where-Object { $_.ColumnName -eq "RunID" }).Length -gt 0)
    {
        "DELETE FROM [{0}] WHERE (RunID = 2);" -f @($_.TableName)
    }
}

#>

# command.CommandText = "UPDATE Student SET Address = @add, City = @cit Where FirstName = @fn and LastName = @add";
# "UPDATE [{0}] SET {1} WHERE {2};"


$JSONArgsFile
Test-Path -Path $JSONArgsFile
[System.IO.File]::Exists($JSONArgsFile)
