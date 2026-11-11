// Volume mixer (replaces pavucontrol): click the bar's volume icon, or
// Ctrl + Alt + V. Next to the volume icon, like the other popups.
//   output: pick the speakers / headphones, and their volume
//   apps:   a volume slider per app that's playing sound
//   input:  pick the microphone, and its volume
// Click an icon to mute, drag or scroll a slider for the volume.
// Edit (top right) lists every device with an eye: click one to hide it from
// the lists (a GPU's HDMI outputs, a webcam mic, ...), again to show it.
// Hidden devices are remembered (services/Audio.qml); the one in use always
// shows.

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
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.mixerScreen = null

    // showing every device, to hide or show them
    property bool editing: false

    component Heading: Label {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 4
        color: Theme.dim
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.8
    }

    // one device (outputs / inputs): a radio row to pick it, or while
    // editing an eye to hide / show it
    component DeviceRow: Rectangle {
        id: device
        required property var node
        property bool chosen: false
        readonly property bool hiddenNow: Audio.isHidden(node)
        signal picked

        Layout.fillWidth: true
        implicitHeight: 40
        radius: 14
        color: !mixer.editing && chosen ? Qt.alpha(Theme.accent, 0.18) : mouse.containsMouse && !(mixer.editing && chosen) ? Theme.hover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            // picking: a radio button
            Rectangle {
                visible: !mixer.editing
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
            // editing: an eye, crossed out when hidden
            Glyph {
                visible: mixer.editing
                glyph: device.hiddenNow && !device.chosen ? String.fromCodePoint(0xf0209) : String.fromCodePoint(0xf0208)
                color: device.hiddenNow && !device.chosen ? Theme.faint : Theme.accent
                font.pixelSize: 16
                Layout.preferredWidth: 16
            }
            Label {
                Layout.fillWidth: true
                text: Audio.nameOf(device.node)
                color: mixer.editing && device.hiddenNow && !device.chosen ? Theme.faint : Theme.fg
                font.pixelSize: 13
                font.weight: device.chosen ? Font.Bold : Font.Medium
                elide: Text.ElideRight
            }
            Label {
                visible: mixer.editing
                text: device.chosen ? "In use" : device.hiddenNow ? "Hidden" : "Shown"
                color: device.chosen ? Theme.dim : device.hiddenNow ? Theme.faint : Theme.fg
                font.pixelSize: 11
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            // the device in use can't be hidden
            enabled: !(mixer.editing && device.chosen)
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (mixer.editing)
                    Audio.setHidden(device.node, !device.hiddenNow);
                else
                    device.picked();
            }
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
            // Edit / Done: hide or show devices
            Rectangle {
                implicitWidth: editLabel.implicitWidth + 24
                implicitHeight: 28
                radius: 14
                color: mixer.editing ? Theme.accent : editMouse.containsMouse ? Theme.hover : Theme.card
                Label {
                    id: editLabel
                    anchors.centerIn: parent
                    text: mixer.editing ? "Done" : "Edit"
                    color: mixer.editing ? Theme.onAccent : Theme.fg
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                MouseArea {
                    id: editMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mixer.editing = !mixer.editing
                }
                Accessible.role: Accessible.Button
                Accessible.name: mixer.editing ? "Done hiding devices" : "Hide or show devices"
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: mixer.editing
            text: "Click a device to hide it from the lists, again to show it."
            color: Theme.dim
            font.pixelSize: 12
            wrapMode: Text.Wrap
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
            // every device while editing; otherwise the shown ones (if
            // there's more than one to pick from)
            model: mixer.editing ? Audio.sinks : Audio.shownSinks.length > 1 ? Audio.shownSinks : []
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
            model: mixer.editing ? Audio.sources : Audio.shownSources.length > 1 ? Audio.shownSources : []
            DeviceRow {
                required property var modelData
                node: modelData
                chosen: modelData === Pipewire.defaultAudioSource
                onPicked: Audio.setDefaultSource(modelData)
            }
        }
    }
}
