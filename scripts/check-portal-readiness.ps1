<#
.SYNOPSIS
Checks whether an Azure-managed API Center portal's identity prerequisites are
configured without changing Azure or Microsoft Entra state.

.DESCRIPTION
Reads values from the selected azd environment unless explicit parameters are
provided. Returns ready, failed, or unverified. A ready result verifies static
configuration and anonymous denial; a real non-owner browser test is still
required before the portal is considered operational.

.EXAMPLE
pwsh ./scripts/check-portal-readiness.ps1

.EXAMPLE
pwsh ./scripts/check-portal-readiness.ps1 -OutputFormat json
#>
[CmdletBinding()]
param(
    [string]$ApiCenterResourceId = "",
    [string]$PortalClientId = "",
    [string]$ReadersGroupId = "",
    [string]$TestPrincipalId = "",
    [ValidateSet("text", "json")]
    [string]$OutputFormat = "text",
    [string]$StatePath = ""
)

$ErrorActionPreference = "Stop"
$apiCenterResourceAppId = "c3ca1a77-7a87-4dba-b8f8-eea115ae4573"
$apiCenterDataReaderRoleId = "c7244dfb-f447-457d-b2ba-3999044d1706"

function Invoke-External {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$Json
    )

    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) "portal-readiness-$([guid]::NewGuid()).log"
    try {
        $output = & $FilePath @Arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $errorText = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
            $errorCategory = "command-failed"
            if ($errorText -match "(?i)(ResourceNotFound|Request_ResourceNotFound|status code.? 404|could not be found|does not exist)") {
                $errorCategory = "not-found"
            }
            return [pscustomobject]@{
                Success = $false
                Value = $null
                ErrorCategory = $errorCategory
            }
        }

        $text = ($output | Out-String).Trim()
        if ($Json) {
            if ([string]::IsNullOrWhiteSpace($text)) {
                return [pscustomobject]@{
                    Success = $true
                    Value = $null
                    ErrorCategory = ""
                }
            }

            try {
                $value = $text | ConvertFrom-Json
            }
            catch {
                return [pscustomobject]@{
                    Success = $false
                    Value = $null
                    ErrorCategory = "invalid-json"
                }
            }

            return [pscustomobject]@{
                Success = $true
                Value = $value
                ErrorCategory = ""
            }
        }

        return [pscustomobject]@{
            Success = $true
            Value = $text
            ErrorCategory = ""
        }
    }
    finally {
        Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-AzdValue {
    param([Parameter(Mandatory)][string]$Name)

    $result = Invoke-External -FilePath "azd" -Arguments @("env", "get-value", $Name)
    if (-not $result.Success -or [string]::IsNullOrWhiteSpace($result.Value) -or $result.Value -eq "null") {
        return ""
    }
    return $result.Value.Trim()
}

function New-State {
    param([bool]$TestPrincipalRequested)

    return [ordered]@{
        inputs = [ordered]@{
            apiCenterConfigured = $false
            portalClientConfigured = $false
            readersGroupConfigured = $false
        }
        portal = [ordered]@{
            inspectable = $false
            exists = $false
            enabled = $false
            authMode = ""
            anonymousAccess = $true
            tenantMatches = $false
            clientMatches = $false
        }
        application = [ordered]@{
            inspectable = $false
            exists = $false
            singleTenant = $false
            redirectUriMatches = $false
            clientServicePrincipalExists = $false
            scopeResolution = "unverified"
            permissionConfigured = $false
            consentInspectable = $false
            tenantWideConsent = $false
        }
        reader = [ordered]@{
            inspectable = $false
            exists = $false
            securityEnabled = $false
            rbacInspectable = $false
            dataReaderAtServiceScope = $false
        }
        anonymousProbe = [ordered]@{
            inspectable = $false
            statusCode = 0
        }
        testPrincipal = [ordered]@{
            requested = $TestPrincipalRequested
            inspectable = $false
            effectiveDataReader = $false
        }
    }
}

function Add-Check {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Checks,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet("pass", "fail", "unverified")]
        [string]$Outcome,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Checks.Add([pscustomobject]@{
        name = $Name
        outcome = $Outcome
        message = $Message
    })
}

function Test-ReadinessState {
    param([Parameter(Mandatory)]$State)

    $checks = [System.Collections.Generic.List[object]]::new()

    foreach ($inputCheck in @(
        @{ Name = "api-center-input"; Present = $State.inputs.apiCenterConfigured; Message = "API Center resource ID is configured." },
        @{ Name = "portal-client-input"; Present = $State.inputs.portalClientConfigured; Message = "Portal client ID is configured." },
        @{ Name = "reader-group-input"; Present = $State.inputs.readersGroupConfigured; Message = "Reader security-group ID is configured." }
    )) {
        if ($inputCheck.Present) {
            Add-Check -Checks $checks -Name $inputCheck.Name -Outcome pass -Message $inputCheck.Message
        }
        else {
            Add-Check -Checks $checks -Name $inputCheck.Name -Outcome fail -Message ($inputCheck.Message -replace " is configured", " is missing")
        }
    }

    if (-not $State.portal.inspectable) {
        Add-Check -Checks $checks -Name "portal-resource" -Outcome unverified -Message "Portal ARM configuration could not be inspected."
    }
    elseif (-not $State.portal.exists) {
        Add-Check -Checks $checks -Name "portal-resource" -Outcome fail -Message "The managed portal resource does not exist."
    }
    else {
        Add-Check -Checks $checks -Name "portal-resource" -Outcome pass -Message "The managed portal resource exists."
        if ($State.portal.enabled) {
            Add-Check -Checks $checks -Name "portal-enabled" -Outcome pass -Message "The managed portal is enabled."
        }
        else {
            Add-Check -Checks $checks -Name "portal-enabled" -Outcome fail -Message "The managed portal is disabled."
        }
        if ($State.portal.authMode -eq "azureRbac") {
            Add-Check -Checks $checks -Name "portal-auth-mode" -Outcome pass -Message "The portal uses Azure RBAC authorization."
        }
        else {
            Add-Check -Checks $checks -Name "portal-auth-mode" -Outcome fail -Message "The portal does not use the required azureRbac mode."
        }
        if ($State.portal.anonymousAccess) {
            Add-Check -Checks $checks -Name "portal-anonymous-setting" -Outcome fail -Message "Anonymous portal access is enabled."
        }
        else {
            Add-Check -Checks $checks -Name "portal-anonymous-setting" -Outcome pass -Message "Anonymous portal access is disabled."
        }
        if ($State.portal.tenantMatches) {
            Add-Check -Checks $checks -Name "portal-tenant" -Outcome pass -Message "The portal tenant matches the deployment tenant."
        }
        else {
            Add-Check -Checks $checks -Name "portal-tenant" -Outcome fail -Message "The portal tenant does not match the deployment tenant."
        }
        if ($State.portal.clientMatches) {
            Add-Check -Checks $checks -Name "portal-client" -Outcome pass -Message "The portal references the configured client application."
        }
        else {
            Add-Check -Checks $checks -Name "portal-client" -Outcome fail -Message "The portal does not reference the configured client application."
        }
    }

    if (-not $State.application.inspectable) {
        Add-Check -Checks $checks -Name "portal-application" -Outcome unverified -Message "Portal application and consent state could not be inspected with the current directory identity."
    }
    elseif (-not $State.application.exists) {
        Add-Check -Checks $checks -Name "portal-application" -Outcome fail -Message "The configured portal application does not exist."
    }
    else {
        Add-Check -Checks $checks -Name "portal-application" -Outcome pass -Message "The configured portal application exists."
        if ($State.application.singleTenant) {
            Add-Check -Checks $checks -Name "single-tenant-app" -Outcome pass -Message "The portal application is single-tenant."
        }
        else {
            Add-Check -Checks $checks -Name "single-tenant-app" -Outcome fail -Message "The portal application is not single-tenant."
        }
        if ($State.application.redirectUriMatches) {
            Add-Check -Checks $checks -Name "portal-redirect" -Outcome pass -Message "The portal SPA redirect URI is configured."
        }
        else {
            Add-Check -Checks $checks -Name "portal-redirect" -Outcome fail -Message "The portal SPA redirect URI is missing."
        }
        if ($State.application.clientServicePrincipalExists) {
            Add-Check -Checks $checks -Name "portal-service-principal" -Outcome pass -Message "The portal client service principal exists."
        }
        else {
            Add-Check -Checks $checks -Name "portal-service-principal" -Outcome fail -Message "The portal client service principal is missing."
        }

        switch ($State.application.scopeResolution) {
            "Data.Read.All" {
                Add-Check -Checks $checks -Name "delegated-scope" -Outcome pass -Message "The current Data.Read.All delegated scope was resolved."
            }
            "user_impersonation" {
                Add-Check -Checks $checks -Name "delegated-scope" -Outcome pass -Message "The legacy user_impersonation delegated scope was resolved; review migration to the current scope."
            }
            "ambiguous" {
                Add-Check -Checks $checks -Name "delegated-scope" -Outcome fail -Message "The Azure API Center delegated scope is ambiguous."
            }
            "missing" {
                Add-Check -Checks $checks -Name "delegated-scope" -Outcome fail -Message "No supported Azure API Center delegated scope was found."
            }
            default {
                Add-Check -Checks $checks -Name "delegated-scope" -Outcome unverified -Message "The Azure API Center delegated scope could not be inspected."
            }
        }

        if ($State.application.permissionConfigured) {
            Add-Check -Checks $checks -Name "delegated-permission" -Outcome pass -Message "The portal app requests the resolved delegated permission."
        }
        else {
            Add-Check -Checks $checks -Name "delegated-permission" -Outcome fail -Message "The portal app does not request the resolved delegated permission."
        }

        if (-not $State.application.consentInspectable) {
            Add-Check -Checks $checks -Name "tenant-wide-consent" -Outcome unverified -Message "Tenant-wide delegated consent could not be inspected."
        }
        elseif ($State.application.tenantWideConsent) {
            Add-Check -Checks $checks -Name "tenant-wide-consent" -Outcome pass -Message "Tenant-wide delegated consent covers the resolved scope."
        }
        else {
            Add-Check -Checks $checks -Name "tenant-wide-consent" -Outcome fail -Message "Tenant-wide delegated consent does not cover the resolved scope."
        }
    }

    if (-not $State.reader.inspectable) {
        Add-Check -Checks $checks -Name "reader-group" -Outcome unverified -Message "The configured reader group could not be inspected with the current directory identity."
    }
    elseif (-not $State.reader.exists) {
        Add-Check -Checks $checks -Name "reader-group" -Outcome fail -Message "The configured reader group does not exist."
    }
    elseif (-not $State.reader.securityEnabled) {
        Add-Check -Checks $checks -Name "reader-group" -Outcome fail -Message "The configured reader principal is not a security-enabled group."
    }
    else {
        Add-Check -Checks $checks -Name "reader-group" -Outcome pass -Message "The configured reader principal is a security-enabled group."
    }

    if (-not $State.reader.rbacInspectable) {
        Add-Check -Checks $checks -Name "reader-rbac" -Outcome unverified -Message "The reader-group Azure RBAC assignment could not be inspected."
    }
    elseif ($State.reader.dataReaderAtServiceScope) {
        Add-Check -Checks $checks -Name "reader-rbac" -Outcome pass -Message "The reader group has Data Reader at the API Center resource."
    }
    else {
        Add-Check -Checks $checks -Name "reader-rbac" -Outcome fail -Message "The reader group lacks Data Reader at the API Center resource."
    }

    if (-not $State.anonymousProbe.inspectable) {
        Add-Check -Checks $checks -Name "anonymous-probe" -Outcome unverified -Message "Anonymous data-plane denial could not be tested."
    }
    elseif ($State.anonymousProbe.statusCode -in @(401, 403)) {
        Add-Check -Checks $checks -Name "anonymous-probe" -Outcome pass -Message "An unauthenticated data-plane request was denied."
    }
    elseif ($State.anonymousProbe.statusCode -eq 200) {
        Add-Check -Checks $checks -Name "anonymous-probe" -Outcome fail -Message "An unauthenticated data-plane request returned catalog data."
    }
    else {
        Add-Check -Checks $checks -Name "anonymous-probe" -Outcome unverified -Message "The anonymous probe returned an unexpected response."
    }

    if ($State.testPrincipal.requested) {
        if (-not $State.testPrincipal.inspectable) {
            Add-Check -Checks $checks -Name "test-principal-rbac" -Outcome unverified -Message "Effective group-derived access for the test principal could not be inspected."
        }
        elseif ($State.testPrincipal.effectiveDataReader) {
            Add-Check -Checks $checks -Name "test-principal-rbac" -Outcome pass -Message "The test principal has effective Data Reader access."
        }
        else {
            Add-Check -Checks $checks -Name "test-principal-rbac" -Outcome fail -Message "The test principal lacks effective Data Reader access."
        }
    }

    $status = "ready"
    if (@($checks | Where-Object { $_.outcome -eq "fail" }).Count -gt 0) {
        $status = "failed"
    }
    elseif (@($checks | Where-Object { $_.outcome -eq "unverified" }).Count -gt 0) {
        $status = "unverified"
    }

    return [pscustomobject]@{
        status = $status
        checks = @($checks)
        browserVerificationRequired = $true
    }
}

function Get-HttpStatus {
    param([Parameter(Mandatory)][string]$Uri)

    $client = [System.Net.Http.HttpClient]::new()
    try {
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        return [pscustomobject]@{
            Success = $true
            StatusCode = [int]$response.StatusCode
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            StatusCode = 0
        }
    }
    finally {
        $client.Dispose()
    }
}

function Get-LiveState {
    param(
        [string]$ResourceId,
        [string]$ClientId,
        [string]$GroupId,
        [string]$EffectiveTestPrincipalId
    )

    if ($null -eq (Get-Command "az" -ErrorAction SilentlyContinue)) {
        throw "Required command 'az' is not installed."
    }
    $azdAvailable = $null -ne (Get-Command "azd" -ErrorAction SilentlyContinue)
    $needsAzdInputs = (
        [string]::IsNullOrWhiteSpace($ResourceId) -or
        [string]::IsNullOrWhiteSpace($ClientId) -or
        [string]::IsNullOrWhiteSpace($GroupId)
    )
    if ($needsAzdInputs -and -not $azdAvailable) {
        throw "Required command 'azd' is not installed and explicit portal inputs were not supplied."
    }

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        $ResourceId = Get-AzdValue -Name "apiCenterResourceId"
    }
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $ClientId = Get-AzdValue -Name "PORTAL_ENTRA_CLIENT_ID"
    }
    if ([string]::IsNullOrWhiteSpace($GroupId)) {
        $GroupId = Get-AzdValue -Name "CATALOG_READERS_PRINCIPAL_ID"
    }

    $state = New-State -TestPrincipalRequested (-not [string]::IsNullOrWhiteSpace($EffectiveTestPrincipalId))
    $state.inputs.apiCenterConfigured = -not [string]::IsNullOrWhiteSpace($ResourceId)
    $state.inputs.portalClientConfigured = -not [string]::IsNullOrWhiteSpace($ClientId)
    $state.inputs.readersGroupConfigured = -not [string]::IsNullOrWhiteSpace($GroupId)

    $account = Invoke-External -FilePath "az" -Arguments @("account", "show", "--output", "json", "--only-show-errors") -Json
    $tenantId = ""
    if ($account.Success -and $null -ne $account.Value) {
        $tenantId = [string]$account.Value.tenantId
    }

    $portalHostname = ""
    $dataApiHostname = ""
    if ($azdAvailable) {
        $portalHostname = Get-AzdValue -Name "portalHostname"
        $dataApiHostname = Get-AzdValue -Name "dataApiHostname"
    }

    if ($state.inputs.apiCenterConfigured) {
        $service = Invoke-External -FilePath "az" -Arguments @(
            "rest",
            "--method", "GET",
            "--url", "https://management.azure.com${ResourceId}?api-version=2024-06-01-preview",
            "--output", "json",
            "--only-show-errors"
        ) -Json
        if ($service.Success -and $null -ne $service.Value) {
            $livePortalHostname = [string]$service.Value.properties.portalHostname
            $liveDataApiHostname = [string]$service.Value.properties.dataApiHostname
            if (-not [string]::IsNullOrWhiteSpace($livePortalHostname)) {
                $portalHostname = $livePortalHostname
            }
            if (-not [string]::IsNullOrWhiteSpace($liveDataApiHostname)) {
                $dataApiHostname = $liveDataApiHostname
            }
        }

        $portalId = "$ResourceId/portals/default"
        $portal = Invoke-External -FilePath "az" -Arguments @(
            "rest",
            "--method", "GET",
            "--url", "https://management.azure.com${portalId}?api-version=2024-06-01-preview",
            "--output", "json",
            "--only-show-errors"
        ) -Json
        if ($portal.Success) {
            $state.portal.inspectable = $true
            $state.portal.exists = $null -ne $portal.Value
            if ($state.portal.exists) {
                $state.portal.enabled = $portal.Value.properties.enabled -eq $true
                $state.portal.authMode = [string]$portal.Value.properties.authentication.authMode
                $state.portal.anonymousAccess = $portal.Value.properties.allowAnonymousAccess -eq $true
                $state.portal.tenantMatches = (
                    -not [string]::IsNullOrWhiteSpace($tenantId) -and
                    [string]$portal.Value.properties.authentication.tenantId -eq $tenantId
                )
                $state.portal.clientMatches = (
                    $state.inputs.portalClientConfigured -and
                    [string]$portal.Value.properties.authentication.clientId -eq $ClientId
                )
            }
        }
        elseif ($portal.ErrorCategory -eq "not-found") {
            $state.portal.inspectable = $true
            $state.portal.exists = $false
        }

        $assignments = Invoke-External -FilePath "az" -Arguments @(
            "role", "assignment", "list",
            "--scope", $ResourceId,
            "--all",
            "--output", "json",
            "--only-show-errors"
        ) -Json
        if ($assignments.Success) {
            $state.reader.rbacInspectable = $true
            if ($state.inputs.readersGroupConfigured) {
                $matchingAssignments = @(
                    $assignments.Value | Where-Object {
                        [string]$_.principalId -eq $GroupId -and
                        [string]$_.scope -eq $ResourceId -and
                        ([string]$_.roleDefinitionId).EndsWith($apiCenterDataReaderRoleId, [System.StringComparison]::OrdinalIgnoreCase)
                    }
                )
                $state.reader.dataReaderAtServiceScope = $matchingAssignments.Count -gt 0
            }
        }
    }

    if ($state.inputs.portalClientConfigured) {
        $app = Invoke-External -FilePath "az" -Arguments @(
            "ad", "app", "show",
            "--id", $ClientId,
            "--output", "json",
            "--only-show-errors"
        ) -Json
        $apiCenterSp = Invoke-External -FilePath "az" -Arguments @(
            "ad", "sp", "show",
            "--id", $apiCenterResourceAppId,
            "--output", "json",
            "--only-show-errors"
        ) -Json
        $clientSp = Invoke-External -FilePath "az" -Arguments @(
            "ad", "sp", "show",
            "--id", $ClientId,
            "--output", "json",
            "--only-show-errors"
        ) -Json

        if ($app.ErrorCategory -eq "not-found") {
            $state.application.inspectable = $true
            $state.application.exists = $false
        }
        elseif ($app.Success -and ($apiCenterSp.Success -or $apiCenterSp.ErrorCategory -eq "not-found")) {
            $state.application.inspectable = $true
            $state.application.exists = $null -ne $app.Value
            if ($state.application.exists) {
                $state.application.singleTenant = [string]$app.Value.signInAudience -eq "AzureADMyOrg"
                $expectedRedirects = @()
                if (-not [string]::IsNullOrWhiteSpace($portalHostname)) {
                    $expectedRedirects = @("https://$portalHostname", "https://$portalHostname/")
                }
                $actualRedirects = @($app.Value.spa.redirectUris)
                $state.application.redirectUriMatches = @(
                    $expectedRedirects | Where-Object { $actualRedirects -contains $_ }
                ).Count -gt 0
                $state.application.clientServicePrincipalExists = $clientSp.Success -and $null -ne $clientSp.Value

                $resolvedScope = $null
                if ($apiCenterSp.Success) {
                    $currentScopes = @(
                        $apiCenterSp.Value.oauth2PermissionScopes |
                            Where-Object { $_.isEnabled -and $_.value -eq "Data.Read.All" }
                    )
                    $legacyScopes = @(
                        $apiCenterSp.Value.oauth2PermissionScopes |
                            Where-Object { $_.isEnabled -and $_.value -eq "user_impersonation" }
                    )

                    if ($currentScopes.Count -eq 1) {
                        $resolvedScope = $currentScopes[0]
                        $state.application.scopeResolution = "Data.Read.All"
                    }
                    elseif ($currentScopes.Count -gt 1) {
                        $state.application.scopeResolution = "ambiguous"
                    }
                    elseif ($legacyScopes.Count -eq 1) {
                        $resolvedScope = $legacyScopes[0]
                        $state.application.scopeResolution = "user_impersonation"
                    }
                    elseif ($legacyScopes.Count -gt 1) {
                        $state.application.scopeResolution = "ambiguous"
                    }
                    else {
                        $state.application.scopeResolution = "missing"
                    }
                }
                else {
                    $state.application.scopeResolution = "missing"
                }

                if ($null -ne $resolvedScope) {
                    $configuredPermissions = @(
                        $app.Value.requiredResourceAccess |
                            Where-Object { $_.resourceAppId -eq $apiCenterResourceAppId } |
                            ForEach-Object { $_.resourceAccess } |
                            Where-Object { $_.id -eq $resolvedScope.id -and $_.type -eq "Scope" }
                    )
                    $state.application.permissionConfigured = $configuredPermissions.Count -gt 0

                    if ($clientSp.Success -and $null -ne $clientSp.Value -and $null -ne $apiCenterSp.Value) {
                        $filter = [uri]::EscapeDataString("clientId eq '$($clientSp.Value.id)' and resourceId eq '$($apiCenterSp.Value.id)'")
                        $grants = Invoke-External -FilePath "az" -Arguments @(
                            "rest",
                            "--method", "GET",
                            "--url", "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter",
                            "--output", "json",
                            "--only-show-errors"
                        ) -Json
                        if ($grants.Success) {
                            $state.application.consentInspectable = $true
                            $matchingGrants = @(
                                $grants.Value.value | Where-Object {
                                    $_.consentType -eq "AllPrincipals" -and
                                    @(([string]$_.scope -split "\s+") | Where-Object { $_ -eq $resolvedScope.value }).Count -gt 0
                                }
                            )
                            $state.application.tenantWideConsent = $matchingGrants.Count -gt 0
                        }
                    }
                }
            }
        }
    }

    if ($state.inputs.readersGroupConfigured) {
        $group = Invoke-External -FilePath "az" -Arguments @(
            "rest",
            "--method", "GET",
            "--url", "https://graph.microsoft.com/v1.0/groups/${GroupId}?`$select=id,securityEnabled",
            "--output", "json",
            "--only-show-errors"
        ) -Json
        if ($group.Success) {
            $state.reader.inspectable = $true
            $state.reader.exists = $null -ne $group.Value
            if ($state.reader.exists) {
                $state.reader.securityEnabled = $group.Value.securityEnabled -eq $true
            }
        }
        elseif ($group.ErrorCategory -eq "not-found") {
            $state.reader.inspectable = $true
            $state.reader.exists = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($EffectiveTestPrincipalId) -and $state.inputs.apiCenterConfigured) {
        $effectiveAssignments = Invoke-External -FilePath "az" -Arguments @(
            "role", "assignment", "list",
            "--assignee", $EffectiveTestPrincipalId,
            "--scope", $ResourceId,
            "--include-groups",
            "--include-inherited",
            "--all",
            "--output", "json",
            "--only-show-errors"
        ) -Json
        if ($effectiveAssignments.Success) {
            $state.testPrincipal.inspectable = $true
            $effectiveDataReader = @(
                $effectiveAssignments.Value | Where-Object {
                    [string]$_.principalId -eq $GroupId -and
                    ([string]$_.roleDefinitionId).EndsWith($apiCenterDataReaderRoleId, [System.StringComparison]::OrdinalIgnoreCase)
                }
            )
            $state.testPrincipal.effectiveDataReader = $effectiveDataReader.Count -gt 0
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($dataApiHostname)) {
        $probe = Get-HttpStatus -Uri "https://$dataApiHostname/workspaces/default/apis?api-version=2024-02-01-preview"
        $state.anonymousProbe.inspectable = $probe.Success
        $state.anonymousProbe.statusCode = $probe.StatusCode
    }

    return $state
}

if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "State fixture not found."
    }
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
}
else {
    $state = Get-LiveState `
        -ResourceId $ApiCenterResourceId `
        -ClientId $PortalClientId `
        -GroupId $ReadersGroupId `
        -EffectiveTestPrincipalId $TestPrincipalId
}

$result = Test-ReadinessState -State $state

if ($OutputFormat -eq "json") {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Host "Portal readiness: $($result.status.ToUpperInvariant())"
    foreach ($check in $result.checks) {
        Write-Host ("[{0}] {1}" -f $check.outcome.ToUpperInvariant(), $check.message)
    }
    Write-Host "[REQUIRED] Complete the clean-browser non-owner acceptance test before declaring the portal operational."
}

switch ($result.status) {
    "ready" { exit 0 }
    "failed" { exit 1 }
    default { exit 2 }
}
