# AeroFlow

**A lightweight, config-driven tiling window manager for macOS.**

AeroFlow is a performance-focused fork of [OmniWM](https://github.com/OmniNull/OmniWM) (GPL-2.0-only). It strips out every piece of UI — no settings window, no menu-bar item, no update popups, no sponsor cards — and leaves a headless daemon you configure with a single TOML file and drive with a CLI. Think Hyprland for macOS: the config file *is* the interface.

## Features

- **Two layout engines per workspace** — Niri-style orientation-aware scrolling containers (columns left/right, rows up/down, tabbed) and Hyprland-style Dwindle BSP
- **Workspaces** with per-monitor assignment and cross-monitor routing
- **Window rules** — match by bundle ID / app name / title (substring or regex) / AX role; float, pin to a workspace, set min size and initial span
- **Full IPC/CLI** — `aeroflowctl`: commands, window/workspace/display/rule queries, live event subscriptions, `watch --exec` for scripting (SketchyBar, yabai-style tooling)
- **Gaps** per monitor (inner + outer), single-window fit, mouse warp
- **Hyper key** (⌃⌥⇧⌘) and mouse/trackpad gestures (right-drag + Option to resize)
- **Keep Awake** (caffeine-style), window restore across restarts, native window-tab groups
- **Refresh-rate-aware animations**, SIP stays on

## Requirements

- Apple Silicon, macOS 15 (Sequoia) or later — tested on Sequoia and Tahoe (macOS 26)
- **Accessibility** and **Input Monitoring** permissions
- System Settings → Desktop & Dock → Mission Control → **Displays have separate Spaces: ON**

## Installation

### Homebrew (recommended)

```sh
brew install frostymur/aerofi/aeroflow
brew services start aeroflow
```

The formula builds from source (needs Xcode Command Line Tools) and
installs the `AeroFlow` daemon plus the `aeroflowctl` CLI into your
PATH. `brew upgrade aeroflow` updates it.

### From a GitHub release

Releases are ad-hoc signed (no Apple Developer ID). Install with the
helper script, which downloads the latest release, places the app in
`~/Applications` and removes the quarantine flag:

```sh
curl -fsSL https://raw.githubusercontent.com/frostymur/OmniWM/main/install.sh | bash
```

If you download the `.zip` yourself: `xattr -cr "/Applications/AeroFlow.app"` before first launch.

### From source

```sh
git clone https://github.com/frostymur/OmniWM.git aero-flow
cd aero-flow
./Scripts/package-app.sh release dev   # ad-hoc signed, no Apple account needed
open dist/AeroFlow.app
```

On first launch the app shows an onboarding window asking for
Accessibility access; it starts tiling as soon as it is granted.

Install one of the three, not several — only one AeroFlow can run at a
time (the launch conflict gate waits for the other to exit).

### Permissions after updates

Without a Developer ID, replacing the app resets TCC permissions. After every update (or rebuild) re-grant **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security.

## Configuration

Everything lives in one file:

```
~/.config/aeroflow/settings.toml          # release builds
~/.config/aeroflow-dev/settings.toml      # dev builds
```

Edit it while the app is running — changes apply live. Main sections:

| Section | What it controls |
|---|---|
| `[general]` | animations, IPC, keep awake, hyper key |
| `[appearance]` | light/dark mode |
| `[gaps]`, `[gaps.outer]` | inner/outer gaps (per-monitor overrides below) |
| `[niri]`, `[dwindle]` | layout engine defaults |
| `[focus]` | focus follow / crossing behaviour |
| `[gestures]` | trackpad scroll + mouse-move/resize modifiers |
| `[mouseWarp]`, `[routing]` | pointer warp across monitors |
| `[[workspaces]]` | workspace names, monitor assignment, layout |
| `[[hotkeys]]` | key bindings (`binding = "Hyper+H"`, `id = "focus.left"`) |
| `[[appRules]]` | window rules (see below) |

**Gaps** — Hyprland-style model: `gaps_in` lives between windows, `gaps_out`
reaches the screen edge. A single window is inset by the outer gap only
(`singleWindowFit = "gapped"` — the default); `"fill"` still makes it edge-to-edge.

```toml
[gaps]
size = 16.0                  # gaps_in  — between windows
fullscreenUsesOuterGaps = false   # fullscreen ignores gaps by default

[gaps.outer]                 # gaps_out — tiling area vs screen edges
left = 12.0
right = 12.0
top = 8.0                    # measured from below the menu bar
bottom = 12.0
```

The same rules apply in both layouts (niri and dwindle) and on both axes:
windows never grow an extra inner gap at the tiling-area boundary — the edge
margin is always `[gaps.outer]` alone.

**Hotkeys** — every command is bindable:

```toml
[[hotkeys]]
binding = "Hyper+H"
id = "focus.left"

[[hotkeys]]
binding = "Hyper+Shift+H"
id = "move.left"
```

**Window rules** — Hyprland-style rule matching:

```toml
[[appRules]]
bundleId = "com.apple.Terminal"
layout = "float"

[[appRules]]
titleRegex = ".* — VS Code"
assignToWorkspace = "2"
minWidth = 800
minHeight = 500
```

Rules can also be managed at runtime: `aeroflowctl rule add|replace|remove|move|apply` (see `aeroflowctl help`).

## CLI — `aeroflowctl`

The app installs `aeroflowctl` into your `PATH` (`~/.local/bin`) on first launch. Highlights:

```sh
aeroflowctl ping                                  # is the daemon alive?
aeroflowctl command focus left                    # window management
aeroflowctl command switch-workspace 2
aeroflowctl command move-to-workspace 3
aeroflowctl command toggle-workspace-layout       # niri <-> dwindle

aeroflowctl query windows --focused --fields id,app,title,frame
aeroflowctl query workspaces --current
aeroflowctl query displays --fields name,frame,inner-gap

aeroflowctl subscribe windows-changed --format ndjson
aeroflowctl watch focus --exec /path/to/my/statusbar-hook
aeroflowctl completion zsh                        # shell completions
```

`aeroflowctl help` lists every command, query, selector and field.

## Launch at login

Register a LaunchAgent for the installed app:

```sh
cat > ~/Library/LaunchAgents/com.frostymur.AeroFlow.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.frostymur.AeroFlow</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/AeroFlow.app/Contents/MacOS/AeroFlow</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.frostymur.AeroFlow.plist
```

## Development

```sh
swift build                      # compile
swift test                       # run the test suite (requires Xcode, not just CLT)
./Scripts/package-app.sh release dev
```

Dev builds use `com.frostymur.AeroFlow.dev` and the `aeroflow-dev` config/state directories, so they can run side by side with a release install.

## Upstream

AeroFlow started from [OmniWM](https://github.com/OmniNull/OmniWM) by [OmniNull](https://github.com/OmniNull) and the contributors — thank you. Upstream continues to be a full-featured app (website, settings UI, sponsor program) at <https://omniwm.app>; AeroFlow intentionally diverges: headless, minimal, config-first. GPL-2.0-only applies to both.
