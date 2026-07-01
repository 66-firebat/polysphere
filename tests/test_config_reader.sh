#!/usr/bin/env bash
# Phase 1 Test Suite — Polysphere Config Reader
#
# Requires: quickshell, Hyprland (or any Wayland compositor), python3
# Run from the repo root:  ./tests/test_config_reader.sh
#
# Each test launches polysphere via shell.qml with $POLYSPHERE_CONFIG set,
# waits for the debug dump, kills quickshell, and diffs against expected JSON.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEBUG_DUMP="/tmp/polysphere-config-debug.json"
PASS=0
FAIL=0
TIMEOUT_SEC=8

cleanup() {
    rm -f "$DEBUG_DUMP"
}
trap cleanup EXIT

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
}

# Deep-merge two JSON files using Python (mirrors QML deepMerge logic)
json_merged() {
    local defaults="$1"
    local overrides="$2"
    python3 -c "
import json, sys
with open('$defaults') as f:
    default = json.load(f)
with open('$overrides') as f:
    overrides = json.load(f)
from copy import deepcopy
merged = deepcopy(default)
def deep_merge(d, o):
    for k, v in o.items():
        if k in d and isinstance(d[k], dict) and isinstance(v, dict):
            deep_merge(d[k], v)
        else:
            d[k] = v
if overrides:
    deep_merge(merged, overrides)
print(json.dumps(merged, indent=2))
"
}

# Run a single test
run_test() {
    local name="$1"
    local config_abs="$2"      # absolute path to config file
    local expected_json="$3"   # the expected merged JSON as a string
    local description="$4"

    echo ""
    echo "─── Test: $name ───"
    echo "  $description"
    echo "  Config: $config_abs"
    echo ""

    # Clean up any prior debug dump
    rm -f "$DEBUG_DUMP"

    # Launch quickshell from the repo root
    cd "$REPO_DIR"
    POLYSPHERE_CONFIG="$config_abs" quickshell -p shell.qml &
    local QS_PID=$!
    echo "  Quickshell PID: $QS_PID"

    # Wait for the debug dump file (poll every 100ms)
    local waited=0
    while [ ! -f "$DEBUG_DUMP" ] && [ $waited -lt $((TIMEOUT_SEC * 10)) ]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    # Kill quickshell
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true

    # Check if debug dump was produced
    if [ ! -f "$DEBUG_DUMP" ]; then
        echo "  ✗ FAIL: Debug dump not produced after ${TIMEOUT_SEC}s"
        FAIL=$((FAIL + 1))
        return
    fi

    # Compare actual vs expected using Python
    local actual
    actual=$(cat "$DEBUG_DUMP")
    if echo "$actual" | python3 -c "
import json, sys
actual = json.load(sys.stdin)
expected = json.loads('''$expected_json''')
# Normalize: sort keys for comparison
def normalize(obj):
    if isinstance(obj, dict):
        return {k: normalize(v) for k, v in sorted(obj.items())}
    elif isinstance(obj, list):
        return [normalize(v) for v in obj]
    return obj
if normalize(actual) == normalize(expected):
    sys.exit(0)
else:
    import difflib
    a_str = json.dumps(normalize(actual), indent=2)
    e_str = json.dumps(normalize(expected), indent=2)
    diff = list(difflib.unified_diff(e_str.splitlines(), a_str.splitlines(),
                                      fromfile='expected', tofile='actual', lineterm=''))
    print('DIFF:')
    for line in diff:
        print(line)
    sys.exit(1)
" 2>&1; then
        echo "  ✓ PASS"
        PASS=$((PASS + 1))
    else
        echo "  ✗ FAIL: Config mismatch (see diff above)"
        FAIL=$((FAIL + 1))
    fi
}

# ------------------------------------------------------------------
# Test Case Data
# ------------------------------------------------------------------

# Read the default config once
DEFAULT_JSON=$(python3 -c "
import json
with open('$REPO_DIR/polysphere.json') as f:
    print(json.dumps(json.load(f), indent=2))
")

# Compute expected merged JSON for full config test
FULL_EXPECTED=$(json_merged "$REPO_DIR/polysphere.json" "$REPO_DIR/tests/config_full.json")

# Compute expected merged JSON for partial config test
PARTIAL_EXPECTED=$(json_merged "$REPO_DIR/polysphere.json" "$REPO_DIR/tests/config_partial.json")

# ------------------------------------------------------------------
# Test Execution
# ------------------------------------------------------------------

banner "Phase 1: Config Reader Tests"

# T1: Full config override
run_test \
    "T1: Full config" \
    "$REPO_DIR/tests/config_full.json" \
    "$FULL_EXPECTED" \
    "Every config key overridden; merged result must match expected"

# T2: Partial config (only 3 top-level keys set)
run_test \
    "T2: Partial config" \
    "$REPO_DIR/tests/config_partial.json" \
    "$PARTIAL_EXPECTED" \
    "Only totalApps, baseSphereRadius, base+text colors set; all else defaults"

# T3: Malformed JSON
run_test \
    "T3: Malformed JSON" \
    "$REPO_DIR/tests/config_malformed.json" \
    "$DEFAULT_JSON" \
    "Invalid JSON should produce fallback to full defaults"

# T4: Missing config file
run_test \
    "T4: Missing config" \
    "/tmp/polysphere-nonexistent-test.json" \
    "$DEFAULT_JSON" \
    "Nonexistent file should produce fallback to full defaults with warning"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
banner "Results"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "✓ All Phase 1 config reader tests passed."
    exit 0
else
    echo "✗ Some tests failed. Review output above."
    exit 1
fi
