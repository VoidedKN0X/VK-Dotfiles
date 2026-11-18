// The workspace overview's view (popups/Overview.qml): over the whole focused
// monitor, a dimmed and blurred desktop with that monitor's workspaces
// (BarState.workspaces), each thumbnail in its shape, with the wallpaper and every window at its real place as a live
// preview. It has the search field and takes the keyboard.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.common
import qs.services

PanelWindow {
    id: view

    required property var modelData
    required property var overview

    readonly property var shellScreen: modelData
    readonly property bool focusedHere: true

    // the row of the focused monitor (the one the overview opened on) with
    // its workspaces: { screen, ids, aspect, activeId }. (A list, so it can
    // hold more monitors' rows again.)
    readonly property var monitors: [shellScreen].filter(s => s && BarState.edgeFor(s.name) !== "").map(s => ({
                screen: s,
                ids: BarState.workspaces[s.name] ?? Hyprland.workspaces.values.filter(w => w.monitor?.name === s.name && w.id > 0).map(w => w.id),
                aspect: s.width / Math.max(1, s.height),
                activeId: Hyprland.workspaces.values.find(w => w.monitor?.name === s.name && w.active)?.id ?? -1
            }))
    // every workspace in that order, for the arrow keys
    readonly property var ids: monitors.reduce((all, m) => all.concat(m.ids), [])
    readonly property var activeIds: monitors.map(m => m.activeId)

    // the workspace picked with the arrow keys: the focused one at first
    property int selected: Math.max(0, ids.indexOf(Hyprland.focusedWorkspace?.id ?? -1))

    screen: shellScreen
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    // blurred behind its dimmed background (rules.lua: vk-*); zooms in
    WlrLayershell.namespace: "vk-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // ── layout: every monitor's workspaces in one row, as tall as fits ────
    readonly property int margin: 60
    readonly property int gap: 24
    readonly property int labelHeight: 30
    readonly property int rowLabelHeight: 34
    readonly property int headerHeight: 130
    readonly property real thumbHeight: {
        const areaW = width - margin * 2;
        const areaH = height - headerHeight - margin;
        const rowLabel = monitors.length > 1 ? rowLabelHeight : 0;
        let h = (areaH - monitors.length * (labelHeight + rowLabel + gap)) / Math.max(1, monitors.length);
        for (const m of monitors) {
            const n = Math.max(1, m.ids.length);
            h = Math.min(h, (areaW - (n - 1) * gap) / (n * m.aspect));
        }
        return Math.max(40, Math.floor(h));
    }

    function moveSelection(step) {
        if (ids.length > 0)
            selected = (selected + step + ids.length) % ids.length;
    }

    // to the same place in the row of the other monitor
    function moveRow(step) {
        let start = 0;
        for (let r = 0; r < monitors.length; r++) {
            const n = monitors[r].ids.length;
            if (selected < start + n) {
                const target = monitors[(r + step + monitors.length) % monitors.length];
                const offset = ids.indexOf(target.ids[0]);
                selected = offset + Math.min(selected - start, target.ids.length - 1);
                return;
            }
            start += n;
        }
    }

    function accept() {
        if (overview.search.trim() !== "") {
            const first = overview.clients.find(c => overview.matches(c));
            if (first)
                overview.focusWindow(first.address);
            return;
        }
        overview.goToWorkspace(ids[selected]);
    }

    // the dimmed desktop; a click on it closes the overview
    Rectangle {
        anchors.fill: parent
        color: Theme.shade
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: overview.close()
        }
    }

    // ── header ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.top: parent.top
        anchors.topMargin: 44
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(560, parent.width - 2 * view.margin)
        spacing: 12

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "Workspaces"
            font.pixelSize: 22
            font.weight: Font.Bold
        }
        SearchField {
            id: search
            Layout.fillWidth: true
            placeholder: "Type to find a window..."
            onTextChanged: view.overview.search = text
            onMoveLeft: view.moveSelection(-1)
            onMoveRight: view.moveSelection(1)
            onMoveUp: view.moveRow(-1)
            onMoveDown: view.moveRow(1)
            onAccepted: view.accept()
            onEscaped: {
                if (text !== "")
                    text = "";
                else
                    view.overview.close();
            }
            Component.onCompleted: focusInput()
        }
    }

    // ── the workspaces: a row per monitor ─────────────────────────────────
    ColumnLayout {
        anchors.top: parent.top
        anchors.topMargin: view.headerHeight + 20
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: view.gap

        Repeater {
            model: view.monitors

            ColumnLayout {
                id: monitorRow
                required property var modelData
                readonly property var shown: modelData.screen
                // screen pixels -> thumbnail pixels
                readonly property real zoom: view.thumbHeight / Math.max(1, shown.height)
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                // the monitor's name, when there's more than one row
                Label {
                    visible: view.monitors.length > 1
                    Layout.preferredHeight: view.rowLabelHeight - 8
                    text: monitorRow.shown.name
                    color: Theme.dim
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                RowLayout {
                    spacing: view.gap

                    Repeater {
                        model: monitorRow.modelData.ids

                        ColumnLayout {
                            id: workspace
                            required property int modelData
                            readonly property int index: view.ids.indexOf(modelData)
                            readonly property bool active: modelData === monitorRow.modelData.activeId
                            readonly property bool picked: index === view.selected
                            readonly property var windows: view.overview.clients.filter(c => c.workspace.id === modelData)
                            spacing: 6

                            ClippingRectangle {
                                id: thumb
                                implicitWidth: Math.round(view.thumbHeight * monitorRow.modelData.aspect)
                                implicitHeight: view.thumbHeight
                                radius: 14
                                color: Theme.solid
                                border.width: workspace.active ? 3 : workspace.picked ? 2 : 1
                                border.color: workspace.active || workspace.picked ? Theme.accent : Theme.edge

                                // where it is on the screen, for dropping a dragged window
                                function registerDropTarget() {
                                    const p = thumb.mapToItem(null, 0, 0);
                                    view.overview.dropTargets[`${monitorRow.shown.name}:${workspace.modelData}`] = {
                                        id: workspace.modelData,
                                        x: view.shellScreen.x + p.x,
                                        y: view.shellScreen.y + p.y,
                                        w: thumb.width,
                                        h: thumb.height
                                    };
                                }
                                onWidthChanged: Qt.callLater(registerDropTarget)
                                onXChanged: Qt.callLater(registerDropTarget)
                                onYChanged: Qt.callLater(registerDropTarget)
                                Component.onCompleted: Qt.callLater(registerDropTarget)

                                Image {
                                    anchors.fill: parent
                                    source: Wallpaper.current === "" ? "" : "file://" + Wallpaper.current
                                    sourceSize.width: 640
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: 0.85
                                }

                                // a click on the workspace (not on a window): go there
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.overview.goToWorkspace(workspace.modelData)
                                }

                                Label {
                                    anchors.centerIn: parent
                                    visible: workspace.windows.length === 0
                                    text: "Empty"
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.pixelSize: 13
                                }

                                // the windows, at their real place, as live previews
                                Repeater {
                                    model: workspace.windows

                                    ClippingRectangle {
                                        id: win
                                        required property var modelData
                                        readonly property var toplevel: view.overview.toplevelFor(modelData.address)
                                        readonly property bool dim: !view.overview.matches(modelData)
                                        readonly property bool beingDragged: view.overview.dragging === modelData.address

                                        x: (modelData.at[0] - monitorRow.shown.x) * monitorRow.zoom
                                        y: (modelData.at[1] - monitorRow.shown.y) * monitorRow.zoom
                                        width: Math.max(12, modelData.size[0] * monitorRow.zoom)
                                        height: Math.max(12, modelData.size[1] * monitorRow.zoom)
                                        radius: 6
                                        color: Qt.alpha(Theme.base, 0.9)
                                        border.width: winMouse.containsMouse ? 2 : 1
                                        border.color: winMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.25)
                                        opacity: beingDragged ? 0.35 : dim ? 0.25 : 1
                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 150
                                            }
                                        }

                                        ScreencopyView {
                                            id: preview
                                            anchors.fill: parent
                                            captureSource: win.toplevel?.wayland ?? null
                                            live: true
                                        }
                                        // until the preview is there (or if it can't be): the app's icon
                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: Math.min(32, parent.width / 2, parent.height / 2)
                                            visible: !preview.hasContent
                                            source: Quickshell.iconPath((win.modelData.class ?? "").toLowerCase(), "application-x-executable")
                                        }

                                        MouseArea {
                                            id: winMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            cursorShape: pressed && view.overview.dragging !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            property point pressedAt

                                            onPressed: event => pressedAt = Qt.point(event.x, event.y)
                                            onPositionChanged: event => {
                                                if (!pressed || !(pressedButtons & Qt.LeftButton))
                                                    return;
                                                // a real drag, not a shaky click
                                                if (view.overview.dragging === "" && Math.hypot(event.x - pressedAt.x, event.y - pressedAt.y) > 8)
                                                    view.overview.dragging = win.modelData.address;
                                                if (view.overview.dragging !== "") {
                                                    const p = winMouse.mapToItem(null, event.x, event.y);
                                                    ghost.x = p.x - ghost.width / 2;
                                                    ghost.y = p.y - ghost.height / 2;
                                                    ghost.title = win.modelData.title;
                                                }
                                            }
                                            onReleased: event => {
                                                if (view.overview.dragging !== "") {
                                                    const p = winMouse.mapToItem(null, event.x, event.y);
                                                    view.overview.drop(win.modelData.address, view.shellScreen.x + p.x, view.shellScreen.y + p.y);
                                                    return;
                                                }
                                                if (event.button === Qt.MiddleButton)
                                                    view.overview.closeWindow(win.modelData.address);
                                                else
                                                    view.overview.focusWindow(win.modelData.address);
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.leftMargin: 4
                                spacing: 8
                                Label {
                                    text: `Workspace ${workspace.modelData}`
                                    color: workspace.active ? Theme.accent : Theme.fg
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }
                                Label {
                                    text: workspace.windows.length === 1 ? "1 window" : `${workspace.windows.length} windows`
                                    color: Theme.dim
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // the window under the pointer while dragging
    Rectangle {
        id: ghost
        property string title: ""
        visible: view.overview.dragging !== ""
        width: 180
        height: 44
        radius: 12
        color: Theme.panel
        border.width: 2
        border.color: Theme.accent
        z: 10
        Label {
            anchors.fill: parent
            anchors.margins: 10
            text: ghost.title
            font.pixelSize: 12
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
