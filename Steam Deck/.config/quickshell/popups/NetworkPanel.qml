// Network panel (replaces nmtui): click the bar's network icon or the control
// center's Network toggle. Next to the bar's status island, like the mixer.
// Everything nmtui does, in three pages:
//   main      wired: each cable connection, its state and IP address
//             Wi-Fi (on PCs with Wi-Fi): on / off, the networks around,
//             strongest first; click one to connect, a password field opens
//             when it needs one; disconnect / forget; join a hidden network
//             VPN: each saved VPN / WireGuard connection, on / off
//   settings  (the cog) every saved connection (nmtui's "Edit a connection"),
//             import a VPN (WireGuard .conf, OpenVPN .ovpn), the hostname
//             (nmtui's "Set system hostname")
//   edit      one connection: name, connect automatically, connect /
//             disconnect (nmtui's "Activate a connection"), Wi-Fi password,
//             IPv4 automatic or a static address with gateway, DNS servers,
//             IPv6 on / off, delete
// The Wi-Fi list and switch use Quickshell's Networking module; the rest runs
// nmcli (NetworkManager's own command line tool, like nmtui uses the same
// NetworkManager), and its error is shown when something fails. Changing the
// hostname asks for your password (the shell's polkit dialog).

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
    edge: BarState.edgeFor(shownScreen?.name ?? "") || "top"
    onCloseRequested: BarState.networkScreen = null

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: (wifi?.networks?.values ?? []).slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))

    // "main", "settings" or "edit"
    property string page: "main"
    onTargetScreenChanged: if (targetScreen)
        page = "main"

    // the network whose password field is open
    property var askingPassword: null

    // a message under the current page: what happened, or nmcli's error
    property string status: ""
    property bool statusError: false
    function setStatus(text, isError) {
        status = text.trim().replace(/^Error:\s*/, "");
        statusError = !!isError;
    }
    // to another page, without the last page's message
    function go(target) {
        setStatus("", false);
        page = target;
    }

    // look for Wi-Fi networks only while the panel is open
    onWifiChanged: if (wifi)
        wifi.scannerEnabled = true
    Component.onCompleted: {
        if (wifi)
            wifi.scannerEnabled = true;
        refreshConnections();
    }
    Component.onDestruction: if (wifi)
        wifi.scannerEnabled = false

    // ── running nmcli ────────────────────────────────────────────────────
    // run(["nmcli", ...], (exitCode, stdout, stderr) => ...): one process per
    // command, removed when it's done (after its exit and both outputs)
    Component {
        id: commandComponent
        Process {
            id: proc
            property var callback: null
            property int pending: 3
            property int code: -1
            function step() {
                pending -= 1;
                if (pending === 0) {
                    if (callback)
                        callback(code, out.text, err.text);
                    proc.destroy();
                }
            }
            stdout: StdioCollector {
                id: out
                onStreamFinished: proc.step()
            }
            stderr: StdioCollector {
                id: err
                onStreamFinished: proc.step()
            }
            onExited: exitCode => {
                proc.code = exitCode;
                proc.step();
            }
        }
    }
    function run(command, callback) {
        const process = commandComponent.createObject(panel, {
            command: command,
            callback: callback ?? null
        });
        process.running = true;
    }

    // nmcli -t (terse) output: fields split at ":", with "\:" and "\\"
    // standing for a colon and a backslash in a value
    function splitTerse(line) {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                current += line[i + 1];
                i++;
            } else if (ch === ":") {
                fields.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        fields.push(current);
        return fields;
    }

    // ── saved connections ────────────────────────────────────────────────
    // {name, uuid, type, device, active}, without the loopback one (lo)
    property var connections: []
    readonly property var vpns: connections.filter(c => c.type === "vpn" || c.type === "wireguard")
    function refreshConnections() {
        run(["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE", "connection", "show"], (code, out) => {
            if (code !== 0)
                return;
            panel.connections = out.split("\n").filter(line => line !== "").map(line => {
                const f = panel.splitTerse(line);
                return {
                    name: f[0],
                    uuid: f[1],
                    type: f[2],
                    device: f[3],
                    active: f[4] === "yes"
                };
            }).filter(c => c.type !== "loopback");
        });
    }
    // NetworkManager's changes (a connection up or down, added, removed, from
    // here or elsewhere): the list again, once things settle
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: refreshTimer.restart()
        }
    }
    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: panel.refreshConnections()
    }

    readonly property var typeNames: ({
            "802-3-ethernet": "Wired",
            "802-11-wireless": "Wi-Fi",
            "vpn": "VPN",
            "wireguard": "WireGuard",
            "bridge": "Bridge",
            "bond": "Bond",
            "vlan": "VLAN",
            "tun": "Tunnel",
            "gsm": "Mobile broadband",
            "bluetooth": "Bluetooth"
        })
    function typeName(type) {
        return typeNames[type] ?? type;
    }
    function typeIcon(type) {
        if (type === "802-3-ethernet")
            return Theme.iconEthernet;
        if (type === "802-11-wireless")
            return Theme.iconWifi;
        if (type === "vpn" || type === "wireguard")
            return String.fromCodePoint(0xf0582);  // vpn
        return String.fromCodePoint(0xf0318);  // lan
    }

    // a connection up or down (VPNs on the main page, the editor)
    property string busyUuid: ""
    function setActive(uuid, on) {
        busyUuid = uuid;
        setStatus("", false);
        run(["nmcli", "connection", on ? "up" : "down", uuid], (code, out, err) => {
            panel.busyUuid = "";
            if (code !== 0)
                panel.setStatus(err, true);
            panel.refreshConnections();
        });
    }

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

    // ── building blocks ──────────────────────────────────────────────────
    // (the rest are files in common/: LabeledField, PillButton, ChoiceRow,
    // SwitchRow, PageTitle, StatusLine)
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

        // ═══ main page ═══════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: panel.page === "main"
            spacing: 8

            PageTitle {
                text: "Network"
                onNavigate: page => panel.go(page)
            }

            // ── wired ─────────────────────────────────────────────────────
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

            // ── Wi-Fi ─────────────────────────────────────────────────────
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
                                onVisibleChanged: if (visible)
                                    focusInput()
                            }
                        }
                    }
                }

                // a network that doesn't show its name (nmtui: hidden network)
                Rectangle {
                    id: hidden
                    property bool open: false
                    Layout.fillWidth: true
                    visible: Networking.wifiEnabled
                    implicitHeight: hiddenContent.implicitHeight + 16
                    radius: 14
                    color: hiddenMouse.containsMouse || open ? Theme.hover : "transparent"

                    MouseArea {
                        id: hiddenMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            hidden.open = !hidden.open;
                            if (hidden.open)
                                hiddenSsid.focusInput();
                        }
                    }

                    ColumnLayout {
                        id: hiddenContent
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
                                glyph: String.fromCodePoint(0xf0415)  // plus
                                color: Theme.dim
                                font.pixelSize: 16
                            }
                            Label {
                                Layout.fillWidth: true
                                text: "Hidden network..."
                                color: Theme.dim
                                font.pixelSize: 13
                            }
                        }
                        LabeledField {
                            id: hiddenSsid
                            visible: hidden.open
                            Layout.rightMargin: 4
                            icon: Theme.iconWifi
                            placeholder: "Network name (SSID)"
                            onAccepted: hiddenPassword.focusInput()
                        }
                        LabeledField {
                            id: hiddenPassword
                            visible: hidden.open
                            Layout.rightMargin: 4
                            icon: Theme.iconLock
                            password: true
                            placeholder: "Password (empty for an open network)"
                            onAccepted: hiddenConnect.clicked()
                        }
                        PillButton {
                            id: hiddenConnect
                            visible: hidden.open
                            Layout.alignment: Qt.AlignRight
                            Layout.rightMargin: 4
                            Layout.bottomMargin: 2
                            primary: true
                            text: "Connect"
                            active: hiddenSsid.text.trim() !== ""
                            onClicked: {
                                // nmcli takes the password as an argument
                                // (NetworkManager's own command line way)
                                const command = ["nmcli", "device", "wifi", "connect", hiddenSsid.text.trim()];
                                if (hiddenPassword.text !== "")
                                    command.push("password", hiddenPassword.text);
                                command.push("hidden", "yes");
                                panel.setStatus("Connecting to " + hiddenSsid.text.trim() + "...", false);
                                panel.run(command, (code, out, err) => {
                                    if (code !== 0) {
                                        panel.setStatus(err, true);
                                        return;
                                    }
                                    panel.setStatus("Connected to " + hiddenSsid.text.trim(), false);
                                    hiddenSsid.text = "";
                                    hiddenPassword.text = "";
                                    hidden.open = false;
                                });
                            }
                        }
                    }
                }
            }

            // ── VPN ───────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                visible: panel.vpns.length > 0
                spacing: 6

                Heading {
                    text: "VPN"
                }
                Repeater {
                    model: panel.vpns
                    Rectangle {
                        id: vpn
                        required property var modelData
                        readonly property bool busy: panel.busyUuid === modelData.uuid
                        Layout.fillWidth: true
                        implicitHeight: 54
                        radius: 14
                        color: modelData.active ? Qt.alpha(Theme.accent, 0.14) : Theme.card

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            Glyph {
                                glyph: panel.typeIcon(vpn.modelData.type)
                                color: vpn.modelData.active ? Theme.accent : Theme.fg
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    Layout.fillWidth: true
                                    text: vpn.modelData.name
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: vpn.busy ? (vpn.modelData.active ? "Disconnecting..." : "Connecting...") : vpn.modelData.active ? `${panel.typeName(vpn.modelData.type)} · Connected` : panel.typeName(vpn.modelData.type)
                                    color: vpn.modelData.active ? Theme.accent : Theme.dim
                                    font.pixelSize: 11
                                }
                            }
                            ToggleSwitch {
                                checked: vpn.modelData.active
                                accessibleName: vpn.modelData.name
                                onToggled: if (!vpn.busy)
                                    panel.setActive(vpn.modelData.uuid, !vpn.modelData.active)
                            }
                        }
                    }
                }
            }

            StatusLine {
                message: panel.status
                error: panel.statusError
            }
        }

        // ═══ settings page ═══════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: panel.page === "settings"
            spacing: 8

            PageTitle {
                text: "Connection settings"
                back: "main"
                onNavigate: page => panel.go(page)
            }

            Flickable {
                id: settingsFlick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(settingsColumn.implicitHeight, 560)
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: settingsColumn
                    width: settingsFlick.width
                    spacing: 6

                    // ── every saved connection ────────────────────────────
                    Heading {
                        text: "SAVED CONNECTIONS"
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        visible: panel.connections.length === 0
                        text: "No saved connections"
                        color: Theme.faint
                        font.pixelSize: 13
                    }
                    Repeater {
                        model: panel.connections
                        Rectangle {
                            id: saved
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 50
                            radius: 14
                            color: savedMouse.containsMouse ? Theme.hover : modelData.active ? Qt.alpha(Theme.accent, 0.1) : "transparent"

                            MouseArea {
                                id: savedMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: editor.load(saved.modelData)
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 10
                                Glyph {
                                    glyph: panel.typeIcon(saved.modelData.type)
                                    color: saved.modelData.active ? Theme.accent : Theme.fg
                                    font.pixelSize: 16
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        Layout.fillWidth: true
                                        text: saved.modelData.name
                                        font.pixelSize: 13
                                        font.weight: saved.modelData.active ? Font.Bold : Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: panel.typeName(saved.modelData.type) + (saved.modelData.active ? ` · Connected${saved.modelData.device ? " on " + saved.modelData.device : ""}` : "")
                                        color: saved.modelData.active ? Theme.accent : Theme.dim
                                        font.pixelSize: 11
                                    }
                                }
                                Glyph {
                                    glyph: Theme.iconRight
                                    color: Theme.faint
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }

                    // ── import a VPN ──────────────────────────────────────
                    Heading {
                        text: "IMPORT A VPN"
                    }
                    LabeledField {
                        id: importPath
                        icon: String.fromCodePoint(0xf0582)  // vpn
                        placeholder: "~/Downloads/vpn.conf"
                        label: "A WireGuard .conf or OpenVPN .ovpn file"
                        onAccepted: importButton.clicked()
                    }
                    PillButton {
                        id: importButton
                        Layout.alignment: Qt.AlignRight
                        text: "Import"
                        active: importPath.text.trim() !== ""
                        onClicked: {
                            let path = importPath.text.trim();
                            if (path.startsWith("~"))
                                path = Quickshell.env("HOME") + path.slice(1);
                            const type = path.toLowerCase().endsWith(".ovpn") ? "openvpn" : path.toLowerCase().endsWith(".conf") ? "wireguard" : "";
                            if (type === "") {
                                panel.setStatus("Pick a WireGuard .conf or an OpenVPN .ovpn file", true);
                                return;
                            }
                            panel.run(["nmcli", "connection", "import", "type", type, "file", path], (code, out, err) => {
                                if (code !== 0) {
                                    panel.setStatus(type === "openvpn" && err.indexOf("plugin") >= 0 ? "OpenVPN needs NetworkManager's OpenVPN plugin: sudo pacman -S networkmanager-openvpn" : err, true);
                                    return;
                                }
                                // added: not connected, and not on its own at
                                // login (switch it on in the main page's VPN list)
                                const m = out.match(/\(([0-9a-f-]{36})\)/);
                                if (m) {
                                    panel.run(["nmcli", "connection", "modify", m[1], "connection.autoconnect", "no"], () => panel.run(["nmcli", "connection", "down", m[1]], () => panel.refreshConnections()));
                                }
                                panel.setStatus("VPN imported: switch it on in the VPN list", false);
                                importPath.text = "";
                            });
                        }
                    }

                    // ── the hostname ──────────────────────────────────────
                    Heading {
                        text: "HOSTNAME"
                    }
                    LabeledField {
                        id: hostnameField
                        icon: String.fromCodePoint(0xf0379)  // monitor
                        label: "This PC's name on the network"
                        placeholder: "hostname"
                        onAccepted: hostnameButton.clicked()
                        Component.onCompleted: panel.run(["hostnamectl", "hostname"], (code, out) => {
                            if (code === 0)
                                hostnameField.text = out.trim();
                        })
                    }
                    PillButton {
                        id: hostnameButton
                        Layout.alignment: Qt.AlignRight
                        text: "Save hostname"
                        active: /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostnameField.text.trim())
                        onClicked: {
                            const name = hostnameField.text.trim();
                            panel.run(["hostnamectl", "hostname", name], (code, out, err) => {
                                if (code !== 0)
                                    panel.setStatus(err, true);
                                else
                                    panel.setStatus("Hostname set to " + name, false);
                            });
                        }
                    }

                    StatusLine {
                        message: panel.status
                        error: panel.statusError
                    }
                }
            }
        }

        // ═══ edit page: one connection ═══════════════════════════════════
        ColumnLayout {
            id: editor
            Layout.fillWidth: true
            visible: panel.page === "edit"
            spacing: 8

            // the connection being edited ({name, uuid, type, ...}) and its
            // settings as nmcli shows them ("ipv4.method" -> "auto")
            property var target: null
            property var settings: ({})
            property bool loaded: false
            property bool deleteArmed: false
            readonly property bool hasIp: target !== null && (target.type === "802-3-ethernet" || target.type === "802-11-wireless")
            readonly property bool hasPassword: ["wpa-psk", "sae"].indexOf(settings["802-11-wireless-security.key-mgmt"] ?? "") >= 0
            // the live state of it (connected or not), from the list
            readonly property bool active: target !== null && panel.connections.some(c => c.uuid === target.uuid && c.active)

            function load(connection) {
                target = connection;
                settings = {};
                loaded = false;
                deleteArmed = false;
                panel.setStatus("", false);
                panel.page = "edit";
                panel.run(["nmcli", "-t", "connection", "show", connection.uuid], (code, out, err) => {
                    if (code !== 0) {
                        panel.setStatus(err, true);
                        return;
                    }
                    const s = {};
                    for (const line of out.split("\n")) {
                        if (line === "")
                            continue;
                        const f = panel.splitTerse(line);
                        s[f[0]] = f.slice(1).join(":");
                    }
                    editor.settings = s;
                    nameField.text = s["connection.id"] ?? connection.name;
                    autoconnectRow.checked = s["connection.autoconnect"] === "yes";
                    ipv4Choice.value = s["ipv4.method"] === "manual" ? "manual" : "auto";
                    addressField.text = (s["ipv4.addresses"] ?? "").split(",")[0].trim();
                    gatewayField.text = s["ipv4.gateway"] ?? "";
                    dnsField.text = (s["ipv4.dns"] ?? "").split(",").filter(x => x !== "").join(", ");
                    ignoreDnsRow.checked = s["ipv4.ignore-auto-dns"] === "yes";
                    ipv6Choice.value = s["ipv6.method"] === "disabled" || s["ipv6.method"] === "ignore" ? "disabled" : "auto";
                    passwordField.text = "";
                    editor.loaded = true;
                });
            }

            function save() {
                const s = settings;
                const command = ["nmcli", "connection", "modify", target.uuid, "connection.id", nameField.text.trim(), "connection.autoconnect", autoconnectRow.checked ? "yes" : "no"];
                if (nameField.text.trim() === "") {
                    panel.setStatus("The name can't be empty", true);
                    return;
                }
                if (hasIp) {
                    if (ipv4Choice.value === "manual") {
                        let address = addressField.text.trim();
                        if (!/^\d{1,3}(\.\d{1,3}){3}(\/\d{1,2})?$/.test(address)) {
                            panel.setStatus("Enter the address like 192.168.1.50/24", true);
                            return;
                        }
                        if (address.indexOf("/") < 0)
                            address += "/24";
                        command.push("ipv4.method", "manual", "ipv4.addresses", address, "ipv4.gateway", gatewayField.text.trim());
                    } else if (s["ipv4.method"] === "manual") {
                        command.push("ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "");
                    }
                    const dns = dnsField.text.split(/[\s,]+/).filter(x => x !== "");
                    if (ignoreDnsRow.checked && dns.length === 0) {
                        panel.setStatus("Add a DNS server, or switch off \"Only these DNS servers\"", true);
                        return;
                    }
                    command.push("ipv4.dns", dns.join(","), "ipv4.ignore-auto-dns", ignoreDnsRow.checked ? "yes" : "no");
                    const ipv6Was = s["ipv6.method"] === "disabled" || s["ipv6.method"] === "ignore" ? "disabled" : "auto";
                    if (ipv6Choice.value !== ipv6Was)
                        command.push("ipv6.method", ipv6Choice.value);
                }
                // nmcli takes the password as an argument (NetworkManager's
                // own command line way)
                if (hasPassword && passwordField.text !== "")
                    command.push("wifi-sec.psk", passwordField.text);
                const uuid = target.uuid;
                const wasActive = active;
                panel.setStatus("Saving...", false);
                panel.run(command, (code, out, err) => {
                    if (code !== 0) {
                        panel.setStatus(err, true);
                        return;
                    }
                    passwordField.text = "";
                    if (!wasActive) {
                        panel.refreshConnections();
                        editor.load(Object.assign({}, editor.target, {
                            name: nameField.text.trim()
                        }));
                        panel.setStatus("Saved", false);
                        return;
                    }
                    // connected: again, so the new settings apply now
                    panel.setStatus("Saved, reconnecting...", false);
                    panel.run(["nmcli", "connection", "up", uuid], (code2, out2, err2) => {
                        panel.setStatus(code2 === 0 ? "Saved and reconnected" : "Saved, but reconnecting failed: " + err2.trim().replace(/^Error:\s*/, ""), code2 !== 0);
                        panel.refreshConnections();
                    });
                });
            }

            PageTitle {
                text: editor.target ? editor.target.name : ""
                back: "settings"
                onNavigate: page => panel.go(page)
            }

            Flickable {
                id: editFlick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(editColumn.implicitHeight, 560)
                contentWidth: width
                contentHeight: editColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: editColumn
                    width: editFlick.width
                    spacing: 10

                    Label {
                        Layout.leftMargin: 6
                        visible: !editor.loaded && panel.status === ""
                        text: "Loading..."
                        color: Theme.faint
                        font.pixelSize: 13
                    }

                    // connect / disconnect (nmtui: Activate a connection)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: editor.loaded
                        Layout.leftMargin: 6
                        spacing: 10
                        Label {
                            Layout.fillWidth: true
                            text: editor.target ? panel.typeName(editor.target.type) + (editor.active ? " · Connected" : " · Not connected") : ""
                            color: editor.active ? Theme.accent : Theme.dim
                            font.pixelSize: 12
                        }
                        PillButton {
                            text: panel.busyUuid !== "" && editor.target && panel.busyUuid === editor.target.uuid ? "..." : editor.active ? "Disconnect" : "Connect"
                            primary: !editor.active
                            onClicked: if (panel.busyUuid === "")
                                panel.setActive(editor.target.uuid, !editor.active)
                        }
                    }

                    LabeledField {
                        id: nameField
                        visible: editor.loaded
                        label: "Name"
                        placeholder: "Connection name"
                    }
                    SwitchRow {
                        id: autoconnectRow
                        visible: editor.loaded
                        text: "Connect automatically"
                        hint: "When it's available, also at login"
                    }
                    LabeledField {
                        id: passwordField
                        visible: editor.loaded && editor.hasPassword
                        label: "Wi-Fi password"
                        icon: Theme.iconLock
                        password: true
                        placeholder: "Unchanged"
                    }

                    // ── IPv4 ──────────────────────────────────────────────
                    Heading {
                        visible: editor.loaded && editor.hasIp
                        text: "IPV4"
                    }
                    ChoiceRow {
                        id: ipv4Choice
                        visible: editor.loaded && editor.hasIp
                        options: [
                            {
                                value: "auto",
                                label: "Automatic (DHCP)"
                            },
                            {
                                value: "manual",
                                label: "Manual (static)"
                            }
                        ]
                    }
                    LabeledField {
                        id: addressField
                        visible: editor.loaded && editor.hasIp && ipv4Choice.value === "manual"
                        label: "Address / prefix"
                        placeholder: "192.168.1.50/24"
                    }
                    LabeledField {
                        id: gatewayField
                        visible: editor.loaded && editor.hasIp && ipv4Choice.value === "manual"
                        label: "Gateway (router)"
                        placeholder: "192.168.1.1"
                    }
                    LabeledField {
                        id: dnsField
                        visible: editor.loaded && editor.hasIp
                        label: "DNS servers"
                        placeholder: ipv4Choice.value === "manual" ? "1.1.1.1, 9.9.9.9" : "From the router (or add your own)"
                    }
                    SwitchRow {
                        id: ignoreDnsRow
                        visible: editor.loaded && editor.hasIp
                        text: "Only these DNS servers"
                        hint: "Ignore the ones the router hands out"
                    }

                    // ── IPv6 ──────────────────────────────────────────────
                    Heading {
                        visible: editor.loaded && editor.hasIp
                        text: "IPV6"
                    }
                    ChoiceRow {
                        id: ipv6Choice
                        visible: editor.loaded && editor.hasIp
                        options: [
                            {
                                value: "auto",
                                label: "Automatic"
                            },
                            {
                                value: "disabled",
                                label: "Off"
                            }
                        ]
                    }

                    // ── save / delete ─────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: editor.loaded
                        spacing: 8
                        PillButton {
                            danger: true
                            text: editor.deleteArmed ? "Click again to delete" : "Delete"
                            onClicked: {
                                if (!editor.deleteArmed) {
                                    editor.deleteArmed = true;
                                    return;
                                }
                                panel.run(["nmcli", "connection", "delete", editor.target.uuid], (code, out, err) => {
                                    if (code !== 0) {
                                        panel.setStatus(err, true);
                                        return;
                                    }
                                    panel.refreshConnections();
                                    panel.page = "settings";
                                    panel.setStatus("Deleted " + editor.target.name, false);
                                });
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        PillButton {
                            primary: true
                            text: "Save"
                            onClicked: editor.save()
                        }
                    }

                    StatusLine {
                        message: panel.status
                        error: panel.statusError
                    }
                }
            }
        }
    }
}
