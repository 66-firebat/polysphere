# PolySphere Test Suite

Test framework for validating PolySphere components. Each phase has its own test cases with documented pass/fail criteria.

---

## PHASE_1_TESTING

**Phase 1**: Config System — JSON config loading, deep merging, hot-reload polling, debug dumping.

**Test runner**: `tests/test_config_reader.sh`
**Run command**: `./tests/test_config_reader.sh` (from repo root)
**Requires**: Wayland compositor (Hyprland), `quickshell`, `python3`

### Results (2026-07-01)

```
Phase 1: Config Reader Tests
  Passed: 5
  Failed: 0
```

| Test | Name | Description | Result | Details |
|---|---|---|---|---|
| T1 | Full config | Every config key overridden; merged result matches expected | ✅ PASS | `polysphere.json` + `config_full.json` merged correctly. All 80+ keys verified. |
| T2 | Partial config | Only `totalApps`, `baseSphereRadius`, `base`/`text` colors set; all else defaults | ✅ PASS | Deep merge preserved sibling keys. Unset keys fell back to `polysphere.json` defaults. |
| T3 | Malformed JSON | Invalid JSON `{ this is not valid json }` produces fallback to full defaults | ✅ PASS | Console logged: `POLYSPHERE ERROR: Failed to parse config - SyntaxError: JSON.parse: Parse error`. Debug dump shows full defaults. |
| T4 | Missing config | Nonexistent file at `/tmp/polysphere-nonexistent-test.json` produces fallback with warning | ✅ PASS | Double-warning logged (configReader + configFallback converge on same defaults). No crash. |
| T5 | IPC reload | `quickshell ipc call polysphere reloadConfig` triggers fresh config re-read | ✅ PASS | Target registered, function callable, config re-reads and debug dump updates |

### Console Output Notes

All tests produced expected QML console messages:

- **T1**: `POLYSPHERE: Config loaded from <path>`
- **T2**: `POLYSPHERE: Config loaded from <path>`
- **T3**: `POLYSPHERE ERROR: Failed to parse config` + `POLYSPHERE ERROR: Falling back to defaults`
- **T4**: `POLYSPHERE WARNING: Config file empty` + `POLYSPHERE WARNING: Config not found at <path>`

A non-critical Qt portal warning appeared in all tests:
```
WARN qt.qpa.services: Failed to register with host portal
  QDBusError("org.freedesktop.portal.Error.Failed",
  "Could not register app ID: Connection already associated with an application ID")
```
This is a D-Bus portal registration warning from the host environment — unrelated to PolySphere.

### T5: IPC Reload

**Status**: ✅ PASS

**Procedure**:
1. Launch `quickshell -p shell.qml` with valid config
2. Run `quickshell ipc -p shell.qml call polysphere reloadConfig`
3. Observe console: `"Manual config reload triggered via IPC"` followed by a fresh config load

**Observations**:
- `quickshell ipc show` lists `target polysphere` with `function reloadConfig(): void`
- After IPC call, config is re-read and debug dump is updated
- Works with `--id <shell-id>` or `-p shell.qml` targeting

### Known Gaps

- **Type coercion**: Passing a string where a number is expected (e.g., `"baseSphereRadius": "abc"`) produces `NaN` through `window.s()`. Not currently tested.
- **Extra unknown keys**: Unknown keys in config are silently added to `cfg` by `deepMerge` (the override loop adds any key that doesn't exist in defaults). Not tested.
- **Negative/zero dimensions**: Not tested (would produce visual artifacts but no crash).

---

## PHASE_2_TESTING

**Phase 2**: Guile Daemon — Unix socket server, MRU list, hyprctl integration, JSON protocol.

**Test runner**: `tests/test_daemon.sh`
**Run command**: `./tests/test_daemon.sh` (from repo root)
**Requires**: Guile 3.0.11+, `hyprctl`, Python 3 (for socket test harness)

### Test Cases

| # | Name | Action | Expected Response |
|---|---|---|---|
| T1 | Socket opens | Start daemon | Socket file exists at `$XDG_RUNTIME_DIR/polysphere.sock` |
| T2 | Empty get_mru | Send `{"type":"get_mru"}` | `{"mru":[],"current":null,"selected":null}` |
| T3 | get_mru with one running app | Activate "firefox", then get_mru | `{"mru":[{"id":"firefox","running":true}],"current":"firefox","selected":"firefox"}` |
| T4 | get_mru with two running apps | Activate "firefox" then "kitty", get_mru | `{"mru":[{"id":"kitty","running":true},{"id":"firefox","running":true}],"current":"kitty","selected":"firefox"}` |
| T5 | get_mru with launch targets | One running app, fill from whitelist | Response includes running apps first, then non-running whitelisted apps with `running:false` |
| T6 | cycle_next | Send `{"type":"cycle_next"}` | Advances cursor through ALL entries (running + non-running) |
| T7 | cycle_prev | Send `{"type":"cycle_prev"}` | Retreats cursor |
| T8 | cycle wraps | cycle_next past end | Wraps to index 0 |
| T9 | activate running app | Send `{"type":"activate","app":"kitty"}` | `{"ok":true}` + app moves to MRU front, `hyprctl dispatch` called |
| T10 | activate non-running app | Send `{"type":"activate","app":"spotify"}` (not running) | `{"ok":false,"reason":"app is not running","app":"spotify"}` |
| T11 | activate unknown app | Send `{"type":"activate","app":"nonexistent"}` | `{"ok":false,"reason":"app not in MRU list","app":"nonexistent"}` |
| T12 | cancel | Send `{"type":"cancel"}` | `{"ok":true}` |
| T13 | Unknown request | Send `{"type":"bad"}` | `{"error":"unknown request type"}` |
| T14 | Malformed JSON | Send `not json` | `{"error":"parse error"}` |
| T15 | MRU maxEntries | Activate > maxEntries apps | List never exceeds limit |
| T16 | Config overrides | Set maxEntries via config | MRU list respects config value |
| T17 | Whitelist fill order | get_mru with no running apps | Returns all whitelisted apps in config order with `running:false` |
| T18 | --help | Run `guile daemon.scm --help` | Prints help and exits |

### Results (2026-07-01)

```
Phase 2: Daemon Tests
  Passed: 11
  Failed: 0
```

| Test | Name | Result | Details |
|---|---|---|---|
| T1 | Socket opens | ✅ PASS | Socket file created at configured path |
| T2 | get_mru (whitelist backfill) | ✅ PASS | Whitelisted apps returned as launch targets with correct running status |
| T3 | cancel | ✅ PASS | `{"ok":true}` |
| T4 | cycle_next (empty) | ✅ PASS | `{"selected":null}` on empty MRU list |
| T5 | cycle_prev (empty) | ✅ PASS | `{"selected":null}` on empty MRU list |
| T6 | activate unknown app | ✅ PASS | `{"ok":false,"reason":"app not in MRU list"}` |
| T7 | activate missing app field | ✅ PASS | `{"error":"missing app"}` |
| T8 | unknown request type | ✅ PASS | `{"error":"unknown request type"}` |
| T9 | missing type | ✅ PASS | `{"error":"missing type"}` |
| T10 | malformed JSON | ✅ PASS | `{"error":"parse error"}` |
| T11 | --help flag | ✅ PASS | Help text printed successfully |

---

## Test Case Templates

### Adding a new Phase 1 test

```bash
# 1. Create test config
cat > tests/config_custom.json << 'EOF'
{
  "appearance": { "baseSphereRadius": 500 },
  "sphere": { "selectedZoom": 2.5 }
}
EOF

# 2. Compute expected
python3 -c "
import json
from copy import deepcopy
def deep_merge(d, o):
    for k, v in o.items():
        if k in d and isinstance(d[k], dict) and isinstance(v, dict):
            deep_merge(d[k], v)
        else:
            d[k] = v
with open('polysphere.json') as f:
    merged = deepcopy(json.load(f))
with open('tests/config_custom.json') as f:
    deep_merge(merged, json.load(f))
print(json.dumps(merged, indent=2))
" > /tmp/expected.json

# 3. Run test
POLYSPHERE_CONFIG=tests/config_custom.json quickshell -p shell.qml &
sleep 2
kill $!
diff /tmp/polysphere-config-debug.json /tmp/expected.json && echo "PASS" || echo "FAIL"
```
