#!/bin/bash

WALLPAPER=$(find ~/Pictures/Wallpapers -iregex '.*\.\(jpg\|jpeg\|png\|gif\)' -type f | shuf -n 1)

if [ -z "$WALLPAPER" ]; then
    echo "No wallpapers found"
    exit 1
fi

awww img "$WALLPAPER"

# Generate and apply accent colors
wallust run "$WALLPAPER"

# Reload swaync CSS
swaync-client --reload-css 2>/dev/null || true

# Reload waybar
killall -SIGUSR2 waybar 2>/dev/null || true
