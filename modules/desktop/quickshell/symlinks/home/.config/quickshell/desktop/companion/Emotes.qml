pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../ui"

// Floating symbols spawned by Puppet.emote(). Positions derive from the
// puppet's frame clock, so emotes move only while it draws frames.
Item {
    id: root

    required property var puppet

    Repeater {
        model: root.puppet.emotes
        Item {
            id: emote
            required property var modelData
            readonly property real t: Math.max(0, (root.puppet.clock - modelData.born) / 1000)
            readonly property real progress: Math.min(1, t / modelData.life)
            readonly property string kind: modelData.kind
            readonly property var glyphs: ({
                    note: "♪",
                    z: "z",
                    bang: "!",
                    question: "?",
                    ding: "ding!"
                })
            x: modelData.x + modelData.vx * t + 6 * Math.sin(t * 5 + modelData.phase)
            y: modelData.y + modelData.vy * t
            opacity: modelData.born > root.puppet.clock ? 0 : Math.min(1, t * 6) * (1 - progress * progress)
            scale: (kind === "z" ? 0.7 + 0.6 * progress : 1) * (0.6 + 0.4 * Math.min(1, t * 5))

            Text {
                visible: emote.kind in emote.glyphs
                anchors.centerIn: parent
                text: emote.glyphs[emote.kind] ?? ""
                color: emote.kind === "note" ? "#7a6ff0" : emote.kind === "bang" ? "#e94f5e" : emote.kind === "ding" ? "#e0a92e" : "#6f8f80"
                font.family: Theme.fontFamily
                font.pixelSize: emote.kind === "ding" ? 15 : 20
                font.bold: emote.kind !== "z"
                style: Text.Outline
                styleColor: "#ffffff"
            }
            Shape {
                visible: emote.kind === "heart"
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "#ffffff"
                    strokeWidth: 1.5
                    fillColor: "#ff4f87"
                    startX: 0
                    startY: 8
                    PathCubic {
                        control1X: -2
                        control1Y: 6
                        control2X: -10
                        control2Y: 1
                        x: -10
                        y: -3
                    }
                    PathCubic {
                        control1X: -10
                        control1Y: -9
                        control2X: -2
                        control2Y: -10
                        x: 0
                        y: -5
                    }
                    PathCubic {
                        control1X: 2
                        control1Y: -10
                        control2X: 10
                        control2Y: -9
                        x: 10
                        y: -3
                    }
                    PathCubic {
                        control1X: 10
                        control1Y: 1
                        control2X: 2
                        control2Y: 6
                        x: 0
                        y: 8
                    }
                }
            }
            Shape {
                visible: emote.kind === "sparkle"
                rotation: emote.t * 90
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: "#ffd34d"
                    startX: 0
                    startY: -9
                    PathQuad {
                        controlX: 1.5
                        controlY: -1.5
                        x: 9
                        y: 0
                    }
                    PathQuad {
                        controlX: 1.5
                        controlY: 1.5
                        x: 0
                        y: 9
                    }
                    PathQuad {
                        controlX: -1.5
                        controlY: 1.5
                        x: -9
                        y: 0
                    }
                    PathQuad {
                        controlX: -1.5
                        controlY: -1.5
                        x: 0
                        y: -9
                    }
                }
            }
            Rectangle {
                visible: emote.kind === "drop"
                x: -3
                y: -4
                width: 6
                height: 8
                radius: 3
                color: "#6ec6ff"
            }
        }
    }
}
