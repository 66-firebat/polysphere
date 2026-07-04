#!/usr/bin/env python3
"""PolySphere daemon - reliable MRU manager (Python)."""
import os, sys, json, socket, select, signal, subprocess, glob

HOME = os.environ.get("HOME","/home/fireshark")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR","/run/user/1000")
SOCKET = os.environ.get("POLYSPHERE_SOCKET", f"{RUNTIME}/polysphere.sock")
CONFIG = os.environ.get("POLYSPHERE_CONFIG", f"{HOME}/.config/polysphere/polysphere.json")

class Daemon:
    def __init__(self):
        self.cfg = {}
        self.mru = []
        self.apps = []
        self.running = True

    def log(self, msg): print(msg, file=sys.stderr, flush=True)

    def load_config(self):
        try:
            with open(CONFIG) as f: self.cfg = json.load(f)
            self.log(f"Config loaded ({len(self.cfg)} keys)")
        except: self.log("No config, using defaults")

    def scan_apps(self):
        for d in [f"{HOME}/.local/share/applications", "/usr/share/applications",
                  "/run/current-system/sw/share/applications"]:
            for p in glob.glob(f"{d}/*.desktop"):
                try:
                    with open(p) as f:
                        app = {"id": os.path.basename(p).replace(".desktop",""),
                               "name":"", "icon":"application-x-executable", "exec":""}
                        in_entry = False
                        for line in f:
                            line = line.strip()
                            if line.startswith("[") and line.endswith("]"):
                                in_entry = (line == "[Desktop Entry]")
                            elif in_entry and "=" in line:
                                k,v = line.split("=",1)
                                k = k.strip(); v = v.strip()
                                if k == "Name": app["name"] = v
                                elif k == "Icon": app["icon"] = v
                                elif k == "Exec": app["exec"] = v
                                elif k == "NoDisplay" and v == "true": app = None; break
                        if app and app.get("name"): self.apps.append(app)
                except: pass
        self.log(f"App DB: {len(self.apps)} entries")

    def hyprctl(self, *args):
        try: return subprocess.check_output(["hyprctl"]+list(args), stderr=subprocess.DEVNULL, timeout=5).decode()
        except: return None

    def focus_app(self, app_id):
        """Focus a window by class using Hyprland's Lua dispatch."""
        lua_cmd = f'hl.dsp.focus({{"window":"class:{app_id}"}})'
        subprocess.run(["hyprctl", "dispatch", lua_cmd], capture_output=True, timeout=5)

    def handle(self, req):
        t = req.get("type")
        if t == "get_mru":
            running = set()
            raw = self.hyprctl("clients","-j")
            if raw:
                try:
                    for c in json.loads(raw):
                        if c.get("class"): running.add(c["class"])
                except: pass
            total = self.cfg.get("totalApps",20)
            whitelist = self.cfg.get("whitelistedApps",[])
            seg1, seen = [], set()
            for a in self.mru:
                if a in running and a not in seen:
                    seg1.append({"id":a,"running":True,"name":a,"icon":"application-x-executable","exec":a})
                    seen.add(a)
            for a in self.mru:
                if a not in seen:
                    seg1.append({"id":a,"running":False,"name":a,"icon":"application-x-executable","exec":a})
                    seen.add(a)
            from copy import deepcopy
            for a in whitelist:
                aid = a.replace(".desktop","")
                if aid not in seen and len(seg1) < total:
                    seg1.append({"id":aid,"running":aid in running,"name":aid,"icon":"application-x-executable","exec":aid})
                    seen.add(aid)
            cur = seg1[0]["id"] if seg1 else None
            sel = seg1[1]["id"] if len(seg1)>1 else cur
            return {"mru":seg1,"current":cur,"selected":sel}
        elif t == "get_app_db":
            return {"apps":self.apps}
        elif t == "cancel":
            return {"ok":True}
        elif t == "track_launch":
            a = req.get("app")
            if a:
                if a in self.mru: self.mru.remove(a)
                self.mru.insert(0,a)
                self.log(f"Tracked: {a}")
            return {"ok":True}
        elif t == "activate":
            a = req.get("app")
            if not a: return {"error":"missing app"}
            raw = self.hyprctl("clients","-j")
            if raw:
                try:
                    for c in json.loads(raw):
                        if c.get("class") == a:
                            if a in self.mru: self.mru.remove(a)
                            self.mru.insert(0,a)
                            self.focus_app(a)
                            self.log(f"Activated: {a}")
                            return {"ok":True}
                except: pass
            return {"ok":False,"reason":"not running","app":a}
        else:
            return {"error":"unknown type","type":t}

    def run(self):
        self.load_config()
        self.scan_apps()
        try: os.unlink(SOCKET)
        except: pass
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(SOCKET)
        s.listen(5)
        s.setblocking(False)
        poll = select.poll()
        poll.register(s, select.POLLIN)
        self.log(f"Listening on {SOCKET}")
        while self.running:
            for fd, ev in poll.poll(500):
                if fd == s.fileno():
                    try:
                        c, _ = s.accept()
                        data = c.recv(65536).decode().strip()
                        if data:
                            try:
                                req = json.loads(data)
                                resp = self.handle(req)
                                c.sendall((json.dumps(resp)+"\n").encode())
                            except json.JSONDecodeError:
                                c.sendall(b'{"error":"parse error"}\n')
                        c.close()
                    except: pass
        s.close()
        try: os.unlink(SOCKET)
        except: pass
        self.log("Exited")

if __name__ == "__main__":
    signal.signal(signal.SIGINT, lambda *_: os._exit(0))
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    Daemon().run()
