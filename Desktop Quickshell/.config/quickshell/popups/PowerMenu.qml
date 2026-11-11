// Power menu: the bar's power button. Lock and suspend, then log out, restart
// and shut down; the last three need a second click (the first turns the row
// red: "Click again to restart", back to normal after 3 seconds). Next to the
// power button: top right with the bar on top, the bottom corner with a side
// bar. A click outside, a second click on the button or Escape closes it.

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.services

PopupLayer {
    id: menu

    name: "vk-power"
    place: "end"
    panelWidth: 230
    padding: 8
    targetScreen: BarState.powerMenuScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.powerMenuScreen = null

    // the action waiting for its second click
    property string pending: ""

    Timer {
        id: confirmTimeout
        interval: 3000
        onTriggered: menu.pending = ""
    }

    ColumnLayout {
        width: parent.width
        spacing: 2

        Repeater {
            model: [
                { action: "lock", label: "Lock", icon: Theme.iconLock },
                { action: "suspend", label: "Suspend", icon: Theme.iconSuspend },
                { separator: true },
                { action: "logout", label: "Log out", icon: Theme.iconLogout },
                { action: "reboot", label: "Restart", icon: Theme.iconRestart, danger: true },
                { action: "poweroff", label: "Shut down", icon: Theme.iconPower, danger: true }
            ]

            Item {
                id: row
                required property var modelData
                readonly property bool confirming: menu.pending === modelData.action
                Layout.fillWidth: true
                implicitHeight: modelData.separator ? 9 : 40

                // between lock + suspend and the ones that end the session
                Rectangle {
                    visible: row.modelData.separator === true
                    anchors.centerIn: parent
                    width: parent.width - 20
                    height: 1
                    color: Theme.hover
                }

                Rectangle {
                    visible: !row.modelData.separator
                    anchors.fill: parent
                    radius: 14
                    color: row.confirming ? Qt.alpha(Theme.warn, 0.22) : mouse.containsMouse ? Theme.hover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12
                        Glyph {
                            glyph: row.modelData.icon ?? ""
                            color: row.modelData.danger ? Theme.warn : Theme.fg
                            Layout.preferredWidth: 22
                        }
                        Label {
                            Layout.fillWidth: true
                            text: row.confirming ? Session.confirmText[row.modelData.action] : (row.modelData.label ?? "")
                            color: row.confirming ? Theme.warnLight : Theme.fg
                            font.pixelSize: 13
                            font.weight: row.confirming ? Font.DemiBold : Font.Medium
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menu.choose(row.modelData.action)
                    }
                }
            }
        }
    }

    function choose(action) {
        if (Session.confirmText[action] && pending !== action) {
            pending = action;
            confirmTimeout.restart();
            return;
        }
        Session.run(action);
    }
}
