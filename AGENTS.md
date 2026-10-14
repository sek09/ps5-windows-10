# AGENTS.md — instructions for AI assistants

You are helping a user set up Windows XP on a PS5 with this repository. Follow these steps in order. After each
step, run the **check**; do not continue on failure, use the **if it fails** notes. Never download Windows, product
keys, games or any copyrighted binaries for the user, and never redistribute qemu-3dfx builds: build from source.
Read [docs/TECHNICAL.md](docs/TECHNICAL.md) for the why behind each step.

## Assumptions (verify, ask the user if not true)

- PS5 runs PS5 Linux (loader v2.5, CachyOS-based image) and the user can open a terminal or SSH into it.
  Check: `uname -r` (tested 7.1.7), `ls /dev/kvm` exists, `grep -c svm /proc/cpuinfo` > 0.
- Desktop user is `steam` with sudo (adjust `XPDIR`/`HOME_DIR` in `ps5-session` otherwise).
- The user has their own **Windows XP Professional SP3 32-bit (x86)** ISO and key. **x64 is not supported**
  (the build is `qemu-system-i386` only; x64 XP lacks drivers and the 32-bit 3D wrappers).
- The boot partition is mounted at `/boot/efi` and contains `cmdline.txt`.

## 1. Clone
```
git clone https://github.com/v0ltfault/ps5-windows-xp.git ~/ps5-windows-xp
```
Check: `ls ~/ps5-windows-xp/qemu/build.sh`.

## 2. Build QEMU
```
bash ~/ps5-windows-xp/qemu/build.sh
```
Check: `~/qemu-3dfx/build/qemu-system-i386 --version` prints `QEMU emulator version 9.2.2`.
If it fails: re-run (downloads); on `patch ... FAILED` remove `~/qemu-3dfx/qemu-9.2.2` and re-run; missing packages
→ `sudo pacman -S --needed <pkg>`.

## 3. VM folder
```
mkdir -p ~/xp/floppy && cp ~/ps5-windows-xp/linux/xp/* ~/xp/ && chmod +x ~/xp/*.sh
```
User copies their ISO to `~/xp/xp.iso`. Check: `file ~/xp/xp.iso` → ISO 9660 / UDF; the volume label usually
contains `XP` and `PRO`. If the ISO is x64 (label contains `X64`/`AMD64`) stop and tell the user.

## 4. Answer file
```
cp ~/ps5-windows-xp/guest/winnt.sif.template ~/xp/floppy/winnt.sif
```
Ask the user for their key and set `ProductKey=` (never write the key anywhere else, never log it).
Check: `grep -c 'XXXXX' ~/xp/floppy/winnt.sif` → `0`.

## 5. Disk
```
~/qemu-3dfx/build/qemu-img create -f qcow2 ~/xp/xp.qcow2 40G
```

## 6. Install XP (graphical session required: run from Konsole on the PS5, DISPLAY=:0)
```
~/xp/xp.sh install
```
Unattended; ~20–30 min, several reboots. Done when the XP desktop shows; the user shuts down from the Start menu.
Check: `~/qemu-3dfx/build/qemu-img info ~/xp/xp.qcow2` → disk size ≥ 1.5 GiB.
If "No bootable device": wrong ISO path/name. If setup asks for the key: floppy/winnt.sif missing or malformed.

## 7. Guest tools
- Build wrappers + bright.exe with this repo's GitHub Actions (`build-wrappers`, `build-bright`) on the user's fork.
- User downloads: VMware SVGA II driver **11.9.1** (Windows 2000/XP), WineD3D **1.7.52** for XP (fdossena.com),
  Supermium 32-bit (win32ss/supermium releases).
- Assemble `TOOLS/` = `3DFX/` (wrappers), `SVGA/`, `WINED3D/`, `SUPERMIUM/`, `BRIGHT/` (bright.exe + guest/bright/INSTALL.CMD),
  plus `guest/*.CMD *.REG *.JS`; then `xorriso -as mkisofs -J -R -o ~/xp/tools.iso TOOLS`.
- Start XP in a window: `~/xp/xp.sh`. In XP: install the SVGA driver from Device Manager; run `RES.CMD`,
  `INST3D.CMD`, `TWEAKS.REG`, `FIXD3D.CMD`, `BRIGHT\INSTALL.CMD`; Supermium shortcut target gets ` --no-sandbox`.
- **Always shut XP down; never use Restart** (crashes QEMU; xp.sh restarts it in kiosk/desktop mode).
Check: XP at 1920×1080 32-bit; `~/xp/serial.txt` contains `INST3DDONE`.

## 8. Tile boot
```
cd ~/ps5-windows-xp/linux/system
sudo install -m755 ps5-session /usr/local/bin/ps5-session
sudo cp -r ps5-xp.conf.d /etc/X11/
sudo cp 70-xp-playstation-pads.rules /etc/udev/rules.d/ && sudo udevadm control --reload
sudo cp plasma-autostart.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable plasma-autostart.service
sudo sh -c 'tr -d "\n" < /boot/efi/cmdline.txt; echo " ps5vm=xp"' | sudo tee /boot/efi/cmdl-xp.txt
```
Before enabling `plasma-autostart.service`, check how the image currently starts the desktop
(`systemctl list-unit-files | grep -E "sddm|plasma|getty"`). If a display manager/autologin exists, do not add a
second session starter; make the existing one run `/usr/local/bin/ps5-session` instead. Back up every file you replace.
Check: `cat /boot/efi/cmdl-xp.txt` ends with `ps5vm=xp`.
Dry run without the tile: `echo xp > ~/.ps5vm; touch ~/xp/NOPOWEROFF; sudo systemctl restart plasma-autostart.service`
→ XP starts full screen. Afterwards `rm ~/.ps5vm ~/xp/NOPOWEROFF`.

On a PC: `python tile/patch_loader.py ps5-linux-loader.elf loader-xp.elf` (expects `patched offset 0x18708` for v2.5).
Fork itsPLK/ps5-webkit-autoloader, `git apply tile/ps5-webkit-autoloader-tiles.patch`, copy loader-xp.elf to
`tiles/xp/loader.elf`, `git add -f tiles/xp/loader.elf`, push, run **Actions → Build tile installer** (tile `xp`),
send `tile-xp-installer.elf` from Payload Manager in normal PS5 mode, choose relapse, reboot.
Check: a "Windows XP" tile exists; pressing it boots to XP; shutting XP down powers the PS5 off.

## Rules
- Keep the QEMU monitor bound to 127.0.0.1 (it can execute host commands).
- Never change the display to 120 Hz on the PS5 link; never range-scan GPU registers (`amdgpu_regs`) — it froze a console.
- For PS5 Linux picture problems use [display-fixes/README.md](display-fixes/README.md); nothing there is required.
