#!/bin/bash
# Volume / mic / brightness / Caps Lock keys: change the level, then show it
# in the bar's popup (waybar/scripts/osd.py) on the focused monitor.
#   osd.sh --output-volume raise|lower|mute-toggle   (5% steps, max 100%)
#   osd.sh --input-volume mute-toggle
#   osd.sh --brightness raise|lower                  (5% steps, min 5%)
#   osd.sh --caps-lock

OSD="$HOME/.config/waybar/scripts/osd.py"
SINK=@DEFAULT_AUDIO_SINK@
SOURCE=@DEFAULT_AUDIO_SOURCE@

# "Volume: 0.62 [MUTED]" -> "62 1"
volume_of() {
    wpctl get-volume "$1" | awk '{ printf "%d %d\n", $2 * 100 + 0.5, /MUTED/ ? 1 : 0 }'
}

case "$1 ${2:-}" in
    "--output-volume raise") wpctl set-volume -l 1.0 "$SINK" 5%+ ;;
    "--output-volume lower") wpctl set-volume "$SINK" 5%- ;;
    "--output-volume mute-toggle") wpctl set-mute "$SINK" toggle ;;
    "--input-volume mute-toggle") wpctl set-mute "$SOURCE" toggle ;;
    "--brightness raise") brightnessctl -q set 5%+ ;;
    # never all the way to 0 (a black screen)
    "--brightness lower") brightnessctl -q -n5% set 5%- ;;
    "--caps-lock ") ;;
    *)
        echo "usage: osd.sh --output-volume raise|lower|mute-toggle | --input-volume mute-toggle | --brightness raise|lower | --caps-lock" >&2
        exit 1
        ;;
esac

case "$1" in
    --output-volume)
        read -r level muted < <(volume_of "$SINK")
        exec "$OSD" volume "$level" "$muted"
        ;;
    --input-volume)
        read -r _ muted < <(volume_of "$SOURCE")
        exec "$OSD" mic "$muted"
        ;;
    --brightness)
        # brightnessctl -m: device,class,current,percent%,max
        level=$(brightnessctl -m | cut -d, -f4 | tr -d %)
        exec "$OSD" brightness "${level:-0}"
        ;;
    --caps-lock)
        # the key is bound on release, so the Caps Lock light has switched by now
        on=0
        for led in /sys/class/leds/*::capslock/brightness; do
            [ -r "$led" ] && [ "$(cat "$led")" != 0 ] && on=1
        done
        exec "$OSD" caps "$on"
        ;;
esac
