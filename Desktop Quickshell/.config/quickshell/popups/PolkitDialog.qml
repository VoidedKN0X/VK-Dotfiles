// The password dialog when an app asks for admin rights (replaces
// hyprpolkitagent): what's asking and why, a password field, Cancel and
// Authenticate. Enter confirms, Escape cancels. With the YubiKey login set up
// (Post Install/yubikey-setup.sh) the "touch your key" message shows here too.
// In the middle of the focused monitor, above everything.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.services

PopupLayer {
    id: dialog

    required property var agent
    readonly property var flow: agent.flow

    name: "vk-polkit"
    centered: true
    typing: true
    panelWidth: 420
    padding: 22
    targetScreen: BarState.focusedScreen()
    edge: BarState.edgeFor(targetScreen?.name ?? "") || "top"
    onCloseRequested: flow?.cancelAuthenticationRequest()

    function submit() {
        if (!flow)
            return;
        flow.submit(password.text);
        password.text = "";
    }

    ColumnLayout {
        width: parent.width
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: 24
                color: Qt.alpha(Theme.accent, 0.18)
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 28
                    visible: (dialog.flow?.iconName ?? "") !== ""
                    source: Quickshell.iconPath(dialog.flow?.iconName ?? "", true)
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: (dialog.flow?.iconName ?? "") === ""
                    glyph: String.fromCodePoint(0xf099d)  // shield with a lock
                    color: Theme.accent
                    font.pixelSize: 22
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: "Authentication required"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Label {
                    Layout.fillWidth: true
                    text: dialog.flow?.actionId ?? ""
                    color: Theme.faint
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: dialog.flow?.message ?? ""
            color: Qt.alpha(Theme.fg, 0.85)
            font.pixelSize: 13
            font.weight: Font.Normal
            wrapMode: Text.Wrap
        }

        SearchField {
            id: password
            Layout.fillWidth: true
            icon: Theme.iconLock
            password: !(dialog.flow?.responseVisible ?? false)
            placeholder: (dialog.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
            enabled: dialog.flow?.isResponseRequired ?? false
            opacity: enabled ? 1 : 0.5
            onAccepted: dialog.submit()
            onEscaped: dialog.closeRequested()
            Component.onCompleted: focusInput()
            onEnabledChanged: if (enabled) focusInput()
        }

        // "Please touch the device", or why it failed
        Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: (dialog.flow?.supplementaryMessage ?? "") || (dialog.flow?.failed ? "Wrong password, try again" : "")
            color: (dialog.flow?.supplementaryIsError || dialog.flow?.failed) ? Theme.warn : Theme.dim
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                implicitWidth: 104
                implicitHeight: 44
                radius: 22
                color: cancelMouse.containsMouse ? Theme.hover : Theme.card
                border.width: 1
                border.color: Theme.cardEdge
                Label {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: 13
                }
                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialog.closeRequested()
                }
            }
            Rectangle {
                implicitWidth: 140
                implicitHeight: 44
                radius: 22
                color: Theme.accent
                opacity: password.enabled ? 1 : 0.5
                Label {
                    anchors.centerIn: parent
                    text: "Authenticate"
                    color: Theme.onAccent
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: password.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialog.submit()
                }
            }
        }
    }
}
