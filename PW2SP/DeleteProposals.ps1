$propListFile = "E:\PW2SP\20260416-FedProposalsInPW.csv"
$fedProps = Import-CSV -Path $propListFile -Delimiter "`t"

$fedProps | Foreach-Object -ThrottleLimit 10 -Parallel {
    if($_.HasBeenDeleted -eq $false)
    {
        $null = Start-Process -Wait -FilePath pwsh.exe -ArgumentList @(
            "-NoProfile",
            "-File", "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\DeletePWFiles3.ps1",
            "-folderGUID", $_.FolderGUID,
            "-projectName", $_.Name
        )
        $_.HasBeenDeleted = $true

        $mutex = [System.Threading.Mutex]::new($false, "PWProposalDeleteMutex")
        try
        {
            $null = $mutex.WaitOne()   # Wait for any other threads in this block to complete, then block others...
            $using:fedProps | Export-CSV -Path $using:propListFile -Delimiter "`t" -NoTypeInformation -Force -Confirm:$false
        }
        finally   # No matter what happens, make sure to release the mutex...
        {
            $null = $mutex.ReleaseMutex()  # All done, let others play...
        }
    } `
    else
    {
        Write-Host ("{0}:{1} has already beed processed." -f @($_.Name, $_.folderGUID))
    }
}
