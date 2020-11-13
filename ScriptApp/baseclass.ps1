class ScriptApplication
{
    # The path where the script application framework is stored.
    [String] $RootPath = [String]::Empty

    # The name of the script application that is running.
    [String] $Name = [String]::Empty

    # The path where the specific script application is stored.
    [String] $ScriptRoot = [String]::Empty

    [Object[]] $Settings = $null

    ScriptApplication([String] $scriptAppPath, [String] $jsonArgsFile)
    {
    }
}   # ScriptApplication
