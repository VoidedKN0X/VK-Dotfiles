//@ pragma UseQApplication
// (the tray icons' menus are Qt menus, which need QApplication)

// VK Shell: the bar, control center, calendar, power menu, notifications and
// volume popup of the "Desktop Quickshell" profile. Started by Hyprland
// (hypr/hyprland/execs.lua); Super + R restarts it.
//
//   common/        the look (Theme.qml) and shared pieces
//   services/      system info, audio, music, notifications, ...
//   bar/           the bar and its islands
//   controlcenter/ the control center
//   popups/        calendar, power menu, notification popups, volume popup
//   scripts/       stats.sh (CPU, memory, temperature), cava.sh (visualizer)
//   colors.json    written by wallust (wallust/templates/colors-quickshell.template)
//   bar-position   written by Super + B: "top" or "left"
//
// Commands for keybinds and scripts (qs ipc show lists them):
//   qs ipc call bar toggle             move the main bar between top and left
//   qs ipc call controlCenter toggle   open / close the control center
//   qs ipc call calendar toggle        open / close the calendar
//   qs ipc call power toggle           open / close the power menu
//   qs ipc call osd show ...           the volume popup (see popups/Osd.qml)

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.bar
import qs.controlcenter
import qs.popups

ShellRoot {
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
}
