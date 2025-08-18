ConnectTo vcenter
$ddcSASRP = Get-ResourcePool -Name "DDC - SAS" -Server $vCenter
$ddcSASVMs = Get-VM -Server $vCenter -Location $ddcSASRP
$ddcSASVMs | Select-Object Name, MemoryMB, NumCPU, UsedSpaceGB | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
