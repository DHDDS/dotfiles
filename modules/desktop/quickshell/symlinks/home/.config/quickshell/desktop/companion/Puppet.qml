import QtQuick

// Motion model for Character. It eases parameters toward the expression and
// gaze, blinks, breathes, plays gestures and emotes, dances, walks and mouths
// speech. Each frame costs the process about 1.5 ms of CPU, so one Timer draws
// ~30 fps only while something moves, 6 fps while breathing, single frames for
// blinks and glances when calm, and nothing once asleep or not running.
Item {
    id: root

    implicitWidth: character.implicitWidth
    implicitHeight: character.implicitHeight

    property bool running: true
    property bool asleep: false
    // Nobody has used the computer for a while: hold still between blinks.
    property bool calm: false
    property bool foldLeaves: false
    // The pointer moved recently, so gaze can change at any frame.
    property bool lively: false
    // Without pointer input, look around on its own instead of following gaze.
    property bool wander: false
    // Lifted by a drag: it hangs in the air until released.
    property bool held: false
    property string expression: "neutral"
    // Look target in -1..1, y up. Expressions such as "thinking" override it.
    property point gaze: Qt.point(0, 0)
    // Microphone level while listening and audio level while dancing, 0..1.
    property real level: 0
    property bool dancing: false
    property bool walking: false
    property int walkDirection: 1
    readonly property alias character: character
    readonly property bool speaking: speech.length > 0
    readonly property int frameInterval: frame.interval
    // Milliseconds; emotes animate from it so they cost frames only while alive.
    property double clock: Date.now()
    property var emotes: []

    signal stepped(real dt)

    property var speech: []
    property var speechRound: []
    property real speechRate: 30
    property double speechStart: 0

    readonly property var expressions: ({
            neutral: {},
            content: {
                eyeOpen: 0.92,
                mouthForm: 0.85,
                cheek: 0.35
            },
            happy: {
                eyeOpen: 0.5,
                eyeSmile: 1,
                browY: 0.4,
                mouthForm: 1,
                mouthOpen: 0.45,
                cheek: 1
            },
            excited: {
                eyeOpen: 1.12,
                eyeStyle: "sparkle",
                browY: 0.8,
                mouthForm: 1,
                mouthOpen: 0.6,
                cheek: 0.8
            },
            love: {
                eyeStyle: "heart",
                browY: 0.5,
                mouthForm: 1,
                mouthOpen: 0.25,
                cheek: 1
            },
            proud: {
                eyeStyle: "star",
                browY: 0.6,
                mouthForm: 1,
                mouthOpen: 0.35,
                cheek: 0.5,
                lean: 0.25
            },
            cheeky: {
                eyeOpen: 0.95,
                wink: 1,
                mouthForm: 0.7,
                mouthOpen: 0.15,
                tongue: 1,
                cheek: 0.5,
                tilt: 6
            },
            pout: {
                eyeOpen: 0.85,
                browY: 0.2,
                browAngle: 0.5,
                mouthForm: -0.3,
                mouthRound: 1,
                mouthOpen: 0.05,
                cheek: 0.9,
                tilt: -5
            },
            surprised: {
                eyeOpen: 1.15,
                browY: 1,
                mouthForm: 0,
                mouthOpen: 0.55,
                mouthRound: 0.7
            },
            curious: {
                eyeOpen: 1.06,
                browY: 0.5,
                browAngle: -0.2,
                mouthForm: 0.3,
                mouthOpen: 0.08,
                tilt: 8
            },
            listening: {
                eyeOpen: 1.08,
                browY: 0.6,
                mouthForm: 0.6,
                tilt: 6,
                lean: -0.15
            },
            thinking: {
                eyeOpen: 0.85,
                browY: 0.35,
                browAngle: -0.4,
                mouthForm: 0.05,
                tilt: -7,
                gaze: [0.55, 0.7]
            },
            nervous: {
                eyeOpen: 1,
                browY: 0.4,
                browAngle: -0.7,
                mouthForm: 0.25,
                sweat: 1
            },
            sleepy: {
                eyeOpen: 0.35,
                browY: -0.4,
                mouthForm: 0.2
            },
            asleep: {
                eyeOpen: 0,
                browY: 0.2,
                mouthForm: 0.15,
                mouthOpen: 0.06,
                tilt: -6,
                lean: -0.5,
                gaze: [0, -0.3]
            },
            sad: {
                eyeOpen: 0.8,
                browY: 0.2,
                browAngle: -1,
                mouthForm: -0.9,
                lean: -0.3
            },
            crying: {
                eyeOpen: 0.55,
                eyeSmile: 0.35,
                browY: 0.3,
                browAngle: -1,
                mouthForm: -1,
                mouthOpen: 0.35,
                tears: 1,
                lean: -0.3
            },
            dizzy: {
                eyeStyle: "spiral",
                browY: 0.6,
                browAngle: -0.6,
                mouthForm: -0.3,
                mouthOpen: 0.3,
                mouthRound: 0.5
            },
            squeeze: {
                eyeStyle: "squeeze",
                browY: -0.2,
                mouthForm: 0.6,
                mouthOpen: 0.2,
                cheek: 0.8
            }
        })
    readonly property var neutral: ({
            eyeOpen: 1,
            eyeSmile: 0,
            eyeStyle: "",
            wink: 0,
            browY: 0,
            browAngle: 0,
            mouthForm: 0.45,
            mouthOpen: 0,
            mouthRound: 0,
            tongue: 0,
            tears: 0,
            sweat: 0,
            cheek: 0,
            tilt: 0,
            lean: 0
        })

    // Simulation state; not meant for callers.
    property double last: Date.now()
    property real breathPhase: 0
    property real openness: 1
    property double nextBlink: Date.now() + 1500
    property bool doubleBlink: false
    property real squashVelocity: 0
    property real sideVelocity: 0
    property real tiltOffset: 0
    property real tiltVelocity: 0
    property real liftVelocity: 0
    property real sproutVelocity: 0
    property real previousAngleX: 0
    property var gesture: null
    property point wanderGaze: Qt.point(0, 0)
    property double nextWander: 0
    property real beatAverage: 0
    property double lastBeat: 0
    property double nextNote: 0
    // Asleep and settled: the frame timer stays off until something changes.
    property bool parked: false

    onAsleepChanged: kick()
    onFoldLeavesChanged: kick()
    onCalmChanged: kick()
    onExpressionChanged: kick()
    onGazeChanged: kick()
    onDancingChanged: kick()
    onWalkingChanged: kick()
    onHeldChanged: kick()

    // Gestures: "hop", "wave", "cheer", "wiggle", "shake", "nod", "stretch",
    // "yawn", "sneeze" and "wink".
    function play(name: string): void {
        if (name === "hop")
            liftVelocity = Math.max(liftVelocity, 330);
        else
            gesture = {
                name,
                start: Date.now(),
                sneezed: false
            };
        kick();
    }

    // A poke at a point in character coordinates; where it lands decides the
    // reaction. Returns the zone: "head", "side", "face" or "belly".
    function poke(x: real, y: real): string {
        const dx = x - width / 2;
        const dy = y - (height - 85);
        let zone = "belly";
        if (dy < -52)
            zone = "head";
        else if (Math.abs(dx) > 46)
            zone = "side";
        else if (dy < 12)
            zone = "face";
        if (zone === "head") {
            squashVelocity += 9;
            emote("bang", 1);
        } else if (zone === "side") {
            sideVelocity += 9;
            tiltVelocity += -Math.sign(dx) * 90;
        } else if (zone === "face") {
            squashVelocity += 5;
        } else {
            squashVelocity += 6;
            play("wiggle");
        }
        kick();
        return zone;
    }

    // Mouth an amplitude envelope (0..1 per frame at `rate` frames per second),
    // with an optional roundness track for "oo" sounds.
    function speak(envelope: var, rate: real, round: var): void {
        speech = envelope ?? [];
        speechRound = round ?? [];
        speechRate = rate > 0 ? rate : 30;
        speechStart = Date.now();
        kick();
    }

    // Silent speech: an envelope shaped by the text's vowels, about 13 letters/s.
    function babble(text: string): void {
        const envelope = [];
        const round = [];
        const vowels = "aeiouyаеиоуъюяэыёі";
        for (const letter of text.toLowerCase()) {
            let value = 0.32;
            let frames = 2;
            if (vowels.includes(letter))
                value = 0.65 + Math.random() * 0.35;
            else if (letter === " ")
                value = 0.08;
            else if (",.!?;:…".includes(letter)) {
                value = 0;
                frames = 5;
            }
            for (let index = 0; index < frames; index++) {
                envelope.push(value);
                round.push("ouоу".includes(letter) ? 0.8 : 0);
            }
        }
        speak(envelope, 26, round);
    }

    function stopSpeaking(): void {
        speech = [];
        speechRound = [];
    }

    // Floating symbols: "heart", "note", "z", "bang", "question", "sparkle", "drop", "bell".
    function emote(kind: string, count: int): void {
        const now = Date.now();
        const added = [];
        for (let index = 0; index < Math.max(1, count); index++)
            added.push({
                kind,
                born: now + index * 160,
                x: width / 2 + (Math.random() - 0.5) * 70,
                y: height - 160 + Math.random() * 20,
                vx: (Math.random() - 0.5) * 30,
                vy: -(28 + Math.random() * 18),
                life: kind === "z" ? 2.6 : 1.8,
                phase: Math.random() * 6
            });
        emotes = emotes.filter(item => (now - item.born) / 1000 < item.life).concat(added);
        kick();
    }

    function kick(): void {
        parked = false;
        frame.interval = 16;
        frame.restart();
    }

    // Ease a parameter; true while the remaining change is still visible
    // (about 0.15 px: 0.01 for -1..1 parameters, 0.08 for degrees).
    function approach(name: string, value: real, rate: real, visible = 0.01): bool {
        const delta = value - character[name];
        character[name] += delta * rate;
        return Math.abs(delta) > visible;
    }

    function step(): void {
        const now = Date.now();
        const dt = Math.min(0.1, Math.max(0.001, (now - last) / 1000));
        last = now;
        clock = now;
        const ease = seconds => 1 - Math.exp(-dt / seconds);
        const target = Object.assign({}, neutral, expressions[asleep ? "asleep" : expression] ?? {});
        let busy = lively || held || dancing || walking;

        if (!calm && !asleep) {
            breathPhase = (breathPhase + dt / 3.6) % 1;
            character.breath = 0.5 - 0.5 * Math.cos(2 * Math.PI * breathPhase);
        }

        // Gesture offsets, all decaying back to the expression.
        let tilt = target.tilt;
        let lean = target.lean;
        let shake = 0;
        let nod = 0;
        let armL = 0;
        let armR = 0;
        let stretch = 0;
        let eyeFactor = 1;
        let wink = target.wink;
        let mouthOpen = target.mouthOpen;
        let mouthRound = target.mouthRound;
        let eyeStyle = target.eyeStyle;
        if (gesture) {
            const t = (now - gesture.start) / 1000;
            const decay = Math.exp(-3 * t);
            const name = gesture.name;
            const durations = {
                wave: 1.6,
                cheer: 1.1,
                wiggle: 1.2,
                shake: 1,
                nod: 0.9,
                stretch: 1.5,
                yawn: 2.2,
                sneeze: 1.7,
                wink: 0.45
            };
            if (name === "wave")
                armR = Math.min(1, t * 6) * (0.85 + 0.2 * Math.sin(t * 13));
            else if (name === "cheer")
                armL = armR = Math.min(1, t * 6) * (0.9 + 0.12 * Math.sin(t * 16));
            else if (name === "wiggle")
                tilt += 9 * Math.sin(t * 17) * decay;
            else if (name === "shake")
                shake = 0.45 * Math.sin(t * 19) * decay;
            else if (name === "nod")
                nod = 0.35 * Math.sin(t * 14) * decay;
            else if (name === "stretch")
                armL = armR = stretch = Math.sin(Math.min(1, t / 1.5) * Math.PI);
            else if (name === "yawn") {
                const amount = Math.sin(Math.min(1, t / 2.2) * Math.PI);
                eyeFactor = 1 - 0.9 * amount;
                mouthOpen = Math.max(mouthOpen, 0.95 * amount);
                mouthRound = Math.max(mouthRound, 0.6 * amount);
                lean += 0.4 * amount;
                armL = armR = 0.55 * amount;
            } else if (name === "sneeze") {
                if (t < 1) {
                    eyeFactor = 1 - 0.75 * Math.min(1, t);
                    lean += 0.5 * Math.min(1, t);
                    mouthOpen = Math.max(mouthOpen, 0.3 * Math.min(1, t));
                } else {
                    if (!gesture.sneezed) {
                        gesture.sneezed = true;
                        squashVelocity += 8;
                        emote("drop", 3);
                    }
                    eyeStyle = "squeeze";
                    lean -= 0.6 * Math.exp(-6 * (t - 1));
                    mouthOpen = Math.max(mouthOpen, 0.5 * Math.exp(-4 * (t - 1)));
                }
            } else if (name === "wink")
                wink = Math.max(wink, Math.sin(Math.min(1, t / 0.45) * Math.PI));
            if (t >= (durations[name] ?? 0))
                gesture = null;
            busy = true;
        }
        if (held)
            armL = armR = Math.max(armL, 0.75);
        if (character.umbrella)
            armR = Math.max(armR, 0.9);

        // Dancing follows beats in the audio level, or a steady tempo without one.
        if (dancing) {
            beatAverage += (level - beatAverage) * ease(0.6);
            const beat = level > 0.12 ? level > beatAverage * 1.3 : (now - lastBeat) > 520;
            if (beat && now - lastBeat > 280) {
                lastBeat = now;
                squashVelocity += 3 + 4 * level;
                if (Math.random() < 0.25)
                    liftVelocity = Math.max(liftVelocity, 160);
            }
            const sway = Math.sin(now / 1000 * Math.PI * 1.9);
            tilt += 7 * sway;
            armL = Math.max(armL, 0.35 + 0.35 * Math.max(0, sway));
            armR = Math.max(armR, 0.35 + 0.35 * Math.max(0, -sway));
            if (now > nextNote) {
                nextNote = now + 900 + Math.random() * 700;
                emote("note", 1);
            }
        }

        // Gaze: follow the target, or wander when nobody is pointing nearby.
        let look = gaze;
        if (target.gaze)
            look = Qt.point(target.gaze[0], target.gaze[1]);
        else if (walking)
            look = Qt.point(0.8 * walkDirection, 0);
        else if (wander) {
            if (now >= nextWander) {
                const atViewer = Math.random() < 0.35;
                wanderGaze = atViewer ? Qt.point(0, 0) : Qt.point(Math.random() * 1.6 - 0.8, Math.random() * 0.9 - 0.3);
                nextWander = now + (calm ? 6000 + Math.random() * 8000 : 4000 + Math.random() * 5000);
            }
            look = wanderGaze;
        }
        if (walking) {
            character.step = (character.step + dt * 2.4) % 1;
            stepped(dt);
        }
        character.walking = walking;

        // Springs: a tilt pushed by side pokes, a squash and a side squeeze.
        tiltVelocity += (-160 * tiltOffset - 12 * tiltVelocity) * dt;
        tiltOffset += tiltVelocity * dt;
        busy = busy || Math.abs(tiltVelocity) > 0.5 || Math.abs(tiltOffset) > 0.08;
        sideVelocity += (-170 * character.squashSide - 11 * sideVelocity) * dt;
        character.squashSide += sideVelocity * dt;
        busy = busy || Math.abs(sideVelocity) > 0.05 || Math.abs(character.squashSide) > 0.01;

        const head = ease(0.2);
        busy = approach("angleX", look.x * 0.75 + shake, head) || busy;
        busy = approach("angleY", look.y * 0.6 + lean + nod, head) || busy;
        busy = approach("angleZ", tilt + tiltOffset + character.angleX * 4, ease(0.22), 0.08) || busy;
        busy = approach("eyeBallX", look.x, ease(0.06)) || busy;
        busy = approach("eyeBallY", look.y, ease(0.06)) || busy;
        busy = approach("armL", armL, ease(0.08)) || busy;
        busy = approach("armR", armR, ease(0.08)) || busy;
        const face = ease(0.09);
        for (const name of ["eyeSmile", "browY", "browAngle", "mouthForm", "cheek", "tongue", "tears", "sweat"])
            busy = approach(name, target[name], face) || busy;
        character.eyeStyle = eyeStyle;
        const moving = character.tears > 0.02 || character.sweat > 0.02 || eyeStyle === "heart" || eyeStyle === "spiral";
        if (moving) {
            character.spin = (character.spin + dt * 220) % 360;
            character.dropPhase = (character.dropPhase + dt * 0.8) % 1;
        }
        busy = busy || moving;

        // Blinks scale whatever openness the expression wants.
        const opennessDelta = target.eyeOpen - openness;
        openness += opennessDelta * face;
        busy = busy || Math.abs(opennessDelta) > 0.01;
        let blink = 1;
        if (!asleep && openness > 0.25 && now >= nextBlink) {
            const t = (now - nextBlink) / 170;
            if (t < 1) {
                blink = Math.abs(1 - 2 * t);
                busy = true;
            } else if (!doubleBlink && Math.random() < 0.2) {
                doubleBlink = true;
                nextBlink = now + 140;
            } else {
                doubleBlink = false;
                nextBlink = now + (calm ? 4000 + Math.random() * 5000 : 1800 + Math.random() * 4200);
            }
        }
        character.eyeOpenL = openness * blink * eyeFactor;
        character.eyeOpenR = openness * blink * eyeFactor * (1 - 0.92 * wink);

        // Speech drives the mouth; the expression's mouth shows between syllables.
        let round = mouthRound;
        if (speech.length) {
            const index = Math.floor((now - speechStart) / 1000 * speechRate);
            if (index >= speech.length)
                stopSpeaking();
            else {
                const at = Math.max(0, index);
                mouthOpen = Math.max(mouthOpen * 0.5, speech[at] * 0.9);
                round = speechRound[at] ?? 0;
                busy = true;
            }
        }
        busy = approach("mouthOpen", mouthOpen, ease(speaking ? 0.035 : 0.09)) || busy;
        busy = approach("mouthRound", round, ease(speaking ? 0.05 : 0.09)) || busy;

        // Squash spring, plus a stretch target while stretching.
        squashVelocity += (-170 * (character.squash + 0.35 * stretch) - 11 * squashVelocity) * dt;
        character.squash += squashVelocity * dt;
        busy = busy || Math.abs(squashVelocity) > 0.05 || Math.abs(character.squash + 0.35 * stretch) > 0.01;

        // Hops are ballistic; landing squashes the body. Being held lifts it.
        if (held) {
            liftVelocity = 0;
            approach("lift", 18, ease(0.08));
        } else if (character.lift > 0 || liftVelocity > 0) {
            liftVelocity -= 1500 * dt;
            character.lift = Math.max(0, character.lift + liftVelocity * dt);
            if (character.lift === 0) {
                squashVelocity += Math.min(9, -liftVelocity * 0.02);
                liftVelocity = 0;
            }
            busy = true;
        }

        // The sprout lags behind head turns and perks up to a voice.
        const headVelocity = (character.angleX - previousAngleX) / dt;
        previousAngleX = character.angleX;
        sproutVelocity += (-90 * character.sprout - 6 * sproutVelocity - headVelocity * 55) * dt;
        character.sprout += sproutVelocity * dt;
        busy = busy || Math.abs(sproutVelocity) > 0.4 || Math.abs(character.sprout) > 0.25;
        busy = approach("perk", expression === "listening" ? level : 0, ease(0.06)) || busy;
        busy = approach("leafFold", foldLeaves ? 1 : 0, ease(0.18)) || busy;

        if (emotes.length) {
            // Reassigning rebuilds the emote delegates, so only drop expired ones.
            const alive = emotes.filter(item => (now - item.born) / 1000 < item.life);
            if (alive.length !== emotes.length)
                emotes = alive;
            busy = busy || emotes.length > 0;
        }

        // Between movements, wake only for the next breath frame, blink or glance.
        if (!busy && asleep) {
            parked = true;
            return;
        }
        let wait = 33;
        if (!busy) {
            wait = Math.max(16, nextBlink - now);
            if (wander)
                wait = Math.min(wait, Math.max(16, nextWander - now));
            if (!calm)
                wait = Math.min(wait, 166);
        }
        if (frame.interval !== wait)
            frame.interval = wait;
    }

    Character {
        id: character
        anchors.fill: parent
    }

    Timer {
        id: frame
        interval: 33
        repeat: true
        running: root.running && !root.parked
        onRunningChanged: if (running)
            root.last = Date.now()
        onTriggered: root.step()
    }
}
