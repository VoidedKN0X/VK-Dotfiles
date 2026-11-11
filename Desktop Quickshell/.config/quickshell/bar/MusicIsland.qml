// Music island: the visualizer and the track title (a note icon on a side
// bar). It shows while a player has a title. Hovering slides out the artist
// (top bar) and previous / play-pause / next. Clicking the visualizer or the
// title opens the control center, which has the full player.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

Island {
    id: island

    required property var screen
    required property string edge

    visible: Media.active
    spacing: vertical ? 4 : 0
    clickable: true
    onClicked: BarState.toggleControlCenter(island.screen)

    // ── always there ──────────────────────────────────────────────────────
    CavaBars {
        grow: island.edge === "left" ? "right" : island.edge === "right" ? "left" : "up"
        barLength: island.vertical ? 18 : 12
        Layout.alignment: Qt.AlignCenter
        Layout.rightMargin: island.vertical ? 0 : 4
    }

    BarModule {
        vertical: island.vertical
        icon: island.vertical ? Theme.iconMusic : ""
        // 28 characters at most, like the Waybar module
        text: island.vertical ? "" : island.trim(Media.title, 28)
        onClicked: BarState.toggleControlCenter(island.screen)
    }

    // ── slides out on hover ───────────────────────────────────────────────
    BarModule {
        visible: island.hovered && !island.vertical && Media.artist !== ""
        text: island.trim(Media.artist, 24)
        color: Theme.dim
        onClicked: BarState.toggleControlCenter(island.screen)
    }
    BarModule {
        visible: island.hovered
        vertical: island.vertical
        icon: Theme.iconPrev
        onClicked: Media.previous()
    }
    BarModule {
        visible: island.hovered
        vertical: island.vertical
        icon: Media.playing ? Theme.iconPause : Theme.iconPlay
        color: Theme.accent
        onClicked: Media.togglePlaying()
    }
    BarModule {
        visible: island.hovered
        vertical: island.vertical
        icon: Theme.iconNext
        onClicked: Media.next()
    }

    function trim(text, max) {
        return text.length > max ? text.slice(0, max - 1) + "…" : text;
    }
}
