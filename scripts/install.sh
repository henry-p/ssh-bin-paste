#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SSH_BIN_PASTE_BASE_URL:-https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master}"
BIN_DIR="${SSH_BIN_PASTE_BIN_DIR:-$HOME/.local/bin}"
ASSET_DIR="${SSH_BIN_PASTE_ASSET_DIR:-$HOME/.local/share/ssh-bin-paste}"

log() {
  printf '==> %s\n' "$*"
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

download() {
  local url="$1" dest="$2"
  curl -fsSL "$url" -o "$dest"
}

need curl
need ssh
need swift

mkdir -p "$BIN_DIR" "$ASSET_DIR"

log "installing ssh-bin-paste to $BIN_DIR"
download "$BASE_URL/bin/ssh-bin-paste" "$BIN_DIR/ssh-bin-paste"
chmod 0755 "$BIN_DIR/ssh-bin-paste"

log "installing runtime helpers to $ASSET_DIR"
download "$BASE_URL/remote/ssh-bin-paste-remote.sh" "$ASSET_DIR/ssh-bin-paste-remote.sh"
download "$BASE_URL/host/macos/clipboard-capture.swift" "$ASSET_DIR/clipboard-capture.swift"
download "$BASE_URL/host/macos/paste-up.swift" "$ASSET_DIR/paste-up.swift"
chmod 0644 "$ASSET_DIR/clipboard-capture.swift" "$ASSET_DIR/paste-up.swift"
chmod 0755 "$ASSET_DIR/ssh-bin-paste-remote.sh"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    log "add $BIN_DIR to PATH to run ssh-bin-paste without the full path"
    ;;
esac

cat <<EOF2

ssh-bin-paste installed.

Start the host shortcut and configure on first run:
  ssh-bin-paste up

After connecting to your remote:
  ssh-bin-paste attach

Then copy a supported payload locally and press Cmd+Shift+V.
EOF2
