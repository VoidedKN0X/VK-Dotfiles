#!/bin/bash
# Notifications about Steam Deck BIOS updates.
# The system service `steamdeck-bios-update` (installed by run-all-steamdeck.sh)
# checks for updates at boot and every hour and writes what it found to
# /var/lib/steamdeck-bios-update/. This script turns that into notifications,
# each one only once.
#   bios-update-notify.sh           check once
#   bios-update-notify.sh --watch   keep checking every 10 minutes (started at login)

DIR=/var/lib/steamdeck-bios-update
SEEN_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bios-update-notify"
mkdir -p "$SEEN_DIR"

# read KEY=VALUE files without executing them
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

# notify once per unique key; $1 = which file, $2 = key, rest = notify-send args
once() {
    local name="$1" key="$2"; shift 2
    [ "$key" = "$(cat "$SEEN_DIR/$name" 2>/dev/null)" ] && return
    notify-send -a "BIOS update" -i system-software-update "$@"
    echo "$key" > "$SEEN_DIR/$name"
}

check() {
    # 1. a finished update (applied during the last restart)
    if [ -r "$DIR/last-update" ]; then
        local from to
        from=$(field "$DIR/last-update" FROM)
        to=$(field "$DIR/last-update" TO)
        [ -n "$to" ] && once updated "$from>$to" \
            "BIOS updated" "Your Steam Deck BIOS was updated from $from to $to."
    fi

    # 2. the current state of the update check
    [ -r "$DIR/status" ] || return
    local state target current
    state=$(field "$DIR/status" STATE)
    target=$(field "$DIR/status" TARGET)
    current=$(field "$DIR/status" CURRENT)
    case "$state" in
        staged)
            once status "staged>$target" -u normal \
                "BIOS update ready" "BIOS $target installs on the next restart. Keep the charger connected while it restarts." ;;
        needs-ac)
            once status "needs-ac>$target" \
                "BIOS update available" "BIOS $target is available. Connect the charger: it's prepared automatically within the hour." ;;
        low-battery)
            once status "low-battery>$target" \
                "BIOS update available" "BIOS $target is available. Charge above 20% with the charger connected: it's prepared automatically within the hour." ;;
        manual)
            once status "manual>$target" \
                "BIOS update available" "BIOS $target is available, but Valve marks it as a manual update. With the charger connected, run: sudo jupiter-biosupdate, then restart." ;;
        failed)
            once status "failed>$target>$current" -u critical \
                "BIOS update failed" "Updating to BIOS $target failed. Details: journalctl -u steamdeck-bios-update" ;;
        *)
            # up to date: forget the last message, so a new update is announced again
            echo "$state" > "$SEEN_DIR/status" ;;
    esac
}

if [ "${1:-}" = "--watch" ]; then
    while :; do check; sleep 600; done
else
    check
fi
