# Logs in to ghcr.io, fetches JWT token if needed, then starts agents.
# Checks $LASTEXITCODE by hand: Windows PowerShell 5.1 does not stop on a failing docker command.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Read credentials from .env
$envLines = Get-Content .env
$pullToken = ($envLines | Where-Object { $_ -like 'PROOFARC_PULL_TOKEN=*' } | Select-Object -Last 1).Substring('PROOFARC_PULL_TOKEN='.Length)
$agentToken = ($envLines | Where-Object { $_ -like 'PROOFARC_AGENT_TOKEN=*' } | Select-Object -Last 1).Substring('PROOFARC_AGENT_TOKEN='.Length)
$agentUser = ($envLines | Where-Object { $_ -like 'PROOFARC_AGENT_USERNAME=*' } | Select-Object -Last 1).Substring('PROOFARC_AGENT_USERNAME='.Length)
$agentPass = ($envLines | Where-Object { $_ -like 'PROOFARC_AGENT_PASSWORD=*' } | Select-Object -Last 1).Substring('PROOFARC_AGENT_PASSWORD='.Length)
$proofarc_url = ($envLines | Where-Object { $_ -like 'PROOFARC_URL=*' } | Select-Object -Last 1).Substring('PROOFARC_URL='.Length)

# Login to ghcr.io if pull token is set
if ($pullToken) {
    $pullToken | docker login ghcr.io -u proofarc --password-stdin
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Fetch JWT token if not provided but credentials are available
if (-not $agentToken -and $agentUser -and $agentPass) {
    if (-not $proofarc_url) {
        Write-Error "Error: PROOFARC_URL not set in .env"
        exit 1
    }
    Write-Host "Fetching JWT token for agent..."
    $body = @{username=$agentUser; password=$agentPass} | ConvertTo-Json
    $response = $body | Invoke-WebRequest -Uri "$proofarc_url/api/auth/login" `
        -Method POST `
        -ContentType 'application/json' `
        -UseBasicParsing

    $agentToken = ($response.Content | ConvertFrom-Json).token

    if (-not $agentToken) {
        Write-Error "Error: Failed to fetch JWT token. Check credentials and PROOFARC_URL."
        exit 1
    }
    Write-Host "Token fetched successfully"
    $env:PROOFARC_AGENT_TOKEN = $agentToken
}

docker compose pull
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
docker compose up -d
exit $LASTEXITCODE
