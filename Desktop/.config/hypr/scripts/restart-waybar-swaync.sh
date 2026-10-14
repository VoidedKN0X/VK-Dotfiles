#!/bin/bash
# Restart waybar and swaync. waybar: a normal SIGTERM lets it clean up (tray
# icons, layer surfaces); then wait for the old process to exit before starting
# a new one, so two bars never run at once. swaync runs as a systemd user
# service (swaync.service), so D-Bus activation and this script never start a
# second copy.

killall -q waybar

for _ in $(seq 20); do
    pgrep -x waybar >/dev/null || break
    sleep 0.1
done
# Still alive after 2s: force it
killall -q -9 waybar

# a swaync started outside systemd (older login) would block the service
pkill -x -f '^swaync$' && sleep 0.5
systemctl --user restart swaync

waybar >/dev/null 2>&1 &
disown -a
