// A round quick toggle with its name under it: filled with the accent color
// while on.

import QtQuick
import qs.common

Column {
    id: toggle

    property string icon: ""
    property string label: ""
    property bool on: false

    signal clicked
    signal rightClicked

    spacing: 6

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 48
        height: 48
        radius: 24
        color: toggle.on ? Theme.accent : mouse.containsMouse ? Theme.buttonHover : Theme.button
        border.width: toggle.on ? 0 : 1
        border.color: Theme.buttonHover

        Accessible.role: Accessible.Button
        Accessible.name: toggle.label
        Accessible.checkable: true
        Accessible.checked: toggle.on
        Accessible.onPressAction: toggle.clicked()

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Glyph {
            anchors.centerIn: parent
            glyph: toggle.icon
            color: toggle.on ? Theme.onAccent : Theme.fg
            font.pixelSize: 18
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => event.button === Qt.RightButton ? toggle.rightClicked() : toggle.clicked()
        }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: toggle.label
        color: Qt.alpha(Theme.fg, 0.7)
        font.pixelSize: 11
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 60)
        horizontalAlignment: Text.AlignHCenter
    }
}
