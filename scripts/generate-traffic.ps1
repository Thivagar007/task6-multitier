<#
.SYNOPSIS
  Generates realistic mixed traffic against both regional backends so the
  Grafana dashboard has data: fast calls, SQL calls, slow calls (latency
  p95), and a small share of HTTP 500s (error rate).

.EXAMPLE
  ./scripts/generate-traffic.ps1 -Minutes 10
#>
param(
    [int]    $Minutes = 10,
    [string] $Prefix  = "task6",
    [string] $Suffix  = "jwqg"
)

$targets = @(
    @{ Weight = 8; Url = "https://app-$Prefix-api-cin-$Suffix.azurewebsites.net" },  # ~80% Central India
    @{ Weight = 2; Url = "https://app-$Prefix-api-sin-$Suffix.azurewebsites.net" }   # ~20% South India
)
$pool = foreach ($t in $targets) { 1..$t.Weight | ForEach-Object { $t.Url } }

# Weighted mix of endpoints
$paths = @(
    "/api/info", "/api/info", "/api/info", "/api/info",
    "/api/orders", "/api/orders",
    "/api/health",
    "/api/slow?ms=600", "/api/slow?ms=1500",   # drives p95 up
    "/api/error"                              # ~10% -> HTTP 500
)

$end = (Get-Date).AddMinutes($Minutes)
$n = 0; $codes = @{}
Write-Host "Generating traffic for $Minutes min (Ctrl+C to stop)..." -ForegroundColor Cyan
while ((Get-Date) -lt $end) {
    $url  = ($pool | Get-Random) + ($paths | Get-Random)
    $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 20 $url
    $codes[$code]++; $n++
    if ($n % 25 -eq 0) {
        $summary = ($codes.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "  "
        Write-Host ("{0:HH:mm:ss}  {1} requests  [{2}]" -f (Get-Date), $n, $summary)
    }
    Start-Sleep -Milliseconds 300
}
Write-Host "Done: $n requests." -ForegroundColor Green
