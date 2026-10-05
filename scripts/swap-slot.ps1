<#
.SYNOPSIS
  Blue/green deployment of the backend with a gated, zero-downtime slot swap
  and automatic rollback.

.DESCRIPTION
  For each region (one at a time - Central India first, then South India):
    1. Deploy the zip to the STAGING slot (async) and set APP_VERSION
    2. Wait until staging reports the new version and is healthy
    3. Smoke-test staging (/api/info, /api/orders)       <- pre-swap GATE
    4. Swap staging -> production (App Service warms staging first = zero downtime)
    5. Watch production for -WatchMinutes                <- post-swap GATE
       2 consecutive failures => swap back immediately (ROLLBACK) and stop
  A failure in one region stops the rollout before the next region.

  Safety net on top of this script: App Insights availability tests + alert
  + Automation runbook roll back automatically even if nobody is watching.

.EXAMPLE
  # Build/zip first, then:
  ./scripts/swap-slot.ps1 -Version 1.1.0 -ZipPath app/backend.zip

.EXAMPLE
  # Code already in staging - swap only
  ./scripts/swap-slot.ps1 -Version 1.1.0 -SkipDeploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string]   $ZipPath,
    [string[]] $Regions          = @("cin", "sin"),
    [string]   $Prefix           = "task6",
    [string]   $Suffix           = "jwqg",
    [int]      $DeployTimeoutSec = 900,
    [int]      $WatchMinutes     = 3,
    [switch]   $SkipDeploy
)

$ErrorActionPreference = "Stop"

function Write-Step([string] $msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Write-Ok([string] $msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Bad([string] $msg)  { Write-Host "    !!  $msg" -ForegroundColor Red }

function Invoke-Az {
    # Run an az command and fail fast on a non-zero exit code
    & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed (exit $LASTEXITCODE)" }
}

function Get-Health([string] $BaseUrl) {
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/api/health" -UseBasicParsing -TimeoutSec 15 -SkipHttpErrorCheck
        $body = $null
        try { $body = $r.Content | ConvertFrom-Json } catch {}
        return [pscustomobject]@{ Code = [int]$r.StatusCode; Version = $body.version; Slot = $body.slot }
    } catch {
        return [pscustomobject]@{ Code = 0; Version = $null; Slot = $null }
    }
}

function Test-Endpoint([string] $Url) {
    try {
        return [int](Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -SkipHttpErrorCheck).StatusCode
    } catch { return 0 }
}

if (-not $SkipDeploy -and -not $ZipPath) { throw "Provide -ZipPath, or use -SkipDeploy to swap only." }
if ($ZipPath -and -not (Test-Path $ZipPath)) { throw "Zip not found: $ZipPath" }

$summary = @()

foreach ($r in $Regions) {
    $rg      = "rg-$Prefix-$r"
    $app     = "app-$Prefix-api-$r-$Suffix"
    $prodUrl = "https://$app.azurewebsites.net"
    $stgUrl  = "https://$app-staging.azurewebsites.net"

    Write-Host "`n################ $app ($rg) -> v$Version ################" -ForegroundColor Yellow
    $before = Get-Health $prodUrl
    Write-Host "    production before: HTTP $($before.Code), v$($before.Version)"

    # ---- 1. Deploy to staging ---------------------------------------------------
    if (-not $SkipDeploy) {
        Write-Step "1. Deploy to STAGING slot (async)"
        Invoke-Az webapp config appsettings set -g $rg -n $app --slot staging --settings "APP_VERSION=$Version" -o none
        Invoke-Az webapp deploy -g $rg -n $app --slot staging --src-path $ZipPath --type zip --async true -o none
        Write-Ok "package uploaded; building on the server"
    }

    # ---- 2. Wait for staging to run the new version -------------------------------
    Write-Step "2. Wait for staging to report v$Version"
    $deadline = (Get-Date).AddSeconds($DeployTimeoutSec)
    do {
        $h = Get-Health $stgUrl
        Write-Host "    staging: HTTP $($h.Code), v$($h.Version)"
        if ($h.Code -eq 200 -and $h.Version -eq $Version) { break }
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)
    if (-not ($h.Code -eq 200 -and $h.Version -eq $Version)) {
        Write-Bad "staging never became healthy on v$Version - NOT swapping. Production untouched."
        exit 1
    }
    Write-Ok "staging healthy on v$Version"

    # ---- 3. Smoke test staging (pre-swap gate) -------------------------------------
    Write-Step "3. Smoke test staging"
    foreach ($path in "/api/info", "/api/orders") {
        $code = Test-Endpoint "$stgUrl$path"
        if ($code -ne 200) { Write-Bad "$path returned $code - NOT swapping."; exit 1 }
        Write-Ok "$path -> 200"
    }

    # ---- 4. Swap -------------------------------------------------------------------
    Write-Step "4. Swap staging -> production (zero downtime)"
    Invoke-Az webapp deployment slot swap -g $rg -n $app --slot staging --target-slot production
    Write-Ok "swap done"

    # ---- 5. Watch production (post-swap gate) ---------------------------------------
    Write-Step "5. Watch production for $WatchMinutes min (rollback on 2 consecutive failures)"
    $failures = 0
    $end = (Get-Date).AddMinutes($WatchMinutes)
    $rolledBack = $false
    while ((Get-Date) -lt $end) {
        $h = Get-Health $prodUrl
        $ok = ($h.Code -eq 200 -and $h.Version -eq $Version)
        Write-Host ("    {0:HH:mm:ss} production: HTTP {1}, v{2}  {3}" -f (Get-Date), $h.Code, $h.Version, ($(if ($ok) { "ok" } else { "FAIL" })))
        if ($ok) { $failures = 0 } else { $failures++ }
        if ($failures -ge 2) {
            Write-Bad "production unhealthy after swap -> ROLLING BACK"
            Invoke-Az webapp deployment slot swap -g $rg -n $app --slot staging --target-slot production
            $after = Get-Health $prodUrl
            Write-Bad "rolled back: production now HTTP $($after.Code), v$($after.Version)"
            $rolledBack = $true
            break
        }
        Start-Sleep -Seconds 15
    }

    if ($rolledBack) {
        $summary += [pscustomobject]@{ Region = $r; Result = "ROLLED BACK"; Production = "v$($before.Version)" }
        $summary | Format-Table -AutoSize
        Write-Bad "Stopping rollout - remaining regions keep the previous version."
        exit 1
    }

    Write-Ok "$app is serving v$Version"
    $summary += [pscustomobject]@{ Region = $r; Result = "DEPLOYED"; Production = "v$Version" }
}

Write-Step "Rollout complete"
$summary | Format-Table -AutoSize
