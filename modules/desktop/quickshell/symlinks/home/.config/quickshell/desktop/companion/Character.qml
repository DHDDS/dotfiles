import QtQuick
import QtQuick.Shapes

// A parameter-driven vector puppet. Behaviour code animates the parameters;
// this file only draws them, so it never decides what the character does.
// Parts that are switched off are invisible and cost nothing to draw.
Item {
    id: root

    implicitWidth: 200
    implicitHeight: 200

    // Head pose. angleX/angleY are -1..1 (viewer's right/up positive), angleZ is degrees.
    property real angleX: 0
    property real angleY: 0
    property real angleZ: 0
    // Eyes: openness 0..1 per eye, smile 0..1 bends them into crescents, ball -1..1.
    property real eyeOpenL: 1
    property real eyeOpenR: 1
    property real eyeSmile: 0
    property real eyeBallX: 0
    property real eyeBallY: 0
    // "", "sparkle", "heart", "star", "squeeze" (> <) or "spiral".
    property string eyeStyle: ""
    property real spin: 0
    // Brows: raise -1..1, slant -1 (worried) .. 1 (cross).
    property real browY: 0
    property real browAngle: 0
    // Mouth: open 0..1, form -1 (frown) .. 1 (smile), round 0..1 ("oo"), tongue 0..1.
    property real mouthOpen: 0
    property real mouthForm: 0.5
    property real mouthRound: 0
    property real tongue: 0
    property real cheek: 0
    // Tears and a sweat drop, 0..1, with a 0..1 cycle phase for their motion.
    property real tears: 0
    property real sweat: 0
    property real dropPhase: 0
    // Body: breath 0..1, squash -1 (stretch) .. 1 (squash), side squeeze -1..1, lift in pixels.
    property real breath: 0
    property real squash: 0
    property real squashSide: 0
    property real lift: 0
    property real sprout: 0
    property real leafFold: 0
    property real perk: 0
    property real armL: 0
    property real armR: 0
    // Walking: a 0..1 step cycle; 0 while standing.
    property real step: 0
    property bool walking: false
    // Outfit: "", "nightcap", "party", "beanie" or "santa"; plus accessories.
    property string hat: ""
    property bool glasses: false
    property bool scarf: false
    property bool umbrella: false

    readonly property color ink: "#26304a"
    readonly property real ground: height - 18
    readonly property alias bodyItem: body
    readonly property real stepL: walking ? Math.max(0, Math.sin(step * 2 * Math.PI)) : 0
    readonly property real stepR: walking ? Math.max(0, -Math.sin(step * 2 * Math.PI)) : 0

    // Ground shadow; it shrinks as the character leaves the ground.
    Rectangle {
        readonly property real fade: Math.max(0.35, 1 - root.lift / 90)
        width: 112 * fade
        height: 14 * fade
        radius: height / 2
        x: (root.width - width) / 2
        y: root.ground - height / 2 + 2
        color: "#000000"
        opacity: 0.16 * fade
    }

    Item {
        id: figure
        width: 140
        height: 150
        x: (root.width - width) / 2
        y: root.ground - height - root.lift - 2 * (root.stepL + root.stepR)
        transform: [
            Scale {
                origin.x: figure.width / 2
                origin.y: figure.height
                xScale: (1 - 0.012 * root.breath + 0.11 * root.squash) * (1 - 0.12 * Math.abs(root.squashSide))
                yScale: (1 + 0.022 * root.breath - 0.13 * root.squash) * (1 + 0.05 * Math.abs(root.squashSide))
            },
            Rotation {
                origin.x: figure.width / 2
                origin.y: figure.height
                angle: root.angleZ * 0.6
            }
        ]

        // Feet sit behind the body and lift in turn while walking.
        Repeater {
            model: [-1, 1]
            Rectangle {
                required property int modelData
                width: 34
                height: 18
                radius: 9
                x: figure.width / 2 + modelData * 27 - width / 2 + root.angleX * 3
                y: figure.height - height - 7 * (modelData < 0 ? root.stepL : root.stepR)
                color: "#4fb985"
            }
        }

        // Arms pivot at the shoulder and swing out when raised.
        Repeater {
            model: [-1, 1]
            Rectangle {
                id: arm
                required property int modelData
                readonly property real raise: modelData < 0 ? root.armL : root.armR
                width: 20
                height: 34
                radius: 10
                x: figure.width / 2 + modelData * 62 - width / 2
                y: figure.height - 72
                color: "#6ccf9c"
                border.color: "#55bb88"
                border.width: 2
                transform: Rotation {
                    origin.x: arm.width / 2
                    origin.y: 4
                    angle: -arm.modelData * (14 + arm.raise * 120)
                }
            }
        }

        Rectangle {
            id: body
            width: 136
            height: 118
            radius: 58
            x: (figure.width - width) / 2
            y: figure.height - height - 8
            border.color: "#55bb88"
            border.width: 2
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#b4f5cf"
                }
                GradientStop {
                    position: 1
                    color: "#6ccf9c"
                }
            }

            // Belly patch moves less than the face, which reads as depth.
            Rectangle {
                width: 64
                height: 30
                radius: 15
                x: (body.width - width) / 2 + root.angleX * 6
                y: body.height - height - 9 - root.angleY * 2
                color: "#e4fcef"
                opacity: 0.6
            }

            // A knitted scarf above the belly, with its end hanging to one side.
            Item {
                visible: root.scarf
                Rectangle {
                    x: 6
                    y: 84
                    width: body.width - 12
                    height: 14
                    radius: 7
                    color: "#e94f5e"
                    Repeater {
                        model: 5
                        Rectangle {
                            required property int index
                            x: 14 + index * 22 + root.angleX * 4
                            width: 6
                            height: 14
                            color: "#ffffff"
                            opacity: 0.55
                        }
                    }
                }
                Rectangle {
                    x: body.width - 40
                    y: 90
                    width: 15
                    height: 28
                    radius: 6
                    rotation: -12 - root.angleZ * 0.5
                    color: "#d9404f"
                }
            }

            Item {
                id: face
                x: body.width / 2 + root.angleX * 17
                y: body.height * 0.45 - root.angleY * 9

                Repeater {
                    model: [-1, 1]
                    Rectangle {
                        required property int modelData
                        width: 22
                        height: 12
                        radius: 6
                        x: modelData * 41 - width / 2 + root.angleX * (modelData === Math.sign(root.angleX) ? -3 : 0)
                        y: 10
                        color: "#ff7a9a"
                        opacity: 0.42 + 0.5 * root.cheek
                    }
                }

                Repeater {
                    model: [-1, 1]
                    Rectangle {
                        required property int modelData
                        width: 15
                        height: 4
                        radius: 2
                        x: modelData * 24 - width / 2 + root.eyeBallX * 1.5
                        y: -31 - root.browY * 5 - (root.glasses ? 4 : 0)
                        color: root.ink
                        opacity: 0.8
                        rotation: modelData * root.browAngle * 18
                    }
                }

                Eye {
                    x: -24
                    y: -6
                    side: -1
                    open: root.eyeOpenL
                }
                Eye {
                    x: 24
                    y: -6
                    side: 1
                    open: root.eyeOpenR
                }

                // Tears roll from under each eye while crying.
                Repeater {
                    model: [-1, 1]
                    Rectangle {
                        required property int modelData
                        readonly property real fall: (root.dropPhase + (modelData < 0 ? 0 : 0.5)) % 1
                        visible: root.tears > 0.02
                        width: 6
                        height: 8
                        radius: 3
                        x: modelData * 24 + modelData * 9 - width / 2
                        y: 6 + fall * 16
                        color: "#6ec6ff"
                        opacity: root.tears * (1 - fall)
                    }
                }

                // Sunglasses cover the eyes but leave the brows free.
                Item {
                    visible: root.glasses
                    x: root.eyeBallX * 1.5
                    Repeater {
                        model: [-1, 1]
                        Rectangle {
                            required property int modelData
                            width: 32
                            height: 23
                            radius: 10
                            x: modelData * 24 - width / 2
                            y: -17
                            color: "#1d2233"
                            opacity: 0.94
                            Rectangle {
                                x: 6
                                y: 4
                                width: 10
                                height: 4
                                radius: 2
                                rotation: -20
                                color: "#ffffff"
                                opacity: 0.35
                            }
                        }
                    }
                    Rectangle {
                        x: -10
                        y: -10
                        width: 20
                        height: 4
                        radius: 2
                        color: "#1d2233"
                    }
                }

                Shape {
                    id: mouth
                    readonly property real half: (11 + root.mouthOpen * 2) * (1 - 0.4 * root.mouthRound)
                    readonly property real f: root.mouthForm * (1 - 0.6 * root.mouthRound)
                    readonly property real o: root.mouthOpen * (1 + 0.25 * root.mouthRound)
                    readonly property real lowerControl: 4 * f + 22 * o
                    readonly property real side: -0.55 * f + 7.67 * o
                    readonly property real depth: 0.5 * f + 11 * o - 1.5
                    x: root.angleX * 2
                    y: 15
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: "#6b2737"
                        strokeWidth: 3
                        fillColor: mouth.o > 0.04 ? "#7a2a3c" : "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: -mouth.half
                        startY: -3 * mouth.f
                        PathQuad {
                            controlX: 0
                            controlY: 4 * mouth.f - 2 * mouth.o - 4 * root.mouthRound * mouth.o
                            x: mouth.half
                            y: -3 * mouth.f
                        }
                        PathQuad {
                            controlX: 0
                            controlY: mouth.lowerControl
                            x: -mouth.half
                            y: -3 * mouth.f
                        }
                    }
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: mouth.o > 0.3 ? "#ff7e93" : "transparent"
                        startX: -0.55 * mouth.half
                        startY: mouth.side
                        PathQuad {
                            controlX: 0
                            controlY: mouth.side - 2 * mouth.o
                            x: 0.55 * mouth.half
                            y: mouth.side
                        }
                        PathQuad {
                            controlX: 0
                            controlY: 2 * mouth.depth - mouth.side
                            x: -0.55 * mouth.half
                            y: mouth.side
                        }
                    }
                }

                // A cheeky tongue poking out over the lower lip.
                Rectangle {
                    visible: root.tongue > 0.03
                    width: 12
                    height: 5 + 10 * root.tongue
                    radius: 6
                    x: mouth.x - width / 2 + 2
                    y: mouth.y + Math.max(1, mouth.depth * 0.6)
                    color: "#ff7e93"
                    border.color: "#e0647b"
                    border.width: 1
                    Rectangle {
                        x: parent.width / 2 - 0.5
                        y: 2
                        width: 1
                        height: parent.height - 5
                        color: "#e0647b"
                    }
                }
            }

            // An anime-style sweat drop on the side of the head.
            Shape {
                visible: root.sweat > 0.02
                x: body.width * 0.84
                y: 14 + root.dropPhase * 6
                opacity: root.sweat
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "#5aa9e6"
                    strokeWidth: 1.5
                    fillColor: "#bfe6ff"
                    startX: 0
                    startY: -9
                    PathCubic {
                        control1X: 3
                        control1Y: -4
                        control2X: 7
                        control2Y: 0
                        x: 6
                        y: 4
                    }
                    PathArc {
                        x: -6
                        y: 4
                        radiusX: 6
                        radiusY: 6
                    }
                    PathCubic {
                        control1X: -7
                        control1Y: 0
                        control2X: -3
                        control2Y: -4
                        x: 0
                        y: -9
                    }
                }
            }
        }

        // The sprout bends from its base, lags behind head turns and perks up
        // to the voice it is listening to.
        Item {
            id: sprout
            width: 4
            height: 26
            x: figure.width / 2 - width / 2 + root.angleX * 8
            y: body.y - height + 3
            transformOrigin: Item.Bottom
            rotation: root.sprout + root.angleZ * 0.4
            scale: 1 + 0.12 * root.perk
            Rectangle {
                anchors.fill: parent
                radius: 2
                color: "#4e9f3d"
            }
            Repeater {
                model: [-1, 1]
                Rectangle {
                    required property int modelData
                    width: 24
                    height: 13
                    radius: 7
                    x: sprout.width / 2 + (modelData < 0 ? -width + 2 : -2)
                    y: -6
                    color: modelData < 0 ? "#7bd15c" : "#62c04a"
                    transformOrigin: modelData < 0 ? Item.Right : Item.Left
                    rotation: modelData * (-28 - 22 * root.perk + 72 * root.leafFold)
                }
            }
        }

        Hat {
            visible: root.hat !== ""
            kind: root.hat
            x: body.x + 30 + root.angleX * 10
            y: body.y + 12
            rotation: -16 + root.angleZ * 0.4
        }

        // An umbrella held up in the right hand, leaning over the head.
        Item {
            id: umbrellaItem
            readonly property real angle: -(14 + root.armR * 120) * Math.PI / 180
            visible: root.umbrella
            x: figure.width / 2 + 62 - 30 * Math.sin(angle)
            y: figure.height - 68 + 30 * Math.cos(angle)
            rotation: -24
            Rectangle {
                x: -1.5
                y: -112
                width: 3
                height: 112
                radius: 1.5
                color: "#6b5b4b"
            }
            Shape {
                y: -112
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "#e0a92e"
                    strokeWidth: 2
                    fillColor: "#ffd166"
                    joinStyle: ShapePath.RoundJoin
                    startX: -62
                    startY: 4
                    PathArc {
                        x: 62
                        y: 4
                        radiusX: 62
                        radiusY: 46
                    }
                    PathArc {
                        x: 21
                        y: 4
                        radiusX: 21
                        radiusY: 9
                    }
                    PathArc {
                        x: -21
                        y: 4
                        radiusX: 21
                        radiusY: 9
                    }
                    PathArc {
                        x: -62
                        y: 4
                        radiusX: 21
                        radiusY: 9
                    }
                }
            }
        }
    }

    component Hat: Item {
        id: hat
        property string kind
        readonly property color main: kind === "party" ? "#7a6ff0" : kind === "nightcap" ? "#4f6bd8" : kind === "santa" ? "#e23d4b" : "#f08a4b"
        readonly property color trim: kind === "party" ? "#ffd166" : kind === "nightcap" ? "#cfe0ff" : "#ffffff"

        // Cone hats: party, nightcap (floppy) and santa.
        Shape {
            visible: hat.kind !== "beanie"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.darker(hat.main, 1.25)
                strokeWidth: 1.5
                fillColor: hat.main
                joinStyle: ShapePath.RoundJoin
                startX: -24
                startY: 0
                PathCubic {
                    control1X: -16
                    control1Y: -18
                    control2X: hat.kind === "party" ? -4 : -10
                    control2Y: -34
                    x: hat.kind === "party" ? 0 : 14
                    y: hat.kind === "party" ? -44 : -40
                }
                PathCubic {
                    control1X: hat.kind === "party" ? 4 : 18
                    control1Y: hat.kind === "party" ? -34 : -26
                    control2X: 18
                    control2Y: -14
                    x: 24
                    y: 0
                }
                PathLine {
                    x: -24
                    y: 0
                }
            }
        }
        Repeater {
            model: hat.kind === "party" ? [[-9, -12], [6, -22], [-2, -31]] : []
            Rectangle {
                required property var modelData
                x: modelData[0] - 3
                y: modelData[1] - 3
                width: 6
                height: 6
                radius: 3
                color: hat.trim
            }
        }
        // Knitted beanie dome.
        Rectangle {
            visible: hat.kind === "beanie"
            x: -26
            y: -26
            width: 52
            height: 30
            radius: 18
            color: hat.main
            border.color: Qt.darker(hat.main, 1.25)
            border.width: 1.5
        }
        // Brim and pompom.
        Rectangle {
            visible: hat.kind !== "party"
            x: -27
            y: -5
            width: 54
            height: 10
            radius: 5
            color: hat.trim
        }
        Rectangle {
            x: (hat.kind === "party" ? 0 : hat.kind === "beanie" ? 0 : 14) - width / 2
            y: (hat.kind === "party" ? -44 : hat.kind === "beanie" ? -30 : -40) - height / 2
            width: 11
            height: 11
            radius: 5.5
            color: hat.trim
        }
    }

    component Eye: Item {
        id: eye
        property real open: 1
        property int side: 1
        readonly property real smile: root.eyeSmile
        readonly property real a: 11.5
        readonly property real upper: 15 * Math.max(0.06, open)
        readonly property real lower: 15 * Math.max(0.06, open) * (1 - 1.7 * smile)
        readonly property real lookX: root.eyeBallX * 3.5
        readonly property real lookY: -root.eyeBallY * 3
        readonly property bool plain: root.eyeStyle === "" || root.eyeStyle === "sparkle"

        Shape {
            visible: eye.plain
            x: eye.lookX
            y: eye.lookY
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.ink
                strokeWidth: 3
                fillColor: root.ink
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: -eye.a
                startY: 0
                PathCubic {
                    control1X: -eye.a
                    control1Y: -1.33 * eye.upper
                    control2X: eye.a
                    control2Y: -1.33 * eye.upper
                    x: eye.a
                    y: 0
                }
                PathCubic {
                    control1X: eye.a
                    control1Y: 1.33 * eye.lower
                    control2X: -eye.a
                    control2Y: 1.33 * eye.lower
                    x: -eye.a
                    y: 0
                }
            }
        }
        // Highlights shift less than the eye, which reads as a round eyeball.
        Rectangle {
            visible: eye.plain
            readonly property real big: root.eyeStyle === "sparkle" ? 10 : 8
            width: big
            height: big
            radius: big / 2
            x: eye.lookX * 0.55 - 7
            y: eye.lookY * 0.55 - 9 * eye.open
            color: "white"
            opacity: Math.max(0, Math.min(1, (eye.open - 0.35) * 2.5)) * (1 - eye.smile)
        }
        Rectangle {
            visible: eye.plain
            width: 4
            height: 4
            radius: 2
            x: eye.lookX * 0.55 + 3
            y: eye.lookY * 0.55 + 3 * eye.open
            color: "white"
            opacity: Math.max(0, Math.min(1, (eye.open - 0.5) * 2.5)) * (1 - eye.smile)
        }
        // Excitement adds a four-pointed glint.
        Shape {
            visible: root.eyeStyle === "sparkle" && eye.open > 0.5
            x: eye.lookX * 0.55 + 4
            y: eye.lookY * 0.55 - 6
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: "white"
                startX: 0
                startY: -6
                PathQuad {
                    controlX: 1
                    controlY: -1
                    x: 6
                    y: 0
                }
                PathQuad {
                    controlX: 1
                    controlY: 1
                    x: 0
                    y: 6
                }
                PathQuad {
                    controlX: -1
                    controlY: 1
                    x: -6
                    y: 0
                }
                PathQuad {
                    controlX: -1
                    controlY: -1
                    x: 0
                    y: -6
                }
            }
        }
        Shape {
            visible: root.eyeStyle === "heart"
            x: eye.lookX * 0.6
            y: eye.lookY * 0.6
            scale: 0.9 + 0.12 * Math.sin(root.spin * Math.PI / 90)
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "#c2185b"
                strokeWidth: 1.5
                fillColor: "#ff4f87"
                startX: 0
                startY: 11
                PathCubic {
                    control1X: -2
                    control1Y: 9
                    control2X: -15
                    control2Y: 2
                    x: -15
                    y: -4
                }
                PathCubic {
                    control1X: -15
                    control1Y: -13
                    control2X: -3
                    control2Y: -15
                    x: 0
                    y: -7
                }
                PathCubic {
                    control1X: 3
                    control1Y: -15
                    control2X: 15
                    control2Y: -13
                    x: 15
                    y: -4
                }
                PathCubic {
                    control1X: 15
                    control1Y: 2
                    control2X: 2
                    control2Y: 9
                    x: 0
                    y: 11
                }
            }
        }
        Shape {
            visible: root.eyeStyle === "star"
            x: eye.lookX * 0.6
            y: eye.lookY * 0.6
            rotation: root.spin * 0.1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "#d08a00"
                strokeWidth: 1.5
                fillColor: "#ffd34d"
                joinStyle: ShapePath.RoundJoin
                startX: 0
                startY: -14
                PathPolyline {
                    path: {
                        const points = [];
                        for (let index = 1; index <= 10; index++) {
                            const radius = index % 2 ? 6 : 14;
                            const angle = -Math.PI / 2 + index * Math.PI / 5;
                            points.push(Qt.point(radius * Math.cos(angle), radius * Math.sin(angle)));
                        }
                        return points;
                    }
                }
            }
        }
        Shape {
            visible: root.eyeStyle === "squeeze"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.ink
                strokeWidth: 3.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: -6 * eye.side
                startY: -7
                PathLine {
                    x: 7 * eye.side
                    y: 0
                }
                PathLine {
                    x: -6 * eye.side
                    y: 7
                }
            }
        }
        Shape {
            visible: root.eyeStyle === "spiral"
            rotation: root.spin * eye.side
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.ink
                strokeWidth: 2.2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 0
                startY: 0
                PathPolyline {
                    path: {
                        const points = [];
                        for (let index = 0; index <= 48; index++) {
                            const angle = index / 48 * 4 * Math.PI;
                            const radius = 0.9 * angle;
                            points.push(Qt.point(radius * Math.cos(angle), radius * Math.sin(angle)));
                        }
                        return points;
                    }
                }
            }
        }
    }
}
