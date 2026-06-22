#!/bin/bash

LAST_WALLPAPER="$HOME/.config/hypr/colors/current-wallpaper.conf"
if [ -f "$LAST_WALLPAPER" ]; then
    WALLPAPER=$(sed 's/^\$current_wallpaper = //' "$LAST_WALLPAPER")
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER=$(find ~/Pictures/Wallpapers -iregex '.*\.\(jpg\|jpeg\|png\|gif\)' -type f | head -n 1)
fi

if [ -z "$WALLPAPER" ]; then
    echo "No wallpapers found"
    exit 1
fi

awww img "$WALLPAPER"

# Generate and apply accent colors
wallust run "$WALLPAPER"

# Update hyprlock wallpaper path
mkdir -p "$(dirname "$LAST_WALLPAPER")"
echo "\$current_wallpaper = $WALLPAPER" > "$LAST_WALLPAPER"

# Reload swaync CSS
swaync-client --reload-css 2>/dev/null || true

# Reload waybar
killall -SIGUSR2 waybar 2>/dev/null || true
