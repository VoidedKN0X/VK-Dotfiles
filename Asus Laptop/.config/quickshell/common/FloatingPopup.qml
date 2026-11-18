// A popup that floats in the middle of the screen (the password dialog, the
// window switcher): its own invisible layer over the whole screen, above
// everything (fullscreen apps too), with a rounded panel in the middle. A
// click outside the panel or Escape closes it. With typing set it takes the
// keyboard as soon as it opens.
// (The popups that grow out of the frame are common/PopupLayer.qml.)

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popupLayer

    required property var targetScreen
    // the edge of that screen's bar: "top", "left" or "right"
    // (BarState.edgeFor; this file is in common/, which services/ imports)
    required property string edge
    // the layer's name; "-" and the bar's edge are added. Hyprland picks the
    // animation and blur by it (hypr/hyprland/rules.lua)
    required property string name
    property int panelWidth: 380
    property int padding: 16
    // takes the keyboard at once (a search field): typing goes here until it
    // closes. Otherwise it only gets the keyboard once clicked.
    property bool typing: false
    default property alias content: inner.data
    readonly property alias panel: panel

    signal closeRequested

    screen: targetScreen
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: name + "-" + edge
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    // a click outside the panel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: popupLayer.closeRequested()
    }

    Rectangle {
        id: panel

        readonly property real contentLength: inner.implicitHeight + popupLayer.padding * 2

        width: popupLayer.panelWidth
        height: Math.min(contentLength, popupLayer.height - 2 * Theme.barEndMargin)
        x: (popupLayer.width - width) / 2
        y: Math.max(Theme.barEndMargin, (popupLayer.height - height) / 2)
        color: Theme.panel
        border.color: Theme.edge
        border.width: 1
        radius: Theme.panelRadius
        clip: true

        // clicks inside the panel stay inside
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // soft highlight along the top edge, like the bar's islands
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
            height: 1
            color: Theme.highlight
        }

        FocusScope {
            id: inner
            anchors.fill: parent
            anchors.margins: popupLayer.padding
            focus: true
            implicitHeight: childrenRect.height
            Keys.onEscapePressed: popupLayer.closeRequested()
        }
    }

    Component.onCompleted: inner.forceActiveFocus()
}
