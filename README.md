# ssh-bin-paste

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.

ssh-bin-paste uses `tmux` on the remote host so it has a stable place to inject the pasted file path. You keep using your normal SSH terminal; inside SSH, `ssh-bin-paste attach` attaches to the tmux session running Claude or Codex and pairs that terminal with your Mac.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

In another terminal, connect to your VPS yourself and attach to the agent session:

```sh
ssh example-vps
ssh-bin-paste attach
```

Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut. The payload is uploaded over SSH and the remote path is pasted into the currently attached Claude or Codex session.

If the paste shortcut is not running:

```sh
ssh-bin-paste up
```

## More commands

| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Mac | Configure SSH, install the remote helper, and start the paste shortcut. |
| `ssh-bin-paste up` | Mac | Run the paste shortcut and wait for remote `attach` pairings. |
| `ssh-bin-paste attach` | VPS | Choose and attach to the remote `tmux` session running Claude or Codex. |

## Requirements

- macOS locally.
- Swift or Apple Command Line Tools for the current macOS helper.
- SSH access to the remote host.
- `tmux` on the remote host.
- Claude Code and/or Codex on the remote host.
