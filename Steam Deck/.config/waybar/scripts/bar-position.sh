#!/bin/bash
# Move the bar between the top and the left edge of the screen, so on an OLED
# the bar doesn't sit in the same place all the time. The notification panel,
# notification popups, the calendar and the volume popup move with it:
#   top:  notifications top right, under the bell button; calendar and volume
#         popup under the clock
#   left: notifications bottom left, next to the bell button; calendar next to
#         the clock, volume popup at the bottom
#
#   bar-position.sh                      switch to the other position (Super + B)
#   bar-position.sh top|left             use that position
#   bar-position.sh --files-only [pos]   only rewrite the config files, don't
#                                        restart anything (used by Install.sh)

WB="$HOME/.config/waybar"
CURRENT="$WB/layouts/current.jsonc"
SWAYNC="$HOME/.config/swaync/config.json"
SWAYNC_POS="$HOME/.config/swaync/position.css"

files_only=0
if [ "${1:-}" = "--files-only" ]; then
    files_only=1
    shift
fi

now=$(grep -o 'layouts/[a-z]*\.jsonc' "$CURRENT" 2>/dev/null | head -n 1 | sed 's#layouts/##; s#\.jsonc##')
[ "$now" = left ] || now=top

case "${1:-}" in
    top | left) pos=$1 ;;
    "")
        if [ "$files_only" = 1 ]; then
            pos=$now
        elif [ "$now" = top ]; then
            pos=left
        else
            pos=top
        fi
        ;;
    *)
        echo "usage: bar-position.sh [--files-only] [top|left]" >&2
        exit 1
        ;;
esac

printf '%s\n%s\n' \
    '// Written by scripts/bar-position.sh: the bar position in use (top or left)' \
    "{ \"include\": [\"~/.config/waybar/layouts/$pos.jsonc\"] }" >"$CURRENT"

# Notification panel (control center) and popups. The panel's margins are
# counted from the screen edge after the bar's space; right/bottom skip the
# power button so the panel lines up with the bell.
if [ "$pos" = top ]; then
    x=right y=top mt=6 mb=8 ml=0 mr=46
    popup_margin="0 46px 0 0"
else
    x=left y=bottom mt=8 mb=46 ml=6 mr=0
    popup_margin="0 0 46px 0"
fi

sed -i -E \
    -e "s/(\"positionX\": *)\"[a-z]+\"/\1\"$x\"/" \
    -e "s/(\"positionY\": *)\"[a-z]+\"/\1\"$y\"/" \
    -e "s/(\"control-center-margin-top\": *)[0-9]+/\1$mt/" \
    -e "s/(\"control-center-margin-bottom\": *)[0-9]+/\1$mb/" \
    -e "s/(\"control-center-margin-left\": *)[0-9]+/\1$ml/" \
    -e "s/(\"control-center-margin-right\": *)[0-9]+/\1$mr/" \
    "$SWAYNC"

# popups have no margin setting in config.json; style.css imports this file
printf '%s\n%s\n' \
    '/* Written by waybar/scripts/bar-position.sh: popups next to the bell button */' \
    ".floating-notifications > scrolledwindow { margin: $popup_margin; }" >"$SWAYNC_POS"

[ "$files_only" = 1 ] && exit 0

# restarts waybar and swaync (swaync reads config.json when it starts)
~/.config/hypr/scripts/restart-waybar-swaync.sh

# The calendar and volume popups (calendar.py, osd.py) read the position
# themselves each time they open
