pragma Singleton
import "../../ui" as Desktop
import "." as Local
import QtQuick
import QtQuick.Controls

QtObject {
    readonly property color background: "#09090b"
    readonly property color surface: "#141117"
    readonly property color raised: "#261b25"
    readonly property color border: "#49313e"
    readonly property color text: "#ffffff"
    readonly property color muted: "#c2bcc9"
    readonly property color accent: "#e50914"
    readonly property color accentText: "#ffffff"
    readonly property color accentSurface: "#40e50914"
    readonly property color danger: "#ff6571"
    readonly property int controlHeight: 38
    readonly property int controlRadius: 6
    readonly property int radius: 12
    readonly property int panelPadding: 20
    readonly property string fontFamily: Desktop.Theme.fontFamily
    readonly property int fontSize: Desktop.Theme.fontSize
    function primaryColor(pressed, hovered) {
        return pressed ? Qt.darker(accent, 1.2) : hovered ? Qt.lighter(accent, 1.1) : accent;
    }
    function filtersActive(values, defaults) {
        const baseline = defaults || {};
        return Object.keys(values || {}).some(key => JSON.stringify(values[key] ?? "") !== JSON.stringify(baseline[key] ?? ""));
    }

    component PanelSurface: Rectangle {
        color: Local.MovieStyle.background
        border.color: Local.MovieStyle.border
        radius: Local.MovieStyle.radius
    }

    component Panel: Popup {
        id: panel
        property bool fullArea: false
        property real maximumPanelWidth: 1100
        property real maximumPanelHeight: 700
        property real edgeInset: Local.MovieStyle.panelPadding

        width: parent ? (fullArea ? parent.width : Math.min(maximumPanelWidth, Math.max(0, parent.width - edgeInset * 2))) : 0
        height: parent ? (fullArea ? parent.height : Math.min(maximumPanelHeight, Math.max(0, parent.height - edgeInset * 2))) : 0
        x: parent && !fullArea ? (parent.width - width) / 2 : 0
        y: parent && !fullArea ? (parent.height - height) / 2 : 0
        padding: Local.MovieStyle.panelPadding
        popupType: Popup.Item
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: Local.MovieStyle.background
            border.color: Local.MovieStyle.border
            radius: Local.MovieStyle.radius
        }
    }

    component PanelTitle: Local.MovieText {
        font.bold: true
        font.pixelSize: Local.MovieStyle.fontSize
    }

    component PanelClose: Local.MovieIconButton {
        iconName: "x"
    }
}
