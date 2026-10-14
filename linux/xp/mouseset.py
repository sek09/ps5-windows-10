"""mouseset.py tablet|ps2 : route the host mouse to that guest device via the QEMU monitor (HMP mouse_set).
The desktop wants the USB tablet (absolute, exact); DirectInput games want the PS/2 mouse (relative)."""
import re, socket, sys, time

want = {"tablet": "Tablet", "ps2": "PS/2"}[sys.argv[1]]

def drain(s, wait=0.5):
    out, end = b"", time.time() + wait
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d:
                break
            out += d
        except socket.timeout:
            pass
    return out.decode("latin1")

s = socket.create_connection(("127.0.0.1", 4445), timeout=5)
s.settimeout(0.2)
drain(s)
s.sendall(b"info mice\n")
mice = re.findall(r"Mouse #(\d+): ([^\r\n]+)", drain(s))
idx = [n for n, name in mice if want in name]
if not idx:
    print(f"mouse: no {want} device in {mice}")
    sys.exit(1)
s.sendall(f"mouse_set {idx[0]}\n".encode())
drain(s, 0.3)
print(f"mouse: {sys.argv[1]} (#{idx[0]}) at {time.strftime('%H:%M:%S')}")
