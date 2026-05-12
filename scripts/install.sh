#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${SSH_BIN_PASTE_REPO:-git@github.com:henry-p/ssh-bin-paste.git}"
INSTALL_DIR="${SSH_BIN_PASTE_DIR:-$HOME/coding/private/ssh-bin-paste}"
BRANCH="${SSH_BIN_PASTE_BRANCH:-master}"
HOST="${SSH_BIN_PASTE_HOST:-example-vps}"
SSH_COMMAND="${SSH_BIN_PASTE_SSH:-}"
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

remote_label() {
  if [ -n "$SSH_COMMAND" ]; then
    printf '%s\n' "$SSH_COMMAND"
  else
    printf '%s\n' "$HOST"
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
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
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

if [ -n "$SSH_COMMAND" ]; then
  REMOTE_ARGS=(--ssh "$SSH_COMMAND")
else
  REMOTE_ARGS=(--host "$HOST")
fi
REMOTE_LABEL="$(remote_label)"

log "running doctor for $REMOTE_LABEL / $AGENT"
ssh-bin-paste doctor "${REMOTE_ARGS[@]}" --agent "$AGENT"

if [ "$SKIP_REMOTE" != "1" ]; then
  log "installing remote helper on $REMOTE_LABEL"
  ssh-bin-paste install-remote "${REMOTE_ARGS[@]}"
else
  log "skipping remote helper install"
fi

if [ -n "$SSH_COMMAND" ]; then
  START_COMMAND="ssh-bin-paste start --ssh '$SSH_COMMAND' --agent $AGENT"
  ATTACH_COMMAND="use the attach command printed by ssh-bin-paste start"
  PASTE_COMMAND="ssh-bin-paste paste --ssh '$SSH_COMMAND'"
else
  START_COMMAND="ssh-bin-paste start --host $HOST --agent $AGENT"
  ATTACH_COMMAND="ssh -t $HOST 'tmux attach -t agent'"
  PASTE_COMMAND="ssh-bin-paste paste --host $HOST"
fi

cat <<EOF

ssh-bin-paste installed.

Start an agent:
  $START_COMMAND

Attach from your SSH client:
  $ATTACH_COMMAND

Paste an image after copying it locally:
  $PASTE_COMMAND
EOF
