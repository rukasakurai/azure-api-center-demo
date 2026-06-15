<#
.SYNOPSIS
Registers (idempotently) the Microsoft Entra application that the Azure API
Center self-service portal uses for user sign-in, then stores its client ID in
the azd environment so the next 'azd up' publishes the Entra-protected portal.

.DESCRIPTION
This is the ONLY step that needs Microsoft Entra *directory* permissions
(creating an app registration), which is why it lives in a helper script rather
than in the Bicep template that anyone with Azure resource access runs.

.EXAMPLE
azd up                         # first provision (creates the API Center; portal skipped)
./scripts/register-portal-app.ps1
azd up                         # publishes the portal using the new client ID
#>
param(
    [string]$AppName = "api-center-portal"
)

$ErrorActionPreference = "Stop"

$host_ = (azd env get-value PORTAL_HOSTNAME 2>$null)
if ([string]::IsNullOrWhiteSpace($host_) -or $host_ -eq "null") {
    Write-Error "PORTAL_HOSTNAME not found in the azd environment. Run 'azd provision' (or 'azd up') first."
    exit 1
}
$redirectUri = "https://$host_"

Write-Host "Portal redirect URI : $redirectUri"
Write-Host "App display name    : $AppName"

$appId = (az ad app list --display-name $AppName --query "[0].appId" -o tsv)
if ([string]::IsNullOrWhiteSpace($appId)) {
    Write-Host "Creating app registration..."
    $appId = (az ad app create --display-name $AppName --query appId -o tsv)
}
else {
    Write-Host "Reusing existing app registration $appId"
}

# Ensure the single-page-application redirect URI is set (API Center portal is a SPA).
$objId = (az ad app show --id $appId --query id -o tsv)
$body = @{ spa = @{ redirectUris = @($redirectUri) } } | ConvertTo-Json -Compress
az rest --method PATCH `
    --url "https://graph.microsoft.com/v1.0/applications/$objId" `
    --headers "Content-Type=application/json" `
    --body $body | Out-Null
Write-Host "Redirect URI configured."

# Ensure a service principal exists so role assignments can target the app.
az ad sp show --id $appId 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { az ad sp create --id $appId | Out-Null }

azd env set PORTAL_ENTRA_CLIENT_ID $appId
Write-Host ""
Write-Host "Done. Client ID $appId stored in the azd environment."
Write-Host "Run 'azd up' to publish the Entra-protected API Center portal."
