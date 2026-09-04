<#
.SYNOPSIS
Registers (idempotently) the Microsoft Entra application that the Azure API
Center self-service portal uses for user sign-in, then stores its client ID in
the azd environment so the next 'azd up' publishes the Entra-protected portal.

.DESCRIPTION
This helper needs Microsoft Entra directory permission to create or update an
app registration. Tenant-wide consent and reader-group membership are separate
administrator operations and are not performed here.

.EXAMPLE
azd up                         # first provision (creates the API Center; portal skipped)
./scripts/register-portal-app.ps1
azd up                         # publishes the portal using the new client ID
#>
param(
    [string]$AppName = ""
)

$ErrorActionPreference = "Stop"
$apiCenterResourceAppId = "c3ca1a77-7a87-4dba-b8f8-eea115ae4573"

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

$app = az ad app show --id $appId -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to inspect app $appId."
    exit 1
}
if ($app.signInAudience -ne "AzureADMyOrg") {
    Write-Error "The existing app is not single-tenant (signInAudience must be AzureADMyOrg). Use a dedicated single-tenant portal app."
    exit 1
}

# Preserve any existing SPA redirects, such as the optional VS Code redirects.
$redirectUris = @($app.spa.redirectUris)
foreach ($requiredRedirectUri in @($redirectUri, $redirectUriBare)) {
    if ($redirectUris -notcontains $requiredRedirectUri) {
        $redirectUris += $requiredRedirectUri
    }
}

$body = @{ spa = @{ redirectUris = $redirectUris } } | ConvertTo-Json -Compress
$jsonPath = Join-Path ([System.IO.Path]::GetTempPath()) "api-center-portal-$([guid]::NewGuid()).json"
try {
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jsonPath, $body, $utf8WithoutBom)
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

# Resolve the current API Center delegated scope instead of hardcoding a
# permission ID or assuming that the legacy scope name is still current.
$apiCenterSp = az ad sp show --id $apiCenterResourceAppId -o json 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $null -eq $apiCenterSp) {
    Write-Error "The Azure API Center enterprise application is unavailable. Confirm that Microsoft.ApiCenter is registered in this tenant."
    exit 1
}

$currentScopes = @(
    $apiCenterSp.oauth2PermissionScopes |
        Where-Object { $_.isEnabled -and $_.value -eq "Data.Read.All" }
)
$legacyScopes = @(
    $apiCenterSp.oauth2PermissionScopes |
        Where-Object { $_.isEnabled -and $_.value -eq "user_impersonation" }
)

$scope = if ($currentScopes.Count -eq 1) {
    $currentScopes[0]
}
elseif ($currentScopes.Count -gt 1) {
    Write-Error "Multiple enabled Data.Read.All scopes were returned for Azure API Center. Resolve the directory inconsistency before continuing."
    exit 1
}
elseif ($legacyScopes.Count -eq 1) {
    Write-Warning "Using the legacy Azure API Center delegated scope name user_impersonation."
    $legacyScopes[0]
}
elseif ($legacyScopes.Count -gt 1) {
    Write-Error "Multiple enabled user_impersonation scopes were returned for Azure API Center. Resolve the directory inconsistency before continuing."
    exit 1
}
else {
    Write-Error "No enabled Data.Read.All or legacy user_impersonation delegated scope was found on the Azure API Center enterprise application."
    exit 1
}

$permissions = @(az ad app permission list --id $appId -o json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to inspect the portal app's configured API permissions."
    exit 1
}
$apiCenterPermission = @(
    $permissions |
        Where-Object { $_.resourceAppId -eq $apiCenterResourceAppId } |
        ForEach-Object { $_.resourceAccess } |
        Where-Object { $_.id -eq $scope.id -and $_.type -eq "Scope" }
)
if ($apiCenterPermission.Count -eq 0) {
    az ad app permission add `
        --id $appId `
        --api $apiCenterResourceAppId `
        --api-permissions "$($scope.id)=Scope" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure the Azure API Center delegated permission."
        exit 1
    }
}
Write-Host "Azure API Center delegated permission configured ($($scope.value))."

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
Write-Host "Application structure is configured. Client ID $appId was stored in the azd environment."
Write-Host "A tenant administrator must separately review and grant consent for the configured delegated permission."
Write-Host "After consent and the reader-group assignment are in place, run:"
Write-Host "  pwsh ./scripts/check-portal-readiness.ps1"
Write-Host "Run 'azd up' to publish the Entra-protected API Center portal."
