// A Nerd Font icon (Symbols Nerd Font), sized and centered like Waybar's
// icons (one size up from the text).

import QtQuick

Text {
    property string glyph: ""

    text: glyph
    color: Theme.fg
    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
