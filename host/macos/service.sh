#!/usr/bin/env bash
set -euo pipefail

LABEL="com.ssh-bin-paste.up"
CONFIG_FILE="${SSH_BIN_PASTE_CONFIG_FILE:-$HOME/.config/ssh-bin-paste/config.sh}"
CACHE_DIR="${SSH_BIN_PASTE_CACHE_DIR:-$HOME/.cache/ssh-bin-paste}"
PROGRAM="${SSH_BIN_PASTE_PROGRAM:-ssh-bin-paste}"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENT_DIR/$LABEL.plist"
OUT_LOG="$CACHE_DIR/launchagent.out.log"
ERR_LOG="$CACHE_DIR/launchagent.err.log"

usage() {
  printf 'usage: ssh-bin-paste service install|status|restart|uninstall\n' >&2
}

xml_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

domain() {
  printf 'gui/%s\n' "$(id -u)"
}

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf 'ssh-bin-paste service is currently supported on macOS only.\n' >&2
    exit 1
  fi
}

write_plist() {
  mkdir -p "$LAUNCH_AGENT_DIR" "$CACHE_DIR"
  cat > "$PLIST" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(xml_escape "$LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$PROGRAM")</string>
    <string>up</string>
    <string>--service</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$OUT_LOG")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$ERR_LOG")</string>
  <key>WorkingDirectory</key>
  <string>$(xml_escape "$HOME")</string>
</dict>
</plist>
EOF2
}

install_service() {
  if [ ! -f "$CONFIG_FILE" ]; then
    printf 'No config found. Run ssh-bin-paste config first.\n' >&2
    exit 1
  fi
  local target_domain
  target_domain="$(domain)"
  write_plist
  launchctl bootout "$target_domain" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "$target_domain" "$PLIST"
  launchctl kickstart -k "$target_domain/$LABEL"
  printf 'installed and started %s\n' "$LABEL"
  printf 'logs: %s and %s\n' "$OUT_LOG" "$ERR_LOG"
}

uninstall_service() {
  launchctl bootout "$(domain)" "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  printf 'uninstalled %s\n' "$LABEL"
}

restart_service() {
  if [ ! -f "$PLIST" ]; then
    printf 'service is not installed. Run ssh-bin-paste service install first.\n' >&2
    exit 1
  fi
  launchctl kickstart -k "$(domain)/$LABEL"
  printf 'restarted %s\n' "$LABEL"
}

status_service() {
  local target
  target="$(domain)/$LABEL"
  if [ -f "$PLIST" ]; then
    printf 'plist: %s\n' "$PLIST"
  else
    printf 'plist: not installed\n'
  fi
  if launchctl print "$target" >/dev/null 2>&1; then
    printf 'status: loaded\n'
  else
    printf 'status: not loaded\n'
  fi
  printf 'logs: %s and %s\n' "$OUT_LOG" "$ERR_LOG"
}

main() {
  require_macos
  local sub="${1:-status}"
  shift || true
  case "$sub" in
    install) install_service "$@" ;;
    uninstall|remove) uninstall_service "$@" ;;
    restart) restart_service "$@" ;;
    status) status_service "$@" ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
