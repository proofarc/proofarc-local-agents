# Logs in to ghcr.io with the pull token from .env, then downloads and starts the agents.
# Checks $LASTEXITCODE by hand: Windows PowerShell 5.1 does not stop on a failing docker command.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$line = Get-Content .env | Where-Object { $_ -like 'PROOFARC_PULL_TOKEN=*' } | Select-Object -Last 1
$token = if ($line) { $line.Substring('PROOFARC_PULL_TOKEN='.Length) } else { '' }

if ($token) {
    # ghcr.io checks only the token; the username is a placeholder.
    $token | docker login ghcr.io -u proofarc --password-stdin
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
docker compose pull
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
docker compose up -d
exit $LASTEXITCODE
