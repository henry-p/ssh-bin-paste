# Demo GIF generation

This records the real product flow: a host terminal runs `ssh-bin-paste up`, a normal SSH session connects to the remote, the user attaches an existing remote `tmux` session running Codex or Claude, and the host paste shortcut sends a local clipboard payload into the focused remote agent pane.

The demo should show product usage only. Do not include tests, install logs, or repo maintenance commands.

## Requirements

- macOS with iTerm2.
- `ffmpeg` and `gifsicle`.
- `ssh-bin-paste` installed and configured.
- A remote reachable by your normal SSH command, for example `ssh example-remote`.
- Remote `tmux` and either Codex or Claude Code.

## 1. Prepare a local clipboard payload

Use any supported local file or image. For a repeatable image demo:

```sh
DEMO_DIR=/tmp/ssh-bin-paste-demo
mkdir -p "$DEMO_DIR"

cat > "$DEMO_DIR/source.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1040">
  <defs>
    <linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0%" stop-color="#00a6a6"/>
      <stop offset="100%" stop-color="#f2c94c"/>
    </linearGradient>
  </defs>
  <rect width="1800" height="1040" fill="url(#g)"/>
  <text x="900" y="430" text-anchor="middle" font-family="Menlo, monospace" font-size="120" fill="white" font-weight="700">ssh-bin-paste</text>
  <text x="900" y="555" text-anchor="middle" font-family="Menlo, monospace" font-size="54" fill="white">real clipboard image</text>
  <text x="900" y="720" text-anchor="middle" font-family="Menlo, monospace" font-size="42" fill="white">copied on host -&gt; pasted into remote agent</text>
</svg>
SVG

ffmpeg -y -i "$DEMO_DIR/source.svg" "$DEMO_DIR/source.png"
osascript -e "set the clipboard to POSIX file \"$DEMO_DIR/source.png\""
```

## 2. Create the local tmux recording layout

Use stacked panes so the font can be very large while each pane keeps enough horizontal space. The labels make the host and remote roles obvious.

```sh
SESSION=ssh-bin-paste-demo
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n DEMO -c "$HOME"
tmux split-window -v -t "$SESSION:0"
tmux resize-pane -t "$SESSION:0.0" -y 9
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format ' #[bold]#{pane_title} '
tmux set-option -t "$SESSION" status on
tmux set-option -t "$SESSION" status-left '#[bold] ssh-bin-paste demo '
tmux set-option -t "$SESSION" status-right '#[bold] host clipboard -> remote agent over SSH '
tmux select-pane -t "$SESSION:0.0" -T 'HOST: ssh-bin-paste up'
tmux select-pane -t "$SESSION:0.1" -T 'REMOTE: SSH + tmux attach + agent'
tmux select-pane -t "$SESSION:0.0"
```

Open a fresh iTerm2 window in `~`, attach this local recording session, and zoom in heavily with `Cmd`+`+` so both panes are very large and readable:

```sh
tmux attach -t ssh-bin-paste-demo
```

After zooming, resize the iTerm2 window back inside the visible monitor before recording. This matters because iTerm2 may grow the window while increasing font size, and `screencapture -l` will faithfully capture the cropped off-screen window.

One repeatable shape is:

```applescript
tell application "System Events"
  tell process "iTerm2"
    set position of front window to {80, 60}
    set size of front window to {1500, 920}
  end tell
end tell
```

## 3. Find the iTerm2 window id

Save this temporary helper:

```sh
cat > /tmp/list-iterm-windows.swift <<'SWIFT'
import CoreGraphics
import Foundation

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.contains("iTerm") else { continue }

    let number = window[kCGWindowNumber as String] ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    let bounds = window[kCGWindowBounds as String] ?? [:]
    print("\(number)\t\(owner)\t\(name)\t\(bounds)")
}
SWIFT

swift /tmp/list-iterm-windows.swift
```

Use the window id for the fresh iTerm2 demo window.

## 4. Record the exact window

Start the macOS exact-window recording:

```sh
WINDOW_ID=12345
MOV=/tmp/ssh-bin-paste-demo/ssh-bin-paste-demo.mov
screencapture -x -v -V 95 -l "$WINDOW_ID" "$MOV"
```

While recording, perform this flow:

```sh
# HOST pane
ssh-bin-paste up

# REMOTE pane
ssh example-remote
tmux attach -t agent-demo
```

The remote `tmux attach` step is mandatory in the demo because `tmux` is required for focused-pane detection.

Then focus the remote agent pane and press your configured paste shortcut, for example `CMD+SHIFT+V`.

The host pane should show the upload progress bar after the shortcut is detected.

Ask the agent to describe the received image:

```text
describe this image
```

Stop after the agent response is visible.

## 5. Cut idle time

Cut waiting time after the agent has started and trim the idle tail after the response is readable. Keep interactions at normal speed; remove only dead time.

```sh
MOV=/tmp/ssh-bin-paste-demo/ssh-bin-paste-demo.mov
CUT=/tmp/ssh-bin-paste-demo/ssh-bin-paste-demo-cut.mov

ffmpeg -y -i "$MOV" \
  -filter_complex "[0:v]trim=start=0:end=11,setpts=PTS-STARTPTS[v0];[0:v]trim=start=14:end=24,setpts=PTS-STARTPTS[v1];[0:v]trim=start=30:end=40,setpts=PTS-STARTPTS[v2];[v0][v1][v2]concat=n=3:v=1:a=0[v]" \
  -map "[v]" -an "$CUT"
```

Adjust the timestamps for the actual recording. The final GIF should show SSH, remote `tmux attach`, upload progress, and the agent response without long idle gaps.

## 6. Convert the recording to the repo GIF

```sh
MOV=/tmp/ssh-bin-paste-demo/ssh-bin-paste-demo-cut.mov
GIF=docs/ssh-bin-paste-demo.gif
PALETTE=/tmp/ssh-bin-paste-demo/palette.png

ffmpeg -y -i "$MOV" \
  -vf "fps=8,scale=1100:-1:flags=lanczos,palettegen=stats_mode=diff" \
  "$PALETTE"

ffmpeg -y -i "$MOV" -i "$PALETTE" \
  -lavfi "fps=8,scale=1100:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  "$GIF"

gifsicle -O3 "$GIF" -o "$GIF"
```

## 7. README embed

Use this Markdown:

```md
![ssh-bin-paste demo](docs/ssh-bin-paste-demo.gif)
```

## Cleanup

```sh
tmux kill-session -t ssh-bin-paste-demo 2>/dev/null || true
ssh example-remote 'tmux kill-session -t agent-demo 2>/dev/null || true'
```
