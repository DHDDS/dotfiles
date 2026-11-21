import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Lets local clients such as the desktop companion open a Space search result
// the way launcher and assistant cards do. As with cards, provider commands and
// action lists never pass through; the Space resolves its own.
IpcHandler {
    target: "spaces"

    // `request` is JSON: {space, payload, play}. Returns "" or an error.
    function open(request: string): string {
        if (request.length > 96 * 1024)
            return qsTr("This Space request is too large.");
        let value;
        try {
            value = JSON.parse(request);
        } catch (_) {
            return qsTr("Invalid Space request.");
        }
        if (!value || typeof value.space !== "string" || !value.payload || typeof value.payload !== "object" || Array.isArray(value.payload))
            return qsTr("Invalid Space request.");
        // Qt's JavaScript engine lacks Object.fromEntries.
        function strip(item) {
            if (Array.isArray(item))
                return item.map(strip);
            if (!item || typeof item !== "object")
                return item;
            const result = {};
            for (const key of Object.keys(item))
                if (key !== "command" && key !== "actions")
                    result[key] = strip(item[key]);
            return result;
        }
        const output = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        const payload = Object.assign(strip(value.payload), {
            play: value.play === true
        });
        return SpaceState.open(value.space, output, payload) ? "" : qsTr("This Space is unavailable.");
    }
}
