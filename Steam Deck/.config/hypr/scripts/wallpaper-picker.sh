#!/bin/bash
# rofi script mode: with no argument, list wallpapers; with one, apply it.

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

if [ $# -eq 0 ]; then
    # Show the path relative to WALLPAPER_DIR so files in subfolders still resolve
    find "$WALLPAPER_DIR" -iregex '.*\.\(jpg\|jpeg\|png\|gif\)' -type f | sort | while IFS= read -r file; do
        printf "%s\0icon\x1f%s\n" "${file#"$WALLPAPER_DIR"/}" "$file"
    done
else
    WALLPAPER="$WALLPAPER_DIR/$1"
    [ -f "$WALLPAPER" ] || exit 1

    # Same steps as at login, kept in one place
    "$HOME/.config/hypr/scripts/wallpaper.sh" "$WALLPAPER" >/dev/null 2>&1
    exit 0
fi
