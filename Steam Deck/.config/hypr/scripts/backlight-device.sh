#!/bin/bash
# Point the brightness slider in the notification center (swaync) at this
# Deck's backlight. Its name (amdgpu_bl0 or amdgpu_bl1) can differ between
# kernels, so it's checked at every login, right before swaync starts.

CONFIG="$HOME/.config/swaync/config.json"

for bl in /sys/class/backlight/amdgpu_bl*; do
    [ -e "$bl" ] || continue
    name="${bl##*/}"
    grep -q "\"device\": \"$name\"" "$CONFIG" && exit 0
    sed -i "s/\"device\": \"amdgpu_bl[0-9]*\"/\"device\": \"$name\"/" "$CONFIG"
    exit 0
done
