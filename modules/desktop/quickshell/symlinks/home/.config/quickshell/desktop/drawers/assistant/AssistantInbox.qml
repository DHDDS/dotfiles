import Quickshell
import Quickshell.Io
import "../audio"

Scope {
    id: parentInbox
    property var audio: AudioService
    property var openDrawer: null
    property bool publishPresence: false
    property DesktopActions desktopActions: DesktopActions {
        openDrawer: parentInbox.openDrawer
        publishPresence: parentInbox.publishPresence
    }
    IpcHandler {
        target: "assistant"
        function desktop(payload: string): string {
            return parentInbox.desktop(payload);
        }
        function microphone(payload: string): string {
            return parentInbox.microphone(payload);
        }
        function continueFromPip(payload: string): string {
            return parentInbox.continueFromPip(payload);
        }
        function addFiles(payload: string): string {
            return parentInbox.addFiles(payload);
        }
    }

    function desktop(payload: string): string {
        try {
            const request = payload.length <= 8192 ? JSON.parse(payload) : null;
            if (request)
                return JSON.stringify(desktopActions.request(request.tool, request.args, request.context));
        } catch (error) {
            console.warn("Assistant desktop request:", error);
        }
        return JSON.stringify({
            error: qsTr("Invalid desktop request.")
        });
    }

    function microphone(payload: string): string {
        let request;
        try {
            request = payload.length <= 1024 ? JSON.parse(payload) : null;
        } catch (_) {
            request = null;
        }
        if (request?.action === "status")
            return JSON.stringify(audio.microphones());
        if (request?.action === "select" && typeof request.id === "string" && /^[0-9]{1,20}$/.test(request.id))
            return JSON.stringify(audio.selectMicrophone(request.id));
        if (request?.action === "open")
            return JSON.stringify(openDrawer?.("microphone", "") ? {
                opened: true
            } : {
                error: qsTr("The microphone drawer is unavailable.")
            });
        return JSON.stringify({
            error: qsTr("Invalid microphone request.")
        });
    }

    function continueFromPip(payload: string): string {
        let reply;
        try {
            reply = payload.length <= 32 * 1024 ? JSON.parse(payload) : null;
        } catch (_) {
            reply = null;
        }
        if (!reply || typeof reply.id !== "string" || !/^[0-9a-f]{32}$/.test(reply.id) || typeof reply.question !== "string" || !reply.question.trim() || typeof reply.text !== "string" || typeof reply.model !== "string")
            return qsTr("Could not read Pip's answer.");
        if (typeof openDrawer !== "function")
            return qsTr("The Assistant drawer is unavailable.");
        const error = AssistantService.importCompanionReply(reply);
        if (error)
            return error;
        return openDrawer("assistant", typeof reply.output === "string" ? reply.output : "") ? "" : qsTr("The Assistant drawer is unavailable.");
    }

    function addFiles(payload: string): string {
        try {
            if (payload.length > 96 * 1024)
                return qsTr("These file paths are too long to add in one selection.");
            const urls = JSON.parse(payload).files;
            if (!Array.isArray(urls) || urls.length < 1 || urls.length > 6)
                return qsTr("Select between one and six files to add to Assistant.");
            if (!urls.every(url => typeof url === "string" && /^file:\/\/(?:localhost)?\//.test(url)))
                return qsTr("Only local files can be added to Assistant.");
            return AssistantService.attachUrls(urls, true) ? "" : AssistantService.attachmentError;
        } catch (_) {
            return qsTr("Could not read the selected files.");
        }
    }
}
