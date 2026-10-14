#!/usr/bin/env python3
"""brightd.py: backend for the XP tray brightness slider (bright.exe).
Listens on 127.0.0.1:4450 only; XP reaches it as 10.0.2.2:4450 through QEMU user networking.
Commands (one line per connection): "SET <0.10-1.00>" applies the level, "GET" returns it.
`brightd.py --apply` re-applies the saved level and exits. Also handles the keyboard brightness keys.
On start it re-applies the saved level, since X restarts and modesets reset the screen brightness."""
import os
import socket
import subprocess
import sys

STATE = os.path.expanduser("~/.cache/brightness.level")


def apply(level=None):
    """Set the screen brightness directly with xrandr (brightness-set.sh also pops a desktop notification, which
    blocks for ~25 s in the XP session where no notification daemon runs) and remember it."""
    if level is None:
        level = current()
    env = dict(os.environ, DISPLAY=":0", XAUTHORITY=os.path.expanduser("~/.Xauthority"))
    try:
        subprocess.run(["xrandr", "--output", os.environ.get("OUTPUT", "DisplayPort-0"), "--brightness", f"{level:.2f}"], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        with open(STATE, "w") as f:
            f.write(f"{level:.2f}" + chr(10))
    except (OSError, subprocess.SubprocessError):
        pass


def current():
    try:
        return float(open(STATE).read().strip())
    except (OSError, ValueError):
        return 1.0


if sys.argv[1:] == ["--apply"]:      # used by xp.sh after modesets: re-apply the saved level and exit
    apply()
    sys.exit(0)

# Brightness keys: the K811 (Mac layout) sends KEY_BRIGHTNESSDOWN/UP (224/225) on F6/F7 without Fn. Linux sees them
# before XP does, so listen on every input device that has those keys and step the level by 5%. Rescans every 5 s,
# because the Bluetooth keyboard gets a new event node each time it reconnects.
import select
import struct
import threading
import time

KEY_DOWN, KEY_UP, STEP = 224, 225, 0.05
lock = threading.Lock()


def has_brightness_keys(node):
    try:
        words = open(f"/sys/class/input/{node}/device/capabilities/key").read().split()
        bits = int("".join(w.zfill(16) for w in words) or "0", 16)
        return bool((bits >> KEY_DOWN) & 1 or (bits >> KEY_UP) & 1)
    except (OSError, ValueError):
        return False


def key_loop():
    devs, last_scan = {}, 0
    while True:
        if time.time() - last_scan > 5:
            last_scan = time.time()
            for node in os.listdir("/sys/class/input"):
                if node.startswith("event") and node not in devs and has_brightness_keys(node):
                    try:
                        devs[node] = open(f"/dev/input/{node}", "rb", buffering=0)
                        print(f"brightd: watching {node} for brightness keys", flush=True)
                    except OSError:
                        pass
        if not devs:
            time.sleep(5)
            continue
        ready, _, _ = select.select(list(devs.values()), [], [], 5)
        for f in ready:
            try:
                data = f.read(24 * 16)
            except OSError:
                data = b""
            if not data:   # device went away (keyboard disconnected)
                gone = [n for n, fh in devs.items() if fh is f]
                for n in gone:
                    devs.pop(n).close()
                continue
            for i in range(0, len(data) - 23, 24):
                _, _, typ, code, value = struct.unpack("qqHHi", data[i:i + 24])
                if typ == 1 and code in (KEY_DOWN, KEY_UP) and value in (1, 2):
                    with lock:
                        level = current() + (STEP if code == KEY_UP else -STEP)
                        apply(min(1.0, max(0.1, round(level, 2))))


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    srv.bind(("127.0.0.1", 4450))
except OSError:
    print("brightd: port 4450 busy, another instance is serving")
    sys.exit(0)
srv.listen(4)
apply()
threading.Thread(target=key_loop, daemon=True).start()
print(f"brightd: listening, level {current():.2f}", flush=True)
while True:
    conn, _ = srv.accept()
    conn.settimeout(2)
    try:
        line = conn.recv(64).decode(errors="ignore").strip()
        if line.startswith("SET "):
            level = min(1.0, max(0.1, float(line[4:])))
            with lock:
                apply(level)
            conn.sendall(f"OK {level:.2f}\n".encode())
        elif line == "GET":
            conn.sendall(f"{current():.2f}\n".encode())
    except (OSError, ValueError):
        pass
    finally:
        conn.close()
