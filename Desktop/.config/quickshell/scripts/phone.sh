#!/bin/bash
# phone.sh - the phone paired with KDE Connect, for the shell
# (services/Phone.qml). Talks to KDE Connect's background service (kdeconnectd)
# over D-Bus with busctl (part of systemd); the first call starts the service
# if it isn't running yet.
#
#   phone.sh watch            one JSON line whenever something changes
#                             (checked every 10 s):
#                             {"id":"...","name":"...","reachable":true,
#                              "charge":78,"charging":false}
#                             or {"id":""} without a paired phone
#   phone.sh ring <id>        make the phone ring (find my phone)
#   phone.sh clipboard <id>   send this PC's clipboard to the phone
#   phone.sh browse <id>      mount the phone's storage and open it in the file
#                             manager
#   phone.sh send <id>        pick files (kdialog) and send them to the phone

set -uo pipefail

bus=org.kde.kdeconnect
dev=/modules/kdeconnect/devices

# a D-Bus property's value, without busctl's type letter (s "x" -> x, i 78 -> 78)
prop() {
    busctl --user get-property "$bus" "$1" "$2" "$3" 2>/dev/null |
        sed -E 's/^[a-z] //; s/^"(.*)"$/\1/'
}
# the same on a plugin of the device ($1 id, $2 plugin, $3 property)
plugin() {
    prop "$dev/$1/$2" "org.kde.kdeconnect.device.$2" "$3"
}
call() {
    busctl --user call "$bus" "$@" >/dev/null 2>&1
}
notify() {
    notify-send -a "KDE Connect" -i kdeconnect "$@" 2>/dev/null
}

case "${1:-}" in
watch)
    # without KDE Connect: nothing to report, and nothing to start again
    command -v kdeconnectd >/dev/null || exec sleep infinity
    last=""
    while :; do
        # the first paired phone (reachable or not)
        id=$(busctl --user call "$bus" /modules/kdeconnect org.kde.kdeconnect.daemon devices bb false true 2>/dev/null |
            sed -nE 's/^as [1-9][0-9]* "([^"]*)".*/\1/p')
        if [[ -z $id ]]; then
            line='{"id":""}'
        else
            name=$(prop "$dev/$id" org.kde.kdeconnect.device name | tr -d '"\\')
            reachable=$(prop "$dev/$id" org.kde.kdeconnect.device isReachable)
            charge=-1 charging=false
            if [[ $reachable == true ]]; then
                charge=$(plugin "$id" battery charge)
                charging=$(plugin "$id" battery isCharging)
                [[ $charge =~ ^-?[0-9]+$ ]] || charge=-1
                [[ $charging == true ]] || charging=false
            fi
            [[ $reachable == true ]] || reachable=false
            line=$(printf '{"id":"%s","name":"%s","reachable":%s,"charge":%s,"charging":%s}' \
                "$id" "$name" "$reachable" "$charge" "$charging")
        fi
        if [[ $line != "$last" ]]; then
            echo "$line"
            last=$line
        fi
        sleep 10
    done
    ;;
ring)
    call "$dev/$2/findmyphone" org.kde.kdeconnect.device.findmyphone ring ||
        notify "Couldn't ring the phone" "Is it connected?"
    ;;
clipboard)
    if call "$dev/$2/clipboard" org.kde.kdeconnect.device.clipboard sendClipboard; then
        notify "Clipboard sent to your phone"
    else
        notify "Couldn't send the clipboard" "Is it connected?"
    fi
    ;;
browse)
    # mount (sshfs), then open the folder; KDE Connect's own "browse" opens a
    # kdeconnect:// address only KDE's file manager understands
    # (mountAndWait and mountPoint are methods: their answer is "b true" and
    # s "/run/user/1000/...")
    sftp=(busctl --user call "$bus" "$dev/$2/sftp" org.kde.kdeconnect.device.sftp)
    if [[ $("${sftp[@]}" mountAndWait 2>/dev/null) == "b true" ]]; then
        mp=$("${sftp[@]}" mountPoint 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
        [[ -n $mp && -d $mp ]] && xdg-open "$mp" && exit 0
    fi
    error=$("${sftp[@]}" getMountError 2>/dev/null | sed -E 's/^s "(.*)"$/\1/')
    notify "Couldn't open the phone's files" "${error:-Is it connected?}"
    ;;
send)
    mapfile -t files < <(kdialog --title "Send to phone" --multiple --separate-output \
        --getopenfilename "$HOME" 2>/dev/null)
    [[ ${#files[@]} -gt 0 ]] || exit 0
    sent=0
    for f in "${files[@]}"; do
        [[ -f $f ]] && kdeconnect-cli --device "$2" --share "$f" >/dev/null 2>&1 && sent=$((sent + 1))
    done
    if [[ $sent -eq ${#files[@]} ]]; then
        notify "Sent to your phone" "$sent file(s)"
    else
        notify "Not everything was sent" "$sent of ${#files[@]} file(s)"
    fi
    ;;
*)
    echo "usage: $0 watch | ring|clipboard|browse|send <device id>" >&2
    exit 1
    ;;
esac
