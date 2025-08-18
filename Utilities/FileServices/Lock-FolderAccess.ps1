# Prompt for file server Name
Write-Host "For the next few inputs, keep this in mind:"
Write-Host "   For \\server1\shares2\folder3\folder4"
Write-Host "     FILE SERVER is: server1"
Write-Host "     SHARE name is: share2"
Write-Host "     FOLDER name is: folder4`r`n"
$FSName = Read-Host "Enter the FILE SERVER name (eg. LABFS1):"

# Prompt for share name
$FSShare = Read-Host "Enter SHARE name (eg. Substation):"

# Prompt for folder name
$FSFolder = Read-Host "Enter FOLDER name:"

# Create folder path
$FSFolderPath = Read-Host "Enter FOLDER path: "

function Create-ADFSGroup()
{
}
# Create Group Names
$FSGroup1 = "FS-$FSName-$FSShare-Share-$FSFolder-Folder-01-FC"
$FSGroup2 = "FS-$FSName-$FSShare-Share-$FSFolder-Folder-01-RO"
$FSGroup3 = "FS-$FSName-$FSShare-Share-$FSFolder-Folder-01-RW"

# Create Group Descriptions
$FSGroupDesc1 = "Full Control access to $FSFolderPath"
$FSGroupDesc2 = "Read only access to $FSFolderPath"
$FSGroupDesc3 = "Modify access to $FSFolderPath"

# Create the groups
Write-Host "Creating group $FSGroup1"
New-ADGroup -Name $FSGroup1 -GroupCategory Security -GroupScope DomainLocal -Path "OU=File Shares,OU=Groups,OU=IT,OU=PEI,DC=powereng,DC=com" -Description $FSGroupDesc1 -Server "BDC-DC01" -ErrorAction Stop | Out-Null

Write-Host "Creating group $FSGroup2"
New-ADGroup -Name $FSGroup2 -GroupCategory Security -GroupScope DomainLocal -Path "OU=File Shares,OU=Groups,OU=IT,OU=PEI,DC=powereng,DC=com" -Description $FSGroupDesc2 -Server "BDC-DC01" -ErrorAction Stop | Out-Null

Write-Host "Creating group $FSGroup3"
New-ADGroup -Name $FSGroup3 -GroupCategory Security -GroupScope DomainLocal -Path "OU=File Shares,OU=Groups,OU=IT,OU=PEI,DC=powereng,DC=com" -Description $FSGroupDesc3 -Server "BDC-DC01" -ErrorAction Stop | Out-Null

# Sleep for 5 minutes
write-host "Sleeping for 5 minutes to allow for replication"
start-sleep -seconds 300

# Get the existing ACL for the folder
Write-Host "Getting current folder ACL"
$FSFolderACL = Get-Acl $FSFolderPath

# Set the current user as the owner
Write-Host "Setting folder owner"
$FSFolderACL.SetOwner([System.Security.Principal.NTAccount] 'powereng\cchenore-adm')

# Disable inheritance and remove all existing security rules
Write-Host "Disabling inheritance"
$FSFolderACL.SetAccessRuleProtection($true, $false)
$FSFolderACL.Access | ForEach-Object { $FSFolderACL.RemoveAccessRule($_) }

# Add custom access rules
Write-Host "Creating folder ACL's"
$FSFolderRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule('powereng\fs-fileservices-adm', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$FSFolderRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($FSGroup1, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$FSFolderRule3 = New-Object System.Security.AccessControl.FileSystemAccessRule($FSGroup2, 'ReadandExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$FSFolderRule4 = New-Object System.Security.AccessControl.FileSystemAccessRule($FSGroup3, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$FSFolderACL.AddAccessRule($FSFolderRule1)
$FSFolderACL.AddAccessRule($FSFolderRule2)
$FSFolderACL.AddAccessRule($FSFolderRule3)
$FSFolderACL.AddAccessRule($FSFolderRule4)

# Apply the modified ACL to the folder
Write-Host "Applying ACL's"
Set-Acl -Path $FSFolderPath -AclObject $FSFolderACL  -ErrorAction Stop | Out-Null

# Send complete message
Write-Host "Work complete" -ForegroundColor Green
