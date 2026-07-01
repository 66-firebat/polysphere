# Phase 1: Config System

**Goal:** Replace all hardcoded values in `polysphere.qml` with properties loaded from an external JSON config file. Enable hot-reload, debug logging, and a script-driven test suite.

**Dependencies:** None (pure QML, no daemon, no Hyprland IPC).

---

## 1. Repository Reorganization

### New Structure

```
hypr-comp/
├── polysphere.json           ← Default config (shipped with the repo)
├── polysphere.qml            ← Main applauncher component (RENAMED)
├── shell.qml                 ← PanelWindow wrapper (MOVED from applauncher_view/)
├── Caching.qml               ← Path resolution helpers (KEPT)
├── Scaler.qml                ← Resolution-independent scaling (KEPT)
├── toggle-launcher.sh        ← Trigger script stub (KEPT for Phase 3)
├── README.md
├── PLAN.md
├── PHASE_1.md
└── tests/
    ├── config_full.json
    ├── config_partial.json
    ├── config_malformed.json
    ├── config_missing.json   ← empty file / symlink to nonexistent
    └── test_config_reader.sh
```

### Files to Delete

| File | Reason |
|---|---|
| `applauncher.qml` | Renamed to `polysphere.qml` |
| `moon.qml` | Not part of PolySphere |
| `Stars.qml` | Not part of PolySphere |
| `notifications.qml` | Empty placeholder, not part of PolySphere |
| `MatugenColors.qml` | Replaced by `polysphere.json` colors block |
| `app_fetcher.py` | Legacy; PolySphere gets running apps from daemon (Phase 2) |
| `qs_manager.sh` | Stub; toggle mechanism handled by `toggle-launcher.sh` |
| `run_moon.sh` | Belongs to moon.qml |
| `applauncher_view/applauncher.qml` | Duplicate of root applauncher.qml |
| `applauncher_view/shell.qml` | Moved to root as `shell.qml` |
| `quat_moon/` | Experimental QtQuick3D fork |
| `earth.jpg` | Used by moon.qml |
| `moon.jpg` | Used by moon.qml |

### Files to Keep

| File | Why |
|---|---|
| `Caching.qml` | `polysphere.qml` uses it for path resolution |
| `Scaler.qml` | `polysphere.qml` uses it for DPI scaling |
| `toggle-launcher.sh` | Stub kept for Phase 3 wiring |
| `PLAN.md` | Master architecture document |
| `README.md` | Existing notes |

---

## 2. Config Path Resolution

**Priority order** (first non-null wins):

```
1. $POLYSPHERE_CONFIG          ← env var override
2. ~/.config/polysphere/polysphere.json  ← default deployment path
3. (in-repo fallback) "polysphere.json"  ← for development/testing from repo root
```

**Implementation** (in `polysphere.qml`):

```qml
readonly property string configPath: {
    var envPath = Quickshell.env("POLYSPHERE_CONFIG");
    if (envPath) return envPath;

    var home = Quickshell.env("HOME");
    var defaultPath = home + "/.config/polysphere/polysphere.json";

    // For development: if running from repo dir, use local polysphere.json
    // (checked by Process trying the path and falling back)
    return defaultPath;
}
```

The `Process` that reads the config will try the path; if the file doesn't exist, it logs a warning and uses defaults only.

---

## 3. Config Schema

The canonical schema from `PLAN.md` becomes `polysphere.json`. Every key has a corresponding default hardcoded in QML so the UI degrades gracefully.

```json
{
  "totalApps": 20,
  "whitelistedApps": [
    "firefox.desktop",
    "kitty.desktop",
    "emacs.desktop",
    "ghostty.desktop",
    "code.desktop",
    "spotify.desktop",
    "thunar.desktop",
    "discord.desktop",
    "obsidian.desktop",
    "brave-browser.desktop"
  ],
  "appearance": {
    "overlayOpacity": 0.27,
    "baseSphereRadius": 368,
    "starCount": 50,
    "starOpacityMin": 0.08,
    "starOpacityMax": 0.12,
    "searchBar": {
      "width": 560,
      "height": 56,
      "borderRadius": 28,
      "bottomMargin": 63,
      "borderWidth": 1.5,
      "backgroundOpacity": 0.92,
      "shadowOpacity": 0.4,
      "shadowBlur": 1.5
    },
    "appCard": {
      "width": 74,
      "height": 104,
      "borderRadius": 12,
      "iconSize": 55,
      "fontSize": 11
    }
  },
  "satellite": {
    "hullWidth": 216,
    "hullHeight": 148,
    "panelWidth": 64,
    "panelHeight": 51,
    "strutWidth": 10,
    "strutHeight": 4,
    "antennaHeight": 16,
    "thrusterHeight": 11,
    "iconSize": 40,
    "fontSize": 10
  },
  "sphere": {
    "depthOpacityMultiplier": 4.0,
    "baseScaleAtEdge": 0.78,
    "scaleIncreaseTowardCenter": 0.22,
    "maxTiltAngleX": 45,
    "maxTiltAngleY": 35,
    "hoverScaleMultiplier": 1.12,
    "selectedZoom": 1.65,
    "zoomFactorWeight": 0.45
  },
  "animations": {
    "sphereRotateSpeed": 0.002,
    "sphereAutoRotateIntervalMs": 16,
    "sphereZoomDurationMs": 400,
    "searchRotateDurationMs": 700,
    "cardFadeDurationMs": 200,
    "cardScaleDurationMs": 200,
    "satelliteFadeDurationMs": 400,
    "satelliteScaleDurationMs": 450,
    "satelliteInitialScale": 0.4,
    "satelliteTargetScale": 1.5,
    "entranceFadeDurationMs": 800,
    "exitFadeDurationMs": 400
  },
  "mouse": {
    "dragSensitivity": 0.005,
    "maxRotationAngle": 1.45
  },
  "keybindings": {
    "toggle": "Alt+Tab",
    "cancel": "Escape",
    "cycleNext": "Tab",
    "cyclePrevious": "Shift+Tab"
  },
  "colors": {
    "base": "#1e1e2e",
    "mantle": "#181825",
    "crust": "#11111b",
    "text": "#cdd6f4",
    "subtext0": "#a6adc8",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "overlay0": "#6c7086",
    "blue": "#89b4fa",
    "mauve": "#cba6f7",
    "teal": "#94e2d5",
    "peach": "#fab387",
    "yellow": "#f9e2af",
    "sapphire": "#74c7ec"
  },
  "mru": {
    "maxEntries": 20,
    "updateOnExit": true
  }
}
```

---

## 4. Config Reader Implementation (`polysphere.qml`)

### 4.1 Defaults as a Property

A single `var` property holds all defaults, mirroring the config schema exactly:

```qml
readonly property var defaultConfig: ({
    "totalApps": 20,
    "whitelistedApps": [
        "firefox.desktop", "kitty.desktop", "emacs.desktop",
        "ghostty.desktop", "code.desktop", "spotify.desktop",
        "thunar.desktop", "discord.desktop", "obsidian.desktop",
        "brave-browser.desktop"
    ],
    "appearance": {
        "overlayOpacity": 0.27,
        "baseSphereRadius": 368,
        "starCount": 50,
        "starOpacityMin": 0.08,
        "starOpacityMax": 0.12,
        "searchBar": {
            "width": 560, "height": 56, "borderRadius": 28,
            "bottomMargin": 63, "borderWidth": 1.5,
            "backgroundOpacity": 0.92, "shadowOpacity": 0.4, "shadowBlur": 1.5
        },
        "appCard": {
            "width": 74, "height": 104, "borderRadius": 12,
            "iconSize": 55, "fontSize": 11
        }
    },
    "satellite": {
        "hullWidth": 216, "hullHeight": 148, "panelWidth": 64, "panelHeight": 51,
        "strutWidth": 10, "strutHeight": 4, "antennaHeight": 16, "thrusterHeight": 11,
        "iconSize": 40, "fontSize": 10
    },
    "sphere": {
        "depthOpacityMultiplier": 4.0,
        "baseScaleAtEdge": 0.78, "scaleIncreaseTowardCenter": 0.22,
        "maxTiltAngleX": 45, "maxTiltAngleY": 35,
        "hoverScaleMultiplier": 1.12,
        "selectedZoom": 1.65, "zoomFactorWeight": 0.45
    },
    "animations": {
        "sphereRotateSpeed": 0.002, "sphereAutoRotateIntervalMs": 16,
        "sphereZoomDurationMs": 400, "searchRotateDurationMs": 700,
        "cardFadeDurationMs": 200, "cardScaleDurationMs": 200,
        "satelliteFadeDurationMs": 400, "satelliteScaleDurationMs": 450,
        "satelliteInitialScale": 0.4, "satelliteTargetScale": 1.5,
        "entranceFadeDurationMs": 800, "exitFadeDurationMs": 400
    },
    "mouse": {
        "dragSensitivity": 0.005, "maxRotationAngle": 1.45
    },
    "keybindings": {
        "toggle": "Alt+Tab", "cancel": "Escape",
        "cycleNext": "Tab", "cyclePrevious": "Shift+Tab"
    },
    "colors": {
        "base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b",
        "text": "#cdd6f4", "subtext0": "#a6adc8",
        "surface0": "#313244", "surface1": "#45475a", "surface2": "#585b70",
        "overlay0": "#6c7086",
        "blue": "#89b4fa", "mauve": "#cba6f7", "teal": "#94e2d5",
        "peach": "#fab387", "yellow": "#f9e2af", "sapphire": "#74c7ec"
    },
    "mru": {
        "maxEntries": 20, "updateOnExit": true
    }
})
```

### 4.2 Deep Merge Function

A JS function performs a recursive merge: user config overrides defaults at the leaf level; missing keys use defaults.

```qml
function deepMerge(defaults, overrides) {
    if (typeof defaults !== "object" || defaults === null) return overrides !== undefined ? overrides : defaults;
    if (typeof overrides !== "object" || overrides === null) return overrides !== undefined ? overrides : defaults;

    var result = {};
    // Copy all defaults first
    for (var key in defaults) {
        if (defaults.hasOwnProperty(key)) {
            result[key] = defaults[key];
        }
    }
    // Override with user values
    for (var key in overrides) {
        if (overrides.hasOwnProperty(key)) {
            if (typeof defaults[key] === "object" && defaults[key] !== null && !Array.isArray(defaults[key])
                && typeof overrides[key] === "object" && overrides[key] !== null && !Array.isArray(overrides[key])) {
                result[key] = deepMerge(defaults[key], overrides[key]);
            } else {
                result[key] = overrides[key];
            }
        }
    }
    return result;
}
```

### 4.3 Config Loading

```qml
property var cfg: ({})   // resolved config — set after merge

Process {
    id: configReader
    command: ["cat", configPath]
    stdout: StdioCollector {
        onStreamFinished: {
            var raw = {};
            var txt = this.text.trim();
            if (txt.length > 0) {
                try {
                    raw = JSON.parse(txt);
                    console.log("POLYSPHERE: Config loaded from", configPath);
                } catch (e) {
                    console.log("POLYSPHERE ERROR: Failed to parse config -", e);
                    console.log("POLYSPHERE ERROR: Falling back to defaults");
                }
            } else {
                console.log("POLYSPHERE WARNING: Config file empty at", configPath);
                console.log("POLYSPHERE WARNING: Using defaults");
            }
            cfg = deepMerge(defaultConfig, raw);
            writeDebugDump(cfg);
        }
    }
}

Process {
    id: configFallback
    // Only runs if configReader fails (file not found)
    command: ["bash", "-c", "test -f " + configPath + " && echo 'EXISTS' || echo 'NOT_FOUND'"]
    stdout: StdioCollector {
        onStreamFinished: {
            if (this.text.trim() === "NOT_FOUND") {
                console.log("POLYSPHERE WARNING: Config not found at", configPath);
                console.log("POLYSPHERE WARNING: Using defaults. Set $POLYSPHERE_CONFIG to override.");
                cfg = deepMerge(defaultConfig, {});
                writeDebugDump(cfg);
            }
        }
    }
}
```

### 4.4 Config Watcher (Poll on startup, stop after load)

```qml
Timer {
    id: configWatcher
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
        configReader.running = false;
        configReader.running = true;
        configFallback.running = false;
        configFallback.running = true;
    }
}
```

When `cfg` changes, the QML bindings react automatically because all UI properties are bound to `cfg.*` paths.

The timer stops itself after a successful load via `configWatcher.running = false` inside `configReader.onStreamFinished`. This avoids unnecessary I/O every 5 seconds. If the config file is missing, the timer keeps running so it can pick up the file if the user creates it later.

### 4.5 IPC Handler (Manual Reload)

A Quickshell `IpcHandler` exposes a `reloadConfig` function that can be called externally to trigger a config re-read at any time:

```qml
IpcHandler {
    target: "polysphere"

    function reloadConfig(): void {
        console.log("POLYSPHERE: Manual config reload triggered via IPC");
        configReader.running = false;
        configReader.running = true;
        configFallback.running = false;
        configFallback.running = true;
    }
}
```

**Usage:**
```bash
# Reload config for the instance launched with -p shell.qml
quickshell ipc -p shell.qml call polysphere reloadConfig

# Or target a specific instance by shell ID
quickshell ipc --id 5e09d58d call polysphere reloadConfig

# List registered targets (to verify)
quickshell ipc -p shell.qml show
```

This is the primary mechanism for hot-reload after the initial polling timer stops.

### 4.5 Debug Dump

```qml
function writeDebugDump(resolved) {
    var json = JSON.stringify(resolved, null, 2);
    var dumpPath = "/tmp/polysphere-config-debug.json";
    Quickshell.execDetached(["bash", "-c",
        "cat > " + dumpPath + " << 'POLYEOF'\n" + json + "\nPOLYEOF"
    ]);
    console.log("POLYSPHERE DEBUG: Resolved config written to", dumpPath);
}
```

---

## 5. Property Wiring Map

Every hardcoded value in `polysphere.qml` becomes a property read from `cfg.*`. Below is the complete mapping.

### 5.1 Colors (Replace MatugenColors entirely)

**Remove:**
```qml
import "../"
MatugenColors { id: _theme }
```

**Add:**
```qml
readonly property color polyBase:     cfg.colors?.base     ?? "#1e1e2e"
readonly property color polyMantle:   cfg.colors?.mantle   ?? "#181825"
readonly property color polyCrust:    cfg.colors?.crust    ?? "#11111b"
readonly property color polyText:     cfg.colors?.text     ?? "#cdd6f4"
readonly property color polySubtext0: cfg.colors?.subtext0 ?? "#a6adc8"
readonly property color polySurface0: cfg.colors?.surface0 ?? "#313244"
readonly property color polySurface1: cfg.colors?.surface1 ?? "#45475a"
readonly property color polySurface2: cfg.colors?.surface2 ?? "#585b70"
readonly property color polyOverlay0: cfg.colors?.overlay0 ?? "#6c7086"
readonly property color polyBlue:     cfg.colors?.blue     ?? "#89b4fa"
readonly property color polyMauve:    cfg.colors?.mauve    ?? "#cba6f7"
readonly property color polyTeal:     cfg.colors?.teal     ?? "#94e2d5"
readonly property color polyPeach:    cfg.colors?.peach    ?? "#fab387"
readonly property color polyYellow:   cfg.colors?.yellow   ?? "#f9e2af"
readonly property color polySapphire: cfg.colors?.sapphire ?? "#74c7ec"
```

**Search-and-replace in the QML body:**
| Old reference | New reference |
|---|---|
| `window.base` | `window.polyBase` |
| `window.mantle` | `window.polyMantle` |
| `window.crust` | `window.polyCrust` |
| `window.text` | `window.polyText` |
| `window.subtext0` | `window.polySubtext0` |
| `window.surface0` | `window.polySurface0` |
| `window.surface1` | `window.polySurface1` |
| `window.surface2` | `window.polySurface2` |
| `window.overlay0` | `window.polyOverlay0` |
| `window.blue` | `window.polyBlue` |
| `window.mauve` | `window.polyMauve` |
| `window.teal` | `window.polyTeal` |
| `window.peach` | `window.polyPeach` |
| `window.yellow` | `window.polyYellow` |
| `window.sapphire` | `window.polySapphire` |

### 5.2 Appearance / Sphere

| Old hardcoded value | New property |
|---|---|
| `baseSphereRadius: window.s(368)` | `baseSphereRadius: window.s(cfg.appearance?.baseSphereRadius ?? 368)` |
| `sphereRotateSpeed: 0.002` | `sphereRotateSpeed: cfg.animations?.sphereRotateSpeed ?? 0.002` |
| `sphereAutoRotateIntervalMs: 16` | `sphereAutoRotateIntervalMs: cfg.animations?.sphereAutoRotateIntervalMs ?? 16` |
| `sphereZoomDuration: 400` | `sphereZoomDuration: cfg.animations?.sphereZoomDurationMs ?? 400` |
| `searchRotateDuration: 700` | `searchRotateDuration: cfg.animations?.searchRotateDurationMs ?? 700` |
| `cardFadeDuration: 200` | `cardFadeDuration: cfg.animations?.cardFadeDurationMs ?? 200` |
| `cardScaleDuration: 200` | `cardScaleDuration: cfg.animations?.cardScaleDurationMs ?? 200` |
| `entranceFadeDuration: 800` | `entranceFadeDuration: cfg.animations?.entranceFadeDurationMs ?? 800` |
| `exitFadeDuration: 400` | `exitFadeDuration: cfg.animations?.exitFadeDurationMs ?? 400` |

### 5.3 Satellite dimensions

All `_sat_*` properties use `cfg.satellite.*`:

```qml
readonly property real _sat_hullW:     window.s(cfg.satellite?.hullWidth     ?? 216)
readonly property real _sat_hullH:     window.s(cfg.satellite?.hullHeight    ?? 148)
readonly property real _sat_panelW:    window.s(cfg.satellite?.panelWidth    ?? 64)
readonly property real _sat_panelH:    window.s(cfg.satellite?.panelHeight   ?? 51)
readonly property real _sat_strutW:    window.s(cfg.satellite?.strutWidth    ?? 10)
readonly property real _sat_strutH:    window.s(cfg.satellite?.strutHeight   ?? 4)
readonly property real _sat_antennaH:  window.s(cfg.satellite?.antennaHeight ?? 16)
readonly property real _sat_thrusterH: window.s(cfg.satellite?.thrusterHeight ?? 11)
readonly property real _sat_iconSz:    window.s(cfg.satellite?.iconSize      ?? 40)
readonly property real _sat_fontSize:  window.s(cfg.satellite?.fontSize      ?? 10)
```

### 5.4 Sphere depth/scale behavior

| Property | Config path |
|---|---|
| `_baseScale` multiplier `0.78` | `cfg.sphere?.baseScaleAtCenter ?? 0.78` |
| scale increase `0.22` | `cfg.sphere?.scaleIncreaseTowardCenter ?? 0.22` |
| hover scale `1.12` | `cfg.sphere?.hoverScaleMultiplier ?? 1.12` |
| `selectedZoom` `1.65` | `cfg.sphere?.selectedZoom ?? 1.65` |
| `zoomFactorWeight` `0.45` | `cfg.sphere?.zoomFactorWeight ?? 0.45` |
| tilt max X `45` | `cfg.sphere?.maxTiltAngleX ?? 45` |
| tilt max Y `35` | `cfg.sphere?.maxTiltAngleY ?? 35` |
| depth opacity `4.0` | `cfg.sphere?.depthOpacityMultiplier ?? 4.0` |

### 5.5 Search bar

```qml
readonly property real searchBarWidth:          window.s(cfg.appearance?.searchBar?.width          ?? 560)
readonly property real searchBarHeight:         window.s(cfg.appearance?.searchBar?.height         ?? 56)
readonly property real searchBarBorderRadius:   window.s(cfg.appearance?.searchBar?.borderRadius   ?? 28)
readonly property real searchBarBottomMargin:   window.s(cfg.appearance?.searchBar?.bottomMargin   ?? 63)
readonly property real searchBarBorderWidth:    window.s(cfg.appearance?.searchBar?.borderWidth    ?? 1.5)
readonly property real searchBarBgOpacity:      cfg.appearance?.searchBar?.backgroundOpacity       ?? 0.92
readonly property real searchBarShadowOpacity:  cfg.appearance?.searchBar?.shadowOpacity           ?? 0.4
readonly property real searchBarShadowBlur:     cfg.appearance?.searchBar?.shadowBlur              ?? 1.5
```

### 5.6 App card

```qml
readonly property real appCardWidth:        window.s(cfg.appearance?.appCard?.width      ?? 74)
readonly property real appCardHeight:       window.s(cfg.appearance?.appCard?.height     ?? 104)
readonly property real appCardBorderRadius: window.s(cfg.appearance?.appCard?.borderRadius ?? 12)
readonly property real appCardIconSize:     window.s(cfg.appearance?.appCard?.iconSize   ?? 55)
readonly property real appCardFontSize:     cfg.appearance?.appCard?.fontSize            ?? 11
```

### 5.7 Mouse / Interaction

```qml
readonly property real dragSensitivity:  cfg.mouse?.dragSensitivity  ?? 0.005
readonly property real maxRotationAngle: cfg.mouse?.maxRotationAngle ?? 1.45
```

### 5.8 Keybindings

```qml
readonly property string keyToggle:     cfg.keybindings?.toggle     ?? "Alt+Tab"
readonly property string keyCancel:     cfg.keybindings?.cancel     ?? "Escape"
readonly property string keyCycleNext:  cfg.keybindings?.cycleNext  ?? "Tab"
readonly property string keyCyclePrev:  cfg.keybindings?.cyclePrevious ?? "Shift+Tab"
```

### 5.9 Stars background

```qml
readonly property int    starCount:       cfg.appearance?.starCount       ?? 50
readonly property real   starOpacityMin:  cfg.appearance?.starOpacityMin  ?? 0.08
readonly property real   starOpacityMax:  cfg.appearance?.starOpacityMax  ?? 0.12
```

---

## 6. Import Changes

### `polysphere.qml` — Remove `MatugenColors` import

```qml
// BEFORE:
import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

// AFTER:
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
```

Removed:
- `Qt5Compat.GraphicalEffects` — no longer used after removing MatugenColors
- `QtQuick.Window` — not used directly in applauncher.qml
- `"../"` — no longer needed since files are co-located

### `shell.qml` — Update path

Move from `applauncher_view/shell.qml` to root. The `Loader` source path changes:
```qml
// BEFORE (in applauncher_view/shell.qml):
Loader { source: "applauncher.qml" }

// AFTER (in root shell.qml):
Loader { source: "polysphere.qml" }
```

Also update the namespace:
```qml
WlrLayershell.namespace: "polysphere"    // was "app-launcher"
```

---

## 7. Test Suite

### 7.1 Test Config Files

**`tests/config_full.json`** — A full custom config with known values:
```json
{
  "totalApps": 8,
  "whitelistedApps": ["firefox.desktop", "kitty.desktop"],
  "appearance": {
    "baseSphereRadius": 200,
    "starCount": 10,
    "starOpacityMin": 0.05,
    "starOpacityMax": 0.15,
    "appCard": { "width": 60, "height": 80, "borderRadius": 8, "iconSize": 40, "fontSize": 9 }
  },
  "colors": {
    "base": "#000000",
    "text": "#ffffff",
    "blue": "#00aaff"
  },
  "sphere": { "selectedZoom": 2.0, "maxTiltAngleX": 30 }
}
```

**Expected debug output diff:** Every key in the merged result matches either the override value or the default — no missing keys, no extra keys.

**`tests/config_partial.json`** — Only 3 keys set:
```json
{
  "totalApps": 12,
  "appearance": { "baseSphereRadius": 400 },
  "colors": { "base": "#ff0000", "text": "#00ff00" }
}
```

**Expected:** All unset keys equal their hardcoded defaults. Only `totalApps=12`, `baseSphereRadius=400`, `base=#ff0000`, `text=#00ff00` differ.

**`tests/config_malformed.json`** — Invalid JSON:
```
{ this is not valid json }
```

**Expected:** Console error logged, `cfg` equals full defaults.

**`tests/config_missing.json`** — Set `POLYSPHERE_CONFIG` to a nonexistent path.

**Expected:** Console warning logged, `cfg` equals full defaults.

### 7.2 Test Runner Script

**`tests/test_config_reader.sh`** — Automated test harness:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
DEBUG_DUMP="/tmp/polysphere-config-debug.json"

cleanup() {
    rm -f "$DEBUG_DUMP"
}
trap cleanup EXIT

# Helper: run a test scenario
run_test() {
    local name="$1"
    local config_path="$2"
    local expected_json="$3"
    local description="$4"

    echo "─── Test: $name ───"
    echo "  $description"

    # Launch quickshell with the test config
    POLYSPHERE_CONFIG="$config_path" quickshell -p polysphere.qml &
    QS_PID=$!

    # Wait for debug dump (max 5s)
    local waited=0
    while [ ! -f "$DEBUG_DUMP" ] && [ $waited -lt 50 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true

    if [ ! -f "$DEBUG_DUMP" ]; then
        echo "  ✗ FAIL: Debug dump not produced"
        FAIL=$((FAIL + 1))
        return
    fi

    # Compare against expected
    local actual
    actual=$(cat "$DEBUG_DUMP")
    local expected
    expected=$(echo "$expected_json" | python3 -m json.tool 2>/dev/null || echo "$expected_json")

    if echo "$actual" | python3 -c "
import json, sys
actual = json.load(sys.stdin)
expected = json.loads('$expected_json')
if actual == expected:
    sys.exit(0)
else:
    print('DIFF:', json.dumps(actual, indent=2))
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ PASS"
        PASS=$((PASS + 1))
    else
        echo "  ✗ FAIL: Config mismatch"
        FAIL=$((FAIL + 1))
    fi
}

# === Test Cases ===

run_test "full config" \
    "tests/config_full.json" \
    "$(python3 -c "
import json
# Load defaults from polysphere.json
with open('polysphere.json') as f:
    default = json.load(f)
# Load overrides
with open('tests/config_full.json') as f:
    overrides = json.load(f)
# Deep merge
from copy import deepcopy
merged = deepcopy(default)
def deep_merge(d, o):
    for k, v in o.items():
        if k in d and isinstance(d[k], dict) and isinstance(v, dict):
            deep_merge(d[k], v)
        else:
            d[k] = v
deep_merge(merged, overrides)
print(json.dumps(merged, indent=2))
")" \
    "Full custom config overrides all set keys, defaults for the rest"

run_test "partial config" \
    "tests/config_partial.json" \
    "$(python3 -c "
import json
with open('polysphere.json') as f:
    default = json.load(f)
with open('tests/config_partial.json') as f:
    overrides = json.load(f)
from copy import deepcopy
merged = deepcopy(default)
def deep_merge(d, o):
    for k, v in o.items():
        if k in d and isinstance(d[k], dict) and isinstance(v, dict):
            deep_merge(d[k], v)
        else:
            d[k] = v
deep_merge(merged, overrides)
print(json.dumps(merged, indent=2))
")" \
    "Partial config: only 3 keys set, everything else defaults"

run_test "malformed json" \
    "tests/config_malformed.json" \
    "$(python3 -c "
import json
with open('polysphere.json') as f:
    print(f.read())
")" \
    "Malformed JSON: should use full defaults"

run_test "missing file" \
    "/tmp/polysphere-nonexistent-test.json" \
    "$(python3 -c "
import json
with open('polysphere.json') as f:
    print(f.read())
")" \
    "Missing file: should use full defaults with warning"

# === Summary ===
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ]
```

### 7.3 Pass / Fail Criteria

| # | Test | Pass Condition |
|---|---|---|
| T1 | Full config override | Every property in `cfg` matches the expected merged result. Checked via debug dump diff. |
| T2 | Partial config (3 keys) | Only those 3 keys differ from defaults. Every other key equals the hardcoded default. |
| T3 | Malformed JSON | `cfg` equals full defaults. Error logged to console. |
| T4 | Missing config file | `cfg` equals full defaults. Warning logged to console. |
| T5 | IPC reload | Launch with valid config, verify `quickshell ipc call polysphere reloadConfig` triggers a re-read. Verifiable via debug dump timestamp/contents. |

---

## 8. File-by-File Change Summary

### New Files

| File | Contents |
|---|---|
| `polysphere.json` | Default config (full schema from §3) |
| `tests/config_full.json` | Full custom config for testing |
| `tests/config_partial.json` | 3-key partial config for testing |
| `tests/config_malformed.json` | Invalid JSON for testing |
| `tests/config_missing.json` | Symlink to nonexistent path (or empty marker) |
| `tests/test_config_reader.sh` | Test runner script |

### Renamed Files

| Old Path | New Path | Notes |
|---|---|---|
| `applauncher.qml` | `polysphere.qml` | Full rewrite of imports, config, colors |

### Modified Files

| File | Changes |
|---|---|
| `applauncher_view/shell.qml` | Moved to `shell.qml`, loader path → `polysphere.qml`, namespace → `"polysphere"` |
| `Caching.qml` | No changes needed (already standalone) |
| `Scaler.qml` | No changes needed (already standalone) |
| `toggle-launcher.sh` | No changes (stub, Phase 3) |

### Deleted Files

See §1.2 table above.

---

## 9. Implementation Checklist

- [ ] Create `polysphere.json` with full default schema
- [ ] Rename `applauncher.qml` → `polysphere.qml`
- [ ] Remove MatugenColors import and references
- [ ] Add `defaultConfig` property with all defaults
- [ ] Add `deepMerge()` function
- [ ] Add `configPath` resolution property (env var → default)
- [ ] Add `configReader` Process for reading config file
- [ ] Add `configFallback` Process for detecting missing file
- [x] Add `configWatcher` Timer for initial poll + auto-stop after successful load (5s interval)
- [ ] Add `writeDebugDump()` function
- [ ] Wire every hardcoded property to `cfg.*` (see §5 mapping)
- [ ] Update `shell.qml`: move from `applauncher_view/`, fix loader source, fix namespace
- [ ] Delete all files from §1.2
- [ ] Create `tests/config_full.json`
- [ ] Create `tests/config_partial.json`
- [ ] Create `tests/config_malformed.json`
- [ ] Create `tests/test_config_reader.sh`
- [ ] Run test suite: all tests pass
- [ ] Verify hot-reload manually (edit config, see UI update)

---

## 10. Rollback Plan

If Phase 1 breaks the launcher:

1. **Restore `applauncher.qml`** from git (`git checkout applauncher.qml`)
2. **Restore deleted files** (`git checkout -- moon.qml Stars.qml MatugenColors.qml ...`)
3. **Restore `applauncher_view/`** from git
4. **Revert import changes** — put `import "../"` back
5. **Re-add `MatugenColors { id: _theme }`** and all `_theme` color references
6. **Restore all hardcoded values** — remove every `cfg.*` binding

The Phase 1 commit should be atomic so `git revert` undoes everything cleanly.
