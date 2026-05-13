# ssh-bin-paste
Inspired by [@levelsio](https://x.com/levelsio)'s [remote-agent screenshot paste problem](https://x.com/levelsio/status/2053771680317636965):

**Paste images and into remote Claude or Codex CLI sessions over SSH!**
**Drag & drop also works!**

Keep using your normal SSH terminal. No tunnels, no proxies.

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
On first run, you will be asked to enter the ssh command you use to connect to your remote, as well as the shortcut you want to use for pasting files (default is `CMD+SHIFT+V`).

### 3. Run Claude or Codex on your remote and paste file!
```sh
tmux new -s agent
codex
```
**Paste:** Press `CMD+SHIFT+V` (or your configured shortcut)
or
**Drag & drop**
→ The file will be pasted as if being on your host!

## Want it as always-on background service?
`ssh-bin-paste service install` installs a `launchd` (macOS) service.
Windows/Linux support coming soon.

## Commands
| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Set the SSH command, install the remote helper, and add the tmux binding. |
| `ssh-bin-paste up` | Host | Configure on first run, then run the paste shortcut listener. |
| `ssh-bin-paste service` `install`/`status`/`restart`/`uninstall` | Host | Service commands for running `ssh-bin-paste up` automatically when you log in. |

## Requirements
**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)\
&nbsp;&nbsp;&nbsp;↓ *SSH*\
**Remote**: `tmux` and Claude Code or Codex

## Coming soon
- Multiple remotes
- Windows/Linux support
