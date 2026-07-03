# PolySphere

A 3D Fibonacci-sphere Alt+Tab application switcher for Hyprland, built with Quickshell + QML and a Guile Scheme MRU daemon.

## Components

| Component | Description |
|---|---|
| `polysphere.qml` | Main 3D app switcher UI (Fibonacci sphere with orbiting satellite detail view) |
| `shell.qml` | Quickshell `PanelWindow` wrapper (WlrLayer.Overlay) |
| `Caching.qml` | XDG path resolution helpers |
| `Scaler.qml` | Resolution-independent DPI scaling |
| `daemon.scm` | Guile Scheme MRU daemon (Unix socket IPC, hyprctl integration) |
| `polysphere.json` | Configuration file |

## Socket

The MRU daemon listens on a Unix domain socket at:

```
$XDG_RUNTIME_DIR/polysphere.sock
```

Typically: `/run/user/1000/polysphere.sock`

Overridable via `--socket` CLI argument or `$POLYSPHERE_SOCKET` environment variable.

## Daemon

```bash
# Start the daemon
guile ~/.config/polysphere/daemon.scm

# Test the socket
echo '{"type":"get_mru"}' | nc -U /run/user/1000/polysphere.sock
```

Add to `~/.config/hypr/hyprland.conf`:
```
exec-once = guile ~/.config/polysphere/daemon.scm
```

## Config

Read from `~/.config/polysphere/polysphere.json`. Override with `$POLYSPHERE_CONFIG`.

## Keyboard Capture (kbd-capture)

⚠️ **PolySphere uses a low-level keyboard capture (`kbd-capture`, written in C) to intercept ALL key events directly from the kernel via evdev.** This is intentional and necessary — Hyprland's keybind system intercepts Alt+letter combinations before QML's built-in `Keys.onPressed` can see them. Without this, typing search queries while holding Alt (e.g., Alt+F, Alt+J) would trigger Hyprland actions (fullscreen, focus movement) instead of reaching the search bar.

kbd-capture:
- Reads raw keystrokes from `/dev/input/event*` devices
- Bypasses Hyprland's keybind processing entirely
- Streams JSON-encoded key events to QML via a stdout pipe
- Is managed as a child Process by the QML overlay (auto-started, auto-restarted)
- Reads its keybinding configuration from `polysphere.json` → `keybindings` block

The keybinding format uses modifier+key syntax:
```json
"keybindings": {
  "toggle": "Alt+Tab",
  "cancel": "Escape",
  "cycleNext": "Tab",
  "cyclePrevious": "Shift+Tab"
}
```

**No Hyprland keybinds are needed for PolySphere operation.** The Hyprland `ALT + Tab` bind in `keymaps.lua` is optional and only used as a fallback IPC trigger — kbd-capture handles all keyboard input directly.

## Testing

See `TESTS.md` for the full test suite.
