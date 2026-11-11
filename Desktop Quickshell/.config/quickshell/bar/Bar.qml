// The bar of one monitor: separate glass islands, on the top, left or right
// edge (BarState.edgeFor).
//   start:  workspaces, music
//   middle: clock
//   end:    CPU / temperature / memory, tray + Bluetooth + network + volume,
//           stay awake, notifications, power
// On a side bar, start is the top and end the bottom.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: bar

    required property var modelData
    // "top", "left" or "right"; a change creates a new bar (shell.qml)
    required property string edge

    readonly property bool vertical: edge !== "top"

    screen: modelData
    color: "transparent"
    // the layer's name: Hyprland blurs the islands by it (hypr/hyprland/rules.lua)
    WlrLayershell.namespace: "vk-" + edge
    WlrLayershell.layer: WlrLayer.Top

    anchors {
        top: true
        bottom: bar.vertical
        left: bar.edge !== "right"
        right: bar.edge !== "left"
    }
    margins {
        top: bar.vertical ? Theme.barEndMargin : Theme.barEdgeMargin
        bottom: bar.vertical ? Theme.barEndMargin : 0
        left: bar.edge === "left" ? Theme.barEdgeMargin : bar.vertical ? 0 : Theme.barEndMargin
        right: bar.edge === "right" ? Theme.barEdgeMargin : bar.vertical ? 0 : Theme.barEndMargin
    }
    implicitHeight: Theme.barHeight
    implicitWidth: Theme.barWidth

    // stay awake while the coffee cup is on (the same protocol Waybar's
    // idle_inhibitor used)
    IdleInhibitor {
        window: bar
        enabled: BarState.stayAwake
    }

    // ── start ─────────────────────────────────────────────────────────────
    GridLayout {
        anchors.left: bar.vertical ? undefined : parent.left
        anchors.top: bar.vertical ? parent.top : undefined
        anchors.verticalCenter: bar.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: bar.vertical ? parent.horizontalCenter : undefined
        columns: bar.vertical ? 1 : 100
        columnSpacing: Theme.islandSpacing
        rowSpacing: Theme.islandSpacing

        Workspaces {
            vertical: bar.vertical
            monitorName: bar.modelData.name
        }
        MusicIsland {
            vertical: bar.vertical
            screen: bar.modelData
            edge: bar.edge
        }
    }

    // ── middle ────────────────────────────────────────────────────────────
    Clock {
        anchors.centerIn: parent
        vertical: bar.vertical
        screen: bar.modelData
    }

    // ── end ───────────────────────────────────────────────────────────────
    GridLayout {
        anchors.right: bar.vertical ? undefined : parent.right
        anchors.bottom: bar.vertical ? parent.bottom : undefined
        anchors.verticalCenter: bar.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: bar.vertical ? parent.horizontalCenter : undefined
        columns: bar.vertical ? 1 : 100
        columnSpacing: Theme.islandSpacing
        rowSpacing: Theme.islandSpacing

        SystemIsland {
            vertical: bar.vertical
        }
        StatusIsland {
            vertical: bar.vertical
            window: bar
            edge: bar.edge
        }
        // stay awake (idle inhibitor)
        IconIsland {
            vertical: bar.vertical
            icon: BarState.stayAwake ? Theme.iconAwake : Theme.iconSleepy
            iconColor: BarState.stayAwake ? Theme.accent : Theme.dim
            onClicked: BarState.stayAwake = !BarState.stayAwake
        }
        // notifications: click for the control center, right click for do
        // not disturb. An accent pill while there are notifications.
        IconIsland {
            readonly property bool unread: Notifs.count > 0 && !Notifs.dnd
            vertical: bar.vertical
            icon: Notifs.dnd ? Theme.iconBellOff : Notifs.count > 0 ? Theme.iconBellNew : Theme.iconBell
            iconColor: Notifs.dnd ? Theme.faint : unread ? Theme.onAccent : Theme.fg
            iconHoverColor: unread ? Theme.onAccent : Theme.accent
            fill: unread ? Theme.accent : Theme.glass
            border.color: unread ? "transparent" : Theme.edge
            onClicked: BarState.toggleControlCenter(bar.modelData)
            onRightClicked: Notifs.dnd = !Notifs.dnd
        }
        // power menu
        IconIsland {
            vertical: bar.vertical
            icon: Theme.iconPower
            iconColor: Theme.warn
            iconHoverColor: Theme.warn
            hoverFill: Qt.alpha(Theme.warn, 0.25)
            onClicked: BarState.togglePowerMenu(bar.modelData)
        }
    }
}
