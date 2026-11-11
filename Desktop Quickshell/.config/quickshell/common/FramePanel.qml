// The glass behind a popup that grows out of the frame (Theme "the frame"):
// a panel joined to the frame's inner edge by two rounded joins, with round
// outer corners. Fills its parent; all coordinates are the parent's.
//   side   the frame side it grows out of: "top", "bottom", "left", "right"
//   base   where that side's inner edge is (y for top/bottom, x for left/right)
//   from, to  where the panel starts and ends along that side
//   depth  how far it reaches into the desktop
// With span set it fills the whole side (from and to are the desktop's
// edges there): it takes the desktop's round corners, and its outer corners
// join the frame on the two sides next to it (the control center).

import QtQuick
import QtQuick.Shapes

Shape {
    id: shape

    property string side: "top"
    property real base: 0
    property real from: 0
    property real to: 100
    property real depth: 100
    property bool span: false
    property color color: Theme.frame

    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // the outline for a panel hanging from the top (u along the side, v into
    // the desktop), turned to its real side
    readonly property string path: {
        const d = Math.max(1, depth);
        const f = Math.min(Theme.fillet, d / 2);
        const r = Math.min(Theme.panelRadius, d / 2, (to - from) / 2);
        const R = Theme.frameRadius;
        // top: as is; right: turned; bottom and left: mirrored, which turns
        // every arc the other way
        const flip = side === "bottom" || side === "left";
        const pt = (u, v) => {
            switch (side) {
            case "bottom":
                return `${u} ${base - v}`;
            case "left":
                return `${base + v} ${u}`;
            case "right":
                return `${base - v} ${u}`;
            default:
                return `${u} ${base + v}`;
            }
        };
        const arc = (radius, sweep, u, v) => `A${radius} ${radius} 0 0 ${flip ? 1 - sweep : sweep} ${pt(u, v)}`;
        const a = from, b = to;
        if (span)
            return `M${pt(a + R, 0)} L${pt(b - R, 0)} ${arc(R, 1, b, R)} L${pt(b, d + f)} ${arc(f, 0, b - f, d)} L${pt(a + f, d)} ${arc(f, 0, a, d + f)} L${pt(a, R)} ${arc(R, 1, a + R, 0)} Z`;
        return `M${pt(a - f, 0)} ${arc(f, 1, a, f)} L${pt(a, d - r)} ${arc(r, 0, a + r, d)} L${pt(b - r, d)} ${arc(r, 0, b, d - r)} L${pt(b, f)} ${arc(f, 1, b + f, 0)} Z`;
    }

    ShapePath {
        fillColor: shape.color
        strokeWidth: -1
        strokeColor: "transparent"
        PathSvg {
            path: shape.path
        }
    }
}
