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

The installer is interactive. It asks where to install the local binary, then launches the same `ssh-bin-paste config` wizard used after installation. The wizard accepts either an SSH config host alias, such as `example-vps`, or a full SSH command, such as `ssh -i ~/.ssh/example_ed25519 user@203.0.113.10`. It validates the shape of the input before writing config, and the installer then runs `doctor` to verify SSH, remote `tmux`, the selected agent command, and the writable remote cache.

No remote server is installed. `install-remote` installs a tiny helper script that is invoked over SSH when needed.

`install-remote` also starts a tiny cleanup daemon on the remote host. It is not a server and does not listen on any port; it only wakes up periodically and removes old `ssh-bin-paste-*` files from the remote cache.

## Commands

```sh
ssh-bin-paste doctor --host example-vps --agent codex
ssh-bin-paste config
ssh-bin-paste doctor
ssh-bin-paste doctor --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10' --agent codex
ssh-bin-paste install-remote --host example-vps
ssh-bin-paste install-remote
ssh-bin-paste install-remote --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10'
ssh-bin-paste start --host example-vps --agent codex
ssh-bin-paste start
ssh-bin-paste start --ssh 'ssh -i ~/.ssh/example_ed25519 root@203.0.113.10' --agent codex
ssh-bin-paste start --host example-vps --agent claude
ssh-bin-paste panes --host example-vps
ssh-bin-paste panes --host example-vps --select
ssh-bin-paste paste --host example-vps
ssh-bin-paste paste
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

Run `ssh-bin-paste config` to open the config wizard; it guides you through setup and writes this file. Use `ssh-bin-paste config --path` to print the path without running the wizard.

Use `panes --select` if you want to adopt an existing `tmux` pane instead of the managed session.
