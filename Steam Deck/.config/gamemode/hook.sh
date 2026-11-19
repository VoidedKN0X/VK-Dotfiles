#!/bin/sh
# GameMode start/end hook (~/.config/gamemode.ini): Quickshell pauses cava and
# the Caps Lock check while a game runs, and resumes afterwards. Runs once
# when the first game starts and once when the last one ends.

case "$1" in
start) qs ipc call gamemode setActive true >/dev/null 2>&1 ;;
end) qs ipc call gamemode setActive false >/dev/null 2>&1 ;;
esac
exit 0
