#!/usr/bin/env bash
# PolySphere Manual Test Launcher
# Starts the daemon and Quickshell overlay for manual testing.
# After running this script, open the overlay via:
#   quickshell ipc -p shell.qml call polysphere toggle

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SOCKET="/run/user/1000/polysphere.sock"
DAEMON_LOG="/tmp/polysphere-daemon-manual.log"

echo "═══ PolySphere Manual Test Launcher ═══"
echo ""

# Clean up any leftover processes
pkill -f "guile.*daemon.scm" 2>/dev/null || true
pkill -f "quickshell.*shell.qml" 2>/dev/null || true
rm -f "$SOCKET" 2>/dev/null

# Start the daemon
echo "[1/2] Starting daemon..."
cd "$REPO_DIR"
guile daemon.scm --verbose > "$DAEMON_LOG" 2>&1 &
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
echo "To open the overlay, run in another terminal:"
echo "  quickshell ipc -p shell.qml call polysphere toggle"
echo ""
echo "To close everything when done:"
echo "  pkill -f quickshell; pkill -f guile.*daemon; rm -f $SOCKET"
echo ""
echo "Daemon log: $DAEMON_LOG"
