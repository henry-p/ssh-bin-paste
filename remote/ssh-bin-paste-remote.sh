#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEFAULT_CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste/files}"
STATE_DIR="${SSH_BIN_PASTE_STATE_DIR:-$HOME/.cache/ssh-bin-paste}"
CLEANUP_PID_FILE="$STATE_DIR/cleanup-worker.pid"
CLEANUP_LOG_FILE="$STATE_DIR/cleanup-worker.log"
REQUEST_DIR="$STATE_DIR/paste-requests"
ARM_FILE="$STATE_DIR/paste-arm"

usage() {
  cat >&2 <<'EOF'
usage: ssh-bin-paste-remote <command> [args]

commands:
  version
  protocol-version
  install-tmux-binding
  request-arm <token>
  request <client-tty> <pane-id> [tmux-session]
  request-next [token] [created-after]
  request-consume <request-id>
  ensure-cache [cache-dir]
  inject <target-pane>
  scan-local-paths
  watch-local-paths [interval-seconds]
  replace-local-path <target-pane> <typed-path> <remote-path>
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
  local token="$5"
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
    printf 'token='
    quote_sh "$token"
    printf '\n'
    printf 'created_at='
    quote_sh "$created_at"
    printf '\n'
  } > "$REQUEST_DIR/$request_id"
}

request_arm() {
  local token="${1:-}"
  if [ -z "$token" ]; then
    printf 'missing token\n' >&2
    return 2
  fi
  mkdir -p "$STATE_DIR"
  {
    printf 'token='
    quote_sh "$token"
    printf '\n'
    printf 'created_at='
    quote_sh "$(date +%s)"
    printf '\n'
  } > "$ARM_FILE"
}

request_paste() {
  local client_tty="${1:-}"
  local pane_id="${2:-}"
  local tmux_session="${3:-}"
  local token=""
  local armed_created_at=0
  if [ -z "$pane_id" ]; then
    printf 'missing pane id\n' >&2
    return 2
  fi
  if [ -z "$tmux_session" ] && command -v tmux >/dev/null 2>&1; then
    tmux_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
  fi
  if [ -f "$ARM_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ARM_FILE"
    armed_created_at="${created_at:-0}"
    case "$armed_created_at" in ''|*[!0-9]*) armed_created_at=0 ;; esac
    if [ $(( $(date +%s) - armed_created_at )) -gt 10 ]; then
      token=""
    fi
    rm -f "$ARM_FILE"
  fi
  local request_id
  request_id="$(new_id)"
  write_request_record "$request_id" "$client_tty" "$pane_id" "$tmux_session" "$token"
}

request_next() {
  local want_token="${1:-}"
  local after="${2:-}"
  if [ -z "$after" ]; then
    after="$(($(date +%s) - 15))"
  fi
  case "$after" in ''|*[!0-9]*) after=0 ;; esac
  local newest_file=""
  local newest_created=0
  local file request_id tmux_session client_tty pane_id token created_at
  mkdir -p "$REQUEST_DIR"
  for file in "$REQUEST_DIR"/*; do
    [ -f "$file" ] || continue
    request_id=""
    tmux_session=""
    client_tty=""
    pane_id=""
    token=""
    created_at=0
    # shellcheck disable=SC1090
    . "$file"
    case "$created_at" in ''|*[!0-9]*) created_at=0 ;; esac
    if [ -n "$want_token" ] && [ "$token" != "$want_token" ]; then
      continue
    fi
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

unescape_typed_path() {
  local raw="$1" out="" i=0 len char
  len="${#raw}"
  while [ "$i" -lt "$len" ]; do
    char="${raw:$i:1}"
    if [ "$char" = "\\" ] && [ $((i + 1)) -lt "$len" ]; then
      i=$((i + 1))
      out="${out}${raw:$i:1}"
    else
      out="${out}${char}"
    fi
    i=$((i + 1))
  done
  printf '%s\n' "$out"
}

extract_local_paths_from_line() {
  local pane_id="$1" line="$2" len i start raw char local_path tail tail_local
  len="${#line}"
  i=0
  while [ "$i" -lt "$len" ]; do
    start=-1
    case "${line:$i}" in
      /Users/*|/Volumes/*|/private/var/*|file:///Users/*|file:///Volumes/*|file:///private/var/*|file://localhost/Users/*|file://localhost/Volumes/*|file://localhost/private/var/*) start="$i" ;;
    esac
    if [ "$start" -lt 0 ]; then
      i=$((i + 1))
      continue
    fi

    raw=""
    while [ "$i" -lt "$len" ]; do
      char="${line:$i:1}"
      if [ "$char" = " " ] || [ "$char" = "$(printf '\t')" ] || [ "$char" = '"' ] || [ "$char" = "'" ] || [ "$char" = "<" ] || [ "$char" = ">" ] || [ "$char" = "|" ] || [ "$char" = "[" ] || [ "$char" = "]" ] || [ "$char" = "{" ] || [ "$char" = "}" ]; then
        break
      fi
      case "$char" in
        "\\")
          raw="${raw}${char}"
          i=$((i + 1))
          if [ "$i" -lt "$len" ]; then
            raw="${raw}${line:$i:1}"
          fi
          ;;
        *)
          raw="${raw}${char}"
          ;;
      esac
      i=$((i + 1))
    done

    if [ -n "$raw" ]; then
      local_path="$(unescape_typed_path "$raw")"
      case "$local_path" in
        file://localhost/*) local_path="${local_path#file://localhost}" ;;
        file://*) local_path="${local_path#file://}" ;;
      esac
      printf '%s\t%s\t%s\n' "$pane_id" "$raw" "$local_path"
    fi

    tail="${line:$start}"
    tail="${tail%"${tail##*[![:space:]]}"}"
    if [ -n "$tail" ] && [ "$tail" != "$raw" ]; then
      tail_local="$(unescape_typed_path "$tail")"
      case "$tail_local" in
        file://localhost/*) tail_local="${tail_local#file://localhost}" ;;
        file://*) tail_local="${tail_local#file://}" ;;
      esac
      printf '%s\t%s\t%s\n' "$pane_id" "$tail" "$tail_local"
    fi
  done
}

scan_local_paths() {
  command -v tmux >/dev/null 2>&1 || return 0
  local pane_id pane_command cursor_y start_y content line
  tmux list-panes -a -F '#{pane_id}	#{pane_current_command}' 2>/dev/null | while IFS="$(printf '\t')" read -r pane_id pane_command; do
    [ -n "$pane_id" ] || continue
    case "$pane_command" in
      codex|claude|node|bun|deno|python|python3) ;;
      *) continue ;;
    esac
    cursor_y="$(tmux display-message -p -t "$pane_id" '#{cursor_y}' 2>/dev/null || printf 0)"
    case "$cursor_y" in ''|*[!0-9]*) cursor_y=0 ;; esac
    start_y="$cursor_y"
    if [ "$start_y" -gt 0 ]; then
      start_y=$((start_y - 1))
    fi
    content="$(tmux capture-pane -p -J -t "$pane_id" -S "$start_y" -E "$cursor_y" 2>/dev/null || true)"
    while IFS= read -r line; do
      extract_local_paths_from_line "$pane_id" "$line"
    done <<EOF2
$content
EOF2
  done
}

watch_local_paths() {
  local interval="${1:-0.5}"
  while true; do
    scan_local_paths
    sleep "$interval"
  done
}

replace_local_path() {
  local target="${1:-}" typed_path="${2:-}" remote_path="${3:-}" count i
  if [ -z "$target" ] || [ -z "$typed_path" ] || [ -z "$remote_path" ]; then
    printf 'usage: replace-local-path <target-pane> <typed-path> <remote-path>\n' >&2
    return 2
  fi
  validate_pane "$target"

  count="${#typed_path}"
  i=0
  while [ "$i" -lt "$count" ]; do
    tmux send-keys -t "$target" BSpace
    i=$((i + 1))
  done
  remove_leftover_path_slash "$target"
  printf '%s' "$remote_path" | inject "$target"
}

remove_leftover_path_slash() {
  local target="$1" cursor_y line trimmed
  cursor_y="$(tmux display-message -p -t "$target" '#{cursor_y}' 2>/dev/null || printf 0)"
  case "$cursor_y" in ''|*[!0-9]*) cursor_y=0 ;; esac
  line="$(tmux capture-pane -p -J -t "$target" -S "$cursor_y" -E "$cursor_y" 2>/dev/null || true)"
  trimmed="${line%"${line##*[![:space:]]}"}"
  if [ "${trimmed%"${trimmed#?}"}" = "" ]; then
    return 0
  fi
  if [ "${trimmed: -1}" = "/" ]; then
    tmux send-keys -t "$target" BSpace
  fi
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
  protocol-version)
    printf '3\n'
    ;;
  install-tmux-binding)
    install_tmux_binding
    ;;
  request-arm)
    shift
    request_arm "${1:-}"
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
  scan-local-paths)
    scan_local_paths
    ;;
  watch-local-paths)
    shift
    watch_local_paths "${1:-}"
    ;;
  replace-local-path)
    shift
    replace_local_path "${1:-}" "${2:-}" "${3:-}"
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
