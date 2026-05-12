# ssh-bin-paste

Paste supported local clipboard payloads into remote terminal agents over SSH.

The core CLI is written in Rust, keeping the tool fast and resource-light enough for tiny VPS servers.

Images are the main supported clipboard payload today. The bridge is file-based, so every supported binary file type follows the same upload-and-paste path.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

Start Codex:

```sh
ssh-bin-paste start codex
```

Or start Claude Code:

```sh
ssh-bin-paste start claude
```

Copy a supported file or image locally, focus your SSH terminal, then press the paste shortcut to send it to the remote agent.

## What setup does

The installer runs `ssh-bin-paste setup`. It guides you through SSH configuration, checks the remote host, installs the tiny remote helper, and starts remote cache cleanup.

If you installed manually, run:

```sh
ssh-bin-paste setup
```

## Requirements

- macOS locally.
- Rust/Cargo locally.
- SSH access to the remote host.
- `tmux` on the remote host.
- Codex or Claude Code on the remote host.
