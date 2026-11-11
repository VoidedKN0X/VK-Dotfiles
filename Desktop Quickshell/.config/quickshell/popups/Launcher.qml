// App launcher (replaces rofi): tap Super. Type to search, Up / Down to pick,
// Enter or a click to start the app, Escape or Super again to close. Apps you
// start often come first (the counts are kept in Quickshell's state folder,
// ~/.local/state/quickshell). It reads the same .desktop files rofi did, so
// the entries hidden in ~/.local/share/applications stay hidden.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.launcherScreen = null

    readonly property int rows: 8
    readonly property int rowHeight: 48

    // how often each app was started, by its id
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                launcher.usage = JSON.parse(text());
            } catch (e) {
                launcher.usage = {};
            }
        }
    }

    readonly property var results: {
        const query = search.text.trim().toLowerCase();
        const apps = DesktopEntries.applications.values;
        const scored = [];
        for (const app of apps) {
            const s = score(app, query);
            if (s > 0)
                scored.push({
                    app: app,
                    score: s + Math.min(usage[app.id] ?? 0, 50)
                });
        }
        scored.sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name));
        return scored.map(s => s.app);
    }

    // how well an app matches what's typed (0: not at all)
    function score(app, query) {
        if (query === "")
            return 1;
        const name = (app.name ?? "").toLowerCase();
        if (name.startsWith(query))
            return 300;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(query)))
            return 200;
        if (name.includes(query))
            return 150;
        const extra = [app.genericName, app.comment, (app.keywords ?? []).join(" "), (app.categories ?? []).join(" "), app.id].join(" ").toLowerCase();
        return extra.includes(query) ? 60 : 0;
    }

    function launch(app) {
        if (!app)
            return;
        const counts = Object.assign({}, usage);
        counts[app.id] = (counts[app.id] ?? 0) + 1;
        usageFile.setText(JSON.stringify(counts));
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
                    onEntered: list.currentIndex = row.index
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
