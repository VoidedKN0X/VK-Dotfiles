// The volume / microphone / brightness / Caps Lock popup (replaces osd.py):
// hypr/scripts/osd.sh changes the level, then shows it here with
//   qs ipc call osd show volume <0-100> <muted 0|1>
//   qs ipc call osd show mic <muted 0|1> ""
//   qs ipc call osd show brightness <0-100> ""
//   qs ipc call osd show caps <on 0|1> ""
// On the focused monitor, a small panel growing out of the right side of the
// frame, in the middle: the icon, a level bar going up and the value. It's
// drawn in the frame's own window (common/FrameHosts.qml), so it's the same
// glass with the same blur. It watches for itself, so it shows whatever
// changed it: the volume and mute (keys, the bar, the mixer, an app, a
// headset's buttons), the microphone's mute and Caps Lock. Gone after 1.2 s;
// holding a key keeps it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

Item {
    id: osd

    property var targetScreen: null
    readonly property string edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"

    property string icon: ""
    property real level: -1     // 0-1, or -1 for no bar (mic, Caps Lock)
    property string valueText: ""
    property bool muted: false
    property bool shown: false

    // in the frame's window of that screen; clicks go through it (it isn't
    // the frame's clickArea)
    parent: FrameHosts.hostFor(targetScreen?.name ?? "")
    visible: parent !== null && progress > 0
    width: parent?.width ?? 0
    height: parent?.height ?? 0

    // grows out of the frame, goes back in when it's done
    property real progress: shown ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    readonly property real base: width - Theme.frameSize(edge, "right")
    readonly property real fullWidth: 64
    readonly property real fullHeight: column.implicitHeight + 32

    FramePanel {
        side: "right"
        base: osd.base
        from: panel.y
        to: panel.y + panel.height
        depth: Math.max(1, panel.width)
    }

    Item {
        id: panel
        clip: true
        width: osd.fullWidth * osd.progress
        height: osd.fullHeight
        x: osd.base - width
        y: (Theme.frameSize(osd.edge, "top") + osd.height - Theme.frameSize(osd.edge, "bottom") - height) / 2

        ColumnLayout {
            id: column
            x: (osd.fullWidth - implicitWidth) / 2
            y: 16
            spacing: 10

            Glyph {
                Layout.alignment: Qt.AlignHCenter
                glyph: osd.icon
                color: osd.muted ? Theme.faint : Theme.accent
                font.pixelSize: 18
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: osd.level >= 0
                implicitWidth: 26
                implicitHeight: 150
                radius: 13
                color: Theme.track
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(parent.width, parent.height * Math.max(0, osd.level))
                    visible: osd.level > 0
                    radius: 13
                    color: osd.muted ? Qt.alpha(Theme.fg, 0.35) : Theme.accent
                    Behavior on height {
                        NumberAnimation {
                            duration: 80
                        }
                    }
                }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: osd.valueText
                color: osd.muted ? Theme.faint : Theme.fg
                font.pixelSize: Theme.smallSize
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // show it on the focused monitor
    function present() {
        const target = BarState.focusedScreen();
        if (target !== osd.targetScreen) {
            osd.shown = false;
            osd.targetScreen = target;
        }
        osd.shown = true;
        hideTimer.restart();
    }

    function showVolume(n, isMuted) {
        osd.muted = isMuted;
        osd.icon = isMuted || n === 0 ? Theme.iconMuted : Theme.iconVolume[Math.min(2, Math.floor(n / 34))];
        osd.level = n / 100;
        osd.valueText = `${n}%`;
        present();
    }

    // the volume changed (any way): show it. Not in the first seconds, while
    // PipeWire reports the starting values.
    property bool ready: false
    Timer {
        interval: 3000
        running: true
        onTriggered: osd.ready = true
    }
    Connections {
        target: Audio
        function onPercentChanged() {
            if (osd.ready)
                osd.showVolume(Audio.percent, Audio.muted);
        }
        function onMutedChanged() {
            if (osd.ready)
                osd.showVolume(Audio.percent, Audio.muted);
        }
        function onMicMutedChanged() {
            if (osd.ready)
                osd.showMic(Audio.micMuted);
        }
    }

    function showMic(isMuted) {
        osd.muted = isMuted;
        osd.icon = isMuted ? Theme.iconMicOff : Theme.iconMic;
        osd.level = -1;
        osd.valueText = isMuted ? "Off" : "On";
        present();
    }

    function showCaps(on) {
        osd.muted = !on;
        osd.icon = Theme.iconCaps;
        osd.level = -1;
        osd.valueText = on ? "On" : "Off";
        present();
    }

    // Caps Lock: the keyboards' Caps Lock lights, read five times a second
    // with bash's own read (only sleep runs in between), printed only when
    // it changes: "1" on, "0" off. The first line is the state at start.
    // Paused while a game runs with GameMode (services/GameMode.qml).
    property bool capsKnown: false
    Process {
        running: !GameMode.active
        // resumed after a game: the first line is the state again, not a change
        onRunningChanged: osd.capsKnown = false
        command: ["bash", "-c", "prev=; while :; do on=0; for f in /sys/class/leds/*::capslock/brightness; do [ -r \"$f\" ] && read -r b < \"$f\" && [ \"$b\" != 0 ] && on=1; done; [ \"$on\" != \"$prev\" ] && echo \"$on\" && prev=$on; sleep 0.2; done"]
        stdout: SplitParser {
            onRead: line => {
                if (osd.capsKnown && osd.ready)
                    osd.showCaps(line.trim() === "1");
                osd.capsKnown = true;
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: osd.shown = false
    }

    IpcHandler {
        target: "osd"

        function show(kind: string, value: string, extra: string): void {
            const n = Math.max(0, Math.min(100, parseInt(value) || 0));
            switch (kind) {
            case "volume":
                osd.muted = extra === "1";
                osd.icon = osd.muted || n === 0 ? Theme.iconMuted : Theme.iconVolume[Math.min(2, Math.floor(n / 34))];
                osd.level = n / 100;
                osd.valueText = `${n}%`;
                break;
            case "mic":
                osd.muted = value === "1";
                osd.icon = osd.muted ? Theme.iconMicOff : Theme.iconMic;
                osd.level = -1;
                osd.valueText = osd.muted ? "Off" : "On";
                break;
            case "brightness":
                osd.muted = false;
                osd.icon = Theme.iconBrightness[Math.min(2, Math.floor(n / 34))];
                osd.level = n / 100;
                osd.valueText = `${n}%`;
                break;
            case "caps":
                osd.muted = value !== "1";
                osd.icon = Theme.iconCaps;
                osd.level = -1;
                osd.valueText = value === "1" ? "On" : "Off";
                break;
            default:
                return;
            }
            osd.present();
        }
    }
}
