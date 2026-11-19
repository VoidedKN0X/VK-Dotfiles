#!/bin/sh
# GameMode start/end hook (~/.config/gamemode.ini):
#   start: the 9950X3D prefers its 3D V-Cache CCD (amd_x3d_mode "cache";
#          the gamemode group may write it, see
#          /etc/udev/rules.d/90-vk-x3d-mode.rules), and Quickshell pauses cava
#          and the Caps Lock check
#   end:   the mode it had before the game, Quickshell resumes
# Runs once when the first game starts and once when the last one ends.

saved="${XDG_RUNTIME_DIR:-/tmp}/vk-x3d-mode"
x3d=
for f in /sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode; do
    [ -w "$f" ] && x3d=$f && break
done

case "$1" in
start)
    if [ -n "$x3d" ]; then
        cat "$x3d" >"$saved"
        echo cache >"$x3d"
    fi
    qs ipc call gamemode setActive true >/dev/null 2>&1
    ;;
end)
    if [ -n "$x3d" ]; then
        mode=$(cat "$saved" 2>/dev/null)
        echo "${mode:-frequency}" >"$x3d"
        rm -f "$saved"
    fi
    qs ipc call gamemode setActive false >/dev/null 2>&1
    ;;
esac
exit 0
