

$ucsVLANs = @(
    @{ID = 1; Name = "VL01-PSRV" },
    @{ID = 3; Name = "VL03-SERVERDATA" },
    @{ID = 5; Name = "VL05-INFRAMGMT" },
    @{ID = 7; Name = "VL07-NLS" },
    @{ID = 9; Name = "VL09-LB-FARM" },
    @{ID = 11; Name = "VL11-STORAGE" },
    @{ID = 20; Name = "VL20-VOICE-ELAN" },
    @{ID = 21; Name = "VL21-INFOSEC-MGMT" },
    @{ID = 40; Name = "VL40-CLIENTLAN" },
    @{ID = 60; Name = "VL60-EXTDMZ" },
    @{ID = 61; Name = "VL61-INTDMZ" },
    @{ID = 63; Name = "VL63-WSINTDMZ" },
    @{ID = 68; Name = "VL68-DMZSTORAGE" },
    @{ID = 69; Name = "VL69-DMZMGMT" },
    @{ID = 80; Name = "VL80-DEV1" },
    @{ID = 82; Name = "VL82-PSRVDEV" },
    @{ID = 84; Name = "VL84-TEST1" },
    @{ID = 88; Name = "VL88-STGDEV" }
)

$ucsVLANGroups = @(
    @{Name = "GUEST"; Members = @("VL01-PSRV", "VL03-SERVERDATA", "VL07-NLS", "VL09-LB-FARM", "VL20-VOICE-ELAN", "VL21-INFOSEC-MGMT", "VL40-CLIENTLAN", "VL80-DEV1", "VL82-PSRVDEV", "VL84-TEST1" ) },
    @{Name = "MGMT-VMOTION"; Members = @("VL01-PSRV", "VL05-INFRAMGMT", "VL11-STORAGE") },
    @{Name = "STORAGE"; Members = @("VL11-STORAGE", "VL88-STGDEV") },
    @{Name = "DMZ-GUEST"; Members = @("VL60-EXTDMZ", "VL61-INTDMZ", "VL63-WSINTDMZ") },
    @{Name = "DMZ-MGMT-VMOTION"; Members = @("VL68-DMZSTORAGE", "VL69-DMZMGMT") },
    @{Name = "DMZ-STORAGE"; Members = @("VL68-DMZSTORAGE") }
)

$vNICTemplatePairs = @(
    @{
        Primary   = @{Name = "GST.DMZ.AX"; Description = "DMZ Guest | Fabric A | No Failover"; Switch = "A"; MTU = 1500; VLANGroups = @("DMZ-GUEST") };
        Secondary = @{Name = "GST.DMZ.BX"; Description = "DMZ Guest | Fabric B | No Failover"; Switch = "B"; };
    },
    @{
        Primary   = @{Name = "STG.DMZ.AX"; Description = "DMZ Storage | Fabric A | No Failover"; Switch = "A"; MTU = 9000; VLANGroups = @("DMZ-STORAGE") };
        Secondary = @{Name = "STG.DMZ.BX"; Description = "DMZ Storage | Fabric B | No Failover"; Switch = "B"; };
    },
    @{
        Primary   = @{Name = "MGTVMN.DMZ.AB"; Description = "DMZ MGMT & vMotion | Fabric A | Failover B"; Switch = "A-B"; MTU = 9000; VLANGroups = @("DMZ-MGMT-VMOTION") };
        Secondary = @{Name = "VMNMGT.DMZ.BA"; Description = "DMZ vMotion & MGMT | Fabric B | Failover A"; Switch = "B-A"; };
    },
    @{
        Primary   = @{Name = "GST.INT.AX"; Description = "Internal Guest | Fabric A | No Failover"; Switch = "A"; MTU = 1500; VLANGroups = @("GUEST") };
        Secondary = @{Name = "GST.INT.BX"; Description = "Internal Guest | Fabric B | No Failover"; Switch = "B"; };
    },
    @{
        Primary   = @{Name = "STG.INT.AX"; Description = "Internal Storage | Fabric A | No Failover"; Switch = "A"; MTU = 9000; VLANGroups = @("STORAGE") };
        Secondary = @{Name = "STG.INT.BX"; Description = "Internal Storage | Fabric B | No Failover"; Switch = "B"; };
    },
    @{
        Primary   = @{Name = "MGTVMN.INT.AB"; Description = "Internal MGMT & vMotion | Fabric A | Failover B"; Switch = "A-B"; MTU = 9000; VLANGroups = @("MGMT-VMOTION") };
        Secondary = @{Name = "VMNMGT.INT.BA"; Description = "Internal vMotion & MGMT | Fabric B | Failover A"; Switch = "B-A"; };
    }
)



Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsVnicTemplate -ModifyPresent  -Name "GST.DMZ.AX"
$mo_1 = $mo | Add-UcsFabricNetGroupRef -ModifyPresent -Name "DMZ-GUEST"
Complete-UcsTransaction
