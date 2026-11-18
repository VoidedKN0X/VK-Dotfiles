// A ring gauge (270°, open at the bottom) with the percentage inside it and a
// label and detail line under it: CPU usage and memory in the control center.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.common

Column {
    id: ring

    property real value: 0      // 0-100
    property string label: ""
    property string detail: ""
    property int size: 96
    property int thickness: 7

    spacing: 2

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: ring.size
        height: ring.size

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // the empty track
            ShapePath {
                strokeColor: Theme.track
                strokeWidth: ring.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.size / 2
                    centerY: ring.size / 2
                    radiusX: (ring.size - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: 135
                    sweepAngle: 270
                }
            }
            // the value
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: ring.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.size / 2
                    centerY: ring.size / 2
                    radiusX: (ring.size - ring.thickness) / 2
                    radiusY: radiusX
                    startAngle: 135
                    sweepAngle: 270 * Math.max(0.005, Math.min(1, ring.value / 100))
                    Behavior on sweepAngle {
                        NumberAnimation {
                            duration: 400
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        // the percentage, in the middle of the ring
        RowLayout {
            anchors.centerIn: parent
            spacing: 1
            Label {
                Layout.alignment: Qt.AlignBaseline
                text: Math.round(ring.value)
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Label {
                Layout.alignment: Qt.AlignBaseline
                text: "%"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: 14
            }
        }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: -8
        text: ring.label
        font.pixelSize: 13
        font.weight: Font.Bold
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: ring.detail
        color: Theme.dim
        font.pixelSize: 11
    }
}
