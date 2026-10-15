#!/usr/bin/env bash
# Build a separate, standard QEMU for 64-bit guests on PS5 Linux.
# Unlike qemu/build.sh, this does not apply the XP/qemu-3dfx patches.
set -euo pipefail

QEMU_VER=9.2.2
DEST="${DEST:-$HOME/qemu-windows10}"
JOBS="${JOBS:-$(nproc)}"

echo "== Install build dependencies (CachyOS/Arch-based PS5 Linux)"
sudo pacman -S --needed --noconfirm base-devel git python ninja meson pkgconf glib2 pixman sdl2 gtk3 libpulse wget

mkdir -p "$DEST"
cd "$DEST"

if [[ ! -f "qemu-$QEMU_VER.tar.xz" ]]; then
  wget "https://download.qemu.org/qemu-$QEMU_VER.tar.xz"
fi

if [[ ! -d "qemu-$QEMU_VER" ]]; then
  tar xf "qemu-$QEMU_VER.tar.xz"
fi

mkdir -p build
cd build

if [[ ! -f config-host.mak ]]; then
  ../qemu-"$QEMU_VER"/configure \
    --target-list=x86_64-softmmu \
    --enable-kvm \
    --enable-sdl \
    --enable-gtk \
    --disable-werror \
    --disable-docs
fi

make -j"$JOBS"

echo
./qemu-system-x86_64 --version | head -n 1
./qemu-img --version | head -n 1
echo "Build complete: $DEST/build/qemu-system-x86_64"
