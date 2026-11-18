#!/bin/sh
# System info for the bar and the control center, one block every 2 seconds
# (the interval of the Waybar cpu, temperature and memory modules):
#   host <hostname>          (once, at the start)
#   cpu <busy> <total>       jiffies since boot, from /proc/stat
#   mem <total kB> <available kB>
#   temp <millidegrees>      CPU, if a CPU sensor exists
#   uptime <seconds>
#   end
# Read by services/SystemStats.qml. One long-running process instead of a new
# one for every value.

# The CPU sensor, found by its driver's name (hwmonN numbers change between
# boots): k10temp or zenpower (AMD, temp1 = Tctl, like btop's k10temp/Tctl),
# coretemp (Intel, temp1 = the package). None: no temperature.
TEMP_FILE=
for dir in /sys/class/hwmon/hwmon*; do
    case "$(cat "$dir/name" 2>/dev/null)" in
        k10temp | zenpower | coretemp)
            TEMP_FILE="$dir/temp1_input"
            break
            ;;
    esac
done

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

    [ -n "$TEMP_FILE" ] && [ -r "$TEMP_FILE" ] && echo "temp $(cat "$TEMP_FILE")"

    read -r up _ </proc/uptime
    echo "uptime ${up%.*}"
    echo end
    sleep 2
done
