# ssh-bin-paste

Inspired by [@levelsio](https://x.com/levelsio)'s [remote-agent screenshot paste problem](https://x.com/levelsio/status/2053771680317636965):

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.
Keep using your normal SSH terminal.
The tool uses a `tmux` key binding to detect the focused remote pane, then pastes the uploaded file path into Claude or Codex.

## Quickstart

### 1. Install

```sh
curl -fsSL \
  https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh \
  | bash
```

### 2. On the host, start paste capture

```sh
ssh-bin-paste up
```

On first run, enter your SSH command, for example `ssh user@example-remote`.
This installs the remote helper, adds an idempotent `Ctrl+]` tmux binding on the remote, and starts the paste shortcut listener; keep it running on the host.

## Use

```sh
# In your normal SSH terminal, connect with the same SSH command.
ssh user@example-remote

# On the remote, run Claude or Codex inside tmux.
tmux new -s agent
codex
```

Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut.
The payload is uploaded over SSH and the remote path is pasted into the focused Claude or Codex tmux pane.

## Paste shortcut

Press `Cmd+Shift+V` while your SSH terminal is focused.
The host sends `Ctrl+]` through the active SSH connection, tmux records the focused pane, then the host uploads the clipboard payload and pastes the remote file path into that pane.

## Commands

| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Set the SSH command, install the remote helper, and add the tmux binding. |
| `ssh-bin-paste up` | Host | Configure on first run, then run the paste shortcut listener. |

## Requirements

**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)\
&nbsp;&nbsp;&nbsp;↓ *SSH*\
**Remote**: `tmux` and Claude Code or Codex

## Coming soon

- Launch service on system start
- Windows/Linux support
