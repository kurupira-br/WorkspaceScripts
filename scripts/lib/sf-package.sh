# Shared Salesforce package helpers (sourced by create-worktree.sh, select-project.sh).

# Default packages when WS_SF_PACKAGES is not set in config/env.local.sh.
readonly _WS_SF_DEFAULT_PACKAGES=(Recruitment BusinessCentral Workforce Maia)

# Prints one package name per line: WS_SF_PACKAGES (space-separated, from env.local.sh)
# if set, otherwise the built-in default list.
sf_package_list() {
  if [[ -n ${WS_SF_PACKAGES:-} ]]; then
    # shellcheck disable=SC2206 # intentional word-splitting of a space-separated config var
    local -a pkgs=($WS_SF_PACKAGES)
    printf '%s\n' "${pkgs[@]}"
  else
    printf '%s\n' "${_WS_SF_DEFAULT_PACKAGES[@]}"
  fi
}

prompt_sf_package() {
  local choice
  local -a pkgs=()
  local p
  while IFS= read -r p; do
    [[ -n $p ]] && pkgs+=("$p")
  done < <(sf_package_list)

  if ((${#pkgs[@]} == 0)); then
    echo "No Salesforce packages configured (WS_SF_PACKAGES)." >&2
    return 1
  fi

  if [[ ${WS_UI_MODE:-} == dialog ]]; then
    local menu=()
    for p in "${pkgs[@]}"; do
      menu+=("$p" "$p")
    done
    if ! choice=$(
      dialog --stdout --title "Salesforce package" \
        --menu "Select package (Cancel to go back):" $((10 + ${#pkgs[@]})) 50 "${#pkgs[@]}" \
        "${menu[@]}" \
        2>/dev/tty
    ); then
      return 1
    fi
    printf '%s\n' "$choice"
    return 0
  fi
  while true; do
    echo "Select Salesforce package:" >&2
    local i=1
    for p in "${pkgs[@]}"; do
      printf '  %d) %s\n' "$i" "$p" >&2
      ((i++))
    done
    read -r -p "Choice [1-${#pkgs[@]}]: " choice || true
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#pkgs[@]})); then
      printf '%s\n' "${pkgs[$((choice - 1))]}"
      return 0
    fi
    echo "Invalid choice; enter 1-${#pkgs[@]}." >&2
  done
}

# True if the repo should be treated as a Salesforce repo (package prompts/marker files).
# Prefers the explicit WS_SF_MODE override; falls back to a basename("Salesforce") heuristic.
is_salesforce_repo() {
  if [[ -n ${WS_SF_MODE:-} ]]; then
    case ${WS_SF_MODE,,} in
      1 | true | yes | on) return 0 ;;
      0 | false | no | off) return 1 ;;
    esac
  fi
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
