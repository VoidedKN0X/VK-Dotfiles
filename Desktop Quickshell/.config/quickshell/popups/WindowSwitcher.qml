// Window switcher (Alt + Tab): a live preview of every open window, most
// recently used first, in the middle of the focused monitor. Keep Alt down and
// press Tab to move right (Shift + Tab: left), let go of Alt to switch to the
// selected window. A click switches too; Escape closes it without switching.
// It opens on the previous window, so a quick Alt + Tab flips between the last
// two (like Windows and GNOME).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.common
import qs.services

PopupLayer {
    id: switcher

    name: "vk-switcher"
    centered: true
    typing: true
    // as wide as the cards (248 px + 12 between), at most the screen minus 160 px
    panelWidth: Math.min(Math.max(1, windows.length) * 260 - 12 + padding * 2, (targetScreen?.width ?? 1600) - 160)
    padding: 18
    targetScreen: BarState.switcherScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.switcherScreen = null

    // the windows when it opened (the list doesn't reorder while you pick)
    property var windows: []
    property int selected: 0

    Component.onCompleted: {
        windows = WindowHistory.windows;
        // Alt + Tab: the previous window; Alt + Shift + Tab: the last one
        if (windows.length > 1)
            selected = BarState.switcherFirstStep > 0 ? 1 : windows.length - 1;
    }

    function move(step) {
        if (windows.length > 0)
            selected = (selected + step + windows.length) % windows.length;
    }

    function commit() {
        const target = windows[selected];
        BarState.switcherScreen = null;
        WindowHistory.focus(target);
    }

    Connections {
        target: BarState
        function onSwitcherStep(step) {
            switcher.move(step);
        }
        function onSwitcherCommit() {
            switcher.commit();
        }
    }

    // letting go of Alt switches (this layer has the keyboard while open)
    Item {
        focus: true
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)
                switcher.commit();
        }
        Keys.onReturnPressed: switcher.commit()
        Keys.onEnterPressed: switcher.commit()
        Keys.onRightPressed: switcher.move(1)
        Keys.onLeftPressed: switcher.move(-1)
        Keys.onTabPressed: switcher.move(1)
        Keys.onBacktabPressed: switcher.move(-1)
        Keys.onEscapePressed: switcher.closeRequested()
    }

    Flow {
        id: cards
        width: switcher.panelWidth - switcher.padding * 2
        spacing: 12

        Label {
            visible: switcher.windows.length === 0
            text: "No open windows"
            color: Theme.dim
            font.pixelSize: 13
        }

        Repeater {
            model: switcher.windows

            Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property bool isSelected: index === switcher.selected

                width: 248
                height: 196
                radius: 16
                color: isSelected ? Qt.alpha(Theme.accent, 0.18) : mouse.containsMouse ? Theme.hover : Theme.card
                border.width: isSelected ? 2 : 1
                border.color: isSelected ? Theme.accent : Theme.cardEdge

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // live preview of the window
                    ClippingRectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: Theme.shade
                        ScreencopyView {
                            anchors.centerIn: parent
                            captureSource: card.modelData.wayland
                            live: true
                            constraintSize: Qt.size(parent.width, parent.height)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        IconImage {
                            implicitSize: 18
                            source: Quickshell.iconPath(card.modelData.wayland?.appId ?? "", "application-x-executable")
                        }
                        Label {
                            Layout.fillWidth: true
                            text: card.modelData.title
                            font.pixelSize: 12
                            font.weight: card.isSelected ? Font.Bold : Font.Medium
                            elide: Text.ElideRight
                        }
                        // the workspace it's on
                        Label {
                            text: card.modelData.workspace?.name ?? ""
                            color: Theme.dim
                            font.pixelSize: 11
                        }
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        switcher.selected = card.index;
                        switcher.commit();
                    }
                }
            }
        }
    }
}
