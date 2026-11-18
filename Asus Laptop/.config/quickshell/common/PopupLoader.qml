// Loads a popup (common/PopupLayer.qml) while it's open, and keeps it a
// moment after it closes, so it can go back into the frame instead of
// vanishing. screen is where it's open (one of BarState's *Screen
// properties; null: closed).

import QtQuick
import Quickshell

Scope {
    id: root

    property var screen: null
    // the popup, e.g. Component { CalendarPopup {} }
    property Component popup
    // as long as the closing animation (PopupLayer: 220 ms) plus a little
    readonly property int closeTime: 300

    property bool lingering: false
    onScreenChanged: {
        if (screen === null) {
            lingering = true;
            linger.restart();
        } else {
            linger.stop();
            lingering = false;
        }
    }
    Timer {
        id: linger
        interval: root.closeTime
        onTriggered: root.lingering = false
    }

    LazyLoader {
        active: root.screen !== null || root.lingering
        component: root.popup
    }
}
