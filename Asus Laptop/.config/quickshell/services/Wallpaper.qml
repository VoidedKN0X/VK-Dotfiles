pragma Singleton

// The wallpaper (replaces awww): the one in hypr/colors/current-wallpaper.conf,
// which hypr/scripts/wallpaper.sh writes and the lock screen reads too, and
// the list of wallpapers in ~/Pictures/Wallpapers for the picker.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string folder: home + "/Pictures/Wallpapers"
    // the script that shows a wallpaper and makes the colors from it
    readonly property string applyScript: home + "/.config/hypr/scripts/wallpaper.sh"

    // the file shown now ("" before one is picked)
    property string current: ""

    FileView {
        path: root.home + "/.config/hypr/colors/current-wallpaper.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // "$current_wallpaper = /home/axel/Pictures/Wallpapers/x.png"
            const match = text().match(/^\$current_wallpaper\s*=\s*(.+)$/m);
            const path = match ? match[1].trim() : "";
            // the repo's default is "screenshot" (for the lock screen): no file
            root.current = path.startsWith("/") ? path : "";
        }
    }

    // all wallpapers, sorted (the same files wallpaper.sh looks for)
    property var files: []

    Process {
        id: finder
        command: ["find", root.folder, "-type", "f", "-iregex", ".*\\.\\(jpg\\|jpeg\\|png\\|gif\\)"]
        stdout: StdioCollector {
            onStreamFinished: root.files = text.split("\n").filter(f => f !== "").sort()
        }
    }

    // read the folder again (each time the picker opens)
    function refresh() {
        finder.running = true;
    }

    function apply(file) {
        Quickshell.execDetached([applyScript, file]);
    }
}
