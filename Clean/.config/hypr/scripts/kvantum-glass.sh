#!/bin/bash
# Frosted glass for Qt apps, like the Quickshell frame and the GTK apps: a
# Kvantum theme ("VKGlass") made from Orchis Dark, the Kvantum version of the
# GTK apps' Orchis theme (rounded, flat, modern buttons; Install.sh puts it in
# ~/.config/Kvantum/Orchis), or from Kvantum's own KvArcDark when Orchis
# isn't there. Its windows are see-through (42 % opaque, Hyprland blurs
# what's behind them), in the wallpaper's colors. Text, menus and buttons
# stay solid.
# qt5ct and qt6ct use the "kvantum" style (qt5ct/qt5ct.conf, qt6ct/qt6ct.conf).
# Runs after wallust at every wallpaper change (wallpaper.sh) and once from
# Install.sh. Open Qt apps take the new colors when they're started again.
# Kvantum keeps some apps solid on purpose (video players and editors such as
# VLC and Kdenlive): its "opaque" list.

COLORS="$HOME/.config/quickshell/colors.json"
THEME_DIR="$HOME/.config/Kvantum/VKGlass"
OUT="$THEME_DIR/VKGlass.kvconfig"

# the theme it's made from: its settings (.kvconfig) and its look (.svg)
BASE=""
for base in "$HOME/.config/Kvantum/Orchis/OrchisDark" /usr/share/Kvantum/Orchis/OrchisDark \
    /usr/share/Kvantum/KvArcDark/KvArcDark; do
    if [ -r "$base.kvconfig" ] && [ -r "$base.svg" ]; then
        BASE="$base"
        break
    fi
done
if [ -z "$BASE" ]; then
    echo "kvantum-glass: no Orchis or KvArcDark Kvantum theme found (is kvantum installed?)" >&2
    exit 1
fi

# a color from colors.json without the "#" ("color5" -> "C678DD")
color() {
    sed -n "s/.*\"$1\": *\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$COLORS" 2>/dev/null | head -n 1
}
bg=$(color background)
fg=$(color foreground)
accent=$(color color5)
: "${bg:=202021}" "${fg:=ABB2BF}" "${accent:=C678DD}"

# the glass: the background color at 55 % (like the shell's frame)
glass=$(printf '%02x%02x%02x' $((16#${bg:0:2} * 55 / 100)) $((16#${bg:2:2} * 55 / 100)) $((16#${bg:4:2} * 55 / 100)))

mkdir -p "$THEME_DIR"
cp "$BASE.svg" "$THEME_DIR/VKGlass.svg"
# the base theme's settings with these changed (and added where it has none):
#   see-through windows (58 % less opaque = 42 % opaque), solid menus, no
#   Kvantum blur (that's KDE's; Hyprland does the blurring)
#   the colors: windows the glass, views clear over it, text the wallpaper's
#   foreground, selection and links its accent (buttons keep the theme's own
#   look)
awk -v glass="$glass" -v fg="$fg" -v accent="$accent" '
BEGIN {
    set["%General", "composite"] = "true"
    set["%General", "translucent_windows"] = "true"
    set["%General", "reduce_window_opacity"] = "58"
    set["%General", "reduce_menu_opacity"] = "0"
    set["%General", "blurring"] = "false"
    set["%General", "popup_blurring"] = "false"
    set["GeneralColors", "window.color"] = "#" glass
    set["GeneralColors", "base.color"] = "#" glass "00"
    set["GeneralColors", "alt.base.color"] = "#ffffff0d"
    set["GeneralColors", "highlight.color"] = "#" accent "aa"
    set["GeneralColors", "inactive.highlight.color"] = "#" accent "66"
    set["GeneralColors", "text.color"] = "#" fg
    set["GeneralColors", "window.text.color"] = "#" fg
    set["GeneralColors", "button.text.color"] = "#" fg
    set["GeneralColors", "highlight.text.color"] = "#ffffff"
    set["GeneralColors", "link.color"] = "#" accent
}
# at the end of a section: add the keys it did not have
function flush(   k, parts) {
    for (k in set) {
        split(k, parts, SUBSEP)
        if (parts[1] == section && !((section, parts[2]) in done))
            print parts[2] "=" set[k]
    }
}
/^\[.*\]$/ {
    flush()
    section = substr($0, 2, length($0) - 2)
    print
    next
}
{
    key = $0
    sub(/=.*/, "", key)
    if ((section, key) in set) {
        print key "=" set[section, key]
        done[section, key] = 1
        next
    }
    print
}
END { flush() }
' "$BASE.kvconfig" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

# use it
mkdir -p "$HOME/.config/Kvantum"
printf '[General]\ntheme=VKGlass\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"
# (the theme of the first version of this script)
rm -rf "$HOME/.config/Kvantum/KvArcDark#"
