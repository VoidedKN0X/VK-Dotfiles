// Notification popups, on the focused monitor next to the bell, in one panel
// that grows out of the frame (Theme "the frame"): out of its right side at
// the top with the bar on top, out of the bar's side at the bottom with a
// side bar (where swaync put them). Newest nearest the bell. Each one stays
// 8 s (low: 6 s, critical: until closed); hovering one keeps it. They stay in
// the control center's list after they go away.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: popups

    readonly property var targetScreen: BarState.focusedScreen()
    readonly property string edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    readonly property bool fromBottom: edge !== "top"
    // the frame side it grows out of
    readonly property string side: edge === "left" ? "left" : "right"
    readonly property int padding: 10

    screen: targetScreen
    visible: Notifs.popups.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vk-notifications-" + side
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: !popups.fromBottom
        bottom: popups.fromBottom
        left: popups.side === "left"
        right: popups.side === "right"
    }
    // from the frame's inner edge, clear of the desktop's round corner (the
    // window includes the rounded joins above and below the cards)
    margins {
        top: popups.fromBottom ? 0 : Theme.frameSize(popups.edge, "top") + Theme.cornerClearance - Theme.fillet
        bottom: popups.fromBottom ? Theme.frameSize(popups.edge, "bottom") + Theme.cornerClearance - Theme.fillet : 0
        left: popups.side === "left" ? Theme.frameSize(popups.edge, "left") : 0
        right: popups.side === "right" ? Theme.frameSize(popups.edge, "right") : 0
    }
    implicitWidth: 360 + padding * 2
    implicitHeight: Math.max(1, list.implicitHeight) + padding * 2 + Theme.fillet * 2

    FramePanel {
        side: popups.side
        base: popups.side === "right" ? popups.width : 0
        from: Theme.fillet
        to: popups.height - Theme.fillet
        depth: popups.width
    }

    // in the order on screen: newest at the top under a top bar, at the
    // bottom (nearest the bell) next to a side bar
    readonly property var ordered: fromBottom ? Notifs.popups.slice().reverse() : Notifs.popups

    property real now: Date.now()
    Timer {
        interval: 30000
        running: popups.visible
        repeat: true
        onTriggered: popups.now = Date.now()
    }

    ColumnLayout {
        id: list
        x: popups.padding
        y: Theme.fillet + popups.padding
        width: parent.width - popups.padding * 2
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
