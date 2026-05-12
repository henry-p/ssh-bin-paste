#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${SSH_BIN_PASTE_REPO:-git@github.com:henry-p/ssh-bin-paste.git}"
INSTALL_DIR="${SSH_BIN_PASTE_DIR:-$HOME/coding/private/ssh-bin-paste}"
HOST="${SSH_BIN_PASTE_HOST:-vibeps}"
AGENT="${SSH_BIN_PASTE_AGENT:-codex}"
SKIP_REMOTE="${SSH_BIN_PASTE_SKIP_REMOTE:-0}"
ALLOW_DIRTY="${SSH_BIN_PASTE_ALLOW_DIRTY:-0}"

log() {
  printf '==> %s\n' "$*"
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

need git
need npm
need ssh
need swift

if [ -d "$INSTALL_DIR/.git" ]; then
  log "updating $INSTALL_DIR"
  if [ "$ALLOW_DIRTY" != "1" ] && ! git -C "$INSTALL_DIR" diff --quiet; then
    printf 'install dir has uncommitted changes: %s\n' "$INSTALL_DIR" >&2
    printf 'commit/stash them, choose another SSH_BIN_PASTE_DIR, or set SSH_BIN_PASTE_ALLOW_DIRTY=1.\n' >&2
    exit 1
  fi
  git -C "$INSTALL_DIR" fetch origin
  git -C "$INSTALL_DIR" checkout main
  git -C "$INSTALL_DIR" pull --ff-only origin main
else
  log "cloning $REPO_URL to $INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

log "installing dependencies"
npm install

log "building CLI"
npm run build

log "linking ssh-bin-paste"
npm link

log "running doctor for $HOST / $AGENT"
ssh-bin-paste doctor --host "$HOST" --agent "$AGENT"

if [ "$SKIP_REMOTE" != "1" ]; then
  log "installing remote helper on $HOST"
  ssh-bin-paste install-remote --host "$HOST"
else
  log "skipping remote helper install"
fi

cat <<EOF

ssh-bin-paste installed.

Start an agent:
  ssh-bin-paste start --host $HOST --agent $AGENT

Attach from your SSH client:
  ssh -t $HOST 'tmux attach -t agent'

Paste an image after copying it locally:
  ssh-bin-paste paste --host $HOST
EOF
