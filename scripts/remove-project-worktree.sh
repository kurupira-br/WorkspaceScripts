#!/usr/bin/env bash
# Select a project worktree under WS_GIT_WORKTREE_PATH, remove it, and delete its branch (if any).
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

# Globals used while parsing porcelain
WT_BASE=
REPO_ROOT=
path=
bname=

flush_worktree_block() {
  [[ -z ${path:-} ]] && return
  local rp
  if ! rp=$(cd "$path" 2>/dev/null && pwd); then
    path=
    bname=
    return
  fi
  case "$rp" in
    "$WT_BASE" | "$WT_BASE"/*) ;;
    *)
      path=
      bname=
      return
      ;;
  esac
  if [[ $rp == "$REPO_ROOT" ]]; then
    path=
    bname=
    return
  fi
  printf '%s\t%s\n' "$rp" "${bname:-}"
  path=
  bname=
}

collect_removable() {
  WT_BASE=$(cd "$WS_GIT_WORKTREE_PATH" && pwd)
  REPO_ROOT=$(cd "$WS_GIT_REPO_ROOT" && pwd)
  path=
  bname=
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == worktree\ * ]]; then
      flush_worktree_block
      path=${line#worktree }
    elif [[ $line == branch\ refs/heads/* ]]; then
      bname=${line#branch refs/heads/}
    elif [[ $line == branch\ * ]]; then
      bname="__detached__"
    elif [[ $line == detached ]]; then
      bname="__detached__"
    fi
  done < <(git -C "$REPO_ROOT" worktree list --porcelain)
  flush_worktree_block
}

load_sorted_arrays() {
  paths_sorted=()
  branches_sorted=()
  local line tab p b
  tab=$'\t'
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    p=${line%%"$tab"*}
    b=${line#*"$tab"}
    paths_sorted+=("$p")
    branches_sorted+=("$b")
  done < <(collect_removable | sort -u)
}

branch_label() {
  local b=$1
  case $b in
    '' | __detached__) echo "(detached — branch will not be deleted)" ;;
    *) echo "$b" ;;
  esac
}

pick_dialog() {
  local choice menu=() i p bn br lbl dcl=()
  for i in "${!paths_sorted[@]}"; do
    p=${paths_sorted[$i]}
    br=${branches_sorted[$i]}
    bn=$(basename "$p")
    lbl=$(branch_label "$br")
    menu+=("$i" "$bn — $lbl")
  done
  if [[ ${WS_UI_MODE:-} != dialog ]]; then
    dcl=(--clear)
  fi
  if ! choice=$(
    dialog --stdout "${dcl[@]}" \
      --title "WorkspaceScripts" \
      --backtitle "Remove project worktree under $WS_GIT_WORKTREE_PATH" \
      --menu "Select a worktree to remove (Cancel to return to the main menu):" 22 100 16 \
      "${menu[@]}" \
      2>/dev/tty
  ); then
    return 1
  fi
  SELECTED_PATH=${paths_sorted[$choice]}
  SELECTED_BRANCH=${branches_sorted[$choice]}
}

pick_select() {
  local opt p br idx
  echo "Worktrees under $WS_GIT_WORKTREE_PATH (primary repo excluded):" >&2
  for idx in "${!paths_sorted[@]}"; do
    p=${paths_sorted[$idx]}
    br=$(branch_label "${branches_sorted[$idx]}")
    printf '  %2d) %s  [%s]\n' "$((idx + 1))" "$p" "$br" >&2
  done
  read -r -p "Enter number (1-${#paths_sorted[@]}): " opt </dev/tty || return 1
  if ! [[ $opt =~ ^[0-9]+$ ]] || ((opt < 1 || opt > ${#paths_sorted[@]})); then
    echo "Invalid choice." >&2
    return 1
  fi
  SELECTED_PATH=${paths_sorted[$((opt - 1))]}
  SELECTED_BRANCH=${branches_sorted[$((opt - 1))]}
}

confirm_remove() {
  local wt=$1 b=$2 msg
  wt=${wt//\\/\\\\}
  if [[ -z $b || $b == __detached__ ]]; then
    msg=$(printf 'Remove this worktree only (no branch to delete)?\n\n%s' "$wt")
  else
    msg=$(printf 'Remove worktree and delete local branch?\n\nPath: %s\nBranch: %s' "$wt" "$b")
  fi
  dialog --title "Confirm removal" --yesno "$msg" 16 80 2>/dev/tty
}

confirm_remove_tty() {
  local p=$1 b=$2 yn
  echo "Path: $p" >&2
  echo "Branch: $(branch_label "$b")" >&2
  read -r -p "Type YES to remove: " yn </dev/tty || return 1
  [[ $yn == YES ]]
}

# Plain sequential removal (no dialog monitor) — used when dialog is unavailable.
remove_worktree_and_branch() {
  local wt_path=$1 branch=$2
  echo "Removing worktree: $wt_path" >&2
  if ! git -C "$REPO_ROOT" worktree remove "$wt_path" 2>&1; then
    echo "Retrying with --force (uncommitted changes or locked files)..." >&2
    git -C "$REPO_ROOT" worktree remove --force "$wt_path"
  fi

  if [[ -n $branch && $branch != __detached__ ]]; then
    echo "Deleting branch: $branch" >&2
    if ! git -C "$REPO_ROOT" branch -d "$branch" 2>&1; then
      read -r -p "Branch not merged. Force delete with -D? [y/N]: " yn </dev/tty || true
      if [[ ${yn:-} == [yY] ]]; then
        git -C "$REPO_ROOT" branch -D "$branch"
      else
        echo "Branch '$branch' left in repository." >&2
      fi
    fi
  fi
}

# Stream git output through dialog --progressbox, then optional force-delete prompt + second progress view.
remove_with_monitor_ui() {
  local wt_path=$1 branch=$2 wt_force_st
  (
    set +e
    set +o pipefail
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Worktree removal — live log"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo ">>> git worktree remove"
    echo "    $wt_path"
    echo ""
    if git -C "$REPO_ROOT" worktree remove "$wt_path" 2>&1; then
      echo ""
      echo ">>> OK — worktree removed."
    else
      echo ""
      echo ">>> Retrying: git worktree remove --force"
      echo ""
      git -C "$REPO_ROOT" worktree remove --force "$wt_path" 2>&1
      wt_force_st=$?
      echo ""
      echo ">>> git worktree remove --force finished (exit: $wt_force_st)"
    fi

    if [[ -n $branch && $branch != __detached__ ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Branch deletion (git branch -d)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo ">>> git branch -d $branch"
      echo ""
      git -C "$REPO_ROOT" branch -d "$branch" 2>&1
      bd=$?
      echo ""
      if [[ $bd -ne 0 ]]; then
        echo ">>> git branch -d failed (often: branch not merged)."
        echo ">>> If the branch still exists, you will get a prompt to run git branch -D next."
      else
        echo ">>> Branch deleted."
      fi
    else
      echo ""
      echo ">>> No branch to delete (detached or unknown)."
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  End of log — press Enter / OK to close this monitor"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ) 2>&1 | dialog --title "Project removal — monitor" --progressbox "Streaming git output…" 32 100 || true

  if [[ -n $branch && $branch != __detached__ ]]; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      if dialog --title "Branch still present" --yesno "Branch '$branch' was not deleted (e.g. not merged). Run git branch -D?" 12 75 2>/dev/tty; then
        (
          set +e
          set +o pipefail
          echo ">>> git branch -D $branch"
          echo ""
          git -C "$REPO_ROOT" branch -D "$branch" 2>&1
          st=$?
          echo ""
          echo ">>> git branch -D finished (exit: $st)"
        ) 2>&1 | dialog --title "Force-delete branch — monitor" --progressbox "git branch -D output…" 18 90 || true
      else
        dialog --msgbox "Left branch '$branch' in the repository." 9 60 2>/dev/tty
      fi
    fi
  fi
}

main() {
  REPO_ROOT=$(cd "$WS_GIT_REPO_ROOT" && pwd)
  load_sorted_arrays
  if ((${#paths_sorted[@]} == 0)); then
    if command -v dialog >/dev/null 2>&1; then
      dialog --msgbox "No removable worktrees under ${WS_GIT_WORKTREE_PATH} (primary repo excluded)." 8 70 2>/dev/tty
    else
      echo "No removable worktrees found." >&2
    fi
    exit 1
  fi

  SELECTED_PATH=
  SELECTED_BRANCH=
  if command -v dialog >/dev/null 2>&1; then
    pick_dialog || exit 0
  else
    pick_select || exit 1
  fi

  if command -v dialog >/dev/null 2>&1; then
    confirm_remove "$SELECTED_PATH" "$SELECTED_BRANCH" || exit 0
  else
    confirm_remove_tty "$SELECTED_PATH" "$SELECTED_BRANCH" || exit 0
  fi

  if command -v dialog >/dev/null 2>&1; then
    remove_with_monitor_ui "$SELECTED_PATH" "$SELECTED_BRANCH"
    dialog --msgbox "Removal steps finished for:\\n$SELECTED_PATH" 11 80 2>/dev/tty
  else
    remove_worktree_and_branch "$SELECTED_PATH" "$SELECTED_BRANCH"
    echo "Done." >&2
  fi
}

main "$@"
