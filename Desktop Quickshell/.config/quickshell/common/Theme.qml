pragma Singleton

// The look of the whole shell: the same glass, text colors, fonts and sizes as
// the Waybar config of the Desktop profile (waybar/style.css there).
// The accent is wallust's color5 from ../colors.json, which wallust rewrites at
// every wallpaper change (wallust/templates/colors-quickshell.template). The
// file is watched, so everything recolors at once, without a restart.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── colors ────────────────────────────────────────────────────────────
    property var colors: ({})

    FileView {
        path: Qt.resolvedUrl("../colors.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.colors = JSON.parse(text());
            } catch (e) {
                // a half-written file while wallust saves: the next change
                // event brings the whole one
            }
        }
    }

    // wallust's accent, used for everything active (Waybar's @color5)
    readonly property color accent: colors.color5 ?? "#C678DD"
    // text on an accent background (Waybar's @color0)
    readonly property color onAccent: colors.color0 ?? "#202021"

    // text and icons stay neutral, so they work on any wallpaper
    readonly property color fg: "#d3d6de"
    readonly property color dim: Qt.rgba(0.827, 0.839, 0.871, 0.55)
    readonly property color faint: Qt.rgba(0.827, 0.839, 0.871, 0.28)
    // fixed red for power and warnings: wallust's color1 isn't always red
    readonly property color warn: "#e07a6c"

    // frosted glass: a dark gray tint with a light edge. Hyprland blurs what's
    // behind it (layer rules in hypr/hyprland/rules.lua)
    readonly property color glass: Qt.rgba(0.082, 0.090, 0.114, 0.48)
    // the control center, popups and menus: a little more solid
    readonly property color panel: Qt.rgba(0.082, 0.090, 0.114, 0.58)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.11)
    // soft highlight along the top edge, like light on frosted glass
    readonly property color highlight: Qt.rgba(1, 1, 1, 0.07)
    // cards inside the control center and popups
    readonly property color card: Qt.rgba(1, 1, 1, 0.05)
    readonly property color cardEdge: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    // the empty part of sliders and progress bars
    readonly property color track: Qt.rgba(0.827, 0.839, 0.871, 0.12)

    // ── fonts ─────────────────────────────────────────────────────────────
    // text in Ubuntu, icons from Symbols Nerd Font (both installed by Install.sh)
    readonly property string font: "Ubuntu"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property int fontSize: 14
    readonly property int smallSize: 12
    readonly property int iconSize: 17

    // ── bar sizes (the Waybar layouts' height, width and margins) ─────────
    readonly property int barHeight: 30     // top bar
    readonly property int barWidth: 38      // side bars
    readonly property int barEdgeMargin: 8  // from the screen edge
    readonly property int barEndMargin: 10  // top bar: left/right, side bars: top/bottom
    readonly property int islandSpacing: 6
    // space between the bar and the popups, control center and volume popup
    readonly property int gap: 14

    // distance from the screen edge (on the bar's side) to a popup's near edge
    function offset(edge) {
        return barEdgeMargin + (edge === "top" ? barHeight : barWidth) + gap;
    }

    // ── icons (Nerd Font Material Design, the same glyphs as Waybar) ──────
    readonly property string iconCpu: String.fromCodePoint(0xf0ee0)
    readonly property string iconTemp: String.fromCodePoint(0xf050f)
    readonly property string iconTempHot: String.fromCodePoint(0xf0e01)
    readonly property string iconMemory: String.fromCodePoint(0xf035b)
    readonly property var iconVolume: [String.fromCodePoint(0xf057f), String.fromCodePoint(0xf0580), String.fromCodePoint(0xf057e)]
    readonly property string iconMuted: String.fromCodePoint(0xf075f)
    readonly property string iconMic: String.fromCodePoint(0xf036c)
    readonly property string iconMicOff: String.fromCodePoint(0xf036d)
    readonly property string iconBluetooth: String.fromCodePoint(0xf00af)
    readonly property string iconBluetoothOff: String.fromCodePoint(0xf00b2)
    readonly property string iconBluetoothConnected: String.fromCodePoint(0xf00b1)
    readonly property string iconEthernet: String.fromCodePoint(0xf0200)
    readonly property string iconWifi: String.fromCodePoint(0xf05a9)
    readonly property string iconOffline: String.fromCodePoint(0xf05aa)
    readonly property string iconAwake: String.fromCodePoint(0xf0176)
    readonly property string iconSleepy: String.fromCodePoint(0xf06ca)
    readonly property string iconBellNew: String.fromCodePoint(0xf116b)
    readonly property string iconBell: String.fromCodePoint(0xf009c)
    readonly property string iconBellOff: String.fromCodePoint(0xf009b)
    readonly property string iconPower: String.fromCodePoint(0xf0425)
    readonly property string iconPrev: String.fromCodePoint(0xf04ae)
    readonly property string iconPause: String.fromCodePoint(0xf03e4)
    readonly property string iconPlay: String.fromCodePoint(0xf040a)
    readonly property string iconNext: String.fromCodePoint(0xf04ad)
    readonly property string iconMusic: String.fromCodePoint(0xf075a)
    readonly property string iconLock: String.fromCodePoint(0xf033e)
    readonly property string iconSuspend: String.fromCodePoint(0xf0904)
    readonly property string iconLogout: String.fromCodePoint(0xf0343)
    readonly property string iconRestart: String.fromCodePoint(0xf0709)
    readonly property string iconCaps: String.fromCodePoint(0xf0632)
    readonly property var iconBrightness: [String.fromCodePoint(0xf00de), String.fromCodePoint(0xf00df), String.fromCodePoint(0xf00e0)]
    readonly property string iconWallpaper: String.fromCodePoint(0xf0e09)
    readonly property string iconBarTop: String.fromCodePoint(0xf1513)
    readonly property string iconBarLeft: String.fromCodePoint(0xf10aa)
    readonly property string iconLeft: String.fromCodePoint(0xf0141)
    readonly property string iconRight: String.fromCodePoint(0xf0142)
    readonly property string iconClose: String.fromCodePoint(0xf0156)
    readonly property string iconDown: String.fromCodePoint(0xf0140)
    readonly property string iconUp: String.fromCodePoint(0xf0143)
}
