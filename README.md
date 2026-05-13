# ssh-bin-paste
Inspired by [@levelsio](https://x.com/levelsio)'s [remote-agent screenshot paste problem](https://x.com/levelsio/status/2053771680317636965):

Paste images and other supported local clipboard payloads into remote Claude or Codex CLI sessions over SSH.
Keep using your normal SSH terminal.
The tool uses a `tmux` key binding to detect the focused remote pane, then pastes the uploaded file path into Claude or Codex.

![ssh-bin-paste demo](docs/ssh-bin-paste-demo.gif)

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
This installs the required counterpart on the remote. Keep it running.

On first run, you will be asked to enter the ssh command you use to connect to your remote, as well as the shortcut you want to use for pasting files (default is `CMD+SHIFT+V`).

### 3. Run Claude or Codex on your remote and paste file!
```sh
tmux new -s agent
codex
```
Press `CMD+SHIFT+V` (or your configured shortcut) while your SSH terminal is focused → the file will be pasted as if being on your host!

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
- Windows/Linux support
