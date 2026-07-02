# Phase 3: Daemon IPC Bridge, Search & Alt+Tab UX

**Goal:** Wire the QML overlay to the Guile daemon, implement the full Alt+Tab interaction loop with keyboard-driven cycling, integrate Fuse.js fuzzy search, and remove all legacy code. Everything works end-to-end.

**Dependencies:** Phase 1 (config system), Phase 2 (Guile daemon), Fuse.js v7.0.0 (bundled at `lib/fuse.js`)

---

## 1. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Hyprland                                                              │
│  exec-once = guile daemon.scm                                        │
│  bind = Alt+Tab, exec, toggle-launcher.sh                            │
└──────────┬────────────────────────────────────────────────┬──────────┘
           │ Alt+Tab pressed                               │ hyprctl dispatch
           ▼                                                ▲ focuswindow
┌──────────────────────────┐   IPC (Unix socket)   ┌────────────────────┐
│ polysphere.qml            │◄─────────────────────►│ daemon.scm          │
│                           │   get_mru, get_app_db │                     │
│  ┌───────────────────┐   │   activate, cancel    │  ┌───────────────┐  │
│  │ Tab cycling       │   │   track_launch        │  │ MRU List      │  │
│  │ (local via        │   │                       │  │ App Database  │  │
│  │  appModel index)  │   │                       │  │ (desktop scan)│  │
│  └───────────────────┘   │                       │  └───────────────┘  │
│                           │                       │                     │
│  IpcHandler "polysphere"  │                       │                     │
│    toggle(), reloadConfig │                       │                     │
└──────────────────────────┘                       └─────────────────────┘
         ▲
         │ quickshell ipc call polysphere toggle
         ▼
┌──────────────────┐
│ toggle-launcher.sh│
│ IPC call to QML  │
└──────────────────┘
```

### Design Note: Local Tab Cycling vs Daemon `cycle_next`

**Problem:** The daemon's internal MRU list only tracks apps that have been activated at least once (via `hyprctl` focus events). The `get_mru` response backfills non-running whitelisted apps to produce the full combined list shown on the sphere. But `cycle_next`/`cycle_prev` only iterate through daemon's **internal** list, which may be much smaller than what's visible.

**Solution:** Tab/Shift+Tab cycling is handled **locally in QML** by advancing `selectedAppIndex` through `appModel` (the visible ListModel). This ensures:
- ALL entries cycle through — running apps AND non-running launch targets
- During search, only filtered results are cycled
- No IPC round-trip needed for every Tab press

The daemon's `cycle_next`/`cycle_prev` handlers still exist (Phase 2) but are no longer used by the QML overlay. They remain for potential future use by other clients.

### Data Flow

```
toggle-launcher.sh
  │ quickshell ipc call polysphere toggle
  ▼
IpcHandler.toggle()
  │ sets overlay.visible = true
  │ sends get_mru + get_app_db to daemon
  ▼
Daemon returns mru list + app database
  │
  ├─ Sphere populated with MRU entries (running + launch targets)
  ├─ Fuse.js cache populated with all apps
  └─ Search bar focused, waiting for input

User presses Tab
  │
  ├─ QML cycles locally: selectedAppIndex = (selectedAppIndex + 1) % appModel.count
  ├─ No daemon communication needed — cycles through whatever is visible
  └─ Sphere highlights new selection

User types "thun"
  │
  ├─ searchTimer resets on each keystroke
  ├─ After 500ms, Fuse.js searches local cache
  ├─ Sphere rerenders with filtered results (top 20)
  └─ First result is auto-selected

User presses Escape
  │
  ├─ searchBar has text? → clear text, restore full sphere, restore prev selection
  ├─ searchBar empty? → send cancel to daemon, close overlay

User releases Alt
  │
  ├─ running app? → send activate, daemon focuses window, close overlay
  ├─ non-running app? → Quickshell.execDetached(exec), send track_launch, close overlay
```

---

## 2. Files

### New Files

| File | Purpose |
|---|---|
| `lib/fuse.js` | Fuse.js v7.0.0 bundled for QML (68KB, `.pragma library`) |
| `toggle-launcher.sh` | Quickshell IPC call to open overlay (replaces legacy stub) |

### Modified Files

| File | Changes |
|---|---|
| **`polysphere.qml`** | Daemon IPC bridge, search system, Alt+Tab key handling, legacy code removal. Major rewrite. |
| **`daemon.scm`** | ✅ **Already done** — `get_app_db`, `track_launch`, enriched MRU entries all implemented and tested |
| **`polysphere.json`** | Add `search.delayMs` config key (default 500ms) |
| **`tests/test_daemon.sh`** | ✅ **Already done** — tests for `get_app_db` and `track_launch` added |
| **`TESTS.md`** | Add PHASE_3_TESTING with manual procedures |

### Deleted References

From `polysphere.qml`:
- `paths.qsDir + "/applauncher/app_fetcher.py"` (appFetcher Process — line 454)
- `paths.qsDir + "/applauncher/app_fetcher.py"` (launchApp logging — line 508)
- `paths.serpantinumDir + "/scripts/qs_manager.sh"` (close sequence — line 440)
- `Caching { id: paths }` instantiation and all `paths.*` references
- `import Qt5Compat.GraphicalEffects` (removed in Phase 1)
- `import QtQuick.Window` (removed in Phase 1)
- `import "../"` (removed in Phase 1)

**Deleted from repo:**
- `Caching.qml` — replaced by inline `daemonSocket` resolution in `polysphere.qml`

---

## 3. Daemon Changes

### 3.1 New Request: `get_app_db`

**Purpose:** Return all installed apps for Fuse.js search indexing.

**Daemon behavior:** On startup, scan `~/.local/share/applications/` and `/usr/share/applications/` for `.desktop` files. Parse `Name`, `Icon`, `Exec`, and `NoDisplay` fields. Cache the full database in memory.

```
Request:  {"type":"get_app_db"}
Response: {
  "apps": [
    {"id":"firefox","name":"Firefox","icon":"firefox","exec":"firefox %u"},
    {"id":"code","name":"Code","icon":"code","exec":"code"},
    {"id":"gimp","name":"GIMP","icon":"gimp","exec":"gimp %f"},
    ...
  ]
}
```

| Field | Source | Description |
|---|---|---|
| `id` | .desktop filename without `.desktop` | Unique identifier, matches window class |
| `name` | `Name=` field from .desktop | Display name for search and rendering |
| `icon` | `Icon=` field from .desktop | Icon name for `image://icon/` |
| `exec` | `Exec=` field from .desktop | Shell command to launch |

**Caching:** Scan once at startup. The daemon can also accept a `SIGHUP` to re-scan if new apps are installed.

### 3.2 New Request: `track_launch`

**Purpose:** Add a newly-launched app to the MRU list without checking `hyprctl` (used after launching a non-running app from search).

```
Request:  {"type":"track_launch","app":"gimp"}
Response: {"ok":true}
Side effects:
  - Adds "gimp" to front of MRU list (index 0)
  - Truncates to maxEntries
  - Sets cursor to index 1
  - Does NOT call hyprctl (app may not be running yet)
```

### 3.3 Enriched MRU Entries

The `get_mru` response enriches each entry with full app metadata from the cached app database. Each entry becomes:

```json
{"id":"firefox","running":true,"name":"Firefox","icon":"firefox","exec":"firefox %u"}
```

Fields `name`, `icon`, and `exec` come from the daemon's cached `.desktop` scan. If an app is in the MRU list but its `.desktop` file wasn't found (e.g., a running window whose class doesn't match any `.desktop` file), the missing fields fall back to:

| Field | Fallback |
|---|---|
| `name` | The `id` itself |
| `icon` | `"application-x-executable"` |
| `exec` | The `id` itself |

### 3.4 Config Additions

`polysphere.json` gains no new keys — the existing `polysphere.json` schema already has everything. The daemon already reads `mru.maxEntries`, `whitelistedApps`, and `totalApps`.

The search timer is read by QML from `cfg` (the existing config system from Phase 1), and will come from a new config key:

```json
{
  ...
  "search": {
    "delayMs": 500
  }
}
```

---

## 4. QML Changes (`polysphere.qml`)

### 4.1 New Imports

```qml
// fuse.js is a .pragma library, imported like a JS module
import "lib/fuse.js" as FuseJs
```

### 4.2 Daemon IPC Bridge

A `Process` + `StdioCollector` pair sends requests to the daemon via `nc -U`:

```qml
//////////////
// Daemon IPC
//////////////

property string daemonSocket: {
    var envSocket = Quickshell.env("POLYSPHERE_SOCKET");
    if (envSocket) return envSocket;
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
    return (runtimeDir || "/tmp") + "/polysphere.sock";
}

function daemonRequest(type, extraData, callback) {
    var msg = JSON.stringify(Object.assign({type: type}, extraData || {}));
    daemonProcess.command = [
        "bash", "-c",
        "echo '" + msg.replace(/'/g, "'\\''") +
        "' | nc -U " + daemonSocket
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

### 4.3 Search System

```qml
//////////////
// Search system
//////////////

property var appDatabase: []          // full app list from daemon
property var fuseIndex: null          // Fuse.js instance
property string searchQuery: ""
property int savedSelectionIndex: -1  // selection to restore on Escape
property int searchTimerDuration: cfg.search?.delayMs ?? 500

// Fuse.js options
readonly property var fuseOptions: ({
    keys: ["name", "id"],
    threshold: 0.4,
    includeScore: true,
    shouldSort: true,
    minMatchCharLength: 1
})

// Called once on startup to get the app database
function loadAppDatabase() {
    daemonRequest("get_app_db", {}, function(response) {
        if (response.apps) {
            appDatabase = response.apps;
            fuseIndex = new FuseJs.Fuse(appDatabase, fuseOptions);
            console.log("POLYSPHERE: App database loaded (" + appDatabase.length + " apps)");
        }
    });
}

// Search timer — resets on each keystroke
Timer {
    id: searchTimer
    interval: searchTimerDuration
    running: false
    repeat: false
    onTriggered: executeSearch()
}

// Called on every keystroke in the search bar
function handleSearchInput(text) {
    searchQuery = text;
    searchTimer.running = false;
    searchTimer.running = true;  // reset debounce timer
}

// Performs the actual search
function executeSearch() {
    if (searchQuery === "") {
        // Clear search — restore full sphere
        restoreFullSphere();
        return;
    }
    
    if (!fuseIndex) return;
    
    var results = fuseIndex.search(searchQuery);
    var topResults = results.slice(0, cfg.totalApps || 20);
    
    // Rebuild the sphere model with search results
    // Order: running apps first (from current MRU), then by Fuse score
    populateSearchResults(topResults);
    
    // Auto-select the first result
    if (appModel.count > 0) {
        selectedAppIndex = 0;
        centerOnApp(0);
        sphereZoom = sphereSelectedZoom;
    }
}

function populateSearchResults(fuseResults) {
    appModel.clear();
    
    // Build a set of running app IDs from the last get_mru response
    var runningIds = {};
    for (var i = 0; i < currentMruList.length; i++) {
        if (currentMruList[i].running) {
            runningIds[currentMruList[i].id] = true;
        }
    }
    
    // Segment 1: running apps from search results
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
    
    // Segment 2: non-running apps, sorted by Fuse score
    for (var k = 0; k < running.length; k++) {
        appModel.append(running[k]);
    }
    for (var l = 0; l < nonRunning.length; l++) {
        appModel.append(nonRunning[l]);
    }
}

// Restore the sphere to the daemon's MRU list
function restoreFullSphere() {
    appModel.clear();
    // Repopulate from last get_mru response
    for (var i = 0; i < currentMruList.length; i++) {
        appModel.append(currentMruList[i]);
    }
    // Restore previous selection
    window.selectedAppIndex = savedSelectionIndex;
    window.sphereZoom = 1.0;
    if (savedSelectionIndex >= 0) {
        centerOnApp(savedSelectionIndex);
    }
}
```

### 4.4 Alt+Tab Key Handling

```qml
Item {
    id: window
    focus: true
    visible: false  // controlled by IpcHandler.toggle()
    
    property bool altHeld: false
    property bool tabWasPressed: false
    
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
            altHeld = true;
            event.accepted = true;
        }
        
        // Tab/Shift+Tab cycles through the visible appModel, NOT the daemon's MRU.
        // This ensures ALL entries (running + non-running whitelisted)
        // are cycled through, not just the daemon's internal MRU list.
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.AltModifier)) {
            tabWasPressed = true;
            if (appModel.count > 0) {
                var dir = (event.key === Qt.Key_Tab) ? 1 : -1;
                var nextIndex = (window.selectedAppIndex + dir + appModel.count) % appModel.count;
                selectByIndex(nextIndex);
            }
            event.accepted = true;
        }
        
        // Letter characters → search bar
        if (!event.isAutoRepeat && event.text.length > 0 && event.text.match(/[a-zA-Z0-9]/)) {
            searchInput.text += event.text;
            searchInput.forceActiveFocus();
            event.accepted = true;
        }
    }
    
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Alt) {
            altHeld = false;
            // Only activate if Tab was pressed during this Alt hold
            if (tabWasPressed) {
                triggerActivate();
            }
            event.accepted = true;
        }
    }
    
    function triggerActivate() {
        var entry = getSelectedEntry();
        if (!entry) return;
        
        if (entry.running) {
            daemonRequest("activate", {app: entry.id}, function(r) {
                if (r.ok) closeOverlay();
            });
        } else {
            // Launch non-running app
            Quickshell.execDetached(["bash", "-c", entry.exec]);
            // Track in MRU so it appears on next Alt+Tab
            daemonRequest("track_launch", {app: entry.id}, function(r) {});
            closeOverlay();
        }
    }
    
    function updateSelection(selectedId) {
        // Find the app in the current model and highlight it
        for (var i = 0; i < appModel.count; i++) {
            if (appModel.get(i).id === selectedId) {
                window.selectedAppIndex = i;
                window.selectedAppName = appModel.get(i).name;
                window.selectedAppIcon = appModel.get(i).icon || "";
                window.selectedAppExec = appModel.get(i).exec || "";
                centerOnApp(i);
                break;
            }
        }
    }
}
```

### 4.5 IpcHandler (Toggle)

The existing `IpcHandler` from Phase 1 gains a `toggle()` function and becomes the bridge for the shell script:

```qml
IpcHandler {
    target: "polysphere"
    
    function reloadConfig(): void { ... }  // existing from Phase 1
    function toggle(): void {
        if (window.visible) {
            closeOverlay();
        } else {
            openOverlay();
        }
    }
}
```

### 4.6 Overlay Lifecycle

```qml
function openOverlay() {
    window.visible = true;
    window.altHeld = false;
    window.tabWasPressed = false;
    window.searchQuery = "";
    searchInput.text = "";
    
    // Save previous selection index
    savedSelectionIndex = window.selectedAppIndex;
    
    // Fetch fresh data from daemon
    daemonRequest("get_mru", {}, function(response) {
        if (response.mru) {
            currentMruList = response.mru;
            populateSphereFromMru(response);
        }
    });
    
    introPhaseAnim.restart();
    searchInput.forceActiveFocus();
}

function closeOverlay() {
    closeSequence.start();
    // closeSequence animates introPhase to 0, then hides
}

function populateSphereFromMru(response) {
    appModel.clear();
    for (var i = 0; i < response.mru.length; i++) {
        appModel.append(response.mru[i]);
    }
    window.selectedAppIndex = -1;
    
    // Set selected from daemon's response
    if (response.selected) {
        for (var j = 0; j < response.mru.length; j++) {
            if (response.mru[j].id === response.selected) {
                window.selectedAppIndex = j;
                window.selectedAppName = response.mru[j].name;
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
```

### 4.7 Escape Key Tiers

```qml
Shortcut {
    sequence: cfg.keybindings?.cancel ?? "Escape"
    onActivated: handleEscape()
}

function handleEscape() {
    if (searchInput.text.length > 0) {
        // Tier 1: Clear search, restore full sphere
        searchInput.text = "";
        searchQuery = "";
        searchTimer.running = false;
        restoreFullSphere();
    } else {
        // Tier 3: Close overlay (cancel)
        daemonRequest("cancel", {}, function(r) {
            closeOverlay();
        });
    }
}
```

### 4.8 Config Additions

Add to `polysphere.json`:
```json
{
  ...
  "search": {
    "delayMs": 500
  }
}
```

Add to `defaultConfig` in `polysphere.qml`:
```qml
"search": {
    "delayMs": 500
}
```

### 4.9 Legacy Code Removal

**Removed from polysphere.qml:**

1. The entire `appFetcher` Process (was lines ~446-467) — replaced by `daemonProcess` + `daemonRequest()`
2. The `handleSearch` function — replaced by new Fuse.js search system with `handleSearchInput()` + `executeSearch()`
3. The `launchApp` function — replaced by `triggerActivate()` which uses daemon `activate`/`track_launch` or direct `execDetached`
4. The `closeSequence`'s `ScriptAction` calling `qs_manager.sh` — replaced by `window.visible = false`
5. The old `Shortcut` for Escape — replaced by tiered `handleEscape()` (clear search → close overlay)
6. All `paths.*` references to `app_fetcher.py`, `qs_manager.sh`, and the `Caching { id: paths }` instantiation

**Removed from repo:**
- `Caching.qml` — no longer needed; `daemonSocket` resolution is inline in `polysphere.qml`
- `tests/config_daemon.json` (no longer needed — already using `config_full.json`)
- Any remaining references to `MatugenColors`, `app_fetcher`, `qs_manager`

---

## 5. `toggle-launcher.sh`

```bash
#!/usr/bin/env bash
# Open/close the PolySphere overlay via Quickshell IPC
quickshell ipc -p ~/.config/polysphere/shell.qml call polysphere toggle
```

Hyprland config:
```
bind = Alt, Tab, exec, ~/.config/polysphere/toggle-launcher.sh
```

---

## 6. Search Architecture (Detailed Flow)

### Startup

```
1. QML loads polysphere.qml
2. Component.onCompleted fires
3. daemonRequest("get_app_db", {}, callback) → fetches ALL apps
4. callback creates Fuse.js index from appDatabase
5. Ready for search
```

### Typing

```
1. User presses 't' → searchInput.text = "t"
2. handleSearchInput("t") → resets searchTimer
3. User presses 'h' → searchInput.text = "th" → searchTimer resets
4. User presses 'u' → searchInput.text = "thu" → searchTimer resets
5. User pauses typing
6. 500ms elapses → searchTimer fires → executeSearch()
7. Fuse.js searches appDatabase with keys ["name", "id"], threshold 0.4
8. Results sorted by Fuse score
9. Running apps (from last get_mru) sorted first, then non-running by score
10. Top 20 results populate the sphere
11. First result is auto-selected and zoomed
```

### Escape

```
1. User presses Escape
2. searchInput.text.length > 0 → clear text
3. restoreFullSphere() → repopulate from currentMruList
4. savedSelectionIndex is restored
5. User presses Escape again
6. searchInput.text.length === 0 → daemonRequest("cancel") → closeOverlay()
```

---

## 7. Fuse.js Configuration

The Fuse.js instance is created with:

```javascript
{
    keys: ["name", "id"],          // Search against display name and app ID
    threshold: 0.4,                // 0.0 = exact match, 1.0 = match anything
    includeScore: true,            // Return relevance score for sorting
    shouldSort: true,              // Sort by score
    minMatchCharLength: 1,         // Single character matches
    isCaseSensitive: false         // Case-insensitive search
}
```

**Why threshold 0.4?** At this level:
- "thun" matches "Thunar File Manager" ✅
- "fi" matches "Firefox" ✅
- "vsc" does NOT match "Visual Studio Code" (threshold too low for acronym — this is acceptable; user can type "visual" or "code")
- False positives are minimal

The threshold can be tuned later by adding it to the config.

---

## 8. Daemon `track_launch` Handler Implementation

```scheme
(define (handle-track-launch app)
  "Handle a track_launch request — add app to MRU without hyprctl check."
  (log-verbose (string-append "Handling track_launch for " app))
  (mru-push-front app)
  (log-msg "INFO" (string-append "Tracked launch of " app))
  (scm->json-string (make-ok-response)))
```

---

## 9. Daemon `get_app_db` Handler Implementation

The daemon scans `.desktop` files at startup and caches them:

```scheme
(define %desktop-paths
  '("~/.local/share/applications"
    "/usr/share/applications"
    "/usr/local/share/applications"))

(define app-database '())  ;; populated at startup

(define (scan-desktop-files)
  "Scan all .desktop files and build the app database."
  (set! app-database
    (append-map
      (lambda (dir)
        (let ((expanded (string-append (getenv "HOME") (substring dir 1))))
          (if (file-exists? expanded)
              (map (lambda (f) (parse-desktop-file (string-append expanded "/" f)))
                   (filter (lambda (f) (string-suffix? ".desktop" f))
                           (or (scandir expanded) '())))
              '())))
      %desktop-paths))
  ;; Filter out #f entries (failed parses, NoDisplay=true)
  (set! app-database (filter (lambda (e) (and e (assoc-ref e "name"))) app-database))
  (log-msg "INFO" (string-append "App database: " (number->string (length app-database)) " entries")))

(define (parse-desktop-file path)
  "Parse a .desktop file and return an alist with id, name, icon, exec."
  (catch #t
    (lambda ()
      (call-with-input-file path
        (lambda (port)
          (let loop ((line (read-line port)) (in-desktop-entry #f) (name #f) (icon #f) (exec #f) (no-display #f))
            (if (eof-object? line)
                (if (and name (not no-display))
                    (let ((id (path->id path)))
                      `(("id" . ,id) ("name" . ,name) ("icon" . ,(or icon "application-x-executable")) ("exec" . ,(or exec name))))
                    #f)
                (let* ((trimmed (string-trim-both line))
                       (section (if (and (> (string-length trimmed) 0) (eq? #\[ (string-ref trimmed 0)))
                                    (string-trim-both trimmed #\[ #\]) #f)))
                  (cond
                   (section (loop (read-line port) (string=? section "Desktop Entry") name icon exec no-display))
                   ((not in-desktop-entry) (loop (read-line port) #f name icon exec no-display))
                   (else
                    (let* ((eq-pos (string-index trimmed #\=))
                           (key (if eq-pos (string-trim-right (substring trimmed 0 eq-pos)) ""))
                           (val (if eq-pos (string-trim (substring trimmed (1+ eq-pos))) "")))
                      (cond
                       ((string=? key "Name") (loop (read-line port) #t val icon exec no-display))
                       ((string=? key "Icon") (loop (read-line port) #t name val exec no-display))
                       ((string=? key "Exec") (loop (read-line port) #t name icon val no-display))
                       ((string=? key "NoDisplay") (loop (read-line port) #t name icon exec (or (string=? val "true") no-display)))
                       (else (loop (read-line port) #t name icon exec no-display)))))))))))
    (lambda (key . args)
      (log-error (string-append "Failed to parse " path))
      #f)))

(define (path->id path)
  "Extract app ID from .desktop file path."
  (let* ((basename (basename path))
         (without-ext (if (string-suffix? ".desktop" basename)
                          (string-drop-right basename (string-length ".desktop"))
                          basename)))
    without-ext))

(define (handle-get-app-db)
  "Handle a get_app_db request."
  (log-verbose "Handling get_app_db")
  (let* ((apps-vec (list->vector app-database))
         (response `(("apps" . ,apps-vec))))
    (scm->json-string response)))
```

---

## 10. Config Changes (`polysphere.json`)

Add to `polysphere.json`:
```json
{
  ...
  "search": {
    "delayMs": 500
  }
}
```

The `search.delayMs` key controls the debounce timer. Lower values = more responsive but more CPU. Higher values = less CPU but delays search results.

---

## 11. Testing

Phase 3 testing is **interactive manual testing** since the overlay requires a running Hyprland session.

### Test Procedures

Test runner: none — you perform these manually.

**Prerequisites:**
- Daemon running: `guile ~/.config/polysphere/daemon.scm`
- Quickshell ready: `quickshell -p shell.qml` (daemon starts it, or launch manually)
- Several apps open (firefox, kitty, code)

---

#### T1: Overlay opens on Alt+Tab

**Procedure:**
```
1. Press Alt+Tab and hold Alt
2. Observe the overlay appears with the 3D sphere
```

**Expected:** The overlay fades in (800ms entrance animation). The sphere shows running apps first, then whitelisted apps as launch targets.

---

#### T2: Sphere populates correctly

**Procedure:**
```
1. Press Alt+Tab
2. Observe the apps on the sphere
```

**Expected:**
- The currently focused app is at the front (`current`)
- The second-most-recent app is highlighted with the satellite detail view (`selected`)
- Running apps show full opacity
- Non-running whitelisted apps show as launch targets
- Total count doesn't exceed `totalApps`

---

#### T3: Tab cycles forward

**Procedure:**
```
1. Press Alt+Tab and hold Alt
2. Press Tab multiple times
3. Observe the sphere rotation and highlight changes
```

**Expected:** Each Tab press rotates the sphere to highlight the next app. The satellite detail view follows the selection. The selection wraps around at the end.

---

#### T4: Shift+Tab cycles backward

**Procedure:**
```
1. Press Alt+Tab and hold Alt
2. Press Tab twice to advance
3. Press Shift+Tab to go back
```

**Expected:** Shift+Tab reverses the cycle direction. The selection goes back one step. It wraps at the beginning.

---

#### T5: Escape closes (no focus change)

**Procedure:**
```
1. Press Alt+Tab
2. Press Escape
3. Observe the overlay closes with exit animation
```

**Expected:** Overlay fades out (400ms). No window focus changes. The app that was focused before Alt+Tab remains focused.

---

#### T6: Releasing Alt activates running app

**Procedure:**
```
1. Press Alt+Tab
2. Tab to a running app (e.g., kitty)
3. Release Alt
4. Observe
```

**Expected:**
- Exit animation plays (400ms)
- Kitty window comes to focus
- Overlay closes

---

#### T7: Escape clears search

**Procedure:**
```
1. Press Alt+Tab
2. Type "fi" into the search bar (don't press enter — just type)
3. Wait for the sphere to filter (500ms debounce)
4. Observe filtered results
5. Press Escape
```

**Expected:** After step 3, the sphere shows only apps matching "fi" (Firefox, etc.). First result is auto-selected and zoomed. After step 5, the search bar clears, the full sphere is restored, and the previous selection is restored.

---

#### T8: Escape closes overlay when search is empty

**Procedure:**
```
1. Press Alt+Tab
2. Press Escape (with empty search bar)
```

**Expected:** Overlay closes immediately (no search to clear).

---

#### T9: Search launches non-running app

**Procedure:**
```
1. Press Alt+Tab
2. Type the name of a non-running whitelisted app (e.g., "spotify")
3. Wait for search results
4. Release Alt
```

**Expected:** The app launches. The overlay closes. On the next Alt+Tab, the app should appear on the sphere (it was tracked in MRU via `track_launch`).

---

#### T10: Tab cycling works during search

**Procedure:**
```
1. Press Alt+Tab
2. Type "fi" to filter
3. Wait for sphere to show filtered results
4. Press Tab to cycle through filtered results
5. Release Alt to activate the selected app
```

**Expected:** Tab cycles through the filtered list only. Releasing Alt activates/launches whatever is selected.

---

#### T11: Mouse drag works

**Procedure:**
```
1. Press Alt+Tab
2. Click and drag on the sphere
3. Observe the sphere rotates with mouse movement
```

**Expected:** The sphere follows the mouse drag. The auto-rotation pauses during drag and resumes after.

---

#### T12: Search timer is configurable

**Procedure:**
```
1. Edit polysphere.json, set search.delayMs to 200
2. Reload config via IPC: quickshell ipc call polysphere reloadConfig
3. Press Alt+Tab, type "fi"
4. Observe the search fires faster (200ms instead of 500ms)
```

**Expected:** The search debounce respects the config value.

---

#### T13: App database loads correctly

**Procedure:**
```
1. Check daemon logs: cat /tmp/polysphere.log
2. Look for "App database: N entries" message
```

**Expected:** The daemon reports a reasonable number of installed apps (varies by system, typically 100-500).

---

#### T14: Escape + Alt release during search

**Procedure (edge case):**
```
1. Press Alt+Tab
2. Type "fi", wait for filtered results
3. Clear search with Escape (sphere restores)
4. Type "th", wait for filtered results
5. Release Alt (without clearing search)
```

**Expected:** Step 3 restores full sphere and previous selection. Step 5 activates the currently selected app (from the "th" filtered results). The overlay closes.

---

### Pass/Fail Criteria

| Test | Name | Pass Condition |
|---|---|---|
| T1 | Overlay opens | Sphere appears, entrance animation plays |
| T2 | Sphere populates | Correct MRU order, running/non-running badges |
| T3 | Tab cycles forward | Selection advances, wraps around |
| T4 | Shift+Tab cycles backward | Selection retreats, wraps around |
| T5 | Escape closes | Overlay closes, no focus change |
| T6 | Release activates | Selected app focuses, overlay closes |
| T7 | Escape clears search | Full sphere restored, prev selection restored |
| T8 | Empty Escape closes | Overlay closes immediately |
| T9 | Search launches | Non-running app launches, tracked in MRU |
| T10 | Tab in search | Only cycles filtered results |
| T11 | Mouse drag | Sphere rotates smoothly |
| T12 | Configurable timer | 200ms vs 500ms search response |
| T13 | App database | Daemon reports app count |
| T14 | Escape+Release in search | Both paths work correctly |

---

## 12. Implementation Checklist

- [x] **Daemon changes:** ✅ **Complete**
  - [x] Add `.desktop` file scanner at startup
  - [x] Add `get_app_db` request handler
  - [x] Add `track_launch` request handler
  - [x] Enrich MRU entries with `name`, `icon`, `exec` from app database
  - [x] Update `--help` output with new request types
- [ ] **QML changes:** (remaining work)
  - [ ] Add Fuse.js import (`lib/fuse.js`)
  - [ ] Add `search.delayMs` to `defaultConfig`
  - [ ] Add state variables: `appDatabase`, `fuseIndex`, `currentMruList`, `daemonSocket`, etc.
  - [ ] Add daemon IPC bridge — replace `appFetcher` with `daemonProcess` + `daemonRequest()`
  - [ ] Add search system (Fuse index, debounce timer, executeSearch, restoreFullSphere)
  - [ ] Add IpcHandler `toggle()` function
  - [ ] Add overlay lifecycle (`openOverlay`, `closeOverlay`, `populateSphereFromMru`)
  - [ ] Add Alt+Tab key handling (`Keys.onPressed`/`onReleased`, `updateSelection`, `triggerActivate`)
  - [ ] Add tiered Escape handler (clear search → close overlay)
  - [ ] Remove legacy code: `handleSearch()`, `launchApp()`, `paths.*` refs, `qs_manager.sh`, `Caching { id: paths }`
  - [ ] Update `searchInput` TextField: wire to `handleSearchInput()`, remove old key handlers
  - [ ] Update sphere delegate `MouseArea.onClicked` to use `triggerActivate()`-equivalent
  - [ ] Remove `Caching.qml` from repo
- [ ] **Config:**
  - [ ] Add `search.delayMs` to `polysphere.json`
- [ ] **Files:**
  - [x] `lib/fuse.js` — ✅ already created
  - [ ] Create `toggle-launcher.sh`
- [ ] **Testing:**
  - [ ] Complete T1–T14 manual tests
  - [ ] Update TESTS.md with PHASE_3_TESTING results
  - [x] Daemon test suite — ✅ already updated for new request types
- [ ] **Documentation:**
  - [ ] Update README.md with search and IPC info
  - [ ] Update PLAN.md with final architecture

---

## 13. Rollback Plan

If Phase 3 breaks the system:

1. **Revert `polysphere.qml`**: `git checkout polysphere.qml`
2. **Revert `daemon.scm`**: `git checkout daemon.scm`
3. **Revert `polysphere.json`**: `git checkout polysphere.json`
4. **Restore legacy files**: `git checkout -- app_fetcher.py qs_manager.sh` (if still in git history)
5. **Kill daemon**: `pkill -f "guile.*daemon.scm"`

The key risk is the IPC bridge — if the `Process` + `nc` approach has timing issues, the daemon communication may fail. The fallback is to use a persistent Python socket client or a dedicated C helper.
