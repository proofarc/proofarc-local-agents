#!/usr/bin/env bash
# Checks that the local platform is up and able to run tests. Prints one line per check and exits 1
# if any check fails. ./start.sh runs it at the end; run it yourself any time.
set -uo pipefail
cd "$(dirname "$0")"

val() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -n 1; }
API_PORT="$(val PROOFARC_API_PORT)"; API_PORT="${API_PORT:-8080}"
UI_PORT="$(val PROOFARC_UI_PORT)"; UI_PORT="${UI_PORT:-3000}"
MCP_PORT="$(val PROOFARC_MCP_PORT)"; MCP_PORT="${MCP_PORT:-8090}"
ADMIN_PW="$(val PROOFARC_ADMIN_PASSWORD)"

# Each check is tried again until it passes or WAIT seconds have gone by (default 60), so a service
# that is still starting is waited for rather than reported as broken.
WAIT="${CHECK_WAIT:-60}"
failed=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; failed=1; }
retry() {  # retry <test function>: true once the test passes, false when WAIT runs out
  local end=$((SECONDS + WAIT))
  until "$1"; do
    [ "$SECONDS" -lt "$end" ] || return 1
    sleep 3
  done
}

platform_up() { curl -s -m 10 "http://localhost:${API_PORT}/actuator/health" | grep -q '"UP"'; }
admin_signs_in() {
  [ "$(printf '{"username":"admin","password":"%s"}' "$ADMIN_PW" \
    | curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST "http://localhost:${API_PORT}/api/auth/login" \
        -H 'Content-Type: application/json' -d @-)" = "200" ]
}
admin_is_administrator() {
  [ "$(docker compose exec -T postgres psql -U secadmin -d security_agent -At -c \
    "select count(*) from user_roles r join users u on u.id = r.user_id where u.username = 'admin' and u.enabled and r.role = 'ADMIN'" 2>/dev/null)" = "1" ]
}
# Only admin (you) and agent-service (the agents) can sign in; the starter users are switched off.
only_two_logins() {
  [ "$(docker compose exec -T postgres psql -U secadmin -d security_agent -At -c \
    "select string_agg(username, ',' order by username) from users where enabled" 2>/dev/null)" = "admin,agent-service" ]
}
# An agent that is up has registered and sent a heartbeat in the last two minutes.
agent_connected() {
  docker compose exec -T postgres psql -U secadmin -d security_agent -At -c \
    "select agent_id from agent_registration where status <> 'OFFLINE' and last_seen_at > now() - interval '2 minutes'" 2>/dev/null \
    | grep -q "^${AGENT}-agent-local"
}
web_app_opens() { [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:${UI_PORT}/")" = "200" ]; }
# Any HTTP answer means the MCP server is listening; it refuses a bare GET without a session.
mcp_listens() { [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://localhost:${MCP_PORT}/mcp")" != "000" ]; }

echo "Checking ProofArc on this machine"

if retry platform_up; then pass "platform answers on http://localhost:${API_PORT}"
else fail "platform does not answer on http://localhost:${API_PORT} — see: docker compose logs security-agent"; fi

if retry admin_signs_in; then pass "admin signs in with the password in .env"
else fail "admin cannot sign in with the password in .env (PROOFARC_ADMIN_PASSWORD) — see: docker compose logs db-init"; fi

if retry admin_is_administrator; then pass "admin is an administrator"
else fail "admin is not an administrator — see: docker compose logs db-init"; fi

if retry only_two_logins; then pass "only admin and agent-service can sign in"
else fail "other users can still sign in — see: docker compose logs db-init"; fi

for AGENT in playwright api-test; do
  if retry agent_connected; then pass "${AGENT} agent is connected"
  else fail "${AGENT} agent is not connected — see: docker compose logs ${AGENT}-agent"; fi
done

if retry web_app_opens; then pass "web app opens on http://localhost:${UI_PORT}"
else fail "web app does not open on http://localhost:${UI_PORT} — see: docker compose logs ui"; fi

if retry mcp_listens; then pass "MCP server listens on http://localhost:${MCP_PORT}/mcp"
else fail "MCP server does not answer on http://localhost:${MCP_PORT}/mcp — see: docker compose logs mcp"; fi

if [ "$failed" = 0 ]; then echo "All checks passed."; else echo "Some checks failed."; fi
exit "$failed"
