#!/bin/bash
# Power menu for the bar's power button. Reboot and shut down go through the
# notification center's power.sh, which asks for confirmation first.

choice=$(printf '%s\n' "󰌾  Lock" "󰤄  Suspend" "󰍃  Log out" "󰜉  Reboot" "󰐥  Shut down" |
    rofi -dmenu -i -no-custom -p "Power")

case "$choice" in
    *Lock) hyprlock ;;
    *Suspend) systemctl suspend ;;
    # same as Super + M
    *"Log out") command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()' ;;
    *Reboot) ~/.config/swaync/scripts/power.sh reboot ;;
    *"Shut down") ~/.config/swaync/scripts/power.sh poweroff ;;
esac
