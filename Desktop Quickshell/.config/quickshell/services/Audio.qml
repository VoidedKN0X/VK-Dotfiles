pragma Singleton

// Speakers and microphone (PipeWire): the bar's volume module, the control
// center's sliders.

import QtQuick
import Quickshell
import Quickshell.Io
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

    // ── devices and apps (the volume mixer) ───────────────────────────────
    // outputs and inputs: hardware and virtual devices, not app streams
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream && !(n.name ?? "").endsWith(".monitor"))
    // apps playing sound
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)

    PwObjectTracker {
        objects: root.sinks.concat(root.sources, root.streams)
    }

    // ── hidden devices ────────────────────────────────────────────────────
    // devices you never use (HDMI outputs of the GPU, a webcam mic, ...):
    // hidden from the mixer's lists (its Edit button), by their PipeWire node
    // name, which stays the same between boots. The device in use always
    // shows. Kept in Quickshell's state folder (~/.local/state/quickshell),
    // so it's per PC and survives a reinstall of the dotfiles.
    property var hidden: []

    FileView {
        id: hiddenFile
        path: Quickshell.statePath("hidden-audio-devices.json")
        printErrors: false
        onLoaded: {
            try {
                const list = JSON.parse(text());
                root.hidden = Array.isArray(list) ? list : [];
            } catch (e) {
                root.hidden = [];
            }
        }
    }

    function isHidden(node) {
        return hidden.includes(node?.name ?? "");
    }
    function setHidden(node, hide) {
        const name = node?.name ?? "";
        if (name === "")
            return;
        const list = hidden.filter(n => n !== name);
        if (hide)
            list.push(name);
        hidden = list;
        hiddenFile.setText(JSON.stringify(list, null, 2) + "\n");
    }

    // what the mixer lists: all but the hidden ones (the one in use stays)
    readonly property var shownSinks: sinks.filter(n => !isHidden(n) || n === Pipewire.defaultAudioSink)
    readonly property var shownSources: sources.filter(n => !isHidden(n) || n === Pipewire.defaultAudioSource)

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // a node's name for people: "Speakers", "Firefox", ...
    function nameOf(node) {
        if (!node)
            return "";
        const props = node.properties ?? {};
        if (node.isStream)
            return props["application.name"] || node.description || node.name;
        return node.nickname || node.description || node.name;
    }
    // what an app is playing ("YouTube - Firefox"), if it says
    function mediaOf(node) {
        return node?.properties?.["media.name"] ?? "";
    }
    // its icon name, for the app's icon
    function iconOf(node) {
        const props = node?.properties ?? {};
        return props["application.icon-name"] || props["application.process.binary"] || "";
    }

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
