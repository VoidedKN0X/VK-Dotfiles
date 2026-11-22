// Status island: the system tray, Bluetooth, network and volume. Every icon
// opens its program, like the Waybar modules did:
//   tray icons  -> their app (right click: its menu)
//   Bluetooth   -> the Bluetooth panel (right click: Bluetooth on / off)
//   network     -> the network panel
//   volume      -> the volume mixer (scroll: volume in 1% steps, right click: mute)
//   battery     -> (laptops only) the charge; hover: the time left
//   YubiKey     -> (only while it waits for a touch) a blinking key; the panel
//                  under the clock says what's asking (popups/YubikeyTouch.qml)
//   phone       -> (with a phone paired in KDE Connect and in reach) its
//                  battery, in the accent color while charging; click: the
//                  control center, with the phone card

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

    // the YubiKey waiting for a touch: a blinking key
    BarModule {
        id: yubikey
        visible: YubiKey.waiting
        vertical: island.vertical
        icon: String.fromCodePoint(0xf0306)  // key
        color: Theme.accent
        interactive: false
        SequentialAnimation on opacity {
            running: yubikey.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                yubikey.opacity = 1
            NumberAnimation {
                to: 0.3
                duration: 500
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                to: 1
                duration: 500
                easing.type: Easing.InOutQuad
            }
        }
    }
    // the phone (KDE Connect), while it's in reach
    BarModule {
        visible: Phone.present && Phone.reachable
        vertical: island.vertical
        icon: String.fromCodePoint(0xf011c)  // cellphone
        text: Phone.charge >= 0 ? `${Phone.charge}%` : ""
        color: Phone.charging ? Theme.accent : Theme.fg
        onClicked: BarState.toggleControlCenter(island.window.modelData)
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
    // only where there is a battery: orange when low, red when almost empty
    BarModule {
        visible: Battery.present
        vertical: island.vertical
        icon: Battery.icon
        text: `${Battery.percent}%`
        color: Battery.critical ? Theme.warn : Battery.low ? Theme.accent : Theme.fg
        interactive: false
    }
}
