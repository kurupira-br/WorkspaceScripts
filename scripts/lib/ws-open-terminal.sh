# Open a new shell in a new tab of the *current* terminal, cwd = first argument.
# (tmux new-window, Windows Terminal new-tab, gnome-terminal --tab, ….)
# For custom automation or WS_OPEN_TERMINAL_HOOK — not used by select-project (ws-ui only shows a path).
# Returns 0 if a launcher was started (best effort). Returns 1 if nothing worked.
# Optional: WS_OPEN_TERMINAL_HOOK — executable (or .sh) receiving absolute $1; exit 0 = success.
# Optional: WS_WT_WINDOW_ID — Windows Terminal -w (default -1; set 0 if your wt.exe rejects it).

ws_open_terminal_in_dir() {
  local abs=$1
  local q
  local wt_w
  wt_w=${WS_WT_WINDOW_ID:--1}
  abs=$(cd "$abs" 2>/dev/null && pwd) || return 1
  q=$(printf '%q' "$abs")

  if [[ -n ${WS_OPEN_TERMINAL_HOOK:-} && -e $WS_OPEN_TERMINAL_HOOK ]]; then
    if [[ -x $WS_OPEN_TERMINAL_HOOK ]]; then
      "$WS_OPEN_TERMINAL_HOOK" "$abs" && return 0
    else
      bash "$WS_OPEN_TERMINAL_HOOK" "$abs" && return 0
    fi
  fi

  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null 2>&1; then
    if tmux new-window -c "$abs" -n "ws" bash -l; then
      return 0
    fi
  fi

  if command -v wt.exe >/dev/null 2>&1; then
    if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
      wt.exe -w "$wt_w" new-tab wsl -d "$WSL_DISTRO_NAME" -e bash -lc "cd $q && exec bash -l" &
    else
      wt.exe -w "$wt_w" new-tab wsl -e bash -lc "cd $q && exec bash -l" &
    fi
    disown 2>/dev/null || true
    return 0
  fi

  if [[ -n ${DISPLAY:-} ]]; then
    if command -v gnome-terminal >/dev/null 2>&1; then
      gnome-terminal --tab --working-directory="$abs" >/dev/null 2>&1 &
      disown 2>/dev/null || true
      return 0
    fi
    if command -v konsole >/dev/null 2>&1; then
      konsole --new-tab --workdir "$abs" >/dev/null 2>&1 &
      disown 2>/dev/null || true
      return 0
    fi
    if command -v alacritty >/dev/null 2>&1; then
      alacritty --working-directory "$abs" &
      disown 2>/dev/null || true
      return 0
    fi
    if command -v xterm >/dev/null 2>&1; then
      xterm -e bash -lc "cd $q; exec bash -l" &
      disown 2>/dev/null || true
      return 0
    fi
    if command -v x-terminal-emulator >/dev/null 2>&1; then
      x-terminal-emulator -e bash -lc "cd $q; exec bash -l" &
      disown 2>/dev/null || true
      return 0
    fi
  fi

  return 1
}
