# Shared Salesforce package helpers (sourced by create-worktree.sh, select-project.sh).

prompt_sf_package() {
  local choice
  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    if ! choice=$(
      dialog --stdout --title "Salesforce package" \
        --menu "Select package (Cancel to go back):" 16 50 4 \
        Recruitment "Recruitment" \
        BusinessCentral "Business Central" \
        Workforce "Workforce" \
        Maia "Maia" \
        2>/dev/tty
    ); then
      return 1
    fi
    printf '%s\n' "$choice"
    return 0
  fi
  while true; do
    echo "Select Salesforce package:" >&2
    echo "  1) Recruitment" >&2
    echo "  2) BusinessCentral" >&2
    echo "  3) Workforce" >&2
    echo "  4) Maia" >&2
    read -r -p "Choice [1-4]: " choice || true
    case $choice in
      1) echo Recruitment; return 0 ;;
      2) echo BusinessCentral; return 0 ;;
      3) echo Workforce; return 0 ;;
      4) echo Maia; return 0 ;;
      *) echo "Invalid choice; enter 1, 2, 3, or 4." >&2 ;;
    esac
  done
}

# True if the configured main repo is treated as the Salesforce repo (basename contains "Salesforce").
is_salesforce_repo() {
  local base
  base=$(basename "$WS_GIT_REPO_ROOT")
  [[ $base == *Salesforce* ]]
}

# Resolve directory for a package: <git worktree root> + package name, or WS_SF_PROJECTS_ROOT + package.
# Prints absolute path. Returns 1 if directory missing.
sf_resolve_package_dir() {
  local worktree_root=$1
  local pkg=$2
  local dest
  if [[ -n ${WS_SF_PROJECTS_ROOT:-} ]]; then
    dest=$(cd "$WS_SF_PROJECTS_ROOT" && pwd)/$pkg
  else
    dest=$(cd "$worktree_root" && pwd)/$pkg
  fi
  if [[ ! -d $dest ]]; then
    echo "Package directory not found: $dest" >&2
    return 1
  fi
  printf '%s\n' "$dest"
}

# Full path to .ws-sf-package: parent of the package base (worktree, or WS_SF_PROJECTS_ROOT when
# set) + /.ws-sf-package — e.g. worktree .../BUG1234/Salesforce -> .../BUG1234/.ws-sf-package
sf_package_marker_path() {
  local worktree_root=$1
  local base
  if [[ -n ${WS_SF_PROJECTS_ROOT:-} ]]; then
    base=$(cd "$WS_SF_PROJECTS_ROOT" && pwd)
  else
    base=$(cd "$worktree_root" && pwd)
  fi
  printf '%s\n' "$(dirname "$base")/.ws-sf-package"
}

# Package name written by create-worktree.sh (first line of file from sf_package_marker_path).
# Prints the name; returns 1 if file missing or empty.
read_saved_sf_package() {
  local root=$1 f line
  f=$(sf_package_marker_path "$root")
  if [[ ! -f $f ]]; then
    f="$root/.ws-sf-package" # legacy: was stored in the worktree root
  fi
  [[ -f $f ]] || return 1
  line=$(head -n 1 "$f" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ -n $line ]] || return 1
  printf '%s\n' "$line"
}
