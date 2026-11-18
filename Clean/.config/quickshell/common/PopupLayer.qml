// A popup that grows out of the frame (control center, calendar, power menu,
// launcher, ...). It isn't a window of its own: it's drawn in the frame's own
// window (bar/Bar.qml) of its screen, so it is the same piece of glass with
// exactly the same blur, and it opens by growing out of the frame's edge
// instead of sliding in, and closes by going back into it. While it's open
// the frame takes the clicks of the whole screen, so a click outside the
// panel (also on the button that opened it) or Escape closes it.
// targetScreen is where it should be open (null: closed). It stays on
// shownScreen while it closes; its loader (common/PopupLoader.qml) keeps it
// loaded until it's back in.
//   attach  the frame side it grows out of; the bar's side unless set
//           ("bottom" for the launcher, wallpaper picker and clipboard)
//   place   along that side: "start", "center" or "end" (top bar: left,
//           middle, right; side bars and the bottom: top, middle, bottom)
//   fullHeight  it fills that whole side (the control center)
// With typing set it takes the keyboard as soon as it opens.
// (The popups in the middle of the screen are common/FloatingPopup.qml.)

import QtQuick

Item {
    id: popupLayer

    required property var targetScreen
    // where it is: targetScreen, and the last one while it closes
    property var shownScreen: null
    readonly property bool open: !!targetScreen
    onTargetScreenChanged: if (targetScreen)
        shownScreen = targetScreen
    // the edge of shownScreen's bar: "top", "left" or "right"
    // (BarState.edgeFor; this file is in common/, which services/ imports)
    required property string edge
    // a name for it (logs, debugging)
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
    // takes the keyboard at once (a search field): typing goes here until it
    // closes. Otherwise it gets the keyboard once clicked.
    property bool typing: false
    default property alias content: inner.data
    // the whole panel at its full size (its content measures against it)
    readonly property alias panel: body

    // read by the frame: while open it takes every click on the screen (not
    // while it closes: then clicks reach what's under it again)
    readonly property bool blocksScreen: open

    signal closeRequested

    // in the frame's window of the target screen (bar/Bar.qml registers it)
    parent: FrameHosts.hostFor(shownScreen?.name ?? "")
    visible: parent !== null
    width: parent?.width ?? 0
    height: parent?.height ?? 0

    readonly property string side: attach !== "" ? attach : edge
    readonly property bool acrossLeftRight: side === "left" || side === "right"

    // the desktop inside the frame
    readonly property real holeLeft: Theme.frameSize(edge, "left")
    readonly property real holeTop: Theme.frameSize(edge, "top")
    readonly property real holeRight: width - Theme.frameSize(edge, "right")
    readonly property real holeBottom: height - Theme.frameSize(edge, "bottom")
    // where the frame's inner edge is on the side it grows out of
    readonly property real base: side === "top" ? holeTop : side === "bottom" ? holeBottom : side === "left" ? holeLeft : holeRight

    // ── growing out of the frame ─────────────────────────────────────────
    // 0 = hidden in the frame, 1 = all the way out. Out quickly and slowing
    // down at the end (280 ms); back in starting slowly and speeding up
    // (220 ms). Started by hand (not a Behavior), so it also runs right after
    // the popup is created.
    property real progress: 0
    NumberAnimation {
        id: slide
        target: popupLayer
        property: "progress"
    }
    function slideTo(value) {
        slide.stop();
        slide.from = progress;
        slide.to = value;
        slide.duration = value > progress ? 280 : 220;
        slide.easing.type = value > progress ? Easing.OutQuint : Easing.InCubic;
        slide.start();
    }
    onOpenChanged: {
        slideTo(open ? 1 : 0);
        if (open)
            inner.forceActiveFocus();
    }

    // a click outside the panel
    MouseArea {
        anchors.fill: parent
        enabled: popupLayer.open
        acceptedButtons: Qt.AllButtons
        onClicked: popupLayer.closeRequested()
    }

    // the glass, joined to the frame, as far out as it has grown
    FramePanel {
        side: popupLayer.side
        base: popupLayer.base
        from: popupLayer.acrossLeftRight ? body.y : body.x
        to: popupLayer.acrossLeftRight ? body.y + body.height : body.x + body.width
        depth: Math.max(1, body.depth * popupLayer.progress)
        span: popupLayer.fullHeight
    }

    // what's out of the frame so far: the content slides out with the edge
    Item {
        id: shown
        clip: true
        readonly property real depth: body.depth * popupLayer.progress
        x: popupLayer.side === "right" ? popupLayer.base - depth : popupLayer.side === "left" ? popupLayer.base : body.x
        y: popupLayer.side === "bottom" ? popupLayer.base - depth : popupLayer.side === "top" ? popupLayer.base : body.y
        width: popupLayer.acrossLeftRight ? depth : body.width
        height: popupLayer.acrossLeftRight ? body.height : depth

        // clicks inside the panel stay inside
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // the panel at its full size, its far edge at the edge of what's shown
        Item {
            x: (popupLayer.side === "left" ? shown.width - body.width : 0)
            y: (popupLayer.side === "top" ? shown.height - body.height : 0)
            width: body.width
            height: body.height

            FocusScope {
                id: inner
                anchors.fill: parent
                anchors.margins: popupLayer.padding
                focus: true
                implicitHeight: childrenRect.height
                Keys.onEscapePressed: popupLayer.closeRequested()
            }
        }
    }

    // the panel's place and full size (in the frame's window)
    Item {
        id: body

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

        width: popupLayer.acrossLeftRight ? depth : length
        height: popupLayer.acrossLeftRight ? length : depth
        x: popupLayer.side === "left" ? popupLayer.holeLeft : popupLayer.side === "right" ? popupLayer.holeRight - width : along
        y: popupLayer.side === "top" ? popupLayer.holeTop : popupLayer.side === "bottom" ? popupLayer.holeBottom - height : along
    }

    Component.onCompleted: {
        if (targetScreen)
            shownScreen = targetScreen;
        slideTo(open ? 1 : 0);
        inner.forceActiveFocus();
    }
}
