#!/usr/bin/env bash
# List Git worktrees that live under WS_GIT_WORKTREE_PATH and open/select one.
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
source "$SCRIPT_DIR/lib/sf-package.sh"

: "${WS_GIT_REPO_ROOT:?Set WS_GIT_REPO_ROOT in config/env.local.sh}"
: "${WS_GIT_WORKTREE_PATH:?Set WS_GIT_WORKTREE_PATH in config/env.local.sh}"

if ! git -C "$WS_GIT_REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "WS_GIT_REPO_ROOT is not a Git repository: $WS_GIT_REPO_ROOT" >&2
  exit 1
fi

if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
  echo "This script must run in an interactive terminal." >&2
  exit 1
fi

# First path segment under WS_GIT_WORKTREE_PATH (create-worktree folder = BUG1234, etc.).
worktree_path_prefix() {
  local rp wt_base rel
  wt_base=$(cd "$WS_GIT_WORKTREE_PATH" && pwd)
  rp=$(cd "$1" && pwd)
  case "$rp" in
    "$wt_base" | "$wt_base"/)
      basename "$rp"
      ;;
    "$wt_base"/*)
      rel=${rp#"$wt_base"/}
      printf '%s\n' "${rel%%/*}"
      ;;
    *)
      basename "$rp"
      ;;
  esac
}

# create-worktree.sh uses branch BUG1234_Project_Name; show Project_Name, not the path/folder prefix.
worktree_display_label() {
  local rp=$1 br=$2 prefix
  prefix=$(worktree_path_prefix "$rp")
  case $br in
    '' | __detached__)
      printf '%s\n' "$prefix"
      ;;
    *)
      if [[ $br == "${prefix}"_* ]] && [[ $br != "$prefix" ]]; then
        printf '%s\n' "${br#"${prefix}"_}"
      else
        printf '%s\n' "$br"
      fi
      ;;
  esac
}

collect_projects() {
  local wt_base repo line path bname tab combined
  wt_base=$(cd "$WS_GIT_WORKTREE_PATH" && pwd)
  repo=$(cd "$WS_GIT_REPO_ROOT" && pwd)
  paths=()
  branches=()
  path=
  bname=

  flush_worktree_block() {
    [[ -z ${path:-} ]] && return
    local rrp
    if ! rrp=$(cd "$path" 2>/dev/null && pwd); then
      path=
      bname=
      return
    fi
    case "$rrp" in
      "$wt_base" | "$wt_base"/*)
        paths+=("$rrp")
        branches+=("${bname:-}")
        ;;
    esac
    path=
    bname=
  }

  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == worktree\ * ]]; then
      flush_worktree_block
      path=${line#worktree }
    elif [[ $line == branch\ refs/heads/* ]]; then
      bname=${line#branch refs/heads/}
    elif [[ $line == branch\ * ]]; then
      bname=__detached__
    elif [[ $line == detached ]]; then
      bname=__detached__
    fi
  done < <(git -C "$repo" worktree list --porcelain)
  flush_worktree_block

  if ((${#paths[@]} == 0)); then
    return 1
  fi

  tab=$'\t'
  combined=()
  for i in "${!paths[@]}"; do
    combined+=("${paths[$i]}$tab${branches[$i]}")
  done
  paths_sorted=()
  branches_sorted=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    paths_sorted+=("${line%%"$tab"*}")
    branches_sorted+=("${line#*"$tab"}")
  done < <(printf '%s\n' "${combined[@]}" | sort -u -t "$tab" -k1,1)
}

pick_dialog() {
  local choice menu=() i p label br dcl=()
  for i in "${!paths_sorted[@]}"; do
    p=${paths_sorted[$i]}
    br=${branches_sorted[$i]}
    label=$(worktree_display_label "$p" "$br")
    menu+=("$i" "$label")
  done
  # Launched from ws-ui: avoid full-screen --clear so flow stays curses/dialog-consistent.
  if [[ ${WS_UI_MODE:-} != dialog ]]; then
    dcl=(--clear)
  fi
  if ! choice=$(
    dialog --stdout "${dcl[@]}" \
      --title "WorkspaceScripts" \
      --backtitle "Projects under $WS_GIT_WORKTREE_PATH" \
      --menu "Select a project (Cancel to return to the main menu):" 22 100 16 \
      "${menu[@]}" \
      2>/dev/tty
  ); then
    return 1
  fi
  SELECTED_PATH=${paths_sorted[$choice]}
}

pick_select() {
  local i=1 opt p label br idx
  echo "Projects under $WS_GIT_WORKTREE_PATH:" >&2
  for idx in "${!paths_sorted[@]}"; do
    p=${paths_sorted[$idx]}
    br=${branches_sorted[$idx]}
    label=$(worktree_display_label "$p" "$br")
    printf '  %2d) %s\n' "$i" "$label" >&2
    ((i++))
  done
  read -r -p "Enter number (1-${#paths_sorted[@]}): " opt </dev/tty || return 1
  if ! [[ $opt =~ ^[0-9]+$ ]] || ((opt < 1 || opt > ${#paths_sorted[@]})); then
    echo "Invalid choice." >&2
    return 1
  fi
  SELECTED_PATH=${paths_sorted[$((opt - 1))]}
}

main() {
  if ! collect_projects; then
    if command -v dialog >/dev/null 2>&1; then
      dialog --msgbox "No Git worktrees found under ${WS_GIT_WORKTREE_PATH}. Create one with scripts/create-worktree.sh (or the menu: worktree)." 10 75 2>/dev/tty
    else
      echo "No Git worktrees found under: $WS_GIT_WORKTREE_PATH" >&2
    fi
    exit 1
  fi

  SELECTED_PATH=
  if command -v dialog >/dev/null 2>&1; then
    pick_dialog || exit 0
  else
    pick_select || exit 1
  fi

  local FINAL_PATH=$SELECTED_PATH pkg
  if is_salesforce_repo; then
    echo "Selected worktree: $SELECTED_PATH" >&2
    if pkg=$(read_saved_sf_package "$SELECTED_PATH"); then
      if ! FINAL_PATH=$(sf_resolve_package_dir "$SELECTED_PATH" "$pkg"); then
        exit 1
      fi
      echo "Opening saved package (from worktree creation): $pkg → $FINAL_PATH" >&2
    else
      echo "No .ws-sf-package next to the project folder — opening worktree root (create with scripts/create-worktree.sh to record a package)." >&2
      FINAL_PATH=$(cd "$SELECTED_PATH" && pwd)
    fi
  else
    echo "Selected: $SELECTED_PATH" >&2
  fi

  # Same as create-worktree: sourced = cd; TTY = cd + subshell. From ws-ui = dialog summary only.
  if [[ $0 != "${BASH_SOURCE[0]}" ]]; then
    clear
    cd "$FINAL_PATH" || exit 1
    echo "Current directory is now: $PWD" >&2
  elif [[ ${WS_UI_MODE:-} == dialog ]]; then
    if [[ ${WS_FROM_WS_UI:-} == 1 ]]; then
      mkdir -p "$TOOLKIT_ROOT/config" 2>/dev/null || true
      if ! printf '%s\n' "$FINAL_PATH" >"$TOOLKIT_ROOT/config/.ws-ui-cd-next" 2>/dev/null; then
        dialog --title "select-project.sh" --msgbox "Could not write target path. Check permissions on $TOOLKIT_ROOT/config" 10 70 2>/dev/tty
        exit 1
      fi
      # Parent ws-ui reads this path, exits the menu, cd here, and execs an interactive shell.
      exit 10
    fi
    local pmsg gq
    gq=$(printf '%q' "$FINAL_PATH")
    pmsg="Open this directory in a shell:

$FINAL_PATH

Example:
  cd $gq"
    dialog --title "select-project.sh" --msgbox "$pmsg" 20 80 2>/dev/tty
  elif [[ -t 0 && -t 1 ]]; then
    clear
    cd "$FINAL_PATH" || exit 1
    echo "Project directory — shell is now in: $PWD" >&2
    export WS_SCRIPT_TTY=1
    echo "Interactive shell started by WorkspaceScripts (WS_SCRIPT_TTY=1). Type exit when finished." >&2
    profile_file="${HOME}/.profile"
    [[ -r $profile_file ]] || profile_file=/dev/null
    exec bash --init-file "$profile_file" -i
  else
    echo "Non-interactive session — cd manually:" >&2
    printf '  cd %q\n' "$FINAL_PATH" >&2
  fi
}

main "$@"
