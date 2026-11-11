// One notification: its image or app icon, the app and how long ago, the
// title and text, its buttons, and a close button. Clicking it runs its
// default action and closes it (like swaync). Used by the popups and the
// control center's list.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

Rectangle {
    id: card

    required property var notification
    // "now", "5 min", ... (from Notifs.age)
    property string age: ""
    // a popup (in the notification panel) or a card in the control center
    property bool popup: false
    readonly property bool hovered: hover.hovered
    readonly property bool critical: notification?.urgency === NotificationUrgency.Critical

    signal activated
    signal closed
    signal actionInvoked(var action)

    implicitHeight: content.implicitHeight + 24
    radius: 16
    color: Theme.card
    border.width: critical ? 1 : 0
    border.color: critical ? Qt.alpha(Theme.warn, 0.6) : Theme.edge

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // middle click closes, like most notification daemons
        onClicked: event => event.button === Qt.MiddleButton ? card.closed() : card.activated()
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // the notification's own image, else the app's icon
        IconImage {
            readonly property string source_: card.notification?.image || card.iconSource(card.notification?.appIcon ?? "")
            visible: source_ !== ""
            source: source_
            implicitSize: 40
            Layout.alignment: Qt.AlignTop
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label {
                    Layout.fillWidth: true
                    text: card.notification?.appName || "Notification"
                    color: Theme.dim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Label {
                    text: card.age
                    color: Theme.dim
                    font.pixelSize: 11
                }
                HoverButton {
                    size: 22
                    iconSize: 13
                    icon: Theme.iconClose
                    iconColor: Theme.dim
                    accessibleName: "Close"
                    onClicked: card.closed()
                }
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notification?.summary ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notification?.body ?? ""
                textFormat: Text.StyledText
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: 13
                font.weight: Font.Normal
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            // its buttons (all but the default action, which is a click on
            // the card itself)
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                visible: actions.count > 0

                Repeater {
                    id: actions
                    // (a list property: Array methods through .call)
                    model: Array.prototype.filter.call(card.notification?.actions ?? [], a => a.identifier !== "default")

                    Rectangle {
                        required property var modelData
                        implicitWidth: actionLabel.implicitWidth + 24
                        implicitHeight: 32
                        radius: 12
                        color: actionMouse.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Theme.hover

                        Label {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            font.pixelSize: Theme.smallSize
                        }
                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.actionInvoked(parent.modelData)
                        }
                    }
                }
            }
        }
    }

    // an icon name, a path or a file:// url
    function iconSource(icon) {
        if (icon === "")
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.includes("://"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }
}
