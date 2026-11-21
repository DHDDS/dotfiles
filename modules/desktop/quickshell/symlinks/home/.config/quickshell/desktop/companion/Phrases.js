.pragma library

// Short local lines for reactions that never need the language model.
// "%1" is the companion's name.
const lines = {
    greet: ["Hi! I'm %1.", "Hello! %1 is here.", "Hi there!"],
    belly: ["Hee hee!", "That tickles!", "Boop!"],
    face: ["Eep, my eyes!", "Hey, that's my face!"],
    head: ["Bonk!", "Ow, my sprout!"],
    side: ["Whoa!", "Wobble wobble!"],
    dizzy: ["Whoa, I'm dizzy!", "Spinny spin!", "Okay, okay, I'm awake!"],
    petted: ["Aww, thank you!", "That's nice."],
    dropped: ["Wheee!", "Nice spot!", "I like it here."],
    curious: ["Ooh, what's that?", "Is that for me?"],
    holdLonger: ["Hold me while you talk!"],
    nothing: ["Hmm, I didn't hear anything.", "Was that a whisper? Try again!"],
    selection: ["Highlight some text first!"],
    approval: ["Can I do this?"],
    bye: ["Bye bye!", "See you soon!"],
    playful: ["I'm here when you need me."],
    friend: ["Let's play!"],
    assistant: ["Ready to help."],
    quiet: ["I'll keep quiet."],
    offline: ["My thinking cap is off right now. Let's try later!"],
    model: ["I couldn't get an answer from the model."],
    microphone: ["I can't hear you. Is the microphone on?"],
    speech: ["I couldn't transcribe that. Try typing your message."],
    screen: ["I couldn't see the screen."],
    other: ["Oops, my leaves got tangled. Can you try again?"],
    interrupted: ["Okay!", "Got it."]
};

function pick(kind, name) {
    const choices = lines[kind] ?? lines.other;
    return choices[Math.floor(Math.random() * choices.length)].replace("%1", name);
}
