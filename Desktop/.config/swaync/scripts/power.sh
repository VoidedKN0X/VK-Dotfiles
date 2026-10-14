#!/bin/bash
# Reboot or shut down after a confirmation (the power buttons in the
# notification center), so one accidental tap does nothing. The question is a
# notification with Confirm/Cancel buttons, which works with a mouse and on a
# touchscreen.
#   power.sh reboot | poweroff
# Every decision is logged: journalctl -t power.sh

case "$1" in
    reboot)   label="Reboot" ;;
    poweroff) label="Shut down" ;;
    *) echo "usage: power.sh reboot|poweroff" >&2; exit 1 ;;
esac

log() { logger -t power.sh "$*"; }

# close the notification center, so the question is visible
swaync-client -cp >/dev/null 2>&1

# notify-send waits for a button and prints its key; dismissing it prints nothing
start=$(date +%s%N)
choice=$(notify-send -a "Power" -i system-shutdown -u critical \
    -A "confirm=$label" -A "cancel=Cancel" \
    "$label?" "Press $label to confirm.")
rc=$?
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
log "$1: notify-send exit=$rc answer='${choice}' after ${elapsed_ms} ms"

# Only a press on the confirm button counts. An answer within half a second
# can't be a person reading the question (e.g. the same tap landing on it), so
# it's ignored.
if [ "$choice" = "confirm" ] && [ "$elapsed_ms" -ge 500 ]; then
    log "$1: confirmed"
    systemctl "$1"
else
    log "$1: not confirmed - nothing done"
fi
