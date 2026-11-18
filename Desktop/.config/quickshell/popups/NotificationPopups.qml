// Notification popups, on the focused monitor next to the bell, in one panel
// that grows out of the frame: out of its right side at the top with the bar
// on top, out of the bar's side at the bottom with a side bar (where swaync
// put them). It's drawn in the frame's own window (common/FrameHosts.qml), so
// it's the same glass with the same blur. Newest nearest the bell. Each one
// stays 8 s (low: 6 s, critical: until closed); hovering one keeps it. They
// stay in the control center's list after they go away.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

Item {
    id: popups

    readonly property var targetScreen: BarState.focusedScreen()
    readonly property string edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    readonly property bool fromBottom: edge !== "top"
    // the frame side it grows out of
    readonly property string side: edge === "left" ? "left" : "right"
    readonly property int padding: 10
    readonly property bool showing: Notifs.popups.length > 0

    // in the frame's window of the focused screen
    parent: FrameHosts.hostFor(targetScreen?.name ?? "")
    visible: parent !== null && (showing || progress > 0)
    width: parent?.width ?? 0
    height: parent?.height ?? 0

    // read by the frame: only the panel takes clicks
    readonly property Item clickArea: visible ? panel : null

    // grows out of the frame when the first one comes, goes back in after
    // the last one
    property real progress: 0
    Behavior on progress {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }
    onShowingChanged: progress = showing ? 1 : 0
    Component.onCompleted: progress = showing ? 1 : 0

    // the frame's inner edge on that side
    readonly property real base: side === "right" ? width - Theme.frameSize(edge, "right") : Theme.frameSize(edge, "left")
    readonly property real fullWidth: 360 + padding * 2
    readonly property real fullHeight: list.implicitHeight + padding * 2

    // the glass, joined to the frame
    FramePanel {
        side: popups.side
        base: popups.base
        from: panel.y
        to: panel.y + panel.height
        depth: Math.max(1, panel.width)
    }

    // the panel, as far out as it has grown; the cards slide out with it
    Item {
        id: panel
        clip: true
        width: popups.fullWidth * popups.progress
        height: popups.fullHeight
        x: popups.side === "right" ? popups.base - width : popups.base
        y: popups.fromBottom ? popups.height - Theme.frameSize(popups.edge, "bottom") - Theme.cornerClearance - height : Theme.frameSize(popups.edge, "top") + Theme.cornerClearance
        Behavior on height {
            NumberAnimation {
                duration: 160
            }
        }

        ColumnLayout {
            id: list
            x: (popups.side === "left" ? panel.width - popups.fullWidth : 0) + popups.padding
            y: popups.padding
            width: popups.fullWidth - popups.padding * 2
            spacing: 8

            Repeater {
                model: popups.ordered

                NotificationCard {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true
                    popup: true
                    notification: modelData
                    age: Notifs.age(modelData, popups.now)
                    onActivated: Notifs.activate(modelData)
                    onClosed: modelData.dismiss()
                    onActionInvoked: action => Notifs.invoke(modelData, action)

                    Timer {
                        interval: Notifs.timeoutFor(card.modelData) * 1000
                        running: interval > 0 && !card.hovered
                        onTriggered: Notifs.hidePopup(card.modelData)
                    }
                }
            }
        }
    }

    // in the order on screen: newest at the top under a top bar, at the
    // bottom (nearest the bell) next to a side bar
    readonly property var ordered: fromBottom ? Notifs.popups.slice().reverse() : Notifs.popups

    property real now: Date.now()
    Timer {
        interval: 30000
        running: popups.showing
        repeat: true
        onTriggered: popups.now = Date.now()
    }
}
