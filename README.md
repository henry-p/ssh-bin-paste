# ssh-bin-paste

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.

You keep using your normal SSH terminal. The tool attaches to a `tmux` session running `claude` or `codex` and pairs that terminal with your host.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

Start the host shortcut. On first run, this opens the config wizard and installs the remote helper.

```sh
ssh-bin-paste up
```

In another terminal, connect to your remote yourself and attach to the agent session:

```sh
ssh example-remote
ssh-bin-paste attach
```

Keep `ssh-bin-paste up` running on the host. Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut. The payload is uploaded over SSH and the remote path is pasted into the currently attached Claude or Codex session.

## Commands

| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Configure SSH and install the remote helper. |
| `ssh-bin-paste up` | Host | Configure on first run, then run the paste shortcut and wait for remote `attach` pairings. |
| `ssh-bin-paste attach` | Remote | Choose and attach to the remote `tmux` session running Claude or Codex. |

## Requirements

**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)\
&nbsp;&nbsp;&nbsp;↓ *SSH*\
**Remote**: `tmux` , `codex` || `claude`\
