// Network panel (replaces nmtui in the bar and control center): click the
// bar's network icon or the control center's Network toggle. Next to the bar's
// status island, like the mixer.
//   wired:  each cable connection, its state and IP address
//   Wi-Fi:  (on PCs with Wi-Fi: the laptop and Steam Deck profiles) on / off,
//           the networks around, strongest first; click one to connect, a
//           password field opens when it needs one; disconnect / forget
// nmtui is still installed (NetworkManager): "More settings" opens it for VPNs
// and static addresses.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.common
import qs.services

PopupLayer {
    id: panel

    name: "vk-network"
    place: "end"
    panelWidth: 400
    targetScreen: BarState.networkScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.networkScreen = null

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: (wifi?.networks?.values ?? []).slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))

    // the network whose password field is open
    property var askingPassword: null

    // look for Wi-Fi networks only while the panel is open
    onWifiChanged: if (wifi) wifi.scannerEnabled = true
    Component.onCompleted: if (wifi) wifi.scannerEnabled = true
    Component.onDestruction: if (wifi) wifi.scannerEnabled = false

    // the IPv4 addresses, by interface ("eno1" -> "192.168.1.20")
    property var addresses: ({})
    Process {
        running: true
        command: ["ip", "-4", "-o", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const m = line.match(/^\d+:\s+(\S+)\s+inet\s+([\d.]+)/);
                    if (m && !(m[1] in found))
                        found[m[1]] = m[2];
                }
                panel.addresses = found;
            }
        }
    }

    function signalIcon(strength) {
        const icons = [0xf091f, 0xf0922, 0xf0925, 0xf0928];
        return String.fromCodePoint(icons[Math.min(3, Math.floor(strength * 4))]);
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

    ColumnLayout {
        width: parent.width
        spacing: 8

        Label {
            Layout.leftMargin: 4
            text: "Network"
            font.pixelSize: 16
            font.weight: Font.Bold
        }

        // ── wired ─────────────────────────────────────────────────────────
        Repeater {
            model: panel.wired
            Rectangle {
                id: wire
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 54
                radius: 14
                color: modelData.connected ? Qt.alpha(Theme.accent, 0.14) : Theme.card

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12
                    Glyph {
                        glyph: wire.modelData.connected ? Theme.iconEthernet : Theme.iconOffline
                        color: wire.modelData.connected ? Theme.accent : Theme.faint
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            text: `Ethernet · ${wire.modelData.name}`
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Label {
                            text: wire.modelData.connected ? (panel.addresses[wire.modelData.name] ? `Connected · ${panel.addresses[wire.modelData.name]}` : "Connected") : "Cable unplugged or not connected"
                            color: wire.modelData.connected ? Theme.accent : Theme.dim
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // ── Wi-Fi ─────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: panel.wifi !== null
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Heading {
                    text: "WI-FI"
                }
                ToggleSwitch {
                    checked: Networking.wifiEnabled
                    accessibleName: "Wi-Fi"
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: !Networking.wifiHardwareEnabled
                text: "Wi-Fi is switched off with a hardware switch or key"
                color: Theme.warn
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: Networking.wifiEnabled && panel.networks.length === 0
                text: "Looking for networks..."
                color: Theme.faint
                font.pixelSize: 13
            }

            Repeater {
                model: Networking.wifiEnabled ? panel.networks : []
                Rectangle {
                    id: net
                    required property var modelData
                    readonly property bool asking: panel.askingPassword === modelData
                    property bool failed: false
                    Layout.fillWidth: true
                    implicitHeight: content.implicitHeight + 16
                    radius: 14
                    color: modelData.connected ? Qt.alpha(Theme.accent, 0.14) : netMouse.containsMouse || asking ? Theme.hover : "transparent"

                    Connections {
                        target: net.modelData
                        function onConnectionFailed(reason) {
                            // it needs a password (or the saved one is wrong)
                            if (reason === ConnectionFailReason.NoSecrets) {
                                net.failed = net.asking;
                                panel.askingPassword = net.modelData;
                            }
                        }
                        function onConnectedChanged() {
                            if (net.modelData.connected && net.asking)
                                panel.askingPassword = null;
                        }
                    }

                    MouseArea {
                        id: netMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!net.modelData.connected && !net.modelData.stateChanging)
                                net.modelData.connect();
                        }
                    }

                    ColumnLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        anchors.leftMargin: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Glyph {
                                glyph: panel.signalIcon(net.modelData.signalStrength)
                                color: net.modelData.connected ? Theme.accent : Theme.fg
                                font.pixelSize: 16
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    Layout.fillWidth: true
                                    text: net.modelData.name
                                    font.pixelSize: 13
                                    font.weight: net.modelData.connected ? Font.Bold : Font.Medium
                                    elide: Text.ElideRight
                                }
                                Label {
                                    visible: text !== ""
                                    text: net.modelData.stateChanging ? "Connecting..." : net.modelData.connected ? "Connected" : net.modelData.known ? "Saved" : ""
                                    color: net.modelData.connected ? Theme.accent : Theme.dim
                                    font.pixelSize: 11
                                }
                            }
                            Label {
                                visible: net.modelData.connected
                                text: "Disconnect"
                                color: Theme.dim
                                font.pixelSize: 12
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: net.modelData.disconnect()
                                }
                            }
                            HoverButton {
                                visible: net.modelData.known
                                size: 28
                                iconSize: 14
                                icon: String.fromCodePoint(0xf09e7)  // delete
                                iconColor: Theme.dim
                                accessibleName: "Forget " + net.modelData.name
                                onClicked: net.modelData.forget()
                            }
                        }

                        // the password, when the network asks for one
                        SearchField {
                            id: password
                            Layout.fillWidth: true
                            Layout.rightMargin: 4
                            Layout.bottomMargin: 2
                            visible: net.asking
                            implicitHeight: 42
                            icon: Theme.iconLock
                            password: true
                            placeholder: net.failed ? "Wrong password, try again" : "Password"
                            onAccepted: {
                                net.modelData.connectWithPsk(password.text);
                                password.text = "";
                            }
                            onEscaped: panel.askingPassword = null
                            onVisibleChanged: if (visible) focusInput()
                        }
                    }
                }
            }
        }

        // nmtui for what the panel doesn't do (VPN, static IP, ...)
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 4
            text: "More settings (VPN, static IP) in nmtui"
            color: Theme.dim
            font.pixelSize: 12
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    BarState.networkScreen = null;
                    Session.networkSettings();
                }
            }
        }
    }
}
