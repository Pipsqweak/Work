function UpdateCIFSData([NetAppCIFSServer] $naCIFSServer)
{
    if($null -ne $naCIFSServer)
    {
        # Add or update the server name record in the database and get the server ID
        $serverID = [DataAccess]::AddUpdateServer($naCIFSServer.name)

        if($serverID -ne -1)
        {
            # Update the aliases for the server
            for($b = 0; $b -lt $naCIFSServer.aliases.Count; $b++)
            {
                # Not too worried about making sure aliases were saved ok...
                $aliasID = [DataAccess]::AddUpdateServerAlias($serverID, $naCIFSServer.aliases[$b])
            }
        }
        else
        {
            [Log]::Warning("Unable to save results for {0}.  Failed to update server name in database." -f @($naCIFSServer.name))
        }
    }
    else
    {
        [Log]::Warning("Attempt to save Get-ACLs results with null naCIFSServer.")
    }
}
