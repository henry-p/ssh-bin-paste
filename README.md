# ssh-bin-paste

Paste local clipboard images into remote terminal agents over SSH.

`ssh-bin-paste` keeps your normal SSH client in the loop. It captures an image from your Mac clipboard, uploads it to a remote host, and pastes the remote file path into an agent running inside `tmux`.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/main/scripts/install.sh | bash
```

Then start an agent:

```sh
ssh-bin-paste start --host vibeps --agent codex

# Copy an image on your Mac, then:
ssh-bin-paste paste --host vibeps
```

For Claude Code:

```sh
ssh-bin-paste start --host vibeps --agent claude
```

Attach to the managed remote session from your normal SSH client:

```sh
ssh -t vibeps 'tmux attach -t agent'
```

## Requirements

- macOS on the local machine.
- SSH access to the remote host.
- `tmux` on the remote host.
- An agent CLI on the remote host, such as Codex or Claude Code.

The install script clones or updates the repo at `~/coding/private/ssh-bin-paste`, runs `npm install`, builds the CLI, links `ssh-bin-paste`, runs `doctor`, installs the remote helper, and starts the remote cleanup daemon.

Install options:

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/main/scripts/install.sh | \
  SSH_BIN_PASTE_HOST=vibeps SSH_BIN_PASTE_AGENT=claude bash

curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/main/scripts/install.sh | \
  SSH_BIN_PASTE_DIR=~/tools/ssh-bin-paste bash

curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/main/scripts/install.sh | \
  SSH_BIN_PASTE_SKIP_REMOTE=1 bash
```

No remote server is installed. `install-remote` installs a tiny helper script that is invoked over SSH when needed.

`install-remote` also starts a tiny cleanup daemon on the remote host. It is not a server and does not listen on any port; it only wakes up periodically and removes old `ssh-bin-paste-*` files from the remote cache.

## Commands

```sh
ssh-bin-paste doctor --host vibeps --agent codex
ssh-bin-paste install-remote --host vibeps
ssh-bin-paste start --host vibeps --agent codex
ssh-bin-paste start --host vibeps --agent claude
ssh-bin-paste panes --host vibeps
ssh-bin-paste panes --host vibeps --select
ssh-bin-paste paste --host vibeps
ssh-bin-paste cleanup --host vibeps
ssh-bin-paste cleanup-daemon status --host vibeps
ssh-bin-paste cleanup-daemon stop --host vibeps
ssh-bin-paste cleanup-daemon start --host vibeps
ssh-bin-paste daemon --host vibeps
ssh-bin-paste daemon --host vibeps --hijack-paste
```

`paste` requires the remote agent to be running inside `tmux`. Direct SSH PTYs cannot be reliably injected from a sidecar process.

## Configuration

Config is optional and lives at:

```text
~/.config/ssh-bin-paste/config.json
```

Default profile shape:

```json
{
  "host": "vibeps",
  "tmuxSession": "agent",
  "remoteCacheDir": "~/.cache/ssh-bin-paste/images",
  "remoteHelperPath": "~/.local/bin/ssh-bin-paste-remote",
  "cleanupDaemon": {
    "enabled": true,
    "maxAgeSeconds": 86400,
    "intervalSeconds": 300
  },
  "agents": {
    "codex": { "command": "codex" },
    "claude": { "command": "claude" }
  }
}
```

Use `panes --select` if you want to adopt an existing `tmux` pane instead of the managed session.
