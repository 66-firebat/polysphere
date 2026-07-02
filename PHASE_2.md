# Phase 2: Guile Daemon

**Goal:** Build a standalone Guile Scheme daemon that maintains an MRU app list, communicates via Unix domain socket, and integrates with Hyprland's `hyprctl`. This is the stateful backend — the "brain" behind PolySphere's Alt+Tab switching.

**Dependencies:** Guile 3.0.11+, `guile-json` (via `.nix-profile`), `hyprctl`, Python 3 (for testing).

---

## 1. Daemon Architecture

```
┌─────────────────────────────────────────────────┐
│ daemon.scm                                       │
│                                                   │
│  ┌──────────┐    ┌──────────────┐                │
│  │ MRU List │◄───│ Unix Socket  │◄── IPC ─── QML │
│  │ (memory) │    │ :polysphere  │                │
│  └────┬─────┘    └──────┬───────┘                │
│       │                 │                        │
│       ▼                 ▼                        │
│  ┌──────────┐    ┌──────────────┐                │
│  │ hyprctl  │    │ JSON Parser  │                │
│  │ clients  │    │ (guile-json) │                │
│  └──────────┘    └──────────────┘                │
└─────────────────────────────────────────────────┘
         │
         ▼
  ~/.config/polysphere/polysphere.json  (config)
```

### Startup Flow

1. Hyprland's `exec-once` launches `guile ~/.config/polysphere/daemon.scm`
2. Daemon reads `polysphere.json` for `mru.maxEntries` and `whitelistedApps`
3. Daemon opens Unix socket at `$XDG_RUNTIME_DIR/polysphere.sock`
4. Daemon enters main loop: `accept → read → dispatch → respond → close`

### IPC Flow

```
QML                          daemon.scm
 │                              │
 ├─── {"type":"get_mru"} ──────►│
 │                              ├── hyprctl clients -j
 │                              ├── build Segment 1 (running, MRU)
 │                              ├── build Segment 2 (non-running, whitelist)
 │◄──── {"mru":[{id, running}...]} ─────┤
 │                              │
 ├─── {"type":"cycle_next"} ───►│
 │◄─── {"selected":"kitty"} ───┤
 │                              │
 ├─── {"type":"activate",       │
 │      "app":"kitty"} ────────►│
 │                              ├── MRU reorder
 │                              ├── hyprctl dispatch focuswindow class:kitty
 │◄─── {"ok":true} ────────────┤
 │                              │
 ├─── {"type":"cancel"} ───────►│
 │◄─── {"ok":true} ────────────┤
```

---

## 2. Files

### New Files

| File | Purpose |
|---|---|
| `daemon.scm` | Main Guile Scheme daemon — socket, MRU, hyprctl integration |
| `tests/config_daemon.json` | Test config with known values for daemon testing |
| `tests/test_daemon.sh` | Automated test suite — starts daemon, sends IPC, checks responses |

### Modified Files

| File | Changes |
|---|---|
| `~/.config/polysphere/polysphere.json` | **No changes needed** — daemon reads it as-is |
| `TESTS.md` | Add PHASE_2_TESTING section |
| `README.md` | Add socket location, daemon startup instructions |

---

## 3. Command-Line Interface

```
Usage: guile daemon.scm [OPTIONS]

PolySphere MRU Daemon — tracks Most Recently Used applications and
manages window focus for the PolySphere Alt+Tab switcher.

The daemon opens a Unix domain socket and listens for JSON requests.
It maintains an in-memory MRU list, polls hyprctl for running windows,
and dispatches focus commands via hyprctl.

OPTIONS:
  --help                 Print this help message and exit
  --config PATH          Path to polysphere.json config file
                         (default: $POLYSPHERE_CONFIG or
                          ~/.config/polysphere/polysphere.json)
  --socket PATH          Path for the Unix domain socket
                         (default: $XDG_RUNTIME_DIR/polysphere.sock)
  --verbose              Enable verbose logging to stderr

SOCKET:
  The daemon listens on a Unix domain socket at the path specified by
  --socket, $POLYSPHERE_SOCKET, or $XDG_RUNTIME_DIR/polysphere.sock
  (in that order of precedence). The socket uses newline-delimited
  JSON messages. One request → one response per connection.

PROTOCOL (JSON over Unix socket, newline-delimited):

  Request:  {"type":"get_mru"}
  Response: {"mru":[
              {"id":"firefox","running":true},
              {"id":"kitty","running":true},
              {"id":"spotify","running":false}
            ],"current":"firefox",
             "selected":"kitty"}
  Side effects: Runs hyprctl clients -j.
    Segment 1: alive MRU apps (switching targets, running: true)
    Segment 2: non-running whitelisted apps (launch targets, running: false)
    Combined and truncated to totalApps

  Request:  {"type":"cycle_next"}
  Response: {"selected":"kitty"}
  Side effects: Advances selection cursor forward (wraps)

  Request:  {"type":"cycle_prev"}
  Response: {"selected":"firefox"}
  Side effects: Advances selection cursor backward (wraps)

  Request:  {"type":"activate","app":"kitty"}
  Response: {"ok":true}
  Side effects: Moves "kitty" to MRU front,
                runs hyprctl dispatch focuswindow class:kitty

  Request:  {"type":"cancel"}
  Response: {"ok":true}
  Side effects: None (no-op)

INTEGRATION:
  Add to ~/.config/hypr/hyprland.conf:
    exec-once = guile ~/.config/polysphere/daemon.scm

  The daemon reads polysphere.json for:
    - mru.maxEntries    (default: 20)
    - whitelistedApps   (default: [firefox, kitty, emacs, ...])

EXAMPLES:
  # Run with defaults
  guile daemon.scm

  # Run with custom config and socket
  guile daemon.scm --config ~/my-config.json --socket /tmp/mysock.sock

  # Test the daemon
  echo '{"type":"get_mru"}' | nc -U /run/user/1000/polysphere.sock

  # Verbose mode (logs every request/response)
  guile daemon.scm --verbose
```

---

## 4. Socket Protocol

### Location

```
Priority 1: --socket CLI argument
Priority 2: $POLYSPHERE_SOCKET environment variable
Priority 3: $XDG_RUNTIME_DIR/polysphere.sock  (default)
```

The socket is a **Unix domain stream socket**. Each connection handles exactly one request-response cycle, then closes.

### Message Format

- **Encoding**: UTF-8
- **Delimiter**: Newline (`\n`)
- **One request per connection**: Client connects, sends one JSON line, reads one JSON line, disconnects

### Request/Response Table

| Request | Response | Side effects |
|---|---|---|
| `{"type":"get_mru"}` | `{"mru":[{"id":"...","running":true/false},...],"current":"...","selected":"..."}` | Runs `hyprctl clients -j`, builds two segments (running MRU + non-running whitelist), truncates to totalApps |
| `{"type":"cycle_next"}` | `{"selected":"..."}` | Advances selection cursor forward |
| `{"type":"cycle_prev"}` | `{"selected":"..."}` | Advances selection cursor backward |
| `{"type":"activate","app":"kitty"}` | `{"ok":true}` | Reorders MRU, dispatches `hyprctl dispatch focuswindow class:kitty` |
| `{"type":"cancel"}` | `{"ok":true}` | No-op |

### Error Responses

```json
{"error": "unknown request type", "type": "bad_type"}
{"error": "app not in MRU list", "app": "nonexistent"}
{"error": "app is not running", "app": "spotify"}
{"error": "hyprctl failed", "detail": "..."}
```

---

## 5. MRU Algorithm

The daemon builds a **two-segment ordered list** on each `get_mru` call. The internal MRU list tracks only apps that have been activated (focused) at least once — this is the ordering source for Segment 1.

### Data Structures

```
Internal state:
  mru-list     = ("firefox" "kitty" "code")    ← ordered by MRU recency, index 0 = most recent
  mru-cursor   = 1                               ← points to "selected" app index
  max-entries  = 20                              ← from config
  whitelist    = ("firefox" "kitty" "emacs" ...)  ← from config in order
```

### On `get_mru` — Build the two-segment response

```
Input:  (none)
Output: {
  mru: [
    {"id": "firefox", "running": true},    ← Segment 1: switching targets
    {"id": "code",    "running": true},    ←   (alive, MRU-ordered)
    {"id": "spotify", "running": false},   ← Segment 2: launch targets
    {"id": "discord", "running": false}    ←   (non-running, whitelist-ordered)
  ],
  current: "firefox",
  selected: "code"
}

--- Segment 1: Switching targets (running MRU apps) ---

Step 1: Run hyprctl clients -j
        → JSON array of all windows
        → Extract "class" from each window
        → alive-set = {"kitty", "firefox", "code"}

Step 2: Filter mru-list against alive-set
        → Keep only entries whose class is in alive-set
        → Preserve MRU order
        → segment1 = ("firefox" "code")    (kitty not in mru-list yet)

Step 3: For each entry in segment1, create an enriched object:
        → {"id": entry, "running": true}

--- Segment 2: Launch targets (non-running whitelisted apps) ---

Step 4: Build a set of all app IDs already in segment1:
        → already-included = {"firefox", "code"}

Step 5: Iterate whitelist in config order:
        For each app in whitelist:
          If app is NOT in already-included:
            Append {"id": app, "running": false} to segment2
            Add app to already-included
          Stop when len(segment1) + len(segment2) >= totalApps

--- Combine ---

Step 6: mru = segment1 + segment2  (concatenate, segment1 first)

Step 7: Determine current and selected:
        If mru is empty:     current = null,  selected = null
        Elif len(mru) == 1:  current = mru[0].id,  selected = mru[0].id
        Else:                current = mru[0].id,  selected = mru[1].id
        (current/selected always reference running apps when possible.
         If only non-running apps exist, they'll be current/selected.)

Step 8: Return { mru: mru, current: current, selected: selected }
```

### On `cycle_next` — Advance selection

```
Input:  (none)
Output: { selected: "..." }

Step 1: mru-cursor = (mru-cursor + 1) % len(mru-list)
Step 2: Return { selected: mru-list[mru-cursor].id }
        (Cycles through ALL entries — both running and non-running.
         Non-running apps are selectable; QML handles launch in Phase 3.)
```

### On `cycle_prev` — Retreat selection

```
Input:  (none)
Output: { selected: "..." }

Step 1: mru-cursor = (mru-cursor - 1 + len(mru-list)) % len(mru-list)
Step 2: Return { selected: mru-list[mru-cursor].id }
```

### On `activate` — Focus or reject

```
Input:  { app: "kitty" }
Output: { ok: true }  or  { ok: false, reason: "..." }

Step 1: Verify app is in mru-list
        → If not, return { ok: false, reason: "app not in MRU list", app: "kitty" }

Step 2: Find the entry in mru-list
        → If the entry has running: false, return { ok: false, reason: "app is not running", app: "kitty" }

Step 3 (running app):
  3a. Remove app from its current position in mru-list
  3b. Insert app at index 0 (most recent)
  3c. Truncate mru-list to max-entries
  3d. Set mru-cursor = 1
  3e. Run: hyprctl dispatch focuswindow class:<app>
  3f. Return: { ok: true }
```

### On `cancel` — No-op

```
Output: { ok: true }
```

### Edge Cases

| Scenario | Behavior |
|---|---|
| No windows running, whitelist has entries | Returns all whitelisted apps with `running: false`. Sphere shows launch targets only. |
| Only 1 window | `current` = `selected` = that app |
| `activate` with unknown app | `{ok: false, reason: "app not in MRU list"}`, no hyprctl call |
| `activate` with non-running app | `{ok: false, reason: "app is not running"}`, no hyprctl call |
| `cycle_next` on empty list | `{selected: null}` |
| `cycle_prev` on empty list | `{selected: null}` |
| `hyprctl` not found | Log error, return `{error:"hyprctl not found"}` |
| Malformed JSON request | Return `{error:"parse error"}` |
| `get_mru` with alive-set empty | Segment 1 empty, Segment 2 filled from whitelist (up to totalApps) |
| Whitelist shorter than totalApps | Segment 2 ends when whitelist is exhausted; mru is shorter than totalApps |
| New app launched but not in whitelist | App appears in hyprctl output but won't be in segment1 (no MRU history) and won't be in segment2 (not whitelisted). WON'T appear on sphere until activated once. |

---

## 6. Guile Implementation Notes

### Required imports

```scheme
(add-to-load-path (string-append (getenv "HOME") "/.nix-profile/share/guile/site/3.0"))
(use-modules (json))
(use-modules (ice-9 match))
(use-modules (ice-9 rdelim))
(use-modules (ice-9 regex))
(use-modules (srfi srfi-1))  ; for list operations
```

### JSON handling

```scheme
;; Parse JSON string to alist
(define data (json-string->scm "{\"hello\": \"world\"}"))
;; => (("hello" . "world"))

;; Alist access
(assoc-ref data "hello")
;; => "world"

;; Serialize scm to JSON string
(scm->json-string '(("ok" . #t)))
;; => "{\"ok\": true}"
```

### Unix socket (AF_UNIX)

Guile uses POSIX socket APIs via `(ice-9 socket)`:

```scheme
(let* ((sock (socket AF_UNIX SOCK_STREAM 0))
       (addr (make-socket-address AF_UNIX sock-path)))
  (bind sock addr)
  (listen sock 5)
  ;; Accept loop...
  (let ((client (accept sock)))
    (display (read-line client) client)
    (newline client)
    (close client)))
```

### hyprctl integration

```scheme
;; Run hyprctl and capture stdout
(define (run-hyprctl . args)
  (let* ((port (open-input-output-pipe
                (string-join (cons "hyprctl" args) " ")))
         (output (read-string port)))
    (close-pipe port)
    output))

;; Example: get all clients
(define clients-json (run-hyprctl "clients" "-j"))
(define clients (json-string->scm clients-json))
```

### Error handling pattern

```scheme
(define (safe-hyprctl . args)
  (catch #t
    (lambda () (apply run-hyprctl args))
    (lambda (key . args)
      (format (current-error-port) "hyprctl error: ~a ~a\n" key args)
      #f)))
```

---

## 7. Testing Strategy

### Test Harness (Python-based)

Since `socat` is not available on this system, the test suite uses Python's `socket` module to connect to the daemon, send requests, and validate responses.

### Test Cases

| # | Name | Action | Expected Response |
|---|---|---|---|
| T1 | Socket opens | Start daemon | Socket file exists at `$XDG_RUNTIME_DIR/polysphere.sock` |
| T2 | Empty get_mru | Send `{"type":"get_mru"}` | `{"mru":[],"current":null,"selected":null}` |
| T3 | get_mru with one running app | Activate "firefox", then get_mru | `{"mru":[{"id":"firefox","running":true}],"current":"firefox","selected":"firefox"}` |
| T4 | get_mru with two running apps | Activate "firefox" then "kitty", get_mru | `{"mru":[{"id":"kitty","running":true},{"id":"firefox","running":true}],"current":"kitty","selected":"firefox"}` |
| T5 | get_mru with launch targets | One running app, fill from whitelist | Response includes running apps first, then non-running whitelisted apps with `running:false` |
| T6 | cycle_next | Send `{"type":"cycle_next"}` | `{"selected":"...}` — advances cursor through ALL entries (running + non-running) |
| T7 | cycle_prev | Send `{"type":"cycle_prev"}` | `{"selected":"..."}` — retreats cursor |
| T8 | cycle wraps | cycle_next past end | Wraps to index 0 |
| T9 | activate running app | Send `{"type":"activate","app":"kitty"}` | `{"ok":true}` + app moves to MRU front, `hyprctl dispatch` called |
| T10 | activate non-running app | Send `{"type":"activate","app":"spotify"}` (spotify not running) | `{"ok":false,"reason":"app is not running","app":"spotify"}` |
| T11 | activate unknown app | Send `{"type":"activate","app":"nonexistent"}` | `{"ok":false,"reason":"app not in MRU list","app":"nonexistent"}` |
| T12 | cancel | Send `{"type":"cancel"}` | `{"ok":true}` |
| T13 | Unknown request | Send `{"type":"bad"}` | `{"error":"unknown request type","type":"bad"}` |
| T14 | Malformed JSON | Send `not json` | `{"error":"parse error"}` |
| T15 | MRU maxEntries | Activate more than maxEntries apps | List never exceeds maxEntries |
| T16 | Config overrides | Set `maxEntries: 5` in config | MRU list respects the limit |
| T17 | Whitelist fill order | get_mru with no running apps | Returns all whitelisted apps in config order with `running:false` |
| T18 | --help flag | Run `guile daemon.scm --help` | Prints help text and exits |

### Test Script Architecture

```bash
test_daemon.sh
  │
  ├── Starts daemon in background
  │   └── guile daemon.scm --config tests/config_daemon.json
  │       └── waits for socket to appear
  │
  ├── For each test case:
  │   ├── python3 -c "..."
  │   │   └── connect to socket
  │   │   └── send JSON request
  │   │   └── read JSON response
  │   │   └── compare against expected
  │   └── PASS/FAIL
  │
  └── Kills daemon
  └── Reports summary
```

### Python test client pattern

```python
import socket, json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/run/user/1000/polysphere.sock")
sock.sendall(b'{"type":"get_mru"}\n')
response = sock.recv(4096).decode().strip()
sock.close()

data = json.loads(response)
assert "mru" in data
assert "current" in data
assert "selected" in data
```

---

## 8. Implementation Checklist

- [ ] Create `daemon.scm` with:
  - [ ] CLI argument parser (--help, --config, --socket, --verbose)
  - [ ] `--help` output with full protocol documentation
  - [ ] Config reader (reads `polysphere.json`)
  - [ ] Unix domain socket server (accept → read → dispatch → respond → close)
  - [ ] MRU list data structure with maxEntries limit
  - [ ] `get_mru` handler (poll hyprctl, filter, fill from whitelist)
  - [ ] `cycle_next` / `cycle_prev` handlers (cursor with wrap)
  - [ ] `activate` handler (reorder MRU, dispatch hyprctl)
  - [ ] `cancel` handler (no-op)
  - [ ] Error handling (malformed JSON, unknown type, hyprctl failure)
  - [ ] Logging (stderr + `/tmp/polysphere.log`)
  - [ ] Signal handling (SIGTERM/SIGINT for clean shutdown)
- [ ] Create `tests/config_daemon.json` with known values
- [ ] Create `tests/test_daemon.sh` with Python-based test harness
- [ ] Run test suite: all T1–T18 pass
- [ ] Update `TESTS.md` with PHASE_2_TESTING block
- [ ] Update `README.md` with socket location and daemon instructions

---

## 9. Rollback Plan

If Phase 2 breaks the system:

1. **Kill the daemon**: `kill $(cat /tmp/polysphere.pid 2>/dev/null) || pkill -f "guile.*daemon.scm"`
2. **Remove the socket**: `rm -f /run/user/1000/polysphere.sock`
3. **Revert `daemon.scm`**: `git checkout daemon.scm`
4. **Revert config**: Restore `polysphere.json` from backup

The daemon is fully independent from QML (Phase 1), so reverting it doesn't affect the existing config system.
