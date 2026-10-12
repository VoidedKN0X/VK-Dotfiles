#!/bin/bash
# Show or hide the on-screen keyboard (squeekboard), e.g. from a touch gesture.
# squeekboard already pops up by itself in text fields; this is for apps that
# don't tell it (X11 apps like Steam, some Electron apps) or to hide it again.
#   osk-toggle.sh          toggle
#   osk-toggle.sh show     show
#   osk-toggle.sh hide     hide

DEST=(sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0)

# Start squeekboard if it isn't running (it registers sm.puri.OSK0 on D-Bus)
if ! pgrep -x squeekboard >/dev/null; then
    squeekboard >/dev/null 2>&1 &
    disown
    for _ in $(seq 30); do
        busctl --user status sm.puri.OSK0 >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

case "${1:-toggle}" in
    show) want=true ;;
    hide) want=false ;;
    *)
        # current state: "b true" or "b false"
        visible=$(busctl --user get-property "${DEST[@]}" Visible 2>/dev/null | awk '{print $2}')
        if [ "$visible" = "true" ]; then want=false; else want=true; fi
        ;;
esac

busctl --user call "${DEST[@]}" SetVisible b "$want"
