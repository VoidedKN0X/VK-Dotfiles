pragma Singleton

// GameMode (Feral): true while a game runs with it. The GameMode hook
// (~/.config/gamemode/hook.sh) sets it with
//   qs ipc call gamemode setActive true|false
// and at start it asks gamemoded itself (Quickshell restarted mid-game; no
// gamemode installed: false). Cava and the Caps Lock check pause while it's
// true.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    Process {
        running: true
        command: ["sh", "-c", "command -v gamemoded >/dev/null && gamemoded -s"]
        stdout: StdioCollector {
            onStreamFinished: root.active = text.indexOf("is active") >= 0
        }
    }

    IpcHandler {
        target: "gamemode"

        function setActive(on: bool): void {
            root.active = on;
        }
    }
}
