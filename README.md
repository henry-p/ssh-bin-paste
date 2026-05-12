# ssh-bin-paste

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.

You keep using your normal SSH terminal. The tool attaches to a `tmux` session running Claude Code or Codex and pairs that terminal with your host.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

The installer runs `config` and starts the host paste shortcut in the background.

In another terminal, connect to your remote yourself and attach to the agent session:

```sh
ssh example-remote
ssh-bin-paste attach
```

Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut. The payload is uploaded over SSH and the remote path is pasted into the currently attached Claude or Codex session.

If you skipped config, or if the paste shortcut is not running:

```sh
ssh-bin-paste up
```

## Commands

| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Configure SSH, install the remote helper, and start the paste shortcut. |
| `ssh-bin-paste up` | Host | Run the paste shortcut and wait for remote `attach` pairings. |
| `ssh-bin-paste attach` | Remote | Choose and attach to the remote `tmux` session running Claude or Codex. |

## Requirements

**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)
&nbsp;&nbsp;&nbsp;↓ *SSH*
**Remote**: `tmux` , `codex` || `claude`
