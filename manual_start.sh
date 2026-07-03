#!/usr/bin/env bash
# PolySphere Manual Test Launcher
# Starts the daemon and Quickshell overlay for manual testing.
# After running this script, open the overlay via:
#   quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere toggle
#
# Hyprland intercepts Alt+Tab before QML can see it, so cycling is done
# via IPC. Use "cycle" for the Hyprland bind:
#   hl.bind("ALT + Tab", function()
#       hl.dispatch(hl.dsp.exec_cmd(
#           "quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere cycle"
#       ))
#   end
#
# First press opens the overlay. Subsequent presses cycle forward.
# Releasing Alt activates the selected app (Alt key reaches QML fine).

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

# Build kbd-capture if needed
echo "[1/3] Building kbd-capture..."
cd "$REPO_DIR"
if [ ! -x "lib/kbd-capture" ] || [ "lib/kbd-capture.c" -nt "lib/kbd-capture" ]; then
    gcc -O2 -o lib/kbd-capture lib/kbd-capture.c && echo "      Build OK" || echo "      Build FAILED (kbd-capture will not work)"
else
    echo "      Already up to date"
fi

# Start the daemon (--no-auto-compile ensures we use the latest source)
echo "[2/3] Starting daemon..."
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
echo "[3/3] Starting Quickshell overlay (invisible)..."
cd "$REPO_DIR"
quickshell -p shell.qml &
QS_PID=$!
sleep 2

echo ""
echo "═══ Ready for testing ═══"
echo ""
echo "To open/cycle the overlay, run in another terminal:"
echo "  quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere cycle"
echo ""
echo "To close it:"
echo "  quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere toggle"
echo ""
echo "To close everything when done:"
echo "  pkill -f quickshell; pkill -f guile.*daemon; rm -f $SOCKET"
echo ""
echo "Daemon log: $DAEMON_LOG"
