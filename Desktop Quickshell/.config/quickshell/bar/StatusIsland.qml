// Status island: the system tray, Bluetooth, network and volume. Every icon
// opens its program, like the Waybar modules did:
//   tray icons  -> their app (right click: its menu)
//   Bluetooth   -> the Bluetooth panel (right click: Bluetooth on / off)
//   network     -> the network panel
//   volume      -> the volume mixer (scroll: volume in 1% steps, right click: mute)

import QtQuick
import Quickshell.Services.SystemTray
import qs.common
import qs.services

Island {
    id: island

    required property var window
    required property string edge

    spacing: vertical ? 2 : 3

    Repeater {
        model: SystemTray.items.values
        TrayIcon {
            window: island.window
            edge: island.edge
        }
    }

    BarModule {
        vertical: island.vertical
        icon: Connectivity.bluetoothIcon
        // the battery of a connected device, if it reports one
        text: Connectivity.bluetoothBattery >= 0 ? `${Connectivity.bluetoothBattery}%` : ""
        color: Connectivity.bluetoothOn ? Theme.fg : Theme.faint
        onClicked: BarState.toggleBluetooth(island.window.modelData)
        onRightClicked: Connectivity.toggleBluetooth()
    }
    BarModule {
        vertical: island.vertical
        icon: Connectivity.networkIcon
        color: Connectivity.connected ? Theme.fg : Theme.faint
        onClicked: BarState.toggleNetwork(island.window.modelData)
    }
    BarModule {
        vertical: island.vertical
        icon: Audio.icon
        text: `${Audio.percent}%`
        color: Audio.muted ? Theme.faint : Theme.fg
        onClicked: BarState.toggleMixer(island.window.modelData)
        onRightClicked: Audio.toggleMute()
        onScrolled: steps => Audio.setVolume(Audio.volume + steps * 0.01)
    }
}
