#!/bin/bash
# xppeek.sh mount|umount : read-only view of the running XP's C: drive at /mnt/xpc (qcow2 -> FUSE raw -> loop -> ntfs3 ro).
# Reads only; the image is opened read-only without locking, so a live XP may show slightly stale files.
set -e
case "$1" in
mount)
  touch /tmp/xpraw
  qemu-storage-daemon --daemonize --pidfile /tmp/xpqsd.pid \
    --blockdev driver=file,node-name=f,filename=${XPDIR:-$HOME/xp}/xp.qcow2,read-only=on,locking=off \
    --blockdev driver=qcow2,node-name=q,file=f,read-only=on \
    --export type=fuse,id=e,node-name=q,mountpoint=/tmp/xpraw,writable=off
  L=$(losetup -r -f -P --show /tmp/xpraw); echo "$L" > /tmp/xploop
  mkdir -p /mnt/xpc; sleep 1
  mount -t ntfs3 -o ro "${L}p1" /mnt/xpc && echo "mounted ${L}p1 at /mnt/xpc (read-only)" ;;
umount)
  umount /mnt/xpc 2>/dev/null || true
  [ -f /tmp/xploop ] && losetup -d "$(cat /tmp/xploop)" 2>/dev/null || true
  [ -f /tmp/xpqsd.pid ] && kill "$(cat /tmp/xpqsd.pid)" 2>/dev/null || true
  rm -f /tmp/xploop; echo unmounted ;;
esac
