#!/bin/bash
# Windows XP under KVM on PS5 Linux. Modes: run (window), kiosk (tile boot), desktop (Plasma icon), install (XP CD + answer floppy).
# ---- settings (override with environment variables) ----
XPDIR=${XPDIR:-$HOME/xp}                                         # VM folder: xp.qcow2, xp.iso, tools.iso, this script
QEMU=${QEMU:-$HOME/qemu-3dfx/build/qemu-system-i386}             # QEMU 9.2.2 + qemu-3dfx + the patches in qemu/patches
OUTPUT=${OUTPUT:-DisplayPort-0}                           # xrandr output name of the PS5 HDMI port
RAM=${RAM:-2048}                                                 # MB for XP (32-bit XP uses at most ~3.5 GB)
CPUS=${CPUS:-8}
NOLAN=${NOLAN:-0}                                                # 1 = keep XP off the home network, internet only (optional, see README)
# NOLAN=1 runs this script again under the group "xpnet", so the firewall rule from linux/system/xp-nolan.nft can tell
# QEMU's connections apart from the rest of the PS5. Needs the one-time setup in README.md first.
if [ "$NOLAN" = 1 ] && [ "$(id -gn)" != xpnet ]; then
  getent group xpnet | grep -qw "$(id -un)" || { echo "NOLAN=1: user $(id -un) is not in group xpnet, see README.md"; exit 1; }
  exec sg xpnet -c "$(printf '%q ' bash "$(readlink -f "$0")" "$@")"
fi
cd "$XPDIR" || exit 1
export DISPLAY=:0 SDL_VIDEODRIVER=x11
MODE=${1:-run}; [ $# -gt 0 ] && shift
# Keep the guest memory cache types write-back (patched QEMU, see kvm_wrmsr_pat_ignore in kvm.c): XP's display
# driver maps the emulated video memory uncached, which made all 2D drawing crawl. WBPAT=0 turns it off.
[ "${WBPAT:-1}" = 1 ] && export QEMU_FORCE_WB_PAT=1
# Mouse: XP gets the PS/2 mouse (relative). The USB tablet (absolute) made DirectInput games
# move their cursor in jumps. MOUSEDEV="-device usb-tablet" brings the tablet back.
EXTRA=""

# The PS5 display link loses sync when QEMU recreates its full-screen window, which the 3D
# pass-through does each time a game opens or closes its 3D context. Linux still reports the
# mode as active, so the fix is a fresh modeset (alternating 60 / 59.94 Hz) once the burst settles.
relink() {
  tail -n0 -F $XPDIR/qemu.log 2>/dev/null \
    | grep -a --line-buffered -E "wglMakeCurrent cntx 1 curr 0|wglDeleteContext" \
    | while read -r _; do
        while read -r -t 3 _; do :; done
        r=59.94; [ "$(cat /tmp/xp-rate 2>/dev/null)" = 59.94 ] && r=60
        echo $r > /tmp/xp-rate
        xrandr --output $OUTPUT --mode 1920x1080 --rate $r
        echo "relink: modeset 1920x1080@$r"
        python3 $XPDIR/brightd.py --apply   # a modeset resets the screen brightness
      done
}

if [ "$MODE" = install ]; then
  EXTRA="-boot d -drive file=fat:floppy:rw:$XPDIR/floppy,format=raw,if=floppy"
elif [ "$MODE" = kiosk ] || [ "$MODE" = desktop ]; then
  # kiosk: started by ps5-session straight from boot; the console powers off when XP shuts down.
  # desktop: started from the Plasma desktop icon; back to the 4K desktop when XP shuts down.
  [ -f $XPDIR/qemu.log ] && mv -f $XPDIR/qemu.log $XPDIR/qemu.log.prev   # crash forensics
  exec > $XPDIR/qemu.log 2>&1
  [ "$MODE" = kiosk ] && touch /tmp/xp-kiosk-started   # tells ps5-session that X itself came up
  EXTRA="-full-screen"
  xrandr --output $OUTPUT --mode 1920x1080 --rate 60 2>/dev/null
  echo 60 > /tmp/xp-rate
  # On a cold boot from the tile the PipeWire/Pulse server may not be up yet: wait up to 15 s, else boot XP silent.
  for i in $(seq 1 30); do pactl info >/dev/null 2>&1 && break; sleep 0.5; done
  echo "kiosk: XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pulse socket: $(ls -la $XDG_RUNTIME_DIR/pulse/native 2>&1)"; pactl info 2>&1 | grep -E "Server Name|Connection failure" | sed "s/^/kiosk: /"
  if ! pactl info >/dev/null 2>&1; then echo "kiosk: no sound server, starting XP without audio"; AUDIO="-audiodev none,id=snd0"; fi
  relink >> $XPDIR/relink.log 2>&1 &
  WATCH=$!
  # Backend for the XP tray brightness slider (bright.exe), reached from XP as 10.0.2.2:4450.
  python3 $XPDIR/brightd.py >> $XPDIR/brightd.log 2>&1 &
  BRIGHTD=$!
  # The screen can stay dark after X starts, so do one more fresh modeset once QEMU is up. The tile boot now
  # starts X at 1080p@60 (ps5-session, /etc/X11/ps5-xp.conf.d); this stays as a safety net.
  ( sleep 8; echo 59.94 > /tmp/xp-rate; xrandr --output $OUTPUT --mode 1920x1080 --rate 59.94; echo "kiosk: startup modeset 1080p@59.94"; python3 $XPDIR/brightd.py --apply ) &
  START=$(date +%s)
  rm -f /tmp/xp-kiosk-failed
  if [ "$MODE" = kiosk ]; then
    # Power off only after a real XP session. If QEMU dies within its first minute (a failed start),
    # leave a marker instead so ps5-session falls back to the Plasma desktop.
    trap 'pkill -P $WATCH; kill $WATCH $BRIGHTD 2>/dev/null
          if [ $(( $(date +%s) - START )) -lt 60 ]; then echo "kiosk: QEMU exited after $(( $(date +%s) - START )) s, falling back to the desktop"; touch /tmp/xp-kiosk-failed
          elif [ ! -f $XPDIR/NOPOWEROFF ]; then sudo systemctl poweroff; fi' EXIT
  else
    trap "pkill -P $WATCH; kill $WATCH $BRIGHTD 2>/dev/null; xrandr --output $OUTPUT --mode 3840x2160 --rate 60" EXIT
  fi
fi
# The tools disc (drivers, scripts) is optional: it does not exist yet while XP is being installed.
TOOLS=${TOOLS:-tools.iso}
TOOLSDRIVE=""; [ -f "$TOOLS" ] && TOOLSDRIVE="-drive file=$TOOLS,media=cdrom,if=ide"
while :; do
"$QEMU" -accel kvm -cpu host,-hypervisor -m $RAM -smp $CPUS,sockets=1,cores=$CPUS -M pc \
  -drive file=xp.qcow2,if=ide,format=qcow2,cache=writeback \
  -drive file=xp.iso,media=cdrom,if=ide \
  $TOOLSDRIVE \
  -vga vmware -display sdl \
  -usb ${MOUSEDEV:-} \
  -device usb-ehci,id=ehci -device usb-host,bus=ehci.0,vendorid=0x054c,productid=${PADPID:-0x0ce6},id=dualsense \
  ${AUDIO:--audiodev pa,id=snd0} -device AC97,audiodev=snd0 \
  -netdev user,id=n0 -device rtl8139,netdev=n0 \
  -rtc base=localtime,clock=host \
  -monitor tcp:127.0.0.1:4445,server,nowait \
  -serial file:$XPDIR/serial.txt \
  -name "Windows XP" $EXTRA "$@"
rc=$?
echo "kiosk: qemu exit code $rc after $(( $(date +%s) - ${START:-$(date +%s)} )) s"
# QEMU killed by a signal (a crash: exit code 128 + signal) after a real session: start XP again rather than
# ending the session, which in kiosk mode powers the console off. A shutdown from XP itself exits 0.
if [ $rc -ge 128 ] && { [ "$MODE" = kiosk ] || [ "$MODE" = desktop ]; } && [ $(( $(date +%s) - ${START:-0} )) -ge 60 ]; then
  echo "kiosk: QEMU crashed (signal $((rc - 128))) at $(date +%T), starting XP again"; sleep 2; continue
fi
break
done
