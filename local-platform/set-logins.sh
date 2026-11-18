#!/bin/sh
# Runs inside db-init after the tables exist. Sets the two logins from .env:
#   admin          you: an administrator, for the web app and for MCP
#   agent-service  the two test agents
# clears "must change password at first sign-in", which would otherwise block both, and switches
# every other user off.
# Runs on every start, so the passwords in .env are always the ones that work.
set -eu
psql -v ON_ERROR_STOP=1 -v admin_pw="$PROOFARC_ADMIN_PASSWORD" -v agent_pw="$PROOFARC_AGENT_PASSWORD" <<'SQL'
UPDATE users SET password = crypt(:'admin_pw', gen_salt('bf', 10)), force_password_change = false,
       enabled = true, account_locked = false WHERE username = 'admin';
UPDATE users SET password = crypt(:'agent_pw', gen_salt('bf', 10)), force_password_change = false,
       enabled = true, account_locked = false WHERE username = 'agent-service';
-- The starting data also has demo users with well-known passwords. Only the two above may sign in.
UPDATE users SET enabled = false WHERE username NOT IN ('admin', 'agent-service') AND enabled;
DO $$ BEGIN
  IF (SELECT count(*) FROM users WHERE username IN ('admin', 'agent-service')) <> 2 THEN
    RAISE EXCEPTION 'expected users admin and agent-service after db-init, found %',
      (SELECT string_agg(username, ', ') FROM users WHERE username IN ('admin', 'agent-service'));
  END IF;
END $$;
SQL
echo "Logins set: admin, agent-service; every other user switched off"
