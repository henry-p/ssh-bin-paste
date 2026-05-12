# ssh-bin-paste

Paste local clipboard images into remote terminal agents over SSH.

`ssh-bin-paste` keeps your normal SSH client in the loop. It captures an image from your Mac clipboard, uploads it to a remote host, and pastes the remote file path into an agent running inside `tmux`.

## Quickstart

```sh
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

## Requirements

- macOS on the local machine.
- SSH access to the remote host.
- `tmux` on the remote host.
- An agent CLI on the remote host, such as Codex or Claude Code.

No remote daemon is installed. `install-remote` installs a tiny helper script that is invoked over SSH only when needed.

