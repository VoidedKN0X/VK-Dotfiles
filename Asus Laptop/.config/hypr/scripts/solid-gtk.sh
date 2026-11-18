#!/bin/bash
# Starts a GTK app without the frosted glass (gtk-3.0/gtk.css,
# gtk-4.0/gtk.css): its normal, solid dark theme. For apps the glass doesn't
# work in:
#   LACT       Hyprland doesn't blur behind it, so the wallpaper showed
#              through its window sharp
#   LibreWolf  takes its address bar colors from GTK, so the suggestions under
#              the address bar had no background
# Their .desktop files in ~/.local/share/applications start them through this
# script (Install.sh makes them from the apps' own), and so does Super + W
# (hypr/variables.lua).
#   solid-gtk.sh lact gui
# GTK reads the glass from $XDG_CONFIG_HOME/gtk-*/gtk.css, so the app gets a
# config folder of its own, ~/.config/vk-solid: a mirror of ~/.config (links
# to everything in it: the apps' settings, fonts, folders, default apps, ...)
# with the GTK folders' files linked one by one, all but gtk.css.

SOLID="$HOME/.config/vk-solid"
mkdir -p "$SOLID"

# everything in ~/.config, linked (new folders appear in the mirror the next
# time an app starts through this)
for entry in "$HOME/.config"/* "$HOME/.config"/.[!.]*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    case "$name" in
    vk-solid | gtk-3.0 | gtk-4.0) continue ;;
    esac
    [ -e "$SOLID/$name" ] || [ -L "$SOLID/$name" ] || ln -s "$entry" "$SOLID/$name"
done
# the GTK folders: their files, without the glass
for v in gtk-3.0 gtk-4.0; do
    # (an earlier version linked the whole folder)
    [ -L "$SOLID/$v" ] && rm "$SOLID/$v"
    mkdir -p "$SOLID/$v"
    for f in "$HOME/.config/$v"/*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        case "$name" in
        gtk.css | vk-colors.css) continue ;;
        esac
        ln -sfn "$f" "$SOLID/$v/$name"
    done
    rm -f "$SOLID/$v/gtk.css"
done
# links to things removed from ~/.config
find "$SOLID" -maxdepth 2 -xtype l -delete 2>/dev/null

XDG_CONFIG_HOME="$SOLID" exec "$@"
