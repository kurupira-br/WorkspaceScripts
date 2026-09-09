#!/usr/bin/env bash
# Terminal UI: worktree & setup; children get WS_UI_MODE=dialog.
# select-project: chooses a worktree / package, exits the UI, and starts a shell in that directory (see exit 10 path).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLKIT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SETUP_SH="$TOOLKIT_ROOT/scripts/setup.sh"
CREATE_WT_SH="$TOOLKIT_ROOT/scripts/create-worktree.sh"
SELECT_SH="$TOOLKIT_ROOT/scripts/select-project.sh"
REMOVE_SH="$TOOLKIT_ROOT/scripts/remove-project-worktree.sh"

if [[ ! -f $SETUP_SH ]] || [[ ! -f $CREATE_WT_SH ]] || [[ ! -f $SELECT_SH ]] || [[ ! -f $REMOVE_SH ]]; then
  echo "Missing scripts under $TOOLKIT_ROOT/scripts" >&2
  exit 1
fi

if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
  echo "This UI must run in an interactive terminal (not a pipe)." >&2
  exit 1
fi

require_dialog() {
  if ! command -v dialog >/dev/null 2>&1; then
    echo "This UI requires the dialog(1) program." >&2
    echo "Install: sudo apt install dialog    (Debian / Ubuntu / WSL)" >&2
    exit 1
  fi
}

run_subscript() {
  local path=$1
  local name st cdfile p
  name=$(basename "$path")
  # Unique handoff file per invocation so concurrent `ws` sessions don't race on the same path.
  cdfile=$(mktemp "$TOOLKIT_ROOT/config/.ws-ui-cd-next.XXXXXX" 2>/dev/null) || cdfile="$TOOLKIT_ROOT/config/.ws-ui-cd-next"
  rm -f "$cdfile" 2>/dev/null || true # mktemp pre-creates it empty; child (re)writes it only on exit 10
  WS_FROM_WS_UI=1 WS_UI_MODE=dialog WS_UI_CD_NEXT_FILE="$cdfile" bash "$path"
  st=$?
  # select-project & create-worktree: exit 10 = cd to project path in $cdfile, then login shell
  if ((st == 10)) && { [[ $name == select-project.sh ]] || [[ $name == create-worktree.sh ]]; }; then
    p=$(tr -d '\r' <"$cdfile" 2>/dev/null | head -n 1) || p=
    rm -f "$cdfile" 2>/dev/null || true
    if [[ -n $p && -d $p ]]; then
      clear
      cd "$p" || {
        dialog --title "$name" --msgbox "Could not change directory to:\n$p" 10 64 2>/dev/tty
        return
      }
      profile_file="${HOME}/.profile"
      [[ -r $profile_file ]] || profile_file=/dev/null
      export WS_SCRIPT_TTY=1
      exec bash --init-file "$profile_file" -i
    else
      dialog --title "$name" --msgbox "Missing or invalid project path after selection." 9 64 2>/dev/tty
    fi
    return
  fi
  rm -f "$cdfile" 2>/dev/null || true
  if ((st != 0)); then
    dialog --title "$name" --msgbox "Error (exit $st). Press OK to return to the menu." 10 60 2>/dev/tty
  fi
}

menu_main() {
  local choice
  while true; do
    if ! choice=$(
      dialog --stdout --clear \
        --title "WorkspaceScripts" \
        --backtitle "Git & worktrees" \
        --menu "Select an action (Cancel or ESC to exit):" 22 78 12 \
        setup "configure repo & worktree paths" \
        worktree "new branch & worktree folder" \
        select "list & pick a project worktree" \
        remove "remove worktree & branch" \
        exit "Exit" \
        2>/dev/tty
    ); then
      clear
      return 0
    fi
    case $choice in
      setup) run_subscript "$SETUP_SH" ;;
      worktree) run_subscript "$CREATE_WT_SH" ;;
      select) run_subscript "$SELECT_SH" ;;
      remove) run_subscript "$REMOVE_SH" ;;
      exit) clear; return 0 ;;
    esac
  done
}

main() {
  require_dialog
  menu_main
}

main "$@"
