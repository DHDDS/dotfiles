pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../ui"

// A transparent Top-layer surface with the character at its bottom centre.
// Only the character accepts input, so the rest passes through, and keyboard
// focus is taken only while the menu or message box is open.
PanelWindow {
    id: window

    required property var companion
    readonly property alias puppet: puppet
    property bool holding: false
    property var menuContext: null
    readonly property real screenWidth: screen?.width ?? width
    readonly property real screenHeight: screen?.height ?? height
    // The character's centre stays at least 80 px inside the screen.
    readonly property real homeRight: clampRight(companion.position.right ?? 110 - width / 2, false)
    readonly property real homeBottom: clampBottom(companion.position.bottom ?? 16)
    readonly property real marginRight: companion.dragging ? companion.dragMargins.x : homeRight
    readonly property real marginBottom: companion.dragging ? companion.dragMargins.y : homeBottom
    readonly property bool interactive: companion.composing || menu.visible || chatModelMenu.visible

    function clampRight(value: real, peeking: bool): real {
        return Math.max(-(width / 2 + (peeking ? 20 : -80)), Math.min(screenWidth - width / 2 - 80, value));
    }
    function clampBottom(value: real): real {
        return Math.max(-10, Math.min(screenHeight - height, value));
    }
    // Cards centre over the character but stay inside the visible screen.
    function cardX(cardWidth: real): real {
        const left = screenWidth - marginRight - width;
        const visibleLeft = Math.max(0, -left) + 4;
        const visibleRight = width - Math.max(0, -marginRight) - 4;
        return Math.max(visibleLeft, Math.min(visibleRight - cardWidth, puppet.x + puppet.width / 2 - cardWidth / 2));
    }

    screen: companion.screen
    anchors {
        bottom: true
        right: true
    }
    margins {
        right: window.marginRight
        bottom: window.marginBottom
    }
    implicitWidth: 460
    implicitHeight: 640
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "desktop-companion"
    WlrLayershell.keyboardFocus: window.interactive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: window.interactive ? everything : hitArea
        Region {
            item: bubble.interactive ? bubble : null
        }
        Region {
            item: cards.visible ? cards : null
        }
    }

    HyprlandFocusGrab {
        windows: [window]
        active: window.interactive
        onCleared: {
            window.companion.composing = false;
            menu.close();
            chatModelMenu.close();
        }
    }

    // Direction from the character's eyes to the global cursor, -1..1 with y up.
    readonly property point cursorGaze: {
        const cursor = companion.cursor;
        if (!screen || isNaN(cursor.x))
            return Qt.point(0, 0);
        const left = screen.x + screen.width - marginRight - width;
        const top = screen.y + screen.height - marginBottom - height;
        const dx = cursor.x - (left + puppet.x + puppet.width / 2);
        const dy = cursor.y - (top + puppet.y + 108);
        const distance = Math.hypot(dx, dy);
        if (distance < 1)
            return Qt.point(0, 0);
        const reach = distance / (distance + 220);
        return Qt.point(dx / distance * reach, -dy / distance * reach);
    }

    Item {
        id: everything
        anchors.fill: parent
    }

    Puppet {
        id: puppet
        x: (window.width - width) / 2
        y: window.height - height
        running: window.visible
        asleep: window.companion.asleep
        calm: window.companion.calm
        expression: window.companion.expression
        lively: !window.companion.quietDesktop && window.companion.tracking && !window.companion.cursorStill
        wander: window.companion.ambientAllowed && !window.companion.glancing && !window.companion.tracking
        gaze: window.companion.glancing ? window.companion.glance : window.cursorGaze
        level: window.companion.level
        dancing: window.companion.dancing
        foldLeaves: window.companion.focusPhase === "focus" && window.companion.phase === "idle"
        character.hat: window.companion.outfit.hat
        character.glasses: window.companion.outfit.glasses
        character.scarf: window.companion.outfit.scarf
        character.umbrella: window.companion.outfit.umbrella
    }

    Emotes {
        x: puppet.x
        y: puppet.y
        width: puppet.width
        height: puppet.height
        puppet: puppet
    }

    // The body and sprout at rest; squash and hops stay close to it.
    Item {
        id: hitArea
        objectName: "companionHitArea"
        x: puppet.x + 28
        y: puppet.y + 20
        width: 144
        height: 164

        function local(point: point): point {
            return hitArea.mapToItem(puppet, point.x, point.y);
        }

        HoverHandler {
            id: hover
        }
        Timer {
            running: hover.hovered && window.companion.phase === "idle"
            interval: 1600
            onTriggered: {
                window.companion.react(Math.random() < 0.3 ? "love" : "content", 2500);
                window.puppet.emote("heart", 1);
                if (Math.random() < 0.3)
                    window.companion.line("petted");
            }
        }
        TapHandler {
            longPressThreshold: 0.35
            onTapped: eventPoint => {
                const point = hitArea.local(eventPoint.position);
                window.companion.poke(point.x, point.y);
            }
            onDoubleTapped: window.companion.compose()
            onLongPressed: window.holding = window.companion.listen("hold")
            onPressedChanged: if (!pressed && window.holding) {
                window.holding = false;
                window.companion.stopListening();
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: menu.open()
        }
        DragHandler {
            target: null
            onActiveChanged: active ? window.companion.startDrag(centroid.scenePressPosition) : window.companion.endDrag()
        }
        DropArea {
            anchors.fill: parent
            onEntered: {
                window.companion.react("curious", 4000);
                window.companion.line("curious");
            }
            onDropped: drop => {
                const files = drop.urls.map(url => String(url)).filter(url => url.startsWith("file:"));
                if (files.length)
                    window.companion.ask("", {
                        files
                    });
            }
        }
    }

    Rectangle {
        id: bubble
        readonly property bool interactive: visible && (more.visible || recordingControls.visible)
        readonly property real tail: Math.max(radius, Math.min(width - radius, puppet.x + puppet.width / 2 - x))
        visible: opacity > 0
        opacity: window.companion.phase === "listening" || window.companion.bubbleText || (window.companion.status && window.companion.phase === "thinking") ? 1 : 0
        width: Math.max(label.contentWidth, statusLine.visible ? statusLine.contentWidth : 0, more.visible ? more.implicitWidth : 0, recordingControls.visible ? recordingControls.implicitWidth : 0) + 28
        height: content.implicitHeight + 20
        x: window.cardX(width)
        y: puppet.y + 14 - height
        radius: 16
        color: "#fffdf6"
        border.color: "#e2d9c6"
        border.width: 1

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }
        Rectangle {
            width: 12
            height: 12
            x: bubble.tail - width / 2
            y: bubble.height - height / 2 - 1
            rotation: 45
            color: bubble.color
            border.color: bubble.border.color
            border.width: 1
            z: -1
        }
        Column {
            id: content
            x: 14
            y: 10
            spacing: 4
            Text {
                id: label
                width: 300
                visible: text !== ""
                text: window.companion.bubbleText
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                color: window.companion.bubbleQuote ? "#7a705c" : "#3a3326"
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.italic: window.companion.bubbleQuote
            }
            Text {
                id: statusLine
                width: 300
                visible: window.companion.phase === "listening" || (window.companion.status !== "" && window.companion.phase === "thinking")
                text: {
                    if (window.companion.phase !== "listening")
                        return window.companion.status;
                    if (!window.companion.recorderOpen)
                        return qsTr("Opening microphone…");
                    const seconds = window.companion.followUpSeconds;
                    return seconds > 0 ? qsTr("Listening for a follow-up · %1 s").arg(seconds) : qsTr("Microphone open");
                }
                color: "#8a8170"
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
            Row {
                id: recordingControls
                visible: window.companion.phase === "listening"
                spacing: 6
                ShellButton {
                    objectName: "companionStopCapture"
                    text: qsTr("Stop")
                    onClicked: window.companion.stopCapture()
                }
                ShellButton {
                    text: qsTr("Send now")
                    enabled: window.companion.recorderOpen
                    onClicked: window.companion.stopListening()
                }
            }
            Text {
                id: more
                visible: window.companion.phase !== "listening" && !!window.companion.details && !window.companion.showDetails && !window.companion.approval
                text: qsTr("More…")
                color: "#3f8f63"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.underline: moreHover.hovered
                HoverHandler {
                    id: moreHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: window.companion.showDetails = true
                }
            }
        }
    }

    Column {
        id: cards
        // Children's visibility includes this column's, so test the conditions.
        visible: !!window.companion.approval || (window.companion.showDetails && !!window.companion.details) || window.companion.composing
        width: 380
        x: window.cardX(width)
        y: (bubble.visible ? bubble.y : puppet.y + 14) - height - 10
        spacing: 8

        ApprovalCard {
            id: approval
            width: parent.width
            visible: !!window.companion.approval
            activity: window.companion.approval ?? ({})
            onDecided: approved => window.companion.decide(approved)
        }
        DetailsCard {
            id: details
            width: parent.width
            height: implicitHeight
            visible: window.companion.showDetails && !!window.companion.details
            text: window.companion.details
            canContinue: !!window.companion.lastReply && !window.companion.openingDrawer
            onClosed: window.companion.showDetails = false
            onContinueRequested: window.companion.continueInAssistant()
        }
        Composer {
            id: composer
            width: parent.width
            visible: window.companion.composing
            onSubmitted: text => window.companion.ask(text)
            onDismissed: window.companion.composing = false
            onVisibleChanged: if (visible)
                Qt.callLater(focusInput)
        }
    }

    Text {
        visible: window.companion.asleep
        x: puppet.x + 150
        y: puppet.y + 30
        text: "z z"
        color: "#6f8f80"
        font.family: Theme.fontFamily
        font.pixelSize: 16
        font.italic: true
    }

    Menu {
        id: menu
        objectName: "companionMenu"
        popupType: Popup.Item
        x: window.cardX(width)
        y: puppet.y + 20 - height
        width: 290
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: {
            window.menuContext = window.companion.context();
            window.companion.refreshModels();
        }
        delegate: ShellMenuItem {}
        background: Surface {
            color: Theme.background
            radius: Theme.controlRadius
        }

        ShellMenuItem {
            text: qsTr("Listen")
            onTriggered: window.companion.listen("auto", false, window.menuContext)
        }
        ShellMenuItem {
            text: qsTr("Microphone settings")
            enabled: !window.companion.openingDrawer
            onTriggered: window.companion.requestDrawer("microphone", {
                action: "open"
            })
        }
        ShellMenuItem {
            text: qsTr("Type a message…")
            onTriggered: window.companion.compose(window.menuContext)
        }
        ShellMenuItem {
            text: qsTr("Read selected text")
            onTriggered: window.companion.read()
        }
        ShellMenuItem {
            text: qsTr("What's on my screen?")
            enabled: window.companion.selectedChatModel?.vision === true
            onTriggered: window.companion.ask("", {
                screen: true
            })
        }
        ShellMenuItem {
            text: qsTr("Repeat last message")
            enabled: !!window.companion.lastSpoken
            onTriggered: window.companion.repeat()
        }
        ShellMenuItem {
            text: qsTr("Show last answer")
            enabled: !!window.companion.details
            onTriggered: window.companion.showDetails = true
        }
        ShellMenuItem {
            text: qsTr("Continue in Assistant")
            enabled: !!window.companion.lastReply && !window.companion.openingDrawer
            onTriggered: window.companion.continueInAssistant()
        }
        Menu {
            id: behaviorMenu
            title: qsTr("Behaviour")
            popupType: Popup.Item
            width: 280
            padding: 6
            background: Surface {
                color: Theme.background
                radius: Theme.controlRadius
            }
            Instantiator {
                model: Object.keys(window.companion.behaviors)
                delegate: ShellMenuItem {
                    required property string modelData
                    text: (window.companion.behaviors[modelData]?.name ?? modelData) + " · " + (window.companion.behaviors[modelData]?.description ?? "")
                    marked: window.companion.behaviorId === modelData
                    onTriggered: window.companion.setBehavior(modelData)
                }
                onObjectAdded: (index, object) => behaviorMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => behaviorMenu.removeItem(object)
            }
        }
        Menu {
            id: chatModelMenu
            title: qsTr("Chat model")
            enabled: window.companion.chatModels.length > 1
            popupType: Popup.Item
            cascade: false
            width: menu.width
            padding: 6
            background: Surface {
                color: Theme.background
                radius: Theme.controlRadius
            }
            Instantiator {
                model: window.companion.chatModels
                delegate: ShellMenuItem {
                    required property var modelData
                    text: modelData.id
                    marked: modelData.id === window.companion.selectedChatModel?.id
                    onTriggered: window.companion.selectModel(modelData.id)
                }
                onObjectAdded: (index, object) => chatModelMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => chatModelMenu.removeItem(object)
            }
        }
        Menu {
            id: timerMenu
            title: qsTr("Timers")
            property double now: Date.now()
            popupType: Popup.Item
            width: 240
            padding: 6
            onAboutToShow: now = Date.now()
            Timer {
                running: timerMenu.visible
                interval: 1000
                repeat: true
                onTriggered: timerMenu.now = Date.now()
            }
            background: Surface {
                color: Theme.background
                radius: Theme.controlRadius
            }
            ShellMenuItem {
                text: qsTr("Open clock and timers")
                onTriggered: window.companion.requestDrawer("desktop", {
                    tool: "timer",
                    args: {
                        action: "open"
                    },
                    context: window.menuContext
                })
            }
            ShellMenuItem {
                text: qsTr("Start 25 minutes of focus")
                enabled: !window.companion.focusPhase
                onTriggered: window.companion.requestDrawer("desktop", {
                    tool: "timer",
                    args: {
                        action: "focus"
                    },
                    context: window.menuContext
                })
            }
            Instantiator {
                model: window.companion.timers
                delegate: ShellMenuItem {
                    required property var modelData
                    readonly property int remaining: Math.max(0, Math.ceil((modelData.deadline - timerMenu.now) / 1000))
                    text: qsTr("%1 · %2:%3").arg(modelData.kind === "pomodoro" ? (modelData.phase === "break" ? qsTr("Stop break") : qsTr("Stop focus")) : qsTr("Stop %1").arg(modelData.message || qsTr("timer"))).arg(Math.floor(remaining / 60)).arg(String(remaining % 60).padStart(2, "0"))
                    onTriggered: window.companion.requestDrawer("desktop", {
                        tool: "timer",
                        args: {
                            action: "stop",
                            id: modelData.id
                        }
                    })
                }
                onObjectAdded: (index, object) => timerMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => timerMenu.removeItem(object)
            }
        }
        ShellMenuItem {
            text: qsTr("New conversation")
            enabled: window.companion.history.length > 0
            onTriggered: window.companion.newConversation()
        }
        ShellMenuItem {
            text: qsTr("Open memory")
            onTriggered: window.companion.openMemory()
        }
        ShellMenuItem {
            text: qsTr("Goodbye")
            onTriggered: window.companion.goodbye()
        }
    }
}
