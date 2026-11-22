// App launcher (replaces rofi): tap Super. Type to search, Up / Down to pick,
// Enter or a click to start the app, Escape or Super again to close. The apps
// are always in alphabetical order, also while searching (typing only leaves
// out the apps that don't match).
// It reads the same .desktop files rofi did. To hide an app, copy its .desktop
// file to ~/.local/share/applications and add NoDisplay=true under
// [Desktop Entry]; apps with NoDisplay or Hidden aren't listed.
// It's also a calculator: type a sum ("12*21%", "2^10", "sqrt(2)") or a
// conversion ("5 ft to cm", "30 celsius to fahrenheit", "3 GiB to MB",
// "20 EUR to USD") and the answer shows
// above the apps; Enter (or a click on it) copies it and closes. Start with
// "=" to always calculate. It uses qalc (libqalculate).

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

    // ── the calculator ──────────────────────────────────────────────────
    // a sum or a conversion: starts with "=", or starts like one (a number, a
    // bracket, a minus or a maths function) and has an operator (+ - * / ^ %
    // ×), " to " / " in " or a bracket. So "7zip", "4k" or "mp3 to ogg" (an
    // app search) don't count.
    readonly property string query: search.text.trim()
    readonly property bool looksLikeMath: isMath(query)
    function isMath(q) {
        return q.startsWith("=") || (/^([\d.(\-−]|(sqrt|cbrt|ln|sin|cos|tan|abs|round)\()/i.test(q) && /[+\-*\/^%×÷(]|\bto\b|\bin\b/.test(q.slice(1)));
    }
    // qalc's answer to the current query ("" while there's none)
    property string answer: ""
    readonly property bool showAnswer: looksLikeMath && answer !== ""

    // (isMath here, not looksLikeMath: that one may not have caught up with
    // the new text yet when this runs)
    onQueryChanged: {
        answer = "";
        calc.running = false;
        if (isMath(query))
            calcDelay.restart();
        else
            calcDelay.stop();
    }
    // a moment after the last key, not at every key
    Timer {
        id: calcDelay
        interval: 120
        onTriggered: {
            calc.command = ["qalc", "-t", launcher.query.replace(/^=\s*/, "")];
            calc.running = true;
        }
    }
    Process {
        id: calc
        stdout: StdioCollector {
            onStreamFinished: {
                // the last line is the answer; an error, a warning or an
                // answer without a number (a word qalc didn't know) is none
                const lines = text.trim().split("\n").filter(l => l !== "");
                const result = lines.length ? lines[lines.length - 1].trim() : "";
                const bad = result === "" || /^(error|warning)/i.test(result) || !/\d/.test(result);
                launcher.answer = bad || result === launcher.query ? "" : result;
            }
        }
    }
    // the answer to the clipboard (and so the clipboard history), then close
    function copyAnswer() {
        Quickshell.execDetached(["wl-copy", answer]);
        BarState.launcherScreen = null;
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
            onAccepted: launcher.showAnswer ? launcher.copyAnswer() : launcher.launch(launcher.results[list.currentIndex])
            onEscaped: launcher.closeRequested()
            Component.onCompleted: focusInput()
        }

        // the calculator's answer, above the apps
        Rectangle {
            Layout.fillWidth: true
            visible: launcher.showAnswer
            implicitHeight: answerColumn.implicitHeight + 20
            radius: 16
            color: answerMouse.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.22)

            ColumnLayout {
                id: answerColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: "= " + launcher.answer
                    color: Theme.accent
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                Label {
                    Layout.fillWidth: true
                    text: "Enter to copy"
                    color: Theme.dim
                    font.pixelSize: 11
                }
            }
            MouseArea {
                id: answerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: launcher.copyAnswer()
            }
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
            visible: list.count === 0 && !launcher.showAnswer
            horizontalAlignment: Text.AlignHCenter
            text: "No apps found"
            color: Theme.dim
            font.pixelSize: 13
        }
    }
}
