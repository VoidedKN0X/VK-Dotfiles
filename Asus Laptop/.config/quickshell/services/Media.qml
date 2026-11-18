pragma Singleton

// The music player shown in the bar's music island and the control center
// (MPRIS, the same players playerctl sees): the one that's playing, otherwise
// the first one with a track. Hidden while no player has a title.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying && p.trackTitle) ?? players.find(p => p.trackTitle) ?? null;
    }
    readonly property bool active: player !== null && player.trackTitle !== ""
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string app: player?.identity ?? ""
    readonly property real length: player?.length ?? 0
    readonly property bool canSeek: (player?.canSeek ?? false) && (player?.positionSupported ?? false) && length > 0
    // MPRIS doesn't announce position changes: updated every second below
    property real position: 0

    Timer {
        running: root.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }
    onPlayerChanged: position = player?.position ?? 0

    function togglePlaying() {
        if (player?.canTogglePlaying)
            player.togglePlaying();
    }
    function next() {
        if (player?.canGoNext)
            player.next();
    }
    function previous() {
        if (player?.canGoPrevious)
            player.previous();
    }
    function seekTo(fraction) {
        if (canSeek) {
            player.position = Math.max(0, Math.min(1, fraction)) * length;
            position = player.position;
        }
    }

    // "2:14"
    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }
}
