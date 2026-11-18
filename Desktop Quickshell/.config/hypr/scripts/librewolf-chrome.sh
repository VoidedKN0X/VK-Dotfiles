#!/bin/bash
# LibreWolf's address bar suggestions on a solid background.
# The frosted glass for GTK apps (gtk-3.0/gtk.css) makes GTK's text fields and
# windows see-through, and LibreWolf (with its "System theme") takes its address
# bar colors from them, so the suggestions under the address bar were drawn
# without a background, over the page. This gives the address bar (and its
# suggestions while open) a solid background in the wallpaper's colors, with a
# userChrome.css in every LibreWolf profile (and the pref that makes LibreWolf
# load it, in the profile's user.js).
# Runs after wallust at every wallpaper change and at login (wallpaper.sh), so
# profiles made later get it too, and once from Install.sh. LibreWolf picks up
# a change when it's started again.
# Your own userChrome.css is kept: only the part between the "vk-dotfiles"
# lines is rewritten.

COLORS="$HOME/.config/quickshell/colors.json"

# a color from colors.json without the "#"
color() {
    sed -n "s/.*\"$1\": *\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$COLORS" 2>/dev/null | head -n 1
}
bg=$(color background)
fg=$(color foreground)
accent=$(color color5)
: "${bg:=202021}" "${fg:=ABB2BF}" "${accent:=C678DD}"

# a little lighter than the background, like a field on the glass
field=$(printf '%02x%02x%02x' \
    $((16#${bg:0:2} + (255 - 16#${bg:0:2}) * 8 / 100)) \
    $((16#${bg:2:2} + (255 - 16#${bg:2:2}) * 8 / 100)) \
    $((16#${bg:4:2} + (255 - 16#${bg:4:2}) * 8 / 100)))

BEGIN_MARK="/* vk-dotfiles: begin (hypr/scripts/librewolf-chrome.sh rewrites this part) */"
END_MARK="/* vk-dotfiles: end */"
CSS="$BEGIN_MARK
/* the address bar and its suggestions: solid, in the wallpaper's colors */
#urlbar {
    --toolbar-field-background-color: #$field !important;
    --toolbar-field-focus-background-color: #$bg !important;
    --toolbar-field-color: #$fg !important;
    --toolbar-field-focus-color: #$fg !important;
}
#urlbar-background,
.urlbar-background {
    background-color: #$field !important;
}
#urlbar[focused] > #urlbar-background,
#urlbar[focused] > .urlbar-background,
#urlbar[open] > #urlbar-background,
#urlbar[open] > .urlbar-background,
.urlbarView {
    background-color: #$bg !important;
}
.urlbarView-row[selected],
.urlbarView-row:hover {
    background-color: #${accent}55 !important;
}
$END_MARK"

PREF='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

# every LibreWolf profile (the old ~/.librewolf and the newer XDG folder)
for root in "$HOME/.librewolf" "$HOME/.config/librewolf/librewolf"; do
    [ -r "$root/profiles.ini" ] || continue
    while IFS= read -r line; do
        case "$line" in
        Path=/*) dir="${line#Path=}" ;;
        Path=*) dir="$root/${line#Path=}" ;;
        *) continue ;;
        esac
        [ -d "$dir" ] || continue

        # load userChrome.css
        if ! grep -qF "$PREF" "$dir/user.js" 2>/dev/null; then
            echo "$PREF" >>"$dir/user.js"
        fi

        # userChrome.css: replace our part, keep the rest
        mkdir -p "$dir/chrome"
        file="$dir/chrome/userChrome.css"
        rest=""
        if [ -f "$file" ]; then
            rest=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
                $0 == b { skip = 1; next }
                $0 == e { skip = 0; next }
                !skip' "$file")
        fi
        {
            printf '%s\n' "$CSS"
            [ -n "$rest" ] && printf '%s\n' "$rest"
        } >"$file.tmp" && mv "$file.tmp" "$file"
    done <"$root/profiles.ini"
done
exit 0
