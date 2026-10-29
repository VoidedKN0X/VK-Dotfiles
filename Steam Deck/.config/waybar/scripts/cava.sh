#!/bin/bash
# Music visualizer for the bar (custom/cava): runs cava with plain-text output
# and turns every frame into bar characters. It shows exactly while a player
# has a track title (the same title the music island shows, from playerctl):
# paused or silent, it stays as flat bars; other sounds (notifications, a
# video without media info) don't make it appear. An empty line hides it.
#   cava.sh [bars]    number of bars (default 6)

BARS="${1:-6}"
RUN="${XDG_RUNTIME_DIR:-/tmp}"
CONF="$RUN/waybar-cava-$BARS.conf"
TITLE_FILE="$RUN/waybar-cava-title-$BARS"

cat >"$CONF" <<EOF
[general]
bars = $BARS
framerate = 30
# never sleep: frames keep coming during silence, so the bar reacts as soon
# as the title goes away (identical frames aren't passed on to waybar)
sleep_timer = 0

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
# ';' between bars (removed below)
bar_delimiter = 59
EOF

# Current track title -> TITLE_FILE (empty when there's no player or title).
# playerctl exits when no player is running, so it's restarted every 2 s.
: >"$TITLE_FILE"
(
    while true; do
        playerctl --follow metadata --format '{{ title }}' 2>/dev/null |
            while IFS= read -r title; do printf '%s\n' "$title" >"$TITLE_FILE"; done
        : >"$TITLE_FILE"
        sleep 2
    done
) &
watcher=$!
# stop the title watcher and its playerctl when waybar stops this script
trap 'pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null' EXIT INT TERM

# levels 0-7 -> ▁..█. Only lines that changed are printed, so waybar doesn't
# redraw for identical frames.
cava -p "$CONF" | awk -v title_file="$TITLE_FILE" '
BEGIN { split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", ch, " ") }
{
    gsub(/;/, "")
    title = ""
    getline title < title_file
    close(title_file)
    out = ""
    if (title != "")
        for (i = 1; i <= length($0); i++) out = out ch[substr($0, i, 1) + 1]
    if (out != prev) { print out; fflush(); prev = out }
}'
