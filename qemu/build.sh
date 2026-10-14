#!/bin/bash
# Build the QEMU used by this project ON THE PS5 (PS5 Linux, CachyOS/Arch based):
#   QEMU 9.2.2 + kjliew/qemu-3dfx (3D pass-through, commit 920661f) + the 4 patches in ./patches
# Result: ~/qemu-3dfx/build/qemu-system-i386  (the path xp.sh uses by default)
# Takes ~15-25 minutes on the PS5. Needs ~3 GB free space and an internet connection.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
QEMU_VER=9.2.2
Q3DFX_COMMIT=920661f
DEST=${DEST:-$HOME/qemu-3dfx}

echo "== 1/5 build tools and libraries (asks for your password)"
sudo pacman -S --needed --noconfirm base-devel git python ninja meson pkgconf glib2 pixman sdl2 libepoxy mesa gtk3 \
  libpulse rsync wget

echo "== 2/5 qemu-3dfx source + QEMU $QEMU_VER"
[ -d "$DEST/.git" ] || git clone https://github.com/kjliew/qemu-3dfx.git "$DEST"
cd "$DEST"
git checkout -q "$Q3DFX_COMMIT"
[ -f qemu-$QEMU_VER.tar.xz ] || wget -q https://download.qemu.org/qemu-$QEMU_VER.tar.xz
rm -rf qemu-$QEMU_VER && tar xf qemu-$QEMU_VER.tar.xz

echo "== 3/5 apply qemu-3dfx, then this project's patches"
cd qemu-$QEMU_VER
rsync -r ../qemu-0/hw/3dfx ../qemu-1/hw/mesa ./hw/
patch -p0 -i ../00-qemu92x-mesa-glide.patch
bash ../scripts/sign_commit
for p in "$HERE"/patches/*.patch; do echo "   $(basename "$p")"; patch -p1 -i "$p"; done

echo "== 4/5 configure"
mkdir -p ../build && cd ../build
../qemu-$QEMU_VER/configure --target-list=i386-softmmu --enable-kvm --enable-sdl --enable-opengl --enable-gtk \
  --disable-werror --disable-docs

echo "== 5/5 compile"
make -j"$(nproc)"
./qemu-system-i386 --version | head -1
echo "DONE: $DEST/build/qemu-system-i386"
