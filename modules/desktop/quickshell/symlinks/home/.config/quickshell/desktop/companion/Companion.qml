pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../ui"
import "../ui/DesktopContext.js" as DesktopContext
import "Phrases.js" as Phrases

// The companion app: preferences and behaviour, visibility, autonomous
// behaviour, desktop reactions, conversation and the desktop actions its
// tools ask for. The window and puppet exist only while shown.
Scope {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/desktop"
    readonly property string memoryPath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/companion/memory.md"
    readonly property var settings: parse(settingsFile.text())
    readonly property var behaviors: parse(behaviorsFile.text())
    readonly property string name: typeof settings.name === "string" && settings.name.trim() ? settings.name.trim().slice(0, 24) : "Pip"
    property string behaviorId: ""
    readonly property var behavior: behaviors[behaviorId] ?? behaviors.playful ?? ({})
    readonly property var position: settings.position && typeof settings.position === "object" ? settings.position : ({})

    // The pinned output, or the one in use: it walks over after a few seconds.
    readonly property ShellScreen pinned: Quickshell.screens.find(output => output.name === settings.output) ?? null
    readonly property ShellScreen focusedScreen: Quickshell.screens.find(output => output.name === Hyprland.focusedMonitor?.name) ?? null
    property ShellScreen screen: null
    readonly property HyprlandMonitor monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property bool fullscreen: !!monitor?.activeWorkspace?.hasFullscreen
    // Sharing that lasted beyond a moment; `casting` is Hyprland's raw state.
    property bool screencast: false
    property bool casting: false
    readonly property bool shown: !!screen && !fullscreen && !screencast
    readonly property var window: loader.item

    // Conversation: idle, listening, thinking or speaking.
    property string phase: "idle"
    property var history: []
    property string bubbleText: ""
    property bool bubbleQuote: false
    property string status: ""
    property string details: ""
    property var lastReply: null
    readonly property bool openingDrawer: drawerRequest.running
    property bool showDetails: false
    property var approval: null
    property bool composing: false
    property bool handsFree: false
    property int followUps: 0
    property bool recorderOpen: false
    property int followUpSeconds: 0
    property var composerContext: null
    property var turnContext: null
    property bool answered: false
    property bool quitAfterReply: false
    property real micLevel: 0
    property var audioCapabilities: ({})
    property var chatModels: []
    property string defaultModel: ""
    readonly property var selectedChatModel: chatModels.find(row => row.id === settings.model) ?? chatModels.find(row => row.id === defaultModel)
    // What the current request has said so far, and the last message said.
    property var spoken: []
    property string lastSpoken: ""
    readonly property bool asleep: sleepMonitor.isIdle && phase === "idle"
    readonly property bool calm: calmMonitor.isIdle && phase === "idle"

    // Expression: conversation phases first, then the latest reaction.
    property string mood: "neutral"
    readonly property string expression: phase === "listening" ? "listening" : phase === "thinking" ? "thinking" : mood

    // Global cursor from Hyprland, polled only while someone uses an input device.
    property point cursor: Qt.point(Number.NaN, Number.NaN)
    property double cursorMoved: 0
    property bool cursorStill: true
    property bool dragging: false
    property point grab: Qt.point(0, 0)
    property point dragMargins: Qt.point(0, 0)
    readonly property bool tracking: !!window && !asleep && (dragging || !inputMonitor.isIdle)

    // A short look somewhere else, e.g. toward a workspace change.
    property point glance: Qt.point(0, 0)
    property bool glancing: false
    property int workspace: -1
    property var pokes: []

    property bool dancing: false
    readonly property var presence: parse(presenceFile.text())
    readonly property var timers: Array.isArray(presence.timers) ? presence.timers : []
    readonly property string focusPhase: timers.find(row => row.kind === "pomodoro")?.phase ?? ""
    property string priorFocusPhase: ""
    readonly property bool quietDesktop: presence.quiet === true || presence.recording === true || casting
    readonly property bool ambientAllowed: behavior.playful === true && !quietDesktop && focusPhase !== "focus" && !!window && phase === "idle" && !asleep && !window.interactive
    property bool talkHeld: false

    // Outfits follow the season, time of day and local weather.
    property var weather: null
    readonly property var outfit: {
        const now = clock.date;
        const day = `${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
        const hour = now.getHours();
        const birthdays = Array.isArray(settings.birthdays) ? settings.birthdays : [];
        const current = weather ?? {};
        const feels = typeof current.feelsLike === "number" ? current.feelsLike : 15;
        const code = typeof current.code === "number" ? current.code : -1;
        let hat = "";
        if (day === "01-01" || birthdays.includes(day))
            hat = "party";
        else if (now.getMonth() === 11 && now.getDate() >= 20 && now.getDate() <= 26)
            hat = "santa";
        else if (hour >= 21 || hour < 6)
            hat = "nightcap";
        else if (feels < 5)
            hat = "beanie";
        return {
            hat,
            glasses: !!current.isDay && code >= 0 && code <= 1 && feels >= 16 && hour >= 9 && hour < 18,
            umbrella: (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95,
            scarf: feels < 8
        };
    }
    readonly property bool playing: Mpris.players.values.some(row => row.isPlaying)
    readonly property real level: phase === "listening" ? micLevel : dancing ? Math.min(1, peaks.peak) : 0

    // A file next to this one, independent of which entry point loaded it.
    function local(path: string): string {
        return decodeURIComponent(Qt.resolvedUrl(path).toString().replace(/^file:\/\//, ""));
    }

    function parse(text: string): var {
        try {
            const value = JSON.parse(text || "{}");
            return value && typeof value === "object" && !Array.isArray(value) ? value : {};
        } catch (_) {
            return {};
        }
    }

    function save(changes: var): void {
        settingsFile.setText(JSON.stringify(Object.assign({}, settings, changes), null, 2) + "\n");
    }

    function react(expression: string, duration: int): void {
        mood = expression;
        moodReset.interval = duration;
        moodReset.restart();
    }

    function look(x: real, y: real, duration: int): void {
        glance = Qt.point(x, y);
        glancing = true;
        glanceReset.interval = duration;
        glanceReset.restart();
    }

    function show(text: string, seconds: real): void {
        bubbleText = text;
        bubbleQuote = false;
        bubbleReset.interval = Math.max(1500, seconds * 1000 + 2200);
        bubbleReset.restart();
    }

    // Local lines: bubble plus silent mouthing, never during a conversation.
    function line(kind: string): void {
        if (!window || phase !== "idle")
            return;
        const text = Phrases.pick(kind, name);
        show(text, 0.8 + text.length / 13);
        window.puppet.babble(text);
    }

    function context(): var {
        return DesktopContext.capture(Hyprland);
    }

    function send(payload: var): void {
        followUp.stop();
        if (payload.op !== "turn")
            handsFree = false;
        spoken = [];
        helper.request = payload;
        helper.accepting = false;
        helper.controls = [];
        if (helper.running) {
            helper.queued = true;
            helper.running = false;
        } else
            helper.running = true;
    }

    function write(value: var): void {
        if (!helper.request)
            return;
        const line = (typeof value === "string" ? value : JSON.stringify(value)) + "\n";
        if (helper.accepting)
            helper.write(line);
        else
            helper.controls.push(line);
    }

    function cancel(): void {
        followUp.stop();
        holdTimer.stop();
        talkHeld = false;
        helper.queued = false;
        helper.request = null;
        helper.accepting = false;
        helper.controls = [];
        if (helper.running)
            helper.running = false;
        phase = "idle";
        status = "";
        approval = null;
        handsFree = false;
        recorderOpen = false;
        followUpSeconds = 0;
        window?.puppet.stopSpeaking();
    }

    function say(text: string): bool {
        if (!window || !text.trim())
            return false;
        phase = "thinking";
        send({
            op: "say",
            text,
            start: true,
            voice: behavior.voice !== false
        });
        return true;
    }

    // Say the last message again; text-only behaviours show it instead.
    function repeat(): void {
        if (window && lastSpoken)
            say(lastSpoken);
    }

    function read(): void {
        if (!window)
            return;
        phase = "thinking";
        send({
            op: "read"
        });
    }

    function ask(text: string, options = ({})): bool {
        if (!window || (!text.trim() && !options.listen && !options.screen && !options.files))
            return false;
        approval = null;
        showDetails = false;
        details = "";
        status = "";
        answered = false;
        handsFree = options.listen === "auto";
        followUps = options.followUp === true ? followUps + 1 : 0;
        turnContext = options.context ?? (options.followUp ? turnContext : composing ? composerContext : null) ?? context();
        composing = false;
        micLevel = 0;
        recorderOpen = false;
        followUpSeconds = 0;
        if (options.listen) {
            bubbleText = "";
            bubbleQuote = false;
        }
        phase = options.listen ? "listening" : "thinking";
        if (!options.listen)
            show("…", 60);
        send(Object.assign({
            op: "turn",
            text,
            behavior: behaviorId,
            history: history.slice(-12),
            context: turnContext
        }, options));
        return true;
    }

    function listen(mode: string, followUp = false, origin = null): bool {
        if (!window || phase === "listening")
            return false;
        return ask("", {
            listen: mode,
            followUp,
            context: origin ?? (followUp ? turnContext : composing ? composerContext : null) ?? context()
        });
    }

    function stopListening(): void {
        if (phase === "listening") {
            write("stop");
            phase = "thinking";
        }
    }

    function stopCapture(): void {
        if (phase !== "listening")
            return;
        cancel();
        bubbleText = "";
    }

    function compose(origin = null): void {
        if (window && phase !== "listening") {
            followUp.stop();
            if (!composing)
                composerContext = origin ?? context();
            composing = true;
        }
    }

    function pressTalk(): void {
        holdTimer.stop();
        talkHeld = false;
        if (phase === "listening") {
            stopListening();
            return;
        }
        if (!window)
            return;
        if (phase !== "idle")
            cancel();
        if (listen("auto"))
            holdTimer.restart();
    }

    function releaseTalk(): void {
        holdTimer.stop();
        if (talkHeld) {
            talkHeld = false;
            stopListening();
        }
    }

    function refreshModels(): void {
        if (!modelReader.running) {
            modelReader.operation = "models";
            modelReader.running = true;
        }
    }

    function selectModel(id: string): void {
        if (chatModels.some(row => row.id === id))
            save({
                model: id
            });
    }

    function decide(approved: bool): void {
        if (!approval)
            return;
        write({
            type: "approval",
            id: approval.id,
            approved
        });
        approval = null;
        mood = "neutral";
        show("…", 60);
    }

    function setBehavior(id: string): bool {
        if (!behaviors[id])
            return false;
        if (id !== behaviorId) {
            behaviorId = id;
            save({
                behavior: id
            });
            if (!behavior.playful)
                dancing = false;
        }
        return true;
    }

    function newConversation(): void {
        followUp.stop();
        handsFree = false;
        history = [];
        lastReply = null;
        details = "";
        showDetails = false;
    }

    function requestDrawer(method: string, payload: var): void {
        if (openingDrawer)
            return;
        drawerRequest.method = method;
        drawerRequest.exec(["qs", "ipc", "--path", Quickshell.shellPath("shell.qml"), "call", "assistant", method, JSON.stringify(payload)]);
    }

    function continueInAssistant(): void {
        if (!lastReply || openingDrawer)
            return;
        followUp.stop();
        if (phase === "listening" && followUps > 0)
            cancel();
        const payload = Object.assign({
            output: screen?.name ?? ""
        }, lastReply);
        if (JSON.stringify(payload).length > 32 * 1024) {
            show(qsTr("This answer is too long to send to Assistant."), 4);
            return;
        }
        requestDrawer("continueFromPip", payload);
    }

    function goodbye(): void {
        cancel();
        window?.puppet.play("wave");
        react("happy", 3000);
        line("bye");
        quitTimer.restart();
    }

    function openMemory(): void {
        Apps.launch(["sh", "-c", 'mkdir -p "$(dirname "$1")" && { [ -e "$1" ] || printf "# Companion memory\\n\\nOne fact per line; edit or delete freely.\\n\\n" > "$1"; } && exec xdg-open "$1"', "sh", memoryPath]);
    }

    function poke(x: real, y: real): void {
        if (!window)
            return;
        followUp.stop();
        if (phase === "speaking" || phase === "thinking") {
            cancel();
            line("interrupted");
            return;
        }
        if (phase === "listening")
            return;
        const zone = window.puppet.poke(x, y);
        const now = Date.now();
        pokes = pokes.filter(time => now - time < 2500).concat([now]);
        if (pokes.length >= 5) {
            pokes = [];
            react("dizzy", 2200);
            window.puppet.play("wiggle");
            line("dizzy");
            return;
        }
        react(zone === "face" ? "squeeze" : zone === "head" ? "surprised" : "happy", zone === "face" ? 700 : 1200);
        if (pokes.length === 1 && Math.random() < 0.5)
            line(zone);
        if (zone === "belly" && Math.random() < 0.3)
            window.puppet.emote("heart", 2);
    }

    function startDrag(press: point): void {
        if (!window)
            return;
        stopListening();
        grab = press;
        dragMargins = Qt.point(window.marginRight, window.marginBottom);
        dragging = true;
        window.puppet.held = true;
        react("surprised", 600000);
    }

    function endDrag(): void {
        if (!dragging)
            return;
        dragging = false;
        window.puppet.held = false;
        react("happy", 1200);
        save({
            position: {
                right: Math.round(dragMargins.x),
                bottom: Math.round(dragMargins.y)
            }
        });
        line("dropped");
    }

    function cursorReply(data: string): void {
        let value;
        try {
            value = JSON.parse(data);
        } catch (_) {
            return;
        }
        if (typeof value?.x !== "number" || typeof value?.y !== "number")
            return;
        const now = Date.now();
        if (value.x !== cursor.x || value.y !== cursor.y) {
            cursor = Qt.point(value.x, value.y);
            cursorMoved = now;
        }
        cursorStill = now - cursorMoved > 1500;
        if (dragging && window) {
            const output = window.screen;
            const left = cursor.x - grab.x - output.x;
            const top = cursor.y - grab.y - output.y;
            dragMargins = Qt.point(window.clampRight(output.width - left - window.width, false), window.clampBottom(output.height - top - window.height));
        }
    }

    // Desktop actions the helper's tools request; each returns a result object.
    function intent(name: string, args: var): var {
        if (name === "media_control")
            return media(String(args.action ?? "status"));
        if (name === "set_behavior")
            return setBehavior(String(args.behavior ?? "")) ? {
                behavior: behaviorId
            } : {
                error: "Unknown behaviour."
            };
        if (name === "goodbye") {
            quitAfterReply = true;
            return {
                closing: true
            };
        }
        return {
            error: "Unknown desktop action."
        };
    }

    function media(action: string): var {
        const players = Mpris.players.values;
        const player = players.find(row => row.isPlaying) ?? players.find(row => row.canPlay) ?? players[0];
        if (!player)
            return {
                error: "No music or video player is open."
            };
        if (action === "play" && player.canPlay)
            player.play();
        else if (action === "pause" && player.canPause)
            player.pause();
        else if (action === "toggle" && player.canTogglePlaying)
            player.togglePlaying();
        else if (action === "next" && player.canGoNext)
            player.next();
        else if (action === "previous" && player.canGoPrevious)
            player.previous();
        return {
            player: player.identity,
            title: player.trackTitle,
            artist: player.trackArtist,
            playing: action === "play" ? true : action === "pause" ? false : player.isPlaying
        };
    }

    function handle(data: string): void {
        let event;
        try {
            event = JSON.parse(data);
        } catch (_) {
            return;
        }
        if (!helper.accepting)
            return;
        const type = event.type;
        if (type === "listening")
            recorderOpen = phase === "listening";
        else if (type === "listen_wait")
            followUpSeconds = event.seconds;
        else if (type === "level")
            micLevel = event.value;
        else if (type === "transcribing" || type === "thinking") {
            recorderOpen = false;
            followUpSeconds = 0;
            phase = "thinking";
            if (!bubbleQuote)
                show("…", 60);
        } else if (type === "heard") {
            bubbleText = "“" + event.text + "”";
            bubbleQuote = true;
            bubbleReset.stop();
        } else if (type === "tool") {
            const activity = event.activity ?? {};
            status = statusFor(activity.name);
            if (activity.destination && behavior.playful && !quietDesktop && screen && window) {
                const destination = Quickshell.screens.find(output => output.name === activity.destination);
                if (destination)
                    look(destination.x > screen.x ? 0.8 : -0.75, destination.y < screen.y ? 0.45 : 0.1, 1100);
            }
            if (activity.state === "pending_approval") {
                approval = activity;
                showDetails = false;
                bubbleQuote = false;
                bubbleText = Phrases.pick("approval", name);
                bubbleReset.stop();
                react("nervous", 600000);
            } else if (approval && approval.id === activity.id)
                approval = null;
        } else if (type === "action")
            status = statusFor(event.name);
        else if (type === "intent")
            write({
                type: "intent",
                id: event.id,
                result: intent(event.name, event.arguments ?? {})
            });
        else if (type === "speech" || type === "line") {
            phase = "speaking";
            spoken = spoken.concat([event.text]);
            status = "";
            react("content", Math.max(1500, event.duration * 1000 + 800));
            show(event.text, event.duration);
            if (type === "speech")
                window?.puppet.speak(event.envelope, event.fps, event.round);
            else
                window?.puppet.babble(event.text);
        } else if (type === "reply") {
            answered = true;
            if (event.id && (event.text || event.results?.length)) {
                lastReply = {
                    id: event.id,
                    model: event.model,
                    question: event.question,
                    text: event.text,
                    results: event.results
                };
            }
            history = history.concat([
                {
                    role: "user",
                    content: event.question
                },
                Object.assign({
                    role: "assistant",
                    content: event.text
                }, event.tool_context?.length ? {
                    tool_context: event.tool_context
                } : {})]).slice(-12);
            forget.restart();
        } else if (type === "details")
            details = event.text;
        else if (type === "nothing") {
            phase = "idle";
            bubbleQuote = false;
            if (event.reason === "short")
                line("holdLonger");
            else if (event.reason === "selection")
                line("selection");
            else if (!(handsFree && followUps > 0))
                line("nothing");
            handsFree = false;
        } else if (type === "error") {
            console.warn("companion:", event.kind, event.error);
            phase = "idle";
            handsFree = false;
            approval = null;
            bubbleQuote = false;
            react("sad", 2500);
            line(event.kind);
        } else if (type === "notice")
            console.warn("companion:", event.error);
        else if (type === "done")
            finish();
    }

    function finish(): void {
        recorderOpen = false;
        followUpSeconds = 0;
        if (spoken.length)
            lastSpoken = spoken.join(" ");
        if (phase !== "idle")
            phase = "idle";
        status = "";
        if (approval) {
            approval = null;
            mood = "neutral";
        }
        if (quitAfterReply) {
            goodbye();
            return;
        }
        // Hands-free questions get a short window for a follow-up.
        if (handsFree && answered && behavior.followUp && followUps < 1 && !quietDesktop && !window?.interactive) {
            followUp.restart();
            return;
        }
        handsFree = false;
    }

    function statusFor(tool: string): string {
        const labels = {
            timer: qsTr("Checking timers…"),
            window: qsTr("Checking desktop windows…"),
            open_app: qsTr("Opening the app…"),
            agenda: qsTr("Checking the calendar…"),
            lid_policy: qsTr("Checking lid settings…"),
            microphone: qsTr("Checking the microphone…"),
            web_search: qsTr("Searching the web…"),
            read_web_page: qsTr("Reading a page…"),
            search_lyrics: qsTr("Looking up lyrics…"),
            get_song_lyrics: qsTr("Looking up lyrics…"),
            search_spaces: qsTr("Looking in your library…"),
            space_filters: qsTr("Looking in your library…"),
            inspect_system: qsTr("Checking the system…"),
            read_file: qsTr("Reading a file…"),
            list_directory: qsTr("Looking through files…"),
            search_files: qsTr("Searching files…"),
            run_command: qsTr("Running a command…"),
            write_file: qsTr("Writing a file…"),
            play_space_result: qsTr("Starting it…"),
            weather: qsTr("Checking the weather…"),
            look_at_screen: qsTr("Looking at the screen…"),
            recent_notifications: qsTr("Checking notifications…"),
            read_selection: qsTr("Reading…"),
            remember: qsTr("Remembering…"),
            forget: qsTr("Forgetting…")
        };
        return labels[tool] ?? "";
    }

    onShownChanged: if (!shown) {
        cancel();
        dragging = false;
        dancing = false;
        bubbleText = "";
        composing = false;
    }
    onAsleepChanged: if (!asleep && ambientAllowed) {
        window.puppet.play("stretch");
        react("happy", 1500);
    }
    onBehaviorIdChanged: if (window && behaviorId) {
        window.puppet.play("hop");
        line(behaviorId);
    }
    onFocusedScreenChanged: {
        if (!pinned && settings.follow !== false && focusedScreen && focusedScreen !== screen)
            follow.restart();
        else
            follow.stop();
    }
    onPinnedChanged: if (pinned)
        screen = pinned
    onPlayingChanged: if (playing && ambientAllowed) {
        dancing = true;
        danceEnd.restart();
    } else if (!playing)
        dancing = false
    onAmbientAllowedChanged: if (!ambientAllowed)
        dancing = false
    onQuietDesktopChanged: if (quietDesktop) {
        followUp.stop();
        if (phase === "listening" && followUps > 0)
            stopCapture();
    }
    onFocusPhaseChanged: {
        if (priorFocusPhase === "focus" && focusPhase === "break" && ambientAllowed)
            window.puppet.play("stretch");
        priorFocusPhase = focusPhase;
    }

    Component.onCompleted: {
        const requested = Quickshell.env("COMPANION_BEHAVIOR");
        behaviorId = behaviors[requested] ? requested : behaviors[settings.behavior] ? settings.behavior : "playful";
        screen = pinned ?? focusedScreen ?? Quickshell.screens[0] ?? null;
        modelReader.running = true;
        greeting.restart();
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            if (!Quickshell.screens.includes(root.screen))
                root.screen = root.pinned ?? root.focusedScreen ?? Quickshell.screens[0] ?? null;
        }
    }

    FileView {
        id: presenceFile
        path: {
            const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
            return runtime.startsWith("/") ? runtime + "/desktop-companion-state.json" : "";
        }
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: settingsFile
        path: root.configDir + "/companion.json"
        blockLoading: true
        blockWrites: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onSaved: reload()
        onSaveFailed: Qt.callLater(reload)
    }
    FileView {
        id: behaviorsFile
        path: root.local("behaviors.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }

    LazyLoader {
        id: loader
        active: root.shown
        CompanionWindow {
            companion: root
        }
    }

    IdleMonitor {
        id: inputMonitor
        enabled: !!root.window
        timeout: 1.5
        respectInhibitors: false
    }
    IdleMonitor {
        id: calmMonitor
        enabled: !!root.window
        timeout: 30
        respectInhibitors: false
    }
    IdleMonitor {
        id: sleepMonitor
        enabled: !!root.window
        timeout: 180
    }

    Socket {
        id: cursorSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser {
            splitMarker: ""
            onRead: data => {
                // Close first: Hyprland closing the request socket logs a warning.
                cursorSocket.connected = false;
                root.cursorReply(data);
            }
        }
        onConnectedChanged: if (connected)
            write("j/cursorpos")
    }
    Timer {
        running: root.tracking
        repeat: true
        triggeredOnStart: true
        interval: root.dragging ? 16 : root.cursorStill ? 333 : 100
        onTriggered: if (!cursorSocket.connected && cursorSocket.path)
            cursorSocket.connected = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "screencast") {
                // Screenshots, including the companion's own look at the screen,
                // also report 1 then 0 within milliseconds; only sharing that
                // lasts hides it and stops what it is saying.
                root.casting = event.data.startsWith("1");
                if (root.casting)
                    castDelay.restart();
                else {
                    castDelay.stop();
                    root.screencast = false;
                }
                return;
            }
            if (!root.ambientAllowed)
                return;
            if (event.name === "workspacev2") {
                const id = parseInt(event.data);
                if (root.workspace >= 0 && id !== root.workspace)
                    root.look(id > root.workspace ? 1 : -1, 0.1, 900);
                root.workspace = id;
            } else if (event.name === "openwindow") {
                root.react("curious", 1400);
                root.look(-0.7, 0.5, 1200);
            }
        }
    }

    Process {
        id: helper
        property var request: null
        property bool queued: false
        property bool accepting: false
        property var controls: []
        command: ["timeout", "0", "setpriv", "--pdeathsig", "TERM", "--", "python3", "-u", root.local("companion.py")]
        stdinEnabled: true
        onStarted: if (request && !queued) {
            write(JSON.stringify(request) + "\n" + controls.join(""));
            controls = [];
            accepting = true;
        }
        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("companion helper:", data)
        }
        // Also runs for a helper that never started, which emits no `exited`.
        onRunningChanged: if (!running) {
            accepting = false;
            if (queued) {
                queued = false;
                running = true;
            } else {
                request = null;
                if (root.phase !== "idle")
                    root.finish();
            }
        }
    }
    Process {
        id: drawerRequest
        property string method: ""
        stdout: StdioCollector {
            id: drawerResponse
        }
        onExited: code => {
            let message = code ? qsTr("The desktop shell did not answer.") : drawerResponse.text.trim();
            if (!code && ["microphone", "desktop"].includes(method))
                message = root.parse(message).error || "";
            if (message)
                root.show(message, 4);
            else
                root.showDetails = false;
        }
    }

    Process {
        id: modelReader
        property string operation: "warm"
        command: ["timeout", "0", "setpriv", "--pdeathsig", "TERM", "--", "python3", "-u", root.local("companion.py")]
        stdinEnabled: true
        onStarted: write(JSON.stringify({
            op: operation
        }) + "\n")
        stdout: SplitParser {
            onRead: data => {
                const event = root.parse(data);
                if (event.type === "models") {
                    root.defaultModel = event.selected;
                    root.chatModels = event.models;
                } else if (event.type === "ready")
                    root.audioCapabilities = {
                        voice: event.voice,
                        transcriber: event.transcriber
                    };
                else if (event.type === "error" || event.type === "notice") {
                    if (modelReader.operation === "models")
                        root.chatModels = [];
                    console.warn("companion models:", event.error);
                }
            }
        }
    }

    Process {
        id: weatherReader
        command: ["python3", root.local("../drawers/weather/backend.py")]
        stdinEnabled: true
        onStarted: write('{"op": "island"}\n')
        stdout: StdioCollector {
            onStreamFinished: root.weather = root.parse(text).weather?.current ?? root.weather
        }
    }
    Timer {
        running: !!root.window
        repeat: true
        triggeredOnStart: true
        interval: 30 * 60 * 1000
        onTriggered: weatherReader.running = true
    }

    PwObjectTracker {
        objects: root.dancing && Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }
    PwNodePeakMonitor {
        id: peaks
        node: Pipewire.defaultAudioSink
        enabled: root.dancing
    }

    Timer {
        id: castDelay
        interval: 1500
        onTriggered: root.screencast = root.casting
    }
    Timer {
        id: moodReset
        onTriggered: root.mood = "neutral"
    }
    Timer {
        id: glanceReset
        onTriggered: root.glancing = false
    }
    Timer {
        id: bubbleReset
        onTriggered: if (root.phase !== "thinking" && !root.approval)
            root.bubbleText = ""
    }
    // Conversations are short-lived; a later question starts afresh.
    Timer {
        id: forget
        interval: 15 * 60 * 1000
        onTriggered: root.history = []
    }
    Timer {
        id: followUp
        interval: 300
        onTriggered: if (root.phase === "idle" && !root.quietDesktop && !root.window?.interactive)
            root.listen("auto", true)
    }
    Timer {
        id: greeting
        interval: 900
        onTriggered: if (root.window) {
            root.window.puppet.play("wave");
            root.react("happy", 1600);
            root.line("greet");
        }
    }
    Timer {
        id: quitTimer
        interval: 1800
        onTriggered: Qt.quit()
    }
    Timer {
        id: follow
        interval: 4000
        onTriggered: if (root.phase === "idle" && !root.dragging && root.focusedScreen) {
            root.screen = root.focusedScreen;
            arrived.restart();
        }
    }
    Timer {
        id: arrived
        interval: 200
        onTriggered: if (root.ambientAllowed) {
            root.window.puppet.play("hop");
            root.window.puppet.emote("sparkle", 3);
        }
    }
    Timer {
        id: danceEnd
        interval: 6500
        onTriggered: root.dancing = false
    }
    // Tap to talk hands-free; hold to talk until release.
    GlobalShortcut {
        appid: "companion"
        name: "talk"
        description: qsTr("Talk to the companion: tap for hands-free, hold to talk")
        onPressed: root.pressTalk()
        onReleased: root.releaseTalk()
    }
    Timer {
        id: holdTimer
        interval: 450
        onTriggered: if (root.phase === "listening") {
            root.talkHeld = true;
            root.handsFree = false;
            root.write("hold");
        }
    }
    GlobalShortcut {
        appid: "companion"
        name: "type"
        description: qsTr("Type a message to the companion")
        onPressed: root.compose()
    }

    IpcHandler {
        target: "companion"

        function say(text: string): string {
            return root.say(text) ? "" : qsTr("The companion is not shown.");
        }
        function ask(text: string): string {
            return root.ask(text) ? "" : qsTr("The companion is not shown.");
        }
        function listen(): void {
            root.listen("auto");
        }
        function type(): void {
            root.compose();
        }
        function behavior(id: string): string {
            return root.setBehavior(id) ? "" : qsTr("Unknown behaviour: %1").arg(id);
        }
        function repeat(): void {
            root.repeat();
        }
        function quit(): void {
            root.goodbye();
        }
        function status(): string {
            return JSON.stringify({
                behavior: root.behaviorId,
                phase: root.phase,
                shown: root.shown,
                asleep: root.asleep,
                screen: root.screen?.name ?? "",
                frameInterval: root.window?.puppet.frameInterval ?? 0,
                capabilities: Object.assign({}, root.audioCapabilities, {
                    model: root.selectedChatModel?.id ?? "",
                    vision: root.selectedChatModel?.vision ?? false
                })
            });
        }
    }
}
