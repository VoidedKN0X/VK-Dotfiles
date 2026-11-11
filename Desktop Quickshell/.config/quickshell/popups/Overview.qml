// Workspace overview (Super + Tab, or a middle click on the bar's workspaces):
// on both monitors at once, every workspace of that monitor as a thumbnail
// with its windows as live previews at their real place and size.
//   click a workspace       go there
//   click a window          focus it (and go to its workspace)
//   drag a window           onto another workspace (also on the other
//                           monitor) to move it there
//   middle-click a window   close it
//   type                    filter the windows by title or app (the others
//                           dim); Enter goes to the first match
//   arrow keys + Enter      pick a workspace on the focused monitor
//   Escape                  clear the search, then close
// This file holds what both monitors share; popups/OverviewScreen.qml is one
// monitor's view.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

Scope {
    id: shared

    // what's typed (shown on the focused monitor)
    property string search: ""
    // Hyprland's windows: address, position, size, workspace, title, class
    property var clients: []
    // where every workspace thumbnail is, in global coordinates, for dropping
    // a dragged window: { "<monitor>:<workspace id>": { id, x, y, w, h } }
    property var dropTargets: ({})
    // the address of the window being dragged ("" when none)
    property string dragging: ""

    readonly property string focusedMonitor: BarState.focusedScreen()?.name ?? ""

    function close() {
        BarState.overviewOpen = false;
    }

    // window positions and sizes: Hyprland's client list, read when it opens,
    // every second while it's open (windows open, close and move) and right
    // after a move
    Process {
        id: reader
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    shared.clients = JSON.parse(text).filter(c => c.mapped !== false && c.workspace?.id > 0);
                } catch (e) {
                    // keep the last list
                }
            }
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: if (!reader.running && shared.dragging === "") reader.running = true
    }
    function refresh() {
        if (!reader.running)
            reader.running = true;
    }

    // the Quickshell handle of a window (live preview, focus, close)
    function toplevelFor(address) {
        return Hyprland.toplevels.values.find(t => "0x" + t.address === address || t.address === address) ?? null;
    }

    function matches(client) {
        const q = search.trim().toLowerCase();
        return q === "" || (client.title ?? "").toLowerCase().includes(q) || (client.class ?? "").toLowerCase().includes(q);
    }

    function goToWorkspace(id) {
        close();
        BarState.focusWorkspace(id);
    }

    function focusWindow(address) {
        const toplevel = toplevelFor(address);
        close();
        WindowHistory.focus(toplevel);
    }

    function closeWindow(address) {
        toplevelFor(address)?.wayland?.close();
        refreshSoon.restart();
    }

    // drop a window on the workspace under the global point (x, y)
    function drop(address, x, y) {
        dragging = "";
        for (const key in dropTargets) {
            const t = dropTargets[key];
            if (x >= t.x && x < t.x + t.w && y >= t.y && y < t.y + t.h) {
                moveWindow(address, t.id);
                return;
            }
        }
    }

    // Hyprland moves the focused window, so focus it first (like
    // Super + Alt + 1-0), then move it; the overview stays open
    function moveWindow(address, workspaceId) {
        const client = clients.find(c => c.address === address);
        if (!client || client.workspace.id === workspaceId)
            return;
        toplevelFor(address)?.wayland?.activate();
        moveTarget = workspaceId;
        moveLater.restart();
    }
    property int moveTarget: 0
    Timer {
        id: moveLater
        interval: 60
        onTriggered: {
            Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.window.move({ workspace = "${shared.moveTarget}" })` : `movetoworkspace ${shared.moveTarget}`);
            refreshSoon.restart();
        }
    }
    Timer {
        id: refreshSoon
        interval: 150
        onTriggered: shared.refresh()
    }

    // one view per monitor with a bar (the mirrored HDMI-A-1 has none)
    Variants {
        // (a list property: copied into an array for filter())
        model: Array.from(Quickshell.screens).filter(s => BarState.edgeFor(s.name) !== "")

        OverviewScreen {
            overview: shared
        }
    }
}
