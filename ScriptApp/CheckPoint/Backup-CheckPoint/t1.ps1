$hlySM = Get-NCSnapmirror -Controller @($cdot["BDC-CDOTCLST01"], $cdot["CDC-CDOTCLST01"]) -SourceVserver "BOI-SVMA03" -DestinationVserver @("BDC-SVMA02","CDC-SVMA02")

@(
    foreach($s in @($hlySM | Sort-Object DestinationLocation))
    {

        # $sourceControllerName, $sourceVServerName, $sourceVolumeName, $originalDestinationVServerName, $newDestinationVServerName
        # BDC-SVMA02 goes to HLYDR-SVMA01 and CDC-SVMA02 goes to HLYDR-SVMA02.

        $d = "" | Select-Object SourceControllerName, SourceVServerName, SourceVolumeName, OriginalDestinationVServerName, NewDestinationVServerName
        $d.SourceControllerName = "BOI-CDOTCLST01"
        $d.SourceVServerName = $s.SourceVServer
        $d.SourceVolumeName = $s.SourceVolume
        $d.OriginalDestinationVServerName = $s.DestinationVServer
        $d.NewDestinationVServerName = "HLYDR-SVMA01"

        if($d.OriginalDestinationVServerName -eq "CDC-SVMA02")
        {
            $d.NewDestinationVServerName = "HLYDR-SVMA02"
        }

        $d

        Write-Host ("RehostSnapMirror -sourceControllerName `"{0}`" -sourceVServerName `"{1}`" -sourceVolumeName `"{2}`" -originalDestinationVServerName `"{3}`" -newDestinationVServerName `"{4}`"" -f @($d.SourceControllerName, $d.SourceVServerName, $d.SourceVolumeName, $d.OriginalDestinationVServerName, $d.NewDestinationVServerName))
    }
) | ft -AutoSize


# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Accounting_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Admin_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Architec_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_BD_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_BDArt_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Civil_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ClientStd_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Controls_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_DSS_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Electrical_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Enviro_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Generation_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_GIS_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HelpDesk_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HmnRsrcs_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HRPayroll_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_IndProco_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ITES_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ITOpsPM_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Legal_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Legal_02" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Line_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Mechanical_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Network_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Operations_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_OpsDivMgmt_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_OpsMgmt_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_PCI_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_PD_Distmgmt_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Powernetdocs_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Printroom_Requests_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Projects_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ProjectShare_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Rebis_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Studies_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Substation_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDpm_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDproco_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDProdMgmt_01" -originalDestinationVServerName "BDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Accounting_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Admin_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Architec_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_BD_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_BDArt_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Civil_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ClientStd_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Controls_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_DSS_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Electrical_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Enviro_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Generation_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_GIS_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HelpDesk_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HmnRsrcs_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_HRPayroll_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_IndProco_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ITES_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ITOpsPM_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Legal_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Legal_02" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Line_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Mechanical_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Network_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Operations_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_OpsDivMgmt_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_OpsMgmt_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_PCI_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_PD_Distmgmt_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Powernetdocs_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Printroom_Requests_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Projects_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_ProjectShare_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Rebis_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Studies_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_Substation_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDpm_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDproco_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA03" -sourceVolumeName "vol_SMB_TanDProdMgmt_01" -originalDestinationVServerName "CDC-SVMA02" -newDestinationVServerName "HLYDR-SVMA02"

# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "KCK-SVMA01" -sourceVolumeName "vol_SMB_REPLICATE_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "KCKDR-SVMA01"
# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "SEGA-SVMA01" -sourceVolumeName "vol_SMB_REPLICATE_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "SEGADR-SVMA01"
# RehostSnapMirror -sourceControllerName "PHX-CDOTCLST01" -sourceVServerName "PHX-SVMA01" -sourceVolumeName "vol_SMB_REPLICATE_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "PHXDR-SVMA02"
# RehostSnapMirror -sourceControllerName "PHX-CDOTCLST01" -sourceVServerName "PHX-SVMA01" -sourceVolumeName "vol_SMB_REPLICATE_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "PHXDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA01" -sourceVolumeName "vol_dr_vmware_SAS_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "BOIDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA01" -sourceVolumeName "vol_SMB_smartplant_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BOIDR-SVMA02"
# RehostSnapMirror -sourceControllerName "BOI-CDOTCLST01" -sourceVServerName "BOI-SVMA01" -sourceVolumeName "vol_dr_vmware_SAS_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BOIDR-SVMA02"
# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "OPK-SVMA01" -sourceVolumeName "vol_DR_vmware_SAS_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "OPKDR-SVMA02"
# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "OPK-SVMA01" -sourceVolumeName "vol_SMB_SQL_DB_Backups_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "OPKDR-SVMA02"
# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "OPK-SVMA01" -sourceVolumeName "vol_DR_vmware_SAS_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "OPKDR-SVMA01"
# RehostSnapMirror -sourceControllerName "OPK-CDOTCLST01" -sourceVServerName "OPK-SVMA01" -sourceVolumeName "vol_SMB_SQL_DB_Backups_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "OPKDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_AppsScm_Backups_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_CAE_Apps_SAS_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_CAE_SAS_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_Facilities_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_Generation_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_RAM_Mapping_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_SCOM_DB_Backups_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "BDC-CDOTCLST01" -sourceVServerName "BDC-SVMA01" -sourceVolumeName "vol_SMB_SQL_DB_Backups_01" -originalDestinationVServerName "CDC-SVMA01" -newDestinationVServerName "BDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_BAL_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_Enviro_Service_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_Facilities_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_HST_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_Test_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_acquisition_archive_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_dms_active_03" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_dms_active_04" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_dms_archive_02" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_PW_dms_archive_03" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_SAW_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_SQL_Infra_DB_Backups_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_Vault_Backup_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"
# RehostSnapMirror -sourceControllerName "CDC-CDOTCLST01" -sourceVServerName "CDC-SVMA01" -sourceVolumeName "vol_SMB_Vault_FileStore_01" -originalDestinationVServerName "BDC-SVMA01" -newDestinationVServerName "CDCDR-SVMA01"

$snapmirrors = @(Get-NCSnapmirror -Controller @($cdot.Values))
$snapmirrors | Where-Object { (-not $_.DestinationVServer.Contains("DR-SVM")) -and (-not $_.SourceVolume.Contains("ROOT_")) } | Sort-Object SourceLocation | Select-Object SourceLocation,DestinationLocation | ft -AutoSize

$vServerPeers = @(Get-NcVserverPeer -Controller @($cdot.Values))
$additionalStorage = 0
$sourceControllerNames = @($vServerPeers | Where-Object { -not $_.VServer.Contains("DR-SVM") } | Select-Object -Unique -ExpandProperty NCController | Select-Object -ExpandProperty Name | Sort-Object)
for($a = 0; $a -lt $sourceControllerNames.Length; $a++)
{
    $sourceVserverNames = @($vServerPeers | Where-Object { ($_.NCController.Name -eq $sourceControllerNames[$a]) -and (-not $_.VServer.Contains("DR-SVM")) } | Select-Object -Unique -ExpandProperty Vserver | Sort-Object)
    for($b = 0; $b -lt $sourceVserverNames.Length; $b++)
    {
        Write-Host ("{0}:{1}" -f @($sourceControllerNames[$a], $sourceVserverNames[$b]))
        $destinationClusterNames = @($vServerPeers | Where-Object { ($_.NCController.Name -eq $sourceControllerNames[$a]) -and ($_.Vserver -eq $sourceVserverNames[$b]) } | Select-Object -Unique -ExpandProperty PeerCluster)
        for($c = 0; $c -lt $destinationClusterNames.Length; $c++)
        {
            $destinationVServerNames = @($vServerPeers | Where-Object { ($_.NCController.Name -eq $sourceControllerNames[$a]) -and ($_.Vserver -eq $sourceVserverNames[$b]) -and ($_.PeerCluster -eq $destinationClusterNames[$c]) } | Select-Object -Unique -ExpandProperty PeerVServer)
            for($d = 0; $d -lt $destinationVServerNames.Length; $d++)
            {
                Write-Host ("`t{0}:{1}" -f $($destinationClusterNames[$c], $destinationVServerNames[$d]))
                #if(-not $destinationVServerNames[$d].Contains("DR-SVM"))
                #{
                    $tmpSMs = @($snapmirrors | Where-Object { ($_.SourceVServer -eq $sourceVserverNames[$b]) -and ($_.DestinationVServer -eq $destinationVServerNames[$d]) })
                    for($e = 0; $e -lt $tmpSMs.Length; $e++)
                    {
                        $destVol = Get-NCVol -Controller $cdot[$destinationClusterNames[$c]] -Vserver $destinationVServerNames[$d] -Name $tmpSMs[$e].DestinationVolume
                        Write-Host ("`t`t{0} --> {1} ({2} : {3})" -f @($tmpSMs[$e].SourceLocation, $tmpSMs[$e].DestinationLocation, $destVol.JunctionPath, $destVol.VolumeSpaceAttributes.SizeUsed))

                        if(-not [String]::IsNullOrEmpty($destVol.JunctionPath))
                        {
                            $additionalStorage += $destVol.TotalSize
                        }
                    }
                #}
            }
        }
    }
}

$snapmirrors | Where-Object { (-not $_.DestinationVServer.Contains("DR-SVM")) } | Sort-Object SourceLocation | Select-Object SourceLocation,DestinationLocation | ft -AutoSize

$ncVols = @(Get-NCVol -Controller @($cdot.Values))
$sb = [System.Text.StringBuilder]::new()

foreach($c in @($cdot.Values))
{
    [void] $sb.AppendLine( ("{0}" -f @($c.Name)) )
    $vServers = @(Get-NCVServer -Controller $c)
    foreach($s in $vServers)
    {
        if(-not $s.VServer.Contains("DR-SVM") -and ($s.VServerType -eq "data"))
        {
            [void] $sb.AppendLine( ("`t{0}" -f @($s.VServer)) )
            $ncVols = @(Get-NCVol -Controller $c -Vserver $s.Vserver)

            foreach($v in $ncVols)
            {
                [void] $sb.AppendLine( ("`t`t{0}" -f @($v.Name)) )
            }
        }
    }
}

$sb.ToString() | Set-Clipboard
