#!/bin/bash
# Turn squeekboard's automatic popup off while a physical keyboard is
# connected, and back on when it's gone (like SteamOS / GNOME tablet mode).
# Started at login; re-checks whenever an input device is added or removed.
# The swipe-up gesture (osk-toggle.sh) still shows the keyboard on demand.
#
#   osk-auto.sh           watch for keyboards (done at login)
#   osk-auto.sh --check   print which keyboard (if any) counts and exit

# Devices that report keyboard keys but aren't keyboards
IGNORE='yubikey|yubico'

# A "real" keyboard: USB or Bluetooth, has letter keys (udev's
# ID_INPUT_KEYBOARD), and isn't also a mouse (gaming mice like the G502
# expose a keyboard interface for their macro keys)
find_keyboard() {
    local dev props bus name
    for dev in /sys/class/input/event*; do
        props=$(udevadm info -q property "$dev" 2>/dev/null)
        grep -qx 'ID_INPUT_KEYBOARD=1' <<<"$props" || continue
        grep -qx 'ID_INPUT_MOUSE=1' <<<"$props" && continue
        bus=$(cat "$dev/device/id/bustype" 2>/dev/null)
        [ "$bus" = 0003 ] || [ "$bus" = 0005 ] || continue
        name=$(cat "$dev/device/name" 2>/dev/null)
        grep -qiE "$IGNORE" <<<"$name" && continue
        echo "$name"
        return 0
    done
    return 1
}

update() {
    if find_keyboard >/dev/null; then
        want=false
    else
        want=true
    fi
    [ "$want" = "$last" ] && return
    last=$want
    gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled "$want"
    # hide it if it's open right now
    [ "$want" = false ] && busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false >/dev/null 2>&1
}

if [ "$1" = "--check" ]; then
    find_keyboard || echo "no physical keyboard"
    exit 0
fi

# only one watcher
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/osk-auto.lock"
flock -n 9 || exit 0

last=""
update
# udev events come in bursts per device; re-check after each burst settles
udevadm monitor --udev --subsystem-match=input | while read -r _; do
    while read -r -t 0.5 _; do :; done
    update
done
