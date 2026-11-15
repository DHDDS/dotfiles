import QtQuick
import "../movies"

ArtworkCard {
    id: root
    required property var video
    property bool selected: false
    width: 300
    height: 250
    highlighted: selected
    imageSource: visible ? video.thumbnail || "" : ""
    imageAspectRatio: 16 / 9
    imageWidth: 640
    showFallback: false
    text: video.title || ""
    subtitle: video.creator || ""
    titleBold: true
    titleHeight: 42
    titlePixelSize: MovieStyle.fontSize
    subtitlePixelSize: MovieStyle.fontSize
    leadingBadge: video.localPath ? video.audio ? "AUDIO" : "OFFLINE" : ["private", "needs_auth"].includes(video.availability) ? "SIGN-IN" : ""
    trailingBadge: video.live ? "LIVE" : video.duration > 0 ? Math.floor(video.duration / 60) + ":" + String(video.duration % 60).padStart(2, "0") : "YouTube"
    Accessible.name: (video.title || "") + ", " + (video.creator || "")
}
