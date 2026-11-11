// Calendar popup: opened and closed by clicking the clock. A month view,
// Monday first, with today in the accent color. The arrows or the scroll
// wheel change the month; clicking the month's name goes back to today.
// Under the clock with the bar on top, next to it with a side bar.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.services

PopupLayer {
    id: popup

    name: "vk-calendar"
    place: "center"
    panelWidth: 320
    targetScreen: BarState.calendarScreen
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: BarState.calendarScreen = null

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // the month shown: 0 = this month, -1 = last month, ...
    property int monthOffset: 0
    readonly property date today: clock.date
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)

    ColumnLayout {
        width: parent.width
        spacing: 10

        // ── today ─────────────────────────────────────────────────────────
        ColumnLayout {
            spacing: 2
            Label {
                text: Qt.formatDateTime(popup.today, "HH:mm")
                font.pixelSize: 34
                font.weight: Font.Bold
            }
            Label {
                text: Qt.formatDateTime(popup.today, "dddd d MMMM yyyy")
                color: Theme.dim
                font.pixelSize: 13
            }
        }

        // ── month ─────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: month.implicitHeight + 24
            color: Theme.card
            radius: 16

            ColumnLayout {
                id: month
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(popup.shown, "MMMM yyyy")
                        font.weight: Font.Bold
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.monthOffset = 0
                        }
                    }
                    HoverButton {
                        icon: Theme.iconLeft
                        size: 32
                        accessibleName: "Previous month"
                        onClicked: popup.monthOffset--
                    }
                    HoverButton {
                        icon: Theme.iconRight
                        size: 32
                        accessibleName: "Next month"
                        onClicked: popup.monthOffset++
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    rowSpacing: 2
                    columnSpacing: 0

                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Label {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.pixelSize: Theme.smallSize
                        }
                    }

                    Repeater {
                        model: popup.days()
                        Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 30

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                radius: 15
                                color: parent.modelData.today ? Theme.accent : "transparent"
                            }
                            Label {
                                anchors.centerIn: parent
                                text: parent.modelData.day
                                font.pixelSize: 13
                                font.weight: parent.modelData.today ? Font.Bold : Font.Normal
                                color: parent.modelData.today ? Theme.onAccent : parent.modelData.inMonth ? Theme.fg : Theme.faint
                            }
                        }
                    }
                }
            }

            WheelHandler {
                onWheel: event => popup.monthOffset += event.angleDelta.y > 0 ? -1 : 1
            }
        }
    }

    // six weeks, Monday first, with the days of the months around it dimmed
    function days() {
        const first = shown;
        const startOffset = (first.getDay() + 6) % 7;  // Monday = 0
        const result = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(first.getFullYear(), first.getMonth(), 1 - startOffset + i);
            result.push({
                day: d.getDate(),
                inMonth: d.getMonth() === first.getMonth(),
                today: d.toDateString() === today.toDateString()
            });
        }
        return result;
    }
}
