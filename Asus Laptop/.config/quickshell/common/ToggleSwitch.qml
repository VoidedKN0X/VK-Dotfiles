// An on / off switch (Bluetooth, Wi-Fi), accent-colored when on.

import QtQuick

Rectangle {
    id: toggle

    property bool checked: false
    property string accessibleName: ""

    signal toggled

    implicitWidth: 44
    implicitHeight: 26
    radius: height / 2
    color: checked ? Theme.accent : Theme.track
    border.width: checked ? 0 : 1
    border.color: Theme.cardEdge

    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: toggled()

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Rectangle {
        width: 20
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? parent.width - width - 3 : 3
        color: toggle.checked ? Theme.onAccent : Theme.fg
        Behavior on x {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        // a bigger target than the switch itself
        anchors.margins: -9
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}
