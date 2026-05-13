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
On first run, you will be asked to enter one or more SSH commands for your remotes.

### 3. On the remote, run Claude or Codex and paste a file
```sh
tmux new -s agent
codex # or claude
```
**Paste:** Press `CMD+SHIFT+V` (or your configured shortcut)\
&nbsp;&nbsp;&nbsp;or\
**Drag & drop**

→ The file will be pasted as if being on your host!

## Want it as always-on background service?
`ssh-bin-paste service install` installs a `launchd` (macOS) service.
Windows/Linux support coming soon.

## Commands
| Command | Where | Purpose |
| --- | --- | --- |
| `ssh-bin-paste config` | Host | Set remote SSH commands, install remote helpers, and add tmux bindings. |
| `ssh-bin-paste remotes` | Host | List, add, update, or remove configured remotes. |
| `ssh-bin-paste up` | Host | Configure on first run, then run one paste shortcut listener for all active remotes. |
| `ssh-bin-paste service` `install`/`status`/`restart`/`uninstall` | Host | Service commands for running `ssh-bin-paste up` automatically when you log in. |

## Requirements
**Host**: macOS with Swift available (e.g. via Apple Command Line Tools)\
&nbsp;&nbsp;&nbsp;↓ *SSH*\
**Remote**: `tmux` and Claude Code or Codex

## Coming soon
- Windows/Linux support
