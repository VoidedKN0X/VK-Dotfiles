// The control center (replaces the swaync notification panel): the bell or
// Super + N. From the top:
//   session buttons: lock, suspend, restart, shut down (the last two: click twice)
//   quick toggles:   network, Bluetooth, do not disturb, stay awake, bar position, wallpaper
//   system:          CPU usage, CPU temperature, memory used / total
//   volume and microphone sliders
//   the music player (while one has a track)
//   notifications (folded into one row; click it for the list)
// It fills the whole right side of the frame around the screen (with a side
// bar: the bar's side). A click outside, the bell again or Escape closes it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

PopupLayer {
    id: cc

    name: "vk-control-center"
    // the whole right side of the frame (with a side bar: the bar's side)
    attach: edge === "top" ? "right" : edge
    fullHeight: true
    panelWidth: 410
    targetScreen: BarState.controlCenterScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.controlCenterScreen = null

    // the session action waiting for its second click
    property string pending: ""
    property bool notificationsOpen: false

    Timer {
        id: confirmTimeout
        interval: 3000
        onTriggered: cc.pending = ""
    }

    // for "5 min" in the notification cards
    property real now: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: cc.now = Date.now()
    }

    Flickable {
        width: parent.width
        height: cc.panel.height - cc.padding * 2
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 12

            // ── header + session buttons ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: "Control center"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: cc.pending !== "" ? Session.confirmText[cc.pending] : `${SystemStats.hostname} · up ${SystemStats.uptimeText}`
                        color: cc.pending !== "" ? Theme.warn : Theme.dim
                        font.pixelSize: Theme.smallSize
                        elide: Text.ElideRight
                    }
                }

                Repeater {
                    model: [
                        { action: "lock", icon: Theme.iconLock, name: "Lock" },
                        { action: "suspend", icon: Theme.iconSuspend, name: "Suspend" },
                        { action: "reboot", icon: Theme.iconRestart, name: "Restart" },
                        { action: "poweroff", icon: Theme.iconPower, name: "Shut down", danger: true }
                    ]
                    HoverButton {
                        required property var modelData
                        readonly property bool confirming: cc.pending === modelData.action
                        icon: modelData.icon
                        iconSize: 17
                        accessibleName: modelData.name
                        iconColor: confirming ? Theme.onAccent : modelData.danger ? Theme.warn : Theme.fg
                        fill: confirming ? Theme.warn : modelData.danger ? Qt.alpha(Theme.warn, 0.14) : Theme.button
                        borderColor: modelData.danger ? Qt.alpha(Theme.warn, 0.35) : Theme.buttonHover
                        onClicked: cc.session(modelData.action)
                    }
                }
            }

            // ── quick toggles ─────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 6
                columnSpacing: 0

                RoundToggle {
                    Layout.fillWidth: true
                    icon: Connectivity.networkIcon
                    label: "Network"
                    on: Connectivity.connected
                    // the network panel, like the bar's network icon
                    onClicked: BarState.toggleNetwork(cc.targetScreen)
                }
                RoundToggle {
                    Layout.fillWidth: true
                    icon: Connectivity.bluetoothIcon
                    label: "Bluetooth"
                    on: Connectivity.bluetoothOn
                    onClicked: Connectivity.toggleBluetooth()
                    // the Bluetooth panel (devices, pairing)
                    onRightClicked: BarState.toggleBluetooth(cc.targetScreen)
                }
                RoundToggle {
                    Layout.fillWidth: true
                    icon: Theme.iconBellOff
                    label: "DND"
                    on: Notifs.dnd
                    onClicked: Notifs.dnd = !Notifs.dnd
                }
                RoundToggle {
                    Layout.fillWidth: true
                    icon: Theme.iconAwake
                    label: "Awake"
                    on: BarState.stayAwake
                    onClicked: BarState.stayAwake = !BarState.stayAwake
                }
                RoundToggle {
                    Layout.fillWidth: true
                    icon: BarState.mainEdge === "top" ? Theme.iconBarTop : Theme.iconBarLeft
                    label: BarState.mainEdge === "top" ? "Bar top" : "Bar left"
                    // Super + B; the control center closes, the bars move
                    onClicked: BarState.toggleMainEdge()
                }
                RoundToggle {
                    Layout.fillWidth: true
                    icon: Theme.iconWallpaper
                    label: "Wallpaper"
                    onClicked: BarState.toggleWallpaperPicker(cc.targetScreen)
                }
            }

            // ── system ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: stats.implicitHeight + 28
                radius: 18
                color: Theme.card

                RowLayout {
                    id: stats
                    anchors.fill: parent
                    anchors.margins: 14

                    StatRing {
                        Layout.fillWidth: true
                        value: SystemStats.cpuUsage
                        label: "CPU"
                        detail: "usage"
                    }
                    // the temperature: a reading, not a percentage
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Glyph {
                            Layout.alignment: Qt.AlignHCenter
                            glyph: SystemStats.cpuHot ? Theme.iconTempHot : Theme.iconTemp
                            color: SystemStats.cpuHot ? Theme.warn : Theme.accent
                            font.pixelSize: 22
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 1
                            Label {
                                Layout.alignment: Qt.AlignBaseline
                                text: SystemStats.cpuTemp < 0 ? "--" : Math.round(SystemStats.cpuTemp)
                                color: SystemStats.cpuHot ? Theme.warn : Theme.fg
                                font.pixelSize: 30
                                font.weight: Font.Bold
                            }
                            Label {
                                Layout.alignment: Qt.AlignBaseline
                                text: "°C"
                                color: Qt.alpha(Theme.fg, 0.55)
                                font.pixelSize: 16
                            }
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "CPU temp"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Tctl"
                            color: Theme.dim
                            font.pixelSize: 11
                        }
                    }
                    StatRing {
                        Layout.fillWidth: true
                        value: SystemStats.memUsage
                        label: "Memory"
                        detail: `${SystemStats.memUsed.toFixed(1)} / ${SystemStats.memTotal.toFixed(1)} GiB`
                    }
                }

                // click for btop, like the bar's CPU / memory modules
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cc.openApp(() => Session.btop())
                }
            }

            // ── volume and microphone ─────────────────────────────────────
            PillSlider {
                Layout.fillWidth: true
                icon: Audio.icon
                label: Audio.sinkName
                value: Audio.volume
                muted: Audio.muted
                onMoved: value => Audio.setVolume(value)
                onIconClicked: Audio.toggleMute()
            }
            PillSlider {
                Layout.fillWidth: true
                icon: Audio.micMuted ? Theme.iconMicOff : Theme.iconMic
                label: Audio.sourceName
                value: Audio.micVolume
                muted: Audio.micMuted
                onMoved: value => Audio.setMicVolume(value)
                onIconClicked: Audio.toggleMicMute()
            }

            // ── music ─────────────────────────────────────────────────────
            MediaCard {
                Layout.fillWidth: true
                visible: Media.active
            }

            // ── notifications ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 16
                color: summaryMouse.containsMouse && Notifs.count > 0 ? Theme.hover : Theme.card
                border.width: 1
                border.color: Theme.cardEdge

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        textFormat: Text.StyledText
                        text: Notifs.count === 0 ? `<font color="${Theme.dim}">No notifications</font>` : `<b>${Notifs.count}</b> <font color="${Qt.alpha(Theme.fg, 0.65)}">${Notifs.count === 1 ? "notification" : "notifications"} · ${cc.apps()}</font>`
                    }
                    // clear all, once the list is open
                    Label {
                        visible: cc.notificationsOpen && Notifs.count > 0
                        text: "Clear all"
                        color: Theme.dim
                        font.pixelSize: Theme.smallSize
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.clearAll()
                        }
                    }
                    Glyph {
                        visible: Notifs.count > 0
                        glyph: cc.notificationsOpen ? Theme.iconUp : Theme.iconDown
                        color: Theme.accent
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    id: summaryMouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    enabled: Notifs.count > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cc.notificationsOpen = !cc.notificationsOpen
                }
            }

            Repeater {
                model: cc.notificationsOpen ? Notifs.list : []
                NotificationCard {
                    required property var modelData
                    Layout.fillWidth: true
                    notification: modelData
                    age: Notifs.age(modelData, cc.now)
                    onActivated: Notifs.activate(modelData)
                    onClosed: modelData.dismiss()
                    onActionInvoked: action => Notifs.invoke(modelData, action)
                }
            }
        }
    }

    // lock and suspend run at once; restart and shut down need a second click
    function session(action) {
        if (Session.confirmText[action] && pending !== action) {
            pending = action;
            confirmTimeout.restart();
            return;
        }
        Session.run(action);
    }

    // close the control center, then open an app (so it isn't covered)
    function openApp(open) {
        BarState.controlCenterScreen = null;
        open();
    }

    // "pacman, Element"
    function apps() {
        const names = [];
        for (const n of Notifs.list) {
            const name = n.appName || "Notification";
            if (!names.includes(name))
                names.push(name);
        }
        return names.slice(0, 3).join(", ");
    }
}
