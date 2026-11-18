pragma Singleton

// The laptop's battery (UPower; upower must be installed and running): its
// charge, whether it's charging, and the time left. On a PC without a battery
// present is false and the bar shows nothing.

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: (device?.isLaptopBattery ?? false) && (device?.isPresent ?? false)
    // 0-100
    readonly property int percent: Math.round((device?.percentage ?? 0) * 100)
    readonly property bool charging: device?.state === UPowerDeviceState.Charging || device?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: device?.state === UPowerDeviceState.FullyCharged
    // the Waybar battery module's warning and critical levels
    readonly property bool low: !charging && percent <= 30
    readonly property bool critical: !charging && percent <= 15

    readonly property string icon: charging || full ? Theme.iconBatteryCharging : Theme.iconBattery[Math.min(10, Math.floor(percent / 10))]

    // "2h 15m left", "40m to full", or "" when unknown
    readonly property string timeText: {
        const s = charging ? (device?.timeToFull ?? 0) : (device?.timeToEmpty ?? 0);
        if (!s || s <= 0)
            return "";
        const h = Math.floor(s / 3600);
        const m = Math.floor(s % 3600 / 60);
        const t = h > 0 ? `${h}h ${m}m` : `${m}m`;
        return charging ? `${t} to full` : `${t} left`;
    }
}
