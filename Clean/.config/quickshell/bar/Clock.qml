// Clock island: "Tue 10 Nov · 21:47:05" in the top bar; hours, minutes and
// seconds stacked with the day under them in a side bar. Click it for the
// calendar popup (popups/CalendarPopup.qml).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

Island {
    id: island

    required property var screen

    padding: vertical ? 12 : 14
    clickable: true
    onClicked: BarState.toggleCalendar(island.screen)

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // top bar: one line
    Row {
        visible: !island.vertical
        spacing: 8
        Layout.alignment: Qt.AlignCenter

        Label {
            text: Qt.formatDateTime(clock.date, "ddd dd MMM")
            color: Qt.alpha(Theme.fg, 0.6)
        }
        Label {
            text: "·"
            color: Qt.alpha(Theme.fg, 0.45)
        }
        Label {
            text: Qt.formatDateTime(clock.date, "HH:mm:ss")
            font.weight: Font.Bold
        }
    }

    // side bars: stacked
    Column {
        visible: island.vertical
        Layout.alignment: Qt.AlignCenter

        Repeater {
            model: ["HH", "mm", "ss"]
            Label {
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, modelData)
                font.weight: Font.Bold
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 2
            text: Qt.formatDateTime(clock.date, "ddd")
            color: Theme.dim
            font.pixelSize: 11
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dd")
            color: Theme.dim
        }
    }
}
