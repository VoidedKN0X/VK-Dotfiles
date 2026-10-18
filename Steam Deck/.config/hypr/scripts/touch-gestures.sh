#!/bin/bash
# Touchscreen gestures for the Steam Deck, using lisgd (it reads the
# touchscreen directly, so it works no matter what Hyprland version you run).
#
#   touch-gestures.sh            start the gesture daemon (done at login)
#   touch-gestures.sh --debug    run in the foreground and print every gesture,
#                                to check directions/edges after a change
#   touch-gestures.sh <action>   run one action (lisgd calls this)
#
# Gestures:
#   1 finger, swipe up from the bottom edge     app launcher
#   1 finger, swipe down from the top edge      notification center
#   3 fingers, swipe left / right               next / previous workspace
#   3 fingers, swipe up                         fullscreen on/off
#   3 fingers, swipe down                       close the window
#   (1 finger from the left and right edges is still free)

SCRIPTS="$HOME/.config/hypr/scripts"

# /dev/input/touchscreen is created by the udev rule Install.sh adds
DEVICE="/dev/input/touchscreen"

# The panel is mounted portrait and Hyprland rotates it (transform 3 by
# default, or whatever rotate.sh saved), but the touchscreen still reports
# portrait coordinates. lisgd's -o rotates the gestures by the same number of
# 90-degree steps to match.
ROTATION=$(cat "$HOME/.local/state/hypr/rotation" 2>/dev/null)
[ "$ROTATION" = 0 ] || ROTATION=3

hypr() { hyprctl dispatch "$1" >/dev/null; }

case "${1:-start}" in
    notifications)  swaync-client -t -sw ;;
    launcher)       "$SCRIPTS/app-drawer.sh" ;;
    next-workspace) hypr 'hl.dsp.focus({ workspace = "e+1" })' ;;
    prev-workspace) hypr 'hl.dsp.focus({ workspace = "e-1" })' ;;
    fullscreen)     hypr 'hl.dsp.window.fullscreen({ mode = 0 })' ;;
    close-window)   hypr 'hl.dsp.window.close()' ;;
    start|--debug)
        if [ ! -e "$DEVICE" ]; then
            notify-send -u critical "Touch gestures" "No touchscreen found at $DEVICE"
            exit 1
        fi
        pkill -x lisgd
        me="$SCRIPTS/touch-gestures.sh"
        # -g "fingers,direction,edge,distance,mode,command"
        # directions: LR = left-to-right, RL, DU = down-to-up, UD; edges: L R T B, * = anywhere
        args=(-d "$DEVICE" -o "$ROTATION"
            -g "1,DU,B,*,R,$me launcher"
            -g "1,UD,T,*,R,$me notifications"
            -g "3,RL,*,*,R,$me next-workspace"
            -g "3,LR,*,*,R,$me prev-workspace"
            -g "3,DU,*,*,R,$me fullscreen"
            -g "3,UD,*,*,R,$me close-window")
        if [ "$1" = "--debug" ]; then
            exec lisgd -v "${args[@]}"
        fi
        exec lisgd "${args[@]}" >/dev/null 2>&1
        ;;
    *) echo "unknown action: $1" >&2; exit 1 ;;
esac
