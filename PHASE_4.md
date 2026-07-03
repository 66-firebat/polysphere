# Phase 4: Lua Daemon with Integrated Keyboard Capture

**Goal:** Rewrite the Guile Scheme daemon (`daemon.scm`) in Lua, consolidating keyboard capture into the same process for a unified event-driven architecture. The daemon handles ALL keyboard and application logic; QML becomes a pure renderer.

**Dependencies:** Lua 5.2.4 (via Nix profile with luasocket, luaposix, dkjson), `hyprctl`, Linux evdev.

---

## 1. Architecture

### Current (Phase 3, Guile-based)

```
┌──────────────┐  IPC (request-response)  ┌──────────────────┐
│ polysphere.qml│◄────────────────────────►│ daemon.scm (Guile)│
│              │  get_mru, activate,       │ MRU list, socket │
│ Keys.onPressed│  track_launch, cancel     │ hyprctl          │
│ (key handling)│                          │                  │
└──────┬───────┘                          └──────────────────┘
       │ Hyprland intercepts Alt+Tab
       ▼ Problems: compositor eats keys, workaround via IPC, fragile
```

### Target (Phase 4, Lua-based)

```
┌──────────────────────────────────────────────────────────────────┐
│ daemon.lua (Lua 5.2) — ONE PROCESS, ALL LOGIC                    │
│                                                                  │
│  ┌─────────────────────┐  poll()  ┌─────────────────────────┐   │
│  │ Unix Socket Server  │◄────────►│ Event & State Machine    │   │
│  │ (request socket)    │          │                          │   │
│  └─────────┬───────────┘          │ - get_mru, activate      │   │
│            │                      │ - cycle_next/prev        │   │
│  ┌─────────┴───────────┐  poll()  │ - cancel, Escape, search │   │
│  │ evdev Keyboard      │◄────────►│ - track_launch           │   │
│  │ (/dev/input/event*) │          │                          │   │
│  └─────────────────────┘          └─────────────┬────────────┘   │
│                                                  │               │
│  ┌─────────────────────┐                         │               │
│  │ Persistent QML Push │◄────────────────────────┘               │
│  │ Stream Socket       │  State updates:                         │
│  │                     │  - selection_changed                    │
│  └─────────────────────┘  - activate                             │
│                            - close                               │
│                            - search_update                       │
│                            - mru_updated                         │
└──────────────────────────────────────────────────────────────────┘
                        │
                        │ Two Unix sockets:
                        │   1. Request socket (existing): QML → daemon requests
                        │   2. Push socket (NEW): daemon → QML state updates
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│ polysphere.qml — PURE RENDERER                                   │
│                                                                  │
│  - Renders what daemon tells it                                  │
│  - No Keys.onPressed/onReleased for Alt/Tab/Escape               │
│  - No cycling logic                                              │
│  - No search logic (daemon sends filtered results)               │
│  - Receives state updates via persistent connection              │
│  - Sends config/app requests via existing request-response       │
│  - IpcHandler.toggle() still triggers open/close                 │
└──────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Language** | Lua 5.2 | Available on NixOS; `luaposix` for poll/evdev |
| **Keyboard capture** | Integrated in daemon | One process, one event loop, OSE poll loop |
| **Event loop** | `posix.poll()` | Multiplex raw FDs (socket + evdev) in one call |
| **Keyboard grab** | On-demand | Only grab when overlay is open; always release when closed |
| **Key/mouse handling** | Daemon does ALL logic | QML is a pure renderer — no cycling, search, or activation logic |
| **Daemon → QML updates** | Persistent push socket | Daemon opens a long-lived connection to QML and streams state updates |
| **QML → Daemon requests** | Request-response (existing) | Same `daemonRequest()` / `nc` pattern for get_mru, get_app_db, etc. |
| **Config** | Reads `polysphere.json` | Same file, same format |
| **Desktop files** | Scanned at startup | Same behavior as Guile daemon |

---

## 2. Dual-Socket Architecture

The daemon now manages **two Unix sockets**:

```
Socket 1: Request socket (existing)
────────────────────────────────────
Path: $XDG_RUNTIME_DIR/polysphere.sock (or --socket / $POLYSPHERE_SOCKET)
Type: One-shot accept → read → respond → close
Purpose: QML sends get_mru, activate, get_app_db, track_launch
Protocol: Same as Guile daemon — JSON line, one response per connection

Socket 2: Push socket (NEW)
────────────────────────────
Path: $XDG_RUNTIME_DIR/polysphere-state.sock (or --push-socket)
Type: Persistent connection — client connects, daemon pushes state updates
Purpose: Daemon streams state changes to QML in real time
Protocol: Newline-delimited JSON, one message per state change
Lifecycle: 
  - QML connects at startup (or when overlay opens)
  - Daemon accepts and keeps the connection open
  - Daemon writes state updates as they happen
  - Reconnection handled automatically if connection drops
```

### Why two sockets?

- **Request socket** preserves the existing QML → daemon contract. No changes needed for `daemonRequest()` in QML.
- **Push socket** is purely additive. QML opens a second `Process` (or `Socket` via Quickshell) that listens for state updates.
- Separation of concerns: requests are synchronous and one-shot; state pushes are asynchronous and streaming.

---

## 3. Daemon State Machine

The daemon maintains an internal state machine that drives both keyboard handling and QML state pushes:

```
      ┌─────────────────────────────────────────────────────────┐
      │                    IDLE                                  │
      │  No overlay visible. Keyboard NOT grabbed.               │
      │  Listening on request socket only.                       │
      │  Push socket: connected (QML process running), but       │
      │  no state updates sent.                                  │
      └──────────┬──────────────────────────────────────────────┘
                 │ QML sends: toggle / open / IpcHandler.toggle()
                 │ OR: first Alt+Tab from kbd-capture
                 ▼
      ┌─────────────────────────────────────────────────────────┐
      │                    OPENING                                │
      │  - Grab keyboard (EVIOCGRAB)                              │
      │  - Run hyprctl clients to build initial state             │
      │  - Build MRU list + whitelist backfill                    │
      │  - Push: {"type":"open","mru":[...],"selected":"..."}     │
      └──────────┬──────────────────────────────────────────────┘
                 ▼
      ┌─────────────────────────────────────────────────────────┐
      │                    ACTIVE                                 │
      │  Keyboard grabbed. Daemon handles:                       │
      │    Alt+Tab → open overlay, then cycle                    │
      │    Tab (while Alt held) → cycle forward                  │
      │    Shift+Tab → cycle backward                            │
      │    Letter keys → build search query, filter apps         │
      │    Backspace → edit search query                         │
      │    Escape → clear search, then close                     │
      │    Alt release → activate / launch selected               │
      │    Mouse drag → send rotation deltas to QML              │
      │                                                          │
      │  On each state change, push update to QML:               │
      │    {"type":"selection","selected":"kitty","index":3}     │
      │    {"type":"search","query":"fi","results":[...]}        │
      │    {"type":"search_cleared"}                             │
      └──────────┬──────────────────────────────────────────────┘
                 │ Alt release → activate, OR Escape → close
                 ▼
      ┌─────────────────────────────────────────────────────────┐
      │                    CLOSING                                │
      │  - Release keyboard (EVIOCGRAB 0)                        │
      │  - Push: {"type":"close"}                                 │
      │  - QML plays exit animation                              │
      └──────────┬──────────────────────────────────────────────┘
                 ▼
      ┌─────────────────────────────────────────────────────────┐
      │                    IDLE                                  │
      └─────────────────────────────────────────────────────────┘
```

### State Transitions via IPC

The Hyprland bind still calls `toggle-launcher.sh` which does:
```bash
quickshell ipc call polysphere toggle
```

This triggers `IpcHandler.toggle()` in QML, which sends a request to the daemon to open/close. The daemon also detects Alt+Tab from the evdev stream and can self-trigger open.

---

## 4. Daemon Implementation Plan (`daemon.lua`)

### 4.1 Module Structure

```
daemon.lua
├── 1. Imports & Constants
├── 2. CLI Parser (--help, --config, --socket, --push-socket, --verbose)
├── 3. Logging
│   ├── log(level, msg) → stderr + /tmp/polysphere.log
│   └── log_verbose(msg) → only when --verbose
├── 4. Config Reader
│   ├── read_config(path) → Lua table
│   ├── get_whitelisted_apps()
│   ├── get_total_apps()
│   └── get_max_entries()
├── 5. App Database (.desktop scanner)
│   ├── scan_desktop_files() → [{id, name, icon, exec}, ...]
│   └── lookup_app(id) → entry or nil
├── 6. MRU State
│   ├── mru_push_front(app_id)
│   ├── mru_remove(app_id)
│   ├── get_cursor() / set_cursor(idx)
│   └── get_mru_list()
├── 7. hyprctl Wrapper
│   ├── run_hyprctl(...) → string
│   ├── get_running_apps() → {class=true, ...}
│   └── focus_app(app_id)
├── 8. evdev Keyboard Capture
│   ├── auto_detect_kbd() → path
│   ├── open_kbd(path) → file handle
│   ├── parse_input_event(bytes) → {key, value, mods}
│   ├── grab_kbd(fd, bool)
│   ├── update_modifiers(event)
│   └── get_modifiers() → {alt, ctrl, shift}
├── 9. Socket Servers
│   ├── start_request_socket(path) → server fd
│   ├── start_push_socket(path) → server fd
│   ├── handle_request_client(client)
│   └── handle_push_client(client)
├── 10. Request Handlers
│   ├── handle_get_mru()
│   ├── handle_cycle_next()
│   ├── handle_cycle_prev()
│   ├── handle_activate(app)
│   ├── handle_cancel()
│   ├── handle_get_app_db()
│   └── handle_track_launch(app)
├── 11. Keyboard State Machine
│   ├── on_key_event(event)
│   ├── on_alt_pressed()
│   ├── on_alt_released()
│   ├── on_tab_pressed()
│   ├── on_escape_pressed()
│   ├── on_letter_key(key)
│   └── on_backspace()
├── 12. QML State Push
│   ├── push_state(table) — serialize + write to push socket
│   ├── push_selection(selected, index)
│   ├── push_search(query, results)
│   ├── push_open(mru, selected)
│   └── push_close()
├── 13. Search Engine
│   ├── build_search_index(apps)
│   ├── search(query) → results with scores
│   └── filter_by_query(query) → sorted results
├── 14. Main Loop
│   ├── poll({{fd, events}, ...}) → ready fds
│   ├── handle_key_fd()
│   ├── handle_request_fd()
│   ├── handle_push_fd()
│   └── state_machine()
└── 15. main()
```

### 4.2 CLI Interface

```
Usage: lua daemon.lua [OPTIONS]

PolySphere MRU Daemon — tracks Most Recently Used applications,
manages window focus, and captures keyboard events for the
PolySphere Alt+Tab switcher.

OPTIONS:
  -h, --help                    Print this help message and exit
  -c, --config PATH             Path to polysphere.json config file
                                (default: $POLYSPHERE_CONFIG or
                                 ~/.config/polysphere/polysphere.json)
  -s, --socket PATH             Path for the request-response socket
                                (default: $POLYSPHERE_SOCKET or
                                 $XDG_RUNTIME_DIR/polysphere.sock)
  -p, --push-socket PATH        Path for the state-push socket
                                (default: $XDG_RUNTIME_DIR/polysphere-state.sock)
  -k, --kbd-device PATH         Path to keyboard evdev device (auto-detect if not set)
  -v, --verbose                 Enable verbose logging
```

### 4.3 Config — No Changes

Same `polysphere.json` format. No new config keys needed. The existing `keybindings` block is read by the daemon's state machine, not by QML.

### 4.4 evdev Keyboard Handling

```lua
-- struct input_event on x86_64 Linux:
-- [8 bytes sec][8 bytes usec][2 bytes type][2 bytes code][4 bytes value]
local EVENT_SIZE = 24

local function parse_input_event(bytes)
  if #bytes < EVENT_SIZE then return nil end
  local _, _, typ, code, value = string.unpack("i8 i8 I2 I2 i4", bytes)
  if typ ~= 1 then return nil end  -- EV_KEY only
  return { code = code, value = value, key = KEY_NAMES[code] }
end

local function read_key(fd)
  local bytes = fd:read(EVENT_SIZE)
  if not bytes or #bytes < EVENT_SIZE then return nil end
  return parse_input_event(bytes)
end
```

### 4.5 Keyboard Grab (On-Demand)

```lua
-- EVIOCGRAB = _IOW('E', 0x90, int) = (2<<30) | (69<<8) | 0x90 | (4<<0) = 0x40044590
local EVIOCGRAB = 0x40044590

local function grab_kbd(fd, grab)
  -- fd is a raw file descriptor (number), opened via posix.open
  posix.ioctl(fd, EVIOCGRAB, grab and 1 or 0)
end

-- On overlay open:
kbd_fd = posix.open(kbd_path, bit32.bor(bit32.rshift(bit32.bnot(0), 1), 0)) -- O_RDONLY | O_NONBLOCK
grab_kbd(kbd_fd, true)  -- Exclusive access while overlay is active

-- On overlay close:
grab_kbd(kbd_fd, false) -- Release exclusive access
```

### 4.6 Main Poll Loop

```lua
local function main_loop()
  local state = "idle" -- idle | opening | active | closing
  local mods = { alt = false, ctrl = false, shift = false }
  local mru_list = {}
  local mru_cursor = 0
  local search_query = ""
  local selected_index = 0
  local app_db = {}
  
  -- Set up sockets
  local req_srv = start_request_socket(config.socket)
  local push_srv = start_push_socket(config.push_socket)
  local push_client = nil  -- set when QML connects
  
  -- FDs for poll: { fd, events, callback }
  local poll_fds = {
    { fd = req_srv:getfd(), events = "in", cb = accept_request },
    { fd = push_srv:getfd(), events = "in", cb = accept_push },
  }
  local kbd_fd = nil
  
  while running do
    -- Add/remove kbd_fd based on state
    if state == "active" and not has_kbd(poll_fds) then
      open_and_grab_kbd()
      add_kbd_to_poll()
    elseif state ~= "active" and has_kbd(poll_fds) then
      release_kbd()
      remove_kbd_from_poll()
    end
    
    local ready = posix.poll(poll_fds, -1)  -- infinite timeout
    
    for _, rfd in ipairs(ready) do
      for _, pfd in ipairs(poll_fds) do
        if pfd.fd == rfd then pfd.cb() end
      end
    end
  end
end
```

### 4.7 Request Handlers — Same Protocol

All seven handlers maintain the same JSON request/response format as the Guile daemon:

| Request | Response | Side Effects |
|---|---|---|
| `{"type":"get_mru"}` | `{"mru":[...],"current":"...","selected":"..."}` | Runs hyprctl clients, builds segments |
| `{"type":"cycle_next"}` | `{"selected":"..."}` | Advances cursor |
| `{"type":"cycle_prev"}` | `{"selected":"..."}` | Retreats cursor |
| `{"type":"activate","app":"kitty"}` | `{"ok":true/false,"reason":"..."}` | Focuses app via hyprctl |
| `{"type":"cancel"}` | `{"ok":true}` | No-op |
| `{"type":"get_app_db"}` | `{"apps":[...]}` | Returns cached .desktop database |
| `{"type":"track_launch","app":"gimp"}` | `{"ok":true}` | Adds to MRU |

### 4.8 Push Socket Protocol — State Updates

The daemon pushes these state updates to QML over the persistent connection:

```json
// Overlay should open with initial state
{"type":"open","mru":[{"id":"firefox","name":"Firefox","icon":"firefox","exec":"firefox %u","running":true},...],"selected":"kitty","search":""}

// Selection changed (cycling)
{"type":"selection","selected":"kitty","index":3}

// Search update (daemon ran Fuse.js internally)
{"type":"search","query":"fi","results":[{"id":"firefox","name":"Firefox","icon":"firefox"},...]}

// Search cleared
{"type":"search_cleared"}

// Overlay should close
{"type":"close"}

// Activate result
{"type":"activated","app":"kitty","ok":true}

// Launch result (non-running app)
{"type":"launched","app":"spotify","ok":true}

// MRU list changed (e.g., after track_launch)
{"type":"mru_updated","mru":[...],"selected":"..."}

// Error
{"type":"error","message":"..."}
```

### 4.9 Keyboard State Machine

```lua
local function on_key_event(evt)
  if not evt then return end
  
  -- Track modifiers
  if evt.key == "alt_left" or evt.key == "alt_right" then
    mods.alt = (evt.value == 1)  -- press or release
    if not mods.alt and state == "active" then
      -- Alt released: activate selected app
      trigger_activate()
    end
    return
  end
  
  -- Ignore key releases for action keys (only handle press = 1)
  if evt.value ~= 1 then return end
  
  if state == "idle" then
    -- Alt+Tab while idle: open overlay
    if mods.alt and evt.key == "tab" then
      state = "opening"
      open_overlay()
    end
    return
  end
  
  if state == "active" then
    -- Tab while Alt held: cycle
    if evt.key == "tab" and mods.alt then
      cycle_forward()
      return
    end
    
    -- Escape: tiered (clear search → close)
    if evt.key == "esc" then
      handle_escape()
      return
    end
    
    -- Backspace: edit search
    if evt.key == "backspace" then
      search_query = search_query:sub(1, -2)
      if search_query == "" then
        push_state({ type = "search_cleared" })
        push_state(build_current_state())
      else
        local results = search_apps(search_query)
        push_state({ type = "search", query = search_query, results = results })
      end
      return
    end
    
    -- Letter/digit keys: build search query
    if #evt.key == 1 and evt.key:match("[a-zA-Z0-9]") then
      search_query = search_query .. evt.key
      local results = search_apps(search_query)
      push_state({ type = "search", query = search_query, results = results })
      return
    end
  end
end
```

### 4.10 Search Engine (Simplified — Bundled in Daemon)

Instead of Fuse.js (which is JS-only), the daemon uses a **simple fuzzy match** in Lua:

```lua
local function fuzzy_match(query, text)
  -- Case-insensitive: check if all characters in query appear
  -- in order within text
  query = query:lower()
  text = text:lower()
  
  local qi = 1
  for ti = 1, #text do
    if text:sub(ti, ti) == query:sub(qi, qi) then
      qi = qi + 1
      if qi > #query then return true end
    end
  end
  return qi > #query
end

local function search_apps(query)
  if query == "" then return get_current_app_list() end
  
  local results = {}
  local running_ids = get_running_set()
  
  -- Running apps first (switching targets)
  for _, app in ipairs(app_db) do
    if running_ids[app.id] and 
       (fuzzy_match(query, app.name) or fuzzy_match(query, app.id)) then
      table.insert(results, app)
    end
  end
  
  -- Then non-running apps
  for _, app in ipairs(app_db) do
    if not running_ids[app.id] and
       (fuzzy_match(query, app.name) or fuzzy_match(query, app.id)) then
      table.insert(results, app)
    end
  end
  
  -- Limit to totalApps
  local limit = config.totalApps or 20
  local top = {}
  for i = 1, math.min(#results, limit) do
    table.insert(top, results[i])
  end
  return top
end
```

### 4.11 Desktop File Scanner

```lua
local DESKTOP_PATHS = {
  os.getenv("HOME") .. "/.local/share/applications",
  "/usr/share/applications",
  "/usr/local/share/applications",
  "/run/current-system/sw/share/applications",
}

local function parse_desktop(path)
  local file = io.open(path, "r")
  if not file then return nil end
  
  local app = { id = nil, name = nil, icon = "application-x-executable", 
               exec = nil, no_display = false }
  local in_entry = false
  
  for line in file:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then goto continue end
    
    local section = trimmed:match("^%[(.-)%]$")
    if section then
      in_entry = (section == "Desktop Entry")
    elseif in_entry then
      local key, val = trimmed:match("^(.-)=(.*)$")
      if key and val then
        key = key:match("^%s*(.-)%s*$")
        val = val:match("^%s*(.-)%s*$")
        if key == "Name" then app.name = val
        elseif key == "Icon" then app.icon = val
        elseif key == "Exec" then app.exec = val
        elseif key == "NoDisplay" and val == "true" then app.no_display = true
        end
      end
    end
    ::continue::
  end
  file:close()
  
  if not app.name or app.no_display then return nil end
  
  local id = path:match("/([^/]+)%.desktop$")
  if not id then return nil end
  app.id = id
  return app
end

local function scan_all()
  local all = {}
  for _, dir in ipairs(DESKTOP_PATHS) do
    local pipe = io.popen("ls -1 \"" .. dir .. "\"/*.desktop 2>/dev/null")
    if pipe then
      for path in pipe:lines() do
        local app = parse_desktop(path)
        if app then table.insert(all, app) end
      end
      pipe:close()
    end
  end
  return all
end
```

---

## 5. QML Changes (`polysphere.qml`)

### 5.1 What Changes

| Current Feature | Phase 4 Change |
|---|---|
| `Keys.onPressed` for Alt/Tab/Escape/letters | **REMOVED** — daemon handles all keys |
| `Keys.onReleased` for Alt release | **REMOVED** — daemon detects Alt release via evdev |
| `cycleSelection(direction)` | **REMOVED** — daemon handles cycling |
| `handleSearchInput(text)` | **REMOVED** — daemon handles search |
| `executeSearch()` / Fuse.js | **REMOVED** — daemon handles search internally |
| `triggerActivate()` / `handleEscape()` | **REMOVED** — daemon sends open/close/activate pushes |
| `daemonRequest()` / `daemonProcess` | **KEPT** — for get_mru, get_app_db, activate, etc. |
| `daemonRequest("activate", ...)` | **KEPT** — may still be used for explicit activate from QML |
| `populateSphereFromMru(response)` | **KEPT** but simplified — only receives state from push socket |
| `config/colors/sphere rendering` | **KEPT** — unchanged |
| `satellite detail view` | **KEPT** — unchanged |
| `closeSequence` animation | **KEPT** — triggered by `{"type":"close"}` push instead of local logic |
| `IpcHandler.toggle()` | **KEPT** — still triggers open/close from Hyprland bind |
| `MouseArea` for drag | **KEPT** — daemon doesn't handle mouse; QML keeps mouse rotation |

### 5.2 New: Push Socket Listener

QML needs a persistent connection to the daemon's push socket. Since QML `Process` fires `onStreamFinished` on exit (not per-line), we use a **helper Lua script** that stays connected:

```qml
function setupPushSocket() {
    pushStreamProcess.command = [
        "lua", "lib/push_listener.lua", daemonSocket.replace("polysphere.sock", "polysphere-state.sock")
    ];
    pushStreamProcess.running = true;
}

// Process that reads state updates from the daemon push socket
Process {
    id: pushStreamProcess
    running: false
    stdout: StdioCollector {
        onStreamFinished: {
            // Each invocation of the listener gets one push message
            var txt = this.text.trim();
            if (txt.length > 0) {
                try {
                    var state = JSON.parse(txt);
                    handleStatePush(state);
                } catch(e) {
                    console.log("POLYSPHERE: Push parse error:", String(e));
                }
            }
            // Restart the listener for the next push message
            pushStreamProcess.running = false;
            pushStreamProcess.running = true;
        }
    }
}
```

**`lib/push_listener.lua`** — Helper that connects to the push socket, reads one line, prints it, and exits:

```lua
#!/usr/bin/env lua
-- Push listener: connects to polysphere-state.sock, reads one line, prints it
-- QML restarts this process for each push message
local socket = require("socket")
local unix = require("socket.unix")

local client = unix()
client:connect(arg[1])
local line = client:receive("*l")
if line then
  print(line)
  io.write(line .. "\n")
  io.flush()
end
client:close()
```

Alternatively, if Quickshell's `Socket` type supports connecting to a Unix socket as a client (not just `SocketServer` which listens):

```qml
Socket {
    id: pushSocket
    // Connect to daemon's push socket as a persistent client
    // Only if Quickshell supports client-mode sockets
}
```

### 5.3 State Update Handler

```qml
function handleStatePush(state) {
    switch (state.type) {
    case "open":
        // Display overlay with initial MRU data
        populateSphereFromMru(state);
        window.visible = true;
        panelWindow.visible = true;
        introPhaseAnim.restart();
        break;
        
    case "selection":
        // Highlight a different app
        selectByIndex(state.index);
        break;
        
    case "search":
        // Show search results
        populateSearchResults(state.results);
        searchInput.text = state.query;
        break;
        
    case "search_cleared":
        // Restore full sphere
        searchInput.text = "";
        restoreFullSphere();
        break;
        
    case "close":
        // Close overlay
        closeSequence.start();
        break;
        
    case "activated":
    case "launched":
        // Brief feedback, then close
        closeSequence.start();
        break;
        
    case "mru_updated":
        // Background update — don't change visibility
        currentMruList = state.mru;
        break;
    }
}
```

### 5.4 What QML Kicks Off on Startup

```qml
Component.onCompleted: {
    loadAppDatabase();       // Request app list via existing daemonRequest
    setupPushSocket();       // Start listening for state pushes
}
```

---

## 6. Files

### New Files

| File | Purpose |
|---|---|
| `daemon.lua` | Main Lua daemon — socket server, evdev capture, MRU, state machine |
| `lib/push_listener.lua` | Helper script for QML to read one push message from daemon |
| `shell.nix` | Nix expression for Lua 5.2 with luasocket, luaposix, dkjson |
| `tests/test_daemon_lua.sh` | Test suite for Lua daemon |
| `tests/config_lua_test.json` | Test config for Lua daemon tests |

### Modified Files

| File | Changes |
|---|---|
| `polysphere.qml` | Remove key handling, add push socket listener, simplify to pure renderer |
| `manual_start.sh` | Replace `guile daemon.scm` with `lua daemon.lua` |
| `TESTS.md` | Add PHASE_4_TESTING section |
| `README.md` | Update daemon startup, document new architecture |

### Deleted Files

| File | Reason |
|---|---|
| `daemon.scm` | Replaced by `daemon.lua` |

### Files That Need NO Changes

| File | Reason |
|---|---|
| `polysphere.json` | Same format, same config keys |
| `lib/fuse.js` | No longer needed by QML (daemon handles search) — KEPT for reference |
| `shell.qml` | No changes needed |
| `Caching.qml` | Not used |
| `Scaler.qml` | No changes needed |

---

## 7. Testing

### 7.1 Daemon Automated Tests

| # | Name | Request | Expected |
|---|---|---|---|
| T1 | Socket opens | — | Socket file exists at configured path |
| T2 | Empty get_mru | `{"type":"get_mru"}` | `{"mru":[],"current":null,"selected":null}` |
| T3 | cancel | `{"type":"cancel"}` | `{"ok":true}` |
| T4 | cycle_next (empty) | `{"type":"cycle_next"}` | `{"selected":null}` |
| T5 | cycle_prev (empty) | `{"type":"cycle_prev"}` | `{"selected":null}` |
| T6 | activate unknown app | `{"type":"activate","app":"x"}` | `{"ok":false,"reason":"app not in MRU list"}` |
| T7 | missing app field | `{"type":"activate"}` | `{"error":"missing app"}` |
| T8 | unknown request | `{"type":"bad"}` | `{"error":"unknown request type"}` |
| T9 | missing type | `{"foo":"bar"}` | `{"error":"missing type"}` |
| T10 | malformed JSON | `not json` | `{"error":"parse error"}` |
| T11 | --help | Run `lua daemon.lua --help` | Prints help |
| T12 | get_app_db | `{"type":"get_app_db"}` | App list with name, icon, exec |
| T13 | track_launch | `{"type":"track_launch","app":"test"}` | App added to MRU |
| T14 | enriched get_mru | Activate apps, then get_mru | Enriched entries with name, icon, exec |
| T15 | Config overrides | Set totalApps in config | MRU respects limit |
| T16 | Whitelist fill order | get_mru with no running | Whitelisted apps in config order |
| T17 | Push socket connects | Connect to push socket | Connection accepted |
| T18 | Push state update | Trigger state change | State update received on push socket |

### 7.2 Interactive Tests

| # | Name | Procedure | Pass Condition |
|---|---|---|---|
| K1 | Alt+Tab opens overlay | Hold Alt, press Tab | Overlay appears (detected by daemon via evdev) |
| K2 | Tab cycles forward | Hold Alt, Tab repeatedly | Selection advances. State pushed to QML. |
| K3 | Shift+Tab cycles backward | Advance 2×, Shift+Tab | Goes back one step |
| K4 | Alt+letter search | Alt+Tab, type "fi" | Search query built, results pushed to QML |
| K5 | Escape clears then closes | Type "fi", Escape (clear), Escape (close) | Tier 1 clears, Tier 2 closes |
| K6 | Release Alt activates running | Tab to running app, release Alt | App focuses, overlay closes |
| K7 | Release Alt launches | Tab to non-running app, release Alt | App launches, tracked in MRU |
| K8 | Alt+Backspace | Type "fir", Backspace | Search corrects, new results pushed |
| K9 | Full cycle | Open → cycle → activate → reopen | Clean, no degradation |
| K10 | Reopen after launch | Activate, Alt+Tab again | App appears on sphere |
| K11 | Escape with no search | Alt+Tab, Esc immediately | Overlay closes immediately |
| K12 | Push socket reconnect | Kill and restart QML | Daemon accepts new push connection |
| K13 | Keyboard released on close | Open → close → type in another app | Keyboard works normally in other apps |

---

## 8. Implementation Checklist

- [ ] **Dependencies verified** — lua + luasocket + luaposix + dkjson in Nix profile
- [ ] **Create `daemon.lua`** (~800-1000 lines):
  - [ ] CLI parser
  - [ ] Config reader
  - [ ] Logging
  - [ ] App database scanner
  - [ ] MRU state
  - [ ] hyprctl wrapper
  - [ ] evdev keyboard capture (auto-detect, open, parse, grab)
  - [ ] Mon state machine
  - [ ] Request socket server (same protocol as Guile)
  - [ ] Push socket server (new protocol for state updates)
  - [ ] Main poll loop
  - [ ] Search engine (fuzzy match)
  - [ ] All 7 request handlers
  - [ ] Signal handling (SIGINT/SIGTERM)
  - [ ] QML state push functions
- [ ] **Create `lib/push_listener.lua`** (~20 lines)
- [ ] **Update `polysphere.qml`**:
  - [ ] Add push socket listener
  - [ ] Add `handleStatePush()` function
  - [ ] Remove `Keys.onPressed`/`onReleased` for Alt/Tab/Escape/letters
  - [ ] Remove `cycleSelection()`, `handleSearchInput()`, `executeSearch()`, `triggerActivate()`, `handleEscape()`
  - [ ] Remove Fuse.js import and appDatabase/fuseIndex properties
  - [ ] Update `openOverlay()` to just make visible and wait for push
  - [ ] Update `closeSequence` to work with push
  - [ ] Keep `populateSphereFromMru()`, `selectByIndex()`, all rendering code
- [ ] **Update `manual_start.sh`** — `guile daemon.scm` → `lua daemon.lua`
- [ ] **Create tests**:
  - [ ] `tests/test_daemon_lua.sh` — automated socket tests (T1–T18)
- [ ] **Update documentation**:
  - [ ] `TESTS.md` — PHASE_4_TESTING section
  - [ ] `README.md` — new architecture, daemon startup via `lua daemon.lua`
- [ ] **Delete `daemon.scm`**
- [ ] **Run automated test suite**: all T1–T18 pass
- [ ] **Run interactive tests**: all K1–K13 pass

---

## 9. Rollback Plan

If Phase 4 breaks the system:

1. **Restore `daemon.scm`** from git
2. **Revert `polysphere.qml`** — restore Keys.onPressed/onReleased, search, cycling
3. **Revert `manual_start.sh`** — guile daemon.scm
4. **Kill Lua daemon**: `pkill -f "lua daemon.lua"`
5. **Restart Guile daemon**: `guile daemon.scm --verbose`
6. **Delete `daemon.lua`** from repo
