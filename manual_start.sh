#!/usr/bin/env bash
# PolySphere Manual Test Launcher
# Starts the daemon and Quickshell overlay for manual testing.
# After running this script, open the overlay by pressing Alt+Tab
# (Hyprland enters the switcher submap, which routes to QML via IPC).
#
# The submap handles:
#   Tab         → cycle forward
#   Shift+Tab   → cycle backward
#   Escape      → cancel (clear search → close)
#   Alt release → activates selected app (falls through to QML Keys.onReleased)
#
# All global Alt+letter binds (Alt+F fullscreen, Alt+J/K focus, etc.)
# are blocked while the submap is active.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SOCKET="/run/user/1000/polysphere.sock"
DAEMON_LOG="/tmp/polysphere-daemon-manual.log"

echo "═══ PolySphere Manual Test Launcher ═══"
echo ""

# Aggressively kill ALL daemon and quickshell processes
pkill -9 -f "daemon.scm" 2>/dev/null || true
pkill -9 -f "quickshell.*shell.qml" 2>/dev/null || true
rm -f /run/user/1000/polysphere*.sock 2>/dev/null

# Clear Guile's bytecode cache so edits to daemon.scm take effect
find ~/.cache/guile -name "daemon.scm*" -delete 2>/dev/null || true

# Start the daemon (--no-auto-compile ensures we use the latest source)
echo "[1/2] Starting daemon..."
cd "$REPO_DIR"
guile --no-auto-compile daemon.scm --verbose > "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!

# Wait for daemon socket
for i in $(seq 1 10); do
    if [ -S "$SOCKET" ]; then
        echo "      Daemon ready (PID $DAEMON_PID, socket $SOCKET)"
        break
    fi
    sleep 0.5
done

if [ ! -S "$SOCKET" ]; then
    echo "ERROR: Daemon failed to start within 5 seconds"
    exit 1
fi

# Start Quickshell
echo "[2/2] Starting Quickshell overlay (invisible)..."
cd "$REPO_DIR"
quickshell -p shell.qml &
QS_PID=$!
sleep 2

echo ""
echo "═══ Ready for testing ═══"
echo ""
echo "To open/cycle the overlay, press:  Alt+Tab"
echo "  (Hyprland enters the switcher submap and routes to QML via IPC)"
echo ""
echo "While overlay is open:"
echo "  Tab        → cycle forward"
echo "  Shift+Tab  → cycle backward"
echo "  Escape     → cancel (clear search → close)"
echo "  Alt+letter → types into search bar (blocked from global binds by submap)"
echo "  Release Alt → activates selected app"
echo ""
echo "Manual IPC (if submap doesn't work):"
echo "  quickshell ipc -p $REPO_DIR/shell.qml call polysphere toggle"
echo ""
echo "To close everything when done:"
echo "  pkill -f quickshell; pkill -f guile.*daemon; rm -f $SOCKET"
echo ""
echo "Daemon log: $DAEMON_LOG"
