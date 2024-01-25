class DataObject
{
    [System.Object] $_sourceObject = $null
    hidden [System.String] $_identity

    [void] AddPsuedoProperties()
    {
        # .Identity psuedo property
        $this | Add-Member -Name Identity -MemberType ScriptProperty -Value {
            return $this._identity
        } -SecondValue {
            param($value)
            $this._identity = $value
        }

        # .Name psuedo property  (use -Force to override in inherited classes)
        $this | Add-Member -Name Name -MemberType ScriptProperty -Value {
            if (-not [String]::IsNullOrEmpty($this._sourceObject.Name))
            {
                return $this._sourceObject.Name
            } `
            else # NOT (-not [String]::IsNullOrEmpty($this._sourceObject.Name))
            {
                return [String]::Empty
            }
        }

        # .ClassName psuedo property
        $this | Add-Member -Name ClassName -MemberType ScriptProperty -Value {
            return $this.GetType().Name.Replace("NetApp", "").Replace("VMware", "")
        }
    }

    DataObject([System.Object] $sourceObject)
    {
        ([DataObject] $this).AddPsuedoProperties()

        if ($null -eq $sourceObject)
        {
            throw "Missing sourceObject in DataObject."
        } `
        else # NOT ($null -eq $sourceObject)
        {
            # Nothing.
        }

        $this._sourceObject = $sourceObject
    }
}

class NetAppObject : DataObject
{
    [void] AddPsuedoProperties()
    {
        # .Controller psuedo property
        $this | Add-Member -Name Controller -MemberType ScriptProperty -Value {
            return $this._sourceObject.NcController
        }

        # .UUID psuedo property
        $this | Add-Member -Name UUID -MemberType ScriptProperty -Value {
            if($null -ne $this._sourceObject.Uuid)
            {
                return $this._sourceObject.Uuid
            } `
            else # NOT ($null -ne $this._sourceObject.Uuid)
            {
                throw "Missing UUID override in {0} object class." -f @($this.ClassName)
            }
        }

        # .ControllerName psuedo property
        $this | Add-Member -Name ControllerName -MemberType ScriptProperty -Value {
            if (-not [String]::IsNullOrEmpty($this.Controller.Name))
            {
                return ($this.Controller.Name -split '\.')[0].ToUpper()
            } `
            else # NOT (-not [String]::IsNullOrEmpty($this.Controller.Name))
            {
                return [String]::Empty;
            }
        }

        # .ControllerId psuedo property
        $this | Add-Member -Name ControllerID -MemberType ScriptProperty -Value {
            if (-not [String]::IsNullOrEmpty($this.Controller.Name))
            {
                return "{0}.{1}.{2}" -f @(($this.Controller.Name -split '\.')[0].ToUpper(), $this.Controller.Address, $this.Controller.Version)
            } `
            else # NOT (-not [String]::IsNullOrEmpty($this.Controller.Name))
            {
                return "{0}.{1}" -f @($this.Controller.Address, $this.Controller.Version)
            }
        }
    }

    NetAppObject([System.Object] $sourceObject)
        : base($sourceObject)
    {
        ([NetAppObject] $this).AddPsuedoProperties()

        if ($null -eq $sourceObject.NcController)
        {
            throw "Null NcController property in NetAppObject ctor."
        } `
        else # NOT ($null -eq $sourceObject.NcController)
        {
            # Nothing.
        }
    }
}

class NetAppCluster : NetAppObject
{
    [System.Collections.Generic.List[NetAppVServer]] $VServers = $null

    [void] AddPsuedoProperties()
    {
        # .UUID psuedo property
        $this | Add-Member -Force -Name UUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterUuid
        }

        # .Location psuedo property
        $this | Add-Member -Name Location -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterLocation
        }

        # .SerialNumber psuedo property
        $this | Add-Member -Name SerialNumber -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterSerialNumber
        }

        # .Contact psuedo property
        $this | Add-Member -Name Contact -MemberType ScriptProperty -Value {
            return $this._sourceObject.ClusterContact
        }

        # .Name psuedo property
        $this | Add-Member -Force -Name Name -MemberType ScriptProperty -Value {
            return $this.ControllerName
        }
    }

    [void] GetVServers()
    {
        if ($null -eq $this.VServers)
        {
            $this.VServers = [System.Collections.Generic.List[NetAppVServer]]::new()
            if ($null -eq $this.VServers)
            {
                throw "Unable to create VServers list in NetAppCluster::GetVServers."
            } `
            else # NOT ($null -eq $this.VServers)
            {
                # Nothing.
            }
        } `
        else # NOT ($null -eq $this.VServers)
        {
            $this.VServers.Clear()
        }

        try
        {
            $vss = Get-NcVserver -Controller $this.Controller -ErrorAction Stop
            foreach($vs in $vss)
            {
                $newVServer = [NetAppVServer]::new($this, $vs)

                if ($null -ne $newVServer)
                {
                    $this.VServers.Add($newVServer)
                } `
                else # NOT ($null -ne $newVServer)
                {
                    throw "Null NetAppVServer returned in NetAppCluster::GetVServers."
                }
            }
        }
        catch
        {
            throw "Unable to get VServers for {0}." -f @($this.Name)
        }
    }

    NetAppCluster([DataONTAP.C.Types.Cluster.ClusterIdentityInfo] $clusterInfo)
        : base($clusterInfo)
    {
        ([NetAppCluster] $this).AddPsuedoProperties()

        $this.GetVServers()
    }

    static [NetAppCluster] FromController([NetApp.Ontapi.Filer.C.NcController] $controller)
    {
        [NetAppCluster] $cluster = $null

        if ($null -ne $controller)
        {
            try
            {
                $c = Get-NcCluster -Controller $controller -ErrorAction Stop
                $cluster = [NetAppCluster]::new($c)
                $cluster.GetVServers()
            }
            catch
            {
                throw "Failed to create NetAppCluster from {0}." -f @($controller.Name)
            }
        } `
        else # NOT ($null -ne $controller)
        {
            throw "Null NcController in Cluster ctor."
        }

        return $cluster
    }
}

class NetAppClusterObject : NetAppObject
{
    [NetAppCluster] $Cluster

    NetAppClusterObject([Object] $srcObject, [NetAppCluster] $cluster)
        : base($srcObject)
    {
        if ($cluster.ControllerID -ne $this.ControllerID)
        {
            throw "Cluster mismatch: Cluster controller ID: {0}, {1} controller ID: {2}" -f @($cluster.ControllerID, $this.ClassName, $this.ControllerID)
        } `
        else # NOT ($cluster.ControllerID -ne $this.ControllerID)
        {
            $this.Cluster = $cluster
        }
    }
}

class NetAppVServer : NetAppClusterObject
{
#    [System.Collections.Generic.List[NetAppVolume]] $Volumes

    [void] AddPsuedoProperties()
    {
        # .Type psuedo property
        $this | Add-Member -Force -Name Type -MemberType ScriptProperty -Value {
            return $this._sourceObject.VserverType
        }

        # .Name psuedo property
        $this | Add-Member -Force -Name Name -MemberType ScriptProperty -Value {
            return $this._sourceObject.VserverName
        }
    }

    NetAppVServer([NetAppCluster] $cluster, [DataONTAP.C.Types.Vserver.VserverInfo] $vServer)
        : base($vServer, $cluster)
    {
        ([NetAppVServer] $this).AddPsuedoProperties()

        $this.Volumes = [System.Collections.Generic.List[NetAppVolume]]::new()
    }
}

class NetAppAggregate : NetAppClusterObject
{
    [void] AddPsuedoProperties()
    {
        # .Size psuedo property
        $this | Add-Member -Name Size -MemberType ScriptProperty -Value {
            return $this._sourceObject.AggrSpaceAttributes.SizeTotal
        }

        # .Available psuedo property
        $this | Add-Member -Name Available -MemberType ScriptProperty -Value {
            return $this._sourceObject.AggrSpaceAttributes.SizeAvailable
        }

        # .Used psuedo property
        $this | Add-Member -Name Used -MemberType ScriptProperty -Value {
            return $this._sourceObject.AggrSpaceAttributes.SizeUsed
        }

        # .UUID psuedo property
        $this | Add-Member -Force -Name UUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.AggregateUuid
        }
    }

    NetAppAggregate([NetAppCluster] $cluster, [DataONTAP.C.Types.Aggr.AggrAttributes] $aggregate)
        : base($aggregate, $cluster)
    {
        ([NetAppAggregate] $this).AddPsuedoProperties()
    }
}

class NetAppVolume : NetAppClusterObject
{
    [NetAppVServer] $VServer
    [NetAppAggregate] $Aggregate

    [void] AddPsuedoProperties()
    {
        # .Size psuedo property
        $this | Add-Member -Name Size -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeSpaceAttributes.Size
        }

        # .Available psuedo property
        $this | Add-Member -Name Available -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeSpaceAttributes.SizeAvailable
        }

        # .Used psuedo property
        $this | Add-Member -Name Used -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeSpaceAttributes.SizeUsed
        }

        # .UUID psuedo property
        $this | Add-Member -Force -Name UUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeIdAttributes.Uuid
        }

        # .AggregateUUID psuedo property
        $this | Add-Member -Name AggregateUUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeIdAttributes.ContainingAggregateUuid
        }

        # .VServerUUID psuedo property
        $this | Add-Member -Name VServerUUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeIdAttributes.OwningVserverUuid
        }

        # .IsSnapmirrorSource psuedo property
        $this | Add-Member -Name IsSnapmirrorSource -MemberType ScriptProperty -Value {
            return $this._sourceObject.VolumeMirrorAttributes.IsSnapmirrorSourceSpecified -and $this._sourceObject.VolumeMirrorAttributes.IsSnapmirrorSource
        }
    }

<#
    NEED TO ADD SNAPLOCKED...
#>

    NetAppVolume([NetAppVServer] $vServer, [NetAppAggregate] $aggregate, [DataONTAP.C.Types.Volume.VolumeAttributes] $volume)
        : base($volume, $vServer.Cluster)
    {
        ([NetAppVolume] $this).AddPsuedoProperties()

        if ($vServer.ControllerID -ne $aggregate.ControllerID)
        {
            throw "{0}/{1} mismatch: {0} controller ID: {2}, {1} controller ID: {3} in {4} ctor." -f @($vServer.ClassName, $aggregate.ClassName, $vServer.ControllerId, $aggregate.ControllerID, $this.ClassName)
        } `
        else # NOT ($vServer.ControllerID -ne $aggregate.ControllerID)
        {
            if ($vServer.UUID -eq $this.VServerUUID)
            {
                if ($aggregate.UUID -eq $this.AggregateUUID)
                {
                    $this.VServer = $vServer
                    $this.Aggregate = $aggregate
                } `
                else # NOT ($aggregate.UUID -eq $this.AggregateUUID)
                {
                    throw "{0}/{1} mismatch: {0} UUID: {2}, {1} Aggregate UUID: {3} in {1} ctor." -f @($aggregate.ClassName, $this.ClassName, $aggregate.UUID, $this.AggregateUUID)
                }
            } `
            else # NOT ($vServer.UUID -eq $this.VServerUUID)
            {
                throw "{0}/{1} mismatch: {0} UUID: {2}, {1} VServer UUID: {3} in {1} ctor." -f @($vServer.ClassName, $this.ClassName, $vServer.UUID, $this.VServerUUID)
            }
        }
    }
}

class NetAppShare : NetAppClusterObject
{
    [NetAppVolume] $Volume

    [void] AddPsuedoProperties()
    {
        # .UUID psuedo property  -- [DataONTAP.C.Types.Cifs.CifsShare] does not contain a UUID property, so I'll just return [String]::Empty
        $this | Add-Member -Force -Name UUID -MemberType ScriptProperty -Value {
            return [String]::Empty
        }

        # .Path psuedo property  -- [DataONTAP.C.Types.Cifs.CifsShare] does not contain a UUID property, so I'll just return [String]::Empty
        $this | Add-Member -Name Path -MemberType ScriptProperty -Value {
            return $this._sourceObject.Path
        }
    }

    NetAppShare([NetAppVolume] $volume, [DataONTAP.C.Types.Cifs.CifsShare] $share)
        : base($share, $volume.Cluster)
    {
        ([NetAppShare] $this).AddPsuedoProperties()

        if ($volume.Name -eq $this._sourceObject.Volume)
        {
            $this.Volume = $volume
        } `
        else # NOT ($volume.Name -eq $this._sourceObject.Volume)
        {
            throw "{0}/{1} mismatch: {0} name: {2}, {1} volume name: {3} in {1} ctor." -f @($volume.ClassName, $this.ClassName, $volume.Name, $this._sourceObject.Volume)
        }
    }
}

class NetAppLIF : NetAppClusterObject
{
    [NetAppVServer] $VServer

    [void] AddPsuedoProperties()
    {
        # .UUID psuedo property
        $this | Add-Member -Force -Name UUID -MemberType ScriptProperty -Value {
            return $this._sourceObject.LifUuid
        }

        # .Name psuedo property
        $this | Add-Member -Force -Name Name -MemberType ScriptProperty -Value {
            return $this._sourceObject.InterfaceName
        }

        # .Address psuedo property
        $this | Add-Member -Name Address -MemberType ScriptProperty -Value {
            return $this._sourceObject.Address
        }

        # .DataProtocols psuedo property
        $this | Add-Member -Name DataProtocols -MemberType ScriptProperty -Value {
            return $this._sourceObject.DataProtocols
        }
    }

    NetAppLIF([NetAppVServer] $vServer, [DataONTAP.C.Types.Net.NetInterfaceInfo] $lif)
        : base($lif, $vServer.Cluster)
    {
        ([NetAppLIF] $this).AddPsuedoProperties()

        if ($vServer.Name -eq $this._sourceObject.Vserver)
        {
            $this.VServer = $vServer
        } `
        else # NOT ($aggregate.UUID -eq $this.AggregateUUID)
        {
            throw "{0}/{1} mismatch: {0} Name: {2}, {1} VServer: {3} in {1} ctor." -f @($vServer.ClassName, $this.ClassName, $vServer.Name, $this._sourceObject.Vserver)
        }
    }
}

class VMwareDatastore : DataObject
{
    [void] AddPsuedoProperties()
    {
        # .ID psuedo property
        $this | Add-Member -Name ID -MemberType ScriptProperty -Value {
            if($null -ne $this._sourceObject.ID)
            {
                return $this._sourceObject.Uuid
            } `
            else # NOT ($null -ne $this._sourceObject.Uuid)
            {
                throw "Missing UUID override in {0} object class." -f @($this.ClassName)
            }
        }
    }

    VMwareDatastore([System.Object] $sourceObject, [NetAppVolume] $volume)
        : base($sourceObject)
    {
        ([VMwareDatastore] $this).AddPsuedoProperties()
    }
}

ConnectTo cdc,cdot
ConnectTo prod,vcenter
$c = Get-NcCluster -Controller $cdcCDOT
$vss = Get-NCVserver -Controller $cdcCDOT
$aggrs = Get-NCAggr -Controller $cdcCDOT
$vols = Get-NCVol -Controller $cdcCDOT
$shares = Get-NcCifsShare -Controller $cdcCDOT
$lifs = Get-NcNetInterface -Controller $cdcCDOT -DataProtocols "NFS"
$datastores = Get-Datastore -Server $vCenter | Where-Object { $_.Type -eq "NFS" }
$cifsServers = Get-NCCifsServer -Controller $cdcCDOT

do
{
    $testShareNum = Get-Random -Minimum 0 -Maximum $shares.Length
    $testShare = $shares[$testShareNum]
    $testVol = $vols | Where-Object { $_.Name -eq $testShare.Volume }
    $testVS = $vss | Where-Object { $_.VserverName -eq $testVol.Vserver }
    $testAggr = $aggrs | Where-Object { $_.Name -eq $testVol.Aggregate }
    $testLIF = $lifs | Where-Object { $_.Vserver -eq $testVS.Vserver } | Select-Object -First 1
} while($null -eq $testLIF)

$cluster = [NetAppCluster]::new($c)
$vServer = [NetAppVServer]::new($cluster, $testVS)
$aggregate = [NetAppAggregate]::new($cluster, $testAggr)
$volume = [NetAppVolume]::new($vServer, $aggregate, $testVol)
$share = [NetAppShare]::new($volume, $testShare)
$lif = [NetAppLIF]::new($vServer, $testLIF)





class D1
{
    static [System.String] $ClassName = "DataObject"
}

class E1 : D1
{
    static [System.String] $ClassName = "DataObject"
}

$a = [D1]::new()
$b = [E1]::new()

$vss2 = Get-NCVserver -Controller $cdcCDOT -ZapiCall
