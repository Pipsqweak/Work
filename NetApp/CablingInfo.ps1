$shelfEnvironment01 = Get-NcShelfEnvironment -Controller $adcCDOT -NodeName "ADC-NASA01"
$shelfEnvironment02 = Get-NcShelfEnvironment -Controller $adcCDOT -NodeName "ADC-NASA02"

$shelfEnvironment = $shelfEnvironment01
$cableDict = [System.Collections.Generic.SortedDictionary[[String],[System.Collections.Generic.SortedDictionary[[String],[Object[]]]]]]::new()

$a = 0
while($a -lt $shelfEnvironment.Length)
{
    Write-Host ("Channel: {0}" -f @($shelfEnvironment[$a].ChannelName))

    $b = 0
    while($b -lt $shelfEnvironment[$a].ShelfEnvironShelfList.Length)
    {
        Write-Host ("Shelf ID: {0,2:D2}, DevicePathPort: {1}" -f @($shelfEnvironment[$a].ShelfEnvironShelfList[$b].ShelfId, $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ControllerDevicePathPort))
        $c = 0
        while($c -lt $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation.Length)
        {
            $d = 0
            while($d -lt $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList.Length)
            {
                if(-not [String]::IsNullOrEmpty($shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableEndIdentifier))
                {
                    $endSNs = $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableSerialNo -split '-'

                    if($endSNs.Length -eq 2)
                    {
                        if(-not $cableDict.ContainsKey($endSNs[0]))
                        {
                            $cableDict.Add($endSNs[0], [System.Collections.Generic.SortedDictionary[[String],[Object[]]]]::new() )
                        }

                        if(-not $cableDict[$endSNs[0]].ContainsKey($endSNs[1]))
                        {
                            $cableDict[$endSNs[0]].Add($endSNs[1], @())
                        }

                        $obj = "" | Select-Object Channel, PortPath, SasConnector
                        $obj.Channel = $shelfEnvironment[$a].ChannelName
                        $obj.PortPath = $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ControllerDevicePathPort
                        $obj.SasConnector = $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d]

                        $cableDict[$endSNs[0]][$endSNs[1]] += $obj
                    }
                    Write-Host ("{0}, {1}, {2}, {3}, {4}" -f @($shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableEndIdentifier, $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableSerialNo, $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableLength, $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].ConnectorDesignator, $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CablePartNo))
                }
                $d++
            }

            $c++
        }
        $b++
    }
    $a++
}


<#
    Gets the ID and WWN for the SAS ports on all the nodes of a cluster.
#>
function GetControllerNodeSASPorts
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    $results = @()

    $storageAdapters = Get-NcStorageAdapter -Controller $controller
    $a = 0
    while($a -lt $storageAdapters.Length)
    {
        $adapter = $storageAdapters[$a]

        $o = "" | Select-Object Node,Adapter,WWN,Details

        $o.Node = $adapter.NodeName
        $o.Adapter = $adapter.AdapterName

        $adapterInfo = Get-NcStorageAdapterInfo -Name $o.Adapter -Controller $controller -Node $o.Node
        $o.Details = $adapterInfo

        if($adapterInfo.AdapterDetailInfo.AdapterType -eq "ADT_IF_SAS")
        {
            $o.WWN = $adapterInfo.AdapterDetailInfo.AdapterSas.AdapterSasInfo.BaseWwn.Replace(":","").ToUpper()
            $results += $o
        }

        $a++
    }

    return @(, $results)
}

$storageShelves = Get-NcStorageShelf -Controller $adcCDOT
$nodeAdapterWWNs = $nodeAdapters | Select-Object -Unique -ExpandProperty WWN


$shelfSASPorts = @()
$a = 0
while($a -lt $storageShelves.Length)
{
    Write-Host ("{0,2:D2}:{1}:{2}:{3}" -f @($storageShelves[$a].ShelfId, $storageShelves[$a].ShelfModel, $storageShelves[$a].SerialNumber, $storageShelves[$a].DiskCount))

    $b = 0
    while($b -lt $storageShelves[$a].SasPorts.Length)
    {
        if(($storageShelves[$a].SasPorts[$b].SasPortWwpn -notin $nodeAdapterWWNs) -and ($storageShelves[$a].SasPorts[$b].SasPortType -in @("circle","square","host")) -and ($storageShelves[$a].SasPorts[$b].SasPortWwpn -ne "-"))
        {
            $o = "" | Select-Object ShelfID,ModuleID, Type, WWN
            $o.ShelfID = $storageShelves[$a].ShelfId
            $o.ModuleID = $storageShelves[$a].SasPorts[$b].SasPortModuleId
            $o.Type = $storageShelves[$a].SasPorts[$b].SasPortType
            $o.WWN = $storageShelves[$a].SasPorts[$b].SasPortWwpn
            if(@($shelfSASPorts | Where-Object { ($_.ShelfID -eq $o.ShelfID) -and ($_.ModuleId -eq $o.ModuleID) -and ($_.Type -eq $o.Type) -and ($_.WWN -eq $o.WWN) } ).Length -eq 0)
            {
                Write-Host ("`t{0}, {1}, {2}, {3}" -f @($storageShelves[$a].SasPorts[$b].SasPortId, $storageShelves[$a].SasPorts[$b].SasPortModuleId, $storageShelves[$a].SasPorts[$b].SasPortType, $storageShelves[$a].SasPorts[$b].SasPortWwpn))
                $shelfSASPorts += $o
            }
        }
        $b++
    }
    $a++
}

$shelfSasPorts = $shelves1[0].SasPorts | Where-Object { $_.SasPortType -in @("circle","square") }

$shelfSASPortWWNs = $shelfSasPorts | Select-Object -Unique -ExpandProperty SasPortWwpn | Where-Object { $nodeAdapterWWNs -notcontains $_ }



$shelfPorts = Get-NcStorageShelfPort -Controller $cdcCDOT


$storageShelves = Get-NcStorageShelf -Controller $cdcCDOT
$storagePorts = Get-NcStoragePort -Controller $cdcCDOT -Node "CDC-NASA01"

$a = 0
while($a -lt $storagePorts.Length)
{
    # $shelfPort1 : the shelf port connected to the node's storage port
    $shelfPort1 = $shelfPorts | Where-Object { $_.CableId -eq $storagePorts[$a].CableIdentifier }

    if($null -ne $shelfPort1)
    {
        # shelfPort2 : the shelf port on the same module connected to the downstream shelf
        $shelfPort2 = $shelfPorts | Where-Object { ($_.IsCableConnected) -and ($_.ModuleId -eq $shelfPort1.ModuleId) -and ($_.Wwn -eq $shelfPort1.Wwn) -and ($_.RemoteWwn -ne $storagePorts[$a].Wwn.Replace(':',''))  }

        # $shelf is the shelf associated with $shelfPort1 and $shelfPort2
        $shelf = $storageShelves | Where-Object { $_.Shelf -eq $shelfPort1.Shelf }

        if($null -ne $shelf)
        {
            # The upstream device, the node and stoage port...
            $aSide = "{0}:{1}:{2}" -f @($storagePorts[$a].Node, $storagePorts[$a].Port, $storagePorts[$a].Wwn.Replace(':',''))

            # The first storage shelf
            $bSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}" -f @($shelf.ShelfModel, $shelf.SerialNumber, $shelf.ShelfId, $shelfPort1.ModuleId, $shelfPort1.Designator, $shelfPort1.CableTechnology, $shelfPort1.CablePartNumber, $shelfPort1.Wwn))

            Write-Host ("{0}  <-- ( {1} ) -->  {2}" -f @($aSide, $shelfPort.CableLength, $bSide))

            do
            {

                $aSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}" -f @($shelf.ShelfModel, $shelf.SerialNumber, $shelf.ShelfId, $shelfPort2.ModuleId, $shelfPort2.Designator, $shelfPort2.CableTechnology, $shelfPort2.CablePartNumber, $shelfPort2.Wwn))

                $nextShelfPort1 = $shelfPorts | Where-Object { ($_.IsCableConnected) -and ($_.Wwn -eq $shelfPort2.RemoteWwn) -and ($_.ModuleId -eq $shelfPort2.ModuleId) -and ($_.RemoteWwn -eq $shelfPort1.Wwn) }
                $shelf = $storageShelves | Where-Object { $_.Shelf -eq $nextShelfPort1.Shelf }
                $bSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}" -f @($shelf.ShelfModel, $shelf.SerialNumber, $shelf.ShelfId, $nextShelfPort1.ModuleId, $nextShelfPort1.Designator, $nextShelfPort1.CableTechnology, $nextShelfPort1.CablePartNumber, $nextShelfPort1.Wwn))

                Write-Host ("{0}  <-- ( {1} ) -->  {2}" -f @($aSide, $shelfPort2.CableLength, $bSide))

                $shelfPort2 = $shelfPorts | Where-Object { ($_.IsCableConnected) -and ($_.Wwn -eq $nextShelfPort1.Wwn) -and ($_.ModuleId -eq $nextShelfPort1.ModuleId) -and ($_.RemoteWwn -ne $nextShelfPort1.RemoteWwn) }


                $aSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}" -f @($shelf.ShelfModel, $shelf.SerialNumber, $shelf.ShelfId, $nextShelfPort1.ModuleId, $nextShelfPort1.Designator, $nextShelfPort1.CableTechnology, $nextShelfPort1.CablePartNumber, $nextShelfPort1.Wwn))

                # Works to here....

                [int] $shelfStackNumber, [int] $shelfID = $shelfPort1.Shelf -split '\.'

                # The name of the next shelf, if there is one.
                $nextShelfName = "{0}.{1}" -f @($shelfStackNumber, ($shelfID + 1))

                # The shelf port 1 for the next downstream disk shelf
                $nextShelfPort1 = $shelfPorts | Where-Object { ($_.ModuleId -eq $shelfPort2.ModuleId) -and ($_.RemoteWwn -eq $shelfPort2.Wwn) -and ($_.IsCableConnected) -and ($_.Shelf -eq $nextShelfName) }

                # nextShelfPort2 : the shelf port on the same module connected to the downstream shelf
                $nextShelfPort2 = $shelfPorts | Where-Object { ($_.ModuleId -eq $nextShelfPort1.ModuleId) -and ($_.IsCableConnected) -and ($_.Shelf -eq $nextShelfName) } -and ($_.RemoteWwn -eq $shelfPort2.Wwn) }


                if($null -ne $nextShelfPort)
                {
                    # $nextShelf is the shelf associated with $nextShelfPort1
                    $nextShelf = $storageShelves | Where-Object { $_.Shelf -eq $nextShelfPort1.Shelf }

                    if($null -ne $nextShelf)
                    {
                        $shelfPort = $shelfPorts | Where-Object { ($_.RemoteWwn -eq $nextShelfPort.Wwn) -and ($_.IsCableConnected) -and ($_.Shelf -eq $shelfPort.Shelf) }

                        if($null -ne $shelfPort)
                        {

                            $aSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}" -f @($nextShelf.ShelfModel, $nextShelf.SerialNumber, $nextShelfPort.ModuleId, $nextShelfPort.Designator, $nextShelfPort.CableTechnology, $nextShelfPort.CablePartNumber, $nextShelfPort.Wwn))
                            $bSide = ("{0}:{1}:{2}:{3}:{4}:{5}:{6}" -f @($shelf.ShelfModel, $shelf.SerialNumber, $shelfPort.ModuleId, $shelfPort.Designator, $shelfPort.CableTechnology, $shelfPort.CablePartNumber, $shelfPort.Wwn))
                            Write-Host ("{0}  <-- ( {1} ) -->  {2}" -f @($aSide, $shelfPort.CableLength, $bSide))

                            $shelf = $nextShelf
                        }
                    }
                }
                else
                {
                    # End of the stack... Controller 2 will be here.
                }

            } while($true)
        }
    }
    else
    {
        # Might be a shelfLess node ... need to see if the other end of the cable is connected to another node.  Unfortunately, at the time I wrote this, I didn't have a shelfless node to test on.
        Write-Host ("{0}:{1}:{2} - No shelf port found" -f @($storagePorts[$a].Node, $storagePorts[$a].Port, ($storagePorts[$a].Wwn.Replace(':','').ToUpper())))
    }


    $a++
}


$a = 0
while($a -lt $shelfEnvironment.Length)
{
    $b = 0
    while($b -lt $shelfEnvironment[$a].ShelfEnvironShelfList.Length)
    {
        $c = 0
        while($c -lt $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation.Length)
        {
            $d = 0
            while($d -lt $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList.Length)
            {
                $cableShelfPorts = @($shelfPorts | Where-Object { ($_.CableId -eq $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableSerialNo) -and ($_.IsCableConnected) })

                $e = 0
                while($e -lt $cableShelfPorts.Length)
                {
                    Write-Host -NoNewline ("a:{0} | b:{1} | c:{2} | d:{3} | e:{4} |" -f @($a, $b, $c, $d, $e))
                    Write-Host ("{0}:{1}:{2}:{3}:{4}:{5}:{6}" -f @(
                        $shelfEnvironment[$a].NodeName,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ControllerDevicePathPort,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableSerialNo,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].ConnectorDesignator,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].ConnectorNo,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableTechnology,
                        $shelfEnvironment[$a].ShelfEnvironShelfList[$b].ConnectorInformation[$c].SasConnectorList[$d].CableLength))

                    $e++
                }

                $d++
            }
            $c++
        }
        $b++
    }
    $a++
}

$sasPorts = GetControllerNodeSASPorts $cdcCDOT
$shelfPorts = Get-NcStorageShelfPort -Controller $cdcCDOT
$a = 0
$stopLoop = $false
while(($a -lt $sasPorts.Length) -and (-not $stopLoop))
{
    $shelf = $shelves | Where-Object { $_.SasPorts | Where-Object { $_.SasPortWwpn -eq $sasPorts[$a].WWN }}
    $shelfSASPort = $shelf.SasPorts | Where-Object { ($_.SasPortWwpn -eq $sasPorts[$a].WWN) } | Sort-Object -Property SasPortID | Select-Object -First 1

    # Find the shelf SAS port the node is connected to...
    $shelfToNodeSASPort = $shelfPorts | Where-Object { $_.RemoteWwn -eq $sasPorts[$a].WWN }

    if([String]::IsNullOrEmpty($shelfToNodeSASPort.CableEnd) -and [String]::IsNullOrEmpty($shelfToNodeSASPort.CableTechnology))
    {
        $cableTech = "internal"
    } `
    else
    {
        $cableTech = "{0}:{1}:{2}" -f @($shelfToNodeSASPort.CableLength, $shelfToNodeSASPort.CableTechnology, $shelfToNodeSASPort.ConnectorType)
    }

    $cableID = $shelfToNodeSASPort.CableId.ToUpper()

    Write-Host ("{10}) {0}:{1}({2}) <-- {3} ({4}) --> Shelf:{5}:{6}:{7}:{8} ({9})" -f @(
        $sasPorts[$a].Node,
        $sasPorts[$a].Adapter,
        $sasPorts[$a].WWN,
        $cableID,
        $cableTech,
        $shelf.ShelfId,
        $shelf.SerialNumber,
        $shelfToNodeSASPort.ModuleId,
        $shelfToNodeSASPort.Designator,
        $shelfToNodeSASPort.Wwn,
        $a))

    # Now I need to trace the rest of the shelves in the stack...

    # Get the shelf SAS port the node is NOT connected to ... this will be the SAS port connected to the next shelf/node in the stack...
    $shelfToNextDeviceSASPort = $shelfPorts | Where-Object { ($_.Wwn -eq $shelfToNodeSASPort.Wwn) -and ($_.RemoteWwn -ne $sasPorts[$a].WWN) }

    $shelfToShelfConnectorIDs = @($connectorDict.Keys) | Where-Object { $_.Contains($shelfToNextDeviceSASPort.RemoteWwn) }

    $shelfCableID = $shelfToNextDeviceSASPort.CableId.ToUpper()
    if($connectorDict.ContainsKey($shelfCableID))
    {
        $nextDevice = $connectorDict[$shelfCableID] | Where-Object { ($_.Node.Node -eq $sasPorts[$a].Node) -and ($_.SasConnector.CableEndIdentifier -eq $shelfToNextDeviceSASPort.CableEnd) }
        $nextShelf = $shelves | Where-Object { $_.SerialNumber -eq $nextDevice.Shelf.SasSpecificInfo.SerialNo }

    }

    #$shelfPorts | Where-Object { $_.RemoteWwn -eq $shelfPort.Wwn }
    if(-not $stopLoop)
    {
        $a++
    }
}


$t1 = $shelves | Where-Object { $_.SasPorts | Where-Object { $_.SasPortWwpn -eq $sasPorts[0].WWN }}

$t1.SasPorts | Where-Object { ($_.SasPortWwpn -eq $sasPorts[0].WWN) } | Sort-Object -Property SasPortID | Select-Object -First 1


foreach($shelfEnvironment in $shelfEnvironment01)
{
    Write-Host ("`r`n{0}:{1}" -f @(
        $shelfEnvironment.NodeName,
        $shelfEnvironment.ChannelName))

    foreach($shelfEnvironmentShelf in $shelfEnvironment.ShelfEnvironShelfList)
    {
        Write-Host ("`t{0}:{1}" -f @($shelfEnvironmentShelf.ControllerDevicePathPort, $shelfEnvironmentShelf.ShelfType))

        foreach($connector in $shelfEnvironmentShelf.ConnectorInformation)
        {
            foreach($sasConnector in $connector.SasConnectorList)
            {
                if(-not [String]::IsNullOrEmpty($sasConnector.CableSerialNo))
                {
                    Write-Host ("`t`t{0}:{1}:{2}:{3}:{4}:{5}" -f @($sasConnector.CableSerialNo, $sasConnector.CableLength, $sasConnector.CableTechnology, $sasConnector.ConnectorDesignator, $sasConnector.CableEndIdentifier, $sasConnector.ConnectorNo))
                }
            }
        }
    }
}

$l = [System.Collections.Generic.List[Object]]

$connectorDict = [System.Collections.Generic.SortedDictionary[String,[System.Collections.Generic.List[Object]]]]::new()
$controller = $cdcCDOT
$nodes = Get-NcNode -Controller $controller
$a = 0
while($a -lt $nodes.Length)
{
    Write-Host ("{0}" -f @($nodes[$a].Node))
    $shelfEnvironment = Get-NcShelfEnvironment -Controller $controller -NodeName $nodes[$a].Node
    $b = 0
    while($b -lt $shelfEnvironment.Length)
    {
        Write-Host ("`t{0}" -f @($shelfEnvironment[$b].ChannelName))
        $c = 0
        while($c -lt $shelfEnvironment[$b].ShelfEnvironShelfList.Length)
        {
            Write-Host ("`t`t{0}" -f @($shelfEnvironment[$b].ShelfEnvironShelfList[$c].ControllerDevicePathPort))
            $d = 0
            while($d -lt $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation.Length)
            {
                Write-Host ("`t`t`tConnector: {0}" -f @($d))
                $e = 0
                while($e -lt $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation[$d].SasConnectorList.Length)
                {
                    Write-Host ("`t`t`t`tSasConnector: {0}" -f @($e))
                    if(-not [String]::IsNullOrEmpty($shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation[$d].SasConnectorList[$e].CableSerialNo))
                    {
                        $cblSN = $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation[$d].SasConnectorList[$e].CableSerialNo.ToUpper()
                        Write-Host ("`t`t`t`t`t{0}" -f @($cblSN))
                        if(-not $connectorDict.ContainsKey($cblSN))
                        {
                            $nl = [System.Collections.Generic.List[Object]]::new()
                            $connectorDict.Add($cblSN, $nl)
                        }

                        $f = $connectorDict[$cblSN] | Where-Object {
                            ($_.Node.NodeSerialNumber -eq $nodes[$a].NodeSerialNumber) -and `
                            ($_.ShelfEnvironment.ChannelName -eq $shelfEnvironment[$b].ChannelName) -and `
                            ($_.Shelf.ShelfId -eq $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ShelfId)
                        }

                        if($null -eq $f)
                        {
                            $g = "" | Select-Object Node, ShelfEnvironment, Shelf, Connector, SasConnector
                            $g.Node = $nodes[$a]
                            $g.ShelfEnvironment = $shelfEnvironment[$b]
                            $g.Shelf = $shelfEnvironment[$b].ShelfEnvironShelfList[$c]
                            $g.Connector = $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation[$d]
                            $g.SasConnector = $shelfEnvironment[$b].ShelfEnvironShelfList[$c].ConnectorInformation[$d].SasConnectorList[$e]

                            $connectorDict[$cblSN].Add($g)
                        }
                    }
                    $e++
                }
                $d++
            }
            $c++
        }
        $b++
    }
    $a++
}


$storageShelves = Get-NcStorageShelf -Controller $cdcCDOT -ConnectionType "sas"
# $storageShelves[x].SasPorts[y].SasPortWwpn = the WWN of the remote device -- NOT the WWN of the port itself.
<#
    PS C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS> $storageShelves[0].SasPorts | Where-Object { $_.SasPortType -notin @("sil","disk") } | Select-Object -Unique SasPortModuleId,SasPortType,SasPortWwpn

    SasPortModuleId SasPortType SasPortWwpn
    --------------- ----------- -----------
    a               square      500a09800e16a9f0  <-- CDC-NASA02:0a
    a               circle      500a0980050a24ff  <-- Shelf ID 1 : SHJMS1516000490 : Module a : sqr
    b               square      500a09800e16aa90  <-- CDC-NASA01:0a
    b               circle      500a09800507623f  <-- Shelf ID 1 : SHJMS1516000490 : Module b : sqr
#>
