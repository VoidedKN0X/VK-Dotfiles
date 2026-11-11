// The volume / microphone / brightness / Caps Lock popup (replaces osd.py):
// hypr/scripts/osd.sh changes the level, then shows it here with
//   qs ipc call osd show volume <0-100> <muted 0|1>
//   qs ipc call osd show mic <muted 0|1> ""
//   qs ipc call osd show brightness <0-100> ""
//   qs ipc call osd show caps <on 0|1> ""
// On the focused monitor, a small panel growing out of the right side of the
// frame (Theme "the frame"), in the middle: the icon, a level bar going up
// and the value. Gone after 1.2 s; holding a key updates it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: osd

    property var targetScreen: null
    readonly property string edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"

    property string icon: ""
    property real level: -1     // 0-1, or -1 for no bar (mic, Caps Lock)
    property string valueText: ""
    property bool muted: false

    screen: targetScreen
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vk-osd"
    WlrLayershell.layer: WlrLayer.Overlay

    // only anchored right: in the middle of the right side
    anchors.right: true
    margins.right: Theme.frameSize(osd.edge, "right")
    implicitWidth: 64
    implicitHeight: column.implicitHeight + 32 + Theme.fillet * 2
    // it only shows; clicks go through it
    mask: Region {}

    FramePanel {
        side: "right"
        base: osd.width
        from: Theme.fillet
        to: osd.height - Theme.fillet
        depth: osd.width
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
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

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: osd.visible = false
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
            // on the focused monitor; moving it means hiding it first
            const target = BarState.focusedScreen();
            if (target !== osd.targetScreen) {
                osd.visible = false;
                osd.targetScreen = target;
            }
            osd.visible = true;
            hideTimer.restart();
        }
    }
}
