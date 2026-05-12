#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEFAULT_CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste/images}"

usage() {
  cat >&2 <<'EOF'
usage: ssh-bin-paste-remote <command> [args]

commands:
  version
  ensure-cache [cache-dir]
  panes
  inject <target-pane>
  cleanup [cache-dir] [max-age-seconds]
EOF
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

ensure_cache() {
  local dir
  dir="$(expand_path "${1:-$DEFAULT_CACHE_DIR}")"
  mkdir -p "$dir"
  test -d "$dir"
  test -w "$dir"
  printf '%s\n' "$dir"
}

list_panes() {
  tmux list-panes -a -F '#{session_name}	#{window_index}.#{pane_index}	#{pane_id}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}	#{pane_title}' 2>/dev/null || true
}

inject() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    printf 'missing target pane\n' >&2
    return 2
  fi

  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  tmux load-buffer -b ssh-bin-paste "$tmp"
  rm -f "$tmp"
  tmux paste-buffer -p -d -b ssh-bin-paste -t "$target"
}

cleanup() {
  local dir max_age
  dir="$(expand_path "${1:-$DEFAULT_CACHE_DIR}")"
  max_age="${2:-86400}"
  mkdir -p "$dir"
  find "$dir" -type f -name 'ssh-bin-paste-*' -mmin "+$((max_age / 60))" -delete 2>/dev/null || true
}

case "${1:-}" in
  version)
    printf '%s\n' "$VERSION"
    ;;
  ensure-cache)
    shift
    ensure_cache "${1:-}"
    ;;
  panes)
    list_panes
    ;;
  inject)
    shift
    inject "${1:-}"
    ;;
  cleanup)
    shift
    cleanup "${1:-}" "${2:-}"
    ;;
  *)
    usage
    exit 2
    ;;
esac

