#!/bin/bash
# Restart waybar and swaync. A normal SIGTERM lets them clean up (tray icons,
# layer surfaces); then wait for the old processes to exit before starting new
# ones, so two bars never run at once.

killall -q waybar swaync

for _ in $(seq 20); do
    pgrep -x waybar >/dev/null || pgrep -x swaync >/dev/null || break
    sleep 0.1
done
# Still alive after 2s: force it
killall -q -9 waybar swaync

waybar >/dev/null 2>&1 &
swaync >/dev/null 2>&1 &
disown -a
