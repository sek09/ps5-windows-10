#!/usr/bin/env bash
# Windows 10 guest launcher for PS5 Linux.
# This is intentionally separate from xp.sh and does not use the XP-only qemu-3dfx patches.
set -euo pipefail

VM_DIR="${WIN10_DIR:-$HOME/windows10}"
QEMU="${QEMU_WIN10:-$HOME/qemu-windows10/build/qemu-system-x86_64}"
ISO="${WIN10_ISO:-$VM_DIR/Win10.iso}"
DISK="${WIN10_DISK:-$VM_DIR/windows10.qcow2}"
RAM="${WIN10_RAM:-4096}"
CPUS="${WIN10_CPUS:-4}"

die() { printf 'Windows 10: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Linux ]] || die "Run this script on PS5 Linux, not Windows or WSL2."
[[ -e /dev/kvm ]] || die "/dev/kvm is missing. This PS5 Linux environment does not currently expose KVM."
[[ -x "$QEMU" ]] || die "QEMU not found at $QEMU. Build it with qemu/build-windows10.sh first."
[[ -f "$ISO" ]] || die "Windows installer ISO not found: $ISO. Set WIN10_ISO to your own Windows 10 ISO."

command -v "$HOME/qemu-windows10/build/qemu-img" >/dev/null 2>&1 ||
  die "qemu-img not found at $HOME/qemu-windows10/build/qemu-img."

mkdir -p "$VM_DIR"
if [[ ! -f "$DISK" ]]; then
  echo "Creating a new 64 GiB Windows 10 virtual disk at: $DISK"
  "$HOME/qemu-windows10/build/qemu-img" create -f qcow2 "$DISK" 64G
fi

# First milestone: legacy BIOS and broadly supported emulated devices.
# This prioritizes reliable installation over accelerated 3D graphics.
exec "$QEMU" \
  -machine pc,accel=kvm \
  -cpu host \
  -m "$RAM" \
  -smp "$CPUS",sockets=1,cores="$CPUS" \
  -drive file="$DISK",if=ide,format=qcow2,cache=writeback \
  -drive file="$ISO",media=cdrom,if=ide,readonly=on \
  -boot menu=on,order=d \
  -vga std \
  -display sdl \
  -device usb-ehci,id=ehci \
  -device usb-kbd,bus=ehci.0 \
  -device usb-mouse,bus=ehci.0 \
  -netdev user,id=net0 \
  -device e1000,netdev=net0 \
  -audiodev pa,id=snd0 \
  -device intel-hda \
  -device hda-duplex,audiodev=snd0 \
  -rtc base=localtime,clock=host \
  -monitor tcp:127.0.0.1:4446,server,nowait \
  -name "Windows 10 (PS5)"
