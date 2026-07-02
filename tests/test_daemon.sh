#!/usr/bin/env bash
# Phase 2 Test Suite — PolySphere MRU Daemon
#
# Requires: Guile 3.0.11+, hyprctl, Python 3 (for test harness)
# Run from the repo root:  ./tests/test_daemon.sh
#
# Starts the daemon, sends JSON requests via Python socket client,
# validates responses, and reports pass/fail.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOCKET_PATH="/run/user/1000/polysphere-test-$$.sock"
DAEMON_PID=""
PASS=0
FAIL=0

cleanup() {
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
    rm -f "$SOCKET_PATH"
}
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────

banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
}

# Python-based socket request helper
send_request() {
    local request="$1"
    python3 -c "
import socket, json, sys
try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect('$SOCKET_PATH')
    sock.sendall(b'$request\n')
    response = b''
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        response += chunk
    sock.close()
    # Validate it's parseable JSON
    text = response.decode().strip()
    json.loads(text)
    print(text)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
}

run_test() {
    local name="$1"
    local request="$2"
    local expected="$3"
    local description="$4"

    echo ""
    echo "─── Test: $name ───"
    echo "  $description"
    echo "  Request: $request"

    local result
    result=$(send_request "$request" 2>/dev/null) || {
        echo "  ✗ FAIL: Connection error"
        FAIL=$((FAIL + 1))
        return
    }

    echo "  Response: $result"

    # Compare using Python (deep structural comparison)
    if echo "$result" | python3 -c "
import json, sys
actual = json.load(sys.stdin)
expected = json.loads('$expected')
if actual == expected:
    sys.exit(0)
else:
    print('Expected:', json.dumps(expected, indent=2))
    print('Actual:', json.dumps(actual, indent=2))
    sys.exit(1)
" 2>&1; then
        echo "  ✓ PASS"
        PASS=$((PASS + 1))
    else
        echo "  ✗ FAIL: Response mismatch"
        FAIL=$((FAIL + 1))
    fi
}

# ────────────────────────────────────────────────────────────────
# Start Daemon
# ────────────────────────────────────────────────────────────────

echo "Starting daemon..."
rm -f "$SOCKET_PATH"
guile --no-auto-compile "$REPO_DIR/daemon.scm" \
    --socket "$SOCKET_PATH" \
    --config "$REPO_DIR/tests/config_full.json" \
    > /tmp/daemon-$$.log 2>&1 &
DAEMON_PID=$!

# Wait for socket
for i in $(seq 1 10); do
    if [ -S "$SOCKET_PATH" ]; then
        echo "Daemon started (PID: $DAEMON_PID)"
        break
    fi
    sleep 0.3
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "ERROR: Daemon failed to start"
    cat /tmp/daemon-$$.log
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Test Cases
# ────────────────────────────────────────────────────────────────

banner "Phase 2: Daemon Tests"

# T1: Socket opens
echo ""
echo "─── Test: T1: Socket opens ───"
echo "  Socket file exists at expected path"
if [ -S "$SOCKET_PATH" ]; then
    echo "  ✓ PASS"
    PASS=$((PASS + 1))
else
    echo "  ✗ FAIL"
    FAIL=$((FAIL + 1))
fi

# T2: get_mru with whitelist backfill — enriched entries
echo ""
echo "─── Test: T2: get_mru (whitelist backfill, enriched) ───"
echo "  Validating enriched entry structure (id, running, name, icon, exec)"
python3 "$REPO_DIR/tests/test_t2_enriched.py" "$SOCKET_PATH" 2>&1 && \
    echo "  ✓ PASS" && PASS=$((PASS + 1)) || \
    { echo "  ✗ FAIL"; FAIL=$((FAIL + 1)); }

# T3: cancel
run_test "T3: cancel" \
    '{"type":"cancel"}' \
    '{"ok":true}' \
    "Cancel is a no-op"

# T4: cycle_next on empty list
run_test "T4: cycle_next (empty)" \
    '{"type":"cycle_next"}' \
    '{"selected":null}' \
    "Empty MRU list should return null"

# T5: cycle_prev on empty list
run_test "T5: cycle_prev (empty)" \
    '{"type":"cycle_prev"}' \
    '{"selected":null}' \
    "Empty MRU list should return null"

# T6: activate unknown app
run_test "T6: activate unknown app" \
    '{"type":"activate","app":"nonexistent"}' \
    '{"ok":false,"reason":"app not in MRU list","app":"nonexistent"}' \
    "Unknown app should fail with error"

# T7: activate missing app field
run_test "T7: activate missing app field" \
    '{"type":"activate"}' \
    '{"error":"missing app"}' \
    "Missing app field should return error"

# T8: unknown request type
run_test "T8: unknown request type" \
    '{"type":"bad"}' \
    '{"error":"unknown request type","type":"bad"}' \
    "Unknown type should return error"

# T9: missing type
run_test "T9: missing type" \
    '{"foo":"bar"}' \
    '{"error":"missing type"}' \
    "Missing type should return error"

# T10: malformed JSON
run_test "T10: malformed JSON" \
    'not json' \
    '{"error":"parse error"}' \
    "Malformed JSON should return parse error"

# T11: --help flag
echo ""
echo "─── Test: T11: --help flag ───"
echo "  Running guile daemon.scm --help"
if guile --no-auto-compile "$REPO_DIR/daemon.scm" --help 2>/dev/null | grep -q "PolySphere MRU Daemon"; then
    echo "  ✓ PASS"
    PASS=$((PASS + 1))
else
    echo "  ✗ FAIL"
    FAIL=$((FAIL + 1))
fi

# ────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────

echo ""
banner "Results"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "✓ All Phase 2 daemon tests passed."
    exit 0
else
    echo "✗ Some tests failed. Review output above."
    exit 1
fi
