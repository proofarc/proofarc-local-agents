#!/usr/bin/env bash
# Tests for start.sh, run against the fake docker in tests/bin.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
failures=0
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Runs start.sh from / in a scratch copy of the repo; sets $work, $status and $calls.
run_start() {
  local env_file="$1" fail_on="${2:-}"
  work="$(mktemp -d "$scratch/XXXX")"
  cp "$repo/start.sh" "$work/"
  printf '%s\n' "$env_file" > "$work/.env"
  (cd / && PATH="$here/bin:$PATH" FAKE_DOCKER_LOG="$work/calls.log" FAKE_DOCKER_FAIL="$fail_on" \
    bash "$work/start.sh") > "$work/out" 2>&1
  status=$?
  calls="$(cat "$work/calls.log" 2>/dev/null)"
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    printf 'FAIL - %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

run_start 'PROOFARC_PULL_TOKEN=ghp_test=123'
assert_eq "token set: logs in, pulls, starts" \
  "$work | login ghcr.io -u proofarc --password-stdin
$work | compose pull
$work | compose up -d" "$calls"
assert_eq "token set: token goes in on stdin" "ghp_test=123" "$(cat "$work/calls.log.stdin")"
assert_eq "token set: exits 0" 0 "$status"

run_start 'PROOFARC_PULL_TOKEN='
assert_eq "token empty: skips login" \
  "$work | compose pull
$work | compose up -d" "$calls"
assert_eq "token empty: exits 0" 0 "$status"

run_start 'PROOFARC_URL=https://example.test'
assert_eq "token key missing: skips login" \
  "$work | compose pull
$work | compose up -d" "$calls"

run_start 'PROOFARC_PULL_TOKEN=bad' 'login ghcr.io -u proofarc --password-stdin'
assert_eq "login fails: stops before pull" \
  "$work | login ghcr.io -u proofarc --password-stdin" "$calls"
assert_eq "login fails: exits non-zero" 1 "$([ "$status" -ne 0 ] && echo 1 || echo 0)"

run_start 'PROOFARC_PULL_TOKEN=' 'compose pull'
assert_eq "pull fails: does not start" "$work | compose pull" "$calls"
assert_eq "pull fails: exits non-zero" 1 "$([ "$status" -ne 0 ] && echo 1 || echo 0)"

run_start 'PROOFARC_URL=$(touch executed)'
assert_eq ".env is read, not executed" "no" "$([ -e "$work/executed" ] && echo yes || echo no)"

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
