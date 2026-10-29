#!/bin/bash
# Music visualizer for the bar (custom/cava): runs cava with plain-text output
# and turns every frame into bar characters. It shows exactly while a player
# has a track title (the same title the music island shows, from playerctl):
# paused or silent, it stays as flat bars; other sounds (notifications, a
# video without media info) don't make it appear. An empty line hides it.
#   cava.sh [bars] [vertical [flip]]
#       bars:     number of bars (default 6)
#       vertical: for a side bar: the same bars turned on their side, one per
#                 line, growing to the right (waybar "return-type": "json")
#       flip:     growing to the left instead, for a bar on the right edge
#                 (with "justify": "right")

BARS="${1:-6}"
VERTICAL=0
[ "${2:-}" = vertical ] && VERTICAL=1
FLIP=0
[ "${3:-}" = flip ] && FLIP=1
RUN="${XDG_RUNTIME_DIR:-/tmp}"
# one set of files per running copy (each bar runs its own)
CONF="$RUN/waybar-cava-$$.conf"
TITLE_FILE="$RUN/waybar-cava-title-$$"

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
trap 'pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; rm -f "$CONF" "$TITLE_FILE"' EXIT INT TERM

# Levels 0-7, one character per bar: upright ▁..█ in one row; on its side
# ▏..█, one bar per line (the same bars turned 90°). On its side the lines
# get a little extra height, the gap the upright bars get from letter-spacing.
# Flipped, the characters are drawn rotated 180° (Pango gravity "north"), so
# each fills from the right instead of the left. Sent as JSON there, which can
# hold several lines.
# Only frames that changed are printed, so waybar doesn't redraw for
# identical frames.
cava -p "$CONF" | awk -v title_file="$TITLE_FILE" -v vertical="$VERTICAL" -v flip="$FLIP" '
BEGIN {
    split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", up, " ")
    split("▏ ▎ ▍ ▌ ▋ ▊ ▉ █", side, " ")
}
{
    title = ""
    getline title < title_file
    close(title_file)
    out = ""
    if (title != "") {
        n = split($0, level, ";")
        for (i = 1; i <= n; i++) {
            if (level[i] == "") continue
            if (!vertical) out = out up[level[i] + 1]
            else out = out (out == "" ? "" : "\\n") side[level[i] + 1]
        }
    }
    if (out == prev) next
    prev = out
    # \047 is a single quote (the awk program itself is in single quotes)
    if (vertical) printf "{\"text\": \"%s\"}\n", (out == "" ? "" : "<span line_height=\0471.1\047" (flip ? " gravity=\047north\047" : "") ">" out "</span>")
    else print out
    fflush()
}'
