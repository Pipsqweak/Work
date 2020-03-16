
                for($b = 0; $b -lt $shares.Count; $b++)
                {
                    # This code ensures the script doesn't enumerate shares that are nested within other shares....
                    #   Example:
                    #   \\server\share1  =  C:\shares\share1
                    #   \\server\share2  =  c:\shares\share1\HR\Documents.
                    #
                    #    Enumerating share1 will also enumerate share2, so skip share 2.  Later in the process, returned paths will be updated to the
                    #       share closest to the path.
                    #
                    #    \\server\share1\HR\Documents\January Expenses.xlsx will be changed to \\server\share2\January Expenses.xlxs


                    # Get all the volumes accessible from the share that are snapmirror and/or snapvault destinations
                    $shareSMSVs = @(@($mountedVols | Where-Object { ($_.JunctionPath.StartsWith($shares[$b].Path)) -and ($_.VServer -eq $cifsServerConfig.Vserver) }) | Where-Object { @($snapMirrors | Select-Object -ExpandProperty DestinationVolume) -contains $_.Name })

                    # Add paths to avoid during enumeration of files and folders (these are all paths that are based on snapmirror/vault destinations) to the list of pathsToAvoid

                    # Start with an array of all the snapmirror/snapvault volume JunctionPaths
                    $smsvJunctionPaths = @($shareSMSVs | Select-Object -ExpandProperty JunctionPath)
                    foreach($smsvJunctionPath in $smsvJunctionPaths)
                    {
                        # Construct a partial share path from the JunctionPath
                        $fixedPath = $smsvJunctionPath.Replace($this.shares[$b].Path,"/{0}" -f @($this.shares[$b].Name))

                        # Now add the partial path to the list of pathsToAvoid...

                    }

                    @($shareSMSVs | Select-Object -ExpandProperty JunctionPath) | ForEach-Object { $_.Replace($this.shares[$b].Path,"/{0}" -f @($this.shares[$b].Name)) } | ForEach-Object { $this.shares[$b].AddPathToAvoid($_) }
                }

function RandomString()
{
    $len = Get-Random -Minimum 25 -Maximum 150
    $str = ""
    for($i = 0; $i -lt $len; $i++)
    {
        $c = Get-Random -Minimum 32 -Maximum 122
        $str += [char] $c
    }

    return $str
}

[Log]::Init("C:\TMP\LogTest", "Test1", 1, 1, [LogLevel]::DEBUG9)

for($x = 0; $x -lt 1000; $x++)
{
    $logLevel = [LogLevel] (Get-Random -Minimum 0 -Maximum ([int32] ([LogLevel]::TRACE)))
    $message = "{0,5} : {1}" -f @(($x+1), (RandomString))
    $Global:isError = $false
    switch ($logLevel)
    {
        "ALERT"
        {
            [Log]::Alert($message)
            break
        }

        "ERROR"
        {
            [Log]::Error($message)
            break
        }

        "WARNING"
        {
            [Log]::Warning($message)
            break
        }

        "INFO"
        {
            [Log]::Info($message)
            break
        }

        "DEBUG"
        {
            [Log]::Debug($message)
            break
        }

        "DEBUG1"
        {
            [Log]::Debug1($message)
            break
        }

        "DEBUG2"
        {
            [Log]::Debug2($message)
            break
        }

        "DEBUG3"
        {
            [Log]::Debug3($message)
            break
        }

        "DEBUG4"
        {
            [Log]::Debug4($message)
            break
        }

        "DEBUG5"
        {
            [Log]::Debug5($message)
            break
        }

        "DEBUG6"
        {
            [Log]::Debug6($message)
            break
        }

        "DEBUG7"
        {
            [Log]::Debug7($message)
            break
        }

        "DEBUG8"
        {
            [Log]::Debug8($message)
            break
        }

        "DEBUG9"
        {
            [Log]::Debug9($message)
            break
        }

        "TRACE"
        {
            [Log]::Trace($message)
            break
        }
    }
}

# Just to make sure we flush the log to storage
[Log]::DumpLog()


if($true)
{
    [Log]::Debug1("level 1")
    if($true)
    {
        [Log]::Debug2("Level 2")
    }
}
