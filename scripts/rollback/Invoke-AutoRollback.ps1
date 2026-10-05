<#
.SYNOPSIS
  Automatic rollback runbook (Azure Automation, PowerShell 7.2).

.DESCRIPTION
  Triggered by:  App Insights availability test fails
                 -> metric alert fires
                 -> action group -> Automation webhook -> THIS runbook

  Logic:
    1. Ignore "Resolved" notifications (only act on "Fired")
    2. Re-check production /api/health   (skip if it already recovered)
    3. Check the staging slot             (= the PREVIOUS release after a swap)
       - healthy   -> swap staging <-> production  (ROLLBACK)
       - unhealthy -> do NOT swap, fail loudly (both bad = human needed)
    4. Verify production is healthy after the swap

  Identity: the Automation account's system-assigned managed identity,
            granted "Website Contributor" on the backend apps only.

  Parameters ResourceGroup + AppName come from the webhook (one per region).
#>
param(
    [Parameter(Mandatory = $false)] [object] $WebhookData,
    [Parameter(Mandatory = $true)]  [string] $ResourceGroup,
    [Parameter(Mandatory = $true)]  [string] $AppName
)

$ErrorActionPreference = "Stop"

function Get-HealthStatus([string] $Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -SkipHttpErrorCheck
        return [int] $r.StatusCode
    } catch {
        return 0   # timeout / DNS / connection error
    }
}

# ---- 1. Only act on "Fired" alerts -------------------------------------------
if ($WebhookData -and $WebhookData.RequestBody) {
    $alert = $WebhookData.RequestBody | ConvertFrom-Json
    $e = $alert.data.essentials
    Write-Output "Alert rule : $($e.alertRule)"
    Write-Output "Condition  : $($e.monitorCondition)  (severity $($e.severity), fired $($e.firedDateTime))"
    if ($e.monitorCondition -ne "Fired") {
        Write-Output "Not a 'Fired' notification - nothing to do."
        return
    }
}

$prodUrl    = "https://$AppName.azurewebsites.net/api/health"
$stagingUrl = "https://$AppName-staging.azurewebsites.net/api/health"

Write-Output "Connecting with the Automation account managed identity..."
Connect-AzAccount -Identity | Out-Null

# ---- 2. Re-check production ---------------------------------------------------
$prod = Get-HealthStatus $prodUrl
Write-Output "Production health ($prodUrl): $prod"
if ($prod -eq 200) {
    Write-Output "Production is healthy again - no rollback needed."
    return
}

# ---- 3. Is the previous release (now in staging) healthy? ----------------------
$staging = Get-HealthStatus $stagingUrl
Write-Output "Staging / previous release health ($stagingUrl): $staging"
if ($staging -ne 200) {
    throw "Staging is ALSO unhealthy ($staging). Not swapping - manual intervention required."
}

# ---- 4. Roll back ---------------------------------------------------------------
Write-Output ">>> ROLLBACK: swapping 'staging' -> 'production' on $AppName ($ResourceGroup)"
Switch-AzWebAppSlot -ResourceGroupName $ResourceGroup -Name $AppName `
    -SourceSlotName "staging" -DestinationSlotName "production" | Out-Null
Write-Output "Swap completed. Verifying production..."

for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 15
    $prod = Get-HealthStatus $prodUrl
    Write-Output "  check $i : production health = $prod"
    if ($prod -eq 200) {
        Write-Output ">>> ROLLBACK SUCCEEDED: production is healthy on the previous release."
        return
    }
}
throw "Rollback swap done but production is still unhealthy - investigate."
