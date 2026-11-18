// System island: CPU usage, CPU temperature and memory usage, all short (the
// control center has memory used / total). Click any of them for btop.
//   top bar:  󰻠 23%  󰔏 54°  󰍛 41%
//   side bar: the values stacked under their icons

import QtQuick
import qs.common
import qs.services

Island {
    id: island

    BarModule {
        vertical: island.vertical
        icon: Theme.iconCpu
        text: `${Math.round(SystemStats.cpuUsage)}%`
        onClicked: Session.btop()
    }
    BarModule {
        vertical: island.vertical
        icon: SystemStats.cpuHot ? Theme.iconTempHot : Theme.iconTemp
        text: SystemStats.cpuTemp < 0 ? "--" : `${Math.round(SystemStats.cpuTemp)}°`
        color: SystemStats.cpuHot ? Theme.warn : Theme.fg
        onClicked: Session.btop()
    }
    BarModule {
        vertical: island.vertical
        icon: Theme.iconMemory
        text: `${Math.round(SystemStats.memUsage)}%`
        onClicked: Session.btop()
    }
}
