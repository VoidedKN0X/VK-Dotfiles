pragma Singleton

// The look of the whole shell: colors, fonts, sizes and the frame around the
// screen. The colors come from ../colors.json, which wallust rewrites at every
// wallpaper change (wallust/templates/colors-quickshell.template). The file is
// watched, so everything recolors at once, without a restart.

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

    // Every color below comes from that palette, so the whole shell follows
    // the wallpaper. Guards keep it readable whatever the wallpaper: text is
    // always light, glass always dark, the accent always bright enough for
    // dark text on it. A black and white wallpaper (wallust then gives only
    // grays) makes the whole shell gray: no hue is made up for it.
    readonly property color rawBg: colors.background ?? "#202021"
    readonly property color rawFg: colors.foreground ?? "#ABB2BF"
    readonly property color rawAccent: colors.color5 ?? "#C678DD"

    // how colorful the palette is: the strongest color among color1-6
    // (saturation times brightness). Below 0.12 it counts as black and white.
    readonly property real colorfulness: {
        let best = 0;
        for (let i = 1; i <= 6; i++) {
            const c = Qt.color(colors["color" + i] ?? "#808080");
            best = Math.max(best, c.hsvSaturation * c.hsvValue);
        }
        return best;
    }
    readonly property bool monochrome: colorfulness < 0.12

    function clamp(v, lo, hi) {
        return Math.min(hi, Math.max(lo, v));
    }
    // (a gray has no hue: -1)
    function hueOf(c) {
        return Math.max(0, c.hslHue);
    }
    function tint(c, maxSaturation) {
        return monochrome ? 0 : Math.min(c.hslSaturation, maxSaturation);
    }

    // wallust's color5, used for everything active (Waybar's @color5).
    // Lightness kept at 60-80 %, so dark text and icons stay readable on it.
    readonly property color accent: monochrome ? Qt.hsla(0, 0, clamp(rawAccent.hslLightness, 0.72, 0.86), 1) : Qt.hsla(hueOf(rawAccent), Math.max(rawAccent.hslSaturation, 0.35), clamp(rawAccent.hslLightness, 0.6, 0.78), 1)
    // text and icons on an accent background: a very dark shade of it
    readonly property color onAccent: Qt.hsla(hueOf(accent), accent.hslSaturation * 0.5, 0.1, 1)

    // text and icons: the palette's foreground, kept light and only slightly
    // tinted
    readonly property color fg: Qt.hsla(hueOf(rawFg), tint(rawFg, 0.2), Math.max(rawFg.hslLightness, 0.85), 1)
    readonly property color dim: Qt.alpha(fg, 0.55)
    readonly property color faint: Qt.alpha(fg, 0.28)
    // power and warnings: red, as bright as the text around it, and as
    // colorful as the wallpaper (a muted red on a black and white one)
    readonly property color warn: Qt.hsla(0.02, monochrome ? 0.3 : 0.62, 0.7, 1)
    readonly property color warnLight: Qt.hsla(0.02, monochrome ? 0.25 : 0.7, 0.82, 1)

    // the background's hue, very dark: the base of all glass
    readonly property color base: Qt.hsla(hueOf(rawBg), tint(rawBg, 0.35), 0.085, 1)
    // solid: behind the wallpaper while it loads, workspace thumbnails
    readonly property color solid: Qt.hsla(hueOf(rawBg), tint(rawBg, 0.35), 0.05, 1)
    // dims what's behind the overview and the switcher's previews
    readonly property color shade: Qt.alpha(solid, 0.6)

    // frosted glass: the bar's islands. Hyprland blurs what's behind it
    // (layer rules in hypr/hyprland/rules.lua)
    readonly property color glass: Qt.alpha(base, 0.48)
    // the frame around the screen and everything that grows out of it (the
    // control center, popups, notifications): one color, so they join
    // without a seam
    readonly property color frame: Qt.alpha(base, 0.72)
    readonly property color panel: frame
    readonly property color edge: Qt.alpha(fg, 0.11)
    // soft highlight along the top edge, like light on frosted glass
    readonly property color highlight: Qt.alpha(fg, 0.07)
    // cards inside the control center and popups
    readonly property color card: Qt.alpha(fg, 0.05)
    readonly property color cardEdge: Qt.alpha(fg, 0.08)
    readonly property color hover: Qt.alpha(fg, 0.08)
    // buttons that are off (round toggles, session buttons)
    readonly property color button: Qt.alpha(fg, 0.06)
    readonly property color buttonHover: Qt.alpha(fg, 0.1)
    // the empty part of sliders and progress bars, switches that are off
    readonly property color track: Qt.alpha(fg, 0.12)

    // ── fonts ─────────────────────────────────────────────────────────────
    // text in Ubuntu, icons from Symbols Nerd Font (both installed by Install.sh)
    readonly property string font: "Ubuntu"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property int fontSize: 14
    readonly property int smallSize: 12
    readonly property int iconSize: 17

    // ── bar sizes ─────────────────────────────────────────────────────────
    readonly property int barHeight: 30     // top bar islands
    readonly property int barWidth: 38      // side bar islands
    readonly property int barEdgeMargin: 8  // islands from the screen edge
    readonly property int barEndMargin: 10  // top bar: left/right, side bars: top/bottom
    readonly property int islandSpacing: 6
    // space between the bar and the tray icons' menus
    readonly property int gap: 14

    // ── the frame ─────────────────────────────────────────────────────────
    // One piece of glass around each screen with a bar: the bar's side holds
    // the islands, the other three sides are a thin border. The desktop inside
    // has round corners, and the popups grow out of the frame's inner edge
    // with rounded joins (bar/Bar.qml, common/FramePanel.qml).
    readonly property int frameBorder: 8
    readonly property int frameRadius: 24   // the desktop's corners
    readonly property int fillet: 22        // where a popup joins the frame
    readonly property int panelRadius: 22   // a popup's outer corners

    // how thick the frame is on one side of a screen whose bar is on barEdge
    function frameSize(barEdge, side) {
        if (side !== barEdge)
            return frameBorder;
        return barEdgeMargin * 2 + (barEdge === "top" ? barHeight : barWidth);
    }
    // from the screen edge on the bar's side to the frame's inner edge
    function offset(edge) {
        return frameSize(edge, edge);
    }
    // a popup at the start or end of a side stays clear of the desktop's
    // round corner
    readonly property int cornerClearance: frameRadius + fillet + 4

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
