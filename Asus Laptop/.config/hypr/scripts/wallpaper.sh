#!/bin/bash
# Apply a wallpaper and regenerate the wallust colors.
#   wallpaper.sh           -> re-apply the last wallpaper (used at login)
#   wallpaper.sh <file>    -> apply <file> (used by wallpaper-picker.sh)

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
LAST_WALLPAPER="$HOME/.config/hypr/colors/current-wallpaper.conf"

WALLPAPER="${1:-}"
if [ -z "$WALLPAPER" ] && [ -f "$LAST_WALLPAPER" ]; then
    # shellcheck disable=SC2016  # the $ is literal text in that file
    WALLPAPER=$(sed 's/^\$current_wallpaper = //' "$LAST_WALLPAPER")
fi

# At login the colors made from the saved wallpaper are already in place, so
# only the wallpaper itself is shown (no wallust run, no bar/OSD restarts).
# The colors are made again if the saved wallpaper is gone, or if a wallust
# template or wallust.toml changed since (e.g. after Install.sh copied new ones).
RESTORE_ONLY=0
if [ -z "${1:-}" ] && [ -f "$WALLPAPER" ] &&
    [ -z "$(find "$HOME/.config/wallust" -type f -newer "$LAST_WALLPAPER" 2>/dev/null)" ]; then
    RESTORE_ONLY=1
fi

# Fall back to the first wallpaper (sorted, so it's the same one every time)
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER=$(find "$WALLPAPER_DIR" -iregex '.*\.\(jpg\|jpeg\|png\|gif\)' -type f 2>/dev/null | sort | head -n 1)
fi

if [ -z "$WALLPAPER" ]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

# At login this runs at the same time as awww-daemon: wait (max ~5s) until the
# daemon answers, otherwise `awww img` fails and no wallpaper is set.
for _ in $(seq 50); do
    awww query >/dev/null 2>&1 && break
    sleep 0.1
done

awww img "$WALLPAPER"
[ "$RESTORE_ONLY" = 1 ] && exit 0

# Generate and apply accent colors
wallust run "$WALLPAPER"

# Update hyprlock wallpaper path
mkdir -p "$(dirname "$LAST_WALLPAPER")"
echo "\$current_wallpaper = $WALLPAPER" > "$LAST_WALLPAPER"

# Reload swaync CSS
swaync-client --reload-css >/dev/null 2>&1 || true

# Reload waybar
killall -SIGUSR2 waybar >/dev/null 2>&1 || true

# The volume popup only reads its colors when it starts: stop it, the next
# volume key starts it again with the new ones
pkill -f 'waybar/scripts/osd.py' >/dev/null 2>&1 || true
