#!/bin/bash
# Reboot or shut down after a confirmation (the power buttons in the
# notification center), so one accidental tap does nothing. The question is a
# notification with a button, which works with a mouse and on a touchscreen.
#   power.sh reboot | poweroff

case "$1" in
    reboot)   label="Reboot" ;;
    poweroff) label="Shut down" ;;
    *) echo "usage: power.sh reboot|poweroff" >&2; exit 1 ;;
esac

# close the notification center, so the question is visible
swaync-client -cp >/dev/null 2>&1

# notify-send waits for a button and prints its key; dismissing it prints nothing
choice=$(notify-send -a "Power" -i system-shutdown -u critical -A "$1=$label" \
    "$label?" "Press $label to confirm, or dismiss this to cancel.")
[ "$choice" = "$1" ] && systemctl "$1"
