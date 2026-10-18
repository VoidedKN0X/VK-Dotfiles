#!/bin/bash
# Battery icon + percentage for the hyprlock screen (bottom left).
# Prints nothing if there is no battery.
for bat in /sys/class/power_supply/BAT*; do
    [ -r "$bat/capacity" ] && break
done
cap=$(cat "$bat/capacity" 2>/dev/null) || exit 0
status=$(cat "$bat/status" 2>/dev/null)

case "$status" in
    Charging|Full) icon="󰂄" ;;
    *)
        icons=(󰂎 󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
        icon="${icons[$(( (cap + 5) / 10 ))]}"
        ;;
esac

echo "$icon  $cap%"
