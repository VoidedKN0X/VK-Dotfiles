// Wallpaper picker (replaces the rofi one): Super + Shift + W, or the control
// center's toggle. Thumbnails of everything in ~/Pictures/Wallpapers
// (subfolders too), the current one outlined in the accent. Type to search,
// arrow keys to move, Enter or a click to use it: wallpaper.sh shows it and
// wallust recolors everything from it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

PopupLayer {
    id: picker

    name: "vk-wallpaper"
    centered: true
    typing: true
    panelWidth: 720
    targetScreen: BarState.wallpaperScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.wallpaperScreen = null

    readonly property int columns: 3
    readonly property var results: {
        const query = search.text.trim().toLowerCase();
        return Wallpaper.files.filter(f => query === "" || relative(f).toLowerCase().includes(query));
    }

    Component.onCompleted: Wallpaper.refresh()

    // the path under ~/Pictures/Wallpapers
    function relative(file) {
        return file.startsWith(Wallpaper.folder + "/") ? file.slice(Wallpaper.folder.length + 1) : file;
    }

    function choose(file) {
        if (!file)
            return;
        Wallpaper.apply(file);
        BarState.wallpaperScreen = null;
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        SearchField {
            id: search
            Layout.fillWidth: true
            icon: Theme.iconWallpaper
            placeholder: "Search wallpapers..."
            onTextChanged: grid.currentIndex = 0
            onMoveUp: grid.moveCurrentIndexUp()
            onMoveDown: grid.moveCurrentIndexDown()
            onMoveLeft: grid.moveCurrentIndexLeft()
            onMoveRight: grid.moveCurrentIndexRight()
            onAccepted: picker.choose(picker.results[grid.currentIndex])
            onEscaped: picker.closeRequested()
            Component.onCompleted: focusInput()
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            implicitHeight: Math.min(Math.ceil(count / picker.columns), 3) * cellHeight
            cellWidth: width / picker.columns
            cellHeight: cellWidth * 10 / 16 + 28
            clip: true
            model: picker.results
            boundsBehavior: Flickable.StopAtBounds
            // start on the wallpaper in use
            onCountChanged: {
                const at = picker.results.indexOf(Wallpaper.current);
                if (search.text === "" && at >= 0)
                    currentIndex = at;
            }

            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                readonly property bool selected: GridView.isCurrentItem
                readonly property bool inUse: modelData === Wallpaper.current
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: frame
                    anchors.fill: parent
                    anchors.margins: 5
                    anchors.bottomMargin: 28
                    radius: 14
                    color: Theme.card
                    clip: true
                    border.width: cell.selected || cell.inUse ? 3 : 0
                    border.color: cell.selected ? Theme.accent : Qt.alpha(Theme.accent, 0.5)

                    Image {
                        anchors.fill: parent
                        anchors.margins: frame.border.width
                        source: "file://" + cell.modelData
                        // small copies, so a big folder opens quickly
                        sourceSize.width: 320
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }
                Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    height: 20
                    text: picker.relative(cell.modelData)
                    color: cell.selected ? Theme.fg : Theme.dim
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: grid.currentIndex = cell.index
                    onClicked: picker.choose(cell.modelData)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: grid.count === 0
            horizontalAlignment: Text.AlignHCenter
            text: Wallpaper.files.length === 0 ? "No wallpapers in ~/Pictures/Wallpapers" : "No wallpapers found"
            color: Theme.dim
            font.pixelSize: 13
        }
    }
}
