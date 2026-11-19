// A text button (the network panel): primary (accent-filled), danger (red
// text) or plain; dimmed and unclickable while active is false.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: button
    property string text: ""
    property bool primary: false
    property bool danger: false
    property bool active: true
    signal clicked
    implicitHeight: 36
    implicitWidth: buttonLabel.implicitWidth + 32
    radius: height / 2
    opacity: active ? 1 : 0.45
    color: primary ? (buttonMouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent) : buttonMouse.containsMouse ? Theme.hover : Theme.card
    border.width: primary ? 0 : 1
    border.color: Theme.cardEdge
    Accessible.role: Accessible.Button
    Accessible.name: text
    Label {
        id: buttonLabel
        anchors.centerIn: parent
        text: button.text
        color: button.primary ? Theme.onAccent : button.danger ? Theme.warn : Theme.fg
        font.pixelSize: 12
        font.weight: Font.Bold
    }
    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: button.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (button.active)
            button.clicked()
    }
}
