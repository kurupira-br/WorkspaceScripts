# Shared by sf-recruitment.sh, sf-businesscentral.sh, sf-workforce.sh, sf-maia.sh
# Requires: WS_GIT_REPO_ROOT from config/env.local.sh (when not inside a Git work tree).

_sf_goto_package() {
  local pkg=$1
  local top dest

  if top=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -n $top ]]; then
    :
  else
    : "${WS_GIT_REPO_ROOT:?Set WS_GIT_REPO_ROOT in config/env.local.sh (or run inside a clone/worktree).}"
    top=$(cd "$WS_GIT_REPO_ROOT" && pwd)
  fi

  if [[ -n ${WS_SF_PROJECTS_ROOT:-} ]]; then
    dest=$(cd "$WS_SF_PROJECTS_ROOT" && pwd)/$pkg
  else
    dest=$top/$pkg
  fi

  if [[ ! -d $dest ]]; then
    if [[ ${WS_UI_MODE:-} == dialog ]]; then
      dialog --title "Package" --msgbox "Package directory not found: $dest

Create it in the repo or set WS_SF_PROJECTS_ROOT in config/env.local.sh." 14 80 2>/dev/tty
    else
      echo "Package directory not found: $dest" >&2
      echo "Create it in the repo or set WS_SF_PROJECTS_ROOT in config/env.local.sh." >&2
    fi
    exit 1
  fi

  if [[ $0 != "${BASH_SOURCE[0]}" ]]; then
    cd "$dest" || exit 1
    echo "Now in: $PWD" >&2
  elif [[ ${WS_UI_MODE:-} == dialog ]]; then
    local gq
    gq=$(printf '%q' "$dest")
    dialog --title "Package" --msgbox "Package: $pkg

$dest

In a shell:
  cd $gq" 16 80 2>/dev/tty
  elif [[ -t 0 && -t 1 ]]; then
    clear
    cd "$dest" || exit 1
    echo "Now in: $PWD" >&2
  else
    echo "Run from a terminal or source this script. To cd:" >&2
    printf '  cd %q\n' "$dest"
  fi
}
