# Define the specific requirements for this project
$requirements += @{
    RequirementType = "variable";
    VariableName = "deviceName";
    Description = "Name of CheckPoint device to be backed up."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "userName";
    Description = "User name used to connect to <deviceName>."
}

$requirements += @{                                                                                                     
    RequirementType = "variable";                                                                                       
    VariableName = "destinationFolder";                                                                                           
    Description = "Path to folder where the exported snapshot image will be stored."                                                                   
}                                                                                                                       

$requirements += @{                                                                                                     
    RequirementType = "path";                                                                                           
    Create = $true;                                                                                                     
    FromVariable = "destinationFolder";                                                                                           
    Description = "Path to folder where the exported snapshot image will be stored."                                                                   
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "maxFailures";
    Description = "Number of times an SSH command can fail before giving up.  Used while waiting for CheckPoint to export the snapshot.";
    Minimum = 5;
    Maximum = 25;
    DefaultValue = 10
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "waitTimeInSeconds";
    Description = "Enter number of seconds to wait for: 1) snapshot to be created, 2) export to complete and 3) exported image to be copied to working directory.";
    Minimum = 60;
    Maximum = 1800;
    DefaultValue = 600
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "leaveSourceFile";
    Description = "Leave exported image file in user's working directory?";
    DefaultValue = $false
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "cleanScriptedSnapshotsOnly";
    Description = "Clean only snapshots that 'appear' to have been created by this script?";
    DefaultValue = $false
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "savedSnapshotsBackups";
    Description = "How many backup snapshots are saved in the destination folder."
    DefaultValue = 3;
    Minimum = 1;
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "userDefFW1Path";
    Description = "Path to user defined VPN options definition file."
    DefaultValue = "`$FWDIR/conf/user.def.FW1"
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "backupUserDefFW1";
    Description = "Backup user defined VPN options definition file."
    DefaultValue = $true
}
