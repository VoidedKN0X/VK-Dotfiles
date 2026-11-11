//@ pragma UseQApplication
// (the tray icons' menus are Qt menus, which need QApplication)

// VK Shell: the whole desktop shell of the "Desktop Quickshell" profile: the
// wallpaper, bar, control center, calendar, power menu, notifications, volume
// popup and mixer, app launcher, wallpaper picker, clipboard history and the
// password dialog for admin rights (polkit). Started by Hyprland
// (hypr/hyprland/execs.lua); Super + R restarts it.
//
//   common/        the look (Theme.qml) and shared pieces
//   services/      system info, audio, music, notifications, ...
//   bar/           the bar and its islands
//   controlcenter/ the control center
//   popups/        calendar, power menu, notifications, volume popup, mixer,
//                  launcher, wallpaper picker, clipboard, polkit dialog,
//                  Bluetooth and network panels, window switcher, screenshot flash,
//                  workspace overview
//   background/    the wallpaper
//   scripts/       stats.sh (CPU, memory, temperature), cava.sh (visualizer)
//   colors.json    written by wallust (wallust/templates/colors-quickshell.template)
//   bar-position   written by Super + B: "top" or "left"
//
// Commands for keybinds and scripts (qs ipc show lists them):
//   qs ipc call bar toggle             move the main bar between top and left
//   qs ipc call controlCenter toggle   open / close the control center
//   qs ipc call calendar toggle        open / close the calendar
//   qs ipc call power toggle           open / close the power menu
//   qs ipc call mixer toggle           open / close the volume mixer
//   qs ipc call launcher toggle        open / close the app launcher
//   qs ipc call wallpaper toggle       open / close the wallpaper picker
//   qs ipc call clipboard toggle       open / close the clipboard history
//   qs ipc call bluetooth toggle       open / close the Bluetooth panel
//   qs ipc call network toggle         open / close the network panel
//   qs ipc call switcher next / prev   Alt + Tab / Alt + Shift + Tab
//   qs ipc call switcher commit        switch to the selected window
//   qs ipc call screenshot flash       the flash after a screenshot
//   qs ipc call overview toggle        open / close the workspace overview
//   qs ipc call osd show ...           the volume popup (see popups/Osd.qml)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import qs.services
import qs.background
import qs.bar
import qs.controlcenter
import qs.popups

ShellRoot {
    // ── the wallpaper, on every monitor ───────────────────────────────────
    Variants {
        model: Quickshell.screens
        WallpaperLayer {}
    }

    // ── a bar per monitor, on its edge; a new edge creates a new bar ──────
    Variants {
        model: Quickshell.screens

        Scope {
            id: monitor
            required property var modelData
            readonly property string edge: BarState.edgeFor(modelData.name)

            LazyLoader {
                active: monitor.edge === "top"
                Bar {
                    modelData: monitor.modelData
                    edge: "top"
                }
            }
            LazyLoader {
                active: monitor.edge === "left"
                Bar {
                    modelData: monitor.modelData
                    edge: "left"
                }
            }
            LazyLoader {
                active: monitor.edge === "right"
                Bar {
                    modelData: monitor.modelData
                    edge: "right"
                }
            }
        }
    }

    // ── popups, created while open ────────────────────────────────────────
    LazyLoader {
        active: BarState.controlCenterScreen !== null
        ControlCenter {}
    }
    LazyLoader {
        active: BarState.calendarScreen !== null
        CalendarPopup {}
    }
    LazyLoader {
        active: BarState.powerMenuScreen !== null
        PowerMenu {}
    }
    LazyLoader {
        active: BarState.mixerScreen !== null
        Mixer {}
    }
    LazyLoader {
        active: BarState.launcherScreen !== null
        Launcher {}
    }
    LazyLoader {
        active: BarState.wallpaperScreen !== null
        WallpaperPicker {}
    }
    LazyLoader {
        active: BarState.clipboardScreen !== null
        Clipboard {}
    }
    LazyLoader {
        active: BarState.bluetoothScreen !== null
        BluetoothPanel {}
    }
    LazyLoader {
        active: BarState.networkScreen !== null
        NetworkPanel {}
    }
    LazyLoader {
        active: BarState.switcherScreen !== null
        WindowSwitcher {}
    }
    LazyLoader {
        active: BarState.overviewOpen
        Overview {}
    }

    ScreenshotFlash {
        id: screenshotFlash
    }

    // ── admin rights (polkit): the password dialog while an app asks ──────
    PolkitAgent {
        id: polkit
    }
    LazyLoader {
        active: polkit.isActive
        PolkitDialog {
            agent: polkit
        }
    }

    NotificationPopups {}
    Osd {}

    // ── commands for keybinds ─────────────────────────────────────────────
    IpcHandler {
        target: "bar"
        function toggle(): void {
            BarState.toggleMainEdge();
        }
    }
    IpcHandler {
        target: "controlCenter"
        function toggle(): void {
            BarState.toggleControlCenter(null);
        }
    }
    IpcHandler {
        target: "calendar"
        function toggle(): void {
            BarState.toggleCalendar(null);
        }
    }
    IpcHandler {
        target: "power"
        function toggle(): void {
            BarState.togglePowerMenu(null);
        }
    }
    IpcHandler {
        target: "mixer"
        function toggle(): void {
            BarState.toggleMixer(null);
        }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            BarState.toggleLauncher(null);
        }
    }
    IpcHandler {
        target: "wallpaper"
        function toggle(): void {
            BarState.toggleWallpaperPicker(null);
        }
    }
    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            BarState.toggleClipboard(null);
        }
    }
    IpcHandler {
        target: "bluetooth"
        function toggle(): void {
            BarState.toggleBluetooth(null);
        }
    }
    IpcHandler {
        target: "network"
        function toggle(): void {
            BarState.toggleNetwork(null);
        }
    }
    IpcHandler {
        target: "switcher"
        function next(): void {
            BarState.switchWindows(1);
        }
        function prev(): void {
            BarState.switchWindows(-1);
        }
        // letting go of Alt (keybinds.lua), in case the switcher didn't see it
        function commit(): void {
            if (BarState.switcherScreen !== null)
                BarState.switcherCommit();
        }
    }
    IpcHandler {
        target: "overview"
        function toggle(): void {
            BarState.toggleOverview();
        }
    }
    IpcHandler {
        target: "screenshot"
        function flash(): void {
            screenshotFlash.start();
        }
    }
}
