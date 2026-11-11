#!/bin/sh
# Music visualizer for the bar's music island and the control center: runs
# cava with plain-text output, one line per frame with the level of each bar
# (0-7), e.g. "3;5;1;7;2;4;". Read by services/Cava.qml, which only runs this
# while a player has a track (like the Waybar version).
#   cava.sh [bars]   number of bars (default 6)

# One fixed file, rewritten at every start (Quickshell runs one copy)
CONF="${XDG_RUNTIME_DIR:-/tmp}/quickshell-cava.conf"

cat >"$CONF" <<EOF
[general]
bars = ${1:-6}
framerate = 30

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
# ';' between bars
bar_delimiter = 59
EOF

# exec: Quickshell stops cava itself when no track is playing any more
exec cava -p "$CONF"
