// Volume mixer: click the bar's volume icon, or Ctrl + Alt + V. Next to the
// volume icon, like the other popups.
//   output: pick the speakers / headphones, and their volume
//   apps:   a volume slider per app that's playing sound
//   input:  pick the microphone, and its volume
// Click an icon to mute, drag or scroll a slider for the volume.
// Devices (top right) opens pavucontrol on its Configuration tab: there a
// sound card's profile "Off" hides its outputs and inputs (a GPU's HDMI
// outputs, a webcam mic, ...) from this mixer, the bar and every app, and
// picking a profile again shows them. PipeWire (WirePlumber) remembers it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.common
import qs.services
import qs.controlcenter

PopupLayer {
    id: mixer

    name: "vk-mixer"
    place: "end"
    panelWidth: 400
    targetScreen: BarState.mixerScreen
    edge: BarState.edgeFor(shownScreen?.name ?? "") || "top"
    onCloseRequested: BarState.mixerScreen = null

    // pavucontrol on a tab: 1 playback, 2 recording, 3 outputs, 4 inputs,
    // 5 configuration (the sound cards' profiles: "Off" hides a card)
    function openPavucontrol(tab) {
        Quickshell.execDetached(["pavucontrol", "--tab=" + tab]);
        BarState.mixerScreen = null;
    }

    component Heading: Label {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 4
        color: Theme.dim
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.8
    }

    // one device (outputs / inputs): a radio row to pick it
    component DeviceRow: Rectangle {
        id: device
        required property var node
        property bool chosen: false
        signal picked

        Layout.fillWidth: true
        implicitHeight: 40
        radius: 14
        color: chosen ? Qt.alpha(Theme.accent, 0.18) : mouse.containsMouse ? Theme.hover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                implicitWidth: 16
                implicitHeight: 16
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: device.chosen ? Theme.accent : Theme.faint
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    visible: device.chosen
                    color: Theme.accent
                }
            }
            Label {
                Layout.fillWidth: true
                text: Audio.nameOf(device.node)
                color: Theme.fg
                font.pixelSize: 13
                font.weight: device.chosen ? Font.Bold : Font.Medium
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: device.picked()
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 8

        // ── output ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Heading {
                text: "OUTPUT"
            }
            // Devices: show or hide outputs and inputs in pavucontrol
            Rectangle {
                implicitWidth: devicesRow.implicitWidth + 24
                implicitHeight: 28
                radius: 14
                color: devicesMouse.containsMouse ? Theme.hover : Theme.card
                Row {
                    id: devicesRow
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: String.fromCodePoint(0xf0208)
                        color: Theme.accent
                        font.pixelSize: 14
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Devices"
                        color: Theme.fg
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
                MouseArea {
                    id: devicesMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mixer.openPavucontrol(5)
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Show or hide devices in pavucontrol"
            }
        }
        PillSlider {
            Layout.fillWidth: true
            icon: Audio.icon
            label: Audio.sinkName
            value: Audio.volume
            muted: Audio.muted
            onMoved: value => Audio.setVolume(value)
            onIconClicked: Audio.toggleMute()
        }
        Repeater {
            // the devices (if there's more than one to pick from)
            model: Audio.sinks.length > 1 ? Audio.sinks : []
            DeviceRow {
                required property var modelData
                node: modelData
                chosen: modelData === Pipewire.defaultAudioSink
                onPicked: Audio.setDefaultSink(modelData)
            }
        }

        // ── apps ──────────────────────────────────────────────────────────
        Heading {
            text: "APPS"
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: Audio.streams.length === 0
            text: "No apps playing sound"
            color: Theme.faint
            font.pixelSize: 13
        }
        Repeater {
            model: Audio.streams
            ColumnLayout {
                id: app
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 8
                    IconImage {
                        implicitSize: 18
                        source: Quickshell.iconPath(Audio.iconOf(app.modelData), "audio-x-generic")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Audio.mediaOf(app.modelData) !== "" ? `${Audio.nameOf(app.modelData)} · ${Audio.mediaOf(app.modelData)}` : Audio.nameOf(app.modelData)
                        color: Qt.alpha(Theme.fg, 0.8)
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                PillSlider {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    icon: app.modelData.audio?.muted ? Theme.iconMuted : Theme.iconVolume[2]
                    label: ""
                    value: app.modelData.audio?.volume ?? 0
                    muted: app.modelData.audio?.muted ?? false
                    onMoved: value => {
                        if (app.modelData.audio) {
                            app.modelData.audio.muted = false;
                            app.modelData.audio.volume = value;
                        }
                    }
                    onIconClicked: {
                        if (app.modelData.audio)
                            app.modelData.audio.muted = !app.modelData.audio.muted;
                    }
                }
            }
        }

        // ── input ─────────────────────────────────────────────────────────
        Heading {
            text: "INPUT"
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
        Repeater {
            model: Audio.sources.length > 1 ? Audio.sources : []
            DeviceRow {
                required property var modelData
                node: modelData
                chosen: modelData === Pipewire.defaultAudioSource
                onPicked: Audio.setDefaultSource(modelData)
            }
        }
    }
}
