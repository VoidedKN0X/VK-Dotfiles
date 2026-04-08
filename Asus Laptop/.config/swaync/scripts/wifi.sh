#!/bin/bash

status=$(nmcli r wifi)
if [ $status = "enabled" ]
then
    notify-send -i notification-network-wireless-disconnected "Wireless" "Wireless disabled"
    nmcli r wifi off
else
    notify-send -i notification-network-wireless "Wireless" "Wireless enabled"
    nmcli r wifi on
fi
exit 0