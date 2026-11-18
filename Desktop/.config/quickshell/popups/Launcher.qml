// App launcher (replaces rofi): tap Super. Type to search, Up / Down to pick,
// Enter or a click to start the app, Escape or Super again to close. The apps
// are always in alphabetical order, also while searching (typing only leaves
// out the apps that don't match).
// It reads the same .desktop files rofi did. To hide an app, copy its .desktop
// file to ~/.local/share/applications and add NoDisplay=true under
// [Desktop Entry]; apps with NoDisplay or Hidden aren't listed.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.services

PopupLayer {
    id: launcher

    name: "vk-launcher"
    // grows out of the bottom of the frame, in the middle
    attach: "bottom"
    place: "center"
    typing: true
    panelWidth: 480
    targetScreen: BarState.launcherScreen
    edge: BarState.edgeFor(shownScreen?.name ?? "") || "top"
    onCloseRequested: BarState.launcherScreen = null

    readonly property int rows: 8
    readonly property int rowHeight: 48
    // where the mouse last was (scene position): see the rows' MouseArea
    property point lastMouse: Qt.point(-1, -1)

    // the matching apps, A to Z (case and accents ignored, numbers in order:
    // "App 2" before "App 10")
    readonly property var results: {
        const query = search.text.trim().toLowerCase();
        return DesktopEntries.applications.values.filter(app => matches(app, query)).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? "", undefined, {
                sensitivity: "base",
                numeric: true
            }));
    }

    // whether an app matches what's typed: its name, or its description,
    // keywords, categories or id
    function matches(app, query) {
        if (query === "")
            return true;
        const text = [app.name, app.genericName, app.comment, (app.keywords ?? []).join(" "), (app.categories ?? []).join(" "), app.id].join(" ").toLowerCase();
        return text.includes(query);
    }

    function launch(app) {
        if (!app)
            return;
        if (app.runInTerminal)
            Session.inTerminal(app.command);
        else
            app.execute();
        BarState.launcherScreen = null;
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        SearchField {
            id: search
            Layout.fillWidth: true
            placeholder: "Search apps..."
            onTextChanged: list.currentIndex = 0
            onMoveUp: list.decrementCurrentIndex()
            onMoveDown: list.incrementCurrentIndex()
            onAccepted: launcher.launch(launcher.results[list.currentIndex])
            onEscaped: launcher.closeRequested()
            Component.onCompleted: focusInput()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            implicitHeight: Math.min(count, launcher.rows) * launcher.rowHeight
            clip: true
            model: launcher.results
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 120
            // every row made up front (their icons too), so scrolling never
            // waits for icons to load
            cacheBuffer: Math.max(0, count * launcher.rowHeight)

            // the mouse wheel: three apps per notch, gliding there in 150 ms
            // (Qt's own wheel scrolling moves only a few pixels per notch; on
            // Wayland a wheel notch also has a small pixelDelta, which the
            // last version used, so it still crawled). Touchpads (a scroll
            // phase) scroll by their own distance.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const touchpad = event.phase !== Qt.NoScrollPhase || event.angleDelta.y === 0;
                    const dy = touchpad ? event.pixelDelta.y : event.angleDelta.y / 120 * 3 * launcher.rowHeight;
                    const from = glide.running ? glide.to : list.contentY;
                    const to = Math.max(0, Math.min(list.contentHeight - list.height, from - dy));
                    glide.stop();
                    if (touchpad) {
                        list.contentY = to;
                    } else {
                        glide.from = list.contentY;
                        glide.to = to;
                        glide.start();
                    }
                    event.accepted = true;
                }
            }
            NumberAnimation {
                id: glide
                target: list
                property: "contentY"
                duration: 150
                easing.type: Easing.OutCubic
            }

            highlight: Rectangle {
                radius: 16
                color: Qt.alpha(Theme.accent, 0.22)
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: launcher.rowHeight

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    IconImage {
                        implicitSize: 32
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.pixelSize: 14
                            font.weight: row.ListView.isCurrentItem ? Font.Bold : Font.Medium
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: row.modelData.genericName || row.modelData.comment || ""
                            color: Theme.dim
                            font.pixelSize: 11
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // only when the mouse itself moves: rows scrolling under a
                    // still mouse don't move the selection (that made the list
                    // jump back to keep the selected row in view)
                    onPositionChanged: mouse => {
                        const p = mapToItem(null, mouse.x, mouse.y);
                        if (p.x !== launcher.lastMouse.x || p.y !== launcher.lastMouse.y) {
                            launcher.lastMouse = p;
                            list.currentIndex = row.index;
                        }
                    }
                    onClicked: launcher.launch(row.modelData)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: list.count === 0
            horizontalAlignment: Text.AlignHCenter
            text: "No apps found"
            color: Theme.dim
            font.pixelSize: 13
        }
    }
}
