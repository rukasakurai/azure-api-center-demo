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
    [string]$AppName = ""
)

$ErrorActionPreference = "Stop"

# azd stores Bicep outputs under their literal output name, so this is
# 'portalHostname' (camelCase), not PORTAL_HOSTNAME.
$host_ = (azd env get-value portalHostname 2>$null)
if ([string]::IsNullOrWhiteSpace($host_) -or $host_ -eq "null") {
    Write-Error "portalHostname not found in the azd environment. Run 'azd provision' (or 'azd up') first."
    exit 1
}
# The portal's MSAL client uses the page URL (with a trailing slash) as the
# redirect URI, e.g. https://<host>/. Register both the trailing-slash and
# bare forms so sign-in can't fail with AADSTS50011 (redirect URI mismatch).
$redirectUri = "https://$host_/"
$redirectUriBare = "https://$host_"

if ([string]::IsNullOrWhiteSpace($AppName)) {
    $serviceName = $host_.Split('.')[0]
    $AppName = "api-center-portal-$serviceName"
}

Write-Host "Portal redirect URI : $redirectUri"
Write-Host "App display name    : $AppName"

$apps = @(az ad app list --display-name $AppName -o json | ConvertFrom-Json)
$matchingApps = @(
    $apps | Where-Object {
        $_.spa.redirectUris -contains $redirectUri -or
        $_.spa.redirectUris -contains $redirectUriBare
    }
)
if ($matchingApps.Count -gt 1) {
    Write-Error "Multiple app registrations named '$AppName' already use this portal redirect URI. Resolve the duplicate registrations before continuing."
    exit 1
}

$appId = if ($matchingApps.Count -eq 1) {
    $matchingApps[0].appId
}
elseif ($apps.Count -eq 1) {
    $apps[0].appId
}
elseif ($apps.Count -gt 1) {
    Write-Error "Multiple app registrations named '$AppName' exist, but none use this portal redirect URI. Use a unique app name or remove the duplicates."
    exit 1
}
else {
    $null
}

if ([string]::IsNullOrWhiteSpace($appId)) {
    Write-Host "Creating app registration..."
    $appId = (az ad app create --display-name $AppName --query appId -o tsv)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appId)) {
        Write-Error "Failed to create the app registration."
        exit 1
    }
}
else {
    Write-Host "Reusing existing app registration $appId"
}

# Entra is eventually consistent: a freshly created app may not be queryable
# for a few seconds. Retry until it resolves before configuring it.
$objId = $null
foreach ($i in 1..10) {
    $objId = (az ad app show --id $appId --query id -o tsv 2>$null)
    if (-not [string]::IsNullOrWhiteSpace($objId)) { break }
    Start-Sleep -Seconds 3
}
if ([string]::IsNullOrWhiteSpace($objId)) {
    Write-Error "App $appId did not become queryable in time. Re-run the script."
    exit 1
}

# Ensure the single-page-application redirect URI is set (API Center portal is a SPA).
$body = @{ spa = @{ redirectUris = @($redirectUri, $redirectUriBare) } } | ConvertTo-Json -Compress
$jsonPath = Join-Path ([System.IO.Path]::GetTempPath()) "api-center-portal-$([guid]::NewGuid()).json"
try {
    $body | Set-Content -Path $jsonPath -Encoding utf8NoBOM
    az rest --method PATCH `
        --url "https://graph.microsoft.com/v1.0/applications/$objId" `
        --headers "Content-Type=application/json" `
        --body "@$jsonPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure the portal redirect URI."
        exit 1
    }
}
finally {
    Remove-Item -Path $jsonPath -Force -ErrorAction SilentlyContinue
}
Write-Host "Redirect URI configured."

# Ensure a service principal exists so role assignments can target the app.
az ad sp show --id $appId 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az ad sp create --id $appId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create the app registration's service principal."
        exit 1
    }
}

azd env set PORTAL_ENTRA_CLIENT_ID $appId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to store PORTAL_ENTRA_CLIENT_ID in the azd environment."
    exit 1
}
Write-Host ""
Write-Host "Done. Client ID $appId stored in the azd environment."
Write-Host "Run 'azd up' to publish the Entra-protected API Center portal."
