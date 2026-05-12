# ssh-bin-paste

Paste local clipboard images into remote terminal agents over SSH.

`ssh-bin-paste` keeps your normal SSH client in the loop. It captures an image from your Mac clipboard, uploads it to a remote host, and pastes the remote file path into an agent running inside `tmux`.

## Quickstart

```sh
git clone git@github.com:henry-p/ssh-bin-paste.git
cd ssh-bin-paste
npm install
npm run build
npm link

ssh-bin-paste doctor --host vibeps
ssh-bin-paste install-remote --host vibeps
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

No remote daemon is installed. `install-remote` installs a tiny helper script that is invoked over SSH only when needed.

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
  "agents": {
    "codex": { "command": "codex" },
    "claude": { "command": "claude" }
  }
}
```

Use `panes --select` if you want to adopt an existing `tmux` pane instead of the managed session.

