pragma Singleton

// Where each screen's frame window (bar/Bar.qml) keeps its popups: popups
// (common/PopupLayer.qml), the notifications and the volume popup are drawn
// in the frame's own window, so they share its glass and blur. Each frame
// registers an item for its screen here; the popups put themselves in it.

import QtQuick
import Quickshell

Singleton {
    id: root

    // screen name -> the item popups go in
    property var hosts: ({})

    function hostFor(screenName) {
        return root.hosts[screenName] ?? null;
    }

    function register(screenName, item) {
        const next = Object.assign({}, root.hosts);
        next[screenName] = item;
        root.hosts = next;
    }

    function unregister(screenName, item) {
        if (root.hosts[screenName] !== item)
            return;
        const next = Object.assign({}, root.hosts);
        delete next[screenName];
        root.hosts = next;
    }
}
