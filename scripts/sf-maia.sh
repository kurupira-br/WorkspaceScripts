#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLKIT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
ENV_FILE="${WS_TOOLKIT_ENV_FILE:-$TOOLKIT_ROOT/config/env.local.sh}"
if [[ ! -f $ENV_FILE ]]; then
  echo "Missing $ENV_FILE — run scripts/setup.sh first." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/sf-goto-package.sh"
_sf_goto_package Maia
