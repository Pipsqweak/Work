[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=1)]
    [String]
    $JSONConfigFile
)

try
{
    # Read the raw configuration information
    $rawConfig = Get-Content -Path $JSONConfigFile -ErrorAction Stop
    try
    {
        # Convert the raw configuration from JSON to a useable object
        $config = $rawConfig | ConvertFrom-Json -ErrorAction Stop

        # Make sure the project root folder exists
        if([System.IO.Directory]::Exists($config.ProjectRoot))
        {
            # Make sure the project archive root folder exists
            if([System.IO.Directory]::Exists($config.ArchiveRoot))
            {
                # Now attempt to archive each project listed in ArchiveProjects
                $a = 0
                while($a -lt $config.ArchiveProjects.Length)
                {
                    # Assume the project needs to be archived until we determine it does not.
                    $archiveProject = $true

                    # If .Complete is null, then assume the project has not been archived
                    if($null -ne $config.ArchiveProjects[$a].Complete)
                    {
                        # If there is a value for .Start, see if it parses into a date.
                        if (-not [String]::IsNullOrEmpty($config.ArchiveProjects[$a].Start))
                        {
                            # Initialize $whenToArchiveProject so .TryParse has a place to put the parsed value
                            $whenToArchiveProject = [DateTime]::MinValue
                            if([DateTime]::TryParse($config.ArchiveProjects[$a].Start, [ref] $whenToArchiveProject))
                            {
                                # Only archive the project if Now is >= $whenToArchiveProject
                                $archiveProject = [DateTime]::Now -ge $whenToArchiveProject
                            }
                            else
                            {
                                Write-Host ("Unable to parse {0} into a [DateTime] value.  Project `"{1}`" not archive at this time." -f @($config.ArchiveProjects[$a].Start, $config.ArchiveProjects[$a].Source))
                            }
                        } `
                        else
                        {
                            # Nothing.
                        }

                        if($archiveProject)
                        {
                            # Construct the path for this project
                            $projectFolder = "{0}{1}{2}" -f @($config.ProjectRoot, [System.IO.Path]::DirectorySeparatorChar, $config.ArchiveProjects[$a].Source)

                            # Make sure the project folder exists.
                            if([System.IO.Directory]::Exists($projectFolder))
                            {
                                # If no .Destination was provided for the project, then assume .Destination == .Source
                                if([String]::IsNullOrEmpty($config.ArchiveProjects[$a].Destination))
                                {
                                    $config.ArchiveProjects[$a].Destination = $config.ArchiveProjects[$a].Source
                                }
                                else
                                {
                                    # Nothing, use .Destination as is
                                }

                                # Construct the path for the project archive folder
                                $projectArchiveFolder = "{0}{1}{2}" -f @($config.ArchiveRoot, [System.IO.Path]::DirectorySeparatorChar, $config.ArchiveProjects[$a].Destination)

                                # If the project archive folder does not exist, then create it...
                                if(-not [System.IO.Directory]::Exists($projectArchiveFolder))
                                {
                                    try
                                    {
                                        $newDirectoryInfo = [System.IO.Directory]::CreateDirectory($projectArchiveFolder)
                                        $archiveProject = $null -ne $newDirectoryInfo
                                    }
                                    catch
                                    {
                                        Write-Error ("Failed to create project archive folder: [{0}]." -f @($projectArchiveFolder))
                                        $archiveProject = $false
                                    }
                                }
                                else
                                {
                                    # Nothing the project's archive folder is already there  [NOTE: May need to revisit this -- might be an issue i.e. Don't add files to an existing folder]
                                }

                                # Are we still good to archive the project?
                                if($archiveProject)
                                {
                                    # Enumerate all the folders/files for the project and move them to their new home...
                                    
                                }
                            } `
                            else
                            {
                                Write-Error ("{0} project folder [{1}] not found!" -f @($config.ArchiveProjects[$a].Source, $projectFolder))
                            }
                        }
                        else
                        {
                            # Nothing, something has prevented this project from being archived.
                        }
                    } `
                    else
                    {
                        $archiveProject = $false
                    }
                    $a++
                }
            } `
            else
            {
                Write-Error ("Project archive root folder not found! [{0}]" -f @($config.ArchiveRoot))
            }
        } `
        else
        {
            Write-Error ("Project root folder not found! [{0}]" -f @($config.ProjectRoot))
        }
    }
    catch
    {
        Write-Error ("Failed to parse raw configuration into JSON.")
    }
}
catch
{
    Write-Error ("Failed to read configuration from {0}." -f @($JSONConfigFile))
}
