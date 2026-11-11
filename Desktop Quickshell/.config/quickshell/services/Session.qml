pragma Singleton

// Lock, suspend, log out, restart, shut down: the commands of the power menu
// and the control center's session buttons (the same ones the Waybar power
// menu ran), and opening the apps the bar links to.

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var actions: ({
            // through hypridle's lock_cmd, so hyprlock never starts twice
            "lock": "loginctl lock-session",
            "suspend": "systemctl suspend",
            // same as Super + M
            "logout": "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'",
            "reboot": "systemctl reboot",
            "poweroff": "systemctl poweroff"
        })

    // the ones that ask for a second click, with the text shown meanwhile
    readonly property var confirmText: ({
            "logout": "Click again to log out",
            "reboot": "Click again to restart",
            "poweroff": "Click again to shut down"
        })

    function run(action) {
        // the popups close first, so nothing of them is on screen (or in the
        // lock screen's screenshot) while it runs
        BarState.closeAll();
        Qt.callLater(() => shell(root.actions[action]));
    }

    // a command through sh (for ~, && and ||), detached from Quickshell
    function shell(command) {
        Quickshell.execDetached(["sh", "-c", command]);
    }

    // the apps the Waybar modules opened
    function btop() {
        shell("foot btop");
    }
    // nmtui, for what the network panel doesn't do (VPN, static IP)
    function networkSettings() {
        shell("foot --app-id=nmtui nmtui");
    }
    // an app in foot (the terminal of hypr/variables.lua)
    function inTerminal(command) {
        Quickshell.execDetached(["foot"].concat(command));
    }
}
