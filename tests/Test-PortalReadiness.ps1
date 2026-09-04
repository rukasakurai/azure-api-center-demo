$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$checkerPath = Join-Path $repositoryRoot "scripts/check-portal-readiness.ps1"
$casesPath = Join-Path $PSScriptRoot "portal-readiness-cases.json"
$fixtures = Get-Content -LiteralPath $casesPath -Raw | ConvertFrom-Json

function Set-PropertyPath {
    param(
        [Parameter(Mandatory)]
        $Target,
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        $Value
    )

    $segments = $Path.Split(".")
    $cursor = $Target
    for ($index = 0; $index -lt $segments.Count - 1; $index++) {
        $cursor = $cursor.($segments[$index])
    }
    $cursor.($segments[-1]) = $Value
}

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($case in $fixtures.cases) {
    $state = $fixtures.baseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    foreach ($override in $case.overrides.PSObject.Properties) {
        Set-PropertyPath -Target $state -Path $override.Name -Value $override.Value
    }

    $statePath = Join-Path ([System.IO.Path]::GetTempPath()) "portal-readiness-state-$([guid]::NewGuid()).json"
    try {
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding utf8
        $output = & pwsh -NoProfile -File $checkerPath -StatePath $statePath -OutputFormat json
        $exitCode = $LASTEXITCODE
        $result = ($output | Out-String) | ConvertFrom-Json

        if ($result.status -ne $case.expectedStatus) {
            $failures.Add("$($case.name): expected status $($case.expectedStatus), got $($result.status)")
        }
        if ($exitCode -ne $case.expectedExitCode) {
            $failures.Add("$($case.name): expected exit code $($case.expectedExitCode), got $exitCode")
        }
    }
    finally {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "All $(@($fixtures.cases).Count) portal readiness cases passed."
