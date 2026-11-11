pragma Singleton

// CPU usage, CPU temperature, memory used / total, uptime and hostname, from
// scripts/stats.sh (every 2 seconds).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string hostname: ""
    property real cpuUsage: 0        // 0-100
    property real cpuTemp: -1        // °C, -1 until the sensor is read
    property real memTotal: 0        // GiB
    property real memUsed: 0         // GiB
    readonly property real memUsage: memTotal > 0 ? memUsed / memTotal * 100 : 0
    property int uptime: 0           // seconds
    // the Waybar temperature module's critical-threshold
    readonly property bool cpuHot: cpuTemp >= 80

    // "3d 4h", "4h 12m", "12m"
    readonly property string uptimeText: {
        const d = Math.floor(uptime / 86400);
        const h = Math.floor(uptime % 86400 / 3600);
        const m = Math.floor(uptime % 3600 / 60);
        if (d > 0)
            return `${d}d ${h}h`;
        if (h > 0)
            return `${h}h ${m}m`;
        return `${m}m`;
    }

    // the previous /proc/stat reading, for the usage since then
    property real lastBusy: -1
    property real lastTotal: -1
    // one block of values, applied together at its "end" line
    property var pending: ({})

    Process {
        id: reader
        running: true
        command: ["sh", Quickshell.shellPath("scripts/stats.sh")]
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
        // stopped for some reason (it never ends by itself): start it again
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: reader.running = true
    }

    function parse(line) {
        const f = line.trim().split(/\s+/);
        switch (f[0]) {
        case "host":
            hostname = f[1] ?? "";
            break;
        case "cpu":
            pending.busy = Number(f[1]);
            pending.total = Number(f[2]);
            break;
        case "mem":
            pending.memTotal = Number(f[1]);
            pending.memAvailable = Number(f[2]);
            break;
        case "temp":
            pending.temp = Number(f[1]) / 1000;
            break;
        case "uptime":
            pending.uptime = Number(f[1]);
            break;
        case "end":
            apply(pending);
            pending = {};
            break;
        }
    }

    function apply(v) {
        if (v.total !== undefined) {
            if (lastTotal >= 0 && v.total > lastTotal)
                cpuUsage = Math.max(0, Math.min(100, (v.busy - lastBusy) / (v.total - lastTotal) * 100));
            lastBusy = v.busy;
            lastTotal = v.total;
        }
        if (v.memTotal !== undefined) {
            // kB -> GiB; used = total - available, like Waybar's memory module
            memTotal = v.memTotal / 1048576;
            memUsed = (v.memTotal - v.memAvailable) / 1048576;
        }
        if (v.temp !== undefined)
            cpuTemp = v.temp;
        if (v.uptime !== undefined)
            uptime = v.uptime;
    }
}
