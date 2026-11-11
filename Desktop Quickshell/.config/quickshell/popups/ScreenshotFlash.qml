// A short white flash on every monitor after a screenshot
// (hypr/scripts/screenshot.sh runs `qs ipc call screenshot flash`).

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: flash

    property bool showing: false

    function start() {
        showing = true;
        done.restart();
    }

    Timer {
        id: done
        interval: 320
        onTriggered: flash.showing = false
    }

    Variants {
        model: flash.showing ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            screen: modelData
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            // not vk-*: no blur behind the flash
            WlrLayershell.namespace: "screenshot-flash"
            WlrLayershell.layer: WlrLayer.Overlay
            // clicks go through to the windows under it
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                color: "white"
                opacity: 0
                SequentialAnimation on opacity {
                    running: true
                    NumberAnimation {
                        to: 0.45
                        duration: 60
                    }
                    NumberAnimation {
                        to: 0
                        duration: 240
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
