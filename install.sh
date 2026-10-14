#!/bin/bash
# One-command setup of Windows XP on PS5 Linux (everything on the Linux side).
#   bash install.sh              interactive: asks for your XP ISO and product key
#   bash install.sh --dry-run    only shows what it would do; changes nothing
#   bash install.sh --no-system  skip the system files (session/tile boot); VM only
# Safe to run again: existing files are kept or backed up (*.bak-<date>), never silently replaced.
# Afterwards: install XP with  ~/xp/xp.sh install   (see README Step 6 onward).
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
XPDIR=${XPDIR:-$HOME/xp}
QEMU_DIR=${QEMU_DIR:-$HOME/qemu-3dfx}
BOOT=${BOOT:-/boot/efi}
DRY=0; SYSTEM=1
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --no-system) SYSTEM=0 ;; -h|--help) sed -n 2,7p "$0"; exit 0 ;; esac; done
STAMP=$(date +%Y%m%d-%H%M%S)

say()  { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mSTOP:\033[0m %s\n' "$*"; exit 1; }
run()  { if [ $DRY = 1 ]; then echo "   [dry-run] $*"; else eval "$@"; fi; }
# put_file SRC DST [sudo]: install a file, backing up a different existing one
put_file() {
  local src=$1 dst=$2 s=${3:-} mode=${4:-}
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then ok "$dst already up to date"; return; fi
  [ -f "$dst" ] && run "$s cp -a '$dst' '$dst.bak-$STAMP'" && warn "backed up $dst -> $dst.bak-$STAMP"
  run "$s install -D -m ${mode:-644} '$src' '$dst'"; ok "installed $dst"
}

say "1/7 Checks"
[ "$(id -u)" != 0 ] || die "run as your normal desktop user, not root (it uses sudo when needed)"
[ -e /dev/kvm ] || die "/dev/kvm is missing: this needs PS5 Linux with KVM (AMD-V)."
grep -q svm /proc/cpuinfo || die "the CPU does not report AMD-V (svm)."
sudo -v || die "sudo is needed"
ok "KVM available, user $(id -un)"
[ $DRY = 1 ] && warn "dry run: nothing will be changed"

say "2/7 QEMU 9.2.2 + qemu-3dfx + patches"
if [ -x "$QEMU_DIR/build/qemu-system-i386" ]; then ok "already built: $QEMU_DIR/build/qemu-system-i386"
else run "DEST='$QEMU_DIR' bash '$REPO/qemu/build.sh'"; fi

say "3/7 VM folder $XPDIR"
run "mkdir -p '$XPDIR/floppy'"
for f in "$REPO"/linux/xp/*; do m=644; case "$f" in *.sh|*.py) m=755 ;; esac; put_file "$f" "$XPDIR/$(basename "$f")" "" $m; done

say "4/7 Windows XP disc (32-bit / x86 only)"
if [ -f "$XPDIR/xp.iso" ]; then ok "$XPDIR/xp.iso present"
else
  read -r -p "   Path to YOUR Windows XP Professional SP3 32-bit ISO: " ISO
  ISO=${ISO/#\~/$HOME}; [ -f "$ISO" ] || die "file not found: $ISO"
  run "cp '$ISO' '$XPDIR/xp.iso'"; ok "copied to $XPDIR/xp.iso"
fi
if [ $DRY = 0 ]; then
  LABEL=$(blkid -o value -s LABEL "$XPDIR/xp.iso" 2>/dev/null || true)
  echo "   disc label: ${LABEL:-unknown}"
  case "${LABEL^^}" in *X64*|*AMD64*|*64*) die "this looks like XP x64. Use the 32-bit (x86) edition (README: Why 32-bit)." ;; esac
fi

say "5/7 Unattended-install answer file"
if [ -f "$XPDIR/floppy/winnt.sif" ]; then ok "floppy/winnt.sif present (kept)"
elif [ $DRY = 1 ]; then echo "   [dry-run] would ask for the product key and write $XPDIR/floppy/winnt.sif"
else
  read -r -p "   Your Windows XP product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX): " KEY
  [[ "$KEY" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]] || die "that does not look like an XP key"
  read -r -p "   Your name for Windows [Player]: " NAME; NAME=${NAME:-Player}
  sed -e "s/XXXXX-XXXXX-XXXXX-XXXXX-XXXXX/${KEY^^}/" -e "s/^FullName=\"Player\"/FullName=\"$NAME\"/" \
      "$REPO/guest/winnt.sif.template" > "$XPDIR/floppy/winnt.sif"
  ok "written (the key stays only in this file on your PS5)"
fi

say "6/7 Virtual hard drive"
if [ -f "$XPDIR/xp.qcow2" ]; then ok "$XPDIR/xp.qcow2 present (kept)"
else run "'$QEMU_DIR/build/qemu-img' create -f qcow2 '$XPDIR/xp.qcow2' ${DISK:-40G} >/dev/null"; ok "created xp.qcow2 (${DISK:-40G}, grows as used)"; fi

say "7/7 Boot straight into XP from the tile"
if [ $SYSTEM = 0 ]; then warn "skipped (--no-system)"
else
  put_file "$REPO/linux/system/ps5-session" /usr/local/bin/ps5-session sudo 755
  run "sudo sed -i 's|^XPDIR=.*|XPDIR=\${XPDIR:-$XPDIR}      # where xp.sh and the VM files live|; s|^HOME_DIR=.*|HOME_DIR=\${HOME_DIR:-$HOME}   # home of the desktop user|' /usr/local/bin/ps5-session"
  for f in "$REPO"/linux/system/ps5-xp.conf.d/*; do put_file "$f" "/etc/X11/ps5-xp.conf.d/$(basename "$f")" sudo; done
  put_file "$REPO/linux/system/70-xp-playstation-pads.rules" /etc/udev/rules.d/70-xp-playstation-pads.rules sudo
  run "sudo udevadm control --reload"
  # Session starter: only install ours when nothing else starts the desktop.
  if systemctl is-enabled sddm.service >/dev/null 2>&1 || systemctl is-enabled display-manager.service >/dev/null 2>&1; then
    warn "a display manager is enabled: not installing plasma-autostart.service."
    warn "make your autologin session run /usr/local/bin/ps5-session instead of startplasma-x11 (docs/TECHNICAL.md#session-start)"
  else
    TMPU=$(mktemp); sed "s/^User=steam/User=$(id -un)/; s/^Group=steam/Group=$(id -gn)/; s|/home/steam|$HOME|g; s|/run/user/1000|/run/user/$(id -u)|g" \
      "$REPO/linux/system/plasma-autostart.service" > "$TMPU"
    put_file "$TMPU" /etc/systemd/system/plasma-autostart.service sudo 644; rm -f "$TMPU"
    run "sudo systemctl daemon-reload && sudo systemctl enable plasma-autostart.service >/dev/null 2>&1"; ok "plasma-autostart.service enabled"
  fi
  if [ -f "$BOOT/cmdline.txt" ]; then
    LINE="$(tr -d '\n' < "$BOOT/cmdline.txt" | sed 's/ ps5vm=[^ ]*//g') ps5vm=xp"
    if [ -f "$BOOT/cmdl-xp.txt" ] && [ "$(tr -d '\n' < "$BOOT/cmdl-xp.txt")" = "$LINE" ]; then ok "$BOOT/cmdl-xp.txt up to date"
    else
      [ -f "$BOOT/cmdl-xp.txt" ] && run "sudo cp '$BOOT/cmdl-xp.txt' '$BOOT/cmdl-xp.txt.bak-$STAMP'"
      run "echo '$LINE' | sudo tee '$BOOT/cmdl-xp.txt' >/dev/null"; ok "wrote $BOOT/cmdl-xp.txt"
    fi
  else warn "$BOOT/cmdline.txt not found: create cmdl-xp.txt by hand (README Step 8.2)"; fi
fi

say "Done"
cat <<EOF
   Next:
   1. Install Windows XP (20-30 min, hands-off):   $XPDIR/xp.sh install
   2. Drivers, 3D, browser, brightness:            README Step 7
   3. Home-screen tile (on your PC + GitHub):      README Step 8.3 - 8.5
EOF
