// One module inside an island: an icon with a value next to it (top bar) or
// stacked under it (side bars), lighting up in the accent color on hover like
// Waybar's modules.
//   left click -> clicked(), right click -> rightClicked(), wheel -> scrolled(steps)

import QtQuick
import QtQuick.Layouts
import qs.common

Item {
    id: module

    property bool vertical: false
    property string icon: ""
    property string text: ""
    // a second, dimmer part after the value ("/31G" after the used memory)
    property string subText: ""
    property color color: Theme.fg
    property color hoverColor: Theme.accent
    property bool interactive: true
    readonly property bool hovered: mouse.containsMouse

    signal clicked
    signal rightClicked
    signal middleClicked
    signal scrolled(int steps)

    // Waybar: padding 0 5px between modules (5px 0 on the side bars)
    implicitWidth: vertical ? Theme.barWidth - 2 : content.implicitWidth + 10
    implicitHeight: vertical ? content.implicitHeight + 10 : Theme.barHeight - 2
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.alignment: Qt.AlignCenter

    readonly property color shownColor: interactive && hovered ? hoverColor : color

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: module.vertical ? 1 : 3
        columnSpacing: 5
        rowSpacing: 0

        Glyph {
            visible: module.icon !== ""
            glyph: module.icon
            color: module.shownColor
            Layout.alignment: Qt.AlignHCenter
            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
        Label {
            visible: module.text !== ""
            text: module.text
            color: module.shownColor
            font.pixelSize: module.vertical ? Theme.smallSize : Theme.fontSize
            Layout.alignment: Qt.AlignHCenter
            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
        Label {
            visible: module.subText !== ""
            text: module.subText
            color: Theme.dim
            font.pixelSize: module.vertical ? 10 : Theme.fontSize
            Layout.alignment: Qt.AlignHCenter
            Layout.leftMargin: module.vertical ? 0 : -5
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: module.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                module.rightClicked();
            else if (event.button === Qt.MiddleButton)
                module.middleClicked();
            else
                module.clicked();
        }
        // one step per wheel notch (Waybar's "scroll-step": 1 for the volume)
        property real wheelRest: 0
        onWheel: event => {
            wheelRest += event.angleDelta.y / 120;
            const steps = wheelRest > 0 ? Math.floor(wheelRest) : Math.ceil(wheelRest);
            if (steps !== 0) {
                wheelRest -= steps;
                module.scrolled(steps);
            }
        }
    }
}
