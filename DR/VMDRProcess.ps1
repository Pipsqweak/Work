# Name of the VM to DR
$drVMName = "CDC-KLBTest01"

# Connection to the source NetApp Cluster
$cdc = $cDot['CDC-CDOTCLST01']

# Name of the source storage virtual machine
$srcVServer = "CDC-SVMA01"

# Name of the source volume
$srcVolName = "vol_DR_vmware_DRTesting_01"

# Connect to the destination NetApp Cluster
$ddc = $cDot['BDC-CDOTCLST01']

# Name of the destination DR storage virtual machine
$destVServer = "CDCDR-SVMA01"

# Name of the destination NFS storage virtual machine
$newSVMName = "BDC-SVMA01"

# Name of the snapmirror destination volume
$destVolName = "SMD_vol_CDC_SVMA01_vol_DR_vmware_DRTesting_01"

# Name of the export policy to apply to the newly mounted volume
$exportPolicyName = "exp_vmware_internal_nfs_01"

# The NFS export path for the volume
$newJunctionPath = "/VMware/KLB_DR_Testing"

# The IP address of the NFS SVM
$nfsHostAddress = "10.247.11.11"

# The name of the datastore as it will appear in vCenter
$newDatastoreName = "KLB_DR_Testing"

# The path to the DR'd VM's .vmx file once the datastore is mounted to an ESXi host
$vmxDatastorePath = "vmstores:\vcenter.powereng.com@443\DDC\KLB_DR_Testing\CDCT-DRTest-01\CDCT-DRTest-01.vmx"

# The name of the ESXi host where the DR'd VM will be registered
$newESXiHostName = "bdc-esx01.powereng.com"
