#!/usr/bin/env bash
# Resolve symlinks (e.g. ~/.local/bin/ws -> this file) so ROOT is this repo, not the symlink's dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L $SOURCE ]]; do
  DIR=$(cd "$(dirname "$SOURCE")" && pwd)
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT=$(cd "$(dirname "$SOURCE")" && pwd)
exec bash "$ROOT/scripts/ws-ui.sh" "$@"
