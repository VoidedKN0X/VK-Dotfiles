// Workspaces island: every workspace is a dot, the active one stretches into
// a pill in the accent color. Occupied workspaces are brighter than empty
// ones, urgent ones turn red. Click a dot to go there, scroll to move to the
// next / previous one (like Super + scroll). Each bar shows only its own
// monitor's workspaces (BarState.workspaces).

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

    readonly property var ids: BarState.workspaces[monitorName] ?? Hyprland.workspaces.values.filter(w => w.monitor?.name === monitorName && w.id > 0).map(w => w.id)

    Repeater {
        model: island.ids

        Item {
            id: dot
            required property int modelData
            readonly property var workspace: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
            readonly property bool active: workspace?.active ?? false
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
                onClicked: {
                    if (dot.workspace)
                        dot.workspace.activate();
                    else
                        BarState.focusWorkspace(dot.modelData);
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => BarState.focusWorkspace(event.angleDelta.y > 0 ? "e-1" : "e+1")
    }
}
