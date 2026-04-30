#!/usr/bin/env bash
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$ROOT/scripts/ws-ui.sh" "$@"
