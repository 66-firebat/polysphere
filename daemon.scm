#!/usr/bin/env -S guile -s
!#
;;;; PolySphere MRU Daemon
;;;;
;;;; Tracks Most Recently Used applications and manages window focus
;;;; for the PolySphere Alt+Tab switcher.
;;;;
;;;; Usage: guile daemon.scm [OPTIONS]
;;;;
;;;; See --help for full documentation.

;; ────────────────────────────────────────────────────────────────
;; Imports
;; ────────────────────────────────────────────────────────────────

(add-to-load-path (string-append (getenv "HOME") "/.nix-profile/share/guile/site/3.0"))

(use-modules (json))
(use-modules (ice-9 match))
(use-modules (ice-9 rdelim))
(use-modules (ice-9 regex))
(use-modules (srfi srfi-1))
(use-modules (ice-9 getopt-long))
(use-modules (ice-9 popen))
(use-modules (srfi srfi-11))

;; ────────────────────────────────────────────────────────────────
;; Constants
;; ────────────────────────────────────────────────────────────────

(define %default-config-path
  (or (getenv "POLYSPHERE_CONFIG")
      (string-append (getenv "HOME") "/.config/polysphere/polysphere.json")))

(define %default-socket-path
  (or (getenv "POLYSPHERE_SOCKET")
      (string-append (or (getenv "XDG_RUNTIME_DIR") "/tmp") "/polysphere.sock")))

(define %help-text
"PolySphere MRU Daemon — tracks Most Recently Used applications and
manages window focus for the PolySphere Alt+Tab switcher.

The daemon opens a Unix domain socket and listens for JSON requests.
It maintains an in-memory MRU list, polls hyprctl for running windows,
and dispatches focus commands via hyprctl.

Usage: guile daemon.scm [OPTIONS]

OPTIONS:
  -h, --help              Print this help message and exit
  -c, --config PATH       Path to polysphere.json config file
                          (default: $POLYSPHERE_CONFIG or
                           ~/.config/polysphere/polysphere.json)
  -s, --socket PATH       Path for the Unix domain socket
                          (default: $POLYSPHERE_SOCKET or
                           $XDG_RUNTIME_DIR/polysphere.sock)
  -v, --verbose           Enable verbose logging

SOCKET:
  The daemon listens on a Unix domain stream socket. Each connection
  handles exactly one request-response cycle, then closes.

  Default location: $XDG_RUNTIME_DIR/polysphere.sock
  Typically:        /run/user/1000/polysphere.sock

PROTOCOL (JSON over Unix socket, newline-delimited):
  The client connects, sends one JSON line, reads one JSON line,
  then disconnects.

  ─── get_mru ────────────────────────────────────────────────────
  Request:  {\"type\":\"get_mru\"}
  Response: {
    \"mru\": [
      {\"id\":\"firefox\",\"running\":true},
      {\"id\":\"code\",\"running\":true},
      {\"id\":\"spotify\",\"running\":false}
    ],
    \"current\":\"firefox\",
    \"selected\":\"code\"
  }
  Side effects: Runs hyprctl clients -j to build the alive set.
    - Segment 1: alive MRU apps (switching targets, running: true)
    - Segment 2: non-running whitelisted apps (launch targets, running: false)
    - Segments are combined and truncated to totalApps from config

  ─── cycle_next ─────────────────────────────────────────────────
  Request:  {\"type\":\"cycle_next\"}
  Response: {\"selected\":\"code\"}
  Side effects: Advances selection cursor forward (wraps).
    Cycles through ALL entries — both running and non-running.

  ─── cycle_prev ─────────────────────────────────────────────────
  Request:  {\"type\":\"cycle_prev\"}
  Response: {\"selected\":\"firefox\"}
  Side effects: Advances selection cursor backward (wraps).

  ─── activate ────────────────────────────────────────────────────
  Request:  {\"type\":\"activate\",\"app\":\"kitty\"}
  Response: {\"ok\":true}
  Side effects:
    - Verifies app is in MRU list and is running
    - Moves activated app to MRU front (index 0)
    - Runs: hyprctl dispatch focuswindow class:<app>
    - On failure: {\"ok\":false,\"reason\":\"app is not running\",\"app\":\"spotify\"}
                 or {\"ok\":false,\"reason\":\"app not in MRU list\",\"app\":\"nonexistent\"}

  ─── cancel ──────────────────────────────────────────────────────
  Request:  {\"type\":\"cancel\"}
  Response: {\"ok\":true}
  Side effects: None (no-op).

INTEGRATION:
  Add to ~/.config/hypr/hyprland.conf:
    exec-once = guile ~/.config/polysphere/daemon.scm --verbose

  The daemon reads polysphere.json for:
    - totalApps          (default: 20)
    - whitelistedApps    (default: [firefox, kitty, emacs, ...])
    - mru.maxEntries     (default: 20)

EXAMPLES:
  # Run with defaults
  guile daemon.scm

  # Run with custom config and socket
  guile daemon.scm --config ~/my-config.json --socket /tmp/mysock.sock

  # Test the daemon
  echo '{\"type\":\"get_mru\"}' | nc -U /run/user/1000/polysphere.sock

  # Verbose mode (logs every request/response)
  guile daemon.scm --verbose
")

;; ────────────────────────────────────────────────────────────────
;; State
;; ────────────────────────────────────────────────────────────────

(define mru-list '())         ;; list of app identifiers, index 0 = most recent
(define mru-cursor 0)         ;; index into mru-list pointing to selected app
(define cfg '())              ;; parsed config alist
(define verbose? #f)          ;; verbose logging flag
(define log-port #f)          ;; log file port
(define running #t)           ;; set to #f to trigger graceful shutdown

;; ────────────────────────────────────────────────────────────────
;; Helpers
;; ────────────────────────────────────────────────────────────────

(define (assoc-ref* alist key . default)
  "Like assoc-ref but with a default value fallback."
  (let ((pair (assoc key alist)))
    (if pair (cdr pair)
        (if (null? default) #f (car default)))))

(define (list-contains? lst item)
  "Check if item is in lst using equal? comparison."
  (not (not (member item lst))))

(define (string->boolean s)
  "Convert a JSON-format boolean string to Scheme boolean."
  (member s '("true" "True" "TRUE" "yes" "Yes" "YES" "1") char=?))

(define (json-null)
  "Return the Scheme representation of JSON null.
   In guile-json, '() serializes to JSON 'null'."
  '())


;; ────────────────────────────────────────────────────────────────
;; Logging
;; ────────────────────────────────────────────────────────────────

(define (log-open)
  "Open the log file."
  (catch #t
    (lambda ()
      (set! log-port (open-file "/tmp/polysphere.log" "a"))
      (log-msg "INFO" "Daemon started"))
    (lambda (key . args)
      (set! log-port #f)
      (display "WARN: Could not open log file: ")
      (display (cadr args))
      (newline))))

(define (log-close)
  "Close the log file."
  (when log-port
    (log-msg "INFO" "Daemon shutting down")
    (close-port log-port)))

(define (log-msg level msg)
  "Write a log message to stderr and the log file."
  (let ((line (string-append "[" level "] " msg)))
    ;; Always write to stderr
    (display line)
    (newline)
    (force-output)
    ;; Also write to log file
    (when log-port
      (catch #t
        (lambda ()
          (display line log-port)
          (newline log-port)
          (force-output log-port))
        (lambda (key . args)
          ;; Log file failed — silently degrade
          #f)))))

(define (log-verbose msg)
  "Log a verbose message only if --verbose is set."
  (when verbose?
    (log-msg "DEBUG" msg)))

(define (log-error msg)
  "Log an error message."
  (log-msg "ERROR" msg))

(define (log-request type data)
  "Log an incoming request (verbose only)."
  (log-verbose (string-append "Request: " type
                              (if data (string-append " " data) ""))))

(define (log-response data)
  "Log an outgoing response (verbose only)."
  (log-verbose (string-append "Response: " data)))


;; ────────────────────────────────────────────────────────────────
;; CLI Argument Parsing
;; ────────────────────────────────────────────────────────────────

(define %options
  `((help        (single-char #\h))
    (config      (single-char #\c) (value #t))
    (socket      (single-char #\s) (value #t))
    (verbose     (single-char #\v))))

(define (parse-args)
  "Parse command-line arguments and return an options alist."
  (let ((opts (getopt-long (program-arguments) %options)))
    (when (option-ref opts 'help #f)
      (display %help-text)
      (exit 0))
    (set! verbose? (option-ref opts 'verbose #f))
    (let ((config-path (option-ref opts 'config #f))
          (socket-path (option-ref opts 'socket #f)))
      (values
       (or config-path %default-config-path)
       (or socket-path %default-socket-path)))))


;; ────────────────────────────────────────────────────────────────
;; Config Reading
;; ────────────────────────────────────────────────────────────────

(define (read-config config-path)
  "Read and parse the polysphere.json config file. Returns an alist.
   If the file is missing or malformed, returns '() and logs a warning."
  (catch #t
    (lambda ()
      (call-with-input-file config-path
        (lambda (port)
          (let ((raw (read-delimited "" port)))
            (if (string-null? (string-trim-both raw))
                (begin
                  (log-msg "WARN" (string-append "Config file empty: " config-path))
                  '())
                (let ((parsed (json-string->scm raw)))
                  (log-msg "INFO" (string-append "Config loaded from " config-path))
                  parsed))))))
    (lambda (key . args)
      (log-msg "WARN" (string-append "Could not read config at " config-path
                                      " — using defaults"))
      '())))

(define (config-get key . default)
  "Get a config value with optional default."
  (let ((val (assoc-ref* cfg key)))
    (if (and val (not (null? val))) val
        (if (null? default) #f (car default)))))

(define (config-get-totalApps)
  "Get totalApps from config, default 20."
  (let ((val (config-get "totalApps")))
    (if (and (number? val) (> val 0)) val 20)))

;; guile-json parses JSON arrays as vectors; convert to list if needed
(define (json->list val)
  (cond
   ((vector? val) (vector->list val))
   ((list? val) val)
   (else '())))

(define (config-get-whitelistedApps)
  "Get whitelistedApps from config. Returns a list of string identifiers,
   with .desktop extension stripped."
  (let* ((raw (json->list (config-get "whitelistedApps" '())))
         (clean (map (lambda (s)
                       (if (string-suffix? ".desktop" s)
                           (string-drop-right s (string-length ".desktop"))
                           s))
                     raw)))
    (log-verbose (string-append "Whitelist: " (string-join clean ", ")))
    clean))

(define (config-get-maxEntries)
  "Get mru.maxEntries from config, default 20."
  (let* ((mru-cfg (config-get "mru" '()))
         (val (assoc-ref* mru-cfg "maxEntries")))
    (if (and (number? val) (> val 0)) val 20)))


;; ────────────────────────────────────────────────────────────────
;; hyprctl Integration
;; ────────────────────────────────────────────────────────────────

(define (run-hyprctl . args)
  "Run a hyprctl command and return stdout as a string.
   Returns #f on failure."
  (catch #t
    (lambda ()
      (let* ((cmd (string-join (cons "hyprctl" args) " "))
             (port (open-input-pipe cmd))
             (output (read-delimited "" port)))
        (close-pipe port)
        output))
    (lambda (key . args)
      (log-error (string-append "hyprctl failed: " (cadr args)))
      #f)))

(define (get-running-apps)
  "Query hyprctl for all running windows and return a list of
   window class identifiers (strings). Returns '() on failure."
  (let ((raw (run-hyprctl "clients" "-j")))
    (if (not raw)
        '()
        (catch #t
          (lambda ()
            (let* ((clients-raw (json-string->scm raw))
                   (clients (json->list clients-raw)))
              (map (lambda (c) (assoc-ref* c "class" "")) clients)))
          (lambda (key . args)
            (log-error "Failed to parse hyprctl output")
            '())))))

(define (get-focused-app)
  "Query hyprctl for the currently focused window.
   Returns its class string, or #f if no window is focused."
  (let ((raw (run-hyprctl "activewindow" "-j")))
    (if (not raw)
        #f
        (catch #t
          (lambda ()
            (let ((win (json-string->scm raw)))
              (and (list? win) (assoc-ref* win "class" #f))))
          (lambda (key . args)
            #f)))))

(define (focus-app app)
  "Focus a window by class. Returns #t on success, #f on failure."
  (let ((result (run-hyprctl "dispatch" "focuswindow" (string-append "class:" app))))
    (if result #t #f)))


;; ────────────────────────────────────────────────────────────────
;; MRU Data Structure Operations
;; ────────────────────────────────────────────────────────────────

(define (mru-push-front app)
  "Move app to index 0 of mru-list. If app is not already in the list,
   prepend it. Truncate to maxEntries after."
  (set! mru-list (cons app (delete app mru-list eq?)))
  (let ((max-entries (config-get-maxEntries)))
    (when (> (length mru-list) max-entries)
      (set! mru-list (take mru-list max-entries))))
  (set! mru-cursor 1)
  (when (>= mru-cursor (length mru-list))
    (set! mru-cursor (1- (length mru-list)))))

(define (mru-remove app)
  "Remove app from mru-list if present."
  (set! mru-list (delete app mru-list eq?)))


;; ────────────────────────────────────────────────────────────────
;; JSON Response Builders
;; ────────────────────────────────────────────────────────────────

(define (enrich-entry app running?)
  "Create an enriched MRU entry alist."
  `(("id" . ,app) ("running" . ,running?)))

(define (build-mru-response running-set whitelist totalApps)
  "Build the two-segment MRU response.
   Segment 1: Running apps from MRU list (switching targets).
   Segment 2: Non-running whitelisted apps (launch targets)."

  ;; --- Segment 1: switching targets ---
  (let* ((segment1-ids (filter (lambda (app) (list-contains? running-set app)) mru-list))
         (segment1 (map (lambda (app) (enrich-entry app #t)) segment1-ids))
         (included (list-copy segment1-ids))

         ;; --- Segment 2: launch targets ---
         (segment2
          (let loop ((remaining whitelist)
                     (acc '())
                     (seen included))
            (if (or (null? remaining)
                    (>= (+ (length segment1) (length acc)) totalApps))
                (reverse acc)
                (let ((app (car remaining)))
                  (cond
                   ((list-contains? seen app)
                    (loop (cdr remaining) acc seen))
                   ((list-contains? running-set app)
                    ;; Running but not in MRU yet — add as switching target
                    (loop (cdr remaining)
                          (cons (enrich-entry app #t) acc)
                          (cons app seen)))
                   (else
                    ;; Non-running — add as launch target
                    (loop (cdr remaining)
                          (cons (enrich-entry app #f) acc)
                          (cons app seen))))))))

         ;; Combine
         (mru-list (append segment1 segment2))
         (mru-vec (list->vector mru-list))

         ;; Determine current and selected
         (current-str (if (null? mru-list)
                         "null"
                         (string-append "\"" (assoc-ref* (car mru-list) "id") "\"")))
         (selected-str (cond
                        ((null? mru-list) "null")
                        ((null? (cdr mru-list))
                         (string-append "\"" (assoc-ref* (car mru-list) "id") "\""))
                        (else
                         (string-append "\"" (assoc-ref* (cadr mru-list) "id") "\""))))
         (mru-json-str (scm->json-string mru-vec)))

    ;; Build JSON string manually to handle null values
    ;; (scm->json-string cannot serialize JSON null)
    (string-append "{" "\"mru\":" mru-json-str ","
                   "\"current\":" current-str ","
                   "\"selected\":" selected-str "}")))

(define (make-error-response key . extra-pairs)
  "Build an error response alist."
  (let ((base `(("error" . ,key))))
    (if (null? extra-pairs)
        base
        (append base extra-pairs))))

(define (json-ok)
  "Build an ok response as a JSON string."
  "{\"ok\":true}")

(define (json-selected id)
  "Build a selected response as a JSON string.
   If id is #f, uses JSON null."
  (if id
      (string-append "{\"selected\":\"" id "\"}")
      "{\"selected\":null}"))

(define (make-ok-response)
  "Build a success response alist."
  '(("ok" . #t)))

(define (make-ok-false-response reason app)
  "Build a failure response for activate."
  `(("ok" . #f) ("reason" . ,reason) ("app" . ,app)))


;; ────────────────────────────────────────────────────────────────
;; Request Handlers
;; ────────────────────────────────────────────────────────────────

(define (handle-get-mru totalApps whitelist)
  "Handle a get_mru request."
  (log-verbose "Handling get_mru")
  (let* ((running-set (get-running-apps))
         (response (build-mru-response running-set whitelist totalApps)))
    (log-verbose (string-append "get_mru completed"))
    response))

(define (handle-cycle-next)
  "Handle a cycle_next request."
  (log-verbose "Handling cycle_next")
  (cond
   ((null? mru-list)
    (json-selected #f))
   (else
    (set! mru-cursor (modulo (1+ mru-cursor) (length mru-list)))
    (let* ((entry (list-ref mru-list mru-cursor))
           (id (if (pair? entry) (assoc-ref* entry "id") entry)))
      (log-verbose (string-append "cycle_next -> " id))
      (json-selected id)))))

(define (handle-cycle-prev)
  "Handle a cycle_prev request."
  (log-verbose "Handling cycle_prev")
  (cond
   ((null? mru-list)
    (json-selected #f))
   (else
    (set! mru-cursor (modulo (1- mru-cursor) (length mru-list)))
    (let* ((entry (list-ref mru-list mru-cursor))
           (id (if (pair? entry) (assoc-ref* entry "id") entry)))
      (log-verbose (string-append "cycle_prev -> " id))
      (json-selected id)))))

(define (handle-activate app)
  "Handle an activate request."
  (log-verbose (string-append "Handling activate for " app))

  ;; Check if app is in MRU list
  (let ((mru-entry (find (lambda (e)
                           (let ((id (if (pair? e) (assoc-ref* e "id") e)))
                             (string=? id app)))
                         mru-list)))
    (if (not mru-entry)
        ;; App not in MRU list at all
        (scm->json-string (make-ok-false-response "app not in MRU list" app))
        ;; Check if app is running
        (let ((running-set (get-running-apps)))
          (if (not (list-contains? running-set app))
              ;; App is not running
              (scm->json-string (make-ok-false-response "app is not running" app))
              ;; App is running — focus it
              (begin
                (mru-push-front app)
                (focus-app app)
                (log-msg "INFO" (string-append "Activated " app))
                (scm->json-string (make-ok-response))))))))

(define (handle-cancel)
  "Handle a cancel request."
  (log-verbose "Handling cancel")
  (scm->json-string (make-ok-response)))

(define (handle-unknown type)
  "Handle an unknown request type."
  (log-msg "WARN" (string-append "Unknown request type: " type))
  (scm->json-string (make-error-response "unknown request type"
                                          (cons "type" type))))

(define (handle-malformed-json raw)
  "Handle a malformed JSON request."
  (log-msg "WARN" (string-append "Malformed JSON: " raw))
  (scm->json-string (make-error-response "parse error")))


;; ────────────────────────────────────────────────────────────────
;; Request Dispatcher
;; ────────────────────────────────────────────────────────────────

(define (dispatch-request json-string totalApps whitelist)
  "Parse a JSON request and dispatch to the appropriate handler.
   Returns the JSON response string."
  (log-request json-string #f)

  (catch #t
    (lambda ()
      (let* ((data (json-string->scm json-string))
             (type (assoc-ref* data "type")))
        (cond
         ((not type)
          (scm->json-string (make-error-response "missing type")))
         ((string=? type "get_mru")
          (handle-get-mru totalApps whitelist))
         ((string=? type "cycle_next")
          (handle-cycle-next))
         ((string=? type "cycle_prev")
          (handle-cycle-prev))
         ((string=? type "activate")
          (let ((app (assoc-ref* data "app")))
            (if (not app)
                (scm->json-string (make-error-response "missing app"))
                (handle-activate app))))
         ((string=? type "cancel")
          (handle-cancel))
         (else
          (handle-unknown type)))))
    (lambda (key . args)
      (handle-malformed-json json-string))))


;; ────────────────────────────────────────────────────────────────
;; Socket Server
;; ────────────────────────────────────────────────────────────────

(define (setup-socket socket-path)
  "Create, bind, and listen on a Unix domain socket.
   Returns the socket port, or #f on failure."
  (catch #t
    (lambda ()
      ;; Remove existing socket file if present
      (catch #t
        (lambda () (delete-file socket-path))
        (lambda (key . args) #f))

      (let ((sock (socket AF_UNIX SOCK_STREAM 0))
            (addr (make-socket-address AF_UNIX socket-path)))
        (bind sock addr)
        (listen sock 5)
        (log-msg "INFO" (string-append "Listening on " socket-path))
        sock))
    (lambda (key . args)
      (log-error (string-append "Failed to create socket: " (cadr args)))
      #f)))

(define (handle-client client-port totalApps whitelist)
  "Handle a single client connection: read request, dispatch, respond."
  (catch #t
    (lambda ()
      (let ((request (read-line client-port)))
        (if (eof-object? request)
            (log-verbose "Client disconnected without sending data")
            (let* ((request-str (string-trim-both request))
                   (response (dispatch-request request-str totalApps whitelist)))
              (log-response response)
              (display response client-port)
              (newline client-port)
              (force-output client-port)))))
    (lambda (key . args)
      (log-error (string-append "Error handling client: " (cadr args)))))
  (catch #t
    (lambda () (close-port client-port))
    (lambda (key . args) #f)))

(define (run-server socket-path totalApps whitelist)
  "Main accept loop. Runs until 'running' is set to #f."
  (let ((sock (setup-socket socket-path)))
    (if (not sock)
        (begin
          (log-error "Failed to start socket server, exiting")
          (exit 1))
        (let loop ()
          (when running
            (catch #t
              (lambda ()
                (let* ((result (accept sock))
                       (client-port (car result)))
                  (handle-client client-port totalApps whitelist)))
              (lambda (key . args)
                (log-error (string-append "Accept error: " (cadr args)))))
            ;; Re-read config on each iteration (future: signal-based)
            (loop))))))


;; ────────────────────────────────────────────────────────────────
;; Signal Handling
;; ────────────────────────────────────────────────────────────────

(define (setup-signal-handlers)
  "Set up signal handlers for graceful shutdown."
  (sigaction SIGINT
    (lambda (sig)
      (log-msg "INFO" "Received SIGINT, shutting down")
      (set! running #f))
    SA_NOCLDSTOP)
  (sigaction SIGTERM
    (lambda (sig)
      (log-msg "INFO" "Received SIGTERM, shutting down")
      (set! running #f))
    SA_NOCLDSTOP))


;; ────────────────────────────────────────────────────────────────
;; Main
;; ────────────────────────────────────────────────────────────────

(match (program-arguments)
  (("-h") (display %help-text) (newline) (exit 0))
  (("--help") (display %help-text) (newline) (exit 0))
  (_
   (let-values (((config-path socket-path) (parse-args)))
     ;; Open log
     (log-open)

     ;; Read config
     (set! cfg (read-config config-path))
     (let* ((totalApps (config-get-totalApps))
            (whitelist (config-get-whitelistedApps))
            (maxEntries (config-get-maxEntries)))

       (log-msg "INFO" (string-append "Configuration: "
                                       "totalApps=" (number->string totalApps)
                                       ", whitelist=" (number->string (length whitelist))
                                       ", maxEntries=" (number->string maxEntries)))
       (log-msg "INFO" (string-append "Socket: " socket-path))

       ;; Set up signal handlers
       (setup-signal-handlers)

       ;; Run the server
       (run-server socket-path totalApps whitelist)

       ;; Cleanup
       (log-close)
       (when (file-exists? socket-path)
         (delete-file socket-path))
       (log-msg "INFO" "Daemon exited")))))
