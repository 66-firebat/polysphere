# PolySphere — App Launcher + Alt+Tab Switcher

## Overview

An Alt+Tab application switcher with a 3D Fibonacci-sphere interface, built on Quickshell + QML. Running apps appear on a rotating 3D sphere, ordered by Most Recently Used (MRU) recency, with non-running whitelisted apps appended as launch targets. A Guile Scheme daemon tracks MRU state and manages window focus via Hyprland IPC.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Hyprland                                                     │
│  bind = Alt+Tab, exec, ~/.config/hypr-comp/scripts/         │
│                     toggle-launcher.sh                       │
└──────────┬──────────────────────────────────────┬───────────┘
           │ Alt+Tab pressed                     │ hyprctl dispatch
           ▼                                      ▲ focuswindow
┌──────────────────────┐        IPC (Unix socket) ┌──────────────────────┐
│ QML Applauncher       │◄────────────────────────►│ Guile Daemon          │
│ (shell.qml +          │   {get_mru, cycle_next,  │ (daemon.scm)          │
│  Applauncher.qml)     │    cycle_prev, activate, │                       │
│                       │    cancel}               │ - MRU list in memory  │
│ Quickshell PanelWindow│                          │ - hyprctl clients     │
│ Overlay layer         │                          │ - hyprctl dispatch    │
└──────────────────────┘                          └──────────────────────┘
```

### Startup

1. **Hyprland `exec-once`** starts the Guile daemon at login
2. Guile daemon initializes empty MRU list, opens Unix socket at `/tmp/hypr-comp.sock`
3. Alt+Tab is bound in Hyprland config via `bind = Alt, Tab, exec, toggle-launcher.sh`

### Alt+Tab Flow

1. User presses **Alt+Tab** (holds Alt)
2. Hyprland runs `toggle-launcher.sh`
3. Script signals QML to open the overlay (e.g., via `kill -USR1` or writing to a status file)
4. QML overlay opens, sends `{"type": "get_mru"}` to the daemon
5. Daemon runs `hyprctl clients`, matches window classes to `.desktop` filenames, builds the ranked app list
6. Daemon responds with `{"mru": [{"id": "firefox", "running": true}, {"id": "kitty", "running": true}, ...], "current": "firefox", "selected": "kitty"}`
   - `current` = the app currently focused (most recent)
   - `selected` = the app to highlight (second most recent)
   - `mru` = full ordered list, each entry is an object with `id` (app identifier) and `running` (boolean indicating if the app has an active window)
7. QML renders the sphere with all MRU apps. `selected` app is highlighted (zoomed/satellite).
8. User presses **Tab** → QML sends `cycle_next` → daemon returns new `selected`
9. User presses **Shift+Tab** → QML sends `cycle_prev` → daemon returns new `selected`
10. User **releases Alt** → QML plays exit fade animation (400ms), then sends `{"type": "activate", "app": "kitty"}`
11. Daemon moves `kitty` to front of MRU, runs `hyprctl dispatch focuswindow class:kitty`
12. QML overlay closes
13. User presses **Escape** → QML sends `{"type": "cancel"}`, overlay closes with fade, no focus change

### App Population Logic

The sphere shows a flat ordered list containing **two segments**:

**Segment 1 — Switching targets** (running apps with active windows):
1. Daemon runs `hyprctl clients`, extracts window `class`, maps to app identifiers
2. Filter the internal MRU list against the running set, preserving MRU order
3. These are the apps the user can **Alt+Tab to** immediately

**Segment 2 — Launch targets** (non-running whitelisted apps):
1. After Segment 1 is built, iterate the `whitelistedApps` list in config order
2. Any whitelisted app that is **not already in Segment 1** is appended with `running: false`
3. Stop when `totalApps` is reached

Both segments are combined into a single flat `mru` array in the response. Each entry is tagged with `running: true` or `running: false` so the QML can render them differently (switching target vs launch target).

---

## Files

### `~/.config/hypr-comp/`
```
polysphere.json          ← Config file (JSON, read by QML via cat + JSON.parse)
daemon.scm               ← Guile Scheme daemon (exec-once from Hyprland)
applauncher.qml          ← Main QML applauncher component (was Applauncher.qml)
shell.qml                ← Quickshell PanelWindow wrapper
Caching.qml              ← Path resolution helpers
Scaler.qml               ← Resolution-independent scaling
MatugenColors.qml        ← Color theme provider
toggle-launcher.sh       ← Script triggered by Hyprland Alt+Tab bind
app_fetcher.py           ← Legacy .desktop scanner (used for initial whitelist app data)
```

### `~/.config/hypr/hyprland.conf` (additions)
```
exec-once = guile ~/.config/hypr-comp/daemon.scm
bind = Alt, Tab, exec, ~/.config/hypr-comp/toggle-launcher.sh
```

---

## Daemon Details (Guile Scheme)

### Socket: `/tmp/hypr-comp.sock`
### Protocol: JSON-over- Unix domain socket, one request-response per message (newline-delimited)

### Requests handled:

| Request | Response | Side effects |
|---|---|---|
| `{"type": "get_mru"}` | `{"mru": [{"id": "...", "running": true}, ...], "current": "...", "selected": "..."}` | Runs `hyprctl clients` to build alive list. Returns enriched entries with running status. |
| `{"type": "cycle_next"}` | `{"selected": "..."}` | Advances selection cursor forward |
| `{"type": "cycle_prev"}` | `{"selected": "..."}` | Advances selection cursor backward |
| `{"type": "activate", "app": "kitty"}` | `{"ok": true}` (running) or `{"ok": false, "reason": "app is not running"}` (non-running) | Updates MRU order, runs `hyprctl dispatch focuswindow class:kitty`. Returns error if app is not running or not in MRU list. |
| `{"type": "cancel"}` | `{"ok": true}` | No-op for daemon |

### MRU Algorithm:
- The MRU list is an in-memory array of app identifiers (desktop filename without `.desktop`)
- On `get_mru`:
  1. Run `hyprctl clients -j` to get the set of running apps
  2. Filter the MRU list against the running set → Segment 1 (switching targets, `running: true`)
  3. Iterate `whitelistedApps` in config order; any app not already in Segment 1 is appended → Segment 2 (launch targets, `running: false`)
  4. Truncate the combined list to `totalApps`
  5. Return enriched objects: `{"id": app, "running": true/false}`
- On `activate`: move activated app to index 0
- Limit: `mru.maxEntries` from config (default 20)

### `hyprctl` usage:
- `hyprctl clients -j` → JSON list of all windows
- `hyprctl activewindow -j` → currently focused window
- `hyprctl dispatch focuswindow class:<class>` → focus a window

---

## Config File (`~/.config/hypr-comp/polysphere.json`)

Full reference with defaults:

```json
{
  "totalApps": 20,
  "whitelistedApps": [
    "firefox.desktop",
    "kitty.desktop",
    "emacs.desktop",
    "ghostty.desktop",
    "code.desktop",
    "spotify.desktop",
    "thunar.desktop",
    "discord.desktop",
    "obsidian.desktop",
    "brave-browser.desktop"
  ],

  "appearance": {
    "overlayOpacity": 0.27,
    "baseSphereRadius": 368,
    "starCount": 50,
    "starOpacityMin": 0.08,
    "starOpacityMax": 0.12,

    "searchBar": {
      "width": 560,
      "height": 56,
      "borderRadius": 28,
      "bottomMargin": 63,
      "borderWidth": 1.5,
      "backgroundOpacity": 0.92,
      "shadowOpacity": 0.4,
      "shadowBlur": 1.5
    },

    "appCard": {
      "width": 74,
      "height": 104,
      "borderRadius": 12,
      "iconSize": 55,
      "fontSize": 11
    }
  },

  "satellite": {
    "hullWidth": 216,
    "hullHeight": 148,
    "panelWidth": 64,
    "panelHeight": 51,
    "strutWidth": 10,
    "strutHeight": 4,
    "antennaHeight": 16,
    "thrusterHeight": 11,
    "iconSize": 40,
    "fontSize": 10
  },

  "sphere": {
    "depthOpacityMultiplier": 4.0,
    "baseScaleAtEdge": 0.78,
    "scaleIncreaseTowardCenter": 0.22,
    "maxTiltAngleX": 45,
    "maxTiltAngleY": 35,
    "hoverScaleMultiplier": 1.12,
    "selectedZoom": 1.65,
    "zoomFactorWeight": 0.45
  },

  "animations": {
    "sphereRotateSpeed": 0.002,
    "sphereAutoRotateIntervalMs": 16,
    "sphereZoomDurationMs": 400,
    "searchRotateDurationMs": 700,
    "cardFadeDurationMs": 200,
    "cardScaleDurationMs": 200,
    "satelliteFadeDurationMs": 400,
    "satelliteScaleDurationMs": 450,
    "satelliteInitialScale": 0.4,
    "satelliteTargetScale": 1.5,
    "entranceFadeDurationMs": 800,
    "exitFadeDurationMs": 400
  },

  "mouse": {
    "dragSensitivity": 0.005,
    "maxRotationAngle": 1.45
  },

  "keybindings": {
    "toggle": "Alt+Tab",
    "cancel": "Escape",
    "cycleNext": "Tab",
    "cyclePrevious": "Shift+Tab"
  },

  "colors": {
    "base": "#1e1e2e",
    "mantle": "#181825",
    "crust": "#11111b",
    "text": "#cdd6f4",
    "subtext0": "#a6adc8",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "overlay0": "#6c7086",
    "blue": "#89b4fa",
    "mauve": "#cba6f7",
    "teal": "#94e2d5",
    "peach": "#fab387",
    "yellow": "#f9e2af",
    "sapphire": "#74c7ec"
  },

  "mru": {
    "maxEntries": 20,
    "updateOnExit": true
  }
}
```

### How the config feeds the code:

The `Applauncher.qml` will read the config at startup via:
```qml
Process {
    command: ["cat", configPath]
    stdout: StdioCollector {
        onStreamFinished: { cfg = JSON.parse(this.text); /* apply to all properties */ }
    }
}
```

Every hardcoded value in the current code (sphere radius, animation durations, colors, font sizes, satellite dimensions, etc.) becomes a property initialized from `cfg.*`, with a fallback default so it degrades gracefully if the file is missing.

---

## Keybindings (Hyprland)

Add to `~/.config/hypr/hyprland.conf`:
```
exec-once = guile ~/.config/hypr-comp/daemon.scm
bind = Alt, Tab, exec, ~/.config/hypr-comp/toggle-launcher.sh
```

The `toggle-launcher.sh` script:
```bash
#!/usr/bin/env bash
# Signal the QML applauncher to open (or toggle its state)
# This communicates via a simple mechanism: writing to a status file
# that the QML Process watcher monitors
STATUS_FILE="/tmp/hypr-comp-launcher.status"
echo "open" > "$STATUS_FILE"
# Or via signal: kill -USR1 $(pidof quickshell) 2>/dev/null
```

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Daemon** | Guile Scheme (3.0.11) | User's preference; real data structures, JSON lib, Unix sockets |
| **IPC** | Unix domain socket, JSON payloads | Simple, no dependencies, language-agnostic |
| **Config** | Pure JSON | QML parses natively; no external parser needed |
| **Window detection** | On-request polling via `hyprctl clients -j` | Simpler than event-driven IPC subscription |
| **MRU persistence** | In-memory only (daemon stays alive) | No file I/O, survives as long as the session |
| **Mouse support** | None | Keyboard-only Alt+Tab switcher |
| **App matching** | Window class → `.desktop` filename | Reliable mapping via Hyprland's window class field |
| **Sphere fill logic** | Running apps (MRU) first, then non-running whitelisted apps appended | Switching targets first, launch targets after; both are always visible on the sphere. Non-running apps are decorated differently by QML. |
| **No search bar** | Removed in Alt+Tab mode | Search bar is for the old app-launcher mode, not for Alt+Tab cycling |
| **Non-running apps** | Included as launch targets, tagged with `running: false` | Users can see and select non-running favorites; QML will launch them instead of focusing (Phase 3+). Cursor cycles through all entries including non-running. |

---

## Implementation Order

1. **Config reader** — Add JSON config loading to `Applauncher.qml`, wire every property
2. **Guile daemon** — Build `daemon.scm` with Unix socket, MRU list, `hyprctl` integration
3. **`toggle-launcher.sh`** — Script to open the overlay from Hyprland bind
4. **Alt+Tab focus tracking** — QML `Keys` handling for Tab/Shift+Tab cycling
5. **Daemon IPC integration** — QML Process + StdioCollector to talk to daemon socket
6. **Exit/activate flow** — Release Alt → fade animation → daemon activate → close
7. **Entrance animation** — Re-enable and re-integrate the entrance fade animation
8. **Remove old code** — Strip search bar, mouse interactions, legacy app_fetcher references
9. **README** — Document setup, config, daemon, and keybindings (at `~/hypr-comp-applauncher/README.md`)
