# ssh-bin-paste

Inspired by [@levelsio](https://x.com/levelsio)'s [remote-agent screenshot paste problem](https://x.com/levelsio/status/2053771680317636965):

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.
Keep using your normal SSH terminal.
The tool attaches to a `tmux` session running `claude` or `codex` and pairs that terminal with your host.

## Quickstart

### 1. Install

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

### 2. On the host, start the paste capture process

```sh
ssh-bin-paste up
```

On first run, this opens the config wizard and installs the remote helper; keep it running on the host.

### 3. On the remote, attach to the agent session

```sh
ssh example-remote
ssh-bin-paste attach
```

Done! Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut.
The payload is uploaded over SSH and the remote path is pasted into the currently attached Claude or Codex session.

## Commands

| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Configure SSH and install the remote helper. |
| `ssh-bin-paste up` | Host | Configure on first run, then run the paste shortcut and wait for remote `attach` pairings. |
| `ssh-bin-paste attach` | Remote | Choose and attach to the remote `tmux` session running Claude or Codex. |

## Requirements

**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)\
&nbsp;&nbsp;&nbsp;↓ *SSH*\
**Remote**: `tmux` , `codex` || `claude`

## Coming soon

- Launch service on system start
- Windows/Linux support
