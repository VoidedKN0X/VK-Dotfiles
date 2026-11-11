// A popup next to the bar (control center, calendar, power menu): an overlay,
// not a window. Hyprland doesn't tile it or move windows aside for it; it
// floats over everything (fullscreen apps too). It's an invisible layer over
// the whole screen with a glass panel in it, so a click outside the panel
// (also on the button that opened it) or Escape closes it.
//   top bar:   under the bar, at the bar's end / middle / start
//   side bars: next to the bar, at its bottom / middle / top
// 14 px from the bar (Theme.gap) and 10 px from the screen edge along it.
// With centered set (app launcher, wallpaper picker, clipboard, password
// dialog) it's in the middle of the screen instead, and with typing set it
// takes the keyboard as soon as it opens.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popupLayer

    required property var targetScreen
    // the edge of that screen's bar: "top", "left" or "right"
    // (BarState.edgeFor; this file is in common/, which services/ imports)
    required property string edge
    // the layer's name; "-top", "-left" or "-right" is added. Hyprland picks the
    // slide-in direction and blur by it (hypr/hyprland/rules.lua)
    required property string name
    // along the bar: "start", "center" or "end"
    property string place: "end"
    // from the bar's end to the screen's bottom (side bars: top to bottom)
    property bool fullHeight: false
    property int panelWidth: 380
    property int padding: 16
    // in the middle of the screen, not next to the bar
    property bool centered: false
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

        readonly property int alongStart: Theme.barEndMargin
        readonly property int barSide: Theme.offset(popupLayer.edge)

        width: popupLayer.panelWidth
        // (centered: from the size alone, as y depends on the height there)
        height: popupLayer.centered ? Math.min(inner.implicitHeight + popupLayer.padding * 2, popupLayer.height - 2 * Theme.barEndMargin) : popupLayer.fullHeight ? popupLayer.height - y - Theme.barEndMargin : Math.min(inner.implicitHeight + popupLayer.padding * 2, popupLayer.height - y - Theme.barEndMargin)
        x: {
            if (popupLayer.centered)
                return (popupLayer.width - width) / 2;
            if (popupLayer.edge === "left")
                return barSide;
            if (popupLayer.edge === "right")
                return popupLayer.width - barSide - width;
            if (popupLayer.place === "start")
                return alongStart;
            if (popupLayer.place === "center")
                return (popupLayer.width - width) / 2;
            return popupLayer.width - alongStart - width;
        }
        y: {
            if (popupLayer.centered)
                return Math.max(Theme.barEndMargin, (popupLayer.height - height) / 2);
            if (popupLayer.edge === "top")
                return barSide;
            if (popupLayer.fullHeight || popupLayer.place === "start")
                return alongStart;
            if (popupLayer.place === "center")
                return (popupLayer.height - height) / 2;
            return popupLayer.height - alongStart - height;
        }

        color: Theme.panel
        border.color: Theme.edge
        border.width: 1
        radius: 20
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
