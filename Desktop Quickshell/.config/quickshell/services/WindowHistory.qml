pragma Singleton

// The windows in the order you last used them, for Alt + Tab: every time a
// window gets focus it moves to the front. Windows not focused since
// Quickshell started come after, in Hyprland's order.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // window addresses, most recent first
    property var recent: []

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            const address = Hyprland.activeToplevel?.address ?? "";
            if (address !== "")
                root.recent = [address].concat(root.recent.filter(a => a !== address));
        }
    }

    // the open windows (with a Wayland handle, so they can be shown and
    // focused), most recently used first
    readonly property var windows: {
        const all = Hyprland.toplevels.values.filter(t => t.wayland !== null && t.address !== "");
        const rank = a => {
            const i = recent.indexOf(a);
            return i < 0 ? recent.length : i;
        };
        return all.slice().sort((a, b) => rank(a.address) - rank(b.address));
    }

    function focus(toplevel) {
        // Hyprland switches to its workspace and focuses it
        toplevel?.wayland?.activate();
    }
}
