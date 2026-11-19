// The title row of a popup with pages (the network panel): a back arrow when
// back names the page to go back to, else a cog for the settings page.
// navigate(page) asks the popup to go there.

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: titleRow
    property string text: ""
    property string back: ""     // the page the arrow goes back to
    signal navigate(string page)
    Layout.fillWidth: true
    spacing: 6
    HoverButton {
        visible: titleRow.back !== ""
        size: 30
        iconSize: 16
        icon: Theme.iconLeft
        accessibleName: "Back"
        onClicked: titleRow.navigate(titleRow.back)
    }
    Label {
        Layout.fillWidth: true
        Layout.leftMargin: titleRow.back === "" ? 4 : 0
        text: titleRow.text
        font.pixelSize: 16
        font.weight: Font.Bold
        elide: Text.ElideRight
    }
    HoverButton {
        visible: titleRow.back === ""
        size: 30
        iconSize: 16
        icon: String.fromCodePoint(0xf0493)  // cog
        iconColor: Theme.dim
        accessibleName: "Connection settings"
        onClicked: titleRow.navigate("settings")
    }
}
