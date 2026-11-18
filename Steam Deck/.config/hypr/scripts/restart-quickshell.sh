#!/bin/bash
# Restart the bar, control center and notifications (Quickshell, Super + R).
# A normal SIGTERM lets it clean up (tray icons, layer surfaces) and stop its
# own helpers (cava, stats.sh); then wait for the old process to exit before
# starting a new one, so two bars never run at once.

pkill -x qs
pkill -x quickshell

for _ in $(seq 20); do
    pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null || break
    sleep 0.1
done
# Still alive after 2s: force it
pkill -9 -x qs
pkill -9 -x quickshell

qs >/dev/null 2>&1 &
disown -a
