// Workspaces island: every workspace is a dot, the active one stretches into
// a pill in the accent color. Occupied workspaces are brighter than empty
// ones, urgent ones turn red. Click a dot to go there, scroll to move to the
// next / previous one (like Super + scroll), middle-click for the workspace
// overview (like Super + Tab). Every bar shows the workspaces of all monitors
// that have windows, plus the focused one (the one with the keyboard, on
// either monitor), in order; only the focused one is the pill, the same on
// both bars.

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.common
import qs.services

Island {
    id: island

    required property string monitorName

    padding: 9
    spacing: 0

    // the workspaces with windows, plus the focused one, in order
    readonly property var ids: {
        const focused = Hyprland.focusedWorkspace?.id ?? -1;
        const list = Hyprland.workspaces.values.filter(w => w.id > 0 && (w.id === focused || (w.toplevels?.values?.length ?? 0) > 0)).map(w => w.id);
        if (focused > 0 && !list.includes(focused))
            list.push(focused);
        return list.sort((a, b) => a - b);
    }

    Repeater {
        model: island.ids

        Item {
            id: dot
            required property int modelData
            readonly property var workspace: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
            // the focused workspace (not each monitor's active one)
            readonly property bool active: Hyprland.focusedWorkspace?.id === modelData
            readonly property bool urgent: workspace?.urgent ?? false
            readonly property bool occupied: (workspace?.toplevels?.values?.length ?? 0) > 0
            readonly property bool hovered: mouse.containsMouse

            // 8 px dots with 3 px on each side; the active one 24 px long
            implicitWidth: island.vertical ? 14 : (active ? 24 : 8) + 6
            implicitHeight: island.vertical ? (active ? 24 : 8) + 6 : 14
            Layout.alignment: Qt.AlignCenter

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

            Rectangle {
                anchors.centerIn: parent
                width: island.vertical ? 8 : parent.implicitWidth - 6
                height: island.vertical ? parent.implicitHeight - 6 : 8
                radius: 4
                color: dot.hovered ? Theme.fg : dot.urgent ? Theme.warn : dot.active ? Theme.accent : dot.occupied ? Theme.dim : Theme.faint
                Behavior on color {
                    ColorAnimation {
                        duration: 250
                    }
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                // a bigger target than the dot itself
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // (BarState always sends a Lua dispatcher; Quickshell's
                // workspace.activate() only does when it detects the Lua
                // config, and Hyprland 0.57 takes nothing else)
                onClicked: BarState.focusWorkspace(dot.modelData)
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: BarState.toggleOverview()
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => BarState.focusWorkspace(event.angleDelta.y > 0 ? "e-1" : "e+1")
    }
}
