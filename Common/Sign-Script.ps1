$scriptFile = "C:\Users\kbriney\KLB\PEI-IT-OPS\DAStats\Get-DAStats.ps1"
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
Set-AuthenticodeSignature -Certificate $cert -FilePath $scriptFile
