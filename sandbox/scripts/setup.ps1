<#
.SYNOPSIS
  Bootstraps the pinned REA toolchain inside this checkout, without global installs.

.DESCRIPTION
  - Downloads Node.js from .nvmrc into .tools/
  - Restores the Windows native artifact from the matching npm tarball
  - Runs npm ci with a project-local cache
  - Builds the runtime with npm run build:cached

  Everything lives under the repository (ignored by Git).

.EXAMPLE
  .\scripts\setup.ps1
  .\scripts\setup.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

function Invoke-Native {
  param([string]$Label, [scriptblock]$Command)

  # npm and node write progress/warnings to stderr. Stop mode would turn that
  # into a NativeCommandError even when the command succeeds.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $Command
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previous
  if ($code -ne 0) { throw "$Label failed with exit code $code" }
}

$nodeVersion = (Get-Content (Join-Path $repoRoot ".nvmrc") -Raw).Trim()
if (-not $nodeVersion) { throw "Could not read .nvmrc" }

$toolsDir = Join-Path $repoRoot ".tools"
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

$nodeDir = Join-Path $toolsDir "node-v$nodeVersion-win-x64"
$nodeExe = Join-Path $nodeDir "node.exe"

if (-not (Test-Path $nodeExe)) {
  $zip = Join-Path $toolsDir "node-v$nodeVersion-win-x64.zip"
  if (-not (Test-Path $zip)) {
    Write-Host "[setup] Downloading Node.js $nodeVersion..."
    $url = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-win-x64.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  }
  Write-Host "[setup] Extracting Node.js $nodeVersion..."
  Expand-Archive -Path $zip -DestinationPath $toolsDir -Force
}

$env:PATH = "$nodeDir;$env:PATH"
$env:npm_config_cache = Join-Path $toolsDir "npm-cache"
$env:HUSKY = "0"

Write-Host "[setup] node $(node --version) / npm $(npm --version)"

# The Windows native addon ships in the npm tarball, not in Git.
$packageJson = Get-Content (Join-Path $repoRoot "package.json") -Raw | ConvertFrom-Json
$artifactDir = Join-Path $repoRoot "native\windows\build"
$manifest = Join-Path $artifactDir "manifest.json"
$addon = Join-Path $artifactDir "rea-windows-x64.node"

if (-not (Test-Path $manifest) -or -not (Test-Path $addon)) {
  $tgz = Join-Path $toolsDir "rea-agents-$($packageJson.version).tgz"
  $extractDir = Join-Path $toolsDir "rea-agents-$($packageJson.version)"

  if (-not (Test-Path $tgz)) {
    Write-Host "[setup] Restoring native artifact from rea-agents@$($packageJson.version)..."
    $url = "https://registry.npmjs.org/rea-agents/-/rea-agents-$($packageJson.version).tgz"
    Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing
  }

  if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  Invoke-Native "native artifact extraction" { tar -xzf $tgz -C $extractDir }

  New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
  Copy-Item (Join-Path $extractDir "package\native\windows\build\manifest.json") $manifest -Force
  Copy-Item (Join-Path $extractDir "package\native\windows\build\rea-windows-x64.node") $addon -Force
  Write-Host "[setup] Native artifact restored."
}

$needsInstall = $Force -or -not (Test-Path (Join-Path $repoRoot "node_modules\.package-lock.json"))
if ($needsInstall) {
  Write-Host "[setup] Installing locked dependencies (npm ci)..."
  Invoke-Native "npm ci" { & npm.cmd ci --no-audit --no-fund }
}

if (-not $SkipBuild) {
  Write-Host "[setup] Building REA..."
  Invoke-Native "npm run build:cached" { & npm.cmd run build:cached }
}

Write-Host "[setup] Verifying CLI..."
Invoke-Native "REA CLI" { & node scripts/rea.mjs --version }

Write-Host ""
Write-Host "Host toolchain ready."
Write-Host "  CLI:   .\sandbox\scripts\host-rea.cmd --help   (or set PATH to $nodeDir)"
Write-Host "  Tests: .\sandbox\scripts\sandbox.ps1 exec npm run test:local -- tests/"
Write-Host "  Lab:   .\sandbox\scripts\sandbox.ps1 build"
