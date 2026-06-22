#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

if [ $# -eq 0 ]; then
    find "$WALLPAPER_DIR" -iregex '.*\.\(jpg\|jpeg\|png\|gif\)' -type f | sort | while IFS= read -r file; do
        name=$(basename "$file")
        printf "%s\0icon\x1f%s\n" "$name" "$file"
    done
else
    SELECTED="$1"
    WALLPAPER="$WALLPAPER_DIR/$SELECTED"

    if [ ! -f "$WALLPAPER" ]; then
        exit 1
    fi

    awww img "$WALLPAPER" >/dev/null 2>&1

    wallust run "$WALLPAPER" >/dev/null 2>&1

    swaync-client --reload-css >/dev/null 2>&1 || true

    killall -SIGUSR2 waybar >/dev/null 2>&1 || true

    exit 1
fi
