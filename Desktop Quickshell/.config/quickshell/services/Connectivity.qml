pragma Singleton

// Network (NetworkManager) and Bluetooth (BlueZ) state for the bar's status
// island and the control center's toggles.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.common

Singleton {
    id: root

    // ── network ───────────────────────────────────────────────────────────
    // the interface of the Waybar network module (change it for another PC)
    readonly property string interfaceName: "eno1"

    readonly property var device: {
        const devices = Networking.devices.values;
        return devices.find(d => d.name === interfaceName) ?? devices.find(d => d.connected) ?? null;
    }
    readonly property bool connected: device?.connected ?? false
    readonly property bool wifi: device?.type === DeviceType.Wifi
    readonly property string networkIcon: !connected ? Theme.iconOffline : wifi ? Theme.iconWifi : Theme.iconEthernet
    readonly property string networkText: connected ? (device?.name ?? "") : "Offline"

    // ── bluetooth ─────────────────────────────────────────────────────────
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter?.enabled ?? false
    readonly property var connectedDevices: Bluetooth.devices.values.filter(d => d.connected)
    readonly property bool bluetoothConnected: connectedDevices.length > 0
    readonly property string bluetoothIcon: !bluetoothOn ? Theme.iconBluetoothOff : bluetoothConnected ? Theme.iconBluetoothConnected : Theme.iconBluetooth
    // the battery of a connected device that reports one (headphones,
    // controller), like Waybar's "format-connected-battery"; -1 if none
    readonly property int bluetoothBattery: {
        const withBattery = connectedDevices.find(d => d.batteryAvailable);
        return withBattery ? Math.round(withBattery.battery * 100) : -1;
    }
    readonly property string bluetoothText: !bluetoothOn ? "Off" : bluetoothConnected ? (connectedDevices[0].name ?? "Connected") : "On"

    function toggleBluetooth() {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }
}
