# Display issues and how to fix them

**None of this is needed for Windows XP to work, and nothing here is installed automatically.** These are fixes for
PS5 Linux picture problems that happen on **some monitors/TVs** when the PS5 is connected **directly by HDMI at 4K**.
If your picture is fine, skip this page.

Each problem below: **what you see → why it happens → the files → what to do.**
All files are in [`files/`](files). Commands run in **Konsole** on PS5 Linux.

---

## 1. Pink, garbled or cropped picture right after Linux boots (4K)

**What you see:** PS5 Linux boots to a pink/garbled or cropped desktop at 4K. Switching to 1080p and back to 4K fixes it.

**Why:** the PS5's display pipeline reports an "underflow" on the very first 4K picture after boot. Only a detour
through another resolution clears it (turning the output off/on does not). Root cause in the kernel is still unknown.

**Files:** `10-ps5-boot-1080p.conf` (X starts at 1080p, then the desktop switches to your saved 4K layout = the
detour), `set-4k.sh` (optional safety net: checks after login and only repeats the detour if still needed; log in
`~/display-autoset.log`).

**What to do:**
1. Set the desktop to 4K once in System Settings → Display (so it remembers 4K).
2. ```
   sudo cp ~/ps5-windows-xp/display-fixes/files/10-ps5-boot-1080p.conf /etc/X11/xorg.conf.d/
   ```
3. Optional safety net: copy `set-4k.sh` to `~/.local/bin/`, `chmod +x` it, and add it in
   System Settings → Autostart → Add Login Script.
4. Reboot. **Undo:** delete `/etc/X11/xorg.conf.d/10-ps5-boot-1080p.conf`.

> The Windows XP boot does not use this file; it has its own 1080p@60 config (`/etc/X11/ps5-xp.conf.d`).

---

## 2. "No signal" a few seconds after switching to 4K (or after the monitor wakes up)

**What you see:** the picture appears at 4K, then the monitor says *no signal* and never comes back
(often ~2 seconds after the switch, or after the monitor wakes from standby).

**Why:** the monitor "re-announces" itself after a 4K switch. The PS5's DP-to-HDMI bridge chip must then be
configured again (4K needs HDMI scrambling), but the stock PS5 Linux driver never re-sends that setup.

**Files:** `ps5_hdmi_fix.c` + `Makefile` (a small kernel module: it notices the re-announce and replays the bridge
setup, at most 3 times per minute), `ps5-hdmi-fix.service` (loads it at boot).

**What to do:**
1. Build it (needs the kernel headers/build tree **matching your running kernel**; it was made for **7.1.7**):
   ```
   mkdir ~/ps5-hdmi-fix && cp ~/ps5-windows-xp/display-fixes/files/{ps5_hdmi_fix.c,Makefile} ~/ps5-hdmi-fix/
   cd ~/ps5-hdmi-fix && make -C /lib/modules/$(uname -r)/build M=$PWD modules
   ```
2. Install and load at every boot:
   ```
   sudo mkdir -p /usr/lib/modules/$(uname -r)/extra && sudo cp ps5_hdmi_fix.ko /usr/lib/modules/$(uname -r)/extra/
   sudo depmod -a
   sudo cp ~/ps5-windows-xp/display-fixes/files/ps5-hdmi-fix.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now ps5-hdmi-fix.service
   ```
3. Check: `lsmod | grep ps5_hdmi_fix` shows it; after a re-announce `dmesg | grep ps5_hdmi` shows a replay and
   the picture heals in ~6 s.
4. Manual trigger if ever needed: `echo reconf | sudo tee /sys/module/ps5_hdmi_fix/parameters/cmd`.
   Settings: `/sys/module/ps5_hdmi_fix/parameters/{enabled,only_4k,delay_ms}`.

> **After a kernel update you must rebuild the module** (step 1–2). Why systemd and not modules-load.d: see fix 3.

---

## 3. No network (or random missing services) after some boots

**What you see:** sometimes Wi-Fi/Ethernet is dead after boot, or other early services are missing.

**Why:** the image's `ps5-stage-firmware.service` creates a startup ordering loop; systemd breaks the loop by
dropping a random early service (once it dropped D-Bus, which killed NetworkManager).

**Files:** `no-cycle.conf`.

**What to do:**
```
sudo mkdir -p /etc/systemd/system/ps5-stage-firmware.service.d
sudo cp ~/ps5-windows-xp/display-fixes/files/no-cycle.conf /etc/systemd/system/ps5-stage-firmware.service.d/
sudo systemctl daemon-reload
systemd-analyze verify default.target   # should no longer mention an ordering cycle
```
Quick fix if the network is dead right now: `sudo systemctl start NetworkManager`.

---

## 4. Black screen for a moment when a 3D game opens or closes in XP

**What you see:** the screen goes black/no signal when an XP game starts or quits.

**Why:** qemu-3dfx recreates the full-screen window, and the PS5 display link loses sync (Linux still thinks it is fine).

**Already handled:** `xp.sh` watches for this and does a fresh mode switch ~3 seconds later (`~/xp/relink.log`).
Nothing to install. If it ever stays black: from another device, `ssh` in and run
`DISPLAY=:0 xrandr --output DisplayPort-0 --mode 1920x1080 --rate 60`.

---

## 5. Picture drops after a while at 120 Hz

**What you see:** at 1080p **120 Hz** the monitor loses the signal after ~30 minutes.

**What to do:** use **60 Hz** on PS5 Linux. The XP boot already forces 1920×1080@60
(`/etc/X11/ps5-xp.conf.d/10-ps5-xp-1080p60.conf`) because some monitors prefer 1080p@120.

---

## ⚠️ Safety

**Never scan the GPU's registers in bulk** (for example reading a whole range through
`/sys/kernel/debug/dri/0/amdgpu_regs`). Reading certain registers hard-froze a PS5 during this research. Only read
specific, named display registers if you investigate further.
