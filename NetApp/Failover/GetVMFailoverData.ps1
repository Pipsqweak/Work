<#

Get all NFS datastores from vCenter
Match the datastores to the NetApp volumes hosting them
    need object linking datastore to volume
Limit the resulting volumes to only volumes which have snapmirror destinations -- these are failover capable volumes
    add an object to the datastoreToVolume object to keep track of snapmirror destinations.

Get all SVMs which have the NFS protocol active.

#>
