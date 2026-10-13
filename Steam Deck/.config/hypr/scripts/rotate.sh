#!/bin/bash
# Switch the built-in screen between landscape and portrait, turning its
# touchscreen and the touch gestures with it (the rotate button in the
# notification center). The choice is saved, so it survives reloads and
# reboots. Hyprland transforms: 3 = landscape, 0 = portrait.

STATE="$HOME/.local/state/hypr/rotation"

if [ "$(cat "$STATE" 2>/dev/null)" = 0 ]; then
    new=3 name="Landscape"
else
    new=0 name="Portrait"
fi

mkdir -p "$(dirname "$STATE")"
echo "$new" > "$STATE"

hyprctl eval "hl.monitor({ output = 'eDP-1', mode = '800x1280@60', position = '0x0', scale = 1, transform = $new })
hl.config({ input = { touchdevice = { transform = $new } } })" >/dev/null

# restart the gesture daemon and the app menu so they pick up the new rotation
setsid -f "$HOME/.config/hypr/scripts/touch-gestures.sh" >/dev/null 2>&1
"$HOME/.config/hypr/scripts/app-drawer.sh" start

notify-send -t 1500 -i display "Rotation" "$name"
