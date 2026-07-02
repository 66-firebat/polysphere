# PolySphere Phase 3 Handoff

## Context

The daemon (`daemon.scm`) is fully updated with Phase 3 features:
- **`get_app_db`**: Returns all installed apps with `{id, name, icon, exec}` (scanned from .desktop files at startup)
- **`track_launch`**: Adds a launched app to MRU without checking `hyprctl`
- **Enriched MRU entries**: Every entry now includes `name`, `icon`, `exec` fields from the app database

All 11 daemon tests pass. `lib/fuse.js` (67KB, QML-compatible) is ready at `lib/fuse.js`.

What remains is **all QML-side work** in `polysphere.qml` (1032 lines), plus a few small files.

---

## Files to Create

### 1. `toggle-launcher.sh`

One-liner IPC call to open the overlay:

```bash
#!/usr/bin/env bash
quickshell ipc -p ~/.config/polysphere/shell.qml call polysphere toggle
```

Make executable (`chmod +x`).

### 2. `tests/test_get_app_db.sh` (optional but recommended)

A quick automated test that sends `{"type":"get_app_db"}` to the daemon and validates the structure (same pattern as `test_t2_enriched.py`).

---

## Files to Modify

### 3. `polysphere.json` — Add search config

Add this block anywhere in the JSON (I recommend after the `animations` block):

```json
"search": {
    "delayMs": 500
}
```

### 4. `polysphere.qml` — Major rewrite of interaction and data layers

This is the main work. Below are ALL the changes needed, organized by section.

---

## Detailed `polysphere.qml` Changes

### 4.1 — Imports (top of file)

**Current imports (lines 1-8):**
```
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
```

**Add after line 6:**
```qml
import "lib/fuse.js" as FuseJs
```

Note: The `lib/` directory is relative to the repo root. When polysphere.qml is deployed at `~/.config/polysphere/polysphere.qml`, the import path should also find `lib/fuse.js`. For development, ensure the import path resolves correctly.

### 4.2 — Config additions (add to `defaultConfig`)

In the `defaultConfig` property (around line 28-85), add after the `mru` block:

```qml
"search": {
    "delayMs": 500
}
```

### 4.3 — App database state (add after `cfg` property, around line 85)

Add these state variables:

```
property var appDatabase: []           // full app list from daemon
property var fuseIndex: null           // Fuse.js instance
property var currentMruList: []        // last get_mru response's mru array
property int savedSelectionIndex: -1   // selection to restore on Escape
property int searchTimerDuration: cfg.search?.delayMs ?? 500
property bool altHeld: false
property bool tabWasPressed: false
property string daemonSocket: {
    var envSocket = Quickshell.env("POLYSPHERE_SOCKET");
    if (envSocket) return envSocket;
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
    return (runtimeDir || "/tmp") + "/polysphere.sock";
}
```

### 4.4 — Fuse.js options (after state variables)

```
readonly property var fuseOptions: ({
    keys: ["name", "id"],
    threshold: 0.4,
    includeScore: true,
    shouldSort: true,
    minMatchCharLength: 1
})
```

### 4.5 — Daemon IPC bridge

Add a `Process` + helper function. This should replace the old `appFetcher` Process (currently around lines 454-467).

**Remove this block (legacy appFetcher):**
```qml
Process {
    id: appFetcher
    running: true
    command: ["bash", "-c", "python3 " + paths.qsDir + "/applauncher/app_fetcher.py"]
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                if (this.text && this.text.trim().length > 0) {
                    window.allApps = JSON.parse(this.text);
                    let apps  = window.allApps;
                    let chunk = 40;
                    let idx   = 0;
                    function appendChunk() {
                        let end = Math.min(idx + chunk, apps.length);
                        for (; idx < end; idx++) appModel.append(apps[idx]);
                        if (idx < apps.length) Qt.callLater(appendChunk);
                        else { window.projDirty = true; window.rebuildProjCache(); }
                    }
                    appendChunk();
                }
            } catch(e) { console.log("POLYSPHERE: appFetcher error -", String(e)); }
        }
    }
}
```

**Replace with:**
```qml
function daemonRequest(type, extraData, callback) {
    var msg = JSON.stringify(Object.assign({type: type}, extraData || {}));
    var escaped = msg.replace(/'/g, "'\\''");
    daemonProcess.command = [
        "bash", "-c",
        "echo '" + escaped + "' | nc -U " + daemonSocket
    ];
    daemonProcess._callback = callback;
    daemonProcess.running = false;
    daemonProcess.running = true;
}

Process {
    id: daemonProcess
    running: false
    property var _callback: null
    stdout: StdioCollector {
        onStreamFinished: {
            var txt = this.text.trim();
            if (txt.length > 0) {
                try {
                    var response = JSON.parse(txt);
                    if (daemonProcess._callback) {
                        daemonProcess._callback(response);
                    }
                } catch(e) {
                    console.log("POLYSPHERE: Daemon parse error:", String(e));
                }
            }
        }
    }
}
```

### 4.6 — Search timer (add after daemonProcess)

```qml
Timer {
    id: searchTimer
    interval: searchTimerDuration
    running: false
    repeat: false
    onTriggered: executeSearch()
}
```

### 4.7 — Load app database at startup

Add a `Component.onCompleted` handler (or use `Timer` with `triggeredOnStart: true`) that calls:

```qml
function loadAppDatabase() {
    daemonRequest("get_app_db", {}, function(response) {
        if (response.apps) {
            appDatabase = response.apps;
            try {
                fuseIndex = new FuseJs.Fuse(appDatabase, fuseOptions);
                console.log("POLYSPHERE: App database loaded (" + appDatabase.length + " apps)");
            } catch(e) {
                console.log("POLYSPHERE: Fuse init error:", String(e));
            }
        }
    });
}
```

### 4.8 — Search functions (add after loadAppDatabase)

```qml
function handleSearchInput(text) {
    searchQuery = text;
    searchTimer.running = false;
    searchTimer.running = true;
}

function executeSearch() {
    if (searchQuery === "") {
        restoreFullSphere();
        return;
    }

    if (!fuseIndex) return;

    var results = fuseIndex.search(searchQuery);
    var topResults = results.slice(0, cfg.totalApps || 20);

    populateSearchResults(topResults);

    if (searchModel.count > 0) {
        selectedAppIndex = 0;
        centerOnApp(0);
        sphereZoom = sphereSelectedZoom;
    }
}

function populateSearchResults(fuseResults) {
    searchModel.clear();

    var runningIds = {};
    for (var i = 0; i < currentMruList.length; i++) {
        if (currentMruList[i].running) {
            runningIds[currentMruList[i].id] = true;
        }
    }

    var running = [];
    var nonRunning = [];
    for (var j = 0; j < fuseResults.length; j++) {
        var item = fuseResults[j].item;
        if (runningIds[item.id]) {
            running.push(item);
        } else {
            nonRunning.push(item);
        }
    }

    for (var k = 0; k < running.length; k++) {
        searchModel.append(running[k]);
    }
    for (var l = 0; l < nonRunning.length; l++) {
        searchModel.append(nonRunning[l]);
    }
}

function restoreFullSphere() {
    searchModel.clear();
    for (var i = 0; i < currentMruList.length; i++) {
        searchModel.append(currentMruList[i]);
    }
    window.selectedAppIndex = savedSelectionIndex >= 0 ? savedSelectionIndex : 0;
    window.sphereZoom = 1.0;
    if (window.selectedAppIndex >= 0) {
        centerOnApp(window.selectedAppIndex);
    }
}
```

### 4.9 — Alt+Tab Key handling (add after restoreFullSphere)

This replaces the old `Shortcut` for Escape. Remove the old `Shortcut` (line ~305) and the `Connections` block (line ~308-317), and replace with:

```qml
Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
        altHeld = true;
        event.accepted = true;
    }

    if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.AltModifier)) {
        tabWasPressed = true;
        var dir = (event.key === Qt.Key_Tab) ? "cycle_next" : "cycle_prev";
        daemonRequest(dir, {}, function(r) {
            if (r.selected) updateSelection(r.selected);
        });
        event.accepted = true;
    }

    if (!event.isAutoRepeat && event.text.length > 0 && event.text.match(/[a-zA-Z0-9]/)) {
        searchInput.text += event.text;
        searchInput.forceActiveFocus();
        event.accepted = true;
    }
}

Keys.onReleased: (event) => {
    if (event.key === Qt.Key_Alt) {
        altHeld = false;
        if (tabWasPressed) {
            triggerActivate();
        }
        event.accepted = true;
    }
}
```

### 4.10 — Escape handler (tiered)

Replace the old `Shortcut { sequence: "Escape" ... }` with:

```qml
Shortcut {
    sequence: cfg.keybindings?.cancel ?? "Escape"
    onActivated: handleEscape()
}

function handleEscape() {
    if (searchInput.text.length > 0) {
        searchInput.text = "";
        searchQuery = "";
        searchTimer.running = false;
        restoreFullSphere();
    } else {
        daemonRequest("cancel", {}, function(r) {
            closeOverlay();
        });
    }
}
```

### 4.11 — Overlay lifecycle

Add these functions:

```qml
function openOverlay() {
    window.visible = true;
    window.altHeld = false;
    window.tabWasPressed = false;
    window.searchQuery = "";
    searchInput.text = "";
    savedSelectionIndex = window.selectedAppIndex;
    window.sphereZoom = 1.0;

    daemonRequest("get_mru", {}, function(response) {
        if (response.mru) {
            currentMruList = response.mru;
            populateSphereFromMru(response);
        }
    });

    if (fuseIndex === null && appDatabase.length === 0) {
        loadAppDatabase();
    }

    introPhaseAnim.restart();
    searchInput.forceActiveFocus();
}

function closeOverlay() {
    closeSequence.start();
}

function populateSphereFromMru(response) {
    appModel.clear();
    for (var i = 0; i < response.mru.length; i++) {
        appModel.append(response.mru[i]);
    }
    window.selectedAppIndex = -1;

    if (response.selected) {
        for (var j = 0; j < response.mru.length; j++) {
            if (response.mru[j].id === response.selected) {
                window.selectedAppIndex = j;
                window.selectedAppName = response.mru[j].name || "";
                window.selectedAppIcon = response.mru[j].icon || "";
                window.selectedAppExec = response.mru[j].exec || "";
                centerOnApp(j);
                break;
            }
        }
    }

    window.sphereZoom = 1.0;
    window.projDirty = true;
    window.rebuildProjCache();
}

function updateSelection(selectedId) {
    for (var i = 0; i < appModel.count; i++) {
        if (appModel.get(i).id === selectedId) {
            window.selectedAppIndex = i;
            window.selectedAppName = appModel.get(i).name || "";
            window.selectedAppIcon = appModel.get(i).icon || "";
            window.selectedAppExec = appModel.get(i).exec || "";
            centerOnApp(i);
            break;
        }
    }
}

function triggerActivate() {
    var idx = window.selectedAppIndex;
    if (idx < 0 || idx >= appModel.count) return;
    var entry = appModel.get(idx);
    if (!entry) return;

    if (entry.running) {
        daemonRequest("activate", {app: entry.id}, function(r) {
            if (r.ok) closeOverlay();
        });
    } else {
        Quickshell.execDetached(["bash", "-c", entry.exec || entry.id]);
        daemonRequest("track_launch", {app: entry.id}, function(r) {});
        closeOverlay();
    }
}
```

### 4.12 — ListModel for search

Add a second `ListModel` alongside the existing `appModel`:

```qml
ListModel { id: appModel }
ListModel { id: searchModel }     // ADD THIS
```

The search system populates `searchModel` instead of `appModel` when search is active. The sphere's `Repeater` needs to use whichever model is active. **Design decision**: either switch the Repeater's model between `appModel` and `searchModel`, or always use `searchModel` and copy `appModel` into it when search is cleared. The simplest approach: always use `appModel` but clear/repopulate it from search results during search. This way the sphere Repeater doesn't need changes.

### 4.13 — IpcHandler toggle

The existing IpcHandler (lines ~169-178 in the current file) needs a `toggle()` function added:

```qml
IpcHandler {
    target: "polysphere"

    function reloadConfig(): void {
        // existing code...
    }

    function toggle(): void {
        if (window.visible) {
            closeOverlay();
        } else {
            openOverlay();
        }
    }
}
```

### 4.14 — Remove legacy close sequence reference

The `closeSequence` SequentialAnimation currently has:
```qml
ScriptAction { script: Quickshell.execDetached(["bash", paths.serpantinumDir + "/scripts/qs_manager.sh", "close"]) }
```

Replace with:
```qml
ScriptAction { script: { window.visible = false; } }
```

### 4.15 — TextField search input

The existing `searchInput` TextField needs its `onTextChanged` handler updated to call `handleSearchInput(text)` instead of the old `handleSearch(text)`. Remove `Keys.onDownPressed`, `Keys.onUpPressed`, and `Keys.onReturnPressed` from the TextField (those will be handled by the global Keys.onPressed).

### 4.16 — Remove old `handleSearch` function

Delete the old `handleSearch` function (currently around lines 469-490).

### 4.17 — Remove old `launchApp` function

Delete the old `launchApp` function (currently around lines 492-497). It's replaced by `triggerActivate()`.

---

## Key Subtleties

1. **Import path for Fuse.js**: When running from the repo (`quickshell -p shell.qml`), the relative import `"lib/fuse.js"` resolves from the file's directory. File is at `./lib/fuse.js` relative to repo root, and `polysphere.qml` is at `./polysphere.qml`. So `"lib/fuse.js"` should work. If not, use absolute path or copy fuse.js next to polysphere.qml.

2. **Two models**: The sphere Repeater should always use `appModel`. During search, `executeSearch()` clears `appModel` and repopulates it with filtered results. `restoreFullSphere()` clears `appModel` and repopulates from `currentMruList`. This avoids having to switch the Repeater's model binding (which can cause binding loops).

3. **Cycle during search**: Tab cycling should work on `appModel` regardless of whether it's in search mode or full mode. The `cycle_next`/`cycle_prev` requests go to the daemon regardless. The `updateSelection` function finds the app by ID in `appModel` — this works for both modes.

4. **Daemon cursor sync**: With `track_launch`, the daemon's MRU cursor is always at position 1 after any launch. When the user opens the overlay again, `get_mru` returns the updated cursor. This means `updateSelection` must handle the case where the daemon's `selected` app isn't in the current `appModel` (during search). If not found, keep current selection.

5. **`window.visible`**: The shell.qml's Loader loads polysphere.qml. The overlay visibility is controlled by `window.visible = true/false` on the root Item. This works because PanelWindow respects child Item visibility.

6. **Intro animation on reopen**: The `introPhaseAnim` should restart on every `openOverlay()` call. The existing `NumberAnimation on introPhase` runs at component creation. On subsequent opens, the `Connections { onVisibleChanged }` handler restarts it — but that was for the old model. In the new model, `openOverlay()` explicitly calls `introPhaseAnim.restart()`.

---

## Testing After Implementation

Run through the manual tests in TESTS.md PHASE_3_TESTING (T1–T14). The daemon automated tests should still all pass (`bash tests/test_daemon.sh`).

---

## Files That Need NO Changes

| File | Reason |
|---|---|
| `daemon.scm` | Fully updated with get_app_db, track_launch, enriched entries |
| `lib/fuse.js` | Ready and tested (67KB, QML-compatible) |
| `Caching.qml` | Not part of Phase 3 |
| `Scaler.qml` | Not part of Phase 3 |
| `shell.qml` | No changes needed (already has Loader for polysphere.qml) |
| `README.md` | Update at end of phase |
| `PLAN.md` | Not part of Phase 3 |
| `PHASE_2.md` | Completed |
| `PHASE_1.md` | Completed |
| `tests/test_daemon.sh` | Updated with T2 enriched entry validation |
| `tests/test_t2_enriched.py` | Python helper for T2 |

---

## Summary

The daemon is ready. The remaining work is entirely in `polysphere.qml`:

1. Add Fuse.js import + search config to defaultConfig
2. Replace `appFetcher` Process with `daemonProcess` IPC bridge
3. Add search system (Fuse index, debounce timer, executeSearch)
4. Add Alt+Tab key handling (Keys.onPressed/onReleased)
5. Add IpcHandler `toggle()` function
6. Add overlay lifecycle functions (openOverlay, closeOverlay, triggerActivate)
7. Add tiered Escape handler
8. Remove old code: `handleSearch`, `launchApp`, `qs_manager.sh` reference, legacy `Shortcut`
9. Update `searchInput` TextField to new search model
10. Create `toggle-launcher.sh`
11. Update `polysphere.json` with `search.delayMs`
12. Run manual tests T1–T14

Expected total: ~400-500 lines added, ~100 lines removed from polysphere.qml. About 2-4 hours of work depending on debugging.
