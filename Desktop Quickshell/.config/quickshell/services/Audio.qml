pragma Singleton

// Speakers and microphone (PipeWire): the bar's volume module, the control
// center's sliders.

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.common

Singleton {
    id: root

    // EasyEffects' virtual sink is the default output while it runs. Like the
    // Waybar volume module ("ignored-sinks"), show and change a real output
    // instead.
    readonly property string ignoredSink: "Easy Effects Sink"

    readonly property PwNode sink: {
        const preferred = Pipewire.defaultAudioSink;
        if (!preferred || preferred.description !== ignoredSink)
            return preferred;
        const real = Pipewire.nodes.values.find(n => n.isSink && !n.isStream && n.audio && n.description !== ignoredSink);
        return real ?? preferred;
    }
    readonly property PwNode source: Pipewire.defaultAudioSource

    // volume and mute are only valid while the nodes are tracked
    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int percent: Math.round(volume * 100)
    readonly property string sinkName: sink?.nickname || sink?.description || "Output"

    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false
    readonly property string sourceName: source?.nickname || source?.description || "Microphone"

    readonly property string icon: muted || percent === 0 ? Theme.iconMuted : Theme.iconVolume[Math.min(2, Math.floor(percent / 34))]

    // capped at 100%, like the volume keys (hypr/scripts/osd.sh)
    function setVolume(value) {
        if (sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(1, value));
        }
    }
    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }
    function setMicVolume(value) {
        if (source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(1, value));
        }
    }
    function toggleMicMute() {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }
}
