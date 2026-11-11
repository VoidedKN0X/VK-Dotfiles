// A thick pill slider with the icon and name inside it (volume, microphone).
// Drag or click to set the level, scroll for 5% steps, click the icon to mute.

import QtQuick
import qs.common

Rectangle {
    id: slider

    property real value: 0          // 0-1
    property bool muted: false
    property string icon: ""
    property string label: ""
    property string valueText: `${Math.round(value * 100)}%`

    signal moved(real value)
    signal iconClicked

    implicitHeight: 44
    radius: height / 2
    color: Qt.rgba(0.827, 0.839, 0.871, 0.1)
    clip: true

    Accessible.role: Accessible.Slider
    Accessible.name: label

    // the filled part
    Rectangle {
        height: parent.height
        radius: parent.radius
        width: Math.max(parent.height, parent.width * slider.value)
        visible: slider.value > 0
        color: slider.muted ? Theme.faint : Theme.accent
        Behavior on width {
            enabled: !drag.pressed
            NumberAnimation {
                duration: 120
            }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: event => slider.moved(event.x / width)
        onPositionChanged: event => {
            if (pressed)
                slider.moved(Math.max(0, Math.min(1, event.x / width)));
        }
        onWheel: event => slider.moved(Math.max(0, Math.min(1, slider.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }

    // icon (click: mute) and name, on the left
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        HoverButton {
            size: 34
            icon: slider.icon
            iconColor: slider.muted ? Theme.warn : slider.value > 0.08 ? Theme.onAccent : Theme.fg
            hoverFill: Qt.rgba(0, 0, 0, 0.15)
            accessibleName: slider.muted ? "Unmute" : "Mute"
            onClicked: slider.iconClicked()
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: slider.label
            // on the accent fill while it reaches under the name
            color: !slider.muted && slider.value > 0.35 ? Theme.onAccent : Theme.fg
            font.pixelSize: 13
            font.weight: Font.Bold
            elide: Text.ElideRight
            width: Math.min(implicitWidth, slider.width - 140)
        }
    }

    Label {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: slider.muted ? "muted" : slider.valueText
        color: slider.muted ? Theme.warn : slider.value > 0.9 ? Theme.onAccent : Theme.fg
        font.pixelSize: 13
    }
}
