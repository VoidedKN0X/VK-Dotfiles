pragma Singleton

// The screen's backlight (laptops, the Steam Deck), through brightnessctl:
// the control center's slider and the brightness keys (hypr/scripts/osd.sh).
// On a PC without a backlight (desktop monitors) available is false and the
// slider is hidden.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property int percent: 0          // 0-100

    // read the level: brightnessctl -m gives "device,class,current,percent%,max"
    function refresh() {
        if (!reader.running)
            reader.running = true;
    }
    // never all the way to 0 (a black screen)
    function set(value) {
        const p = Math.max(5, Math.min(100, Math.round(value * 100)));
        percent = p;
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", `${p}%`]);
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",");
                root.available = parts.length >= 4;
                if (root.available)
                    root.percent = parseInt(parts[3]) || 0;
            }
        }
    }
    Component.onCompleted: refresh()
    // the keys, the lid or the power settings can change it too: read it
    // again now and then (only where there is a backlight)
    Timer {
        interval: 2000
        repeat: true
        running: root.available
        onTriggered: root.refresh()
    }
}
