// A text field with a small label above it (the network panel's settings):
// common/SearchField.qml with a label. text, placeholder, icon, password;
// accepted on Enter.

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: field
    property alias text: input.text
    property string label: ""
    property string placeholder: ""
    property string icon: String.fromCodePoint(0xf03eb)  // pencil
    property bool password: false
    signal accepted
    function focusInput() {
        input.focusInput();
    }
    Layout.fillWidth: true
    spacing: 4
    Label {
        Layout.leftMargin: 6
        visible: field.label !== ""
        text: field.label
        color: Theme.dim
        font.pixelSize: 11
    }
    SearchField {
        id: input
        Layout.fillWidth: true
        implicitHeight: 40
        icon: field.icon
        placeholder: field.placeholder
        password: field.password
        onAccepted: field.accepted()
    }
}
