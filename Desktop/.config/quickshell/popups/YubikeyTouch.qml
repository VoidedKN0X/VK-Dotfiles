// "Touch your YubiKey": while the key waits for a touch (services/YubiKey.qml:
// sudo or a login with pam-u2f, a website, SSH, GPG signing, challenge-
// response), a small panel grows out of the top of the frame on the focused
// monitor, in the middle (under the clock with the bar on top), saying what's
// asking, with a ring pulsing around the key. When the key stops waiting
// (touched, cancelled or timed out) it goes back in. Like the volume popup,
// it's drawn in the frame's own window (common/FrameHosts.qml): the same glass,
// and clicks go through it. The bar shows a blinking key icon at the same
// time (bar/StatusIsland.qml), for the other monitor.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

Item {
    id: touch

    property var targetScreen: null
    readonly property string edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"

    // in the frame's window of that screen
    parent: FrameHosts.hostFor(targetScreen?.name ?? "")
    visible: parent !== null && progress > 0
    width: parent?.width ?? 0
    height: parent?.height ?? 0

    // on the monitor that's focused when the key starts waiting
    Connections {
        target: YubiKey
        function onWaitingChanged() {
            if (YubiKey.waiting && touch.progress === 0)
                touch.targetScreen = BarState.focusedScreen();
        }
    }

    // grows out of the frame, goes back in when it's done
    property real progress: YubiKey.waiting ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    readonly property real base: Theme.frameSize(edge, "top")
    readonly property real fullWidth: 320
    readonly property real fullHeight: content.implicitHeight + 36

    FramePanel {
        side: "top"
        base: touch.base
        from: panel.x
        to: panel.x + panel.width
        depth: Math.max(1, panel.height)
    }

    Item {
        id: panel
        clip: true
        width: touch.fullWidth
        height: touch.fullHeight * touch.progress
        x: (touch.width - width) / 2
        y: touch.base

        // the content slides down out of the frame with the panel
        RowLayout {
            id: content
            x: 22
            y: panel.height - touch.fullHeight + 18
            width: touch.fullWidth - 44
            spacing: 18

            // the key, with a ring pulsing out of it
            Item {
                implicitWidth: 56
                implicitHeight: 56

                Repeater {
                    model: 2
                    Rectangle {
                        id: ring
                        required property int index
                        anchors.centerIn: parent
                        width: 56
                        height: 56
                        radius: 28
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        opacity: 0
                        SequentialAnimation {
                            running: touch.visible
                            loops: Animation.Infinite
                            PauseAnimation {
                                duration: ring.index * 800
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: ring
                                    property: "scale"
                                    from: 0.7
                                    to: 1.35
                                    duration: 1600
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: ring
                                    property: "opacity"
                                    from: 0.9
                                    to: 0
                                    duration: 1600
                                    easing.type: Easing.OutCubic
                                }
                            }
                            PauseAnimation {
                                duration: (1 - ring.index) * 800
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 46
                    height: 46
                    radius: 23
                    color: Qt.alpha(Theme.accent, 0.18)
                    Glyph {
                        anchors.centerIn: parent
                        glyph: String.fromCodePoint(0xf0306)  // key
                        color: Theme.accent
                        font.pixelSize: 22
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: "Touch your YubiKey"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: YubiKey.reason
                    color: Theme.dim
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "The key is blinking"
                    color: Theme.accent
                    font.pixelSize: 11
                }
            }
        }
    }
}
