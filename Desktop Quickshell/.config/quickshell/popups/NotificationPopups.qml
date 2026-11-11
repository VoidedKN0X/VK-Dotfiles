// Notification popups, on the focused monitor next to the bell: top right
// under a top bar, bottom left next to a left bar, bottom right next to a
// right bar (where swaync put them). Newest nearest the bell. Each one stays
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

    screen: targetScreen
    visible: Notifs.popups.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vk-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: !popups.fromBottom
        bottom: popups.fromBottom
        left: popups.edge === "left"
        right: popups.edge !== "left"
    }
    margins {
        top: popups.fromBottom ? 0 : Theme.offset("top")
        bottom: popups.fromBottom ? Theme.barEndMargin : 0
        left: popups.edge === "left" ? Theme.offset("left") : 0
        right: popups.edge === "right" ? Theme.offset("right") : popups.edge === "top" ? Theme.barEndMargin : 0
    }
    implicitWidth: 360
    implicitHeight: Math.max(1, list.implicitHeight)

    // only the cards take clicks, not the space around them
    mask: Region {
        item: list
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
        width: parent.width
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
