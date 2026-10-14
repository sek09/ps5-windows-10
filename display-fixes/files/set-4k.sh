#!/usr/bin/env bash
# Boot-time handling of the PS5 4K "pink screen" (v4, 2026-10-04).
#
# Two separate bugs:
#  1. Monitor re-announces after a 4K modeset / wake and the kernel bridge
#     driver never re-configures the DP->HDMI chip  -> "no signal".
#     Handled by the ps5_hdmi_fix kernel module (ps5-hdmi-fix.service).
#  2. The first 4K picture after boot is pink: the AMD display pipeline
#     reports an OTG underflow (amdgpu_dm_dtn_log). Only a detour through
#     another resolution clears it (output off/on and pipe-split off do not).
#     /etc/X11/xorg.conf.d/10-ps5-boot-1080p.conf makes X start at 1080p so
#     KScreen's own switch to the saved 4K layout is that detour.
# This script is the safety net: it waits for things to settle, makes sure we
# ended up at 4K, and runs the old proven detour only if underflow is still set.
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
LOG="$HOME/display-autoset.log"
DIAG="$HOME/display-diag"
DTN=/sys/kernel/debug/dri/0/amdgpu_dm_dtn_log

log() { echo "$(date '+%F %T') up=$(cut -d' ' -f1 /proc/uptime) $*" >> "$LOG"; }
underflow() { sudo -n cat $DTN 2>/dev/null | awk '/^OTG:/{getline; print $(NF-1); exit}'; }
curmode() { xrandr 2>/dev/null | awk '/\*/{print $1; exit}'; }
capture() {
    local out="$DIAG/$(date +%Y%m%d-%H%M%S)-$1"
    mkdir -p "$out"
    cut -d' ' -f1 /proc/uptime > "$out/uptime"
    sudo -n cat $DTN > "$out/dtn_log" 2>&1
    sudo -n dmesg > "$out/dmesg" 2>&1
}

log "login: mode=$(curmode) otg_underflow=$(underflow) module=$(lsmod | grep -c ps5_hdmi_fix)"
sleep 15
capture settled
M=$(curmode); U=$(underflow)
log "settled: mode=$M otg_underflow=$U"

if [ "$M" != "3840x2160" ]; then
    log "not at 4K yet -> switching to 4K"
    kscreen-doctor output.DisplayPort-0.mode.3840x2160@60 >> "$LOG" 2>&1
    sleep 12
    M=$(curmode); U=$(underflow)
    log "after 4K switch: mode=$M otg_underflow=$U"
fi
[ "$U" != "1" ] && { log "picture pipeline is clean, done"; exit 0; }

log "underflow set -> detour (1080p, 20 s, 4K)"
kscreen-doctor output.DisplayPort-0.mode.1920x1080@60 >> "$LOG" 2>&1
sleep 20
kscreen-doctor output.DisplayPort-0.mode.3840x2160@60 >> "$LOG" 2>&1
sleep 12
capture after-detour
log "after detour: mode=$(curmode) otg_underflow=$(underflow)"
