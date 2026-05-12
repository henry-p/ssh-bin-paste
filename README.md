# ssh-bin-paste

Paste supported local clipboard payloads into remote terminal agents over SSH.

The normal installer is script-only. You do not need Git, Rust, or Cargo to install or run it.

Images are the main supported clipboard payload today. The bridge is file-based, so every supported binary file type follows the same upload-and-paste path.

Codex and Claude Code are both supported. Run either agent on the VPS inside `tmux`; ssh-bin-paste pairs your Mac with the SSH terminal you attach from.

The macOS shortcut helper currently runs from small Swift scripts. If Swift is unavailable, macOS may ask you to install Command Line Tools; future releases should use prebuilt helpers.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

On your Mac:

```sh
ssh-bin-paste pair
```

In another terminal, connect to your VPS yourself and attach to the agent session:

```sh
ssh example-vps
ssh-bin-paste attach
```

Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut. The payload is uploaded over SSH and the remote path is pasted into the currently attached agent session.

If the paste shortcut is not running:

```sh
ssh-bin-paste up
```

## What config does

The installer runs `ssh-bin-paste config`. It guides you through SSH configuration, checks the remote host, installs the tiny remote helper, and starts the local paste shortcut.

If you installed manually, run:

```sh
ssh-bin-paste config
```

## Requirements

- macOS locally.
- Swift or Apple Command Line Tools for the current macOS helper.
- SSH access to the remote host.
- `tmux` on the remote host.
- Codex and/or Claude Code on the remote host.
