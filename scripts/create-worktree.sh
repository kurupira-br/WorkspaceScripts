#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLKIT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# Override for tests: WS_TOOLKIT_ENV_FILE=/path/to/env.sh
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

# Replace non-alphanumeric with _, collapse runs, trim; then Title_Case each segment (e.g. work item -> Work_Item).
# Example suffix: Work_Item_Test -> branch OTHER1234_Work_Item_Test
sanitize_name_to_branch_suffix() {
  local s=$1
  s=$(printf '%s' "$s" | LC_ALL=C sed 's/[^a-zA-Z0-9]/_/g')
  s=$(printf '%s' "$s" | sed 's/__*/_/g')
  s=${s#_}
  s=${s%_}
  if [[ -z $s ]]; then
    printf '%s' ""
    return
  fi
  local -a parts=()
  IFS='_' read -r -a parts <<< "$s"
  local seg low cap out="" first=1
  for seg in "${parts[@]}"; do
    [[ -z $seg ]] && continue
    if [[ $seg =~ ^[0-9]+$ ]]; then
      cap=$seg
    else
      low=${seg,,}
      cap=${low^}
    fi
    if [[ $first -eq 1 ]]; then
      out=$cap
      first=0
    else
      out="${out}_${cap}"
    fi
  done
  printf '%s' "$out"
}

prompt_project_type() {
  local choice
  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    if ! choice=$(
      dialog --stdout --title "New worktree" \
        --menu "Select project type (Cancel to go back to the main menu):" 16 64 3 \
        BUG "BUG" ITEM "ITEM"         OTHER "OTHER" \
        2>/dev/tty
    ); then
      return 1
    fi
    printf '%s\n' "$choice"
    return 0
  fi
  while true; do
    echo "Select project type:" >&2
    echo "  1) BUG" >&2
    echo "  2) ITEM" >&2
    echo "  3) OTHER" >&2
    read -r -p "Choice [1-3]: " choice || true
    case $choice in
      1) echo BUG; return 0 ;;
      2) echo ITEM; return 0 ;;
      3) echo OTHER; return 0 ;;
      *) echo "Invalid choice; enter 1, 2, or 3." >&2 ;;
    esac
  done
}

prompt_number() {
  local n
  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    while true; do
      if ! n=$(dialog --stdout --title "New worktree" --inputbox "Project number (digits only)" 8 50 "" 2>/dev/tty); then
        return 1
      fi
      n=$(printf '%s' "$n" | tr -d ' \t\r\n')
      if [[ $n =~ ^[0-9]+$ ]]; then
        printf '%s' "$n"
        return 0
      fi
      dialog --title "New worktree" --msgbox "Enter digits only (0–9)." 8 50 2>/dev/tty
    done
  fi
  while true; do
    read -r -p "Project number (digits only): " n || true
    if [[ $n =~ ^[0-9]+$ ]]; then
      printf '%s' "$n"
      return 0
    fi
    echo "Enter a non-empty number (0-9 only)." >&2
  done
}

prompt_name() {
  local raw
  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    while true; do
      if ! raw=$(dialog --stdout --title "New worktree" \
        --inputbox "Project name (e.g. Work Item Test -> Work_Item_Test on the branch name)" 10 80 "" 2>/dev/tty); then
        return 1
      fi
      if [[ -z ${raw//[[:space:]]/} ]]; then
        dialog --title "New worktree" --msgbox "Name is required." 7 50 2>/dev/tty
        continue
      fi
      printf '%s' "$raw"
      return 0
    done
  fi
  while true; do
    read -r -p "Project name (e.g. Work Item Test -> Work_Item_Test on branch): " raw || true
    if [[ -z ${raw//[[:space:]]/} ]]; then
      echo "Name is required." >&2
      continue
    fi
    printf '%s' "$raw"
    return 0
  done
}

# Adds the worktree, records .ws-sf-package when needed. No UI; used by main().
create_worktree_and_marker() {
  git -C "$WS_GIT_REPO_ROOT" worktree add -b "$branch" "$dest"
  if [[ -n ${sf_pkg:-} && -d $dest ]]; then
    printf '%s\n' "$sf_pkg" >"$(sf_package_marker_path "$dest")" 2>/dev/null || true
  fi
}

# Watches background pid $1; outputs dialog --gauge "XXX" data until it exits, then 100% + Done.
# Git does not report worktree progress; we advance 0%→90% while work runs, then 100% at the end.
feed_worktree_gauge() {
  local wpid=$1
  local dest_line=$2
  local br_line=$3
  local pkg_line=$4
  local p=0
  printf 'XXX\n%d\n' 0
  printf 'Path: %s\n' "$dest_line"
  printf 'Branch: %s\n' "$br_line"
  [[ -n $pkg_line ]] && printf 'Package: %s\n' "$pkg_line"
  while kill -0 "$wpid" 2>/dev/null; do
    if ((p < 90)); then
      ((p++))
    else
      p=90
    fi
    printf 'XXX\n%d\n' "$p"
    printf 'git worktree add in progress (this may take a while)…\n'
    sleep 0.2
  done
  if ! wait "$wpid"; then
    # Exit status is in rcode on disk; return 0 so the pipeline and set -e do not stop the script
    return 0
  fi
  # A single 100% line often does not get drawn before the pipe hits EOF. Advance 91%→100%
  # the same way as the main loop (XXX updates + short pause) so the user actually sees 100%.
  for step in 91 92 93 94 95 96 97 98 99 100; do
    printf 'XXX\n%s\n' "$step"
    printf 'Finishing worktree…\n'
    sleep 0.04
  done
  # Let dialog/curses refresh before the writer closes stdin (avoids a frozen bar at ~90%).
  sleep 0.15
  return 0
}

main() {
  if ! git -C "$WS_GIT_REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ ${WS_UI_MODE:-} == dialog ]]; then
      dialog --title "create-worktree.sh" --msgbox "WS_GIT_REPO_ROOT is not a Git repository: $WS_GIT_REPO_ROOT" 10 70 2>/dev/tty
    else
      echo "WS_GIT_REPO_ROOT is not a Git repository: $WS_GIT_REPO_ROOT" >&2
    fi
    exit 1
  fi

  if [[ ! -d $WS_GIT_WORKTREE_PATH ]]; then
    mkdir -p "$WS_GIT_WORKTREE_PATH"
  fi

  local ptype pnum raw_name name_suffix prefix slug branch dest worktree_parent repo_base sf_pkg
  ptype=$(prompt_project_type) || {
    dialog --title "create-worktree.sh" --msgbox "Cancelled. OK to return to the main menu." 8 50 2>/dev/tty
    exit 0
  }
  pnum=$(prompt_number) || {
    dialog --title "create-worktree.sh" --msgbox "Cancelled. OK to return to the main menu." 8 50 2>/dev/tty
    exit 0
  }
  raw_name=$(prompt_name) || {
    dialog --title "create-worktree.sh" --msgbox "Cancelled. OK to return to the main menu." 8 50 2>/dev/tty
    exit 0
  }
  name_suffix=$(sanitize_name_to_branch_suffix "$raw_name")
  if [[ -z $name_suffix ]]; then
    if [[ ${WS_UI_MODE:-} == dialog ]]; then
      dialog --title "create-worktree.sh" --msgbox "After sanitizing, the name is empty. Use letters or digits in the name." 10 70 2>/dev/tty
    else
      echo "After sanitizing, the name is empty. Use letters or digits." >&2
    fi
    exit 1
  fi

  worktree_parent=$(cd "$WS_GIT_WORKTREE_PATH" && pwd)
  repo_base=$(basename "$WS_GIT_REPO_ROOT")

  # Path: .../WORKTREE_PATH/OTHER1234  or  .../OTHER1234/Salesforce  (Salesforce repos)
  prefix="${ptype}${pnum}"
  slug=$prefix
  # Branch: OTHER1234_Work_Item_Test
  branch="${prefix}_${name_suffix}"
  sf_pkg=
  if is_salesforce_repo; then
    if ! sf_pkg=$(prompt_sf_package); then
      dialog --title "create-worktree.sh" --msgbox "Cancelled. OK to return to the main menu." 8 50 2>/dev/tty
      exit 0
    fi
    dest="$worktree_parent/$slug/Salesforce"
  else
    dest="$worktree_parent/$slug"
  fi

  if [[ -e $dest ]]; then
    if [[ ${WS_UI_MODE:-} == dialog ]]; then
      dialog --title "create-worktree.sh" --msgbox "Path already exists:

$dest" 12 80 2>/dev/tty
    else
      echo "Path already exists: $dest" >&2
    fi
    exit 1
  fi

  if git -C "$WS_GIT_REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    if [[ ${WS_UI_MODE:-} == dialog ]]; then
      dialog --title "create-worktree.sh" --msgbox "Branch already exists: $branch" 10 70 2>/dev/tty
    else
      echo "Branch already exists: $branch" >&2
    fi
    exit 1
  fi

  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    # 1) Run work + feed in the same process tree so wait(1) in feed_worktree_gauge is valid.
    # 2) Piping to dialog makes glibc full-buffer the writer: the gauge can stay at 0% until
    #    EOF. Run the writer with stdbuf -i0 -o0 so --gauge gets bytes as they are written.
    # 3) After a failed worktree, we exit 0 so ws-ui does not add a second generic error
    #    (the detailed msgbox already explained the failure).
    local rlog rcode g_st elog
    rlog=$(mktemp)
    rcode=$(mktemp)
    # Child bash needs exported functions; create_worktree uses sf_package_marker_path.
    export rlog rcode dest branch
    export sf_pkg="${sf_pkg:-}"
    export -f create_worktree_and_marker feed_worktree_gauge sf_package_marker_path
    if command -v stdbuf >/dev/null 2>&1; then
      # Note: the script block must be single-quoted to the outer shell so it runs in the child
      # with variables expanded there (rlog, rcode, dest,… are environment variables).
      stdbuf -i0 -o0 -e0 -- bash -c '(
        (
          set +e
          create_worktree_and_marker >"$rlog" 2>&1
          d=$?
          echo "$d" >"$rcode"
          exit "$d"
        ) &
        cpid=$!
        feed_worktree_gauge "$cpid" "$dest" "$branch" "${sf_pkg:-}"
      )' | dialog --title "create-worktree.sh" --gauge "New worktree" 10 75 0 2>/dev/tty
    else
      (
        (
          set +e
          create_worktree_and_marker >"$rlog" 2>&1
          d=$?
          echo "$d" >"$rcode"
          exit "$d"
        ) &
        cpid=$!
        feed_worktree_gauge "$cpid" "$dest" "$branch" "${sf_pkg:-}"
      ) | dialog --title "create-worktree.sh" --gauge "New worktree" 10 75 0 2>/dev/tty
    fi
    g_st=$(tr -d ' \t\r' <"$rcode" 2>/dev/null) || g_st=1
    g_st=${g_st:-1}
    if ((g_st != 0)); then
      elog=$(head -c 3000 <"$rlog" 2>/dev/null) || elog="(no output)"
      dialog --title "create-worktree.sh" --msgbox "git worktree add failed (exit $g_st).

$elog" 22 80 2>/dev/tty
      rm -f "$rlog" "$rcode" 2>/dev/null || true
      exit 0
    fi
    rm -f "$rlog" "$rcode" 2>/dev/null || true
  else
    echo "Creating worktree:"
    echo "  Path:   $dest"
    echo "  Branch: $branch"
    if [[ -n $sf_pkg ]]; then
      echo "  Package: $sf_pkg" >&2
    fi
    create_worktree_and_marker
  fi

  # After Salesforce worktree: land in the chosen package dir when it exists (same rules as select-project).
  local goto_path=$dest
  if [[ -n ${sf_pkg:-} ]]; then
    local resolved
    if resolved=$(sf_resolve_package_dir "$dest" "$sf_pkg"); then
      goto_path=$resolved
    else
      echo "Package folder for '$sf_pkg' is not in this worktree yet; opening worktree root." >&2
    fi
  fi

  # Sourced: cd affects the caller's shell. Executed on a TTY: cd then exec an interactive shell
  # (not when run from the ws-ui dialog: parent menu must return).
  if [[ $0 != "${BASH_SOURCE[0]}" ]]; then
    clear
    cd "$goto_path" || exit 1
    echo "Current directory is now: $PWD" >&2
  elif [[ ${WS_UI_MODE:-} == dialog ]]; then
    # After 100% / success: return to the menu, or leave the UI and open a shell in the project
    # folder (package dir when it exists, same as select-project).
    local _next
    if ! _next=$(
      dialog --stdout --title "create-worktree.sh" --clear \
        --menu "Worktree created.

$goto_path

Choose an action (Cancel = main menu)" 20 80 2 \
        menu "Back to main menu" \
        go "Exit — go to the project (package) folder" \
        2>/dev/tty
    ); then
      exit 0
    fi
    case $_next in
      menu) exit 0 ;;
      go)
        if ! printf '%s\n' "$goto_path" >"$TOOLKIT_ROOT/config/.ws-ui-cd-next" 2>/dev/null; then
          dialog --title "create-worktree.sh" --msgbox "Could not write the path. Change directory yourself:

$goto_path" 18 80 2>/dev/tty
          exit 0
        fi
        exit 10
        ;;
      *) exit 0 ;;
    esac
  elif [[ -t 0 && -t 1 ]]; then
    clear
    cd "$goto_path" || exit 1
    echo "Worktree ready — shell is now in: $PWD" >&2
    # Sign this session so ~/.profile or the user can tweak PS1, hooks, etc.
    export WS_SCRIPT_TTY=1
    echo "Interactive shell started by WorkspaceScripts (WS_SCRIPT_TTY=1). Type exit when finished." >&2
    # Interactive bash: use ~/.profile as startup file instead of ~/.bashrc (see bash(1) --init-file).
    profile_file="${HOME}/.profile"
    [[ -r $profile_file ]] || profile_file=/dev/null
    exec bash --init-file "$profile_file" -i
  else
    echo "Non-interactive session — cd manually:" >&2
    printf '  cd %q\n' "$goto_path"
  fi
}

main "$@"
