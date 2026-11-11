// The search field at the top of the launcher, wallpaper picker and clipboard
// history (where rofi had its input bar): a glass pill with an icon. Up, down,
// Enter and Escape are passed on to the list under it.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: field

    property alias text: input.text
    property string placeholder: "Search..."
    property string icon: String.fromCodePoint(0xf0349)  // magnify
    property bool password: false

    signal moveUp
    signal moveDown
    signal moveLeft
    signal moveRight
    signal accepted
    signal escaped
    // Ctrl + Delete (clipboard: remove the entry)
    signal deleteRequested

    implicitHeight: 48
    radius: height / 2
    color: Theme.card
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Theme.cardEdge

    function focusInput() {
        input.forceActiveFocus();
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10

        Glyph {
            glyph: field.icon
            color: Theme.accent
        }

        TextInput {
            id: input
            Layout.fillWidth: true
            focus: true
            color: Theme.fg
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            selectedTextColor: Theme.fg
            font.family: Theme.font
            font.pixelSize: 15
            font.weight: Font.Medium
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            echoMode: field.password ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"

            Keys.onUpPressed: field.moveUp()
            Keys.onDownPressed: field.moveDown()
            Keys.onTabPressed: field.moveDown()
            Keys.onBacktabPressed: field.moveUp()
            Keys.onReturnPressed: field.accepted()
            Keys.onEnterPressed: field.accepted()
            Keys.onEscapePressed: field.escaped()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier)) {
                    field.deleteRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left && input.text === "") {
                    field.moveLeft();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right && input.text === "") {
                    field.moveRight();
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: input.text === ""
                text: field.placeholder
                color: Theme.faint
                font: input.font
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
