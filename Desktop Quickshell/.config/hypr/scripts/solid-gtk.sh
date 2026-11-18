#!/bin/bash
# Starts a GTK app without the frosted glass (gtk-3.0/gtk.css,
# gtk-4.0/gtk.css): its normal, solid dark theme. For apps the glass doesn't
# work in: LACT showed the wallpaper sharp through its window, because
# Hyprland doesn't blur behind it (its .desktop file in
# ~/.local/share/applications starts it through this script).
#   solid-gtk.sh lact gui
# GTK reads the glass from $XDG_CONFIG_HOME/gtk-*/gtk.css, so the app gets a
# config folder of its own (~/.config/vk-solid) with the GTK settings (theme,
# icons, fonts) but without the glass. Each app's own config folder is linked
# in from ~/.config, so its settings stay where they were.

SOLID="$HOME/.config/vk-solid"
mkdir -p "$SOLID/gtk-3.0" "$SOLID/gtk-4.0"
for v in gtk-3.0 gtk-4.0; do
    [ -e "$HOME/.config/$v/settings.ini" ] && ln -sfn "$HOME/.config/$v/settings.ini" "$SOLID/$v/settings.ini"
done
# the app's own config folder (the name of its command: lact -> ~/.config/lact)
app=$(basename "$1")
mkdir -p "$HOME/.config/$app"
[ -e "$SOLID/$app" ] || ln -s "$HOME/.config/$app" "$SOLID/$app"

XDG_CONFIG_HOME="$SOLID" exec "$@"
