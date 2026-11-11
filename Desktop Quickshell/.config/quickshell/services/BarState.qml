pragma Singleton

// Which monitor gets which bar, where the main bar sits (top or left, Super + B),
// and which popup is open on which monitor.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    // ── monitors ──────────────────────────────────────────────────────────
    // "main": the bar follows mainEdge (top or left, switched with Super + B,
    // so on the OLED it doesn't stay in one place). DP-2 is rotated (portrait)
    // and too narrow for a top bar around a centered clock: always on the
    // right edge. Monitors not listed here (the mirrored HDMI-A-1) get no bar.
    readonly property var outputs: ({
            "DP-1": "main",
            "DP-2": "right"
        })

    // the workspaces each monitor's bar shows: the same split as the workspace
    // rules in hypr/hyprland/monitors.lua
    readonly property var workspaces: ({
            "DP-1": [1, 3, 5, 7, 9],
            "DP-2": [2, 4, 6, 8, 10]
        })

    // the main bar's edge, kept in ../bar-position, so it survives a restart
    // and a reinstall (Install.sh keeps the file)
    property string mainEdge: "top"

    FileView {
        id: positionFile
        path: Qt.resolvedUrl("../bar-position")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.mainEdge = text().trim() === "left" ? "left" : "top"
    }

    // "top", "left", "right", or "" for a monitor without a bar
    function edgeFor(name) {
        const edge = outputs[name];
        if (edge === undefined)
            return "";
        return edge === "main" ? mainEdge : edge;
    }

    function setMainEdge(edge) {
        // the popups were placed next to the old bar: close them
        closeAll();
        mainEdge = edge;
        positionFile.setText(edge + "\n");
    }

    function toggleMainEdge() {
        setMainEdge(mainEdge === "top" ? "left" : "top");
    }

    // ── monitors and focus ────────────────────────────────────────────────
    // the screen Hyprland has focused (where the click or key press happened).
    // A monitor without a bar (the mirror) counts as the main monitor.
    function focusedScreen() {
        // (a list property: copied into an array for find())
        const screens = Array.from(Quickshell.screens);
        const name = Hyprland.focusedMonitor?.name ?? "";
        const focused = screens.find(s => s.name === name && edgeFor(s.name) !== "");
        return focused ?? screens.find(s => outputs[s.name] === "main") ?? screens.find(s => edgeFor(s.name) !== "") ?? screens[0] ?? null;
    }

    // go to a workspace (also one that doesn't exist yet). Hyprland's Lua
    // config takes Lua dispatchers, like the keybinds in hypr/hyprland/keybinds.lua
    function focusWorkspace(target) {
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = "${target}" })` : `workspace ${target}`);
    }

    // ── popups: one open at a time, on one screen ─────────────────────────
    // the control center (bell, Super + N), the calendar (clock) and the
    // power menu (power button): the screen they're open on, or null
    property var controlCenterScreen: null
    property var calendarScreen: null
    property var powerMenuScreen: null
    // stay awake (idle inhibitor): the bar's coffee cup and the control center
    property bool stayAwake: false

    function toggleControlCenter(screen) {
        toggle("controlCenterScreen", screen);
    }
    function toggleCalendar(screen) {
        toggle("calendarScreen", screen);
    }
    function togglePowerMenu(screen) {
        toggle("powerMenuScreen", screen);
    }

    // a second click on the same button closes it; any other popup closes
    function toggle(popup, screen) {
        const target = screen ?? focusedScreen();
        const wasHere = root[popup] !== null && root[popup] === target;
        closeAll();
        if (wasHere)
            return;
        // opened on the next frame, so it's created anew next to that
        // monitor's bar (a layer's name, which sets its slide direction, can't
        // change while it's open)
        Qt.callLater(() => root[popup] = target);
    }

    function closeAll() {
        controlCenterScreen = null;
        calendarScreen = null;
        powerMenuScreen = null;
    }
}
