#!/usr/bin/env bash
#
# Cross-platform entry point for the canonical PowerShell implementation. Keeping
# one implementation prevents the Bash and PowerShell app/permission update logic
# from drifting.
#
# Usage:
#   azd up
#   ./scripts/register-portal-app.sh [app-display-name]
#   azd up
#
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [app-display-name]" >&2
  exit 2
fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: PowerShell 7 (pwsh) is required. See https://learn.microsoft.com/powershell/scripting/install/installing-powershell." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARGS=(-NoProfile -File "${SCRIPT_DIR}/register-portal-app.ps1")
if [ "$#" -eq 1 ]; then
  ARGS+=(-AppName "$1")
fi

exec pwsh "${ARGS[@]}"
