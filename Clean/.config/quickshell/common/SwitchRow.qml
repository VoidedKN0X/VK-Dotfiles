// A setting with a switch on the right (the network panel): text, an
// optional hint under it, checked.

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: switchRow
    property string text: ""
    property string hint: ""
    property bool checked: false
    Layout.fillWidth: true
    Layout.leftMargin: 6
    spacing: 10
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Label {
            Layout.fillWidth: true
            text: switchRow.text
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }
        Label {
            Layout.fillWidth: true
            visible: switchRow.hint !== ""
            text: switchRow.hint
            color: Theme.dim
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
    ToggleSwitch {
        checked: switchRow.checked
        accessibleName: switchRow.text
        onToggled: switchRow.checked = !switchRow.checked
    }
}
