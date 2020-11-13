$requirements += @{
    RequirementType = "function";
    FunctionName = "NASListChecker";
    ScriptPath = "NASListChecker.ps1";
    Description = "Checks nasList defined in the configuration json file to ensure it's complete."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "nasList";
    ValidatorFunction = "NASListChecker";
    Description="List of NAS systems to connect to and the manage server used to process them."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "pathToGetACLs";
    Description = "Path to Get-ACLs script."
}

$requirements += @{
    RequirementType = "file";
    Create = $false;
    FromVariable = "pathToGetACLs";
    Description = "Path to Get-ACLs script."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "remotePSConfigName";
    Description = "Remote powershell session configuration name."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "databaseServer";
    Description = "Name of server hosting the ACL database."
}

$requirements += @{
    RequirementType="variable";
    VariableName = "databaseName";
    Description = "ACL database name."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "partialPathsToAvoid";
    Description = "Array of strings, that if detected in a path, cause the path to be skipped."
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "maxSubProcesses";
    Description = "Maximum remote scanner processes allowed on a management server at once.";
    Minimum = 1;
    Maximum = 15;
    DefaultValue = 10
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "maxScanDepth";
    Description = "How many directories deep should the scanner enumerate.  Default: -1 = no limit.";
    Minimum = -1;
    Maximum = [Int32]::MaxValue;
    DefaultValue = -1
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "maxSharesToCheck";
    Description = "How many shares should be scanned.  Default: -1 = no limit.";
    Minimum = -1;
    Maximum = [Int32]::MaxValue;
    DefaultValue = -1
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "directoriesOnly";
    Description = "Should the scanner process directories only.  Default: true";
    DefaultValue = $true
}

$requirements += @{
    RequirementType = "variable";
    VariableName = "launchRemote";
    Description = "Should the remote scanner script be launched?  Default: true";
    DefaultValue = $true
}

$requirements += @{
    RequirementType = "assembly";
    AssemblyName = "System.DirectoryServices.AccountManagement"
}

$requirements += @{
    RequirementType = "module";
    ModuleName = "DataONTAP"
}

$requirements += @{
    RequirementType = "module";
    ModuleName="ActiveDirectory"
}

$requirements += @{
    RequirementType = "type";
    TypeName = "DBConnection";
    ScriptPath = "DBConnection.ps1";
    Description = "Defines the DBConnection class."
}

$requirements += @{
    RequirementType = "type";
    TypeName = "DataAccess";
    ScriptPath = "DataAccess.ps1";
    Description = "Defines the DataAccess class."
}

$requirements += @{
    RequirementType = "type";
    TypeName = "CIFSShare";
    ScriptPath = "CIFSShare.ps1";
    Description = "Defines the CIFSShare class."
}

$requirements += @{
    RequirementType = "type";
    TypeName = "JobTracker";
    ScriptPath = "JobTracker.ps1";
    Description = "Defines the JobTracker class."
}

$requirements += @{
    RequirementType = "type";
    TypeName = "NetAppCIFSServer";
    ScriptPath = "NetAppCIFSServer.ps1";
    Description = "Defines the NetAppCIFSServer class"
}

$requirements += @{
    RequirementType = "type";
    TypeName = "NetAppCIFSServerCollection";
    ScriptPath = "NetAppCIFSServerCollection.ps1";
    Description = "Defines the NetAppCIFSServerCollection class."
}

$requirements += @{
    RequirementType = "function";
    FunctionName = "Connect-NetApp";
    ScriptPath = "Connect-NetApp.ps1";
    Description = "Function that connects to all the NetApp filers."
}

$requirements += @{
    RequirementType = "function";
    FunctionName = "UpdateCIFSData";
    ScriptPath = "UpdateCIFSData.ps1";
    Description = "Function that pushes NetAPP CIFS server informationn to the ACL database."
}
