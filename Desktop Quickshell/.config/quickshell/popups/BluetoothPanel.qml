// Bluetooth panel (replaces blueman): click the bar's Bluetooth icon, or
// right-click the control center's Bluetooth toggle. Next to the bar's status
// island, like the mixer.
//   switch:      Bluetooth on / off
//   my devices:  paired devices: connect / disconnect, battery, forget
//   available:   "Search" looks for new devices; click one to pair, trust and
//                connect it (headphones, controllers, mice)
// Devices that ask for a PIN code can't be paired here (Quickshell can't
// answer PIN requests yet): pair those with bluetoothctl in a terminal.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets
import qs.common
import qs.services

PopupLayer {
    id: panel

    name: "vk-bluetooth"
    place: "end"
    panelWidth: 400
    targetScreen: BarState.bluetoothScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.bluetoothScreen = null

    readonly property var adapter: Connectivity.adapter
    readonly property var devices: adapter?.devices?.values ?? []
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || nameOf(a).localeCompare(nameOf(b)))
    // new devices found by "Search", with a real name (not just an address)
    readonly property var available: devices.filter(d => !d.paired && nameOf(d) !== d.address)

    // stop searching when the panel closes (searching costs battery and radio
    // time for everything connected)
    Component.onDestruction: {
        if (adapter && adapter.discovering)
            adapter.discovering = false;
    }

    function nameOf(device) {
        return device?.name || device?.deviceName || device?.address || "";
    }

    component Heading: Label {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 6
        color: Theme.dim
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.8
    }

    // a small text button: Connect, Disconnect, Search, ...
    component PillButton: Rectangle {
        id: pill
        property string text: ""
        property bool primary: false
        signal clicked
        implicitWidth: pillLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 15
        color: primary ? Theme.accent : pillMouse.containsMouse ? Theme.hover : Theme.card
        border.width: primary ? 0 : 1
        border.color: Theme.cardEdge
        Accessible.role: Accessible.Button
        Accessible.name: text
        Label {
            id: pillLabel
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? Theme.onAccent : Theme.fg
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Label {
                Layout.fillWidth: true
                text: "Bluetooth"
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            ToggleSwitch {
                checked: Connectivity.bluetoothOn
                accessibleName: "Bluetooth"
                onToggled: Connectivity.toggleBluetooth()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: !panel.adapter
            text: "No Bluetooth adapter found"
            color: Theme.dim
            font.pixelSize: 13
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: Connectivity.bluetoothOn
            spacing: 6

            // ── paired devices ────────────────────────────────────────────
            Heading {
                text: "MY DEVICES"
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: panel.paired.length === 0
                text: "No paired devices yet"
                color: Theme.faint
                font.pixelSize: 13
            }
            Repeater {
                model: panel.paired
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 14
                    color: modelData.connected ? Qt.alpha(Theme.accent, 0.14) : Theme.card

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10
                        IconImage {
                            implicitSize: 22
                            source: Quickshell.iconPath(row.modelData.icon, "bluetooth")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: panel.nameOf(row.modelData)
                                font.pixelSize: 13
                                font.weight: row.modelData.connected ? Font.Bold : Font.Medium
                                elide: Text.ElideRight
                            }
                            Label {
                                text: row.busy ? (row.modelData.connected ? "Disconnecting..." : "Connecting...") : row.modelData.connected ? (row.modelData.batteryAvailable ? `Connected · ${Math.round(row.modelData.battery * 100)}%` : "Connected") : "Not connected"
                                color: row.modelData.connected ? Theme.accent : Theme.dim
                                font.pixelSize: 11
                            }
                        }
                        PillButton {
                            text: row.modelData.connected ? "Disconnect" : "Connect"
                            primary: !row.modelData.connected
                            opacity: row.busy ? 0.5 : 1
                            onClicked: {
                                if (row.busy)
                                    return;
                                if (row.modelData.connected)
                                    row.modelData.disconnect();
                                else
                                    row.modelData.connect();
                            }
                        }
                        HoverButton {
                            size: 30
                            iconSize: 15
                            icon: String.fromCodePoint(0xf09e7)  // delete
                            iconColor: Theme.dim
                            accessibleName: "Forget " + panel.nameOf(row.modelData)
                            onClicked: row.modelData.forget()
                        }
                    }
                }
            }

            // ── new devices ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Heading {
                    text: panel.adapter?.discovering ? "AVAILABLE · SEARCHING..." : "AVAILABLE"
                }
                PillButton {
                    text: panel.adapter?.discovering ? "Stop" : "Search"
                    onClicked: panel.adapter.discovering = !panel.adapter.discovering
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: panel.available.length === 0
                text: panel.adapter?.discovering ? "Looking for devices in pairing mode..." : "Put a device in pairing mode, then Search"
                color: Theme.faint
                font.pixelSize: 13
            }
            Repeater {
                model: panel.available
                Rectangle {
                    id: newRow
                    required property var modelData
                    // paired from here: trust it (so it reconnects by itself)
                    // and connect once pairing is done
                    property bool requested: false
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 14
                    color: newMouse.containsMouse ? Theme.hover : "transparent"

                    Connections {
                        target: newRow.modelData
                        function onPairedChanged() {
                            if (newRow.requested && newRow.modelData.paired) {
                                newRow.modelData.trusted = true;
                                newRow.modelData.connect();
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        IconImage {
                            implicitSize: 20
                            source: Quickshell.iconPath(newRow.modelData.icon, "bluetooth")
                        }
                        Label {
                            Layout.fillWidth: true
                            text: panel.nameOf(newRow.modelData)
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Label {
                            text: newRow.modelData.pairing ? "Pairing..." : "Pair"
                            color: Theme.accent
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                    MouseArea {
                        id: newMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (newRow.modelData.pairing)
                                return;
                            newRow.requested = true;
                            newRow.modelData.pair();
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.topMargin: 4
                text: "A device that asks for a PIN code: pair it with bluetoothctl in a terminal."
                color: Theme.faint
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }
}
