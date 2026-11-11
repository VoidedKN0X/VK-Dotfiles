// A round icon button (session buttons, media controls, calendar arrows):
// transparent until hovered, or filled when given a fill color.

import QtQuick

Rectangle {
    id: button

    property string icon: ""
    property int size: 44
    property int iconSize: 16
    property color iconColor: Theme.fg
    property color fill: "transparent"
    property color hoverFill: Theme.hover
    property color borderColor: "transparent"
    // read by screen readers (icon-only button)
    property string accessibleName: ""
    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    // (colors compare with Qt.colorEqual, not ===)
    color: hovered && Qt.colorEqual(fill, "transparent") ? hoverFill : fill
    border.color: borderColor
    border.width: Qt.colorEqual(borderColor, "transparent") ? 0 : 1

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: clicked()

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Glyph {
        anchors.centerIn: parent
        glyph: button.icon
        color: button.iconColor
        font.pixelSize: button.iconSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
