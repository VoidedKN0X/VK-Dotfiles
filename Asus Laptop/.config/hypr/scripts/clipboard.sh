#!/bin/bash

items=$(cliphist list)
if [ -z "$items" ]; then
    exit 0
fi

selected=$(echo "$items" | rofi -dmenu -p "" -theme ~/.config/rofi/clipboard.rasi -display-columns 2 -kb-custom-1 "Ctrl+Delete")
exit_code=$?

if [ "$exit_code" = 10 ]; then
    [ -n "$selected" ] && echo "$selected" | cliphist delete
    exec "$0"
elif [ "$exit_code" = 0 ] && [ -n "$selected" ]; then
    echo "$selected" | cliphist decode | wl-copy
fi
