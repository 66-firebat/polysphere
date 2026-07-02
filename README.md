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

## Testing

See `TESTS.md` for the full test suite.
