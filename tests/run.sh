#!/usr/bin/env bash
# Runs all tests: start.sh directly, start.ps1 under Pester in a PowerShell container.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/start.sh.test.sh"

docker run --rm -v "$(dirname "$here"):/repo:ro" mcr.microsoft.com/powershell \
  pwsh -NoProfile -Command \
  'Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser; Invoke-Pester /repo/tests -Output Detailed -CI'
