# Technical reference

Everything about how Windows XP runs on the PS5, why each piece exists, and how to rebuild or debug it.
The beginner guide is the [README](../README.md); the AI checklist is [AGENTS.md](../AGENTS.md).

## Architecture

```
PS5 home screen tile "Windows XP" (WKAL00002)
  └─ WebKit Autoloader tile (itsPLK, + tiles patch) sends a payload: the PS5 Linux loader v2.5, patched to read
     cmdl-xp.txt instead of cmdline.txt from the FAT boot partition
       └─ PS5 Linux boots with "ps5vm=xp" on the kernel command line
            └─ plasma-autostart.service (systemd, user steam, tty1) runs /usr/local/bin/ps5-session
                 └─ ps5-session sees ps5vm=xp → startx with -configdir ps5-xp.conf.d (X at 1920x1080@60)
                      └─ xp.sh kiosk → QEMU 9.2.2 + qemu-3dfx + patches, -accel kvm, full screen
                           └─ Windows XP SP3 32-bit (guest)
XP shuts down → QEMU exits 0 → xp.sh trap → systemctl poweroff (PS5 turns off)
```

Why KVM works: under PS5 Linux the AMD Zen 2 CPU exposes SVM (AMD-V) and no hypervisor sits underneath, so
`/dev/kvm` is available and XP runs natively (measured ≈ 9.5× faster than pure emulation).

## Repository layout

| Path | Installed to | Purpose |
|---|---|---|
| `linux/xp/xp.sh` | `~/xp/xp.sh` | VM launcher. Modes: `run` (window), `install` (XP CD + answer floppy), `kiosk` (tile boot, powers off at the end), `desktop` (from a desktop icon, returns to 4K) |
| `linux/xp/brightd.py` | `~/xp/` | Brightness backend on 127.0.0.1:4450 (XP reaches it as 10.0.2.2:4450); also reads keyboard brightness keys via evdev |
| `linux/xp/mouseset.py` | `~/xp/` | Switch the host mouse between the PS/2 mouse and the USB tablet through the QEMU monitor |
| `linux/xp/xppeek.sh` | `~/xp/` | Read-only view of XP's C: drive at /mnt/xpc while it runs (qemu-storage-daemon FUSE + loop + ntfs3 ro) |
| `linux/xp/netwatch.sh` | `~/xp/` | Logs every remote endpoint the XP guest connects to (slirp connections are host sockets of QEMU) |
| `linux/system/ps5-session` | `/usr/local/bin/` | Session chooser: `ps5vm=xp` → XP kiosk, else Plasma; falls back to Plasma if QEMU dies within 60 s |
| `linux/system/plasma-autostart.service` | `/etc/systemd/system/` | Starts ps5-session on tty1 as the desktop user (the image masks getty@tty1) |
| `linux/system/ps5-xp.conf.d/*` | `/etc/X11/ps5-xp.conf.d/` | X config used only for the XP boot: 1080p@60 preferred mode, no DPMS blanking |
| `linux/system/70-xp-playstation-pads.rules` | `/etc/udev/rules.d/` | Lets QEMU (non-root) open DualSense/DS4 USB devices for passthrough |
| `linux/system/cmdl-xp.txt.example` | `/boot/efi/cmdl-xp.txt` | Kernel command line for the XP boot = normal cmdline.txt + ` ps5vm=xp` |
| `qemu/build.sh`, `qemu/patches/*` | builds `~/qemu-3dfx/build/` | QEMU 9.2.2 + qemu-3dfx 920661f + 4 patches |
| `tile/ps5-webkit-autoloader-tiles.patch` | your fork of itsPLK/ps5-webkit-autoloader | Adds single-purpose tiles (own title ID, name, port, icon, fixed payload) + a GitHub Actions build |
| `tile/patch_loader.py` | run on a PC | Makes loader-xp.elf: `cmdline.txt` → `cmdl-xp.txt` (offset 0x18708 in v2.5) |
| `guest/*` | tools.iso → XP | XP-side scripts, answer-file template, brightness tray app source |
| `.github/workflows/build-wrappers.yml` | GitHub Actions | Builds the qemu-3dfx guest wrappers (opengl32, glide*, fxptl.sys, instdrv) with i686 mingw on Ubuntu |
| `.github/workflows/build-bright.yml` | GitHub Actions | Builds `bright.exe` |
| `display-fixes/` | optional | PS5 Linux picture fixes (see its README) |

## The QEMU command line (xp.sh) and why

```
qemu-system-i386 -accel kvm -cpu host,-hypervisor -m 2048 -smp 8,sockets=1,cores=8 -M pc
  -drive file=xp.qcow2,if=ide,format=qcow2,cache=writeback
  -drive file=xp.iso,media=cdrom,if=ide   [-drive file=tools.iso,media=cdrom,if=ide]
  -vga vmware -display sdl [-full-screen]
  -usb  -device usb-ehci,id=ehci -device usb-host,bus=ehci.0,vendorid=0x054c,productid=0x0ce6,id=dualsense
  -audiodev pa,id=snd0 -device AC97,audiodev=snd0
  -netdev user,id=n0 -device rtl8139,netdev=n0
  -rtc base=localtime,clock=host
  -monitor tcp:127.0.0.1:4445,server,nowait  -serial file:serial.txt  -name "Windows XP"
```

| Option | Reason |
|---|---|
| `-accel kvm -cpu host,-hypervisor` | Native speed; hide the hypervisor bit (some XP-era software misbehaves when it sees it) |
| `-smp 8,sockets=1,cores=8` | XP Pro supports 2 sockets max, so all cores in one socket |
| `-vga vmware` | VMware SVGA II: best 2D on XP (driver 11.9.1; 12.x falls back to 4-bit color) |
| `-display sdl` (not `gl=on`) | qemu-3dfx's mesapt/glidept need plain SDL |
| usb-ehci + usb-host DualSense | DualSense is a USB 2.0 high-speed device; it cannot sit on the default UHCI. XP sees a HID game controller (DirectInput) |
| PS/2 mouse (no usb-tablet) | The absolute tablet makes DirectInput games' cursors jump. `MOUSEDEV="-device usb-tablet"` re-enables it |
| AC97 / rtl8139 | XP SP3 has built-in drivers for both |
| `-monitor tcp:127.0.0.1:4445` | HMP for tooling (mouseset.py, screendumps). **Bind to 127.0.0.1 only**: HMP can run host commands |
| env `QEMU_FORCE_WB_PAT=1` | Enables patch 0001/0002 (see below) |
| `WINEDEBUG=-all` (inside XP) | See "Direct3D performance" |

Environment overrides: `XPDIR`, `QEMU`, `OUTPUT` (xrandr output, default `DisplayPort-0`), `RAM`, `CPUS`, `TOOLS`,
`PADPID` (DualSense `0x0ce6`, Edge `0x0df2`, DS4 `0x05c4`/`0x09cc`), `MOUSEDEV`, `WBPAT=0` (disable the PAT fix),
`AUDIO`.

### Kiosk behaviour

- Output forced to 1920×1080@60 before QEMU; a second modeset 8 s later as a safety net (the link can stay dark after X starts).
- Waits up to 15 s for PipeWire/Pulse (`pactl info`); otherwise starts XP silent (`-audiodev none`) instead of failing.
- `relink()` tails qemu.log for `wglMakeCurrent cntx 1 curr 0|wglDeleteContext` (a 3D context opened or closed),
  waits for 3 s of quiet, then does a fresh modeset alternating 60 / 59.94 Hz. Reason: when qemu-3dfx recreates its
  full-screen window the PS5 display link loses sync although Linux still reports the mode as active.
- Exit trap: QEMU ran < 60 s → `/tmp/xp-kiosk-failed` (ps5-session starts Plasma instead of powering off).
  Otherwise `systemctl poweroff` (skip with `~/xp/NOPOWEROFF` for testing).
- QEMU killed by a signal (exit ≥ 128) after a real session → restart XP instead of powering off (crash loop guard
  for the "Restart crashes QEMU" issue).

## QEMU patches (`qemu/patches`)

### 0001 + 0002: force write-back memory types on AMD (the big desktop-speed fix)

XP's VMware SVGA driver maps the emulated framebuffer BAR (16 MB) with PCD+PWT (PAT index 3 = UC). On AMD, KVM
honours the guest PAT (there is no "ignore PAT" bit like Intel's EPT IPAT), so every 2D draw ran at uncached
speed: dragging a window pegged one vCPU at ~88 %. Since every device in this VM is emulated, uncached guest
mappings buy nothing. With `QEMU_FORCE_WB_PAT` set:

- `target/i386/kvm/kvm.c`: a KVM userspace MSR filter traps guest writes to `MSR_PAT` (0x277) and ignores them;
- `target/i386/cpu.c`: the reset value of PAT becomes all write-back `0x0606060606060606`.

Result: the same window drag ≈ 5–7 % vCPU; YouTube full screen in Supermium plays without stutter.
**Worth upstreaming** (QEMU / qemu-3dfx) as an opt-in for AMD hosts with fully emulated devices.

### 0003: 8 ms GUI refresh

`GUI_REFRESH_INTERVAL_DEFAULT` 30 → 8 ms: the emulated 2D screen is repainted at 120 Hz instead of 33 Hz, which makes
the desktop and mouse feel smooth. (The display mode itself stays 60 Hz; see display-fixes about 120 Hz.)

### 0004: full screen = desktop size in SDL2

The kiosk X server has no window manager, so `SDL_WINDOW_FULLSCREEN_DESKTOP` is not enforced. When qemu-3dfx
recreated the window after a game switched XP to 800×600, the window became 800×600 at 0,0 and the image sat in a
corner. In full screen, `sdl2_window_create` now sizes the window to `SDL_GetDesktopDisplayMode` at 0,0 and
`sdl2_window_resize` returns early. 2D is scaled by `SDL_RenderSetLogicalSize`, 3D by the mesapt scaler, both
aspect-correct (4:3 is pillarboxed).

## 3D inside XP (qemu-3dfx)

- Host: kjliew/qemu-3dfx at commit **920661f** (the guest wrappers must match the host revision — build both
  from the same commit; `build-wrappers.yml` pins it).
- Guest: `fxptl.sys` + `glide*.dll` in `system32` (INST3D.CMD), `opengl32.dll` copied **into each OpenGL game's
  folder** (not system32).
- Wrappers must link **msvcrt**, not UCRT: builds made with a modern Arch mingw import `api-ms-win-crt-*` and fail
  on XP. That is why they are built on Ubuntu 24.04 (`gcc-mingw-w64-i686`).
- Direct3D games: **WineD3D 1.7.52** (the last build for XP, fdossena.com): put `d3d8.dll`/`d3d9.dll` + `libwine.dll`
  + `wined3d.dll` in the game folder. WineD3D → OpenGL → qemu-3dfx → PS5 GPU (radeonsi).
- Verified: OpenArena ~90 fps (game cap), NFSU2 and Midnight Club 2 playable.

### Direct3D performance: WINEDEBUG=-all

With WineD3D's default debug channels, `checkGLcall` calls `glGetError` after nearly every GL call. In qemu-3dfx's
guest wrapper `glGetError` is a synchronous MMIO round trip (write + read of the doorbell page): ~19k round trips/s,
one vCPU at 94 % while the GPU idled. `WINEDEBUG=-all` as a system environment variable (FIXD3D.CMD) cut it to
~11k/s and fixed the frame rate.

### Pitfalls found the hard way

- **Never create `HKCU\Software\Wine`** in XP (even empty): WineD3D 1.7.52 then crashes in the GL wrapper at adapter
  init for every D3D game. Delete it with `reg delete HKCU\Software\Wine /f`.
- **Never `taskkill /f` a 3D game** inside XP: the pass-through stays wedged until XP restarts.
- The VM offers **no 16-bit display modes** (`R5G6B5` = `D3DERR_NOTAVAILABLE`). Games that insist on 16-bit may fail.
- **EA-era games crash at start without their HKLM install key** (`HKLM\SOFTWARE\EA Games\<game>`: Install Dir,
  Language, …). Add the registry entries before blaming the GPU layer.
- XP's Run box rejects long commands; use `cmd /k` and type there.
- Add-ons built for Vista+ (e.g. some `.asi` loaders/patches) fail on XP with missing `InitOnce*` imports.

## Session start

The PS5 Linux image masks `getty@tty1`; `plasma-autostart.service` runs `ps5-session` on tty1 as the desktop user
with a PAM session (so PipeWire and the user manager start). If your image already starts the desktop another way
(display manager, autologin), keep it and only make it run `ps5-session` instead of `startplasma-x11`.

`ps5-session` test hook without rebooting: `echo xp > ~/.ps5vm`, `touch ~/xp/NOPOWEROFF`,
`sudo systemctl restart plasma-autostart.service`; remove both files afterwards.

## The tile

`tile/ps5-webkit-autoloader-tiles.patch` (against itsPLK/ps5-webkit-autoloader `main`) adds:

- `tools/make_tile.py <tile>`: rewrites title ID, app name, port and icon from `tiles/<tile>/tile.json`;
- `tiles/xp/tile.json` (`WKAL00002`, "Windows XP", port 18182) and `tiles/xp/icon.svg`;
- `.github/workflows/build-tile.yml`: builds the installer in the SDK docker image with
  `AUTOLOAD_ELF=tiles/<tile>/loader.elf` (the payload is embedded; `*.elf` is git-ignored, add it with `-f`).

The installer page offers the exploit choice; pick **relapse** on 7.40. It installs a second app next to the
regular WebKit Autoloader (WKAL00001).

**Why the loader is patched:** loader v2.5 reads `cmdline.txt` from the FAT boot partition (`/boot/efi` in Linux,
next to `bzImage`, `initrd.img`, `vram.txt`) and only uses its embedded command line when that file is missing, so
an embedded `ps5vm=xp` never applies. The XP loader reads `cmdl-xp.txt` instead; keep it equal to `cmdline.txt` +
` ps5vm=xp` whenever you change `cmdline.txt`.

## Clock

The PS5 kernel clock can run one hour ahead during DST. Guest RTC = host local time (`-rtc base=localtime`).
XP's built-in DST rules are the pre-2007 US ones: disable XP's automatic DST adjustment
(Date and Time → Time Zone → untick "Automatically adjust clock for daylight saving changes") and set the zone.

## Debugging

| Want | How |
|---|---|
| QEMU log of the last tile boot | `~/xp/qemu.log` (previous boot: `qemu.log.prev`) |
| Relink / brightness logs | `~/xp/relink.log`, `~/xp/brightd.log` |
| QEMU monitor | `nc 127.0.0.1 4445` on the PS5 (from a PC: `ssh -L 4445:127.0.0.1:4445 user@ps5`) |
| Screenshot of XP | HMP `screendump /tmp/x.ppm` (2D only); 3D: `ffmpeg -f x11grab -i :0 -frames 1 x.png` |
| See XP's files while it runs | `sudo ~/xp/xppeek.sh mount` → `/mnt/xpc` (read-only), `umount` afterwards |
| Benchmarks | `guest/BENCH.JS` (loop + pi, result on COM1 → `~/xp/serial.txt`), `BENCH2.JS` (app launch times) |
| Network activity of the guest | `~/xp/netwatch.sh` → `netwatch.log` |
| Backups | With XP running: HMP `drive_backup -f ide0-hd0 /path/xp-backup.qcow2 qcow2` (~35 s); or copy xp.qcow2 while XP is off |

## Performance reference (PS5, this setup)

KVM XP vs pure software emulation: ≈ 9.5× faster. Desktop 2D: smooth after patches 0001–0003. Direct3D games:
playable after `WINEDEBUG=-all`. OpenGL: ~90 fps OpenArena (capped).
