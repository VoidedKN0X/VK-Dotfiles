// Text in the shell's font (Ubuntu, medium weight like Waybar).

import QtQuick

Text {
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    font.weight: Font.Medium
    verticalAlignment: Text.AlignVCenter
}
