#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${SSH_BIN_PASTE_REPO:-https://github.com/henry-p/ssh-bin-paste.git}"
BRANCH="${SSH_BIN_PASTE_BRANCH:-master}"
DEFAULT_INSTALL_DIR="~/coding/private/ssh-bin-paste"
DEFAULT_BIN_DIR="~/.local/bin"

log() {
  printf '==> %s\n' "$*"
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

remote_label() {
  "$BIN" config --print | awk -F'"' '
    /"sshCommand":/ { ssh_command = $4 }
    /"host":/ { host = $4 }
    END {
      if (ssh_command != "") print ssh_command
      else if (host != "") print host
      else print "saved config"
    }
  '
}

prompt() {
  local label="$1"
  local default="$2"
  local answer
  while true; do
    printf '%s [%s]: ' "$label" "$default" >/dev/tty
    IFS= read -r answer </dev/tty
    answer="${answer:-$default}"
    if [ -n "$answer" ]; then
      printf '%s\n' "$answer"
      return 0
    fi
    printf 'Please enter a value.\n' >/dev/tty
  done
}

prompt_yes_no() {
  local label="$1"
  local default="$2"
  local answer prompt_label
  if [ "$default" = "y" ]; then
    prompt_label="Y/n"
  else
    prompt_label="y/N"
  fi
  while true; do
    printf '%s [%s]: ' "$label" "$prompt_label" >/dev/tty
    IFS= read -r answer </dev/tty
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf 'Please answer yes or no.\n' >/dev/tty ;;
    esac
  done
}

expand_tilde() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

need git
need cargo
need ssh
need swift

if [ ! -r /dev/tty ]; then
  printf 'interactive install requires a terminal\n' >&2
  exit 1
fi

cat >/dev/tty <<EOF
ssh-bin-paste installer

Press Enter to accept defaults. Remote SSH and agent settings are configured by
the shared ssh-bin-paste config wizard after the CLI is installed.

EOF

INSTALL_DIR_INPUT="$(prompt "Install directory" "$DEFAULT_INSTALL_DIR")"
BIN_DIR_INPUT="$(prompt "Binary directory" "$DEFAULT_BIN_DIR")"
INSTALL_DIR="$(expand_tilde "$INSTALL_DIR_INPUT")"
BIN_DIR="$(expand_tilde "$BIN_DIR_INPUT")"

if [ -d "$INSTALL_DIR/.git" ]; then
  log "updating $INSTALL_DIR"
  if ! git -C "$INSTALL_DIR" diff --quiet; then
    if prompt_yes_no "Existing checkout has uncommitted changes. Build it without updating" "n"; then
      log "building existing checkout without git update"
    else
      printf 'aborting because %s has uncommitted changes\n' "$INSTALL_DIR" >&2
      exit 1
    fi
  else
    git -C "$INSTALL_DIR" fetch origin
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
  fi
else
  log "cloning $REPO_URL to $INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

log "building Rust CLI"
cargo build --release

log "installing ssh-bin-paste to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 target/release/ssh-bin-paste "$BIN_DIR/ssh-bin-paste"
BIN="$BIN_DIR/ssh-bin-paste"

if ! command -v ssh-bin-paste >/dev/null 2>&1; then
  log "add $BIN_DIR to PATH to run ssh-bin-paste without the full path"
fi

log "opening config wizard"
"$BIN" config </dev/tty >/dev/tty

if prompt_yes_no "Run doctor and install the remote helper now" "y"; then
  REMOTE_LABEL="$(remote_label)"
  log "running doctor for $REMOTE_LABEL"
  "$BIN" doctor

  log "installing remote helper on $REMOTE_LABEL"
  "$BIN" install-remote
else
  log "skipping doctor and remote helper install"
fi

cat <<EOF

ssh-bin-paste installed.

Start an agent:
  $BIN start

Attach from your SSH client:
  use the attach command printed by ssh-bin-paste start

Paste a supported file after copying it locally:
  $BIN paste
EOF
