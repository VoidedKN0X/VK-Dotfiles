// A small island with one icon: stay awake, notifications, power.

import QtQuick
import qs.common

Island {
    id: island

    property string icon: ""
    property color iconColor: Theme.fg
    property color iconHoverColor: Theme.accent
    // the accent pill of the bell when there are notifications
    property color fill: Theme.glass
    property color hoverFill: fill

    signal rightClicked

    padding: vertical ? 9 : 12
    color: island.hovered ? hoverFill : fill
    clickable: true

    Behavior on color {
        ColorAnimation {
            duration: 300
        }
    }

    BarModule {
        vertical: island.vertical
        icon: island.icon
        color: island.iconColor
        hoverColor: island.iconHoverColor
        implicitWidth: island.vertical ? Theme.barWidth - 2 : 18
        implicitHeight: island.vertical ? 20 : Theme.barHeight - 2
        onClicked: island.clicked()
        onRightClicked: island.rightClicked()
    }
}
