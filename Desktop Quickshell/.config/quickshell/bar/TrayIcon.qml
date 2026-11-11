// One system tray icon (Steam, Discord, ...): left click opens the app (or
// its menu, for apps that only have a menu), right click opens its menu,
// middle click is the app's second action, scrolling is passed on to it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common

Item {
    id: tray

    required property var modelData
    required property var window
    required property string edge

    readonly property var item: modelData
    readonly property bool vertical: edge !== "top"

    implicitWidth: vertical ? Theme.barWidth - 2 : 24
    implicitHeight: vertical ? 24 : Theme.barHeight - 2
    Layout.alignment: Qt.AlignCenter

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: tray.item.icon
        opacity: mouse.containsMouse ? 1 : 0.9
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                tray.item.secondaryActivate();
            else if (event.button === Qt.RightButton || tray.item.onlyMenu)
                tray.openMenu();
            else
                tray.item.activate();
        }
        onWheel: event => tray.item.scroll(event.angleDelta.y, false)
    }

    // the menu opens next to the bar: under the icon (top bar), beside it
    // (side bars)
    function openMenu() {
        if (!item.hasMenu)
            return;
        const p = window.mapFromItem(tray, 0, 0);
        const x = edge === "top" ? p.x : edge === "left" ? p.x + width + Theme.gap : p.x - Theme.gap;
        const y = edge === "top" ? p.y + height + Theme.gap / 2 : p.y;
        item.display(window, Math.round(x), Math.round(y));
    }
}
