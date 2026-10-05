<#
.SYNOPSIS
  Evidence for "HTTPS-only + TLS 1.2" on every App Service app/slot and Front Door.
  Run from the repo root after `az login`:   .\scripts\verify-https.ps1
#>
param(
  [string]   $Prefix  = "task6",
  [string]   $Suffix  = "jwqg",
  [string[]] $Regions = @("cin", "sin"),
  [string]   $FrontDoorHost = ""
)
$ErrorActionPreference = 'Stop'

Write-Host "`n=== 1. App Service settings (apps + staging slots) ===" -ForegroundColor Cyan
$rows = foreach ($r in $Regions) {
  $rg = "rg-$Prefix-$r"
  foreach ($tier in "api", "web") {
    $app = "app-$Prefix-$tier-$r-$Suffix"
    foreach ($slot in $null, "staging") {
      $slotArgs = if ($slot) { @("--slot", $slot) } else { @() }
      $site = az webapp show -g $rg -n $app @slotArgs --query "{https:httpsOnly, host:defaultHostName}" -o json | ConvertFrom-Json
      $cfg  = az webapp config show -g $rg -n $app @slotArgs --query "{tls:minTlsVersion, scmTls:scmMinTlsVersion, ftps:ftpsState, http2:http20Enabled}" -o json | ConvertFrom-Json
      [pscustomobject]@{
        App = $app; Slot = ($slot ?? "production"); HttpsOnly = $site.https
        MinTLS = $cfg.tls; ScmMinTLS = $cfg.scmTls; FTPS = $cfg.ftps; HTTP2 = $cfg.http2; Host = $site.host
      }
    }
  }
}
$rows | Format-Table App, Slot, HttpsOnly, MinTLS, ScmMinTLS, FTPS, HTTP2 -AutoSize

Write-Host "=== 2. Plain HTTP is redirected to HTTPS ===" -ForegroundColor Cyan
$hosts = @($rows | Where-Object Slot -eq "production" | Select-Object -ExpandProperty Host)
if ($FrontDoorHost) { $hosts += $FrontDoorHost }
foreach ($h in $hosts) {
  $out = curl.exe -s -o NUL -w "%{http_code} -> %{redirect_url}" "http://$h/"
  Write-Host ("{0,-60} {1}" -f "http://$h/", $out)
}

Write-Host "`n=== 3. TLS 1.1 is refused, TLS 1.2 is accepted ===" -ForegroundColor Cyan
$h = $hosts[0]
$old = curl.exe -s -o NUL -w "%{http_code}" --tlsv1.1 --tls-max 1.1 "https://$h/api/health" 2>$null
$new = curl.exe -s -o NUL -w "%{http_code}" --tlsv1.2 --tls-max 1.2 "https://$h/api/health"
Write-Host ("TLS 1.1 -> {0}   (000 = handshake refused)" -f $old)
Write-Host ("TLS 1.2 -> {0}" -f $new)

Write-Host "`n=== 4. Certificate served on the default hostname ===" -ForegroundColor Cyan
$tcp = [Net.Sockets.TcpClient]::new($h, 443)
$ssl = [Net.Security.SslStream]::new($tcp.GetStream(), $false, { $true })
$ssl.AuthenticateAsClient($h)
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
[pscustomobject]@{
  Host = $h; Protocol = $ssl.SslProtocol; Subject = $cert.Subject; Issuer = $cert.Issuer
  NotAfter = $cert.NotAfter
} | Format-List
$ssl.Dispose(); $tcp.Dispose()
