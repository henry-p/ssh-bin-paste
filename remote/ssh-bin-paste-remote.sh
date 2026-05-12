#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
DEFAULT_CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste/files}"
STATE_DIR="${SSH_BIN_PASTE_STATE_DIR:-$HOME/.cache/ssh-bin-paste}"
DAEMON_PID_FILE="$STATE_DIR/cleanup-daemon.pid"
DAEMON_LOG_FILE="$STATE_DIR/cleanup-daemon.log"
LAST_SESSION_FILE="$STATE_DIR/last-session"

usage() {
  cat >&2 <<'EOF'
usage: ssh-bin-paste-remote <command> [args]

commands:
  version
  attach
  remember-session <tmux-session>
  ensure-cache [cache-dir]
  panes
  inject <target-pane>
  cleanup [cache-dir] [max-age-seconds]
  daemon [cache-dir] [max-age-seconds] [interval-seconds]
  daemon-start [cache-dir] [max-age-seconds] [interval-seconds]
  daemon-stop
  daemon-status
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
    printf 'No tmux sessions found. Start an agent first with ssh-bin-paste start codex or ssh-bin-paste start claude on your Mac.\n' >&2
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

daemon() {
  local dir max_age interval
  dir="${1:-$DEFAULT_CACHE_DIR}"
  max_age="${2:-86400}"
  interval="${3:-300}"

  while true; do
    cleanup "$dir" "$max_age"
    sleep "$interval"
  done
}

daemon_pid_alive() {
  local pid
  [ -f "$DAEMON_PID_FILE" ] || return 1
  pid="$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

daemon_start() {
  local dir max_age interval
  dir="${1:-$DEFAULT_CACHE_DIR}"
  max_age="${2:-86400}"
  interval="${3:-300}"

  mkdir -p "$STATE_DIR"
  if daemon_pid_alive; then
    printf 'already running pid=%s\n' "$(cat "$DAEMON_PID_FILE")"
    return 0
  fi

  nohup "$0" daemon "$dir" "$max_age" "$interval" >>"$DAEMON_LOG_FILE" 2>&1 &
  printf '%s\n' "$!" > "$DAEMON_PID_FILE"
  printf 'started pid=%s max_age=%s interval=%s\n' "$!" "$max_age" "$interval"
}

daemon_stop() {
  local pid
  if ! daemon_pid_alive; then
    rm -f "$DAEMON_PID_FILE"
    printf 'not running\n'
    return 0
  fi

  pid="$(cat "$DAEMON_PID_FILE")"
  kill "$pid" 2>/dev/null || true
  rm -f "$DAEMON_PID_FILE"
  printf 'stopped pid=%s\n' "$pid"
}

daemon_status() {
  if daemon_pid_alive; then
    printf 'running pid=%s\n' "$(cat "$DAEMON_PID_FILE")"
  else
    rm -f "$DAEMON_PID_FILE"
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
  daemon)
    shift
    daemon "${1:-}" "${2:-}" "${3:-}"
    ;;
  daemon-start)
    shift
    daemon_start "${1:-}" "${2:-}" "${3:-}"
    ;;
  daemon-stop)
    daemon_stop
    ;;
  daemon-status)
    daemon_status
    ;;
  *)
    usage
    exit 2
    ;;
esac
