<#
.SYNOPSIS
  Entry point for the isolated REA environment.

.EXAMPLES
  .\scripts\sandbox.ps1 setup
  .\scripts\sandbox.ps1 shell
  .\scripts\sandbox.ps1 exec npm run test:local -- tests/domain
  .\scripts\sandbox.ps1 lab analyze-javascript-application /samples/app --json
  .\scripts\sandbox.ps1 web analyze-website https://example.com --json
  .\scripts\sandbox.ps1 host --help
  .\scripts\sandbox.ps1 host-npm run test:local -- tests/
  .\scripts\sandbox.ps1 reset
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("setup", "build", "shell", "exec", "lab", "web", "host", "host-npm", "down", "status", "reset", "help")]
  [string]$Command = "help",

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"
$sandboxDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoRoot = (Resolve-Path (Join-Path $sandboxDir "..")).Path
$composeFile = Join-Path $sandboxDir "compose.yaml"

function Test-Docker {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  & docker info *> $null
  $ok = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $previous
  return $ok
}

function Ensure-Docker {
  if (Test-Docker) { return }

  $exe = Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\Docker Desktop.exe"
  if (-not (Test-Path $exe)) {
    throw "Docker is not running and Docker Desktop was not found. Start Docker and retry."
  }

  Write-Host "[sandbox] Starting Docker Desktop..."
  Start-Process -FilePath $exe | Out-Null

  $deadline = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if (Test-Docker) {
      Write-Host "[sandbox] Docker is ready."
      return
    }
  }
  throw "Docker did not become ready within 4 minutes."
}

function Invoke-Compose {
  & docker compose -f $composeFile @args
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Show-Help {
  @"
REA sandbox commands

  setup      Bootstrap the host toolchain and build the Docker image
  build      Build/refresh the Docker image (rea-sandbox:local)
  shell      Interactive bash inside the dev container (live source mount)
  exec CMD   Run a command in the dev container, e.g. exec npm run test:local -- tests/
  lab CMD    Run REA offline against /samples (writes to /out), no network
  web CMD    Run REA with network access (websites, runtime analysis)
  host CMD   Run the host-built REA CLI with the project-local Node toolchain
  host-npm   Run npm/npx on the host with the project-local toolchain
  status     Show containers, image and Docker disk usage
  down       Stop and remove the sandbox containers
  reset      Remove containers AND named volumes (node_modules cache)

Directories
  sandbox/workspace/samples   read-only target files for the lab
  sandbox/workspace/out       writable results from the lab

Examples
  .\sandbox.ps1 build
  .\sandbox.ps1 shell
  .\sandbox.ps1 exec npm run build:cached
  .\sandbox.ps1 exec npm run test:local -- tests/domain
  .\sandbox.ps1 lab analyze-javascript-application /samples/app.asar --json
  .\sandbox.ps1 host --help
"@ | Write-Host
}

switch ($Command) {
  "help" { Show-Help }

  "setup" {
    & (Join-Path $PSScriptRoot "setup.ps1")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Ensure-Docker
    Write-Host "[sandbox] Building the Docker image..."
    Invoke-Compose build dev
    Write-Host "[sandbox] Ready. Try: .\sandbox.ps1 shell"
  }

  "build" {
    Ensure-Docker
    Invoke-Compose build dev
  }

  "shell" {
    Ensure-Docker
    Invoke-Compose run --rm dev bash
  }

  "exec" {
    Ensure-Docker
    if ($Rest.Count -eq 0) {
      Invoke-Compose run --rm dev bash
    } else {
      Invoke-Compose run --rm dev @Rest
    }
  }

  "lab" {
    Ensure-Docker
    if ($Rest.Count -eq 0) {
      Invoke-Compose run --rm lab rea --help
    } else {
      Invoke-Compose run --rm lab rea @Rest
    }
  }

  "web" {
    Ensure-Docker
    if ($Rest.Count -eq 0) {
      Invoke-Compose run --rm web rea --help
    } else {
      Invoke-Compose run --rm web rea @Rest
    }
  }

  "host" {
    . (Join-Path $PSScriptRoot "env.ps1")
    if ($Rest.Count -eq 0) {
      & node scripts/rea.mjs --help
    } else {
      & node scripts/rea.mjs @Rest
    }
    exit $LASTEXITCODE
  }

  "host-npm" {
    . (Join-Path $PSScriptRoot "env.ps1")
    if ($Rest.Count -eq 0) {
      & npm.cmd --version
    } else {
      & npm.cmd @Rest
    }
    exit $LASTEXITCODE
  }

  "status" {
    Ensure-Docker
    Invoke-Compose ps
    & docker images rea-sandbox --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
    & docker system df
  }

  "down" {
    Ensure-Docker
    Invoke-Compose down --remove-orphans
  }

  "reset" {
    Ensure-Docker
    $answer = Read-Host "This deletes containers and the node_modules cache volume. Type YES to continue"
    if ($answer -eq "YES") {
      Invoke-Compose down --volumes --remove-orphans
      Write-Host "[sandbox] Reset complete."
    } else {
      Write-Host "[sandbox] Cancelled."
    }
  }
}
