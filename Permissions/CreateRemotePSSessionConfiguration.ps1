$username = "kbriney-adm"
$b64 = Get-Content -Path "C:\Users\kbriney\KLB\PEI-IT-Ops\Permissions\ExportedPassword.txt"
$secureStringText = -join ([Convert]::FromBase64String($b64) | ForEach-Object { [char] $_ })
$securePwd = $secureStringText | ConvertTo-SecureString
$user = "{0}\{1}" -f (Get-ADDomain).NetBIOSName, $username
$creds = New-Object System.Management.Automation.PSCredential -ArgumentList $user, $securePwd


$nasToMgmtServer = (Get-Content -Path "C:\Users\kbriney\KLB\PEI-IT-Ops\Permissions\NAS2MgmtServer.json" | ConvertFrom-Json)

$mgmtServers = @($nasToMgmtServer | Where-Object { -not [String]::IsNullOrEmpty($_.MgmtServer) } | Select-Object -Unique -ExpandProperty MgmtServer | Sort-Object)

for($a = 0; $a -lt $mgmtServers.Length; $a++)
{
    Write-Host -NoNewline ("{0} does " -f $mgmtServers[$a])
    $remotePSConf = Invoke-Command -ComputerName $mgmtServers[$a] -ScriptBlock { Get-PSSessionConfiguration -Name $Using:username } -ErrorAction SilentlyContinue
    if($null -eq $remotePSConf)
    {
        Write-Host -NoNewline ("not ")
        # Invoke-Command -ComputerName $mgmtServers[$a] -ScriptBlock { Register-PSSessionConfiguration -Name $Using:username -RunAsCredential $Using:creds -Force }
    }
    Write-Host ("have a PS remote configuration for {0}" -f $username)
}

for($a = 0; $a -lt $mgmtServers.Length; $a++)
{
    Write-Host ("{0}" -f $mgmtServers[$a])
    $remotePSConf = Invoke-Command -ComputerName $mgmtServers[$a] -ScriptBlock { Get-PSSessionConfiguration -Name $Using:username } -ErrorAction SilentlyContinue
    if($null -eq $remotePSConf)
    {
        Write-Host ("`tcreating")
        Invoke-Command -ComputerName $mgmtServers[$a] -ScriptBlock { Register-PSSessionConfiguration -Name $Using:username -RunAsCredential $Using:creds -Force }
    }
}
