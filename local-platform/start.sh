#!/usr/bin/env bash
# Starts ProofArc on this machine. Run it the first time and every time after; it only does what is
# still needed. Steps: check Docker, prepare .env, sign in to the image registry, check ports,
# download, start, wait until the agents are connected, check.
set -euo pipefail
cd "$(dirname "$0")"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

# 1. Docker
command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Desktop (Mac, Windows) or Docker Engine (Linux)."
docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop, wait until it says it is running, then run ./start.sh again."
docker compose version >/dev/null 2>&1 || die "'docker compose' is missing. Update Docker Desktop, or install the Compose plugin on Linux."
command -v curl >/dev/null 2>&1 || die "curl is not installed; it is needed to check the platform once it starts."

mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [ "$mem" -gt 0 ] && [ "$mem" -lt 5800000000 ]; then
  die "Docker has $((mem / 1000000000)) GB of memory; ProofArc needs 6 GB. In Docker Desktop: Settings → Resources → Memory 6 GB or more → Apply & restart. Then run ./start.sh again."
fi

# 2. Settings. Every empty password and key is generated once and kept in .env.
[ -f .env ] || { cp .env.example .env; say "Created .env from .env.example."; }
val() { sed -n "s/^$1=//p" .env | tail -n 1; }
secret() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex "$1"
  else od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; fi
}
fill() {  # fill KEY with VALUE if it is missing or empty in .env
  if ! grep -q "^$1=" .env; then printf '%s=%s\n' "$1" "$2" >> .env
  elif [ -z "$(val "$1")" ]; then sed -i.bak "s|^$1=.*|$1=$2|" .env && rm -f .env.bak
  fi
}
fill PROOFARC_ADMIN_PASSWORD "$(secret 8)"
fill PROOFARC_AGENT_PASSWORD "$(secret 16)"
fill DB_PASSWORD "$(secret 16)"
fill JWT_SECRET "$(secret 32)"
fill ENCRYPTION_KEY "$(secret 16)"   # 32 characters: AES-256

UI_PORT="$(val PROOFARC_UI_PORT)"; UI_PORT="${UI_PORT:-3000}"
API_PORT="$(val PROOFARC_API_PORT)"; API_PORT="${API_PORT:-8080}"
MCP_PORT="$(val PROOFARC_MCP_PORT)"; MCP_PORT="${MCP_PORT:-8090}"

# 3. Registry sign-in. Only when our images for this version are not already on this machine.
version="$(val PROOFARC_VERSION)"; version="${version:-v4.8.46}"
images=(backend ui mcp playwright api-test pa_db_init)
missing=0
for i in "${images[@]}"; do
  docker image inspect "ghcr.io/proofarc/${i}:${version}" >/dev/null 2>&1 || missing=1
done
if [ "$missing" = 1 ]; then
  token="$(val PROOFARC_PULL_TOKEN)"
  [ -n "$token" ] || die "Put the pull token we sent you in local-platform/.env, on the line PROOFARC_PULL_TOKEN=, then run ./start.sh again."
  printf '%s' "$token" | docker login ghcr.io -u proofarc --password-stdin >/dev/null 2>&1 \
    || die "ghcr.io refused the pull token in .env. Check it was copied whole, or ask us for a new one."
fi

# 4. Ports. Skipped for anything of ours already running on them.
running="$(docker compose ps --status running --services 2>/dev/null || true)"
check_port() {  # port, our service that uses it, the .env line to change
  printf '%s\n' "$running" | grep -qx "$2" && return 0
  if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then
    die "Port $1 is already used by another program. Pick a free one in .env ($3=...) and run ./start.sh again."
  fi
}
check_port "$UI_PORT" ui PROOFARC_UI_PORT
check_port "$API_PORT" security-agent PROOFARC_API_PORT
check_port "$MCP_PORT" mcp PROOFARC_MCP_PORT

# 5. Download (only what is not on this machine yet: a release never changes), then start.
docker image inspect postgres:14-alpine >/dev/null 2>&1 || missing=1
if [ "$missing" = 1 ]; then
  say "Downloading ProofArc ${version} (the first time takes a few minutes)..."
  docker compose pull --quiet || die "Download failed. Check the pull token in .env and your internet connection."
fi
say "Starting..."
docker compose up -d --remove-orphans || die "Docker could not start the services. See: docker compose logs"

# 6. Wait for the platform (the first start creates the database); check.sh then waits for the rest.
wait_for_platform() {
  local deadline=$((SECONDS + 900))
  until curl -s -m 5 "http://localhost:${API_PORT}/actuator/health" | grep -q '"UP"'; do
    if [ "$(docker compose ps -a --format '{{.Service}} {{.State}} {{.ExitCode}}' 2>/dev/null | awk '$1=="db-init" && $2=="exited" && $3!="0"')" ]; then
      docker compose logs --tail 30 db-init
      die "Setting up the database failed (above). Send us this output."
    fi
    [ "$SECONDS" -lt "$deadline" ] || die "The platform did not start within 15 minutes. See: docker compose logs security-agent"
    sleep 5
  done
}
say "Waiting for the platform (the first start takes 2 to 5 minutes)..."
wait_for_platform

# The platform remembers each user for up to 10 minutes. If a password in .env changed while it was
# running, restart it (and the agents, which connect to it once) so the new password works now.
logins_now="$(printf '%s:%s' "$(val PROOFARC_ADMIN_PASSWORD)" "$(val PROOFARC_AGENT_PASSWORD)" | cksum | cut -d' ' -f1)"
if printf '%s\n' "$running" | grep -qx security-agent && [ "$logins_now" != "$(cat .logins-applied 2>/dev/null)" ]; then
  say "A password in .env changed: restarting the platform so it takes effect..."
  docker compose restart security-agent >/dev/null || die "Could not restart the platform. See: docker compose logs security-agent"
  wait_for_platform
  docker compose restart playwright-agent api-test-agent >/dev/null || die "Could not restart the agents. See: docker compose logs"
fi
printf '%s\n' "$logins_now" > .logins-applied
# 7. Check, and say how to use it.
echo
say "Waiting for the agents, the web app and the MCP server..."
CHECK_WAIT="${CHECK_WAIT:-300}" ./check.sh || die "ProofArc started, but a check failed (above)."
cat <<EOF

ProofArc is running.
  Web app   http://localhost:${UI_PORT}
  API       http://localhost:${API_PORT}
  MCP       http://localhost:${MCP_PORT}/mcp

  Sign in as   user: admin   password: $(val PROOFARC_ADMIN_PASSWORD)
  (an administrator; the password is kept in local-platform/.env, line PROOFARC_ADMIN_PASSWORD)

To test an app running on this machine, give its address as http://host.docker.internal:<port>,
not http://localhost:<port>. Next steps are in local-platform/README.md.
EOF
