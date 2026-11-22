pragma Singleton

// The phone paired with KDE Connect (the first one, if there are more): its
// name, whether it's in reach, its battery, and the buttons of the control
// center's phone card. scripts/phone.sh talks to KDE Connect's background
// service over D-Bus and reports every change (checked every 10 s). Without
// KDE Connect, or without a paired phone, present stays false and nothing
// shows.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/phone.sh"

    property string deviceId: ""
    property string name: ""
    property bool reachable: false
    property int charge: -1            // 0-100, -1 unknown
    property bool charging: false
    readonly property bool present: deviceId !== ""

    Process {
        id: watch
        running: true
        command: [root.script, "watch"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const p = JSON.parse(line);
                    root.deviceId = p.id ?? "";
                    root.name = p.name ?? "";
                    root.reachable = p.reachable ?? false;
                    root.charge = p.charge ?? -1;
                    root.charging = p.charging ?? false;
                } catch (e) {}
            }
        }
        // stopped (the shell's config reloaded mid-check, or KDE Connect
        // crashed): again after a moment
        onRunningChanged: if (!running)
            restart.start()
    }
    Timer {
        id: restart
        interval: 15000
        onTriggered: watch.running = true
    }

    function run(action) {
        if (present)
            Quickshell.execDetached([script, action, deviceId]);
    }
    function ring() {
        run("ring");
    }
    function sendClipboard() {
        run("clipboard");
    }
    function browse() {
        run("browse");
    }
    function sendFiles() {
        run("send");
    }
}
