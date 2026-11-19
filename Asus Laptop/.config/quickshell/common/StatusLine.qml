// A message under a popup's page (the network panel): what happened, in the
// accent color, or an error (error: true) in the warning color. Hidden while
// empty.

import QtQuick
import QtQuick.Layouts

Label {
    property string message: ""
    property bool error: false
    Layout.fillWidth: true
    Layout.leftMargin: 6
    visible: message !== ""
    text: message
    color: error ? Theme.warn : Theme.accent
    font.pixelSize: 12
    wrapMode: Text.Wrap
}
