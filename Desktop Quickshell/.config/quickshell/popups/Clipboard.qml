// Clipboard history (replaces the rofi one): Super + Shift + H. What you
// copied, newest first (cliphist keeps it). Type to search, Enter or a click
// copies it again, Ctrl + Delete removes the entry.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

PopupLayer {
    id: history

    name: "vk-clipboard"
    // grows out of the bottom of the frame, in the middle
    attach: "bottom"
    place: "center"
    typing: true
    panelWidth: 560
    targetScreen: BarState.clipboardScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.clipboardScreen = null

    readonly property int rows: 9
    readonly property int rowHeight: 44

    // cliphist's lines: "<id>\t<preview>"
    property var entries: []
    readonly property var results: {
        const query = search.text.trim().toLowerCase();
        return entries.filter(e => query === "" || e.toLowerCase().includes(query));
    }

    Process {
        id: lister
        running: true
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: history.entries = text.split("\n").filter(l => l.includes("\t"))
        }
    }

    // the entry's line goes to cliphist on stdin, as rofi passed it
    Process {
        id: remover
        onExited: lister.running = true
    }

    function preview(line) {
        return line.slice(line.indexOf("\t") + 1);
    }
    // cliphist shows images as "[[ binary data 23 KiB png 800x600 ]]"
    function isImage(line) {
        return preview(line).startsWith("[[ binary data");
    }

    function copy(line) {
        if (!line)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", line]);
        BarState.clipboardScreen = null;
    }

    function remove(line) {
        if (!line)
            return;
        remover.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", line];
        remover.running = true;
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        SearchField {
            id: search
            Layout.fillWidth: true
            icon: String.fromCodePoint(0xf0147)  // clipboard
            placeholder: "Search clipboard..."
            onTextChanged: list.currentIndex = 0
            onMoveUp: list.decrementCurrentIndex()
            onMoveDown: list.incrementCurrentIndex()
            onAccepted: history.copy(history.results[list.currentIndex])
            onEscaped: history.closeRequested()
            onDeleteRequested: history.remove(history.results[list.currentIndex])
            Component.onCompleted: focusInput()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            implicitHeight: Math.min(count, history.rows) * history.rowHeight
            clip: true
            model: history.results
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 120

            highlight: Rectangle {
                radius: 14
                color: Qt.alpha(Theme.accent, 0.22)
            }

            delegate: Item {
                id: row
                required property string modelData
                required property int index
                width: list.width
                height: history.rowHeight

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Glyph {
                        glyph: history.isImage(row.modelData) ? String.fromCodePoint(0xf02e9) : String.fromCodePoint(0xf09ee)
                        color: row.ListView.isCurrentItem ? Theme.accent : Theme.dim
                        font.pixelSize: 16
                    }
                    Label {
                        Layout.fillWidth: true
                        text: history.isImage(row.modelData) ? "Image · " + history.preview(row.modelData).replace(/^\[\[ binary data\s*|\s*\]\]$/g, "") : history.preview(row.modelData)
                        font.pixelSize: 13
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: list.currentIndex = row.index
                    onClicked: history.copy(row.modelData)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: list.count === 0
            horizontalAlignment: Text.AlignHCenter
            text: history.entries.length === 0 ? "Nothing copied yet" : "Nothing found"
            color: Theme.dim
            font.pixelSize: 13
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Enter  copy   ·   Ctrl + Delete  remove   ·   Esc  close"
            color: Theme.faint
            font.pixelSize: 11
        }
    }
}
