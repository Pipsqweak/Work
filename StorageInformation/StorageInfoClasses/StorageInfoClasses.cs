using System;
using System.Reflection;
using System.Collections.Generic;
using System.Linq;
using DataONTAP.C.Types.Cluster;
using DataONTAP.C.Types.Vserver;
using DataONTAP.C.Types.Aggr;
using DataONTAP.C.Types.Volume;
using DataONTAP.C.Types.Snapmirror;
using DataONTAP.C.Types.Snapshot;
using DataONTAP.C.Types.Net;
using DataONTAP.C.Types.Cifs;
using VMware.VimAutomation.ViCore.Impl.V1.Inventory;
using VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement;
using System.Collections;

abstract public class DataObject<T>
{
    public T Source { get; set; }
    public abstract string Identity { get; }

    public DataObject(T source)
    {
        Source = source;
    }
}

abstract public class NetAppObject<T> : DataObject<T>, IComparable
{
    public virtual Guid UUID { get { return Guid.Empty; } }
    public virtual string Name { get { return string.Empty; } }

    public NetAppObject(T source) : base(source)
    {
    }

    public override string Identity { get { return Name; } }

    public int CompareTo(object obj)
    {
        int retval = 1;

        if ((null != obj) && (obj is NetAppObject<T>))
        {
            NetAppObject<T> other = obj as NetAppObject<T>;

            retval = UUID.CompareTo(other.UUID);
            if (retval == 0)
            {
                retval = Name.CompareTo(other.Name);
            }
        }

        return retval;
    }
}

public class NetAppCluster : NetAppObject<ClusterIdentityInfo>
{ 
    public string Location { get { return (null != Source) ? (string)Source.ClusterLocation : null; } }
    public string SerialNumber { get { return ((null != Source) && (null != Source.ClusterSerialNumber)) ? (string)Source.ClusterSerialNumber : string.Empty; } }
    public string Contact { get { return (null != Source) ? (string)Source.ClusterContact : null; } }
    public override string Name { get { return ((null != Source) && (null != Source.ClusterName)) ? (string)Source.ClusterName : string.Empty; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.ClusterUuid) : Guid.Empty; } }

    public NetAppVServerCollection VServers { get; private set; }
    public List<NetAppAggregate> Aggregates { get; private set; }

    public NetAppCluster(ClusterIdentityInfo clusterInfo) : base(clusterInfo)
    {
        if (null == clusterInfo)
        {
            throw new Exception(String.Format("Missing clusterInfo in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        VServers = new NetAppVServerCollection();
        Aggregates = new List<NetAppAggregate>();
    }

    public NetAppVServer AddVServer(VserverInfo vServer, string cifsServerName)
    {
        NetAppVServer newNetAppVServer = null;

        // First make sure vServer's cluster is this one.
        if (vServer.NcController.Name == Source.NcController.Name)
        {
            // Next, make sure there is not already a matching vServer in VServers
            Guid vServerUUID = Guid.Parse((string)vServer.Uuid);  // Avoid calling Guid.Parse for each element in VServers.
            var x = from v in VServers
                    where v.UUID == vServerUUID
                    select v;

            if (x.Count() == 0)
            {
                newNetAppVServer = new NetAppVServer(this, vServer, cifsServerName);
                VServers.Add(newNetAppVServer);
            }
            else
            {
                newNetAppVServer = x.First();
            }
        }
        else
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster controller name: {2}, vServer controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Source.NcController.Name, vServer.NcController.Name));
        }
        
        return newNetAppVServer;
    }

    public NetAppVServer AddVServer(VserverInfo vServer)
    {
        return AddVServer(vServer, null);
    }

    public NetAppAggregate AddAggregate(AggrAttributes aggregate)
    {
        NetAppAggregate newNetAppAggregate = null;

        // First, make sure aggregate belongs to this cluster
        if (aggregate.NcController.Name == Source.NcController.Name)
        {
            // Next, make sure there is not already a matching aggregate in Aggregates
            Guid aggregateUUID = Guid.Parse((string)aggregate.AggregateUuid);  // Avoid calling Guid.Parse for each element in Aggregates.
            var x = from a in Aggregates
                    where a.UUID == aggregateUUID
                    select a;

            if (x.Count() == 0)
            {
                newNetAppAggregate = new NetAppAggregate(this, aggregate);
                Aggregates.Add(newNetAppAggregate);
            }
            else
            {
                newNetAppAggregate = x.First();
            }
        }
        else
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster controller name: {2}, Aggregate controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Source.NcController.Name, aggregate.NcController.Name));
        }

        return newNetAppAggregate;
    }

    public List<NetAppVServer> FindVServerByName(string vServerName)
    {
        return VServers.FindVServerByName(vServerName);
    }

    public List<NetAppVServer> FindVServerByUUID(string vServerUUID)
    {
        var x = from v in VServers
                where (v.UUID.ToString() == vServerUUID)
                select v;

        return x.ToList();
    }

    public List<NetAppVServer> FindVServerByNameAndUUID(string vServerName, string vServerUUID)
    {
        var x = from v in VServers
                where (v.Name == vServerName) && (v.UUID.ToString() == vServerUUID)
                select v;

        return x.ToList();
    }
}

public class NetAppClusterCollection : IList<NetAppCluster>
{
    public DateTime WhenCollected { get; set; }
    private List<NetAppCluster> _clusters = new List<NetAppCluster>();
    public int Count { get { return _clusters.Count; } }
    public bool IsReadOnly { get { return false; } }
    public NetAppCluster this[int index] { get { return _clusters[index]; } set { _clusters[index] = value; } }
    public int IndexOf(NetAppCluster item) { return _clusters.IndexOf(item); }
    public void Insert(int index, NetAppCluster item) { _clusters.Insert(index, item); }
    public void RemoveAt(int index) { _clusters.RemoveAt(index); }
    public void Add(NetAppCluster item) { _clusters.Add(item); }
    public void Clear() { _clusters.Clear(); }
    public bool Contains(NetAppCluster item) { return _clusters.Contains(item); }
    public void CopyTo(NetAppCluster[] array, int arrayIndex) { _clusters.CopyTo(array, arrayIndex); }
    public bool Remove(NetAppCluster item) { return _clusters.Remove(item); }
    public IEnumerator<NetAppCluster> GetEnumerator() { return _clusters.GetEnumerator(); }
    IEnumerator IEnumerable.GetEnumerator() { return _clusters.GetEnumerator(); }

    public NetAppClusterCollection()
    {
        WhenCollected = DateTime.Now;
    }

    public NetAppCluster AddCluster(ClusterIdentityInfo clusterInfo)
    {
        NetAppCluster netAppCluster = null;

        // Make sure clusterInfo is not already in Clusters
        var x = from c in _clusters
                where ((string)clusterInfo.ClusterUuid == c.UUID.ToString()) && ((string)clusterInfo.ClusterName == c.Name)
                select c;

        if(x.Count() == 0)
        {
            netAppCluster = new NetAppCluster(clusterInfo);
            _clusters.Add(netAppCluster);
        }
        else
        {
            netAppCluster = x.First();
        }

        return netAppCluster;
    }

    public List<NetAppVServer> FindVServerByName(string vServerName)
    {
        List<NetAppVServer> vServers = new List<NetAppVServer>();
        
        _clusters.ForEach(c => 
        {
            c.FindVServerByName(vServerName).ForEach(v => vServers.Add(v));
        });

        return vServers;
    }

    public List<NetAppVServer> FindVServerByUUID(string vServerUUID)
    {
        List<NetAppVServer> vServers = new List<NetAppVServer>();

        _clusters.ForEach(c =>
        {
            c.FindVServerByUUID(vServerUUID).ForEach(v => vServers.Add(v));
        });

        return vServers;
    }

    public List<NetAppVServer> FindVServerByControllerNameAndVserverName(string controllerName, string vServerName)
    {
        List<NetAppVServer> vServers = new List<NetAppVServer>();

         (from c in _clusters
          where (c.Source.NcController.Name == controllerName)
          select c).ToList().ForEach(cluster => {
              cluster.FindVServerByName(vServerName).ForEach(v => vServers.Add(v));
          });

        return vServers;
    }

    public List<NetAppVServer> FindVServerByClusterNameAndVserverName(string clusterName, string vServerName)
    {
        List<NetAppVServer> vServers = new List<NetAppVServer>();

        (from c in _clusters
         where (c.Name == clusterName)
         select c).ToList().ForEach(cluster => {
             cluster.FindVServerByName(vServerName).ForEach(v => vServers.Add(v));
         });

        return vServers;
    }

    private List<NetAppVolume> FindVolumeByVServerUUIDAndVolumeName(string vServerUUID, string volumeName)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();
        List<NetAppVServer> vServers = null;

        if (!string.IsNullOrEmpty(vServerUUID))
        {
            if (!string.IsNullOrEmpty(volumeName))
            {
                vServers = FindVServerByUUID(vServerUUID);
                vServers.ForEach(vs =>
                {
                    vs.FindVolumeByName(volumeName).ForEach(vol => netAppVolumes.Add(vol));
                });
            }
            else
            {
                throw new NullReferenceException(String.Format("Missing volume name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
            }
        }
        else
        {
            throw new NullReferenceException(String.Format("Missing VServer UUID in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        return netAppVolumes;
    }

    private List<NetAppVolume> FindVolumeByClusterNameVServerNameAndVolumeName(string clusterName, string vServerName, string volumeName)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();
        List<NetAppVServer> vServers = null;

        if (!string.IsNullOrEmpty(clusterName))
        {
            if (!string.IsNullOrEmpty(vServerName))
            {
                if (!string.IsNullOrEmpty(volumeName))
                {
                    vServers = FindVServerByClusterNameAndVserverName(clusterName, vServerName);
                    vServers.ForEach(vs =>
                    {
                        vs.FindVolumeByName(volumeName).ForEach(vol => netAppVolumes.Add(vol));
                    });
                }
                else
                {
                    throw new NullReferenceException(String.Format("Missing volume name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
                }
            }
            else
            {
                throw new NullReferenceException(String.Format("Missing vServer name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
            }
        }
        else
        {
            throw new NullReferenceException(String.Format("Missing cluster name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        return netAppVolumes;
    }

    private List<NetAppVolume> FindVolumeByControllerNameVServerNameAndVolumeName(string controller, string vServerName, string volumeName)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();
        List<NetAppVServer> vServers = null;

        if (!string.IsNullOrEmpty(controller))
        {
            if (!string.IsNullOrEmpty(vServerName))
            {
                if (!string.IsNullOrEmpty(volumeName))
                {
                    vServers = FindVServerByControllerNameAndVserverName(controller, vServerName);
                    vServers.ForEach(vs =>
                    {
                        vs.FindVolumeByName(volumeName).ForEach(vol => netAppVolumes.Add(vol));
                    });
                }
                else
                {
                    throw new NullReferenceException(String.Format("Missing volume name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
                }
            }
            else
            {
                throw new NullReferenceException(String.Format("Missing vServer name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
            }
        }
        else
        {
            throw new NullReferenceException(String.Format("Missing controller name in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        return netAppVolumes;
    }

    public List<NetAppVolume> FindVolumeBySnapmirrorDestination(SnapmirrorInfo snapmirrorInfo)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();

        if (!string.IsNullOrEmpty((string)snapmirrorInfo.DestinationVserverUuid))
        {
            netAppVolumes = FindVolumeByVServerUUIDAndVolumeName((string)snapmirrorInfo.DestinationVserverUuid, (string)snapmirrorInfo.DestinationVolume);
        }
        else
        {
            netAppVolumes = FindVolumeByClusterNameVServerNameAndVolumeName((string)snapmirrorInfo.DestinationCluster, (string)snapmirrorInfo.DestinationVserver, (string)snapmirrorInfo.DestinationVolume);
        }

        return netAppVolumes;
    }

    public List<NetAppVolume> FindVolumeBySnapmirrorSource(SnapmirrorInfo snapmirrorInfo)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();

        if (!string.IsNullOrEmpty((string)snapmirrorInfo.SourceVserverUuid))
        {
            netAppVolumes = FindVolumeByVServerUUIDAndVolumeName((string)snapmirrorInfo.SourceVserverUuid, (string)snapmirrorInfo.SourceVolume);
        }
        else
        {
            netAppVolumes = FindVolumeByClusterNameVServerNameAndVolumeName((string)snapmirrorInfo.SourceCluster, (string)snapmirrorInfo.SourceVserver, (string)snapmirrorInfo.SourceVolume);
        }

        return netAppVolumes;
    }
    
    public List<NetAppVolume> FindVolumeByShare(CifsShare cifsShare)
    {
        List<NetAppVolume> netAppVolumes = null;

        if (null != cifsShare)
        {
            netAppVolumes = FindVolumeByControllerNameVServerNameAndVolumeName(cifsShare.NcController.Name, (string)cifsShare.Vserver, (string)cifsShare.Volume);
        }
        else
        {
            throw new NullReferenceException(String.Format("Missing CIFS share in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        return netAppVolumes;
    }

    public List<NetAppVolume> FindVolumeByDatastore(NasDatastoreImpl datastore)
    {
        List<NetAppVolume> netAppVolumes = new List<NetAppVolume>();

        _clusters.ForEach(c => {
            c.VServers.ToList().ForEach(vs =>
            {
                foreach(string address in datastore.RemoteHost)
                {
                    if(vs.FindLIFByAddress(address).Count > 0)
                    {
                        vs.FindVolumeByJunctionPath(datastore.RemotePath).ForEach(vol => netAppVolumes.Add(vol));
                    }
                }
            });
        });

        return netAppVolumes;
    }
    public List<VMWareVirtualMachine> FindVirtualMachineByNameAndId(string vmName, string vmID)
    {
        /*
         * Return a unique list of VMWareVirtualMachines with Name = vmName && ID == vmID
         * 
         * Clusters -> c
         *      c.VServers -> vs
         *          vs.Volumes -> v
         *              v.Datastores -> ds
         *                  ds.VirtualMachines -> vm
         *                  
         *                      return all unique vms where vm.Name == vmName && vm.ID == vmID
         */
        List<VMWareVirtualMachine> vms = new List<VMWareVirtualMachine>();

        _clusters.ForEach(c =>
        {
            c.VServers.ToList().ForEach(vs =>
            {
                vs.Volumes.ForEach(v =>
                {
                    v.Datastores.ForEach(ds =>
                    {
                        ds.VirtualMachines.Where(vm => (vm.Name == vmName) && (vm.ID == vmID)).ToList().ForEach(vm =>
                        {
                            if (vms.Count(v1 => ((v1.Name == vm.Name) && (v1.ID == vm.ID))) == 0)
                            {
                                vms.Add(vm);
                            }
                        });
                    });
                });
            });
        });

        return vms;
    }
}

abstract public class NetAppClusterObject<T> : NetAppObject<T>
{
    public NetAppCluster Cluster { get; set; }

    public NetAppClusterObject(NetAppCluster cluster, T source) : base(source)
    {
        if (null == cluster)
        {
            throw new Exception(String.Format("Missing cluster in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        if (null == source)
        {
            throw new Exception(String.Format("Missing source in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        Cluster = cluster;
    }

    public override string Identity { get { return string.Format("{0}::{1}", Cluster.Identity, base.Identity); } }
}

public class NetAppVServer : NetAppClusterObject<VserverInfo>
{
    public string Type { get { return ((null != Source) && (null != Source.VserverType)) ? (string)Source.VserverType : string.Empty; } }
    public override string Name { get { return ((null != Source) && (null != Source.VserverName)) ? (string)Source.VserverName : string.Empty; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.Uuid) : Guid.Empty; } }
    public string CIFSServerName { get; set; }

    public List<NetAppVolume> Volumes { get; private set; }
    public List<NetAppShare> Shares { get; private set; }
    public List<NetAppLIF> LIFs { get; private set; }

    private void InitVServer(NetAppCluster cluster, VserverInfo vServer, string cifsServerName)
    {
        if (null == cluster)
        {
            throw new Exception(String.Format("Missing cluster in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        if (null == vServer)
        {
            throw new Exception(String.Format("Missing vServer in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure vServer belongs to cluster
        if (cluster.Source.NcController.Name != vServer.NcController.Name)
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster controller name: {2}, vServer controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, cluster.Source.NcController.Name, vServer.NcController.Name));
        }

        CIFSServerName = cifsServerName;
        Volumes = new List<NetAppVolume>();
        LIFs = new List<NetAppLIF>();
    }
    
    public NetAppVServer(NetAppCluster cluster, VserverInfo vServer, string cifsServerName) : base(cluster, vServer)
    {
        InitVServer(cluster, vServer, cifsServerName);
    }

    public NetAppVServer(NetAppCluster cluster, VserverInfo vServer) : base(cluster, vServer)
    {
        InitVServer(cluster, vServer, null);
    }

    public NetAppVolume AddVolume(VolumeAttributes volume, NetAppAggregate aggregate)
    {
        NetAppVolume newNetAppVolume = null;

        // First make sure volume belongs to this vServer
        if (volume.Vserver == Name)
        {
            // Next, make sure volume is contained on aggregate
            Guid volumeAggrUUID = Guid.Parse((string)volume.VolumeIdAttributes.ContainingAggregateUuid);  // Avoid calling Guid.Parse multiple times.
            if (volumeAggrUUID == aggregate.UUID)
            {
                // Finally, make sure there in not already a matching volume in Volumes
                Guid volUUID = Guid.Parse((string)volume.VolumeIdAttributes.Uuid);  // Avoid calling Guid.Parse for each element in Volumes.
                var x = from v in Volumes
                        where (v.UUID == volUUID)
                        select v;

                if (x.Count() == 0)
                {
                    newNetAppVolume = new NetAppVolume(this, aggregate, volume);
                    Volumes.Add(newNetAppVolume);
                }
                else
                {
                    newNetAppVolume = x.First();
                }
            }
            else
            {
                throw new Exception(String.Format("Aggregate mismatch in {0}.{1}.  Aggregate: {2}, Volume aggregate: {3}:{4}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, aggregate.Identity, (string)volume.VolumeIdAttributes.ContainingAggregateName, volumeAggrUUID.ToString()));
            }
        }
        else
        {
            throw new Exception(String.Format("VServer mismatch in {0}.{1}.  VServer: {2}, Volume vServer: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, volume.Vserver));
        }

        return newNetAppVolume;
    }

    public NetAppShare AddShare(CifsShare share, NetAppVolume volume)
    {
        NetAppShare newNetAppShare = null;

        // First make sure share's vServer is this VServer.
        if (Name == (string)share.Vserver)
        {
            // Next, make sure share is hosted on volume
            if ((string)share.Volume == volume.Name)
            {
                // Finally, make sure there is not a matching share already in Shares.
                var x = from s in Shares
                        where (s.Name == (string)share.ShareName) && (s.Path == (string)share.Path)
                        select s;

                if (x.Count() == 0)
                {
                    newNetAppShare = new NetAppShare(volume, share);
                    Shares.Add(newNetAppShare);
                }
                else
                {
                    newNetAppShare = x.First();
                }
            }
            else
            {
                throw new Exception(String.Format("Volume mismatch in {0}.{1}.  Volume: {2}, Share volume: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, volume.Identity, (string)share.Volume));
            }
        }
        else
        {
            throw new Exception(String.Format("VServer mismatch in {0}.{1}.  VServer: {2}, Share vServer: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, (string)share.Vserver));
        }

        return newNetAppShare;
    }

    public NetAppLIF AddLIF(NetInterfaceInfo lif)
    {
        NetAppLIF newNetAppLIF = null;

        // First make sure share's vServer is this VServer.
        if (Name == (string)lif.Vserver)
        {
            // Finally, make sure there is not a matching lif already in LIFs.
            var x = from l in LIFs
                    where (l.Name == (string)lif.InterfaceName)
                    select l;

            if (x.Count() == 0)
            {
                newNetAppLIF = new NetAppLIF(this, lif);
                LIFs.Add(newNetAppLIF);
            }
            else
            {
                newNetAppLIF = x.First();
            }
        }
        else
        {
            throw new Exception(String.Format("VServer mismatch in {0}.{1}.  VServer: {2}, lif vServer: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, (string)lif.Vserver));
        }

        return newNetAppLIF;
    }

    public new int CompareTo(object obj)
    {
        int retval = 1;

        if((null != obj) && (obj is NetAppVServer))
        {
            NetAppVServer other = obj as NetAppVServer;

            retval = Cluster.CompareTo(other);
            if(retval == 0)
            {
                retval = UUID.CompareTo(other.UUID);
                if (retval == 0)
                {
                    retval = Name.CompareTo(other.Name);
                }
            }
        }

        return retval;
    }

    public List<NetAppVolume> FindVolumeByName(string volumeName)
    {
        return Volumes.Where(v => v.Name == volumeName).ToList();
    }
    public List<NetAppVolume> FindVolumeByJunctionPath(string junctionPath)
    {
        return Volumes.Where(v => v.JunctionPath == junctionPath).ToList();
    }

    public List<NetAppLIF> FindLIFByAddress(string address)
    {
        return (from l in LIFs
                where l.Address == address
                select l).ToList();
    }
}

public class NetAppVServerCollection : IList<NetAppVServer>
{
    private List<NetAppVServer> _vServers = new List<NetAppVServer>();

    public NetAppVServer this[int index] { get { return _vServers[index]; } set { _vServers[index] = value; } }

    public int Count { get { return _vServers.Count(); } }

    public bool IsReadOnly { get { return false; } }

    public void Add(NetAppVServer item)
    {
        var x = from v in _vServers
                where (v.Identity == item.Identity)
                select v;

        if(x.Count() == 0)
        {
            _vServers.Add(item);
        }
    }

    public List<NetAppVServer> FindVServerByName(string vServerName)
    {
        var x = from v in _vServers
                where (v.Name == vServerName)
                select v;

        return x.ToList();
    }

    public void Clear() { _vServers.Clear(); }
    public bool Contains(NetAppVServer item) { return _vServers.Contains(item); }
    public void CopyTo(NetAppVServer[] array, int arrayIndex) { _vServers.CopyTo(array, arrayIndex); }
    public IEnumerator<NetAppVServer> GetEnumerator() { return _vServers.GetEnumerator(); }
    public int IndexOf(NetAppVServer item) { return _vServers.IndexOf(item); }
    public void Insert(int index, NetAppVServer item) { _vServers.Insert(index, item); }
    public bool Remove(NetAppVServer item) { return _vServers.Remove(item); }
    public void RemoveAt(int index) { _vServers.RemoveAt(index); }
    IEnumerator IEnumerable.GetEnumerator() { return _vServers.GetEnumerator(); }
}

public class NetAppLIF : NetAppObject<NetInterfaceInfo>
{
    public NetAppVServer VServer { get; private set; }
    public override string Name { get { return ((null != Source) && (null != Source.InterfaceName)) ? (string)Source.InterfaceName : string.Empty; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.LifUuid) : Guid.Empty; } }
    public string Address { get { return ((null != Source) && (null != Source.Address)) ? (string)Source.Address : string.Empty; } }
    public string[] DataProtocols { get { return (null != Source) ? Source.DataProtocols : new string[] { }; } }

    public NetAppLIF(NetAppVServer vServer, NetInterfaceInfo lif) : base(lif)
    {
        if (null == vServer)
        {
            throw new Exception(String.Format("Missing vServer in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        if (null == lif)
        {
            throw new Exception(String.Format("Missing lif in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure everything is related.
        if ((string)lif.Vserver != vServer.Name)
        {
            throw new Exception(String.Format("vServer mismatch in {0}.{1}.  VServer: {2}, lif vServer name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, vServer.Identity, (string)lif.Vserver));
        }
    }
}

public class NetAppAggregate : NetAppClusterObject<AggrAttributes>
{
    public Decimal Size { get { return (null != Source) && (Source.AggrSpaceAttributes.SizeTotalSpecified) ? (Decimal)Source.AggrSpaceAttributes.SizeTotal : -1; } }
    public Decimal Used { get { return (null != Source) && (((AggrAttributes)Source).AggrSpaceAttributes.SizeUsedSpecified) ? (Decimal)Source.AggrSpaceAttributes.SizeUsed : -1; } }
    public Decimal Available { get { return (null != Source) && (Source.AggrSpaceAttributes.SizeAvailableSpecified) ? (Decimal)Source.AggrSpaceAttributes.SizeAvailable : -1; } }
    public override string Name { get { return ((null != Source) && (null != Source.Name)) ? (string)Source.Name : string.Empty; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.AggregateUuid) : Guid.Empty; } }
    public string SnaplockType { get { return ((null != Source) && (null != Source.AggrSnaplockAttributes) && (null != Source.AggrSnaplockAttributes.SnaplockType)) ? ((string)Source.AggrSnaplockAttributes.SnaplockType).ToLower() : string.Empty; } }

    public List<NetAppVolume> Volumes { get; private set; }

    public NetAppAggregate(NetAppCluster cluster, AggrAttributes aggregate) : base(cluster, aggregate)
    {
        if (null == cluster)
        {
            throw new Exception(String.Format("Missing cluster in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        if (null == aggregate)
        {
            throw new Exception(String.Format("Missing aggregate in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure aggregate belongs to cluster
        if(cluster.Source.NcController.Name != aggregate.NcController.Name)
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster controller name: {2}, aggregate controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, cluster.Source.NcController.Name, aggregate.NcController.Name));
        }

        Volumes = new List<NetAppVolume>();
    }

    public NetAppVolume AddVolume(VolumeAttributes volume, NetAppVServer vServer)
    {
        NetAppVolume newNetAppVolume = null;

        // First make sure volume belongs to same cluster as this aggregate
        if(volume.NcController.Name == Cluster.Source.NcController.Name)
        {
            // Next, make sure vServer belongs to the same cluster as this aggregate
            if(Cluster.UUID == vServer.Cluster.UUID)
            {
                // Next, make sure volume is contained on aggregate
                if ((string)volume.VolumeIdAttributes.ContainingAggregateUuid == UUID.ToString())
                {
                    // Finally, make sure there is not a matching volume in Volumes
                    Guid volUUID = Guid.Parse((string)volume.VolumeIdAttributes.Uuid);  // Avoid calling Guid.Parse for each element in Volumes.
                    var x = from v in Volumes
                            where (v.VServer.UUID == vServer.UUID) && (v.UUID == volUUID)
                            select v;

                    if (x.Count() == 0)
                    {
                        newNetAppVolume = new NetAppVolume(vServer, this, volume);
                        Volumes.Add(newNetAppVolume);
                    }
                    else
                    {
                        newNetAppVolume = x.First();
                    }
                }
                else
                {
                    throw new Exception(String.Format("Aggregate mismatch in {0}.{1}.  Aggregate: {2}, Volume/aggregate: {3}:{4}/{5}:{6}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, volume.Name, (string)volume.VolumeIdAttributes.Uuid, (string)volume.VolumeIdAttributes.ContainingAggregateName, (string)volume.VolumeIdAttributes.ContainingAggregateUuid));
                }
            }
            else
            {
                throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster: {2}, VServer/cluster: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Cluster.Identity, vServer.Identity));
            }
        }
        else
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Cluster controller name: {2}, Volume controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Cluster.Source.NcController.Name, volume.NcController.Name));
        }

        return newNetAppVolume;
    }
}

public class NetAppVolume : NetAppObject<VolumeAttributes>
{
    public NetAppVServer VServer { get; private set; }
    public NetAppAggregate Aggregate { get; private set; }
    public Decimal Size { get { return (null != Source) && (Source.VolumeSpaceAttributes.SizeTotalSpecified) ? (Decimal)Source.VolumeSpaceAttributes.SizeTotal : -1; } }
    public Decimal Used { get { return (null != Source) && (Source.VolumeSpaceAttributes.SizeUsedSpecified) ? (Decimal)Source.VolumeSpaceAttributes.SizeUsed : -1; } }
    public Decimal Available { get { return (null != Source) && (Source.VolumeSpaceAttributes.SizeAvailableSpecified) ? (Decimal)Source.VolumeSpaceAttributes.SizeAvailable : -1; } }
    public string SnaplockType { get { return ((null != Source) && (null != Source.VolumeSnaplockAttributes) && (null != Source.VolumeSnaplockAttributes.SnaplockType)) ? ((string)Source.VolumeSnaplockAttributes.SnaplockType).ToLower() : string.Empty; } }
    public override string Name { get { return ((null != Source) && (null != Source.Name)) ? Source.Name : string.Empty; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.VolumeIdAttributes.Uuid) : Guid.Empty; } }
    public string JunctionPath { get { return ((null != Source) && (null != Source.VolumeIdAttributes.JunctionPath)) ? (string)Source.VolumeIdAttributes.JunctionPath : string.Empty; } }

    public List<NetAppShare> Shares { get; private set; }
    public List<NetAppVolume> SnapmirrorDestinations { get; private set; }
    public List<NetAppSnapshot> Snapshots { get; private set; }
    public List<VMWareDatastore> Datastores { get; private set; }

    public NetAppVolume(NetAppVServer vServer, NetAppAggregate aggregate, VolumeAttributes volume) : base(volume)
    {
        if (null == vServer)
        {
            throw new Exception(String.Format("Missing vServer in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        if (null == aggregate)
        {
            throw new Exception(String.Format("Missing aggregate in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        if (null == volume)
        {
            throw new Exception(String.Format("Missing volume in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure everything is related.
        if(volume.Vserver != vServer.Name)
        {
            throw new Exception(String.Format("vServer mismatch in {0}.{1}.  VServer: {2}, volume vServer name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, vServer.Identity, volume.Vserver));
        }

        if (Guid.Parse((string)volume.VolumeIdAttributes.ContainingAggregateUuid) != aggregate.UUID)
        {
            throw new Exception(String.Format("Aggregate mismatch in {0}.{1}.  Aggregate: {2}, volume aggregate: {3}/{4}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, aggregate.Identity, (string)volume.VolumeIdAttributes.ContainingAggregateName, (string)volume.VolumeIdAttributes.ContainingAggregateUuid));
        }

        if(vServer.Cluster.UUID != aggregate.Cluster.UUID)
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  VServer/Cluster: {2}, Aggregate/Cluster: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, vServer.Identity, aggregate.Identity));
        }

        VServer = vServer;
        Aggregate = aggregate;
        Shares = new List<NetAppShare>();
        SnapmirrorDestinations = new List<NetAppVolume>();
        Snapshots = new List<NetAppSnapshot>();
        Datastores = new List<VMWareDatastore>();
    }

    public bool IsSnaplockProtected  // Is this volume or any of its snapmirror destinations a snaplock volume?
    {
        get
        {
            bool retval = (SnaplockType != "non_snaplock") && (SnaplockType != string.Empty);

            int a = 0;
            while(!retval && (a < SnapmirrorDestinations.Count))
            {
                retval = SnapmirrorDestinations[a].IsSnaplockProtected;
                a++;
            }

            return retval;
        }
    }

    public void AddSnapmirror(NetAppVolume destination)
    {
        // Make sure there isn't already a matching snapmirror destination in SnapmirrorDestinations
        var x = from d in SnapmirrorDestinations
                where (d.Aggregate.UUID == destination.Aggregate.UUID) && (d.UUID == destination.UUID)
                select d;

        if(x.Count() == 0)
        {
            SnapmirrorDestinations.Add(destination);
        }
    }

    public NetAppShare AddShare(CifsShare share)
    {
        NetAppShare newNetAppShare = null;

        // First make sure share's volume is this volume.
        if (Name == (string)share.Volume)
        {
            // Next, make sure there is not a matching share already in Shares.
            var x = from s in Shares
                    where (s.Name == (string)share.ShareName) && (s.Path == (string)share.Path)
                    select s;

            if (x.Count() == 0)
            {
                newNetAppShare = new NetAppShare(this, share);
                Shares.Add(newNetAppShare);
            }
            else
            {
                newNetAppShare = x.First();
            }
        }
        else
        {
            throw new Exception(String.Format("Volume mismatch in {0}.{1}.  Volume: {2}, Share volume: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, (string)share.Volume));
        }

        return newNetAppShare;
    }

    public void AddSnapshot(SnapshotInfo snapshot)
    {
        // Make sure the snapshot belongs to this volume
        if(snapshot.NcController.Name == VServer.Cluster.Source.NcController.Name)
        {
            if((string) snapshot.Vserver == VServer.Name)
            {
                if((string)snapshot.Volume == Name)
                {
                    // Next, make sure there is not a matching snapshot already in Snapshots.
                    var x = from s in Snapshots
                            where s.CompareTo(snapshot) == 0
                            select s;

                    if(x.Count() == 0)
                    {
                        Snapshots.Add(new NetAppSnapshot(this, snapshot));
                    }
                    else
                    {
                        // Nothing, don't add the same snapshot more than once.
                    }
                }
                else
                {
                    throw new Exception(String.Format("Volume mismatch in {0}.{1}.  Volume: {2}, Snapshot volume name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Identity, (string)snapshot.Volume));
                }
            }
            else
            {
                throw new Exception(String.Format("VServer mismatch in {0}.{1}.  Volume vServer: {2}, Snapshot vServer name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, VServer.Identity, (string)snapshot.Vserver));
            }
        }
        else
        {
            throw new Exception(String.Format("Cluster mismatch in {0}.{1}.  Volume cluster controller name: {2}, Snapshot controller name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, VServer.Cluster.Source.NcController.Name, snapshot.NcController.Name));
        }
    }

    public VMWareDatastore AddDatastore(NasDatastoreImpl datastore)
    {
        VMWareDatastore newVMDatastore = null;

        // Make sure everything is related
        bool vServerHasMatchingLIF = false;
        int a = 0;
        while(!vServerHasMatchingLIF && (a < datastore.RemoteHost.Length))
        {
            vServerHasMatchingLIF = VServer.LIFs.Any(t => t.Address == datastore.RemoteHost[a]);
            a++;
        }

        // Have a lif with the right address?
        if(vServerHasMatchingLIF)
        {
            // JunctionPath == RemotePath??
            if(JunctionPath.ToLower() == datastore.RemotePath.ToLower())
            {
                // Finally, make sure datastore is not already in Datastores
                var x = from d in Datastores
                        where (d.ID == datastore.Id) && (d.Name == datastore.Name)
                        select d;

                if (x.Count() == 0)
                {
                    newVMDatastore = new VMWareDatastore(this, datastore);
                    Datastores.Add(newVMDatastore);
                }
                else
                {
                    newVMDatastore = x.First();
                }
            }
        }

        return newVMDatastore;
    }
}

public class NetAppSnapshot : NetAppObject<SnapshotInfo>,IComparable<SnapshotInfo>
{
    /*
     *  NOTE: A snapshot's UUID <SnapshotInfo.SnapshotInstanceUuid> may not be globally unique.  If a volume is mirrored, then all of it's snapshot get mirrored as well, resulting in globally duplicate UUIDs.
     *     However, within the same volume, there will be no duplicates.
     */
    public NetAppVolume Volume { get; private set; }
    public DateTime? Created { get { return (null != Source) && (Source.AccessTimeSpecified) ? Source.AccessTimeDT : null; } }
    public DateTime? ExpiryTime { get { return (null != Source) && (Source.ExpiryTimeSpecified) ? Source.ExpiryTimeDT : null; } }
    public DateTime? SnaplockExpiryTime { get { return (null != Source) && (Source.SnaplockExpiryTimeSpecified) ? Source.SnaplockExpiryTimeDT : null; } }
    public string SnapmirrorLabel { get { return (null != Source) ? (string)Source.SnapmirrorLabel : null; } }
    public override string Name { get { return (null != Source) ? (string)Source.Name : null; } }
    public override Guid UUID { get { return (null != Source) ? Guid.Parse((string)Source.SnapshotInstanceUuid) : Guid.Empty; } }
    public long? CumulativeTotal { get { return (null != Source) && (Source.CumulativeTotalSpecified) ? Source.CumulativeTotal : null; } }
    public long? Total { get { return (null != Source) && (Source.TotalSpecified) ? Source.Total : null; } }

    public NetAppSnapshot(NetAppVolume volume, SnapshotInfo snapshot) : base(snapshot)
    {
        if (null == volume)
        {
            throw new Exception(String.Format("Missing volume in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        if (null == snapshot)
        {
            throw new Exception(String.Format("Missing snapshot in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure snapshot belongs to volume
        if((string)snapshot.Volume != volume.Name)
        {
            throw new Exception(String.Format("Volume mismatch in {0}.{1}.  Volume: {2}, Snapshot volume name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Volume.Identity, (string)snapshot.Volume));
        }
        Volume = volume;

        // NOTE: Do not call Volume.AddSnapshot(snapshot) here, since AddSnapshot will in turn call new NetAppSnapshot creating a loop.
    }

    public int CompareTo(SnapshotInfo other)
    {
        int retval = 1;
        
        retval = UUID.CompareTo(Guid.Parse((string)other.SnapshotInstanceUuid));
        if (retval == 0)
        {
            retval = Name.CompareTo(other.Name);
        }

        return retval;
    }
}

public class NetAppShare : DataObject<CifsShare>
{
    public NetAppVolume Volume { get; private set; }

    public string Path { get { return ((null != Source) && (null != Source.Path)) ? (string)(Source.Path) : string.Empty; } }
    public string Name { get { return ((null != Source) && (null != Source.ShareName)) ? (string)(Source.ShareName) : string.Empty; } }
    public override string Identity { get { return Name; } }

    public NetAppShare(NetAppVolume volume, CifsShare share) : base(share)
    {
        if (null == volume)
        {
            throw new Exception(String.Format("Missing volume in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        if (null == share)
        {
            throw new Exception(String.Format("Missing share in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        // Make sure everything is related...
        if((string)share.Volume != volume.Name)
        {
            throw new Exception(String.Format("Volume mismatch in {0}.{1}.  Volume: {2}, Share volume name: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, Volume.Identity, (string)share.Volume));
        }
        Volume = volume;
    }
}

public class VMWareDatastore : DataObject<NasDatastoreImpl>, IComparable
{
    public NetAppVolume Volume { get; private set; }
    public string ID { get { return ((null != Source) && (null != Source.Id)) ? Source.Id : string.Empty; } }
    public string Name { get { return ((null != Source) && (null != Source.Name)) ? Source.Name : string.Empty; } }
    public override string Identity { get { return Name; } }

    public List<VMWareVirtualMachine> VirtualMachines { get; private set; }

    public VMWareDatastore(NetAppVolume volume, NasDatastoreImpl datastore) : base(datastore)
    {
        if (null == volume)
        {
            throw new Exception(String.Format("Missing volume in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        if (null == datastore)
        {
            throw new Exception(String.Format("Missing datastore in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }
        Volume = volume;
        VirtualMachines = new List<VMWareVirtualMachine>();
    }

    public void AddVirtualMachine(VMWareVirtualMachine virtualMachine)
    {
        // Make sure virtualMachine belongs to this datastore.
        var x = from d in virtualMachine.Datastores
                where d.ID == ID
                select d;

        if(x.Count() > 0)
        {
            // Make sure there is not already a reference to virtualMachine in VirtualMachines
            var y = from v in VirtualMachines
                    where v.ID == virtualMachine.ID
                    select v;

            if (y.Count() == 0)
            {
                VirtualMachines.Add(virtualMachine);
            }
            else
            {
                // Nothing, don't add duplicate virtual machines...
            }
        }
        else
        {
            throw new Exception(String.Format("Datastore mismatch in {0}.{1}.  Virtual machine: {2} does not belong to datastore: {3}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name, virtualMachine.Identity, Identity));
        }
    }

    public int CompareTo(object obj)
    {
        int retval = 1;

        if ((null != obj) && (obj is VMWareDatastore))
        {
            VMWareDatastore other = obj as VMWareDatastore;

            retval = ID.CompareTo(other.ID);
            if (retval == 0)
            {
                retval = Name.CompareTo(other.Name);
            }
        }

        return retval;
    }
}

public class VMWareVirtualMachine : DataObject<VirtualMachineImpl>, IComparable
{
    public string ID { get { return ((null != Source) && (null != Source.Id)) ? Source.Id : string.Empty; } }
    public string Name { get { return ((null != Source) && (null != Source.Name)) ? Source.Name : string.Empty; } }
    public string PowerState { get { return (null != Source) ? Source.PowerState.ToString() : string.Empty; } }
    public override string Identity { get { return string.Format("{0}:{1}", ID, Name); } }

    public List<VMWareDatastore> Datastores { get; set; }

    public VMWareVirtualMachine(VirtualMachineImpl virtualMachine) : base(virtualMachine)
    {
        if (null == virtualMachine)
        {
            throw new Exception(String.Format("Missing virtualMachine in {0}.{1}.", MethodBase.GetCurrentMethod().ReflectedType.Name, MethodBase.GetCurrentMethod().Name));
        }

        Datastores = new List<VMWareDatastore>();
    }

    public void AddDatastore(VMWareDatastore datastore)
    {
        // Make sure there is not already a reference to virtualMachine in VirtualMachines
        var x = from d in Datastores
                where d.ID == datastore.ID
                select d;

        if (x.Count() == 0)
        {
            Datastores.Add(datastore);
        }
        else
        {
            // Nothing, don't add duplicate datastores...
        }
    }

    public int CompareTo(object obj)
    {
        int retval = 1;

        if ((null != obj) && (obj is VMWareVirtualMachine))
        {
            VMWareVirtualMachine other = obj as VMWareVirtualMachine;

            retval = ID.CompareTo(other.ID);
            if (retval == 0)
            {
                retval = Name.CompareTo(other.Name);
            }
        }

        return retval;
    }
}
