#!/usr/bin/env bash
# Logs in to ghcr.io with the pull token from .env, then downloads and starts the agents.
set -euo pipefail
cd "$(dirname "$0")"

# Read as text: sourcing .env would run whatever it contains.
token="$(sed -n 's/^PROOFARC_PULL_TOKEN=//p' .env | tail -n 1)"

if [ -n "$token" ]; then
  # ghcr.io checks only the token; the username is a placeholder.
  printf '%s' "$token" | docker login ghcr.io -u proofarc --password-stdin
fi
docker compose pull
docker compose up -d
