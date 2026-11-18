// One "island" of the bar: a rounded piece of dark glass with a thin light
// edge, holding a row of modules (top bar) or a column (side bars).
// With clickable set, a click anywhere on it (outside its own buttons) sends
// clicked().

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: island

    property bool vertical: false
    // space at the island's ends (Waybar: padding 0 14px, side bars 10px 0)
    property int padding: vertical ? 10 : 14
    property int spacing: 0
    property bool clickable: false
    readonly property bool hovered: hover.hovered
    default property alias content: row.data

    signal clicked

    color: Theme.glass
    border.color: Theme.edge
    border.width: 1
    radius: vertical ? Theme.barWidth / 2 : height / 2
    implicitWidth: vertical ? Theme.barWidth : row.implicitWidth + padding * 2
    implicitHeight: vertical ? row.implicitHeight + padding * 2 : Theme.barHeight

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        id: hover
    }

    // under the modules, so their own buttons get their clicks first
    MouseArea {
        anchors.fill: parent
        enabled: island.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: island.clicked()
    }

    // soft highlight along the top edge, like light on frosted glass
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - parent.radius * 1.2
        height: 1
        color: Theme.highlight
    }

    GridLayout {
        id: row
        anchors.centerIn: parent
        columns: island.vertical ? 1 : 100
        columnSpacing: island.spacing
        rowSpacing: island.spacing
    }
}
