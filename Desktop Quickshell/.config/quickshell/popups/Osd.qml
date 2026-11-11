// The volume / microphone / brightness / Caps Lock popup (replaces osd.py):
// hypr/scripts/osd.sh changes the level, then shows it here with
//   qs ipc call osd show volume <0-100> <muted 0|1>
//   qs ipc call osd show mic <muted 0|1> ""
//   qs ipc call osd show brightness <0-100> ""
//   qs ipc call osd show caps <on 0|1> ""
// On the focused monitor, in the top left corner next to the bar (top right
// next to a right bar), and gone after 1.2 s. Holding a key updates it.

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

    anchors {
        top: true
        left: osd.edge !== "right"
        right: osd.edge === "right"
    }
    margins {
        top: osd.edge === "top" ? Theme.offset("top") : Theme.barEndMargin
        left: osd.edge === "left" ? Theme.offset("left") : osd.edge === "top" ? Theme.barEndMargin : 0
        right: osd.edge === "right" ? Theme.offset("right") : 0
    }
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Rectangle {
        id: pill
        anchors.fill: parent
        implicitWidth: row.implicitWidth + 26
        implicitHeight: 40
        radius: height / 2
        color: Theme.panel
        border.color: Theme.edge
        border.width: 1

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Glyph {
                glyph: osd.icon
                color: osd.muted ? Theme.faint : Theme.fg
                font.pixelSize: 18
            }
            Rectangle {
                visible: osd.level >= 0
                implicitWidth: 100
                implicitHeight: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.14)
                Rectangle {
                    width: parent.width * Math.max(0, osd.level)
                    height: parent.height
                    radius: 2
                    color: osd.muted ? Qt.alpha(Theme.fg, 0.35) : Theme.accent
                    Behavior on width {
                        NumberAnimation {
                            duration: 80
                        }
                    }
                }
            }
            Label {
                text: osd.valueText
                color: osd.muted ? Theme.faint : Theme.fg
                font.pixelSize: Theme.smallSize
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 32
            }
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
