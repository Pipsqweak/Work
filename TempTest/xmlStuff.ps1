[XML] $xml = Get-Content -path "E:\Tmp\PEI.License.Servers.Monitors.xml"

$datasources = $xml.ChildNodes.Monitoring.Discoveries.Discovery.Datasource

$data = @(
    $a = 0
    while($a -lt $datasources.Length)
    {
        if($null -ne $datasources[$a].ServiceName)
        {
            $d = "" | Select-Object ServiceName,DisplayName
            $d.ServiceName = $datasources[$a].ServiceName

            $d.DisplayName = ($datasources[$a].InstanceSettings.Settings.Setting | Where-Object { $_.Name.Contains("DisplayName") -and $_.Name.Contains("System.Entity") }).Value

            $d
        }
        $a++
    }
)

$serviceNames = $xml.ChildNodes.Monitoring.Discoveries.Discovery.Datasource.ServiceName


$archiveData = "" | Select-Object ProjectRoot,ArchiveRoot,HintFileName,ArchiveProjects

$archiveData.ProjectRoot = "C:\Users\kbriney\POWER Engineers, Inc\TM-Viz File Share - _Projects"
$archiveData.ArchiveRoot = "\\boifs1\Visual_Tech\projects_1\Projects"
$archiveData.ArchiveProjects = @()


$d = "" | Select-Object Source,Destination,Start,Complete
$d.Source = "AEP"
$d.Destination = $null

$archiveData.ArchiveProjects += $d
$d = "" | Select-Object Source,Destination,Start,Complete
$d.Source = "Idaho Power"
$d.Destination = "Idaho Power Archive"

$archiveData.ArchiveProjects += $d
