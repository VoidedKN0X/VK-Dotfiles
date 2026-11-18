// The music visualizer: six small bars in the accent color. Upright in the
// top bar; on their side in a side bar, growing away from the screen edge.

import QtQuick
import qs.common
import qs.services

Item {
    id: cava

    // "up", "right" (left bar) or "left" (right bar): the direction they grow
    property string grow: "up"
    property int barLength: 12
    property int barThickness: 3
    property int barGap: 2

    readonly property bool upright: grow === "up"
    readonly property int across: Cava.bars * barThickness + (Cava.bars - 1) * barGap

    implicitWidth: upright ? across : barLength
    implicitHeight: upright ? barLength : across

    Repeater {
        model: Cava.bars

        Rectangle {
            required property int index
            // never quite 0, so the bars stay visible while paused (like the
            // flat ▁ bars of the Waybar version)
            readonly property real level: Math.max(0.12, Cava.levels[index] ?? 0)

            color: Theme.accent
            radius: 1
            x: cava.upright ? index * (cava.barThickness + cava.barGap) : cava.grow === "left" ? cava.barLength - width : 0
            y: cava.upright ? cava.barLength - height : index * (cava.barThickness + cava.barGap)
            width: cava.upright ? cava.barThickness : Math.round(cava.barLength * level)
            height: cava.upright ? Math.round(cava.barLength * level) : cava.barThickness

            Behavior on width {
                NumberAnimation {
                    duration: 60
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 60
                }
            }
        }
    }
}
