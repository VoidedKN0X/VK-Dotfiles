#!/bin/bash
# Screenshot of both monitors as one image (replaces flameshot; Print):
#   saved to ~/Pictures/Screenshots/Screenshot_<date>_<time>.png
#   copied to the clipboard (so it's in the clipboard history too)
#   a white flash on the screens (Quickshell), then a notification with the
#   picture: Open shows it, Show in folder opens Thunar there

DIR="$HOME/Pictures/Screenshots"
FILE="$DIR/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
mkdir -p "$DIR"

# grim without -o takes every monitor, laid out as Hyprland places them
if ! grim "$FILE"; then
    notify-send -u critical -a Screenshot "Screenshot failed" "grim couldn't capture the screen"
    exit 1
fi

wl-copy --type image/png <"$FILE"
qs ipc call screenshot flash >/dev/null 2>&1

# the notification waits for a click on its buttons: in the background, so
# the key is free again at once
(
    action=$(notify-send -a Screenshot -i "$FILE" \
        -A open="Open" -A folder="Show in folder" \
        "Screenshot saved" "$(basename "$FILE") · copied to the clipboard")
    case "$action" in
        open) xdg-open "$FILE" ;;
        folder) thunar "$DIR" ;;
    esac
) >/dev/null 2>&1 &
disown
