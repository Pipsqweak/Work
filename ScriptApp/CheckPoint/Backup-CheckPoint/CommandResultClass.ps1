class CommandResult
{
    [Boolean] $Successful = $false
    [int] $ExitCode = -1
    [String] $Command = [String]::Empty
    [String] $Output = [String]::Empty
    [Boolean] $ExceededMaximumFailures = $false

    CommandResult ()
    {
    }
}
