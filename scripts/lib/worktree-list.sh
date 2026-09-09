# Shared git-worktree-porcelain parsing (sourced by select-project.sh, remove-project-worktree.sh).

# Prints "path<TAB>branch" (one line per worktree found under $wt_base), resolved to
# realpaths. branch is empty or "__detached__" for detached HEADs. Order follows
# `git worktree list --porcelain`; caller is responsible for sort -u / dedup.
# Args: $1 repo_root  $2 wt_base  $3 exclude_repo_root (0/1, default 0)
wt_list_raw() {
  local repo_root=$1 wt_base=$2 exclude_repo_root=${3:-0}
  local line path bname rp

  _wt_list_raw_flush() {
    [[ -z ${path:-} ]] && return
    if ! rp=$(cd "$path" 2>/dev/null && pwd); then
      path=
      bname=
      return
    fi
    case "$rp" in
      "$wt_base" | "$wt_base"/*) ;;
      *)
        path=
        bname=
        return
        ;;
    esac
    if [[ $exclude_repo_root == 1 && $rp == "$repo_root" ]]; then
      path=
      bname=
      return
    fi
    printf '%s\t%s\n' "$rp" "${bname:-}"
    path=
    bname=
  }

  path=
  bname=
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == worktree\ * ]]; then
      _wt_list_raw_flush
      path=${line#worktree }
    elif [[ $line == branch\ refs/heads/* ]]; then
      bname=${line#branch refs/heads/}
    elif [[ $line == branch\ * ]]; then
      bname=__detached__
    elif [[ $line == detached ]]; then
      bname=__detached__
    fi
  done < <(git -C "$repo_root" worktree list --porcelain)
  _wt_list_raw_flush
}
