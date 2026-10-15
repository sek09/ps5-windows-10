# Windows 10 on PS5: first milestone

This port is being developed alongside the original Windows XP configuration. The XP launcher and XP-specific QEMU build remain unchanged.

## Current scope

The first milestone is a basic 64-bit Windows 10 VM under QEMU/KVM on **PS5 Linux**. It uses standard emulated PC hardware and does not assume the XP-only qemu-3dfx graphics patches work with Windows 10.

## Requirements

- A PS5 that already boots a compatible PS5 Linux image.
- `/dev/kvm` available in that Linux environment.
- A legally obtained Windows 10 ISO and an appropriate license.
- Keyboard and mouse connected to the PS5.
- Enough free storage for QEMU build files and a 64 GiB virtual disk.

WSL2 on the PC is useful for editing the repository, but it is **not** the runtime environment for the PS5 VM. Build this QEMU version on the PS5 Linux environment so its KVM support matches the PS5 kernel.

## Build QEMU for 64-bit guests

On the PS5 Linux desktop, open a terminal and run:

```bash
git clone -b windows-10-port https://github.com/sek09/ps5-windows-10.git ~/ps5-windows-10
cd ~/ps5-windows-10
bash qemu/build-windows10.sh
```

This creates a separate build at `~/qemu-windows10/build`; it does not overwrite the XP build at `~/qemu-3dfx`.

## Prepare the installer ISO

Copy your own Windows 10 ISO to:

```
~/windows10/Win10.iso
```

Or set `WIN10_ISO=/path/to/your.iso` when launching.

## Launch the installer

```bash
mkdir -p ~/windows10
bash ~/ps5-windows-10/linux/windows10/windows10.sh
```

On first launch, the script creates `~/windows10/windows10.qcow2` as a 64 GiB virtual disk. It boots from the ISO first; after installation, remove the ISO from the VM configuration or change the boot order to boot from disk.

## Known limitations

- This is an initial compatibility configuration, not a tested or performance-tuned Windows 10 port.
- Standard VGA is used initially; accelerated 3D graphics are not implemented.
- UEFI, VirtIO drivers, GPU passthrough, and a PS5 home-screen tile are later milestones.
- Audio depends on a working PulseAudio-compatible server in the PS5 Linux desktop session.
- Do not run this on the PS5 until PS5 Linux and `/dev/kvm` are confirmed working.
