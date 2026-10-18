#!/bin/bash
# Touch-friendly app menu (nwg-drawer): a full-screen grid of big icons,
# without search bar or categories. It stays in memory so it opens instantly.
#   app-drawer.sh          open / close it (Super key, swipe up from the bottom edge)
#   app-drawer.sh start    (re)start it in the background: at login, and after
#                          a rotation or wallpaper change so the column count
#                          and colors match

case "${1:-toggle}" in
    start)
        pkill -x nwg-drawer
        # wait (max 2s) for it to exit: a new resident instance quits if it
        # still sees the old one running
        for _ in $(seq 20); do
            pgrep -x nwg-drawer >/dev/null || break
            sleep 0.1
        done
        # fewer columns when the screen is in portrait (see rotate.sh)
        if [ "$(cat "$HOME/.local/state/hypr/rotation" 2>/dev/null)" = 0 ]; then
            columns=4
        else
            columns=6
        fi
        # no categories or file search; the search box is hidden in drawer.css
        setsid -f nwg-drawer -r -c "$columns" -is 96 -spacing 8 -closebtn right \
            -nocats -nofs -term foot -fm thunar >/dev/null 2>&1
        ;;
    toggle)
        # running nwg-drawer again shows/hides the resident instance
        if pgrep -x nwg-drawer >/dev/null; then
            nwg-drawer >/dev/null 2>&1
        else
            "$0" start
            sleep 0.5
            nwg-drawer -open >/dev/null 2>&1
        fi
        ;;
    *) echo "usage: app-drawer.sh [toggle|start]" >&2; exit 1 ;;
esac
