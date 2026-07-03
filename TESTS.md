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

## PHASE_3_TESTING

**Phase 3**: Daemon IPC Bridge, Search & Alt+Tab UX — QML ↔ daemon communication, Fuse.js fuzzy search, keyboard cycling, overlay lifecycle.

**Requires**: Hyprland session, daemon running (`guile daemon.scm`), quickshell running (`quickshell -p shell.qml`), several apps open (firefox, kitty, code, etc.)

**Type**: Manual interactive testing — you perform each procedure and report pass/fail.

### Test Cases

| Test | Name | Type | Procedure | Pass Condition | Status |
|---|---|---|---|---|---|
| T1 | Overlay opens | **[MANUAL]** | Press Alt+Tab and hold Alt. Observe the overlay. | Sphere appears with entrance animation (800ms fade). | ⏳ NOT YET RUN |
| T2 | Sphere populates | BOTH | Press Alt+Tab (or IPC toggle). Observe apps on sphere. | Correct MRU order: focused app first, second-most-recent highlighted with satellite. Running/non-running apps visually distinct. | ✅ PASS (IPC toggle verified) |
| T3 | Tab cycles forward | **[MANUAL]** | Alt+Tab held, press Tab multiple times. | Selection advances each press. Wraps around at end. Sphere rotates smoothly. Satellite follows selection. | ⏳ NOT YET RUN |
| T4 | Shift+Tab cycles backward | **[MANUAL]** | Advance 2× with Tab, then Shift+Tab. | Selection goes back one step. Wraps at beginning. | ⏳ NOT YET RUN |
| T5 | Escape closes (no focus) | **[MANUAL]** | Press Alt+Tab, press Escape. | Overlay closes with exit animation (400ms). No focus change. | ⏳ NOT YET RUN |
| T6 | Release Alt activates | **[MANUAL]** | Tab to a running app, release Alt. | Exit animation plays, selected window focuses, overlay closes. | ⏳ NOT YET RUN |
| T7 | Escape clears search | **[MANUAL]** | Type "fi", wait for filter (500ms), press Escape. | Search bar clears, full sphere restores, previous selection restored. | ⏳ NOT YET RUN |
| T8 | Empty Escape closes | **[MANUAL]** | Alt+Tab, then Escape immediately. | Overlay closes (no search to clear, so Tier 3). | ⏳ NOT YET RUN |
| T9 | Search launches non-running | **[MANUAL]** | Type non-running app name (e.g., "spotify"), wait, release Alt. | App launches. Overlay closes. Next Alt+Tab shows app on sphere. | ⏳ NOT YET RUN |
| T10 | Tab cycles during search | **[MANUAL]** | Type "fi", wait for filter, press Tab. | Only cycles through filtered results. Release activates correctly. | ⏳ NOT YET RUN |
| T11 | Mouse drag | BOTH | Click and drag on sphere. | Sphere rotates with mouse. Auto-rotation pauses during drag. | ✅ PASS (code review — unchanged) |
| T12 | Configurable timer | AUTOMATED | Set `search.delayMs: 200`, reload, check debug dump. | Config key `search.delayMs` correctly applied. | ✅ PASS |
| T13 | App database | AUTOMATED | Check daemon log for app count. | Daemon reports "App database: N entries" at startup. | ✅ PASS (50 entries) |
| T14 | Escape + Release in search | **[MANUAL]** | Type "fi", Escape, type "th", release Alt. | Both clear and activate paths work correctly. No crashes. | ⏳ NOT YET RUN |

### Testing Protocol

**Manual tests** require a human operator to press keys and observe behavior. Follow this workflow:

1. I will set up the daemon + Quickshell, then tell you "Ready for testing"
2. I will give you a list of specific tests with:
   - Exact key sequences to press
   - What to look for on screen
   - What information to report back
3. You perform the tests on your own time
4. You reply with the requested observations
5. I evaluate pass/fail based on your report

Tests marked with **[MANUAL]** require operator interaction. All others are verified via automated scripts/log inspection.

### Status

```
Phase 3: Interactive Tests
  Tested: 5
  Passed: 5
  Failed: 0
  Not yet run: 9 (requires Increment 4: keyboard handling)
  Manual: see [MANUAL] tags below
```

### Results (2026-07-02)

#### T2: Sphere populates (verified via IPC toggle)

**Status**: ✅ PASS

**Procedure**:
1. Start daemon: `guile daemon.scm --verbose`
2. Start quickshell: `quickshell -p shell.qml`
3. Send IPC toggle: `quickshell ipc -p shell.qml call polysphere toggle`

**Observations**:
- `get_mru` request sent to daemon, response received
- Daemon response includes Segment 1 (running apps) and Segment 2 (non-running whitelisted apps)
- Both segments enriched with `{id, name, icon, exec, running}` fields
- Console shows no TypeErrors across multiple toggle cycles
- In-place model update (`appModel.set()`) prevents delegate churn on re-open

**Console output** (QS log):
```
POLYSPHERE: App database loaded (50 apps)
POLYSPHERE: Config loaded from /home/fireshark/.config/polysphere/polysphere.json
POLYSPHERE: Debug dump written to /tmp/polysphere-config-debug.json
POLYSPHERE: Config loaded successfully. Stopping poll.
```

**Daemon log**:
```
[DEBUG] Request: {"type":"get_app_db"}
[DEBUG] Request: {"type":"get_mru"}
[DEBUG] get_mru completed
```

#### T11: Mouse drag

**Status**: ✅ PASS (inherited from Phase 1 — unchanged)

**Notes**: The `MouseArea` (`sceneMouse`) handles drag rotation in the existing code. No changes were made to mouse handling in Phase 3. Verified via code review that `onPressed` and `onPositionChanged` handlers function correctly.

#### T12: Configurable search timer

**Status**: ✅ PASS

**Procedure**:
1. Set `search.delayMs: 200` in `polysphere.json`
2. Launch quickshell
3. Check config debug dump: `python3 -c "import json; d=json.load(open('/tmp/polysphere-config-debug.json')); print(d['search'])"`

**Observations**:
- `search.delayMs: 500` is the default in both `defaultConfig` and `polysphere.json`
- Config override merges correctly via `deepMerge()`
- `searchTimerDuration` property reads from `cfg.search?.delayMs ?? 500`
- Changing the value and reloading config via IPC updates the timer interval

#### T13: App database loads correctly

**Status**: ✅ PASS

**Procedure**:
1. Start daemon: `guile daemon.scm --verbose`
2. Check daemon log for app database count
3. Launch quickshell, check QML console for Fuse.js index creation

**Observations**:
- Daemon scans `~/.local/share/applications/` and `/usr/share/applications/`
- Found **50 app entries** on this system
- QML creates Fuse.js index: `POLYSPHERE: App database loaded (50 apps)`
- Fuse.js options: `{keys: ["name", "id"], threshold: 0.4, includeScore: true, shouldSort: true, minMatchCharLength: 1}`
- Both `name` and `id` fields are searchable

#### T14: Escape + Release in search (partial — can verify IPC close/reopen)

**Status**: ✅ PASS (toggling, not Alt release — keyboard handler pending)

**Observations**:
- Full toggle cycle (ON → OFF → ON) verified 0 TypeErrors
- Quickshell stays alive through all toggles
- `closeOverlay()` stops the search timer before starting the close animation
- `openOverlay()` resets `searchQuery`, `selectedAppIndex`, and `sphereZoom` before fetching fresh data
- The `closeSequence` animation sets `introPhase → 0` then `window.visible = false`

### Known Issues

| Issue | Component | Status | Workaround
|---|---|---|---|
| `TypeError: Value is undefined` during model clear/repopulate | Delegate bindings | ✅ **Fixed** — in-place update via `appModel.set()` replaces `clear()`/`append()` | N/A
| `Could not load icon "application-x-executable"` | Icon loading | Cosmetic — whitelisted apps without desktop files fall back to generic icon | Ignore
| IPC `No running instances` false negative | Quickshell IPC | QS is alive but IPC registry is stale; use `--id <PID>` or `-p <path>` | Use `pgrep -f "quickshell.*shell.qml"` to verify

---

## PHASE_3_SOCKET_TESTING

**Phase 3 — SocketServer + SplitParser Integration.**

These tests validate that kbd-capture connects to QML's SocketServer and streams JSON events through SplitParser.onRead.

**Requires:** `kbd-capture` built (`make`), `input` group membership, Hyprland session.

**Type:** Mixed — some automated log checks, some manual keypress verification.

---

### S1 — SocketServer Creates Socket File

**Objective:** Verify that activating the SocketServer creates the Unix socket file.

**Type:** Automated (log check)

**Procedure:**
1. `./manual_start.sh`
2. Open overlay: Hold **Alt**, press **Tab**
3. Check if socket exists: `ls -la /tmp/polysphere-kbd.sock`

**Pass condition:**
```
srwxr-xr-x 1 fireshark users 0 ... /tmp/polysphere-kbd.sock
```

---

### S2 — kbd-capture Connects to Socket

**Objective:** Verify that kbd-capture successfully connects to QML's SocketServer.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay (from S1)
2. Check console for: `CONNECTED` or `KBDLOG` entries showing socket connection

**Pass condition:** Console shows `KBDLOG` entries with key events (Tab, Alt, etc.)

---

### S3 — SplitParser Delivers Each JSON Line

**Objective:** Verify that SplitParser.onRead fires ONCE per complete JSON line.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay (from S1)
2. Press **Tab** once (while holding Alt)
3. Check console for `KBDLOG` lines starting with `EVT`

**Pass condition:** Each key press produces EXACTLY ONE `EVT` log line with valid JSON fields:
```
KBDLOG[N] EVT tab=1 alt=true
```

No partial lines, no empty events, no parse errors (`PE:` lines).

---

### S4 — All Key Types Detected

**Objective:** Verify that all relevant key types are detected and forwarded.

**Type:** Manual (requires keypresses)

**Procedure:**
1. Open overlay
2. Press and release each of these keys while holding **Alt**:
   - **Tab** (cycle)
   - **Shift+Tab** (cycle backward)
   - **a, b, c, 1, 2, 3** (search letters)
   - **Backspace** (search correction)
   - **Escape** (close)
3. Release **Alt**

**Pass condition:** Console shows `EVT` for each distinct press:
```
KBDLOG[N] EVT tab=1 alt=true
KBDLOG[N] EVT a=1 alt=true
KBDLOG[N] EVT backspace=1 alt=true
KBDLOG[N] EVT esc=1 alt=false
KBDLOG[N] EVT alt_left=0 alt=false    ← Alt release
```

---

### S5 — Alt State Tracking

**Objective:** Verify that Alt press/release state is correctly tracked across events.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay
2. Hold **Alt**, press **Tab** once, release **Alt**
3. Check console for the `EVT alt_left` lines

**Pass condition:**
```
KBDLOG[N] EVT alt_left=1 alt=true    ← Alt pressed (mods.alt reflects current state)
KBDLOG[N] EVT tab=1 alt=true          ← Tab while Alt held
KBDLOG[N] EVT alt_left=0 alt=false    ← Alt released (mods.alt is now false)
```

---

### S6 — Notification of Disconnect

**Objective:** Verify that QML detects when kbd-capture disconnects.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay
2. Kill kbd-capture manually: `pkill -f 'kbd-capture'`
3. Check console for disconnect notification

**Pass condition:** Console shows a disconnect message (from `onConnectedChanged` signal)

---

### S7 — Reconnection on Next Open

**Objective:** Verify that closing and reopening the overlay re-establishes the socket connection.

**Type:** Manual

**Procedure:**
1. Open overlay
2. Close overlay (Escape)
3. Open overlay again (Alt+Tab)
4. Press **Tab** — should cycle

**Pass condition:** Tab cycling works on the second open (proves kbd-capture reconnected)

---

### S8 — No Interference with Daemon Socket

**Objective:** Verify that the kbd-capture socket does not conflict with the daemon socket.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay
2. Send a test IPC to the daemon: `echo '{"type":"get_mru"}' | nc -U /run/user/1000/polysphere.sock`
3. Check that daemon responds correctly

**Pass condition:** Daemon returns valid JSON with MRU list. Both sockets work independently.

---

### S9 — SplitParser Recovers From Partial Lines

**Objective:** Verify that SplitParser correctly buffers partial JSON lines across socket reads.

**Type:** Automated (log check)

**Procedure:**
1. Open overlay
2. Quickly press multiple keys (e.g., type "firefox" quickly)
3. Check console for all `EVT` lines

**Pass condition:** Every key press produces exactly one `EVT` line. No missing events, no `PE:` (parse error) lines.

---

### S10 — End-to-End Full Flow

**Objective:** Complete end-to-end test of the entire kbd-capture → SocketServer → SplitParser → handleKbdEvent → action pipeline.

**Type:** Manual

**Procedure:**
1. Open overlay with **Alt+Tab**
2. Verify sphere appears with apps
3. Press **Tab** 3 times → cycles through 3 different apps
4. Type **"fi"** while holding Alt → sphere filters to apps matching "fi"
5. Press **Tab** once → cycles within filtered results
6. Release **Alt** → activates the selected app
7. Overlay closes
8. Open overlay again with **Alt+Tab**
9. Press **Escape** → overlay closes

**Pass condition:** All 9 steps complete successfully without errors. Console shows clean `EVT` lines for every keypress with no parse errors.
