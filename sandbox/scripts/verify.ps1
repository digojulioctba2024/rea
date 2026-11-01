<#
.SYNOPSIS
  Smoke-tests the isolated environment end to end.

.DESCRIPTION
  Runs the host CLI, the offline lab container and a source test in the dev
  container. Use -Full to run the broader fast checks.

.EXAMPLE
  .\scripts\verify.ps1
  .\scripts\verify.ps1 -Full
#>
[CmdletBinding()]
param(
  [switch]$Full
)

$ErrorActionPreference = "Stop"
$sandboxDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoRoot = (Resolve-Path (Join-Path $sandboxDir "..")).Path
$composeFile = Join-Path $sandboxDir "compose.yaml"
$sandbox = Join-Path $PSScriptRoot "sandbox.ps1"

function Assert-Exit([string]$Label) {
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE"
  }
  Write-Host "[verify] $Label OK"
}

Write-Host "[verify] Host CLI"
& $sandbox host --version
Assert-Exit "host CLI"

Write-Host "[verify] Docker image"
& docker image inspect rea-sandbox:local *> $null
Assert-Exit "Docker image"

Write-Host "[verify] Lab container (offline, read-only)"
& docker compose -f $composeFile run --rm lab rea --version
Assert-Exit "lab CLI"

Write-Host "[verify] Lab has no network"
& docker compose -f $composeFile run --rm lab bash -lc "command -v getent >/dev/null 2>&1 || exit 2; if getent hosts registry.npmjs.org >/dev/null 2>&1; then exit 1; else exit 0; fi"
Assert-Exit "lab network isolation"

Write-Host "[verify] Dev container"
& docker compose -f $composeFile run --rm dev node --version
Assert-Exit "dev node"

Write-Host "[verify] Source test"
& docker compose -f $composeFile run --rm dev npm run test:local -- src/config.test.ts
Assert-Exit "dev source test"

if ($Full) {
  Write-Host "[verify] Fast static checks"
  & docker compose -f $composeFile run --rm dev npm run check:fast
  Assert-Exit "check:fast"

  Write-Host "[verify] Python producer tests"
  & docker compose -f $composeFile run --rm dev npm run test:python
  Assert-Exit "test:python"
}

Write-Host ""
Write-Host "[verify] All requested checks passed."
