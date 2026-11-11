#!/bin/sh
# System info for the bar and the control center, one block every 2 seconds
# (the interval of the Waybar cpu, temperature and memory modules):
#   host <hostname>          (once, at the start)
#   cpu <busy> <total>       jiffies since boot, from /proc/stat
#   mem <total kB> <available kB>
#   temp <millidegrees>      CPU (k10temp Tctl), if the sensor exists
#   uptime <seconds>
#   end
# Read by services/SystemStats.qml. One long-running process instead of a new
# one for every value.

# The CPU sensor: k10temp, the same one the Waybar config and btop use
# (btop/btop.conf: k10temp/Tctl). Its hwmonN number changes between boots,
# the PCI path doesn't.
TEMP_GLOB='/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon*/temp1_input'

echo "host $(cat /proc/sys/kernel/hostname)"

while :; do
    # cpu  user nice system idle iowait irq softirq steal ...
    read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
    busy=$((user + nice + system + irq + softirq + steal))
    echo "cpu $busy $((busy + idle + iowait))"

    total=0 available=0
    while read -r key value _; do
        case "$key" in
            MemTotal:) total=$value ;;
            MemAvailable:) available=$value ;;
        esac
    done </proc/meminfo
    echo "mem $total $available"

    for sensor in $TEMP_GLOB; do
        [ -r "$sensor" ] && echo "temp $(cat "$sensor")"
        break
    done

    read -r up _ </proc/uptime
    echo "uptime ${up%.*}"
    echo end
    sleep 2
done
