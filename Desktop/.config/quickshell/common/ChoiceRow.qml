// One of a few choices, side by side (the network panel's IPv4: Automatic /
// Manual): options [{ value, label }], value is the chosen one.

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: choice
    property var options: []     // [{ value, label }]
    property string value: ""
    Layout.fillWidth: true
    spacing: 6
    Repeater {
        model: choice.options
        Rectangle {
            id: option
            required property var modelData
            readonly property bool selected: choice.value === modelData.value
            Layout.fillWidth: true
            implicitHeight: 34
            radius: height / 2
            color: selected ? Qt.alpha(Theme.accent, 0.2) : optionMouse.containsMouse ? Theme.hover : Theme.card
            border.width: 1
            border.color: selected ? Qt.alpha(Theme.accent, 0.6) : Theme.cardEdge
            Label {
                anchors.centerIn: parent
                text: option.modelData.label
                color: option.selected ? Theme.accent : Theme.fg
                font.pixelSize: 12
                font.weight: option.selected ? Font.Bold : Font.Medium
            }
            MouseArea {
                id: optionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: choice.value = option.modelData.value
            }
        }
    }
}
