#!/bin/bash
# Apply a wallpaper and regenerate the wallust colors. Quickshell shows the
# wallpaper named in hypr/colors/current-wallpaper.conf (quickshell/background),
# so writing that file is what changes it on screen.
#   wallpaper.sh           -> re-apply the last wallpaper (used at login)
#   wallpaper.sh <file>    -> apply <file> (used by the wallpaper picker)

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
LAST_WALLPAPER="$HOME/.config/hypr/colors/current-wallpaper.conf"

WALLPAPER="${1:-}"
if [ -z "$WALLPAPER" ] && [ -f "$LAST_WALLPAPER" ]; then
    # shellcheck disable=SC2016  # the $ is literal text in that file
    WALLPAPER=$(sed 's/^\$current_wallpaper = //' "$LAST_WALLPAPER")
fi

# At login the wallpaper and the colors made from it are already in place
# (Quickshell shows the saved one by itself): nothing to do.
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

[ "$RESTORE_ONLY" = 1 ] && exit 0

# Show it: Quickshell watches this file (the lock screen reads it too). Written
# before wallust runs, so the wallpaper changes at once and the colors follow.
mkdir -p "$(dirname "$LAST_WALLPAPER")"
echo "\$current_wallpaper = $WALLPAPER" > "$LAST_WALLPAPER"

# Generate and apply accent colors
wallust run "$WALLPAPER"

# Nothing to reload: Quickshell watches quickshell/colors.json (written by
# wallust above) and recolors the bar and its popups by itself
