/**
 * kbd-capture.c — Capture raw keyboard events via evdev and stream
 *                  JSON-encoded key events to stdout.
 *
 * Usage: kbd-capture [--device <path>] --toggle "Alt+Tab" --cancel "Escape"
 *                    --cycle-next "Tab" --cycle-prev "Shift+Tab"
 *
 * Reads from /dev/input/event* (auto-detected or specified), tracks
 * modifier state (Alt, Ctrl, Shift), and outputs one JSON line per
 * key press/release/repeat.
 *
 * Compile:
 *   gcc -O2 -o kbd-capture kbd-capture.c
 *
 * PolySphere integration:
 *   kbd-capture is launched as a QML Process by polysphere.qml.
 *   QML passes keybinding strings as CLI args (read from polysphere.json).
 *
 * This file lives at lib/kbd-capture.c relative to the repo root.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>

/* ────────────────────────────────────────────────────────────
 * Key name lookup
 * ──────────────────────────────────────────────────────────── */

typedef struct {
    int code;
    const char *name;
} KeyEntry;

static const KeyEntry KEY_NAMES[] = {
    {KEY_RESERVED,    "reserved"},
    {KEY_ESC,         "esc"},
    {KEY_1,           "1"},
    {KEY_2,           "2"},
    {KEY_3,           "3"},
    {KEY_4,           "4"},
    {KEY_5,           "5"},
    {KEY_6,           "6"},
    {KEY_7,           "7"},
    {KEY_8,           "8"},
    {KEY_9,           "9"},
    {KEY_0,           "0"},
    {KEY_MINUS,       "-"},
    {KEY_EQUAL,       "="},
    {KEY_BACKSPACE,   "backspace"},
    {KEY_TAB,         "tab"},
    {KEY_Q,           "q"},
    {KEY_W,           "w"},
    {KEY_E,           "e"},
    {KEY_R,           "r"},
    {KEY_T,           "t"},
    {KEY_Y,           "y"},
    {KEY_U,           "u"},
    {KEY_I,           "i"},
    {KEY_O,           "o"},
    {KEY_P,           "p"},
    {KEY_LEFTBRACE,   "["},
    {KEY_RIGHTBRACE,  "]"},
    {KEY_ENTER,       "enter"},
    {KEY_LEFTCTRL,    "ctrl_left"},
    {KEY_A,           "a"},
    {KEY_S,           "s"},
    {KEY_D,           "d"},
    {KEY_F,           "f"},
    {KEY_G,           "g"},
    {KEY_H,           "h"},
    {KEY_J,           "j"},
    {KEY_K,           "k"},
    {KEY_L,           "l"},
    {KEY_SEMICOLON,   ";"},
    {KEY_APOSTROPHE,  "'"},
    {KEY_GRAVE,       "`"},
    {KEY_LEFTSHIFT,   "shift_left"},
    {KEY_BACKSLASH,   "\\"},
    {KEY_Z,           "z"},
    {KEY_X,           "x"},
    {KEY_C,           "c"},
    {KEY_V,           "v"},
    {KEY_B,           "b"},
    {KEY_N,           "n"},
    {KEY_M,           "m"},
    {KEY_COMMA,       ","},
    {KEY_DOT,         "."},
    {KEY_SLASH,       "/"},
    {KEY_RIGHTSHIFT,  "shift_right"},
    {KEY_KPASTERISK,  "kp_*"},
    {KEY_LEFTALT,     "alt_left"},
    {KEY_SPACE,       "space"},
    {KEY_CAPSLOCK,    "capslock"},
    {KEY_F1,          "f1"},
    {KEY_F2,          "f2"},
    {KEY_F3,          "f3"},
    {KEY_F4,          "f4"},
    {KEY_F5,          "f5"},
    {KEY_F6,          "f6"},
    {KEY_F7,          "f7"},
    {KEY_F8,          "f8"},
    {KEY_F9,          "f9"},
    {KEY_F10,         "f10"},
    {KEY_F11,         "f11"},
    {KEY_F12,         "f12"},
    {KEY_RIGHTALT,    "alt_right"},
    {KEY_HOME,        "home"},
    {KEY_UP,          "up"},
    {KEY_PAGEUP,      "pageup"},
    {KEY_LEFT,        "left"},
    {KEY_RIGHT,       "right"},
    {KEY_END,         "end"},
    {KEY_DOWN,        "down"},
    {KEY_PAGEDOWN,    "pagedown"},
    {KEY_INSERT,      "insert"},
    {KEY_DELETE,      "delete"},
    {KEY_RIGHTCTRL,   "ctrl_right"},
    {KEY_SCROLLLOCK,  "scrolllock"},
    {KEY_PAUSE,       "pause"},
    {KEY_KPSLASH,     "kp_/"},
    {KEY_KPASTERISK,  "kp_*"},
    {KEY_KPMINUS,     "kp_-"},
    {KEY_KPPLUS,      "kp_+"},
    {KEY_KPENTER,     "kp_enter"},
    {KEY_KP1,         "kp_1"},
    {KEY_KP2,         "kp_2"},
    {KEY_KP3,         "kp_3"},
    {KEY_KP4,         "kp_4"},
    {KEY_KP5,         "kp_5"},
    {KEY_KP6,         "kp_6"},
    {KEY_KP7,         "kp_7"},
    {KEY_KP8,         "kp_8"},
    {KEY_KP9,         "kp_9"},
    {KEY_KP0,         "kp_0"},
    {KEY_KPDOT,       "kp_."},
    {KEY_102ND,       "102nd"},
    {KEY_COMPOSE,     "compose"},
    {KEY_POWER,       "power"},
    {KEY_KPEQUAL,     "kp_="},
    {KEY_F13,         "f13"},
    {KEY_F14,         "f14"},
    {KEY_F15,         "f15"},
    {KEY_F16,         "f16"},
    {KEY_F17,         "f17"},
    {KEY_F18,         "f18"},
    {KEY_F19,         "f19"},
    {KEY_F20,         "f20"},
    {KEY_F21,         "f21"},
    {KEY_F22,         "f22"},
    {KEY_F23,         "f23"},
    {KEY_F24,         "f24"},
    {KEY_LEFTMETA,    "meta_left"},
    {KEY_RIGHTMETA,   "meta_right"},
    {KEY_COMPOSE,     "compose"},
    {KEY_STOP,        "stop"},
    {KEY_AGAIN,       "again"},
    {KEY_PROPS,       "props"},
    {KEY_UNDO,        "undo"},
    {KEY_FRONT,       "front"},
    {KEY_COPY,        "copy"},
    {KEY_OPEN,        "open"},
    {KEY_PASTE,       "paste"},
    {KEY_FIND,        "find"},
    {KEY_CUT,         "cut"},
    {KEY_HELP,        "help"},
    {KEY_MENU,        "menu"},
    {KEY_CALC,        "calc"},
    {KEY_SLEEP,       "sleep"},
    {KEY_WAKEUP,      "wakeup"},
    {KEY_FILE,        "file"},
    {KEY_SENDFILE,    "sendfile"},
    {KEY_DELETEFILE,  "deletefile"},
    {KEY_XFER,        "xfer"},
    {KEY_PROG1,       "prog1"},
    {KEY_PROG2,       "prog2"},
    {KEY_PROG3,       "prog3"},
    {KEY_PROG4,       "prog4"},
    {KEY_SCREENLOCK,  "screenlock"},
    {KEY_DIRECTION,   "direction"},
    {KEY_CYCLEWINDOWS,"cyclewindows"},
    {KEY_MAIL,        "mail"},
    {KEY_BOOKMARKS,   "bookmarks"},
    {KEY_COMPUTER,    "computer"},
    {KEY_BACK,        "back"},
    {KEY_FORWARD,     "forward"},
    {KEY_CLOSECD,     "closecd"},
    {KEY_EJECTCD,     "ejectcd"},
    {KEY_EJECTCLOSECD,"ejectclosecd"},
    {KEY_NEXTSONG,    "nextsong"},
    {KEY_PLAYPAUSE,   "playpause"},
    {KEY_PREVIOUSSONG,"previoussong"},
    {KEY_STOPCD,      "stopcd"},
    {KEY_RECORD,      "record"},
    {KEY_REWIND,      "rewind"},
    {KEY_PHONE,       "phone"},
    {KEY_ISO,         "iso"},
    {KEY_CONFIG,      "config"},
    {KEY_HOMEPAGE,    "homepage"},
    {KEY_REFRESH,     "refresh"},
    {KEY_EXIT,        "exit"},
    {KEY_MOVE,        "move"},
    {KEY_EDIT,        "edit"},
    {KEY_SCROLLUP,    "scrollup"},
    {KEY_SCROLLDOWN,  "scrolldown"},
    {KEY_KPLEFTPAREN, "kp_("},
    {KEY_KPRIGHTPAREN,"kp_)"},
    {KEY_NEW,         "new"},
    {KEY_REDO,        "redo"},
    {KEY_PLAY,        "play"},
    {KEY_PAUSE,       "pause"},
    {KEY_PRINT,       "print"},
    {KEY_BASSBOOST,   "bassboost"},
    {KEY_SWITCHVIDEOMODE, "switchvideomode"},
    {KEY_KBDILLUMTOGGLE,  "kbdillumtoggle"},
    {KEY_KBDILLUMDOWN,    "kbdillumdown"},
    {KEY_KBDILLUMUP,      "kbdillumup"},
    {KEY_SEND,        "send"},
    {KEY_REPLY,       "reply"},
    {KEY_FORWARDMAIL, "forwardmail"},
    {KEY_SAVE,        "save"},
    {KEY_DOCUMENTS,   "documents"},
    {KEY_BATTERY,     "battery"},
    {KEY_BLUETOOTH,   "bluetooth"},
    {KEY_WLAN,        "wlan"},
    {KEY_UWB,         "uwb"},
    {KEY_VIDEO,       "video"},
    {KEY_AUDIO,       "audio"},
    {KEY_EJECTCD,     "ejectcd"},
    {KEY_SOUND,       "sound"},
    {KEY_QUESTION,    "question"},
    {KEY_CHAT,        "chat"},
    {KEY_FINANCE,     "finance"},
    {KEY_CANCEL,      "cancel"},
    {KEY_BRIGHTNESSDOWN, "brightnessdown"},
    {KEY_BRIGHTNESSUP,   "brightnessup"},
    {KEY_MEDIA,       "media"},
    {0, NULL}  /* sentinel */
};

static const char* key_name(int code) {
    for (const KeyEntry *e = KEY_NAMES; e->name; e++) {
        if (e->code == code) return e->name;
    }
    return NULL;
}

static int key_code(const char *name) {
    if (!name) return -1;
    for (const KeyEntry *e = KEY_NAMES; e->name; e++) {
        if (strcasecmp(e->name, name) == 0) return e->code;
    }
    return -1;
}

/* ────────────────────────────────────────────────────────────
 * Key combo parsing (e.g. "Alt+Tab" → mods + keycode)
 * ──────────────────────────────────────────────────────────── */

#define MOD_ALT  1
#define MOD_CTRL 2
#define MOD_SHIFT 4
#define MOD_META 8

typedef struct {
    int mods;
    int keycode;  /* -1 if not set */
} KeyCombo;

static KeyCombo parse_combo(const char *str) {
    KeyCombo combo = {0, -1};
    if (!str) return combo;

    char buf[256];
    strncpy(buf, str, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char *save = NULL;
    char *part = strtok_r(buf, "+", &save);
    while (part) {
        /* Trim whitespace */
        while (*part == ' ') part++;
        char *end = part + strlen(part);
        while (end > part && end[-1] == ' ') end--;
        *end = '\0';

        if (strcasecmp(part, "alt") == 0) {
            combo.mods |= MOD_ALT;
        } else if (strcasecmp(part, "ctrl") == 0) {
            combo.mods |= MOD_CTRL;
        } else if (strcasecmp(part, "shift") == 0) {
            combo.mods |= MOD_SHIFT;
        } else if (strcasecmp(part, "meta") == 0 ||
                   strcasecmp(part, "super") == 0 ||
                   strcasecmp(part, "win") == 0) {
            combo.mods |= MOD_META;
        } else {
            /* Must be the key name */
            int kc = key_code(part);
            if (kc >= 0) combo.keycode = kc;
        }
        part = strtok_r(NULL, "+", &save);
    }
    return combo;
}

/* ────────────────────────────────────────────────────────────
 * Device auto-detection
 * ──────────────────────────────────────────────────────────── */

static char* find_keyboard_device(void) {
    /* Read /proc/bus/input/devices to find keyboard devices */
    FILE *fp = fopen("/proc/bus/input/devices", "r");
    if (!fp) goto fallback;

    /* Collect devices, then pick the best one */
    typedef struct { int event; char name[128]; } KbdDev;
    KbdDev devs[32];
    int n = 0;
    char line[512];
    char cur_name[128] = "";

    while (fgets(line, sizeof(line), fp)) {
        if (line[0] == '\n') { cur_name[0] = '\0'; continue; }
        if (strncmp(line, "N: Name=\"", 9) == 0) {
            strncpy(cur_name, line + 9, sizeof(cur_name) - 1);
            char *q = strrchr(cur_name, '\"');
            if (q) *q = '\0';
        }
        if (strstr(line, "Handlers=") && strstr(line, "kbd")) {
            char *p = strstr(line, "event");
            if (p && n < 32) {
                int ev = atoi(p + 5);
                strncpy(devs[n].name, cur_name, 128);
                devs[n].event = ev;
                n++;
            }
        }
    }
    fclose(fp);

    /* Score and pick: prefer "keyboard" in name, then keyd, then lowest event */
    int best = -1, best_score = -999;
    for (int i = 0; i < n; i++) {
        int score = 0;
        if (strstr(devs[i].name, "keyd")) score += 200;  // keyd provides clean aggregated events
        if (strstr(devs[i].name, "keyboard") || strstr(devs[i].name, "Keyboard")) score += 100;
        if (strstr(devs[i].name, "speaker") || strstr(devs[i].name, "Speaker")) score -= 200;
        if (strstr(devs[i].name, "Power")) score -= 100;
        if (strstr(devs[i].name, "Video")) score -= 100;
        score -= devs[i].event;  // prefer lower event numbers as tiebreaker
        fprintf(stderr, "kbd-capture: dev event%d %-40s score=%d\n", devs[i].event, devs[i].name, score);
        if (score > best_score) { best_score = score; best = i; }
    }

    if (best >= 0) {
        char *path = malloc(64);
        snprintf(path, 64, "/dev/input/event%d", devs[best].event);
        fprintf(stderr, "kbd-capture: selected %s (%s)\n", path, devs[best].name);
        return path;
    }

fallback:
    DIR *dir = opendir("/dev/input");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') continue;
            if (strncmp(entry->d_name, "event", 5) != 0) continue;
            char path[256];
            snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name);
            int fd = open(path, O_RDONLY);
            if (fd < 0) continue;
            unsigned char bit[KEY_CNT / 8 + 1];
            memset(bit, 0, sizeof(bit));
            if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bit)), bit) >= 0) {
                int has_letters = 0;
                for (int k = KEY_A; k <= KEY_Z; k++) {
                    if ((bit[k / 8] >> (k % 8)) & 1) { has_letters = 1; break; }
                }
                if (has_letters) { close(fd); closedir(dir); return strdup(path); }
            }
            close(fd);
        }
        closedir(dir);
    }
    return NULL;
}

/* ────────────────────────────────────────────────────────────
 * Modifier key detection
 * ──────────────────────────────────────────────────────────── */

static int is_modifier(int code) {
    return code == KEY_LEFTALT || code == KEY_RIGHTALT ||
           code == KEY_LEFTCTRL || code == KEY_RIGHTCTRL ||
           code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT ||
           code == KEY_LEFTMETA || code == KEY_RIGHTMETA;
}

static int mod_for_code(int code) {
    switch (code) {
        case KEY_LEFTALT: case KEY_RIGHTALT:   return MOD_ALT;
        case KEY_LEFTCTRL: case KEY_RIGHTCTRL: return MOD_CTRL;
        case KEY_LEFTSHIFT: case KEY_RIGHTSHIFT: return MOD_SHIFT;
        case KEY_LEFTMETA: case KEY_RIGHTMETA: return MOD_META;
        default: return 0;
    }
}

/* ────────────────────────────────────────────────────────────
 * JSON output
 * ──────────────────────────────────────────────────────────── */

/* ────────────────────────────────────────────────────────────
 * Unix socket client — connects to QML's SocketServer
 * ──────────────────────────────────────────────────────────── */

static int conn_fd = -1;

/* Connect to QML's SocketServer. Retries until successful or timeout. */
static int connect_to_server(const char *path, int max_retries) {
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    for (int attempt = 0; attempt < max_retries; attempt++) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return -1;

        if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            return fd;
        }
        close(fd);
        usleep(50000); /* 50ms delay between retries */
    }
    return -1;
}

/* Format and send a JSON key event to the connected socket and stdout. */
static void send_json(const char *key, int value, int mods) {
    char buf[512];
    int pos = snprintf(buf, sizeof(buf), "{\"key\":\"%s\",\"value\":%d,\"mods\":{",
                      key ? key : "unknown", value);
    int count = 0;
    if (mods & MOD_ALT)   { pos += snprintf(buf+pos, sizeof(buf)-pos, "%s\"alt\":true", count++ ? "," : ""); }
    if (mods & MOD_CTRL)  { pos += snprintf(buf+pos, sizeof(buf)-pos, "%s\"ctrl\":true", count++ ? "," : ""); }
    if (mods & MOD_SHIFT) { pos += snprintf(buf+pos, sizeof(buf)-pos, "%s\"shift\":true", count++ ? "," : ""); }
    if (mods & MOD_META)  { pos += snprintf(buf+pos, sizeof(buf)-pos, "%s\"meta\":true", count++ ? "," : ""); }
    snprintf(buf+pos, sizeof(buf)-pos, "}}\n");

    /* Always write to stdout (for debugging) */
    fputs(buf, stdout);
    fflush(stdout);

    /* Write to connected socket */
    if (conn_fd >= 0) {
        write(conn_fd, buf, strlen(buf));
    }
}

/* ────────────────────────────────────────────────────────────
 * Main
 * ──────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    const char *device_path = NULL;
    const char *connect_path = NULL;
    KeyCombo toggle_combo = {0, -1};
    KeyCombo cancel_combo = {0, -1};
    KeyCombo cycle_next_combo = {0, -1};
    KeyCombo cycle_prev_combo = {0, -1};

    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            device_path = argv[++i];
        } else if (strcmp(argv[i], "--connect") == 0 && i + 1 < argc) {
            connect_path = argv[++i];
        } else if (strcmp(argv[i], "--toggle") == 0 && i + 1 < argc) {
            toggle_combo = parse_combo(argv[++i]);
        } else if (strcmp(argv[i], "--cancel") == 0 && i + 1 < argc) {
            cancel_combo = parse_combo(argv[++i]);
        } else if (strcmp(argv[i], "--cycle-next") == 0 && i + 1 < argc) {
            cycle_next_combo = parse_combo(argv[++i]);
        } else if (strcmp(argv[i], "--cycle-prev") == 0 && i + 1 < argc) {
            cycle_prev_combo = parse_combo(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("Usage: %s --connect <path> [--device <path>] --toggle \"Alt+Tab\" ...\n", argv[0]);
            printf("       --cycle-next \"Tab\" --cycle-prev \"Shift+Tab\"\n");
            return 0;
        }
    }

    /* Connect to QML's SocketServer */
    if (!connect_path) {
        fprintf(stderr, "kbd-capture: --connect <path> is required\n");
        return 1;
    }
    /* Socket connection happens LATER in the event loop (after grab).
     * conn_fd stays -1 until we successfully connect. */
    conn_fd = -1;
    int conn_retries = 0;

    if (toggle_combo.keycode < 0) {
        toggle_combo = parse_combo("Alt+Tab");
    }
    if (cancel_combo.keycode < 0) {
        cancel_combo = parse_combo("Escape");
    }
    if (cycle_next_combo.keycode < 0) {
        cycle_next_combo = parse_combo("Tab");
    }
    if (cycle_prev_combo.keycode < 0) {
        cycle_prev_combo = parse_combo("Shift+Tab");
    }

    /* Auto-detect device if not specified */
    char *auto_device = NULL;
    if (!device_path) {
        auto_device = find_keyboard_device();
        if (!auto_device) {
            fprintf(stderr, "kbd-capture: no keyboard device found\n");
            return 1;
        }
        device_path = auto_device;
    }

    int fd = open(device_path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "kbd-capture: cannot open %s: %s\n", device_path, strerror(errno));
        free(auto_device);
        return 1;
    }

    int current_mods = 0;

    /* Sync modifier state at startup: query EVIOCGKEY to detect
     * modifiers already held (e.g., Alt held from Alt+Tab launch).
     * Same approach as kaatws's _syncModifierState(). */
    {
        unsigned char key_bits[KEY_CNT / 8 + 1];
        memset(key_bits, 0, sizeof(key_bits));
        if (ioctl(fd, EVIOCGKEY(sizeof(key_bits)), key_bits) >= 0) {
            int alt_pressed = (key_bits[KEY_LEFTALT / 8] >> (KEY_LEFTALT % 8)) & 1
                            | (key_bits[KEY_RIGHTALT / 8] >> (KEY_RIGHTALT % 8)) & 1;
            if (alt_pressed) {
                current_mods |= MOD_ALT;
                fprintf(stderr, "kbd-capture: Alt held at startup, mods initialized to ALT\n");
            }
        }
    }

    /* Leave keyboard UNGRABBED initially. QML will send "grab" via socket
     * when the overlay opens, and "ungrab" when it closes.
     * This way keys work normally until PolySphere needs them. */
    int is_grabbed = 0;

    /* Set O_NONBLOCK so we can poll evdev + socket */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    fprintf(stderr, "kbd-capture: device=%s connecting to %s\n", device_path, connect_path);

    /* Initial connection attempt (non-blocking — event loop retries if needed) */
    conn_fd = connect_to_server(connect_path, 1);  /* single try */
    if (conn_fd >= 0) {
        int sock_flags = fcntl(conn_fd, F_GETFL, 0);
        fcntl(conn_fd, F_SETFL, sock_flags | O_NONBLOCK);
        fprintf(stderr, "kbd-capture: initial connect OK\n");
    }

    struct input_event ev;
    char cmd_buf[64];
    int cmd_pos = 0;
    int loop_count = 0;

    fprintf(stderr, "kbd-capture: entering event loop (no grab yet)\n");

    while (1) {
        /* Poll evdev + socket with 15ms timeout */
        struct pollfd pfds[2];
        int nfds = 1;
        pfds[0].fd = fd;
        pfds[0].events = POLLIN;
        if (conn_fd >= 0) {
            pfds[1].fd = conn_fd;
            pfds[1].events = POLLIN;
            nfds = 2;
        }

        int pret = poll(pfds, nfds, 15);
        if (pret < 0) {
            if (errno == EINTR) continue;
            break;
        }

        /* Check for socket events (data, close, or hangup) */
        if (conn_fd >= 0 && (pfds[1].revents & (POLLIN | POLLHUP | POLLERR))) {
            if (pfds[1].revents & (POLLHUP | POLLERR)) {
                /* Socket hung up or error — QML deactivated SocketServer */
                goto disconnect;
            }
            char ch;
            ssize_t r = read(conn_fd, &ch, 1);
            if (r <= 0) {
disconnect:
                if (is_grabbed) {
                    ioctl(fd, EVIOCGRAB, (void*)0);
                    is_grabbed = 0;
                    fprintf(stderr, "kbd-capture: socket closed, UNGRABBED\n");
                }
                close(conn_fd);
                conn_fd = -1;
            } else if (r == 1) {
                if (ch == '\n') {
                    cmd_buf[cmd_pos] = '\0';
                    if (strcmp(cmd_buf, "grab") == 0 && !is_grabbed) {
                        if (ioctl(fd, EVIOCGRAB, (void*)1) == 0) {
                            is_grabbed = 1;
                            fprintf(stderr, "kbd-capture: GRABBED\n");
                        }
                    }
                    cmd_pos = 0;
                } else if (cmd_pos < (int)sizeof(cmd_buf) - 1) {
                    cmd_buf[cmd_pos++] = ch;
                }
            }
        }

        /* Read keyboard events (only send if connected) */
        if (pfds[0].revents & POLLIN) {
            while (1) {
                ssize_t n = read(fd, &ev, sizeof(ev));
                if (n < 0) {
                    if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                    if (errno == EINTR) continue;
                    goto done;
                }
                if ((size_t)n != sizeof(ev)) continue;
                if (ev.type != EV_KEY) continue;

                const char *name = key_name(ev.code);
                if (!name) continue;

                if (is_modifier(ev.code)) {
                    int mod = mod_for_code(ev.code);
                    if (ev.value == 1 || ev.value == 2) {
                        current_mods |= mod;
                    } else if (ev.value == 0) {
                        current_mods &= ~mod;
                    }
                }

                fprintf(stderr, "kbd-capture: event %s=%d mods=%d\n", name, ev.value, current_mods);
                if (conn_fd >= 0) {
                    send_json(name, ev.value, current_mods);
                }
            }
        }

        /* Try to reconnect every loop iteration (15ms).
         * connect() to a non-existent socket returns ECONNREFUSED
         * instantly (< 1ms). When the server appears, we connect
         * within 15ms — no delay. */
        if (conn_fd < 0) {
            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, connect_path, sizeof(addr.sun_path) - 1);
            int sfd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (sfd >= 0) {
                if (connect(sfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
                    conn_fd = sfd;
                    int f = fcntl(conn_fd, F_GETFL, 0);
                    fcntl(conn_fd, F_SETFL, f | O_NONBLOCK);
                    fprintf(stderr, "kbd-capture: reconnected\n");
                } else {
                    close(sfd);
                }
            }
            if (conn_fd >= 0) {
                int sock_flags = fcntl(conn_fd, F_GETFL, 0);
                fcntl(conn_fd, F_SETFL, sock_flags | O_NONBLOCK);
                fprintf(stderr, "kbd-capture: connected (deferred)\n");
            }
        }
    }

done:

    close(fd);
    if (conn_fd >= 0) close(conn_fd);
    free(auto_device);
    return 0;
}
