# Dot-source this file to use the project-local Node toolchain:
#   . .\sandbox\scripts\env.ps1
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$nodeVersion = (Get-Content (Join-Path $repoRoot ".nvmrc") -Raw).Trim()
$env:PATH = "$repoRoot\.tools\node-v$nodeVersion-win-x64;$env:PATH"
$env:npm_config_cache = Join-Path $repoRoot ".tools\npm-cache"
$env:HUSKY = "0"
Set-Location $repoRoot
