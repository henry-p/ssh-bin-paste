#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEFAULT_CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste/files}"
STATE_DIR="${SSH_BIN_PASTE_STATE_DIR:-$HOME/.cache/ssh-bin-paste}"
CLEANUP_PID_FILE="$STATE_DIR/cleanup-worker.pid"
CLEANUP_LOG_FILE="$STATE_DIR/cleanup-worker.log"
LAST_SESSION_FILE="$STATE_DIR/last-session"
ATTACH_DIR="$STATE_DIR/attachments"
PAIRING_DIR="$STATE_DIR/pairing-requests"

usage() {
  cat >&2 <<'EOF'
usage: ssh-bin-paste-remote <command> [args]

commands:
  version
  attach
  pairing-next
  pairing-consume <attach-id>
  resolve-attach <attach-id>
  remember-session <tmux-session>
  ensure-cache [cache-dir]
  panes
  inject <target-pane>
  cleanup [cache-dir] [max-age-seconds]
  cleanup-loop [cache-dir] [max-age-seconds] [interval-seconds]
  cleanup-start [cache-dir] [max-age-seconds] [interval-seconds]
  cleanup-stop
  cleanup-status
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

list_panes() {
  tmux list-panes -a -F '#{session_name}	#{window_index}.#{pane_index}	#{pane_id}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}	#{pane_title}' 2>/dev/null || true
}

remember_session() {
  local session="${1:-}"
  if [ -z "$session" ]; then
    printf 'missing tmux session\n' >&2
    return 2
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$session" > "$LAST_SESSION_FILE"
}

write_attach_record() {
  local attach_id="$1"
  local session="$2"
  local tty_name="$3"
  local created_at
  created_at="$(date +%s)"
  mkdir -p "$ATTACH_DIR"
  {
    printf 'attach_id='
    quote_sh "$attach_id"
    printf '\n'
    printf 'tmux_session='
    quote_sh "$session"
    printf '\n'
    printf 'tty='
    quote_sh "$tty_name"
    printf '\n'
    printf 'created_at='
    quote_sh "$created_at"
    printf '\n'
  } > "$ATTACH_DIR/$attach_id"
}

write_pairing_request() {
  local attach_id="$1"
  local session="$2"
  local created_at
  created_at="$(date +%s)"
  mkdir -p "$PAIRING_DIR"
  {
    printf 'attach_id='
    quote_sh "$attach_id"
    printf '\n'
    printf 'tmux_session='
    quote_sh "$session"
    printf '\n'
    printf 'created_at='
    quote_sh "$created_at"
    printf '\n'
  } > "$PAIRING_DIR/$attach_id"
}

pairing_next() {
  mkdir -p "$PAIRING_DIR"
  local newest
  newest="$(find "$PAIRING_DIR" -maxdepth 1 -type f -print 2>/dev/null | while IFS= read -r file; do
    printf '%s\t%s\n' "$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || printf 0)" "$file"
  done | sort -rn | head -n 1 | cut -f2-)"
  [ -n "$newest" ] || return 1
  cat "$newest"
}

pairing_consume() {
  local attach_id="${1:-}"
  if [ -z "$attach_id" ]; then
    printf 'missing attach id\n' >&2
    return 2
  fi
  rm -f "$PAIRING_DIR/$attach_id"
}

resolve_attach() {
  local attach_id="${1:-}"
  if [ -z "$attach_id" ]; then
    printf 'missing attach id\n' >&2
    return 2
  fi

  local record="$ATTACH_DIR/$attach_id"
  if [ ! -f "$record" ]; then
    printf 'stale attachment. Keep ssh-bin-paste up running on your Mac and run ssh-bin-paste attach on the VPS again.\n' >&2
    return 1
  fi

  local tmux_session=""
  local tty=""
  # shellcheck disable=SC1090
  . "$record"

  if [ -z "$tmux_session" ] || [ -z "$tty" ]; then
    printf 'invalid attachment record\n' >&2
    return 1
  fi
  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    printf 'paired tmux session no longer exists. Run ssh-bin-paste attach again.\n' >&2
    return 1
  fi

  local pane
  pane="$(tmux list-clients -t "$tmux_session" -F '#{client_tty}	#{client_active_pane}' 2>/dev/null | awk -F '\t' -v tty="$tty" '$1 == tty { print $2; exit }')"
  if [ -z "$pane" ]; then
    pane="$(tmux list-clients -t "$tmux_session" -F '#{client_tty}	#{pane_id}' 2>/dev/null | awk -F '\t' -v tty="$tty" '$1 == tty { print $2; exit }')"
  fi
  if [ -z "$pane" ]; then
    printf 'paired tmux client is not attached. Re-run ssh-bin-paste attach on the VPS.\n' >&2
    return 1
  fi

  printf '%s\n' "$pane"
}

session_score() {
  local target="$1"
  local score=0
  local session command title haystack

  if [ -f "$LAST_SESSION_FILE" ] && [ "$(cat "$LAST_SESSION_FILE" 2>/dev/null || true)" = "$target" ]; then
    score=$((score + 100))
  fi

  case "$target" in
    agent) score=$((score + 20)) ;;
    *codex*|*claude*|*agent*) score=$((score + 8)) ;;
  esac

  while IFS=$'\t' read -r session command title; do
    [ "$session" = "$target" ] || continue
    haystack="$(printf '%s %s %s' "$session" "$command" "$title" | tr '[:upper:]' '[:lower:]')"
    case "$haystack" in *codex*) score=$((score + 12)) ;; esac
    case "$haystack" in *claude*) score=$((score + 12)) ;; esac
    case "$haystack" in *agent*) score=$((score + 4)) ;; esac
  done < <(tmux list-panes -a -F '#{session_name}	#{pane_current_command}	#{pane_title}' 2>/dev/null || true)

  printf '%s\n' "$score"
}

rank_sessions() {
  local session windows attached score
  while IFS=$'\t' read -r session windows attached; do
    [ -n "$session" ] || continue
    score="$(session_score "$session")"
    printf '%s\t%s\t%s\t%s\n' "$score" "$session" "$windows" "$attached"
  done < <(tmux list-sessions -F '#{session_name}	#{session_windows}	#{session_attached}' 2>/dev/null || true) \
    | sort -rn -k1,1
}

attach_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf 'tmux is not installed on this host\n' >&2
    return 1
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'ssh-bin-paste attach requires an interactive SSH terminal\n' >&2
    return 1
  fi

  local sessions=()
  local scores=()
  local windows=()
  local attached=()
  local score session window_count attached_count

  while IFS=$'\t' read -r score session window_count attached_count; do
    sessions+=("$session")
    scores+=("$score")
    windows+=("$window_count")
    attached+=("$attached_count")
  done < <(rank_sessions)

  if [ "${#sessions[@]}" -eq 0 ]; then
    printf 'No tmux sessions found. Start or resume your agent inside tmux first.\n' >&2
    return 1
  fi

  local default="${sessions[0]}"
  if [ "${scores[0]}" -gt 0 ]; then
    printf 'Suggested tmux session: %s\n' "$default"
  else
    printf 'No obvious agent session found. Choose a tmux session to attach.\n'
  fi
  printf '\n'
  printf 'Available tmux sessions:\n'

  local i label
  for i in "${!sessions[@]}"; do
    label=""
    if [ "$i" -eq 0 ] && [ "${scores[0]}" -gt 0 ]; then
      label=" suggested"
    fi
    printf '  %s. %s%s (windows=%s attached=%s)\n' "$((i + 1))" "${sessions[$i]}" "$label" "${windows[$i]}" "${attached[$i]}"
  done

  printf '\nAttach to tmux session [%s]: ' "$default"
  local answer target
  IFS= read -r answer
  if [ -z "$answer" ]; then
    target="$default"
  elif [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#sessions[@]}" ]; then
    target="${sessions[$((answer - 1))]}"
  else
    target="$answer"
  fi

  if ! tmux has-session -t "$target" 2>/dev/null; then
    printf 'tmux session not found: %s\n' "$target" >&2
    return 1
  fi

  remember_session "$target"
  local attach_id tty_name
  attach_id="$(new_id)"
  tty_name="$(tty 2>/dev/null || true)"
  if [ -z "$tty_name" ]; then
    printf 'ssh-bin-paste attach needs to run from an interactive tty\n' >&2
    return 1
  fi
  write_attach_record "$attach_id" "$target" "$tty_name"
  write_pairing_request "$attach_id" "$target"
  printf 'Pairing request created. If your Mac is running ssh-bin-paste up, it will use this tmux attachment.\n'

  exec tmux attach-session -t "$target"
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

cleanup_stop() {
  local pid
  if ! cleanup_pid_alive; then
    rm -f "$CLEANUP_PID_FILE"
    printf 'not running\n'
    return 0
  fi

  pid="$(cat "$CLEANUP_PID_FILE")"
  kill "$pid" 2>/dev/null || true
  rm -f "$CLEANUP_PID_FILE"
  printf 'stopped pid=%s\n' "$pid"
}

cleanup_status() {
  if cleanup_pid_alive; then
    printf 'running pid=%s\n' "$(cat "$CLEANUP_PID_FILE")"
  else
    rm -f "$CLEANUP_PID_FILE"
    printf 'not running\n'
  fi
}

case "${1:-}" in
  version)
    printf '%s\n' "$VERSION"
    ;;
  attach)
    attach_tmux
    ;;
  pairing-next)
    pairing_next
    ;;
  pairing-consume)
    shift
    pairing_consume "${1:-}"
    ;;
  resolve-attach)
    shift
    resolve_attach "${1:-}"
    ;;
  remember-session)
    shift
    remember_session "${1:-}"
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
  cleanup-loop)
    shift
    cleanup_loop "${1:-}" "${2:-}" "${3:-}"
    ;;
  cleanup-start)
    shift
    cleanup_start "${1:-}" "${2:-}" "${3:-}"
    ;;
  cleanup-stop)
    cleanup_stop
    ;;
  cleanup-status)
    cleanup_status
    ;;
  *)
    usage
    exit 2
    ;;
esac
