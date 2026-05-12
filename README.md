# ssh-bin-paste

Paste local clipboard images into remote terminal agents over SSH.

`ssh-bin-paste` keeps your normal SSH client in the loop. It captures an image from your Mac clipboard, uploads it to a remote host, and pastes the remote file path into an agent running inside `tmux`.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | bash
```

Then start an agent:

```sh
ssh-bin-paste start --host example-vps --agent codex

# Copy an image on your Mac, then:
ssh-bin-paste paste --host example-vps
```

For Claude Code:

```sh
ssh-bin-paste start --host example-vps --agent claude
```

Attach to the managed remote session from your normal SSH client:

```sh
ssh -t example-vps 'tmux attach -t agent'
```

## Requirements

- macOS on the local machine.
- Rust/Cargo on the local machine.
- SSH access to the remote host.
- `tmux` on the remote host.
- An agent CLI on the remote host, such as Codex or Claude Code.

The install script clones or updates the repo at `~/coding/private/ssh-bin-paste`, builds the Rust CLI, installs it to `~/.local/bin/ssh-bin-paste`, runs `doctor`, installs the remote helper, and starts the remote cleanup daemon.

Install options:

```sh
curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | \
  SSH_BIN_PASTE_HOST=example-vps SSH_BIN_PASTE_AGENT=claude bash

curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | \
  SSH_BIN_PASTE_SSH='ssh -i ~/.ssh/example_ed25519 root@203.0.113.10' bash

curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | \
  SSH_BIN_PASTE_DIR=~/tools/ssh-bin-paste bash

curl -fsSL https://raw.githubusercontent.com/henry-p/ssh-bin-paste/master/scripts/install.sh | \
  SSH_BIN_PASTE_SKIP_REMOTE=1 bash
```

No remote server is installed. `install-remote` installs a tiny helper script that is invoked over SSH when needed.

`install-remote` also starts a tiny cleanup daemon on the remote host. It is not a server and does not listen on any port; it only wakes up periodically and removes old `ssh-bin-paste-*` files from the remote cache.

## Commands

```sh
ssh-bin-paste doctor --host example-vps --agent codex
ssh-bin-paste config
ssh-bin-paste doctor --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10' --agent codex
ssh-bin-paste install-remote --host example-vps
ssh-bin-paste install-remote --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10'
ssh-bin-paste start --host example-vps --agent codex
ssh-bin-paste start --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10' --agent codex
ssh-bin-paste start --host example-vps --agent claude
ssh-bin-paste panes --host example-vps
ssh-bin-paste panes --host example-vps --select
ssh-bin-paste paste --host example-vps
ssh-bin-paste paste --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10'
ssh-bin-paste cleanup --host example-vps
ssh-bin-paste cleanup-daemon status --host example-vps
ssh-bin-paste cleanup-daemon stop --host example-vps
ssh-bin-paste cleanup-daemon start --host example-vps
ssh-bin-paste daemon --host example-vps
ssh-bin-paste daemon --host example-vps --hijack-paste
```

`paste` requires the remote agent to be running inside `tmux`. Direct SSH PTYs cannot be reliably injected from a sidecar process.

## Configuration

Config is optional and lives at:

```text
~/.config/ssh-bin-paste/config.json
```

Run `ssh-bin-paste config` to open the config helper; it creates and edits this file. Use `ssh-bin-paste config --path` to print the path without opening an editor.

Use `panes --select` if you want to adopt an existing `tmux` pane instead of the managed session.
