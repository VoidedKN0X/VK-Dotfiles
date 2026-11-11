// A popup (control center, calendar, power menu, launcher, ...): an overlay,
// not a window. Hyprland doesn't tile it or move windows aside for it; it
// floats over everything (fullscreen apps too). It's an invisible layer over
// the whole screen with a panel in it, so a click outside the panel (also on
// the button that opened it) or Escape closes it.
// The panel grows out of the frame around the screen (Theme "the frame"):
//   attach  the frame side it grows out of; the bar's side unless set
//           ("bottom" for the launcher, wallpaper picker and clipboard)
//   place   along that side: "start", "center" or "end" (top bar: left,
//           middle, right; side bars and the bottom: top, middle, bottom)
//   fullHeight  it fills that whole side (the control center)
// With centered set (password dialog, window switcher) it floats in the
// middle of the screen instead, a rounded panel of its own. With typing set
// it takes the keyboard as soon as it opens.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popupLayer

    required property var targetScreen
    // the edge of that screen's bar: "top", "left" or "right"
    // (BarState.edgeFor; this file is in common/, which services/ imports)
    required property string edge
    // the layer's name; the side it grows out of ("-top", "-bottom", "-left",
    // "-right") is added. Hyprland picks the slide-in direction and blur by it
    // (hypr/hyprland/rules.lua)
    required property string name
    // the frame side it grows out of ("" = the bar's side)
    property string attach: ""
    // along that side: "start", "center" or "end"
    property string place: "end"
    // the whole side
    property bool fullHeight: false
    // across the side it grows out of (left/right), along it (top/bottom)
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
    readonly property string side: centered ? edge : attach !== "" ? attach : edge
    readonly property bool acrossLeftRight: side === "left" || side === "right"

    // the desktop inside the frame
    readonly property real holeLeft: Theme.frameSize(edge, "left")
    readonly property real holeTop: Theme.frameSize(edge, "top")
    readonly property real holeRight: width - Theme.frameSize(edge, "right")
    readonly property real holeBottom: height - Theme.frameSize(edge, "bottom")

    WlrLayershell.namespace: name + "-" + side
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    // a click outside the panel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: popupLayer.closeRequested()
    }

    // the glass, joined to the frame
    FramePanel {
        visible: !popupLayer.centered
        side: popupLayer.side
        base: side === "top" ? popupLayer.holeTop : side === "bottom" ? popupLayer.holeBottom : side === "left" ? popupLayer.holeLeft : popupLayer.holeRight
        from: popupLayer.acrossLeftRight ? panel.y : panel.x
        to: popupLayer.acrossLeftRight ? panel.y + panel.height : panel.x + panel.width
        depth: popupLayer.acrossLeftRight ? panel.width : panel.height
        span: popupLayer.fullHeight
    }

    Rectangle {
        id: panel

        // along the side: where it may go, and how long it is
        readonly property real lo: popupLayer.acrossLeftRight ? popupLayer.holeTop : popupLayer.holeLeft
        readonly property real hi: popupLayer.acrossLeftRight ? popupLayer.holeBottom : popupLayer.holeRight
        readonly property real contentLength: inner.implicitHeight + popupLayer.padding * 2
        readonly property real length: {
            if (popupLayer.fullHeight)
                return hi - lo;
            const wanted = popupLayer.acrossLeftRight ? contentLength : popupLayer.panelWidth;
            return Math.min(wanted, hi - lo - 2 * Theme.cornerClearance);
        }
        // into the desktop
        readonly property real depth: popupLayer.acrossLeftRight ? popupLayer.panelWidth : Math.min(contentLength, popupLayer.holeBottom - popupLayer.holeTop - Theme.cornerClearance)
        readonly property real along: {
            if (popupLayer.fullHeight)
                return lo;
            if (popupLayer.place === "start")
                return lo + Theme.cornerClearance;
            if (popupLayer.place === "center")
                return (lo + hi - length) / 2;
            return hi - Theme.cornerClearance - length;
        }

        width: popupLayer.centered ? popupLayer.panelWidth : popupLayer.acrossLeftRight ? depth : length
        // (centered: from the size alone, as y depends on the height there)
        height: popupLayer.centered ? Math.min(contentLength, popupLayer.height - 2 * Theme.barEndMargin) : popupLayer.acrossLeftRight ? length : depth
        x: {
            if (popupLayer.centered)
                return (popupLayer.width - width) / 2;
            if (popupLayer.side === "left")
                return popupLayer.holeLeft;
            if (popupLayer.side === "right")
                return popupLayer.holeRight - width;
            return along;
        }
        y: {
            if (popupLayer.centered)
                return Math.max(Theme.barEndMargin, (popupLayer.height - height) / 2);
            if (popupLayer.side === "top")
                return popupLayer.holeTop;
            if (popupLayer.side === "bottom")
                return popupLayer.holeBottom - height;
            return along;
        }

        // joined to the frame, the glass is the FramePanel above; centered,
        // a rounded panel of its own
        color: popupLayer.centered ? Theme.panel : "transparent"
        border.color: Theme.edge
        border.width: popupLayer.centered ? 1 : 0
        radius: Theme.panelRadius
        clip: true

        // clicks inside the panel stay inside
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // soft highlight along the top edge, like the bar's islands
        Rectangle {
            visible: popupLayer.centered
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
