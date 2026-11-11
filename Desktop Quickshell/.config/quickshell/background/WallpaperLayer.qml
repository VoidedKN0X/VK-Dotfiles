// The wallpaper of one monitor (replaces awww): on the background layer,
// cropped to fill the screen, fading over from the previous one when it
// changes. GIFs play.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: wall

    required property var modelData

    screen: modelData
    color: Theme.solid
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    // not named vk-*: Hyprland's blur rule for the shell is for the glass
    WlrLayershell.namespace: "wallpaper"
    WlrLayershell.layer: WlrLayer.Background

    // two images: the new one fades in over the old one
    property bool frontIsA: true

    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            wall.show(Wallpaper.current);
        }
    }
    Component.onCompleted: {
        a.source = Wallpaper.current === "" ? "" : "file://" + Wallpaper.current;
        a.opacity = 1;
    }

    function show(file) {
        const next = frontIsA ? b : a;
        const prev = frontIsA ? a : b;
        next.opacity = 0;
        next.source = file === "" ? "" : "file://" + file;
        next.z = 1;
        prev.z = 0;
        frontIsA = !frontIsA;
        fade.target = next;
        fade.restart();
    }

    NumberAnimation {
        id: fade
        property: "opacity"
        from: 0
        to: 1
        duration: 600
        easing.type: Easing.InOutQuad
    }

    AnimatedImage {
        id: a
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(wall.modelData.width, wall.modelData.height)
        asynchronous: true
        cache: false
        opacity: 0
    }
    AnimatedImage {
        id: b
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(wall.modelData.width, wall.modelData.height)
        asynchronous: true
        cache: false
        opacity: 0
    }
}
