import "../../ui" as Desktop
import QtQuick

MovieButton {
    id: root

    property string hint: text
    property color iconColor: MovieStyle.muted
    property bool toolbar: false
    property bool favoriteControl: false
    property bool favorite: false
    property string favoriteSubject: ""

    iconName: favoriteControl ? (favorite ? "star-filled" : "star") : ""
    text: favoriteControl ? (favorite ? qsTr("Remove favorite") : qsTr("Add favorite")) + (favoriteSubject ? " " + favoriteSubject : "") : ""
    highlighted: favoriteControl ? favorite : checked
    implicitWidth: toolbar ? 42 : MovieStyle.controlHeight
    implicitHeight: MovieStyle.controlHeight
    padding: 9
    Accessible.name: text

    Desktop.PassiveToolTip {
        target: root
        text: root.hint
        maximumLineCount: 20
    }

    contentItem: MovieIcon {
        name: root.iconName
        color: root.hovered || root.highlighted || root.visualFocus ? MovieStyle.text : root.iconColor
    }
}
