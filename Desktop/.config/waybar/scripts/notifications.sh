#!/bin/bash
# The bell button and Super + N: open or close the notification panel next to
# the bell of the bar on the focused monitor. swaync has one position for all
# monitors, so when the focused monitor's bar sits on another edge (on the
# desktop, DP-2's bar is always on the right) the panel is pointed there
# first; swaync reads its position each time the panel opens.

SWAYNC="$HOME/.config/swaync/config.json"
pos=$(python3 "$HOME/.config/waybar/scripts/popup_common.py" 2>/dev/null)

# where the panel points now (from swaync's config)
x=$(grep -o '"positionX": *"[a-z]*"' "$SWAYNC" | grep -o '[a-z]*"$' | tr -d '"')
y=$(grep -o '"positionY": *"[a-z]*"' "$SWAYNC" | grep -o '[a-z]*"$' | tr -d '"')
case "$x/$y" in
    right/top) now=top ;;
    left/bottom) now=left ;;
    right/bottom) now=right ;;
    *) now="" ;;
esac

if [ -n "$pos" ] && [ "$pos" != "$now" ]; then
    "$HOME/.config/waybar/scripts/bar-position.sh" --swaync-only "$pos"
    swaync-client -R >/dev/null 2>&1
    swaync-client -rs >/dev/null 2>&1
fi
exec swaync-client -t -sw
