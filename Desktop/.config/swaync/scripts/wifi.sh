#!/bin/bash

status=$(nmcli radio wifi)
if [ "$status" = "enabled" ]; then
    nmcli radio wifi off && notify-send -i notification-network-wireless-disconnected "Wireless" "Wireless disabled"
else
    nmcli radio wifi on && notify-send -i notification-network-wireless "Wireless" "Wireless enabled"
fi
exit 0
