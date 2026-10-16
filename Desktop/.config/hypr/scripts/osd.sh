#!/bin/bash
# On-screen display on the focused monitor only:
#   osd.sh <swayosd-client options>   e.g. osd.sh --output-volume raise
mon="$(hyprctl monitors | awk '/^Monitor /{name=$2} /focused: yes/{print name; exit}')"
exec swayosd-client ${mon:+--monitor "$mon"} "$@"
