#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEFAULT_CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste/files}"
STATE_DIR="${SSH_BIN_PASTE_STATE_DIR:-$HOME/.cache/ssh-bin-paste}"
CLEANUP_PID_FILE="$STATE_DIR/cleanup-worker.pid"
CLEANUP_LOG_FILE="$STATE_DIR/cleanup-worker.log"
REQUEST_DIR="$STATE_DIR/paste-requests"

usage() {
  cat >&2 <<'EOF'
usage: ssh-bin-paste-remote <command> [args]

commands:
  version
  install-tmux-binding
  request <client-tty> <pane-id> [tmux-session]
  request-next [created-after]
  request-consume <request-id>
  ensure-cache [cache-dir]
  inject <target-pane>
  cleanup-loop [cache-dir] [max-age-seconds] [interval-seconds]
  cleanup-start [cache-dir] [max-age-seconds] [interval-seconds]
EOF
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
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

quote_sh() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

new_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    printf '%s-%s\n' "$(date +%s)" "$$"
  fi
}

write_request_record() {
  local request_id="$1"
  local client_tty="$2"
  local pane_id="$3"
  local tmux_session="$4"
  local created_at
  created_at="$(date +%s)"
  mkdir -p "$REQUEST_DIR"
  {
    printf 'request_id='
    quote_sh "$request_id"
    printf '\n'
    printf 'tmux_session='
    quote_sh "$tmux_session"
    printf '\n'
    printf 'client_tty='
    quote_sh "$client_tty"
    printf '\n'
    printf 'pane_id='
    quote_sh "$pane_id"
    printf '\n'
    printf 'created_at='
    quote_sh "$created_at"
    printf '\n'
  } > "$REQUEST_DIR/$request_id"
}

request_paste() {
  local client_tty="${1:-}"
  local pane_id="${2:-}"
  local tmux_session="${3:-}"
  if [ -z "$pane_id" ]; then
    printf 'missing pane id\n' >&2
    return 2
  fi
  if [ -z "$tmux_session" ] && command -v tmux >/dev/null 2>&1; then
    tmux_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
  fi
  local request_id
  request_id="$(new_id)"
  write_request_record "$request_id" "$client_tty" "$pane_id" "$tmux_session"
}

request_next() {
  local after="${1:-}"
  if [ -z "$after" ]; then
    after="$(($(date +%s) - 15))"
  fi
  case "$after" in ''|*[!0-9]*) after=0 ;; esac
  local newest_file=""
  local newest_created=0
  local file request_id tmux_session client_tty pane_id created_at
  mkdir -p "$REQUEST_DIR"
  for file in "$REQUEST_DIR"/*; do
    [ -f "$file" ] || continue
    request_id=""
    tmux_session=""
    client_tty=""
    pane_id=""
    created_at=0
    # shellcheck disable=SC1090
    . "$file"
    case "$created_at" in ''|*[!0-9]*) created_at=0 ;; esac
    if [ "$created_at" -ge "$after" ] && [ "$created_at" -ge "$newest_created" ]; then
      newest_created="$created_at"
      newest_file="$file"
    fi
  done
  [ -n "$newest_file" ] || return 1
  cat "$newest_file"
}

request_consume() {
  local request_id="${1:-}"
  if [ -z "$request_id" ]; then
    printf 'missing request id\n' >&2
    return 2
  fi
  rm -f "$REQUEST_DIR/$request_id"
}

helper_self_path() {
  case "$0" in
    /*) printf '%s\n' "$0" ;;
    */*) printf '%s/%s\n' "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" "$(basename -- "$0")" ;;
    *) command -v "$0" 2>/dev/null || printf '%s\n' "$0" ;;
  esac
}

install_tmux_binding() {
  local conf="$HOME/.tmux.conf"
  local helper command binding tmp existing_had_block=0
  helper="$(helper_self_path)"
  command="$helper request \"#{client_tty}\" \"#{pane_id}\" \"#{session_name}\""
  binding="bind-key -n C-] run-shell -b $(quote_sh "$command")"

  if [ -f "$conf" ] && grep -Fx -- "$binding" "$conf" >/dev/null; then
    command -v tmux >/dev/null 2>&1 && tmux source-file "$conf" 2>/dev/null || true
    printf 'tmux binding C-] already installed in %s\n' "$conf"
    return 0
  fi

  tmp="$(mktemp)"
  if [ -f "$conf" ]; then
    if grep -Fx -- '# >>> ssh-bin-paste' "$conf" >/dev/null; then
      existing_had_block=1
    fi
    awk '
      /^# >>> ssh-bin-paste$/ { skip = 1; next }
      /^# <<< ssh-bin-paste$/ { skip = 0; next }
      !skip { print }
    ' "$conf" > "$tmp"
  fi
  {
    printf '\n# >>> ssh-bin-paste\n'
    printf '%s\n' "$binding"
    printf '# <<< ssh-bin-paste\n'
  } >> "$tmp"
  mv "$tmp" "$conf"
  command -v tmux >/dev/null 2>&1 && tmux source-file "$conf" 2>/dev/null || true
  if [ "$existing_had_block" = "1" ]; then
    printf 'tmux binding C-] updated in %s\n' "$conf"
  else
    printf 'tmux binding C-] added to %s\n' "$conf"
  fi
}

validate_pane() {
  local pane_id="${1:-}"
  if [ -z "$pane_id" ]; then
    printf 'missing pane id\n' >&2
    return 2
  fi
  if ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fx -- "$pane_id" >/dev/null; then
    printf 'requested tmux pane no longer exists: %s\n' "$pane_id" >&2
    return 1
  fi
}

inject() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    printf 'missing target pane\n' >&2
    return 2
  fi
  validate_pane "$target"

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
  find "$dir" -type f -name 'ssh-bin-paste-*' -mmin "+$(((max_age + 59) / 60))" -delete 2>/dev/null || true
}

cleanup_loop() {
  local dir max_age interval
  dir="${1:-$DEFAULT_CACHE_DIR}"
  max_age="${2:-86400}"
  interval="${3:-300}"

  while true; do
    cleanup "$dir" "$max_age"
    sleep "$interval"
  done
}

cleanup_pid_alive() {
  local pid
  [ -f "$CLEANUP_PID_FILE" ] || return 1
  pid="$(cat "$CLEANUP_PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

cleanup_start() {
  local dir max_age interval
  dir="${1:-$DEFAULT_CACHE_DIR}"
  max_age="${2:-86400}"
  interval="${3:-300}"

  mkdir -p "$STATE_DIR"
  if cleanup_pid_alive; then
    printf 'already running pid=%s\n' "$(cat "$CLEANUP_PID_FILE")"
    return 0
  fi

  nohup "$0" cleanup-loop "$dir" "$max_age" "$interval" >>"$CLEANUP_LOG_FILE" 2>&1 &
  printf '%s\n' "$!" > "$CLEANUP_PID_FILE"
  printf 'started pid=%s max_age=%s interval=%s\n' "$!" "$max_age" "$interval"
}

case "${1:-}" in
  version)
    printf '%s\n' "$VERSION"
    ;;
  install-tmux-binding)
    install_tmux_binding
    ;;
  request)
    shift
    request_paste "${1:-}" "${2:-}" "${3:-}"
    ;;
  request-next)
    shift
    request_next "${1:-}"
    ;;
  request-consume)
    shift
    request_consume "${1:-}"
    ;;
  ensure-cache)
    shift
    ensure_cache "${1:-}"
    ;;
  inject)
    shift
    inject "${1:-}"
    ;;
  cleanup-loop)
    shift
    cleanup_loop "${1:-}" "${2:-}" "${3:-}"
    ;;
  cleanup-start)
    shift
    cleanup_start "${1:-}" "${2:-}" "${3:-}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
