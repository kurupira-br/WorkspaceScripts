#!/usr/bin/env bash
# Installs (or uninstalls) a `ws` command on your PATH that runs this toolkit's ./ws
# launcher from anywhere, via a symlink — no copy, so toolkit updates apply immediately.
#
# Usage:
#   scripts/install.sh                 # symlink ~/.local/bin/ws -> <repo>/ws
#   scripts/install.sh --bin-dir DIR   # use a different target directory
#   scripts/install.sh --name NAME     # install under a different command name
#   scripts/install.sh --force         # overwrite an existing non-symlink file/dir
#   scripts/install.sh --uninstall     # remove the installed symlink (same --bin-dir/--name)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLKIT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
LAUNCHER="$TOOLKIT_ROOT/ws"

BIN_DIR="${HOME}/.local/bin"
CMD_NAME="ws"
FORCE=0
UNINSTALL=0

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --bin-dir)
      BIN_DIR=$2
      shift 2
      ;;
    --bin-dir=*)
      BIN_DIR=${1#--bin-dir=}
      shift
      ;;
    --name)
      CMD_NAME=$2
      shift 2
      ;;
    --name=*)
      CMD_NAME=${1#--name=}
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -x $LAUNCHER ]]; then
  echo "Missing or non-executable launcher: $LAUNCHER" >&2
  exit 1
fi

TARGET="$BIN_DIR/$CMD_NAME"

check_path_hint() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      echo "Note: $BIN_DIR is not on your PATH." >&2
      echo "Add this to ~/.bashrc / ~/.profile:" >&2
      echo "  export PATH=\"$BIN_DIR:\$PATH\"" >&2
      ;;
  esac
}

if ((UNINSTALL)); then
  if [[ -L $TARGET ]]; then
    link_dest=$(readlink -f "$TARGET" 2>/dev/null || true)
    if [[ $link_dest != "$LAUNCHER" ]]; then
      echo "Refusing to remove $TARGET — it does not point at $LAUNCHER (points at: ${link_dest:-?})." >&2
      exit 1
    fi
    rm -f "$TARGET"
    echo "Removed $TARGET"
  elif [[ -e $TARGET ]]; then
    echo "$TARGET exists but is not a symlink — leaving it alone. Remove it manually if needed." >&2
    exit 1
  else
    echo "Nothing to uninstall at $TARGET"
  fi
  exit 0
fi

mkdir -p "$BIN_DIR"

if [[ -e $TARGET || -L $TARGET ]]; then
  if [[ -L $TARGET ]]; then
    link_dest=$(readlink -f "$TARGET" 2>/dev/null || true)
    if [[ $link_dest == "$LAUNCHER" ]]; then
      echo "Already installed: $TARGET -> $LAUNCHER"
      check_path_hint
      echo "You can run '$CMD_NAME' from any directory to open the WorkspaceScripts menu."
      exit 0
    fi
  fi
  if ((! FORCE)); then
    echo "Refusing to overwrite existing path: $TARGET (use --force to replace it)." >&2
    exit 1
  fi
  rm -rf "$TARGET"
fi

ln -s "$LAUNCHER" "$TARGET"
echo "Installed: $TARGET -> $LAUNCHER"
check_path_hint
echo "You can now run '$CMD_NAME' from any directory to open the WorkspaceScripts menu."
