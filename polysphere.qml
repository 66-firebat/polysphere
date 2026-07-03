import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "lib/fuse.js" as FuseJs

Item {
    id: window
    visible: false
    focus: true

    implicitWidth: Screen.width
    implicitHeight: Screen.height

    // ═══════════════════════════════════════════════════════════════
    // Config System
    // ═══════════════════════════════════════════════════════════════

    // Config path resolution: env var → default
    readonly property string configPath: {
        var envPath = Quickshell.env("POLYSPHERE_CONFIG");
        if (envPath) return envPath;
        var home = Quickshell.env("HOME");
        return home + "/.config/polysphere/polysphere.json";
    }

    // Full default config — mirrors polysphere.json schema exactly
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
        },
        "search": {
            "delayMs": 500
        }
    })

    // Resolved config — set after each successful config load
    property var cfg: ({})

    // Deep merge: overrides recursively replace matching leaves in defaults
    function deepMerge(defaults, overrides) {
        if (typeof defaults !== "object" || defaults === null) return overrides !== undefined ? overrides : defaults;
        if (typeof overrides !== "object" || overrides === null) return overrides !== undefined ? overrides : defaults;
        var result = {};
        for (var key in defaults) {
            if (defaults.hasOwnProperty(key)) result[key] = defaults[key];
        }
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

    // Write the resolved config to a debug dump file
    function writeDebugDump(resolved) {
        var json = JSON.stringify(resolved, null, 2);
        var escaped = json.replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-c",
            "cat > /tmp/polysphere-config-debug.json << 'POLYEOF'\n" + json + "\nPOLYEOF"
        ]);
        console.log("POLYSPHERE: Debug dump written to /tmp/polysphere-config-debug.json");
    }

    // Config file reader
    Process {
        id: configReader
        command: ["cat", configPath]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = {};
                var txt = this.text.trim();
                var loaded = false;
                if (txt.length > 0) {
                    try {
                        raw = JSON.parse(txt);
                        console.log("POLYSPHERE: Config loaded from", configPath);
                        loaded = true;
                    } catch (e) {
                        console.log("POLYSPHERE ERROR: Failed to parse config -", String(e));
                        console.log("POLYSPHERE ERROR: Falling back to defaults");
                    }
                } else {
                    console.log("POLYSPHERE WARNING: Config file empty at", configPath);
                }
                window.cfg = window.deepMerge(window.defaultConfig, raw);
                window.writeDebugDump(window.cfg);
                if (loaded) {
                    console.log("POLYSPHERE: Config loaded successfully. Stopping poll.");
                    configWatcher.running = false;
                }
            }
        }
    }

    // Detect missing config file
    Process {
        id: configFallback
        command: ["bash", "-c", "test -f " + configPath + " && echo 'EXISTS' || echo 'NOT_FOUND'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "NOT_FOUND") {
                    console.log("POLYSPHERE WARNING: Config not found at", configPath);
                    console.log("POLYSPHERE WARNING: Using defaults. Set $POLYSPHERE_CONFIG to override.");
                    window.cfg = window.deepMerge(window.defaultConfig, {});
                    window.writeDebugDump(window.cfg);
                }
            }
        }
    }

    // Poll for config on startup; keeps polling if file is missing.
    // Stops automatically after a successful load.
    // Trigger a manual re-read via: quickshell ipc -p shell.qml call polysphere reloadConfig
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

    // IPC handler for manual config reload
    IpcHandler {
        target: "polysphere"

        function reloadConfig(): void {
            console.log("POLYSPHERE: Manual config reload triggered via IPC");
            configReader.running = false;
            configReader.running = true;
            configFallback.running = false;
            configFallback.running = true;
        }

        function toggle(): void {
            if (window.visible) {
                closeOverlay();
            } else {
                window.visible = true;
            }
        }

        // Called by Hyprland's Alt+Tab bind (since Hyprland consumes the key event
        // before QML's Keys.onPressed can see it).
        // First press opens overlay; subsequent presses cycle forward.
        function cycle(): void {
            // IPC fallback — opens overlay. Sets tabWasPressed because
            // kbd-capture may not have started yet (async startup delay).
            // The socket handler no longer resets tabWasPressed, so this
            // won't cause premature activation.
            if (!window.visible) {
                window.altHeld = true;
                window.tabWasPressed = true;
                if (window.panelWindow) {
                    window.panelWindow.visible = true;
                }
                window.visible = true;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Daemon IPC
    // ═══════════════════════════════════════════════════════════════

    // Daemon socket path
    readonly property string daemonSocket: {
        var envSocket = Quickshell.env("POLYSPHERE_SOCKET");
        if (envSocket) return envSocket;
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
        return (runtimeDir || "/tmp") + "/polysphere.sock";
    }

    // App database from daemon
    property var appDatabase: []
    property var fuseIndex: null
    property var currentMruList: []
    property int savedSelectionIndex: -1
    property bool altHeld: false
    property bool tabWasPressed: false
    property bool kbdActive: false          // true when kbd-capture is handling keys
    property bool _openingOverlay: false    // guard to prevent re-entrant openOverlay()

    // Fuse.js search options
    readonly property var fuseOptions: ({
        keys: ["name", "id"],
        threshold: 0.4,
        includeScore: true,
        shouldSort: true,
        minMatchCharLength: 1
    })

    // Helper: send JSON request to daemon via Unix socket
    function daemonRequest(type, extraData, callback) {
        var msg = JSON.stringify(Object.assign({type: type}, extraData || {}));
        var escaped = msg.replace(/'/g, "'\\'");
        daemonProcess.command = [
            "bash", "-c",
            "echo '" + escaped + "' | nc -U " + daemonSocket
        ];
        daemonProcess._callback = callback;
        daemonProcess.running = false;
        daemonProcess.running = true;
    }

    // Process for communicating with the daemon
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

    // ────────────────────────────────────────────────────────────────
    // kbd-capture: raw evdev keyboard capture process
    // ────────────────────────────────────────────────────────────────

    // kbd-capture binary path (relative to repo root, or deployed path)
    readonly property string kbdCapturePath: "/run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/lib/kbd-capture"

    // SocketServer — listens for kbd-capture to connect and stream JSON events.
    // SplitParser fires onRead once per complete JSON line (delimiter = \n).
    property int _kbdLogSeq: 0
    function kbdLog(msg) {
        window._kbdLogSeq = window._kbdLogSeq + 1;
        console.log("KBDLOG[" + window._kbdLogSeq + "] " + msg);
    }

    SocketServer {
        id: kbdServer
        active: false
        path: "/tmp/polysphere-kbd.sock"
        handler: Socket {
            onConnectedChanged: {
                window.kbdLog("SOCKET connected=" + connected);
                if (connected) {
                    // Debounce: only grab if not already grabbed recently
                    var now = Date.now();
                    if (!window._lastGrabTime || now - window._lastGrabTime > 500) {
                        window._lastGrabTime = now;
                        this.write("grab\n");
                        this.flush();
                        window.kbdLog("SOCKET sent grab");
                    }
                }
            }
            parser: SplitParser {
                onRead: (message) => {
                    try {
                        var evt = JSON.parse(message);
                        window.kbdLog("EVT " + evt.key + "=" + evt.value + " alt=" + (evt.mods && evt.mods.alt) + " shift=" + (evt.mods && evt.mods.shift));
                        handleKbdEvent(evt);
                    } catch(e) {
                        window.kbdLog("PE: " + message);
                    }
                }
            }
        }
    }

    // Handle a key event from kbd-capture
    function handleKbdEvent(evt) {
        window.kbdLog("HANDLE key=" + evt.key + " val=" + evt.value + " alt=" + (evt.mods && evt.mods.alt) +
                     " vis=" + window.visible + " tabPressed=" + window.tabWasPressed + " altHeld=" + window.altHeld);
        var alt = evt.mods && evt.mods.alt;
        var shift = evt.mods && evt.mods.shift;

        // --- Alt key tracking ---
        if (evt.key === "alt_left" || evt.key === "alt_right") {
            window.altHeld = (evt.value === 1);
            if (!window.altHeld && window.tabWasPressed) {
                // Alt released after Tab was pressed → activate
                triggerActivate();
            }
            return;
        }

        // --- Ignore key releases for action keys (press-only) ---
        if (evt.value !== 1) return;

        // --- Escape ---
        if (evt.key === "esc") {
            handleEscape();
            return;
        }

        // --- Tab/Backtab (cycle) — only on PRESS (value=1), not release or repeat
        if (evt.key === "tab" && evt.value === 1) {
            if (alt) {
                window.tabWasPressed = true;
                if (window.visible) {
                    cycleSelection(shift ? -1 : 1);
                } else {
                    // First Alt+Tab: open overlay
                    window.altHeld = true;
                    window.tabWasPressed = true;
                    if (window.panelWindow) window.panelWindow.visible = true;
                    window.visible = true;
                }
            }
            return;
        }

        // --- Letter/digit keys (search, only when overlay visible) ---
        if (window.visible && evt.key.length === 1 && evt.key.match(/[a-zA-Z0-9]/)) {
            searchInput.text += evt.key;
            searchInput.forceActiveFocus();
            return;
        }

        // --- Backspace (search) ---
        if (window.visible && evt.key === "backspace") {
            searchInput.text = searchInput.text.slice(0, -1);
            return;
        }
    }

    // Start kbd-capture (runs continuously as long as QML is alive)
    function startKbdCapture() {
        console.log("POLYSPHERE: Starting kbd-capture...");
        kbdLog("START kbd-capture");
        var toggleStr = (cfg.keybindings?.toggle || "Alt+Tab");
        var cancelStr = (cfg.keybindings?.cancel || "Escape");
        var nextStr = (cfg.keybindings?.cycleNext || "Tab");
        var prevStr = (cfg.keybindings?.cyclePrevious || "Shift+Tab");
        var kbdArgs = "--connect /tmp/polysphere-kbd.sock"
            + " --toggle \"" + toggleStr + "\""
            + " --cancel \"" + cancelStr + "\""
            + " --cycle-next \"" + nextStr + "\""
            + " --cycle-prev \"" + prevStr + "\"";
        Quickshell.execDetached(["bash", "-c",
            kbdCapturePath + " " + kbdArgs + " > /tmp/kbd-capture.log 2>&1 &"
        ]);
    }

    // Fetch all installed apps from daemon and build Fuse.js index
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

    // Load app database on startup
    Component.onCompleted: {
        loadAppDatabase();
        startKbdCapture();
    }

    // ═══════════════════════════════════════════════════════════════
    // Overlay Lifecycle
    // ═══════════════════════════════════════════════════════════════

    // Open the overlay — called by toggle(), cycle(), or onVisibleChanged
    // NOTE: Do NOT reset altHeld/tabWasPressed here! cycle() sets them before
    //       calling openOverlay(), and they're needed for Alt-release activation.
    function openOverlay() {
        // Guard against re-entrance — prevents multiple concurrent get_mru requests
        if (window._openingOverlay) {
            console.log("POLYSPHERE: openOverlay already in progress, skipping");
            return;
        }
        window._openingOverlay = true;

        window.kbdLog("OPEN overlay");
        window.kbdActive = true;
        // Activate SocketServer to accept kbd-capture connection
        kbdServer.active = true;

        // Make the PanelWindow visible so it can receive keyboard/mouse events
        if (panelWindow) {
            panelWindow.visible = true;
        }
        window.searchQuery = "";
        searchInput.text = "";
        savedSelectionIndex = window.selectedAppIndex;
        window.sphereZoom = 1.0;

        // Fetch fresh MRU list from daemon
        console.log("POLYSPHERE: openOverlay sending get_mru");
        daemonRequest("get_mru", {}, function(response) {
            console.log("POLYSPHERE: get_mru response received with " + (response.mru ? response.mru.length : 0) + " entries");
            if (response.mru) {
                currentMruList = response.mru;
                populateSphereFromMru(response);
            }
            window._openingOverlay = false;
        });

        // Load app database on first open if not already loaded
        if (fuseIndex === null && appDatabase.length === 0) {
            loadAppDatabase();
        }

        introPhaseAnim.restart();
        searchInput.forceActiveFocus();
    }

    // Close the overlay — plays exit animation, then hides
    function closeOverlay() {
        kbdLog("CLOSE overlay");
        window._openingOverlay = false;  // Reset guard so overlay can reopen
        kbdServer.active = false;
        window.kbdActive = false;
        searchTimer.running = false;
        closeSequence.start();
    }

    // Populate the sphere model from a get_mru daemon response
    function populateSphereFromMru(response) {
        // Deduplicate the response by ID (daemon may return duplicates)
        var seenIds = {};
        var mru = [];
        for (var di = 0; di < response.mru.length; di++) {
            var id = response.mru[di].id;
            if (!seenIds[id]) {
                seenIds[id] = true;
                mru.push(response.mru[di]);
            }
        }
        if (mru.length !== response.mru.length) {
            console.log("POLYSPHERE: deduplicated " + (response.mru.length - mru.length) + " entries from daemon response");
        }
        var i = 0;

        // Update existing entries in-place (preserves delegates, avoids TypeErrors)
        for (; i < appModel.count && i < mru.length; i++) {
            var entry = mru[i];
            appModel.set(i, {
                id: entry.id,
                name: entry.name || "",
                icon: entry.icon || "",
                exec: entry.exec || "",
                running: entry.running
            });
        }

        // Add new entries if response has more
        for (; i < mru.length; i++) {
            var entry = mru[i];
            appModel.append({
                id: entry.id,
                name: entry.name || "",
                icon: entry.icon || "",
                exec: entry.exec || "",
                running: entry.running
            });
        }

        // Remove excess entries if model has more
        while (appModel.count > mru.length) {
            appModel.remove(appModel.count - 1, 1);
        }

        // Debug: verify model contents
        var ids = [];
        for (var di = 0; di < appModel.count; di++) {
            ids.push(appModel.get(di).id);
        }
        var uniqueIds = {};
        var dupes = [];
        for (var di = 0; di < ids.length; di++) {
            if (uniqueIds[ids[di]]) dupes.push(ids[di]);
            uniqueIds[ids[di]] = true;
        }
        console.log("POLYSPHERE: appModel after populate = " + appModel.count + " entries" +
                    (dupes.length > 0 ? " DUPLICATES: " + dupes.join(",") : ""));
        console.log("POLYSPHERE: response.mru had " + mru.length + " entries");

        window.selectedAppIndex = -1;

        // Highlight the daemon's selected app
        if (response.selected) {
            updateSelection(response.selected);
        }

        window.sphereZoom = 1.0;
        window.projDirty = true;
        window.rebuildProjCache();
    }

    // ═══════════════════════════════════════════════════════════════
    // Scaler
    // ═══════════════════════════════════════════════════════════════

    Scaler {
        id: scaler
        currentWidth: window.width
    }

    function s(val) {
        let res = scaler.s(val);
        return res > 0 ? res : val;
    }

    // ═══════════════════════════════════════════════════════════════
    // Colors (from cfg)
    // ═══════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════
    // Pre-scaled size helpers
    // ═══════════════════════════════════════════════════════════════

    readonly property real _s2:   window.s(2)
    readonly property real _s3:   window.s(3)
    readonly property real _s4:   window.s(4)
    readonly property real _s5:   window.s(5)
    readonly property real _s8:   window.s(8)
    readonly property real _s11:  window.s(11)
    readonly property real _s12:  window.s(12)
    readonly property real _s15:  window.s(15)
    readonly property real _s16:  window.s(16)
    readonly property real _s18:  window.s(18)
    readonly property real _s20:  window.s(20)
    readonly property real _s28:  window.s(28)
    readonly property real _s40:  window.s(40)
    readonly property real _s50:  window.s(50)
    readonly property real _s55:  window.s(55)
    readonly property real _s56:  window.s(56)
    readonly property real _s63:  window.s(63)
    readonly property real _s74:  window.s(74)
    readonly property real _s104: window.s(104)

    // Satellite dimensions (from cfg)
    readonly property real _sat_hullW:     window.s(cfg.satellite?.hullWidth     ?? 216)
    readonly property real _sat_hullH:     window.s(cfg.satellite?.hullHeight    ?? 148)
    readonly property real _sat_panelW:    window.s(cfg.satellite?.panelWidth    ?? 64)
    readonly property real _sat_panelH:    window.s(cfg.satellite?.panelHeight   ?? 51)
    readonly property real _sat_strutW:    window.s(cfg.satellite?.strutWidth    ?? 10)
    readonly property real _sat_strutH:    window.s(cfg.satellite?.strutHeight   ?? 4)
    readonly property real _sat_antennaH:  window.s(cfg.satellite?.antennaHeight ?? 16)
    readonly property real _sat_thrusterH: window.s(cfg.satellite?.thrusterHeight ?? 11)
    readonly property real _sat_radius12:  window.s(10)  // derived from hull geometry
    readonly property real _sat_radius8:   window.s(7)
    readonly property real _sat_radius4:   window.s(3)
    readonly property real _sat_antBall:   window.s(6)
    readonly property real _sat_antStick:  window.s(2)
    readonly property real _sat_antOffX:   window.s(14)
    readonly property real _sat_screenM:   window.s(8)
    readonly property real _sat_innerM:    window.s(10)
    readonly property real _sat_iconSz:    window.s(cfg.satellite?.iconSize      ?? 40)
    readonly property real _sat_fontSize:  window.s(cfg.satellite?.fontSize      ?? 10)
    readonly property real _sat_thrBase:   window.s(16)
    readonly property real _sat_spacing:   window.s(5)

    // ═══════════════════════════════════════════════════════════════
    // Animation durations (from cfg)
    // ═══════════════════════════════════════════════════════════════

    readonly property int animSphereZoom:       cfg.animations?.sphereZoomDurationMs        ?? 400
    readonly property int animSearchRotate:     cfg.animations?.searchRotateDurationMs      ?? 700
    readonly property int animCardFade:         cfg.animations?.cardFadeDurationMs          ?? 200
    readonly property int animCardScale:        cfg.animations?.cardScaleDurationMs         ?? 200
    readonly property int animSatFade:          cfg.animations?.satelliteFadeDurationMs     ?? 400
    readonly property int animSatScale:         cfg.animations?.satelliteScaleDurationMs    ?? 450
    readonly property int animEntranceFade:     cfg.animations?.entranceFadeDurationMs      ?? 800
    readonly property int animExitFade:         cfg.animations?.exitFadeDurationMs          ?? 400

    // ═══════════════════════════════════════════════════════════════
    // Sphere state
    // ═══════════════════════════════════════════════════════════════

    readonly property real sphereRotateSpeed:     cfg.animations?.sphereRotateSpeed         ?? 0.002
    readonly property int  sphereAutoRotInterval:  cfg.animations?.sphereAutoRotateIntervalMs ?? 16
    readonly property real sphereBaseScale:        cfg.sphere?.baseScaleAtEdge              ?? 0.78
    readonly property real sphereScaleIncrease:    cfg.sphere?.scaleIncreaseTowardCenter    ?? 0.22
    readonly property real sphereHoverScale:       cfg.sphere?.hoverScaleMultiplier         ?? 1.12
    readonly property real sphereSelectedZoom:     cfg.sphere?.selectedZoom                 ?? 1.65
    readonly property real sphereZoomWeight:       cfg.sphere?.zoomFactorWeight             ?? 0.45
    readonly property real sphereTiltX:            cfg.sphere?.maxTiltAngleX                ?? 45
    readonly property real sphereTiltY:            cfg.sphere?.maxTiltAngleY                ?? 35
    readonly property real depthOpacityMult:       cfg.sphere?.depthOpacityMultiplier       ?? 4.0

    readonly property real mouseDragSens:   cfg.mouse?.dragSensitivity  ?? 0.005
    readonly property real mouseMaxRot:     cfg.mouse?.maxRotationAngle ?? 1.45

    readonly property int    starCount:      cfg.appearance?.starCount      ?? 50
    readonly property real   starOpacityMin: cfg.appearance?.starOpacityMin ?? 0.08
    readonly property real   starOpacityMax: cfg.appearance?.starOpacityMax ?? 0.12

    readonly property real baseSphereRadius: window.s(cfg.appearance?.baseSphereRadius ?? 368)

    // ═══════════════════════════════════════════════════════════════
    // Search bar dimensions (from cfg)
    // ═══════════════════════════════════════════════════════════════

    readonly property real sbWidth:           window.s(cfg.appearance?.searchBar?.width          ?? 560)
    readonly property real sbHeight:          window.s(cfg.appearance?.searchBar?.height         ?? 56)
    readonly property real sbBorderRadius:    window.s(cfg.appearance?.searchBar?.borderRadius   ?? 28)
    readonly property real sbBottomMargin:    window.s(cfg.appearance?.searchBar?.bottomMargin   ?? 63)
    readonly property real sbBorderWidth:     window.s(cfg.appearance?.searchBar?.borderWidth    ?? 1.5)
    readonly property real sbBgOpacity:       cfg.appearance?.searchBar?.backgroundOpacity       ?? 0.92
    readonly property real sbShadowOpacity:   cfg.appearance?.searchBar?.shadowOpacity           ?? 0.4
    readonly property real sbShadowBlur:      cfg.appearance?.searchBar?.shadowBlur              ?? 1.5

    readonly property real acWidth:        window.s(cfg.appearance?.appCard?.width      ?? 74)
    readonly property real acHeight:       window.s(cfg.appearance?.appCard?.height     ?? 104)
    readonly property real acBorderRadius: window.s(cfg.appearance?.appCard?.borderRadius ?? 12)
    readonly property real acIconSize:     window.s(cfg.appearance?.appCard?.iconSize   ?? 55)
    readonly property real acFontSize:     cfg.appearance?.appCard?.fontSize            ?? 11

    property real sphereZoom: 1.0
    Behavior on sphereZoom { NumberAnimation { duration: animSphereZoom; easing.type: Easing.OutCubic } }

    property real sphereRadius: baseSphereRadius

    property real rotX: -0.2
    property real rotY: 0

    NumberAnimation { id: searchRotXAnim; target: window; property: "rotX"; duration: animSearchRotate; easing.type: Easing.OutCubic }
    NumberAnimation { id: searchRotYAnim; target: window; property: "rotY"; duration: animSearchRotate; easing.type: Easing.OutCubic }

    property var projCache: []
    property bool projDirty: true

    function rebuildProjCache() {
        if (!projDirty) return;
        projDirty = false;

        let phi   = Math.PI * (3 - Math.sqrt(5));
        let total = appModel.count;
        let rx    = window.rotX;
        let ry    = window.rotY;
        let cosRx = Math.cos(rx), sinRx = Math.sin(rx);
        let cosRy = Math.cos(ry), sinRy = Math.sin(ry);

        let arr = new Array(total);
        for (let i = 0; i < total; i++) {
            let b_y      = 1.0 - (i / Math.max(1, total - 1)) * 2.0;
            let b_radius = Math.sqrt(1.0 - b_y * b_y);
            let b_theta  = phi * i;
            let b_x      = Math.cos(b_theta) * b_radius;
            let b_z      = Math.sin(b_theta) * b_radius;

            let y1 = b_y * cosRx - b_z * sinRx;
            let z1 = b_y * sinRx + b_z * cosRx;
            let x2 = b_x * cosRy + z1 * sinRy;
            let z2 = -b_x * sinRy + z1 * cosRy;

            arr[i] = { x: x2, y: y1, z: z2 };
        }
        window.projCache = arr;
    }

    onRotXChanged: { projDirty = true; rebuildProjCache(); }
    onRotYChanged: { projDirty = true; rebuildProjCache(); }

    function project3D(bx, by, bz) {
        let rx = window.rotX;
        let ry = window.rotY;
        let y1 = by * Math.cos(rx) - bz * Math.sin(rx);
        let z1 = by * Math.sin(rx) + bz * Math.cos(rx);
        let x2 = bx * Math.cos(ry) + z1 * Math.sin(ry);
        let z2 = -bx * Math.sin(ry) + z1 * Math.cos(ry);
        return { x: x2, y: y1, z: z2 };
    }

    Timer {
        interval: window.sphereAutoRotInterval
        running: !sceneMouse.pressed && !searchRotXAnim.running && !searchRotYAnim.running
        repeat: true
        onTriggered: window.rotY -= window.sphereRotateSpeed
    }

    function centerOnApp(index) {
        if (index < 0 || index >= appModel.count) return;

        let phi    = Math.PI * (3 - Math.sqrt(5));
        let total  = appModel.count;
        let b_y    = 1.0 - (index / Math.max(1, total - 1)) * 2.0;
        let b_radius = Math.sqrt(1.0 - b_y * b_y);
        let b_theta  = phi * index;
        let b_x    = Math.cos(b_theta) * b_radius;
        let b_z    = Math.sin(b_theta) * b_radius;

        let targetRotX = Math.atan2(b_y, b_z);
        let z1         = Math.sqrt(b_y * b_y + b_z * b_z);
        let targetRotY = Math.atan2(-b_x, z1);

        let currentRotYMod = ((window.rotY % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
        let targetRotYNorm = ((targetRotY % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);

        let diff = targetRotYNorm - currentRotYMod;
        if (diff >  Math.PI) diff -= Math.PI * 2;
        if (diff < -Math.PI) diff += Math.PI * 2;

        searchRotXAnim.to = Math.max(-mouseMaxRot, Math.min(mouseMaxRot, targetRotX));
        searchRotYAnim.to = window.rotY + diff;

        searchRotXAnim.restart();
        searchRotYAnim.restart();
    }

    property real introPhase: 0.0
    NumberAnimation on introPhase {
        id: introPhaseAnim
        from: 0.0; to: 1.0; duration: window.animEntranceFade; easing.type: Easing.OutExpo; running: true
    }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) {
                openOverlay();
            }
        }
    }

    SequentialAnimation {
        id: closeSequence
        NumberAnimation { target: window; property: "introPhase"; to: 0.0; duration: window.animExitFade; easing.type: Easing.OutQuint }
        ScriptAction { script: { 
            window.visible = false;
            // Hide the PanelWindow so it stops intercepting mouse/keyboard events
            if (window.panelWindow) {
                window.panelWindow.visible = false;
            }
        } }
    }

    property string searchQuery: ""
    property int    selectedAppIndex: -1

    property string selectedAppName: ""
    property string selectedAppIcon: ""
    property string selectedAppExec: ""

    // Reference to the shell PanelWindow, set by shell.qml after loading.
    // Used to directly control visibility for click-through when closed.
    property var panelWindow: null

    ListModel { id: appModel }

    // Search debounce timer — resets on each keystroke
    readonly property int searchTimerDuration: cfg.search?.delayMs ?? 500

    // ═══════════════════════════════════════════════════════════════
    // Keyboard Handling (kbd-capture primary, QML Keys as fallback)
    // ═══════════════════════════════════════════════════════════════

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        // kbd-capture handles all keys when active
        if (kbdActive) return;

        // FALLBACK: Alt pressed
        if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
            altHeld = true;
            event.accepted = true;
        }

        // FALLBACK: Tab/Shift+Tab with Alt
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.AltModifier)) {
            tabWasPressed = true;
            if (appModel.count > 0) {
                var dir = (event.key === Qt.Key_Tab) ? 1 : -1;
                cycleSelection(dir);
            }
            event.accepted = true;
        }

        // FALLBACK: Escape
        if (event.key === Qt.Key_Escape) {
            handleEscape();
            event.accepted = true;
        }
    }

    Keys.onReleased: (event) => {
        // kbd-capture handles all keys when active
        if (kbdActive) return;

        // FALLBACK: Alt released
        if (event.key === Qt.Key_Alt) {
            altHeld = false;
            if (tabWasPressed) {
                triggerActivate();
            }
            event.accepted = true;
        }
    }

    // Highlight a specific app entry by index (used for local cycling)
    function selectByIndex(index) {
        if (index < 0 || index >= appModel.count) return;
        var entry = appModel.get(index);
        if (!entry) return;
        window.selectedAppIndex = index;
        window.selectedAppName = entry.name || "";
        window.selectedAppIcon = entry.icon || "";
        window.selectedAppExec = entry.exec || "";
        centerOnApp(index);
    }

    // Cycle selection forward (+1) or backward (-1) through the current appModel
    function cycleSelection(direction) {
        window.kbdLog("CYCLE dir=" + direction + " beforeIdx=" + selectedAppIndex + " count=" + appModel.count);
        if (appModel.count === 0) return;
        var nextIndex = (selectedAppIndex + direction + appModel.count) % appModel.count;
        selectByIndex(nextIndex);
    }

    // Find an app by ID in the current appModel and highlight it
    function updateSelection(selectedId) {
        for (var i = 0; i < appModel.count; i++) {
            var entry = appModel.get(i);
            if (entry && entry.id === selectedId) {
                selectByIndex(i);
                break;
            }
        }
    }

    // Activate the currently selected app — focus if running, launch if not
    function triggerActivate() {
        var idx = window.selectedAppIndex;
        window.kbdLog("ACTIVATE idx=" + idx + " count=" + appModel.count);
        if (idx < 0 || idx >= appModel.count) { window.kbdLog("ACTIVATE_SKIP bad idx"); return; }
        var entry = appModel.get(idx);
        if (!entry) { window.kbdLog("ACTIVATE_SKIP no entry"); return; }
        window.kbdLog("ACTIVATE app=" + entry.id + " running=" + entry.running);

        if (entry.running) {
            // Focus running app, then hide overlay
            window._openingOverlay = false;  // Reset guard
            var cmd = "echo '" + JSON.stringify({type: "activate", app: entry.id}).replace(/'/g, "'\\''") + "' | nc -U " + daemonSocket;
            Quickshell.execDetached(["bash", "-c", cmd]);
            window.visible = false;
            if (window.panelWindow) {
                window.panelWindow.visible = false;
            }
        } else {
            // Launch and track non-running app, then focus it
            Quickshell.execDetached(["bash", "-c", entry.exec || entry.id]);
            daemonRequest("track_launch", {app: entry.id}, function(r) {});
            // Also send activate to focus the app once it launches
            var cmd = "echo '" + JSON.stringify({type: "activate", app: entry.id}).replace(/'/g, "'\\''") + "' | nc -U " + daemonSocket;
            Quickshell.execDetached(["bash", "-c", cmd]);
            closeOverlay();
        }
    }

    // Tiered Escape: clear search first, then close overlay
    function handleEscape() {
        window.kbdLog("ESCAPE searchLen=" + searchInput.text.length);
        if (searchInput.text.length > 0) {
            // Tier 1: Clear search, restore full sphere
            searchInput.text = "";
            searchQuery = "";
            searchTimer.running = false;
            if (currentMruList.length > 0) {
                restoreFullSphere();
            }
        } else {
            // Tier 2: Close overlay immediately
            window.kbdLog("ESCAPE closing overlay");
            closeOverlay();
            daemonRequest("cancel", {}, function(r) {});
        }
    }

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
        searchTimer.running = true;
    }

    // Run Fuse.js search and update the sphere model
    function executeSearch() {
        if (searchQuery === "") {
            // Don't call restoreFullSphere here — the model was already
            // populated by get_mru response in openOverlay.
            // Calling it again would clear/repopulate unnecessarily,
            // triggering TypeErrors in delegate bindings during transition.
            window.sphereZoom = 1.0;
            return;
        }

        if (!fuseIndex) return;

        var results = fuseIndex.search(searchQuery);
        var topResults = results.slice(0, cfg.totalApps || 20);
        populateSearchResults(topResults);

        if (appModel.count > 0) {
            selectedAppIndex = 0;
            selectedAppName = appModel.get(0).name || "";
            selectedAppIcon = appModel.get(0).icon || "";
            selectedAppExec = appModel.get(0).exec || "";
            centerOnApp(0);
            sphereZoom = sphereSelectedZoom;
        }
    }

    // Populate appModel with Fuse results (running first, then non-running by score)
    function populateSearchResults(fuseResults) {
        appModel.clear();

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
            appModel.append(running[k]);
        }
        for (var l = 0; l < nonRunning.length; l++) {
            appModel.append(nonRunning[l]);
        }
    }

    // Restore the sphere to the daemon's MRU list
    function restoreFullSphere() {
        if (currentMruList.length === 0) return;
        appModel.clear();
        for (var i = 0; i < currentMruList.length; i++) {
            appModel.append(currentMruList[i]);
        }
        window.selectedAppIndex = savedSelectionIndex >= 0 ? savedSelectionIndex : 0;
        window.sphereZoom = 1.0;
        if (window.selectedAppIndex >= 0 && window.selectedAppIndex < appModel.count) {
            var entry = appModel.get(window.selectedAppIndex);
            window.selectedAppName = entry.name || "";
            window.selectedAppIcon = entry.icon || "";
            window.selectedAppExec = entry.exec || "";
            centerOnApp(window.selectedAppIndex);
        }
    }

    function launchApp(appName, execStr) {
        // Legacy launch — preserves existing mouse-click behavior
        Quickshell.execDetached(["bash", "-c", execStr]);
        closeSequence.start();
    }

    // ═══════════════════════════════════════════════════════════════
    // Stars background
    // ═══════════════════════════════════════════════════════════════

    Item {
        anchors.fill: parent
        opacity: window.introPhase

        Repeater {
            model: window.starCount
            Rectangle {
                property real seed: Math.random()
                x: seed * window.width
                y: Math.random() * window.height
                width:  window._s2 + Math.random() * window._s2
                height: width
                radius: width / 2
                color:  window.polyText
                opacity: window.starOpacityMin + Math.random() * (window.starOpacityMax - window.starOpacityMin)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // 3D Scene
    // ═══════════════════════════════════════════════════════════════

    Item {
        id: scene3D
        anchors.fill: parent
        opacity: window.introPhase
        scale: 0.8 + (0.2 * window.introPhase)

        MouseArea {
            id: sceneMouse
            anchors.fill: parent
            property real lastX: 0
            property real lastY: 0
            onPressed: mouse => {
                searchRotXAnim.stop();
                searchRotYAnim.stop();
                lastX = mouse.x;
                lastY = mouse.y;
            }
            onPositionChanged: mouse => {
                if (!pressed) return;
                let dx = mouse.x - lastX;
                let dy = mouse.y - lastY;
                window.rotY += dx * window.mouseDragSens;
                let newRotX = window.rotX - dy * window.mouseDragSens;
                window.rotX = Math.max(-window.mouseMaxRot, Math.min(window.mouseMaxRot, newRotX));
                lastX = mouse.x;
                lastY = mouse.y;
            }
            onClicked: searchInput.forceActiveFocus()
        }

        Item {
            id: origin
            anchors.centerIn: parent
            width:  window.baseSphereRadius * 2
            height: window.baseSphereRadius * 2

            Repeater {
                id: appRepeater
                model: appModel

                delegate: Item {
                    id: appNode

                    // Safe model access — model may be undefined during transitions
                    readonly property var _m: model || {}
                    readonly property string _name: String(_m.name || "")
                    readonly property string _icon: String(_m.icon || "")
                    readonly property string _exec: String(_m.exec || "")

                    property var proj: (typeof index !== "undefined" && window.projCache && window.projCache.length > index)
                                       ? window.projCache[index]
                                       : { x: 0, y: 0, z: 0 }

                    property real zoomFactor: 1.0 + (window.sphereZoom - 1.0) * window.sphereZoomWeight

                    x: (origin.width  / 2) + (proj.x * window.sphereRadius * zoomFactor) - width  / 2
                    y: (origin.height / 2) + (proj.y * window.sphereRadius * zoomFactor) - height / 2

                    z: Math.round(proj.z * 1000)

                    property bool isMatch: {
                        if (window.searchQuery === "") return true;
                        if (!_m || typeof _m.name !== "string") return false;
                        return _m.name.toLowerCase().indexOf(window.searchQuery) !== -1;
                    }
                    property bool isSelected: index === window.selectedAppIndex

                    property real _hz: Math.max(0.0, Math.min(1.0, proj.z * window.depthOpacityMult))
                    opacity: proj.z > 0.0 ? (isMatch ? _hz : _hz * 0.15) : 0.0
                    Behavior on opacity { NumberAnimation { duration: window.animCardFade; easing.type: Easing.OutCubic } }

                    visible: opacity > 0.01

                    property real _baseScale: window.sphereBaseScale + (Math.max(0.0, proj.z) * window.sphereScaleIncrease)
                    scale: isSelected ? 1.0 : (_baseScale * ((nodeMa.containsMouse && !isSelected) ? window.sphereHoverScale : 1.0))
                    Behavior on scale { NumberAnimation { duration: window.animCardScale; easing.type: Easing.OutCubic } }

                    property real _xNorm: proj.x / (window.sphereRadius / window.s(310.5))
                    property real _yNorm: proj.y / (window.sphereRadius / window.s(310.5))

                    transform: [
                        Rotation {
                            axis { x: 1; y: 0; z: 0 }
                            angle: appNode.isSelected ? 0 : -appNode._yNorm * window.sphereTiltX
                            origin.x: appNode.width  / 2
                            origin.y: appNode.height / 2
                        },
                        Rotation {
                            axis { x: 0; y: 1; z: 0 }
                            angle: appNode.isSelected ? 0 : appNode._xNorm * window.sphereTiltY
                            origin.x: appNode.width  / 2
                            origin.y: appNode.height / 2
                        }
                    ]

                    width:  window.acWidth
                    height: window.acHeight

                    // ── Normal app card (hidden while selected) ───────────────
                    Rectangle {
                        anchors.fill: parent
                        radius: window.acBorderRadius
                        color:  "transparent"
                        border.color: nodeMa.containsMouse && !appNode.isSelected ? window.polySurface2 : "transparent"
                        border.width: window._s2
                        Behavior on color { ColorAnimation { duration: window.animCardFade } }

                        visible: !appNode.isSelected

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: window._s5
                            spacing: window._s5

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth:  window.acIconSize
                                Layout.preferredHeight: window.acIconSize
                                source: appNode._icon
                                    ? (appNode._icon.startsWith("/") ? "file://" + appNode._icon : "image://icon/" + appNode._icon)
                                    : "image://icon/application-x-executable"
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                cache: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: labelText.implicitHeight + window._s4
                                radius: window._s4
                                color: Qt.rgba(window.polyCrust.r, window.polyCrust.g, window.polyCrust.b, 0.60)

                                Text {
                                    id: labelText
                                    anchors.fill: parent
                                    anchors.leftMargin:  window._s3
                                    anchors.rightMargin: window._s3
                                    text: appNode._name
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.acFontSize
                                    font.weight: Font.DemiBold
                                    color: window.polyText
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // ── Satellite detail view (when selected) ────────────────
                    Loader {
                        id: satLoader
                        anchors.centerIn: parent
                        active: appNode.isSelected
                        opacity: appNode.isSelected ? 1.0 : 0.0
                        scale:   appNode.isSelected ? cfg.animations?.satelliteTargetScale ?? 1.5 : (cfg.animations?.satelliteInitialScale ?? 0.4)

                        Behavior on opacity { NumberAnimation { duration: window.animSatFade; easing.type: Easing.OutCubic } }
                        Behavior on scale   { NumberAnimation { duration: window.animSatScale; easing.type: Easing.OutBack  } }

                        sourceComponent: Component {
                            Item {
                                readonly property real satW: window._sat_panelW + window._sat_strutW
                                                           + window._sat_hullW
                                                           + window._sat_strutW + window._sat_panelW
                                readonly property real satH: window._sat_hullH
                                                           + window._sat_antennaH
                                                           + window._sat_thrusterH
                                                           + window.s(11)

                                width:  satW
                                height: satH

                                // Left solar panel
                                Rectangle {
                                    id: lPanel
                                    width:  window._sat_panelW
                                    height: window._sat_panelH
                                    anchors.right: lStrut.left
                                    anchors.verticalCenter: hull.verticalCenter
                                    color: window.polyMantle
                                    border.color: Qt.alpha(window.polySurface2, 0.4)
                                    border.width: 1
                                    radius: window._sat_radius4

                                    Grid {
                                        anchors.fill: parent
                                        anchors.margins: window._sat_screenM * 0.5
                                        columns: 4; rows: 4
                                        spacing: window._s2
                                        Repeater {
                                            model: 16
                                            Rectangle {
                                                width:  (lPanel.width  - window._sat_screenM - 3 * window._s2) / 4
                                                height: (lPanel.height - window._sat_screenM - 3 * window._s2) / 4
                                                color: Qt.alpha(window.polyBlue, index % 3 === 0 ? 0.15 : 0.05)
                                                radius: 1
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: lStrut
                                    width:  window._sat_strutW
                                    height: window._sat_strutH
                                    anchors.right: hull.left
                                    anchors.verticalCenter: hull.verticalCenter
                                    color: Qt.alpha(window.polySurface2, 0.5)
                                }

                                // Central hull
                                Rectangle {
                                    id: hull
                                    width:  window._sat_hullW
                                    height: window._sat_hullH
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: (window._sat_antennaH - window._sat_thrusterH) * 0.5
                                    color: window.polyBase
                                    border.color: Qt.alpha(window.polySurface1, 0.6)
                                    border.width: 1.5
                                    radius: window._sat_radius12

                                    // Antenna
                                    Rectangle {
                                        width:  window._sat_antStick
                                        height: window._sat_antennaH
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.horizontalCenterOffset: -window._sat_antOffX
                                        anchors.bottom: parent.top
                                        color: Qt.alpha(window.polySurface2, 0.7)
                                        radius: 1
                                        Rectangle {
                                            width:  window._sat_antBall
                                            height: window._sat_antBall
                                            radius: width / 2
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.top
                                            color: window.polyBlue
                                        }
                                    }

                                    // Screen showing selected app
                                    Rectangle {
                                        id: notifScreen
                                        anchors.fill: parent
                                        anchors.margins: window._sat_screenM
                                        color: window.polyMantle
                                        radius: window._sat_radius8
                                        border.color: Qt.alpha(window.polySurface0, 0.5)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: window._sat_innerM
                                            spacing: window._sat_spacing

                                            Image {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredWidth:  window._sat_iconSz
                                                Layout.preferredHeight: window._sat_iconSz
                                                source: window.selectedAppIcon
                                                    ? (window.selectedAppIcon.startsWith("/")
                                                       ? "file://" + window.selectedAppIcon
                                                       : "image://icon/" + window.selectedAppIcon)
                                                    : "image://icon/application-x-executable"
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                cache: true
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.fillWidth: true
                                                text: window.selectedAppName
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: window._sat_fontSize
                                                font.weight: Font.Bold
                                                color: window.polyText
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    // Thruster
                                    Rectangle {
                                        width:  window._sat_thrBase
                                        height: window._sat_thrusterH * 0.5
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        color: window.polySurface1
                                        radius: 2
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.bottom
                                            width:  parent.width * 0.6
                                            height: window._sat_thrusterH
                                            radius: width / 2
                                            color: Qt.alpha(window.polySapphire, 0.35)
                                        }
                                    }
                                }

                                // Right solar panel
                                Rectangle {
                                    id: rPanel
                                    width:  window._sat_panelW
                                    height: window._sat_panelH
                                    anchors.left: rStrut.right
                                    anchors.verticalCenter: hull.verticalCenter
                                    color: window.polyMantle
                                    border.color: Qt.alpha(window.polySurface2, 0.4)
                                    border.width: 1
                                    radius: window._sat_radius4

                                    Grid {
                                        anchors.fill: parent
                                        anchors.margins: window._sat_screenM * 0.5
                                        columns: 4; rows: 4
                                        spacing: window._s2
                                        Repeater {
                                            model: 16
                                            Rectangle {
                                                width:  (rPanel.width  - window._sat_screenM - 3 * window._s2) / 4
                                                height: (rPanel.height - window._sat_screenM - 3 * window._s2) / 4
                                                color: Qt.alpha(window.polyBlue, index % 3 === 0 ? 0.15 : 0.05)
                                                radius: 1
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: rStrut
                                    width:  window._sat_strutW
                                    height: window._sat_strutH
                                    anchors.left: hull.right
                                    anchors.verticalCenter: hull.verticalCenter
                                    color: Qt.alpha(window.polySurface2, 0.5)
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: nodeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.launchApp(model.name, model.exec)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Search bar
    // ═══════════════════════════════════════════════════════════════

    Rectangle {
        id: searchContainer
        width:  window.sbWidth
        height: window.sbHeight
        anchors.bottom: parent.bottom
        anchors.bottomMargin: window.sbBottomMargin
        anchors.horizontalCenter: parent.horizontalCenter

        radius: window.sbBorderRadius
        color: Qt.rgba(window.polyMantle.r, window.polyMantle.g, window.polyMantle.b, window.sbBgOpacity)
        border.color: searchInput.activeFocus ? window.polyMauve : window.polySurface1
        border.width: window.sbBorderWidth

        opacity: window.introPhase
        transform: Translate { y: (1 - window.introPhase) * window._s40 }
        Behavior on border.color { ColorAnimation { duration: window.animCardFade } }

        layer.enabled: window.introPhase > 0.01
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: window.sbShadowOpacity
            shadowBlur: window.sbShadowBlur
            shadowVerticalOffset: window._s4
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  window._s20
            anchors.rightMargin: window._s20
            spacing: window._s12

            Text {
                text: ""
                font.family: "Iosevka Nerd Font"
                font.pixelSize: window._s18
                color: searchInput.activeFocus ? window.polyMauve : window.polySubtext0
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            TextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                background: Item {}
                color: window.polyText
                font.family: "JetBrains Mono"
                font.pixelSize: window._s15
                font.weight: Font.Medium
                selectByMouse: true

                placeholderText: "Search applications..."
                placeholderTextColor: window.polyOverlay0
                verticalAlignment: TextInput.AlignVCenter

                onTextChanged: window.handleSearchInput(text)
            }

            Text {
                visible: searchInput.text.length > 0
                text: ""
                font.family: "Iosevka Nerd Font"
                font.pixelSize: window._s16
                color: window.polySubtext0
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }
        }
    }
}
