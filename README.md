# PolySphere

A 3D Fibonacci-sphere Alt+Tab application switcher for Hyprland, built with Quickshell + QML and a Guile Scheme MRU daemon.

## Components

| Component | Description |
|---|---|
| Component | Description |
|---|---|
| `polysphere.qml` | Main 3D app switcher UI (Fibonacci sphere with orbiting satellite detail view) |
| `shell.qml` | Quickshell `PanelWindow` wrapper (WlrLayer.Overlay) |
| `Scaler.qml` | Resolution-independent DPI scaling |
| `daemon.scm` | Guile Scheme MRU daemon (Unix socket IPC, hyprctl integration) |
| `lib/kbd-capture.c` | Raw evdev keyboard capture (C) — intercepts keys before Hyprland |
| `polysphere.json` | Configuration file |
| `Makefile` | Build system (compiles kbd-capture) |

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

> **⚠️ PREREQUISITE: You MUST be in the `input` user group for kbd-capture to work.**
> Without this, kbd-capture falls back to "snoop mode" where Hyprland ALSO receives
> the key events, and Alt+letter binds will fire instead of reaching the search bar.
>
> ```bash
> sudo usermod -a -G input $USER  # then log out and back in
> groups $USER                    # verify 'input' appears
> ```

kbd-capture:
- Reads raw keystrokes from `/dev/input/event*` devices
- Uses `EVIOCGRAB` to exclusively capture the keyboard (prevents Hyprland from seeing the keys)
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

## Building

### Prerequisites

- C compiler (gcc)
- Linux kernel headers (for `linux/input.h`)
- `input` user group membership (see kbd-capture section above)

### Build

```bash
# Build kbd-capture only
make

# Or compile manually
gcc -O2 -o lib/kbd-capture lib/kbd-capture.c
```

The build is automatically handled by `manual_start.sh` — it checks if the source is newer than the binary and recompiles if needed.

### Installation (for system-wide use)

To deploy PolySphere outside the repo:

```bash
# 1. Build kbd-capture
make

# 2. Copy files to config directory
mkdir -p ~/.config/polysphere
cp polysphere.qml shell.qml Scaler.qml ~/.config/polysphere/
cp polysphere.json ~/.config/polysphere/
cp daemon.scm ~/.config/polysphere/
cp lib/kbd-capture lib/fuse.js ~/.config/polysphere/lib/

# 3. Add to Hyprland config
# exec-once = guile ~/.config/polysphere/daemon.scm
# bind = ALT, Tab, exec, quickshell -p ~/.config/polysphere/shell.qml
```

## Troubleshooting: UI Freeze / Unresponsive Desktop

If the desktop becomes unresponsive or clicks don't work after running PolySphere, a test process may have been left running:

```bash
# Kill any leftover PolySphere processes
kill -9 $(pgrep -f "daemon.scm") 2>/dev/null
kill -9 $(pgrep -f "shell.qml") 2>/dev/null
kill -9 $(pgrep -f "kbd-capture") 2>/dev/null
rm -f /tmp/polysphere-kbd.sock /run/user/1000/polysphere.sock 2>/dev/null
```

After running these commands, the UI should return to normal immediately.

## Testing

See `TESTS.md` for the full test suite.
