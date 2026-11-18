// The music player in the control center: visualizer, title, artist and app,
// previous / play-pause / next, and a progress bar (click it to seek).

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.services
import qs.bar

Rectangle {
    id: card

    implicitHeight: content.implicitHeight + 20
    radius: 18
    color: Theme.card

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            CavaBars {
                grow: "up"
                barLength: 26
                barThickness: 4
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: Media.title
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: [Media.artist, Media.app].filter(s => s !== "").join(" · ")
                    color: Theme.dim
                    font.pixelSize: Theme.smallSize
                    elide: Text.ElideRight
                }
            }
            HoverButton {
                size: 36
                icon: Theme.iconPrev
                accessibleName: "Previous"
                onClicked: Media.previous()
            }
            HoverButton {
                icon: Media.playing ? Theme.iconPause : Theme.iconPlay
                iconColor: Theme.onAccent
                fill: Theme.accent
                accessibleName: Media.playing ? "Pause" : "Play"
                onClicked: Media.togglePlaying()
            }
            HoverButton {
                size: 36
                icon: Theme.iconNext
                accessibleName: "Next"
                onClicked: Media.next()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 4
            visible: Media.length > 0
            spacing: 10

            Label {
                text: Media.time(Media.position)
                color: Theme.dim
                font.pixelSize: 11
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.track
                    Rectangle {
                        width: parent.width * Math.min(1, Media.position / Math.max(1, Media.length))
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: Media.canSeek
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => Media.seekTo(event.x / width)
                }
            }
            Label {
                text: Media.time(Media.length)
                color: Theme.dim
                font.pixelSize: 11
            }
        }
    }
}
