#!/usr/bin/env bash
# Logs in to ghcr.io, fetches JWT token if needed, then starts agents.
set -euo pipefail
cd "$(dirname "$0")"

# Read credentials from .env without sourcing
pull_token="$(sed -n 's/^PROOFARC_PULL_TOKEN=//p' .env | tail -n 1)"
agent_token="$(sed -n 's/^PROOFARC_AGENT_TOKEN=//p' .env | tail -n 1)"
agent_user="$(sed -n 's/^PROOFARC_AGENT_USERNAME=//p' .env | tail -n 1)"
agent_pass="$(sed -n 's/^PROOFARC_AGENT_PASSWORD=//p' .env | tail -n 1)"
proofarc_url="$(sed -n 's/^PROOFARC_URL=//p' .env | tail -n 1)"

# Login to ghcr.io if pull token is set
if [ -n "$pull_token" ]; then
  printf '%s' "$pull_token" | docker login ghcr.io -u proofarc --password-stdin
fi

# Fetch JWT token if not provided but credentials are available
if [ -z "$agent_token" ] && [ -n "$agent_user" ] && [ -n "$agent_pass" ]; then
  if [ -z "$proofarc_url" ]; then
    echo "Error: PROOFARC_URL not set in .env"
    exit 1
  fi
  echo "Fetching JWT token for agent..."
  agent_token=$(printf '{"username":"%s","password":"%s"}' "$agent_user" "$agent_pass" \
    | curl -s -X POST "$proofarc_url/api/auth/login" \
      -H 'Content-Type: application/json' \
      -H 'User-Agent: proofarc-agents/1.0' -d @- \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))')

  if [ -z "$agent_token" ] || [ "$agent_token" == "null" ]; then
    echo "Error: Failed to fetch JWT token. Check credentials and PROOFARC_URL."
    exit 1
  fi
  echo "Token fetched successfully"
  # Inject token into docker compose
  export PROOFARC_AGENT_TOKEN="$agent_token"
fi

docker compose pull
docker compose up -d
