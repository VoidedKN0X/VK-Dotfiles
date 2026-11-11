// The bar of one monitor and the frame around its screen: one piece of glass
// along every edge, with the desktop inside it rounded off at the corners
// (Theme "the frame"). The bar's side (top, left or right: BarState.edgeFor)
// is wide enough for the islands; the other sides are a thin border. Popups
// grow out of the frame's inner edge (common/PopupLayer.qml).
// The islands:
//   start:  workspaces, music
//   middle: clock
//   end:    CPU / temperature / memory, tray + Bluetooth + network + volume,
//           stay awake, notifications, power
// On a side bar, start is the top and end the bottom.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

Scope {
    id: root

    required property var modelData
    // "top", "left" or "right"; a change creates a new bar (shell.qml)
    required property string edge

    // ── the space the frame keeps free: windows stay inside it ────────────
    // (one layer per side; the frame itself is one layer over the whole
    // screen, which can't keep space free)
    Variants {
        model: ["top", "bottom", "left", "right"]

        PanelWindow {
            required property string modelData
            screen: root.modelData
            color: "transparent"
            WlrLayershell.namespace: "frame-zone"
            WlrLayershell.layer: WlrLayer.Bottom
            anchors {
                top: modelData !== "bottom"
                bottom: modelData !== "top"
                left: modelData !== "right"
                right: modelData !== "left"
            }
            implicitWidth: 1
            implicitHeight: 1
            exclusiveZone: Theme.frameSize(root.edge, modelData)
            // takes no clicks
            mask: Region {}
        }
    }

    PanelWindow {
        id: bar

        readonly property var modelData: root.modelData
        readonly property string edge: root.edge
        readonly property bool vertical: edge !== "top"

        // the frame's thickness on each side, and the desktop inside it
        readonly property int sizeTop: Theme.frameSize(edge, "top")
        readonly property int sizeBottom: Theme.frameSize(edge, "bottom")
        readonly property int sizeLeft: Theme.frameSize(edge, "left")
        readonly property int sizeRight: Theme.frameSize(edge, "right")

        screen: modelData
        color: "transparent"
        // the layer's name: Hyprland blurs the frame by it (hypr/hyprland/rules.lua)
        WlrLayershell.namespace: "vk-" + edge
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // only the frame takes clicks; the desktop inside it is the windows'
        mask: Region {
            regions: [
                Region {
                    width: bar.width
                    height: bar.sizeTop
                },
                Region {
                    y: bar.height - bar.sizeBottom
                    width: bar.width
                    height: bar.sizeBottom
                },
                Region {
                    width: bar.sizeLeft
                    height: bar.height
                },
                Region {
                    x: bar.width - bar.sizeRight
                    width: bar.sizeRight
                    height: bar.height
                }
            ]
        }

        // stay awake while the coffee cup is on (the same protocol Waybar's
        // idle_inhibitor used)
        IdleInhibitor {
            window: bar
            enabled: BarState.stayAwake
        }

        // the frame: the whole screen minus the desktop with its round corners
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.frame
                strokeWidth: -1
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    readonly property real x0: bar.sizeLeft
                    readonly property real y0: bar.sizeTop
                    readonly property real x1: bar.width - bar.sizeRight
                    readonly property real y1: bar.height - bar.sizeBottom
                    readonly property real r: Theme.frameRadius
                    path: `M0 0 H${bar.width} V${bar.height} H0 Z M${x0 + r} ${y0} H${x1 - r} A${r} ${r} 0 0 1 ${x1} ${y0 + r} V${y1 - r} A${r} ${r} 0 0 1 ${x1 - r} ${y1} H${x0 + r} A${r} ${r} 0 0 1 ${x0} ${y1 - r} V${y0 + r} A${r} ${r} 0 0 1 ${x0 + r} ${y0} Z`
                }
            }
        }

        // the islands, in the bar's side of the frame
        Item {
            x: bar.edge === "top" ? Theme.barEndMargin : bar.edge === "left" ? Theme.barEdgeMargin : bar.width - Theme.barEdgeMargin - Theme.barWidth
            y: bar.edge === "top" ? Theme.barEdgeMargin : Theme.barEndMargin
            width: bar.vertical ? Theme.barWidth : bar.width - 2 * Theme.barEndMargin
            height: bar.vertical ? bar.height - 2 * Theme.barEndMargin : Theme.barHeight

            // ── start ─────────────────────────────────────────────────────────────
            GridLayout {
                anchors.left: bar.vertical ? undefined : parent.left
                anchors.top: bar.vertical ? parent.top : undefined
                anchors.verticalCenter: bar.vertical ? undefined : parent.verticalCenter
                anchors.horizontalCenter: bar.vertical ? parent.horizontalCenter : undefined
                columns: bar.vertical ? 1 : 100
                columnSpacing: Theme.islandSpacing
                rowSpacing: Theme.islandSpacing

                Workspaces {
                    vertical: bar.vertical
                    monitorName: bar.modelData.name
                }
                MusicIsland {
                    vertical: bar.vertical
                    screen: bar.modelData
                    edge: bar.edge
                }
            }

            // ── middle ────────────────────────────────────────────────────────────
            Clock {
                anchors.centerIn: parent
                vertical: bar.vertical
                screen: bar.modelData
            }

            // ── end ───────────────────────────────────────────────────────────────
            GridLayout {
                anchors.right: bar.vertical ? undefined : parent.right
                anchors.bottom: bar.vertical ? parent.bottom : undefined
                anchors.verticalCenter: bar.vertical ? undefined : parent.verticalCenter
                anchors.horizontalCenter: bar.vertical ? parent.horizontalCenter : undefined
                columns: bar.vertical ? 1 : 100
                columnSpacing: Theme.islandSpacing
                rowSpacing: Theme.islandSpacing

                SystemIsland {
                    vertical: bar.vertical
                }
                StatusIsland {
                    vertical: bar.vertical
                    window: bar
                    edge: bar.edge
                }
                // stay awake (idle inhibitor)
                IconIsland {
                    vertical: bar.vertical
                    icon: BarState.stayAwake ? Theme.iconAwake : Theme.iconSleepy
                    iconColor: BarState.stayAwake ? Theme.accent : Theme.dim
                    onClicked: BarState.stayAwake = !BarState.stayAwake
                }
                // notifications: click for the control center, right click for do
                // not disturb. An accent pill while there are notifications.
                IconIsland {
                    readonly property bool unread: Notifs.count > 0 && !Notifs.dnd
                    vertical: bar.vertical
                    icon: Notifs.dnd ? Theme.iconBellOff : Notifs.count > 0 ? Theme.iconBellNew : Theme.iconBell
                    iconColor: Notifs.dnd ? Theme.faint : unread ? Theme.onAccent : Theme.fg
                    iconHoverColor: unread ? Theme.onAccent : Theme.accent
                    fill: unread ? Theme.accent : Theme.glass
                    border.color: unread ? "transparent" : Theme.edge
                    onClicked: BarState.toggleControlCenter(bar.modelData)
                    onRightClicked: Notifs.dnd = !Notifs.dnd
                }
                // power menu
                IconIsland {
                    vertical: bar.vertical
                    icon: Theme.iconPower
                    iconColor: Theme.warn
                    iconHoverColor: Theme.warn
                    hoverFill: Qt.alpha(Theme.warn, 0.25)
                    onClicked: BarState.togglePowerMenu(bar.modelData)
                }
            }
        }
    }
}
