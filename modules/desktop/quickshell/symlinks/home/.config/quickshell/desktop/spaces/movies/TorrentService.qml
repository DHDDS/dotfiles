import QtQuick
import Quickshell
import "../../ui"

Worker {
    id: root
    backend: "torrent_backend.py"
    serviceName: "qBittorrent"
    startOnDemand: true
    timeout: 600000
    property bool monitorJobs: false
    property bool foreground: true
    property string monitorKind: ""
    property var jobs: []
    property bool jobsLoaded: false
    property var deliverNotification: (title, body) => Quickshell.execDetached(["notify-send", "--app-name=" + (root.monitorKind === "game" ? "Games" : root.monitorKind === "tv" ? "TV Series" : root.monitorKind === "book" ? "Books" : "Movies"), "--", title, String(body).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")])
    property bool jobsLoading: false
    property string jobsError: ""
    property int pendingDownloads: 0
    property int pendingChanges: 0
    readonly property bool activeWork: pendingDownloads > 0 || pendingChanges > 0 || jobs.some(job => job.active)
    signal libraryChanged

    function change(op, args, callback) {
        pendingChanges++;
        request(op, args, (result, failure) => {
            try {
                callback(result, failure);
            } finally {
                pendingChanges--;
            }
        });
    }

    function refreshJobs() {
        if (jobsLoading)
            return;
        jobsLoading = true;
        request("jobs", monitorKind ? {
            kind: monitorKind
        } : {}, (result, failure) => {
            jobsLoading = false;
            jobsError = failure || "";
            if (failure)
                return;
            if (jobsLoaded) {
                for (const job of result) {
                    const before = jobs.find(item => item.id === job.id);
                    if (before && before.status !== job.status && ["imported", "review"].includes(job.status))
                        deliverNotification(job.title || "Download", job.status === "imported" ? "Download complete." : job.message || "Review downloaded files.");
                }
            }
            jobsLoaded = true;
            const previous = jobs.filter(job => job.status === "imported").map(job => job.id);
            jobs = result;
            if (jobs.some(job => job.status === "imported" && !previous.includes(job.id)))
                libraryChanged();
        });
    }
    Timer {
        objectName: "torrentJobPoll"
        interval: root.activeWork ? 5000 : 30000
        repeat: true
        running: root.monitorJobs && !root.stopped && (root.foreground || root.activeWork)
        onTriggered: root.refreshJobs()
    }
    onForegroundChanged: if (foreground && monitorJobs && !stopped)
        refreshJobs()
    Component.onCompleted: if (monitorJobs && foreground)
        refreshJobs()
}
