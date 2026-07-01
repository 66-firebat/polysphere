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
