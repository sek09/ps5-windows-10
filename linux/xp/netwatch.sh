#!/bin/bash
# netwatch.sh: log every remote endpoint the XP guest talks to. With QEMU user networking (slirp) each guest
# connection becomes a socket of the QEMU process on this host, so it is visible here and cannot be hidden by the guest.
LOG=${XPDIR:-$HOME/xp}/netwatch.log
declare -A seen
echo "$(date '+%F %T') netwatch started" >> "$LOG"
while true; do
  PID=$(pgrep -x qemu-system-i38 | head -1)
  if [ -n "$PID" ]; then
    ss -Htunp 2>/dev/null | grep "pid=$PID," | awk '{print $1, $6}' | while read -r proto peer; do
      case "$peer" in 127.0.0.1:*|0.0.0.0:*|\*:*|"[::]"*) continue ;; esac
      echo "$proto $peer"
    done | sort -u > /tmp/netwatch.now
    while read -r line; do
      [ -z "$line" ] && continue
      if [ -z "${seen[$line]}" ]; then
        seen[$line]=1
        port=${line##*:}
        tag=""; case "$port" in 80|443|53|123) ;; *) tag="  <-- unusual port" ;; esac
        echo "$(date '+%F %T') $line$tag" >> "$LOG"
      fi
    done < /tmp/netwatch.now
  fi
  sleep 1
done
