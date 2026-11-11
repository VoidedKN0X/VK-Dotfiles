// System island: CPU usage, CPU temperature and memory used / total. Click any
// of them for btop.
//   top bar:  󰻠 23%  󰔏 54°  󰍛 13.1/31G
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
        text: SystemStats.memUsed.toFixed(1)
        // total in whole GiB: "13.1/31G"
        subText: `/${Math.round(SystemStats.memTotal)}G`
        onClicked: Session.btop()
    }
}
