pragma Singleton

// Visualizer levels (cava, scripts/cava.sh): six bars, 0-1 each. Runs only
// while a player has a track, so cava never runs for nothing.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int bars: 6
    property var levels: [0, 0, 0, 0, 0, 0]

    Process {
        running: Media.active
        command: ["sh", Quickshell.shellPath("scripts/cava.sh"), String(root.bars)]
        stdout: SplitParser {
            onRead: line => {
                const values = line.split(";").filter(v => v !== "").map(v => Number(v) / 7);
                if (values.length === root.bars)
                    root.levels = values;
            }
        }
        onRunningChanged: {
            if (!running)
                root.levels = [0, 0, 0, 0, 0, 0];
        }
    }
}
